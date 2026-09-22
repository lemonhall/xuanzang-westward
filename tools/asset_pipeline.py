"""Asset pipeline for Xuanzang Westward.

Two deterministic steps, both idempotent:

  qa        Inspect raw OFOX output: alpha statistics, subject bounding box,
            edge clearance, and light/dark composite contact sheets for human review.
  normalize Crop to the alpha bounding box, scale the subject to a per-actor
            target height, then paste into a fixed canvas aligned to a foot
            baseline. This is what makes independently generated frames line up
            in Godot regardless of how each generation framed the character.

Raw OFOX output is never modified. Normalized files land in assets/sprites,
assets/backgrounds, assets/fx.

Usage:
    python tools/asset_pipeline.py qa --batch l1-probe
    python tools/asset_pipeline.py normalize
"""

from __future__ import annotations

import argparse
import statistics
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter
from PIL import ImageFilter

REPO = Path(__file__).resolve().parents[1]
RAW_ROOT = REPO / "assets" / "raw" / "ofox"
SPRITE_DIR = REPO / "assets" / "sprites"
BG_DIR = REPO / "assets" / "backgrounds"
FX_DIR = REPO / "assets" / "fx"
QA_DIR = REPO / "assets" / "qa"

# slug convention: <actor>_<alias>_<frame>
ACTOR_SPECS = {
    "xuanzang": {"height": 430, "canvas": (512, 512), "baseline": 480},
    "boss": {"height": 420, "canvas": (512, 512), "baseline": 484},
    "enemy": {"height": 300, "canvas": (384, 384), "baseline": 360},
}
FX_CANVAS = 256


def iter_runs():
    """Yield (run_dir, slug) for every OFOX run directory."""
    for model_dir in sorted(p for p in RAW_ROOT.iterdir() if p.is_dir()):
        for run_dir in sorted(p for p in model_dir.iterdir() if p.is_dir()):
            name = run_dir.name
            if not name.startswith("run-"):
                continue
            parts = name.split("-", 2)
            if len(parts) < 3:
                continue
            yield model_dir.name, run_dir, parts[2]


def load_rgba(path: Path) -> Image.Image:
    im = Image.open(path)
    im.load()
    im = im.convert("RGBA")
    # Zero the faintest alpha: LANCZOS resampling can round edge pixels to 0,
    # which makes the measured bounding box (and thus the frame height) jitter.
    alpha = im.getchannel("A").point(lambda v: 0 if v < 8 else v)
    im.putalpha(alpha)
    return im


def subject_stats(im: Image.Image) -> dict:
    alpha = im.getchannel("A")
    bbox = alpha.getbbox()
    total = im.width * im.height
    hist = alpha.histogram()
    transparent = hist[0]
    stats = {
        "size": [im.width, im.height],
        "transparent_pixels": transparent,
        "transparent_ratio": round(transparent / total, 4),
        "native_alpha": transparent > 0,
    }
    if not bbox:
        stats["empty"] = True
        return stats
    stats["bbox"] = list(bbox)
    stats["bbox_w"] = bbox[2] - bbox[0]
    stats["bbox_h"] = bbox[3] - bbox[1]
    stats["height_ratio"] = round((bbox[3] - bbox[1]) / im.height, 4)
    stats["edge_clearance"] = {
        "left": bbox[0],
        "top": bbox[1],
        "right": im.width - bbox[2],
        "bottom": im.height - bbox[3],
    }
    subject_alpha = [a for a in alpha.crop(bbox).getdata() if a > 0]
    stats["subject_alpha_mean"] = round(sum(subject_alpha) / len(subject_alpha), 1)
    stats["subject_alpha_max"] = max(subject_alpha)
    stats["subject_pixel_ratio"] = round(len(subject_alpha) / total, 4)
    rgb = im.convert("RGB").crop(bbox).resize((1, 1), Image.LANCZOS).getpixel((0, 0))
    stats["mean_color_rgb"] = list(rgb)
    return stats


def composite(im: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    plate = Image.new("RGBA", im.size, bg + (255,))
    plate.alpha_composite(im)
    return plate.convert("RGB")


def cmd_qa(args) -> int:
    QA_DIR.mkdir(parents=True, exist_ok=True)
    report = {"batch": args.batch, "runs": []}
    tiles = []

    for model, run_dir, slug in iter_runs():
        images = sorted(run_dir.glob("image-*.png"))
        if not images:
            continue
        entry = {"model": model, "slug": slug, "run_dir": str(run_dir.relative_to(REPO)), "files": []}
        for img_path in images:
            im = load_rgba(img_path)
            stats = subject_stats(im)
            stats["file"] = str(img_path.relative_to(REPO))
            entry["files"].append(stats)
            tiles.append((f"{slug}/{img_path.name}", composite(im, (235, 228, 214)), composite(im, (28, 30, 34))))
        report["runs"].append(entry)

    out_json = QA_DIR / f"qa-{args.batch}.json"
    out_json.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[qa] wrote {out_json.relative_to(REPO)}")

    if tiles:
        thumb = 320
        cols = 2
        rows = len(tiles)
        sheet = Image.new("RGB", (thumb * cols, thumb * rows), (245, 245, 245))
        for row, (_label, light, dark) in enumerate(tiles):
            sheet.paste(light.resize((thumb, thumb), Image.LANCZOS), (0, row * thumb))
            sheet.paste(dark.resize((thumb, thumb), Image.LANCZOS), (thumb, row * thumb))
        sheet_path = QA_DIR / f"contact-{args.batch}.png"
        sheet.save(sheet_path)
        print(f"[qa] wrote {sheet_path.relative_to(REPO)} (left=light bg, right=dark bg)")

    for run in report["runs"]:
        for f in run["files"]:
            flag = "OK " if f.get("native_alpha") or run["slug"].startswith("bg_") else "?? "
            print(f"[qa] {flag}{run['slug']:<28} h_ratio={f.get('height_ratio')} alpha_mean={f.get('subject_alpha_mean')} edge={f.get('edge_clearance')}")
    return 0


def estimate_background(im: Image.Image) -> tuple[int, int, int]:
    """Median colour of the image border, used as the keying target."""
    rgb = im.convert("RGB")
    px = rgb.load()
    samples = []
    step = max(1, min(im.width, im.height) // 64)
    for x in range(0, im.width, step):
        samples.append(px[x, 0])
        samples.append(px[x, im.height - 1])
    for y in range(0, im.height, step):
        samples.append(px[0, y])
        samples.append(px[im.width - 1, y])
    return (
        int(statistics.median(s[0] for s in samples)),
        int(statistics.median(s[1] for s in samples)),
        int(statistics.median(s[2] for s in samples)),
    )


def key_background(im: Image.Image, tolerance: int) -> tuple[Image.Image, dict]:
    """Convert an opaque render into RGBA by keying out its flat background.

    Fallback for endpoints that return RGB: the model is asked for a flat
    magenta plate, and this turns colour distance into alpha. The original file
    is never modified; the mask is derived, so the result is reproducible.
    """
    rgb = im.convert("RGB")
    bg = estimate_background(rgb)
    px = rgb.load()
    out = Image.new("RGBA", rgb.size, (0, 0, 0, 0))
    out_px = out.load()
    keyed = 0
    for y in range(rgb.height):
        for x in range(rgb.width):
            r, g, b = px[x, y]
            distance = abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])
            if distance <= tolerance:
                keyed += 1
                continue
            out_px[x, y] = (r, g, b, 255)
    stats = {
        "background_rgb": list(bg),
        "tolerance": tolerance,
        "keyed_pixels": keyed,
        "keyed_ratio": round(keyed / (rgb.width * rgb.height), 4),
    }
    return out, stats


def cmd_keybg(args) -> int:
    src = Path(args.input)
    if not src.is_absolute():
        src = REPO / src
    im = load_rgba(src)
    rgba, stats = key_background(im, args.tolerance)
    out = Path(args.out)
    if not out.is_absolute():
        out = REPO / out
    out.parent.mkdir(parents=True, exist_ok=True)
    rgba.save(out)
    print(json.dumps({"in": str(src.relative_to(REPO)), "out": str(out.relative_to(REPO)), **stats}, ensure_ascii=False))
    return 0


def _label_components(mask: Image.Image, min_area: int) -> list[tuple[int, int, int, int]]:
    """Connected-component bounding boxes of a 1-bit mask (8-connectivity)."""
    w, h = mask.size
    px = mask.load()
    seen = bytearray(w * h)
    boxes: list[tuple[int, int, int, int]] = []
    for sy in range(h):
        for sx in range(w):
            start = sy * w + sx
            if seen[start] or not px[sx, sy]:
                continue
            stack = [(sx, sy)]
            seen[start] = 1
            min_x = max_x = sx
            min_y = max_y = sy
            area = 0
            while stack:
                x, y = stack.pop()
                area += 1
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y
                for dy in (-1, 0, 1):
                    ny = y + dy
                    if ny < 0 or ny >= h:
                        continue
                    for dx in (-1, 0, 1):
                        nx = x + dx
                        if nx < 0 or nx >= w:
                            continue
                        idx = ny * w + nx
                        if seen[idx] or not px[nx, ny]:
                            continue
                        seen[idx] = 1
                        stack.append((nx, ny))
            if area >= min_area:
                boxes.append((min_x, min_y, max_x + 1, max_y + 1))
    return boxes


def normalize_sprite_from_image(subject_full: Image.Image, actor: str, alias: str, frame: str) -> Path:
    """normalize_sprite, starting from an already-cropped subject image."""
    spec = spec_for(actor)
    target_h = spec["height"]
    scale = target_h / subject_full.height
    target_w = max(1, round(subject_full.width * scale))
    subject = subject_full.resize((target_w, target_h), Image.LANCZOS)
    canvas_w, canvas_h = spec["canvas"]
    if target_w > canvas_w:
        raise SystemExit(f"subject too wide for canvas ({target_w} > {canvas_w}); check the slice bounds")
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    canvas.alpha_composite(subject, ((canvas_w - target_w) // 2, spec["baseline"] - target_h))
    out_dir = SPRITE_DIR / actor
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{alias}_{frame}.png"
    canvas.save(out_path)
    return out_path


def slice_sheet(
    src: Path,
    actor: str,
    aliases: list[str],
    expected: int,
    downsample: int = 4,
    dilate: int = 5,
    alpha_threshold: int = 16,
    rows: int = 0,
) -> dict:
    """Split a one-image sprite sheet into normalized frames.

    Identity consistency comes from generating every pose of a character inside a
    single image. Slicing must not assume the model hit exact cell boundaries, so
    poses are found as alpha connected components: the mask is downsampled for
    speed, dilated so staffs and tassels merge with the body, then mapped back to
    full resolution and cropped tightly.
    """
    im = load_rgba(src)
    alpha = im.getchannel("A")
    small = alpha.resize((max(1, im.width // downsample), max(1, im.height // downsample)), Image.BOX)
    mask = small.point(lambda v: 255 if v >= alpha_threshold else 0)
    if dilate >= 3:
        mask = mask.filter(ImageFilter.MaxFilter(dilate if dilate % 2 == 1 else dilate + 1))

    min_area = max(4, int(mask.width * mask.height * 0.002))
    boxes = _label_components(mask.convert("L"), min_area)
    if not boxes:
        raise SystemExit(f"no components found in {src}")

    # Assign components to rows by splitting sorted y-centres at the largest gaps.
    # More robust than matching against each row's first centre, which breaks as
    # soon as one pose (a raised staff, a jump) sits far from its row mates.
    centres = sorted(((b[1] + b[3]) / 2, b) for b in boxes)
    if rows >= 2 and len(centres) > rows:
        gaps = [(centres[i + 1][0] - centres[i][0], i) for i in range(len(centres) - 1)]
        cuts = sorted(i for _gap, i in sorted(gaps, key=lambda item: -item[0])[: rows - 1])
        row_groups: list[list[tuple[int, int, int, int]]] = []
        start = 0
        for cut in cuts:
            row_groups.append([box for _center, box in centres[start : cut + 1]])
            start = cut + 1
        row_groups.append([box for _center, box in centres[start:]])
    else:
        heights = sorted(b[3] - b[1] for b in boxes)
        tolerance = max(4, heights[len(heights) // 2] // 2)
        row_groups = []
        for _center, box in centres:
            box_center = (box[1] + box[3]) / 2
            for row in row_groups:
                if abs(((row[0][1] + row[0][3]) / 2) - box_center) <= tolerance:
                    row.append(box)
                    break
            else:
                row_groups.append([box])
    ordered: list[tuple[int, int, int, int]] = []
    for row in row_groups:
        ordered.extend(sorted(row, key=lambda b: b[0]))

    if expected and len(ordered) != expected:
        raise SystemExit(
            f"expected {expected} poses, found {len(ordered)} components in {src.name}; "
            "inspect the debug overlay before re-running"
        )

    crop_dir = QA_DIR / "sheet-crops"
    crop_dir.mkdir(parents=True, exist_ok=True)
    written = []
    alias_counters: dict[str, int] = {}
    for index, box in enumerate(ordered, start=1):
        pad = downsample * 2
        full = (
            max(0, box[0] * downsample - pad),
            max(0, box[1] * downsample - pad),
            min(im.width, box[2] * downsample + pad),
            min(im.height, box[3] * downsample + pad),
        )
        crop = im.crop(full)
        tight = crop.getchannel("A").getbbox()
        if tight:
            crop = crop.crop(tight)
        alias = aliases[index - 1] if index - 1 < len(aliases) else aliases[-1]
        alias_counters[alias] = alias_counters.get(alias, 0) + 1
        frame = f"{alias_counters[alias]:02d}"
        crop.save(crop_dir / f"{actor}_{alias}_{frame}_raw.png")
        written.append(str(normalize_sprite_from_image(crop, actor, alias, frame).relative_to(REPO)))

    overlay = im.copy()
    overlay.putalpha(alpha.point(lambda v: max(48, v // 3)))
    debug = Image.alpha_composite(Image.new("RGBA", im.size, (255, 255, 255, 255)), overlay)
    draw = ImageDraw.Draw(debug)
    for index, box in enumerate(ordered, start=1):
        full = (box[0] * downsample, box[1] * downsample, box[2] * downsample, box[3] * downsample)
        draw.rectangle(full, outline=(200, 30, 30, 255), width=3)
        draw.text((full[0] + 8, full[1] + 8), f"#{index}", fill=(20, 20, 20, 255))
    debug_path = QA_DIR / f"slice-debug-{src.parent.name}.png"
    debug.save(debug_path)

    return {
        "source": str(src.relative_to(REPO)),
        "components": len(ordered),
        "frames": written,
        "debug_overlay": str(debug_path.relative_to(REPO)),
        "boxes": [list(b) for b in ordered],
    }


def cmd_slice(args) -> int:
    src = Path(args.input)
    if not src.is_absolute():
        src = REPO / src
    if src.is_dir():
        candidates = sorted(src.glob("image-*.png"))
        if not candidates:
            raise SystemExit(f"no image-*.png in {src}")
        src = candidates[0]
    report = slice_sheet(
        src,
        actor=args.actor,
        aliases=[a.strip() for a in args.aliases.split(",") if a.strip()],
        expected=args.frames,
        downsample=args.downsample,
        dilate=args.dilate,
        rows=args.rows,
    )
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


def spec_for(actor: str) -> dict:
    if actor in ACTOR_SPECS:
        return ACTOR_SPECS[actor]
    for prefix in ("boss", "enemy"):
        if actor.startswith(prefix):
            return ACTOR_SPECS[prefix]
    raise SystemExit(f"no actor spec for '{actor}' (add it to ACTOR_SPECS)")


def normalize_sprite(src: Path, actor: str, alias: str, frame: str) -> Path:
    spec = spec_for(actor)
    im = load_rgba(src)
    bbox = im.getchannel("A").getbbox()
    if not bbox:
        raise SystemExit(f"empty image (no alpha): {src}")

    subject = im.crop(bbox)
    target_h = spec["height"]
    scale = target_h / subject.height
    target_w = max(1, round(subject.width * scale))
    subject = subject.resize((target_w, target_h), Image.LANCZOS)

    canvas_w, canvas_h = spec["canvas"]
    if target_w > canvas_w:
        raise SystemExit(f"subject too wide for canvas ({target_w} > {canvas_w}): {src}")

    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    x = (canvas_w - target_w) // 2
    y = spec["baseline"] - target_h
    canvas.alpha_composite(subject, (x, y))

    out_dir = SPRITE_DIR / actor
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{alias}_{frame}.png"
    canvas.save(out_path)
    return out_path


def normalize_fx(src: Path, name: str) -> Path:
    im = load_rgba(src)
    bbox = im.getchannel("A").getbbox()
    subject = im.crop(bbox) if bbox else im
    scale = min(FX_CANVAS / subject.width, FX_CANVAS / subject.height)
    size = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
    subject = subject.resize(size, Image.LANCZOS)
    canvas = Image.new("RGBA", (FX_CANVAS, FX_CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(subject, ((FX_CANVAS - size[0]) // 2, (FX_CANVAS - size[1]) // 2))
    FX_DIR.mkdir(parents=True, exist_ok=True)
    out = FX_DIR / f"{name}.png"
    canvas.save(out)
    return out


def cmd_normalize(args) -> int:
    written = []
    for _model, run_dir, slug in iter_runs():
        src_images = sorted(run_dir.glob("image-*.png"))
        if not src_images:
            continue
        src = src_images[0]
        parts = slug.split("_")

        if slug.startswith("probe_"):
            print(f"[normalize] SKIP {slug} (diagnostic probe, not a game asset)")
            continue
        if slug.startswith("sheet_"):
            print(f"[normalize] SKIP {slug} (sprite sheet: use the `slice` command)")
            continue
        if slug.startswith("sheet_"):
            print(f"[normalize] SKIP {slug} (sprite sheet: use the `slice` command)")
            continue
        if slug.startswith("bg_"):
            level = parts[1]
            layer = parts[2] if len(parts) > 2 else "layers"
            out_dir = BG_DIR / level
            out_dir.mkdir(parents=True, exist_ok=True)
            out = out_dir / f"bg_{level}_{layer}.png"
            shutil.copyfile(src, out)
        elif slug.startswith("fx_"):
            out = normalize_fx(src, slug)
        elif slug.startswith("item_"):
            out = normalize_fx(src, slug)
        else:
            if len(parts) != 3:
                if len(parts) < 3:
                    print(f"[normalize] SKIP {slug} (expected slug shape <actor>_<alias>_<frame>)")
                    continue
            # Actor names may contain underscores (enemy_guardi_idle_01); the last
            # two segments are always <alias>_<frame>.
            actor = "_".join(parts[:-2])
            alias, frame = parts[-2], parts[-1]
            out = normalize_sprite(src, actor, alias, frame)
        written.append(out)

    for path in written:
        print(f"[normalize] {path.relative_to(REPO)}")
    print(f"[normalize] {len(written)} files")

    if args.verify:
        bad = 0
        groups: dict[tuple[str, str], list[tuple[Path, tuple[int, int, int, int]]]] = {}
        for path in written:
            if SPRITE_DIR not in path.parents:
                continue
            im = Image.open(path)
            bbox = im.getchannel("A").getbbox()
            actor_alias = (path.parent.name, path.stem.rsplit("_", 1)[0])
            groups.setdefault(actor_alias, []).append((path, bbox))
        for (actor, alias), items in sorted(groups.items()):
            heights = {b[3] - b[1] for _p, b in items}
            tops = {b[1] for _p, b in items}
            ok = len(heights) == 1 and len(tops) == 1
            print(f"[verify] {actor}/{alias}: frames={len(items)} top={sorted(tops)} height={sorted(heights)} {'OK' if ok else 'MISALIGNED'}")
            if not ok:
                bad += 1
        if bad:
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_qa = sub.add_parser("qa")
    p_qa.add_argument("--batch", default="batch")
    p_qa.set_defaults(func=cmd_qa)

    p_norm = sub.add_parser("normalize")
    p_norm.add_argument("--verify", action="store_true")
    p_norm.set_defaults(func=cmd_normalize)

    p_key = sub.add_parser("keybg", help="key out a flat background from an opaque render")
    p_key.add_argument("--input", required=True)
    p_key.add_argument("--out", required=True)
    p_key.add_argument("--tolerance", type=int, default=60)
    p_key.set_defaults(func=cmd_keybg)

    p_slice = sub.add_parser("slice", help="split a one-image sprite sheet into frames")
    p_slice.add_argument("--input", required=True, help="run directory or image path")
    p_slice.add_argument("--actor", required=True)
    p_slice.add_argument("--aliases", required=True, help="comma-separated alias per pose, in reading order")
    p_slice.add_argument("--frames", type=int, default=0, help="expected pose count (0 = accept any)")
    p_slice.add_argument("--rows", type=int, default=0, help="expected row count; rows are split at the largest y gaps")
    p_slice.add_argument("--downsample", type=int, default=4)
    p_slice.add_argument("--dilate", type=int, default=5)
    p_slice.set_defaults(func=cmd_slice)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
