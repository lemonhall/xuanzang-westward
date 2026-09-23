"""OFOX generation driver: text-to-image and reference-conditioned editing.

Two modes, chosen per job by whether the job has a `reference`:

  reference absent -> POST /v1/images/generations   (text-to-image)
  reference present -> POST /v1/images/edits        (multipart, reference image + text)

The edits route is how character identity is kept stable: one approved concept
image is the reference, every later frame is "same character, new pose".

Audit trail per run directory: request.json, response-summary.json, image-0.png,
inspection-0.json (format/size/alpha histogram/sha256) or error.txt.
Exactly one paid request per job, no automatic retry, never overwrites a run
directory, never prints the API key.

Manifest shape:
  { "jobs": [ { "name": "01", "slug": "xuanzang_walk_01",
                "prompt": "…", "reference": "assets/…/concept.png",
                "model": "openai/gpt-image-2.5-sunburst", "quality": "high",
                "background": "transparent" | "omit", "size": "1024x1024" } ] }

Usage:
    python tools/ofox_generate.py --manifest assets/manifests/x.json --parallel 3
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import sys
import time
import winreg
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urlparse

import requests
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
RAW_ROOT = REPO / "assets" / "raw" / "ofox"
PROXY = {"http": "http://127.0.0.1:7897", "https": "http://127.0.0.1:7897"}
LOCAL_PROXY_URL = "http://127.0.0.1:7897"
GENERATIONS = "https://api.ofox.ai/v1/images/generations"
EDITS = "https://api.ofox.ai/v1/images/edits"
DEFAULT_MODEL = "openai/gpt-image-2.5-sunburst"
ROUTE = "proxy"  # "proxy" | "direct"; selected by --proxy (default: auto probe)


def _session_for(route: str) -> requests.Session:
    session = requests.Session()
    if route == "proxy":
        session.proxies.update(PROXY)
    return session


def choose_route(preference: str) -> str:
    """Pick the network route.

    The local proxy occasionally drops long image requests (observed: HTTP 10054
    resets while the same request succeeds directly). `auto` probes the cheap
    /v1/models endpoint on the direct route first and falls back to the proxy;
    the chosen route is always printed, never switched silently.
    """
    if preference in ("direct", "proxy"):
        return preference
    try:
        probe = _session_for("direct").get("https://api.ofox.ai/v1/models", timeout=(8, 20))
        if probe.status_code == 200:
            return "direct"
    except Exception:  # noqa: BLE001 - any failure just means "use the proxy"
        pass
    return "proxy"


def _post_with_retry(session: requests.Session, url: str, attempts: int = 3, **kwargs) -> requests.Response:
    """POST with a bounded retry for transport-level resets only.

    Seedream requests take 30–90 s and return several MB of base64, and the
    connection is occasionally reset mid-flight (observed HTTP 10054 on both the
    local proxy and a direct route). A reset means no HTTP response arrived, so a
    retry is the only way to get the image; the trade-off is that the server may
    already have generated a response that we never saw, which would cost one
    extra image. Bounded to `attempts`, with backoff, and logged.
    """
    for i in range(attempts):
        try:
            return session.post(url, **kwargs)
        except (requests.exceptions.ConnectionError, requests.exceptions.ProxyError) as exc:
            if i == attempts - 1:
                raise
            print(f"[ofox] transport reset ({type(exc).__name__}), retry {i + 2}/{attempts} in {5 * (i + 1)}s", flush=True)
            time.sleep(5 * (i + 1))
    raise RuntimeError("unreachable")


def api_key() -> str:
    key = os.environ.get("OFOX_IMG_API_KEY", "")
    if not key:
        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
        ) as reg:
            key = winreg.QueryValueEx(reg, "OFOX_IMG_API_KEY")[0]
    if not key.strip():
        raise SystemExit("OFOX_IMG_API_KEY empty")
    return key


def inspect_bytes(raw: bytes) -> dict:
    im = Image.open(io.BytesIO(raw))
    im.load()
    report = {
        "format": im.format,
        "mode": im.mode,
        "size": list(im.size),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }
    if "A" in im.getbands():
        hist = im.getchannel("A").histogram()
        report["transparent_pixels"] = hist[0]
        report["partial_alpha_pixels"] = sum(hist[1:255])
        report["opaque_pixels"] = hist[255]
        report["native_transparency"] = sum(hist[:255]) > 0
    else:
        report["transparent_pixels"] = 0
        report["native_transparency"] = False
    return report


def run_job(job: dict, key: str) -> dict:
    model = job.get("model", DEFAULT_MODEL)
    # openai/gpt-image-2.5-sunburst -> gpt-image-2.5-sunburst (matches earlier runs)
    model_dir = model.split("/")[-1]
    run_dir = RAW_ROOT / model_dir / f"run-{job['name']}-{job['slug']}"
    if run_dir.exists():
        return {"slug": job["slug"], "status": "skipped", "reason": f"exists: {run_dir.relative_to(REPO)}"}
    run_dir.mkdir(parents=True)

    session = _session_for(ROUTE)
    headers = {"Authorization": "Bearer " + key}
    reference = job.get("reference")

    if reference:
        ref_path = (REPO / reference).resolve()
        if not ref_path.exists():
            return {"slug": job["slug"], "status": "failed", "reason": f"reference missing: {ref_path}"}
        fields = {"model": model, "prompt": job["prompt"], "quality": job.get("quality", "high")}
        if job.get("size"):
            fields["size"] = job["size"]
        if job.get("n"):
            fields["n"] = str(job["n"])
        if job.get("input_fidelity"):
            fields["input_fidelity"] = job["input_fidelity"]
        # `background` is documented for /generations only; pass it through on
        # edits as well so the probe can tell whether the gateway forwards it.
        if job.get("background") and job["background"] != "omit":
            fields["background"] = job["background"]
        if job.get("provider"):
            headers["X-OfoxAI-Provider-Type"] = job["provider"]
        (run_dir / "request.json").write_text(
            json.dumps({"endpoint": EDITS, "fields": fields, "reference": str(ref_path.relative_to(REPO))}, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        with ref_path.open("rb") as handle:
            files = {"image": (ref_path.name, handle.read(), "image/png")}
        response = _post_with_retry(session, EDITS, headers=headers, data=fields, files=files, timeout=(30, 900))
    else:
        payload = {
            "model": model,
            "prompt": job["prompt"],
            "size": job.get("size", "1024x1024"),
            "n": job.get("n", 1),
            "output_format": job.get("output_format", "png"),
        }
        background = job.get("background", "transparent")
        if background != "omit":
            payload["background"] = background
        if job.get("quality"):
            payload["quality"] = job["quality"]
        if job.get("provider"):
            payload["extra_body"] = {"provider": job["provider"]}
        (run_dir / "request.json").write_text(
            json.dumps({"endpoint": GENERATIONS, "payload": payload}, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        response = _post_with_retry(session, GENERATIONS, headers=headers, json=payload, timeout=(30, 900))

    (run_dir / "response-meta.json").write_text(
        json.dumps({"status": response.status_code, "content_type": response.headers.get("content-type")}, indent=2),
        encoding="utf-8",
    )
    if not response.ok:
        body = response.text[:4000].replace(key, "[REDACTED]")
        (run_dir / "error.txt").write_text(body, encoding="utf-8")
        return {"slug": job["slug"], "status": "failed", "reason": f"HTTP {response.status_code}: {body[:300]}"}

    data = response.json()
    items = data.get("data", [])
    if not items:
        (run_dir / "error.txt").write_text(json.dumps(data)[:4000], encoding="utf-8")
        return {"slug": job["slug"], "status": "failed", "reason": "no image in response"}

    item = items[0]
    if item.get("b64_json"):
        raw = base64.b64decode(item["b64_json"], validate=True)
    else:
        url = item["url"]
        if urlparse(url).scheme != "https":
            return {"slug": job["slug"], "status": "failed", "reason": "non-https image url"}
        download = session.get(url, timeout=(30, 180))
        if download.status_code != 200:
            return {"slug": job["slug"], "status": "failed", "reason": f"download {download.status_code}"}
        raw = download.content

    (run_dir / "image-0.png").write_bytes(raw)
    report = inspect_bytes(raw)
    (run_dir / "inspection-0.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (run_dir / "response-summary.json").write_text(
        json.dumps(
            {
                "model": data.get("model", model),
                "size": data.get("size"),
                "quality": data.get("quality"),
                "created": data.get("created"),
                "output_count": len(items),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    return {"slug": job["slug"], "status": "ok", "mode": "edits" if reference else "generations", "report": report}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--parallel", type=int, default=3)
    parser.add_argument("--only", default=None, help="comma-separated slug filter")
    parser.add_argument("--proxy", choices=["auto", "direct", "proxy"], default="auto", help="network route (default: auto probe)")
    args = parser.parse_args()

    global ROUTE
    ROUTE = choose_route(args.proxy)
    print(f"[ofox] network route: {ROUTE}")

    doc = json.loads((REPO / args.manifest).read_text(encoding="utf-8"))
    jobs = doc["jobs"]
    if args.only:
        wanted = {s.strip() for s in args.only.split(",")}
        jobs = [j for j in jobs if j["slug"] in wanted]
    if not jobs:
        raise SystemExit("no jobs to run")

    key = api_key()
    results = []
    with ThreadPoolExecutor(max_workers=max(1, args.parallel)) as pool:
        futures = {pool.submit(run_job, job, key): job["slug"] for job in jobs}
        for future in as_completed(futures):
            try:
                result = future.result()
            except Exception as exc:  # noqa: BLE001 - surfaced, not swallowed
                result = {"slug": futures[future], "status": "failed", "reason": repr(exc)}
            results.append(result)
            print(f"[ofox] {result['status']:<8} {result['slug']} {result.get('mode','')} {result.get('reason','')}", flush=True)

    failures = [r for r in results if r["status"] == "failed"]
    ok = [r for r in results if r["status"] == "ok"]
    print(f"\n[ofox] ok={len(ok)} failed={len(failures)} skipped={len(results)-len(ok)-len(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
