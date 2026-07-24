#!/usr/bin/env python3
"""Extract independent sprite poses from a transparent, regular-grid sheet."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

CELL = (192, 208)


def find_components(frame: Image.Image) -> list[tuple[int, tuple[int, int, int, int]]]:
    mask = np.asarray(frame.getchannel("A"), dtype=np.uint8) > 8
    seen = np.zeros(mask.shape, dtype=bool)
    height, width = mask.shape
    result: list[tuple[int, tuple[int, int, int, int]]] = []
    for y, x in zip(*np.nonzero(mask & ~seen)):
        if seen[y, x]:
            continue
        queue = deque([(int(y), int(x))])
        seen[y, x] = True
        area = 0
        min_x = max_x = int(x)
        min_y = max_y = int(y)
        while queue:
            cy, cx = queue.popleft()
            area += 1
            min_x, max_x = min(min_x, cx), max(max_x, cx)
            min_y, max_y = min(min_y, cy), max(max_y, cy)
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        if area >= 1000:
            result.append((area, (min_x, min_y, max_x + 1, max_y + 1)))
    return result


def keep_largest_component(frame: Image.Image) -> Image.Image:
    array = np.asarray(frame, dtype=np.uint8).copy()
    mask = array[..., 3] > 8
    seen = np.zeros(mask.shape, dtype=bool)
    best: list[tuple[int, int]] = []
    height, width = mask.shape
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        queue = deque([(int(sy), int(sx))])
        seen[sy, sx] = True
        current: list[tuple[int, int]] = []
        while queue:
            y, x = queue.popleft()
            current.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        if len(current) > len(best):
            best = current
    keep = np.zeros(mask.shape, dtype=bool)
    for y, x in best:
        keep[y, x] = True
    array[~keep] = 0
    return Image.fromarray(array, "RGBA")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--action", required=True)
    parser.add_argument("--output-root", type=Path, default=Path("pet/miaomiao/pose-sources"))
    parser.add_argument("--anchor", choices=("center", "bottom"), default="center")
    args = parser.parse_args()

    with Image.open(args.input) as opened:
        sheet = opened.convert("RGBA")
    components = sorted(find_components(sheet), reverse=True)[:args.count]
    if len(components) != args.count:
        raise SystemExit(f"Expected {args.count} character contours, found {len(components)}")
    boxes = [box for _, box in components]
    boxes.sort(key=lambda box: (box[1] + box[3]) / 2)
    ordered: list[tuple[int, int, int, int]] = []
    for row in range(args.rows):
        row_boxes = boxes[row * args.columns:(row + 1) * args.columns]
        ordered.extend(sorted(row_boxes, key=lambda box: (box[0] + box[2]) / 2))
    crops = [keep_largest_component(sheet.crop(box)) for box in ordered]

    scale = min(
        (CELL[0] - 8) / max(pose.width for pose in crops),
        (CELL[1] - 8) / max(pose.height for pose in crops),
    )
    target = args.output_root / args.action
    target.mkdir(parents=True, exist_ok=True)
    for index, pose in enumerate(crops):
        size = (max(1, round(pose.width * scale)), max(1, round(pose.height * scale)))
        pose = pose.resize(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", CELL)
        x = (CELL[0] - size[0]) // 2
        y = CELL[1] - size[1] - 4 if args.anchor == "bottom" else (CELL[1] - size[1]) // 2
        canvas.alpha_composite(pose, (x, y))
        canvas.save(target / f"pose-{index:02d}.png", optimize=True)
    print(f"Wrote {args.count} independent poses to {target}")


if __name__ == "__main__":
    main()
