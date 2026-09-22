"""Local matting for Seedream sprite sheets: chroma key with colour unmixing.

Seedream returns opaque RGB (no alpha), so sprites are generated on a flat key
colour (pure magenta by default) and keyed out here.

This is not a threshold trick. For every pixel the render is modelled as

    observed = alpha * foreground + (1 - alpha) * key

so alpha comes from the distance to the key colour and the foreground is solved
back out (`F = (observed - (1 - a) * key) / a`). That removes the magenta fringe
on soft edges instead of leaving a purple halo around the character.

Usage:
    python tools/matte.py --input raw.png --out keyed.png
    python tools/matte.py --input raw.png --out keyed.png --key "#FF00FF" --inner 40 --outer 120
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]


def parse_color(text: str) -> tuple[int, int, int]:
    text = text.strip().lstrip("#")
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def border_key_color(im: Image.Image) -> tuple[int, int, int]:
    px = im.load()
    w, h = im.size
    samples = []
    step = max(1, min(w, h) // 80)
    for x in range(0, w, step):
        samples.append(px[x, 0])
        samples.append(px[x, h - 1])
    for y in range(0, h, step):
        samples.append(px[0, y])
        samples.append(px[w - 1, y])
    return (
        int(statistics.median(s[0] for s in samples)),
        int(statistics.median(s[1] for s in samples)),
        int(statistics.median(s[2] for s in samples)),
    )


def matte(
    im: Image.Image,
    key: tuple[int, int, int],
    inner: float,
    outer: float,
    alpha_floor: int = 0,
) -> tuple[Image.Image, dict]:
    rgb = im.convert("RGB")
    w, h = rgb.size
    src = rgb.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    kr, kg, kb = key
    keyed = 0
    soft = 0
    fringe = 0
    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            # Euclidean distance to the key colour decides how much background is here.
            distance = ((r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2) ** 0.5
            if distance >= outer:
                alpha = 1.0
            elif distance <= inner:
                alpha = 0.0
            else:
                alpha = (distance - inner) / (outer - inner)
            if alpha * 255.0 < float(alpha_floor):
                # Sub-floor alpha is invisible haze, not a soft edge: clearing it
                # removes the scattered key-coloured specks seen outside a subject
                # (they live at alpha 8–40 and no area filter can catch them all).
                alpha = 0.0
            if alpha <= 0.001:
                keyed += 1
                continue
            if alpha < 0.999:
                soft += 1
                inv = 1.0 - alpha
                # Unmix: subtract the key contribution, then divide by alpha.
                r = (r - inv * kr) / alpha
                g = (g - inv * kg) / alpha
                b = (b - inv * kb) / alpha
                r = min(255.0, max(0.0, r))
                g = min(255.0, max(0.0, g))
                b = min(255.0, max(0.0, b))
            # Leftover magenta haze is only meaningful on the soft edge band, and
            # only where blue dominates (a warm 土黄 fur pixel is not spill).
            if 0.05 < alpha < 0.95 and b > r + 25 and b > g + 25:
                fringe += 1
            dst[x, y] = (int(r), int(g), int(b), int(round(alpha * 255.0)))
    total = w * h
    stats = {
        "size": [w, h],
        "key_color": [kr, kg, kb],
        "inner": inner,
        "outer": outer,
        "alpha_floor": alpha_floor,
        "keyed_pixels": keyed,
        "keyed_ratio": round(keyed / total, 4),
        "soft_edge_pixels": soft,
        "residual_fringe_pixels": fringe,
        "residual_fringe_ratio": round(fringe / total, 6),
    }
    return out, stats


def despeckle(
    rgba: Image.Image,
    alpha_threshold: int = 24,
    min_area: int = 64,
    block: int = 2,
) -> tuple[Image.Image, dict]:
    """Remove isolated faint specks left behind by keying.

    A flat key plate is never perfectly flat: pixels landing in the partial-alpha
    band become 20–50% opaque dots scattered outside the character. They are not
    fringe (they are not attached to an edge), so the fix is a connected-component
    area filter: anything not connected to a big blob, and smaller than
    `min_area` pixels, is cleared. Soft edges of the real subject survive because
    they belong to a large component.
    """
    w, h = rgba.size
    alpha = rgba.getchannel("A")
    px = alpha.load()
    out = rgba.copy()
    out_px = out.load()
    mw, mh = (w + block - 1) // block, (h + block - 1) // block
    visited = bytearray(mw * mh)
    removed_components = 0
    removed_pixels = 0

    def block_hits(mx: int, my: int) -> bool:
        for yy in range(my * block, min(h, (my + 1) * block)):
            for xx in range(mx * block, min(w, (mx + 1) * block)):
                if px[xx, yy] >= alpha_threshold:
                    return True
        return False

    for sy in range(mh):
        for sx in range(mw):
            idx = sy * mw + sx
            if visited[idx] or not block_hits(sx, sy):
                continue
            visited[idx] = 1
            stack = [(sx, sy)]
            cells: list[tuple[int, int]] = []
            area = 0
            overflow = False
            while stack:
                cx, cy = stack.pop()
                if not overflow:
                    cells.append((cx, cy))
                for dy in (-1, 0, 1):
                    ny = cy + dy
                    if ny < 0 or ny >= mh:
                        continue
                    for dx in (-1, 0, 1):
                        nx = cx + dx
                        if nx < 0 or nx >= mw:
                            continue
                        nidx = ny * mw + nx
                        if visited[nidx] or not block_hits(nx, ny):
                            continue
                        visited[nidx] = 1
                        stack.append((nx, ny))
                for yy in range(cy * block, min(h, (cy + 1) * block)):
                    for xx in range(cx * block, min(w, (cx + 1) * block)):
                        if px[xx, yy] >= alpha_threshold:
                            area += 1
                if area > min_area and not overflow:
                    overflow = True
                    cells = []
            if not overflow:
                removed_components += 1
                for cx, cy in cells:
                    for yy in range(cy * block, min(h, (cy + 1) * block)):
                        for xx in range(cx * block, min(w, (cx + 1) * block)):
                            if out_px[xx, yy][3] != 0:
                                out_px[xx, yy] = (0, 0, 0, 0)
                                removed_pixels += 1
    return out, {
        "speckles_removed": removed_components,
        "speckle_pixels_removed": removed_pixels,
        "min_area": min_area,
        "block": block,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--key", default="auto", help='hex colour or "auto" (border median)')
    parser.add_argument("--inner", type=float, default=40.0, help="distance at/below which a pixel is pure background")
    parser.add_argument("--outer", type=float, default=120.0, help="distance at/above which a pixel is pure subject")
    parser.add_argument("--report", default=None)
    parser.add_argument("--despeckle-min-area", type=int, default=64, help="clear isolated alpha blobs smaller than this many pixels (0 disables)")
    parser.add_argument("--alpha-floor", type=int, default=40, help="treat alpha below this as fully transparent (visible-haze removal)")
    args = parser.parse_args()

    src = Path(args.input)
    if not src.is_absolute():
        src = REPO / src
    dst = Path(args.out)
    if not dst.is_absolute():
        dst = REPO / dst

    im = Image.open(src)
    im.load()
    key = border_key_color(im.convert("RGB")) if args.key == "auto" else parse_color(args.key)
    rgba, stats = matte(im, key, args.inner, args.outer, args.alpha_floor)
    if args.despeckle_min_area > 0:
        rgba, speck = despeckle(rgba, alpha_threshold=max(8, args.alpha_floor), min_area=args.despeckle_min_area)
        stats.update(speck)
    dst.parent.mkdir(parents=True, exist_ok=True)
    rgba.save(dst)

    stats["input"] = str(src.relative_to(REPO))
    stats["output"] = str(dst.relative_to(REPO))
    report_path = Path(args.report) if args.report else dst.with_name(dst.stem + ".matte.json")
    if not report_path.is_absolute():
        report_path = REPO / report_path
    report_path.write_text(json.dumps(stats, indent=2), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
