"""Clean, reproducible sprite rebuild.

User-visible problem this solves: assets from two generations ended up mixed in
`assets/sprites/`, and Godot kept showing stale imports of them. Instead of
hand-cleaning, this tool rebuilds everything from a single declared source per
actor:

  1. archive every derived artefact (sprites, mattes, crops, ledgers, contact sheets)
     into assets/raw/superseded/rebuild-<stamp>/
  2. matte the canonical sheet for each actor (chroma key + unmix + despill + despeckle)
  3. slice + normalize with the gates (spacing, zoom-lock, feet baseline/anchor)
  4. purge the Godot import cache and re-import, so the engine cannot show old art
  5. print the gate results

Canonical sources live in assets/manifests/canonical.json — one entry per actor.

Usage:
    python tools/rebuild_sprites.py
    python tools/rebuild_sprites.py --skip-godot
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))

import importlib.util  # noqa: E402

spec = importlib.util.spec_from_file_location("asset_pipeline", REPO / "tools" / "asset_pipeline.py")
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)

matte_spec = importlib.util.spec_from_file_location("matte", REPO / "tools" / "matte.py")
matte_mod = importlib.util.module_from_spec(matte_spec)
matte_spec.loader.exec_module(matte_mod)

CANONICAL = REPO / "assets" / "manifests" / "canonical.json"
SPRITES = REPO / "assets" / "sprites"
QA = REPO / "assets" / "qa"
GODOT = Path(r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")


def archive_derived(stamp: str) -> Path:
    target = REPO / "assets" / "raw" / "superseded" / f"rebuild-{stamp}"
    target.mkdir(parents=True, exist_ok=True)
    for src in [
        SPRITES,
        QA / "matte",
        QA / "sheet-crops",
    ]:
        if src.exists():
            shutil.move(str(src), str(target / src.name))
    for pattern in ("normalization-*.json", "contact-*.png", "slice-debug-*.png"):
        for path in QA.glob(pattern):
            shutil.move(str(path), str(target / path.name))
    SPRITES.mkdir(parents=True, exist_ok=True)
    return target


def rebuild_actor(actor: str, entry: dict) -> dict:
    sheet = REPO / entry["sheet"]
    if not sheet.exists():
        raise SystemExit(f"canonical sheet missing for {actor}: {sheet}")
    matte_path = QA / "matte" / f"{actor}-canonical.png"
    matte_path.parent.mkdir(parents=True, exist_ok=True)

    im = Image.open(sheet)
    im.load()
    key = matte_mod.border_key_color(im.convert("RGB"))
    rgba, stats = matte_mod.matte(im, key, entry.get("inner", 40.0), entry.get("outer", 120.0), entry.get("alpha_floor", 40))
    rgba, spill = matte_mod.despill(rgba, key, entry.get("despill", 0.85))
    rgba, speck = matte_mod.despeckle(rgba, alpha_threshold=max(8, entry.get("alpha_floor", 40)), min_area=entry.get("despeckle_min_area", 64))
    rgba.save(matte_path)
    stats.update(spill)
    stats.update(speck)

    result = pipeline.slice_sheet(
        matte_path,
        actor,
        entry["aliases"],
        expected=len(entry["aliases"]),
        downsample=entry.get("downsample", 4),
        dilate=entry.get("dilate", 3),
        rows=entry.get("rows", 0),
    )
    return {"actor": actor, "sheet": entry["sheet"], "matte": stats, "slice": {k: result[k] for k in ("components", "sheet_scale", "clamped_frames")}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-godot", action="store_true")
    args = parser.parse_args()

    if not CANONICAL.exists():
        raise SystemExit(f"canonical registry missing: {CANONICAL}")
    registry = json.loads(CANONICAL.read_text(encoding="utf-8"))["actors"]

    stamp = time.strftime("%Y%m%d-%H%M%S")
    archived = archive_derived(stamp)
    print(f"[rebuild] archived previous derived assets -> {archived.relative_to(REPO)}")

    summary = []
    for actor, entry in registry.items():
        print(f"[rebuild] {actor} <- {entry['sheet']}")
        summary.append(rebuild_actor(actor, entry))

    verify = subprocess.run(
        [sys.executable, str(REPO / "tools" / "asset_pipeline.py"), "verify"],
        cwd=REPO, capture_output=True, text=True,
    )
    print(verify.stdout.strip())
    if verify.returncode != 0:
        print("[rebuild] GATES FAILED")
        return 1

    if not args.skip_godot:
        cache = REPO / ".godot" / "imported"
        if cache.exists():
            shutil.rmtree(cache)
            print("[rebuild] purged .godot/imported")
        subprocess.run([str(GODOT), "--headless", "--path", str(REPO), "--import"], cwd=REPO, capture_output=True, text=True)
        print("[rebuild] re-imported in Godot")

    print(json.dumps(summary, indent=2, ensure_ascii=False))
    print("[rebuild] done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
