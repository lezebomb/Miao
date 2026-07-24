#!/usr/bin/env python3
"""Update only Codex's fixed idle and directional-running atlas rows.

Codex v2 currently consumes six idle frames, eight running-right frames, and
eight running-left frames. The richer roll/knead/wash behavior remains in
``behavior.json`` for the interactive desktop launcher because stock Codex does
not expose custom event mappings.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

CELL_W, CELL_H = 192, 208
ATLAS_SIZE = (1536, 2288)

ROW_SPECS = {
    "idle": {"row": 0, "count": 6},
    "running-right": {"row": 1, "count": 8},
    "running-left": {"row": 2, "count": 8},
}


def load_frames(directory: Path, count: int) -> list[Image.Image]:
    paths = sorted(directory.glob("pose-*.png"))
    if len(paths) < count:
        raise ValueError(f"{directory} needs at least {count} independent poses")
    frames: list[Image.Image] = []
    for path in paths[:count]:
        with Image.open(path) as opened:
            frame = opened.convert("RGBA")
        if frame.size != (CELL_W, CELL_H):
            raise ValueError(f"{path} is {frame.size}, expected {(CELL_W, CELL_H)}")
        frames.append(frame)
    return frames


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--atlas", type=Path, default=Path("pet/miaomiao/spritesheet.webp")
    )
    parser.add_argument(
        "--pose-root", type=Path, default=Path("pet/miaomiao/pose-sources")
    )
    args = parser.parse_args()

    with Image.open(args.atlas) as opened:
        atlas = opened.convert("RGBA")
    if atlas.size != ATLAS_SIZE:
        raise SystemExit(f"Expected {ATLAS_SIZE}, got {atlas.size}")

    for action, spec in ROW_SPECS.items():
        frames = load_frames(args.pose_root / action, spec["count"])
        row_top = spec["row"] * CELL_H
        atlas.paste(
            Image.new("RGBA", (CELL_W * 8, CELL_H)),
            (0, row_top),
        )
        for column, frame in enumerate(frames):
            atlas.alpha_composite(frame, (column * CELL_W, row_top))
        if action == "idle":
            # Column 6 is Codex's neutral/dead-zone cell; column 7 stays empty.
            atlas.alpha_composite(frames[0], (6 * CELL_W, row_top))

    array = np.asarray(atlas, dtype=np.uint8).copy()
    array[array[..., 3] == 0, :3] = 0
    atlas = Image.fromarray(array, "RGBA")
    atlas.save(
        args.atlas,
        "WEBP",
        lossless=True,
        quality=100,
        method=6,
        exact=True,
    )
    print(args.atlas.resolve())


if __name__ == "__main__":
    main()
