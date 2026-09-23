"""Promote the latest transparent GPT Image 2.5 sprite frames into the game.

The generated sheets are the identity source.  Two poses keep a prop separate
from the body, so those poses are cropped by their authored 2x2 cell instead of
being split by connected components.  The script is idempotent and writes a
small provenance report plus a light/dark contact sheet for human review.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw


REPO = Path(__file__).resolve().parents[1]
SPRITES = REPO / "assets" / "sprites"
QA = REPO / "assets" / "qa"
V2 = QA / "2.5-slice-check-v2" / "sprites"
RAW = REPO / "assets" / "raw" / "ofox" / "gpt-image-2.5-sunburst"
LEGACY = REPO / "assets" / "raw" / "superseded" / "latest-promotion-legacy"
CANVAS = {"xuanzang": (1024, 768), "wolf": (512, 384)}
BASELINE = {"xuanzang": 736, "wolf": 350}


def alpha_bbox(image: Image.Image, threshold: int = 16):
    image = image.convert("RGBA")
    alpha = image.getchannel("A").point(lambda value: value if value >= threshold else 0)
    return alpha.getbbox(), alpha


def validate(path: Path, actor: str) -> dict:
    image = Image.open(path).convert("RGBA")
    expected = CANVAS[actor]
    if image.size != expected:
        raise SystemExit(f"{path} has size {image.size}, expected {expected}")
    alpha = image.getchannel("A")
    histogram = alpha.histogram()
    if histogram[0] == 0:
        raise SystemExit(f"{path} is opaque")
    bbox = alpha.getbbox()
    if not bbox:
        raise SystemExit(f"{path} is empty")
    if bbox[0] < 2 or bbox[2] > image.width - 2:
        raise SystemExit(f"{path} touches the canvas edge: {bbox}")
    if bbox[3] > BASELINE[actor] + 1:
        raise SystemExit(f"{path} crosses the {actor} baseline: {bbox}")
    return {
        "size": list(image.size),
        "bbox": list(bbox),
        "transparent_ratio": round(histogram[0] / (image.width * image.height), 4),
        "alpha_max": max(alpha.getdata()),
    }


def copy_frame(actor: str, alias: str, source: Path) -> Path:
    destination = SPRITES / actor / f"{alias}_01.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    validate(destination, actor)
    return destination


def archive_stale_frames() -> None:
    desired = {
        "xuanzang": {"idle_01.png", "walk_01.png", "attack_01.png", "chant_01.png", "jump_01.png", "fall_01.png", "land_01.png", "hurt_01.png"},
        "wolf": {"idle_01.png", "walk_01.png", "run_01.png"},
    }
    LEGACY.mkdir(parents=True, exist_ok=True)
    for actor, names in desired.items():
        source_dir = SPRITES / actor
        if not source_dir.exists():
            continue
        target_dir = LEGACY / actor
        target_dir.mkdir(parents=True, exist_ok=True)
        for path in source_dir.glob("*.png"):
            if path.name in names:
                continue
            target = target_dir / path.name
            if target.exists():
                target.unlink()
            shutil.move(str(path), str(target))
            sidecar = path.with_name(path.name + ".import")
            if sidecar.exists():
                shutil.move(str(sidecar), str(target.with_name(target.name + ".import")))


def write_ledger(actor: str, names: list[str], scale: float) -> None:
    ledger = {
        "actor": actor,
        "sheet_scale": scale,
        "frames": {name[:-4]: scale for name in names},
        "clamped": [],
        "unique_scales": [scale],
        "source_model": "openai/gpt-image-2.5-sunburst",
        "pipeline": "tools/promote_latest_sprites.py",
    }
    (QA / f"normalization-{actor}.json").write_text(json.dumps(ledger, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def feet_anchor_x(subject: Image.Image) -> float:
    alpha = subject.getchannel("A")
    pixels = alpha.load()
    y0 = max(0, int(subject.height * 0.88))
    total = 0.0
    weighted = 0.0
    for y in range(y0, subject.height):
        for x in range(subject.width):
            value = pixels[x, y]
            if value <= 8:
                continue
            total += value
            weighted += value * x
    return weighted / total if total else subject.width * 0.5


def normalize_cell(source: Path, cell: tuple[int, int, int, int], actor: str, alias: str, scale: float) -> Path:
    image = Image.open(source).convert("RGBA").crop(cell)
    bbox, alpha = alpha_bbox(image)
    if not bbox:
        raise SystemExit(f"empty cell {cell} in {source}")
    alpha = remove_small_components(alpha, min_area=128)
    if alias == "hurt" and cell[1] > 0:
        pixels = alpha.load()
        for y in range(min(28, alpha.height)):
            for x in range(alpha.width):
                pixels[x, y] = 0
    image.putalpha(alpha)
    bbox = alpha.getbbox()
    if not bbox:
        raise SystemExit(f"cell lost all components after cleanup: {source} {cell}")
    subject = image.crop(bbox)
    target = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
    subject = subject.resize(target, Image.Resampling.LANCZOS)
    alpha = subject.getchannel("A").point(lambda value: 0 if value <= 8 else value)
    subject.putalpha(alpha)
    canvas = Image.new("RGBA", CANVAS[actor], (0, 0, 0, 0))
    x = round(canvas.width * 0.5 - feet_anchor_x(subject))
    x = max(2, min(x, canvas.width - subject.width - 2))
    y = BASELINE[actor] - subject.height
    canvas.alpha_composite(subject, (x, y))
    destination = SPRITES / actor / f"{alias}_01.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)
    validate(destination, actor)
    return destination


def remove_small_components(alpha: Image.Image, min_area: int) -> Image.Image:
    """Keep body/prop components and remove tiny pixels leaking from a neighbour."""
    step = 2
    small = alpha.resize(((alpha.width + step - 1) // step, (alpha.height + step - 1) // step), Image.BOX)
    width, height = small.size
    pixels = small.load()
    seen = bytearray(width * height)
    keep = bytearray(width * height)
    components: list[list[tuple[int, int]]] = []
    for sy in range(height):
        for sx in range(width):
            index = sy * width + sx
            if seen[index] or pixels[sx, sy] < 16:
                continue
            seen[index] = 1
            stack = [(sx, sy)]
            component = []
            while stack:
                x, y = stack.pop()
                component.append((x, y))
                for dy in (-1, 0, 1):
                    ny = y + dy
                    if ny < 0 or ny >= height:
                        continue
                    for dx in (-1, 0, 1):
                        nx = x + dx
                        if nx < 0 or nx >= width:
                            continue
                        neighbour = ny * width + nx
                        if seen[neighbour] or pixels[nx, ny] < 16:
                            continue
                        seen[neighbour] = 1
                        stack.append((nx, ny))
            if len(component) >= min_area:
                components.append(component)
    for component in sorted(components, key=len, reverse=True)[:2]:
        for x, y in component:
            keep[y * width + x] = 1
    output = alpha.copy()
    output_pixels = output.load()
    for y in range(output.height):
        for x in range(output.width):
            if not keep[(y // step) * width + (x // step)]:
                output_pixels[x, y] = 0
    return output


def contact_sheet(entries: list[tuple[str, Path]]) -> Path:
    tile_w, tile_h = 260, 230
    cols = 4
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGB", (tile_w * cols * 2, tile_h * rows), (35, 35, 38))
    draw = ImageDraw.Draw(sheet)
    for index, (label, path) in enumerate(entries):
        image = Image.open(path).convert("RGBA")
        plate = Image.new("RGBA", (tile_w, tile_h), (238, 231, 215, 255))
        dark = Image.new("RGBA", (tile_w, tile_h), (28, 30, 34, 255))
        image.thumbnail((tile_w - 24, tile_h - 42), Image.Resampling.LANCZOS)
        offset = ((tile_w - image.width) // 2, 28 + (tile_h - 42 - image.height) // 2)
        plate.alpha_composite(image, offset)
        dark.alpha_composite(image, offset)
        col, row = index % cols, index // cols
        x = col * tile_w * 2
        y = row * tile_h
        sheet.paste(plate.convert("RGB"), (x, y))
        sheet.paste(dark.convert("RGB"), (x + tile_w, y))
        draw.text((x + 8, y + 8), label, fill=(90, 75, 50))
        draw.text((x + tile_w + 8, y + 8), label, fill=(255, 235, 180))
    output = QA / "latest-sprites-contact.png"
    sheet.save(output)
    return output


def main() -> int:
    archive_stale_frames()
    promoted: dict[str, dict[str, dict]] = {"xuanzang": {}, "wolf": {}}
    entries: list[tuple[str, Path]] = []

    xz_sources = {
        "idle": V2 / "xuanzang" / "idle_01.png",
        "walk": V2 / "xuanzang" / "walk_01.png",
        "attack": V2 / "xuanzang" / "staff_01.png",
        "chant": None,
        "jump": None,
        "fall": None,
        "land": None,
        "hurt": None,
    }
    for alias, source in xz_sources.items():
        if source is not None:
            destination = copy_frame("xuanzang", alias, source)
        else:
            if alias == "chant":
                source = RAW / "run-107-sheet_xuanzang_safe4_grid_forward_staff" / "image-0.png"
                cell = (0, 512, 768, 1024)
                destination = normalize_cell(source, cell, "xuanzang", alias, 0.88477)
            else:
                run111 = RAW / "run-111-sheet_xuanzang_air_ground_recoil_2x2" / "image-0.png"
                cells = {
                "jump": (0, 0, 768, 512),
                "fall": (768, 0, 1536, 512),
                "land": (0, 512, 768, 1024),
                "hurt": (768, 512, 1536, 1024),
                }
                destination = normalize_cell(run111, cells[alias], "xuanzang", alias, 0.88477)
        promoted["xuanzang"][f"{alias}_01.png"] = {
            "source": str((source if source is not None else RAW / "run-111-sheet_xuanzang_air_ground_recoil_2x2" / "image-0.png").relative_to(REPO)),
            "generated_model": "openai/gpt-image-2.5-sunburst",
            "validation": validate(destination, "xuanzang"),
        }
        entries.append((f"xuanzang/{alias}", destination))

    wolf_sources = {alias: V2 / "wolf" / f"{alias}_01.png" for alias in ("idle", "walk", "run")}
    for alias, source in wolf_sources.items():
        destination = copy_frame("wolf", alias, source)
        promoted["wolf"][f"{alias}_01.png"] = {
            "source": str(source.relative_to(REPO)),
            "generated_model": "openai/gpt-image-2.5-sunburst",
            "validation": validate(destination, "wolf"),
        }
        entries.append((f"wolf/{alias}", destination))

    write_ledger("xuanzang", ["idle_01.png", "walk_01.png", "attack_01.png", "chant_01.png", "jump_01.png", "fall_01.png", "land_01.png", "hurt_01.png"], 0.88477)
    write_ledger("wolf", ["idle_01.png", "walk_01.png", "run_01.png"], 0.55762)

    report = {
        "model": "openai/gpt-image-2.5-sunburst",
        "transparent_required": True,
        "actors": promoted,
        "legacy_frames_retained": {
            "xuanzang": ["attack_02.png", "attack_03.png"],
            "wolf": ["attack_01.png", "hurt_01.png"],
        },
    }
    report_path = QA / "latest-sprite-promotion.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    contact = contact_sheet(entries)
    print(json.dumps({"report": str(report_path.relative_to(REPO)), "contact": str(contact.relative_to(REPO)), "promoted": promoted}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
