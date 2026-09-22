"""Build a human review sheet for normalized frames.

Two panels per frame: the whole sprite and a head crop (top band of the alpha
bounding box). The head panel is the one that answers "is this the same person?"
at a glance, which silhouette statistics cannot.

Usage:
    python tools/contact_sheet.py --glob "assets/sprites/xuanzang/*.png" --out assets/qa/contact-xuanzang.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[1]
FULL = 200
HEAD = 200
HEAD_BAND = 0.38


def load_rgba(path: Path) -> Image.Image:
    im = Image.open(path)
    im.load()
    return im.convert("RGBA")


def on_background(im: Image.Image, size: int, bg: tuple[int, int, int]) -> Image.Image:
    plate = Image.new("RGB", im.size, bg)
    plate.paste(im, (0, 0), im)
    return plate.resize((size, size), Image.LANCZOS)


def head_crop(im: Image.Image) -> Image.Image:
    bbox = im.getchannel("A").getbbox()
    if not bbox:
        return im
    top = bbox[1]
    band = max(1, int((bbox[3] - bbox[1]) * HEAD_BAND))
    return im.crop((bbox[0], top, bbox[2], min(im.height, top + band)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glob", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--label", default="")
    args = parser.parse_args()

    paths = sorted(REPO.glob(args.glob))
    if not paths:
        raise SystemExit(f"no files matched {args.glob}")

    cols = min(6, len(paths))
    rows = (len(paths) + cols - 1) // cols
    cell_w = FULL + HEAD + 24
    cell_h = FULL + 22
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h + 28), (24, 26, 30))
    draw = ImageDraw.Draw(sheet)
    title = f"contact sheet: {args.label or args.glob}   left=full(double scale) right=head(top {int(HEAD_BAND*100)}%)"
    draw.text((10, 8), title, fill=(240, 236, 224))

    for index, path in enumerate(paths):
        col = index % cols
        row = index // cols
        x = col * cell_w + 6
        y = row * cell_h + 28
        im = load_rgba(path)
        full = on_background(im, FULL, (235, 228, 214))
        head = on_background(head_crop(im), HEAD, (235, 228, 214))
        sheet.paste(full, (x, y))
        sheet.paste(head, (x + FULL + 12, y))
        draw.rectangle((x, y, x + FULL + HEAD + 12, y + FULL - 1), outline=(90, 90, 100))
        draw.text((x + 4, y + FULL + 2), f"{path.stem}", fill=(200, 200, 210))

    out = Path(args.out)
    if not out.is_absolute():
        out = REPO / out
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"[contact] {out.relative_to(REPO)}  frames={len(paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
