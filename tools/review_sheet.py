"""把切片得到的每一格画成带编号的审阅图，供人工标注"第 N 格其实是哪个动作"。

别名是按位置分配的，而模型不保证按提示词的顺序作画；几何闸门查不出"这一格画的是
跑还是走"。这个工具把编号烧进图里，人只要报回一份映射，就能在不重生成的前提下把
别名纠正过来。

Usage:
    python tools/review_sheet.py --dir assets/qa/sheet-crops/run-99-sheet_xuanzang_seed12_v5
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[1]
CELL = 260


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--out", default=None)
    parser.add_argument("--cols", type=int, default=4)
    args = parser.parse_args()

    crop_dir = Path(args.dir)
    if not crop_dir.is_absolute():
        crop_dir = REPO / crop_dir
    paths = sorted(crop_dir.glob("*_raw.png"))
    if not paths:
        raise SystemExit(f"no crops in {crop_dir}")

    rows = (len(paths) + args.cols - 1) // args.cols
    sheet = Image.new("RGB", (args.cols * CELL, rows * CELL), (26, 28, 32))
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(paths, start=1):
        im = Image.open(path).convert("RGBA")
        bbox = im.getchannel("A").getbbox()
        if bbox:
            im = im.crop(bbox)
        scale = min((CELL - 40) / im.width, (CELL - 40) / im.height)
        im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
        col = (index - 1) % args.cols
        row = (index - 1) // args.cols
        plate = Image.new("RGB", (CELL, CELL), (235, 228, 214))
        plate.paste(im, ((CELL - im.width) // 2, (CELL - im.height) // 2), im)
        sheet.paste(plate, (col * CELL, row * CELL))
        draw.rectangle((col * CELL, row * CELL, (col + 1) * CELL - 1, (row + 1) * CELL - 1), outline=(90, 90, 100))
        draw.rectangle((col * CELL + 6, row * CELL + 6, col * CELL + 46, row * CELL + 40), fill=(20, 20, 20))
        draw.text((col * CELL + 14, row * CELL + 14), f"#{index}", fill=(255, 235, 180))
        draw.text((col * CELL + 8, (row + 1) * CELL - 22), path.stem.replace("_raw", ""), fill=(60, 55, 50))

    out = Path(args.out) if args.out else crop_dir.parent / f"review-{crop_dir.name}.png"
    if not out.is_absolute():
        out = REPO / out
    sheet.save(out)
    print(f"[review] {out.relative_to(REPO)}  cells={len(paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
