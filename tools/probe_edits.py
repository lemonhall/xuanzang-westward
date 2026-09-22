"""Probe whether OFOX exposes OpenAI-style reference-conditioned image editing.

If POST /v1/images/edits accepts a reference image, character identity can be
locked to that reference instead of drifting across independent generations.
This is a diagnostic probe: it makes exactly one paid request and never retries.

The API key is read from the environment or the machine registry and is never
printed. Output: request metadata, HTTP status, raw image bytes, alpha inspection.

Usage:
    python tools/probe_edits.py --reference <ref.png> --out <new-dir> --prompt "..."
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import winreg
from pathlib import Path

import requests
from PIL import Image

PROXY = {"http": "http://127.0.0.1:7897", "https": "http://127.0.0.1:7897"}
ENDPOINT = "https://api.ofox.ai/v1/images/edits"


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


def inspect(raw: bytes) -> dict:
    im = Image.open(io.BytesIO(raw))
    im.load()
    alpha = im.getchannel("A") if "A" in im.getbands() else None
    report = {
        "format": im.format,
        "mode": im.mode,
        "size": list(im.size),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }
    if alpha is not None:
        hist = alpha.histogram()
        report["transparent_pixels"] = hist[0]
        report["partial_alpha_pixels"] = sum(hist[1:255])
        report["opaque_pixels"] = hist[255]
        report["native_transparency"] = sum(hist[:255]) > 0
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--model", default="openai/gpt-image-2.5-sunburst")
    parser.add_argument("--input-fidelity", default=None)
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=False)
    ref = Path(args.reference)

    fields = {
        "model": args.model,
        "prompt": args.prompt,
        "size": "1024x1024",
        "n": "1",
        "background": "transparent",
    }
    if args.input_fidelity:
        fields["input_fidelity"] = args.input_fidelity

    (out / "request.json").write_text(
        json.dumps({"endpoint": ENDPOINT, "fields": fields, "reference": str(ref)}, indent=2),
        encoding="utf-8",
    )

    with ref.open("rb") as handle:
        files = {"image": (ref.name, handle.read(), "image/png")}

    session = requests.Session()
    session.proxies.update(PROXY)
    response = session.post(
        ENDPOINT,
        headers={"Authorization": "Bearer " + api_key()},
        data=fields,
        files=files,
        timeout=(30, 600),
    )
    print("HTTP:", response.status_code, flush=True)
    (out / "response-meta.json").write_text(
        json.dumps({"status": response.status_code, "content_type": response.headers.get("content-type")}, indent=2),
        encoding="utf-8",
    )
    if not response.ok:
        body = response.text[:4000].replace(api_key(), "[REDACTED]")
        (out / "error.txt").write_text(body, encoding="utf-8")
        print(body)
        return 1

    payload = response.json()
    items = payload.get("data", [])
    if not items:
        (out / "error.txt").write_text(json.dumps(payload)[:4000], encoding="utf-8")
        raise SystemExit("no image in response")

    item = items[0]
    if item.get("b64_json"):
        raw = base64.b64decode(item["b64_json"], validate=True)
    else:
        download = session.get(item["url"], timeout=(30, 120))
        download.raise_for_status()
        raw = download.content

    (out / "image-0.png").write_bytes(raw)
    report = inspect(raw)
    (out / "inspection-0.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
