"""Measure identity drift between independently generated character frames.

Geometry alignment (asset_pipeline.py) is not identity alignment. This tool
answers the question "is this the same character?" with numbers instead of vibes:

  * silhouette IoU  - shape agreement after both are scaled to a common height
  * palette distance - L1 distance between subject-pixel colour histograms
  * mean colour drift - per-channel difference of the average subject colour
  * aspect drift     - width/height ratio difference of the alpha bounding box

Everything is computed on alpha-bounding-box crops, so it measures the character,
not the framing. Output is JSON plus a ranked table, so a regression batch can
gate on thresholds later.

Usage:
    python tools/consistency_check.py --reference <concept.png> --glob "assets/raw/**/run-*/image-0.png"
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
NORM_H = 256
ALPHA_THRESHOLD = 127


def load_subject(path: Path) -> Image.Image | None:
    im = Image.open(path)
    im.load()
    im = im.convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if not bbox:
        return None
    return im.crop(bbox)


def normalized(subject: Image.Image) -> Image.Image:
    scale = NORM_H / subject.height
    size = (max(1, round(subject.width * scale)), NORM_H)
    return subject.resize(size, Image.LANCZOS)


def silhouette(subject: Image.Image) -> set[tuple[int, int]]:
    im = normalized(subject)
    alpha = im.getchannel("A")
    w, h = im.size
    pixels = alpha.load()
    return {(x, y) for y in range(h) for x in range(w) if pixels[x, y] >= ALPHA_THRESHOLD}


def palette_vector(subject: Image.Image, bits: int = 4) -> list[float]:
    """Normalized histogram over quantized RGB, computed on subject pixels only."""
    bins = 1 << (bits * 3)
    hist = [0.0] * bins
    rgb = subject.convert("RGB")
    alpha = subject.getchannel("A")
    px, ap = rgb.load(), alpha.load()
    shift = 8 - bits
    total = 0
    for y in range(subject.height):
        for x in range(subject.width):
            if ap[x, y] < ALPHA_THRESHOLD:
                continue
            r, g, b = px[x, y]
            idx = ((r >> shift) << (bits * 2)) | ((g >> shift) << bits) | (b >> shift)
            hist[idx] += 1.0
            total += 1
    if total:
        hist = [v / total for v in hist]
    return hist


def palette_l1(a: list[float], b: list[float]) -> float:
    return sum(abs(x - y) for x, y in zip(a, b)) / 2.0


def mean_color(subject: Image.Image) -> tuple[float, float, float]:
    rgb = subject.convert("RGB")
    alpha = subject.getchannel("A")
    px, ap = rgb.load(), alpha.load()
    acc = [0.0, 0.0, 0.0]
    n = 0
    for y in range(subject.height):
        for x in range(subject.width):
            if ap[x, y] < ALPHA_THRESHOLD:
                continue
            r, g, b = px[x, y]
            acc[0] += r
            acc[1] += g
            acc[2] += b
            n += 1
    if not n:
        return (0.0, 0.0, 0.0)
    return (acc[0] / n, acc[1] / n, acc[2] / n)


def compare(ref: Image.Image, ref_sil: set, ref_pal: list[float], ref_rgb, other: Image.Image) -> dict:
    other_sil = silhouette(other)
    inter = len(ref_sil & other_sil)
    union = len(ref_sil | other_sil)
    other_rgb = mean_color(other)
    return {
        "silhouette_iou": round(inter / union, 4) if union else 0.0,
        "palette_l1": round(palette_l1(ref_pal, palette_vector(other)), 4),
        "mean_color_drift": [round(other_rgb[i] - ref_rgb[i], 1) for i in range(3)],
        "aspect_ref": round(ref.width / ref.height, 3),
        "aspect_other": round(other.width / other.height, 3),
        "aspect_drift": round(abs(ref.width / ref.height - other.width / other.height), 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True)
    parser.add_argument("--glob", required=True)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    ref_path = Path(args.reference)
    ref_subject = load_subject(ref_path)
    if ref_subject is None:
        raise SystemExit(f"reference has no subject: {ref_path}")

    ref_sil = silhouette(ref_subject)
    ref_pal = palette_vector(ref_subject)
    ref_rgb = mean_color(ref_subject)

    rows = []
    for path in sorted(REPO.glob(args.glob)):
        subject = load_subject(path)
        if subject is None:
            continue
        stats = compare(ref_subject, ref_sil, ref_pal, ref_rgb, subject)
        stats["file"] = str(path.relative_to(REPO))
        rows.append(stats)

    out = Path(args.out) if args.out else REPO / "assets" / "qa" / "consistency.json"
    if not out.is_absolute():
        out = REPO / out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"reference": str(ref_path), "frames": rows}, indent=2), encoding="utf-8")

    print(f"{'frame':<58} {'IoU':>6} {'palL1':>6} {'aspect':>7}")
    for r in sorted(rows, key=lambda r: r["silhouette_iou"]):
        print(f"{r['file'].replace('assets/raw/ofox/gpt-image-2.5-sunburst/', ''):<58} {r['silhouette_iou']:>6.3f} {r['palette_l1']:>6.3f} {r['aspect_drift']:>7.3f}")
    print(f"[consistency] wrote {out.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
