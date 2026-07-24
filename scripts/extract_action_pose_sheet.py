#!/usr/bin/env python3
"""Extract independently drawn poses from a transparent image-generation sheet.

The script performs only per-pose crop, one shared scale, placement, and an
optional horizontal mirror. It never mixes pixels from two animation poses.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

CELL_W, CELL_H = 192, 208


def slot_bounds(length: int, index: int, slots: int) -> tuple[int, int]:
    return round(index * length / slots), round((index + 1) * length / slots)


def dynamic_column_boundaries(
    row_image: Image.Image, columns: int, threshold: int = 16
) -> list[int]:
    """Locate the widest transparent gutter near every expected column break."""
    alpha = np.asarray(row_image.getchannel("A"), dtype=np.uint8)
    occupied = (alpha >= threshold).any(axis=0)
    width = row_image.width
    nominal = width / columns
    boundaries = [0]
    for index in range(1, columns):
        expected = round(index * nominal)
        search_left = max(boundaries[-1] + round(nominal * 0.45), round(expected - nominal * 0.38))
        search_right = min(
            width - round((columns - index) * nominal * 0.45),
            round(expected + nominal * 0.38),
        )
        candidates: list[tuple[float, int]] = []
        run_start: int | None = None
        for x in range(search_left, search_right + 1):
            if not occupied[x] and run_start is None:
                run_start = x
            if (occupied[x] or x == search_right) and run_start is not None:
                run_end = x if occupied[x] else x + 1
                midpoint = (run_start + run_end) // 2
                run_length = run_end - run_start
                score = run_length - abs(midpoint - expected) * 0.03
                candidates.append((score, midpoint))
                run_start = None
        if candidates:
            boundary = max(candidates)[1]
        else:
            projection = (alpha[:, search_left : search_right + 1] >= threshold).sum(axis=0)
            minimum = int(projection.min())
            minima = np.where(projection == minimum)[0] + search_left
            boundary = int(min(minima, key=lambda value: abs(int(value) - expected)))
        boundaries.append(boundary)
    boundaries.append(width)
    return boundaries


def visible_bbox(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
    yy, xx = np.where(alpha >= threshold)
    if len(xx) == 0:
        raise ValueError("Pose slot is empty")
    return int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1


def clear_hidden_rgb(image: Image.Image) -> Image.Image:
    array = np.asarray(image, dtype=np.uint8).copy()
    array[array[..., 3] == 0, :3] = 0
    return Image.fromarray(array, "RGBA")


def keep_largest_silhouette(image: Image.Image, threshold: int = 16) -> Image.Image:
    """Discard gutter fragments while keeping the one complete cat silhouette."""
    array = np.asarray(image, dtype=np.uint8).copy()
    mask = array[..., 3] >= threshold
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    components: list[list[tuple[int, int]]] = []
    for y, x in np.argwhere(mask):
        y, x = int(y), int(x)
        if visited[y, x]:
            continue
        visited[y, x] = True
        queue: deque[tuple[int, int]] = deque([(y, x)])
        component: list[tuple[int, int]] = []
        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if (
                    0 <= ny < height
                    and 0 <= nx < width
                    and mask[ny, nx]
                    and not visited[ny, nx]
                ):
                    visited[ny, nx] = True
                    queue.append((ny, nx))
        components.append(component)
    if not components:
        raise ValueError("Pose contains no visible silhouette")
    largest = max(components, key=len)
    keep = np.zeros_like(mask, dtype=bool)
    yy, xx = zip(*largest)
    keep[np.asarray(yy), np.asarray(xx)] = True
    array[~keep] = 0
    return Image.fromarray(array, "RGBA")


def extract_slots(
    sheet: Image.Image, columns: int, rows: int, count: int
) -> tuple[list[Image.Image], list[dict]]:
    frames: list[Image.Image] = []
    metadata: list[dict] = []
    for row in range(rows):
        top, bottom = slot_bounds(sheet.height, row, rows)
        row_image = sheet.crop((0, top, sheet.width, bottom))
        boundaries = dynamic_column_boundaries(row_image, columns)
        for column in range(columns):
            index = row * columns + column
            if index >= count:
                break
            left, right = boundaries[column], boundaries[column + 1]
            slot = sheet.crop((left, top, right, bottom))
            box = visible_bbox(slot)
            pose = slot.crop(box)
            pose = keep_largest_silhouette(clear_hidden_rgb(pose))
            box_after_cleanup = visible_bbox(pose)
            pose = pose.crop(box_after_cleanup)
            frames.append(clear_hidden_rgb(pose))
            metadata.append(
                {
                    "index": index,
                    "sourceSlot": [left, top, right, bottom],
                    "sourceVisibleBox": list(box),
                    "sourcePoseSize": list(pose.size),
                }
            )
    if len(frames) != count:
        raise ValueError(f"Expected {count} poses, extracted {len(frames)}")
    return frames, metadata


def normalize(
    poses: list[Image.Image], anchor: str, margin: int
) -> tuple[list[Image.Image], float]:
    max_width = max(pose.width for pose in poses)
    max_height = max(pose.height for pose in poses)
    scale = min(
        (CELL_W - margin * 2) / max_width,
        (CELL_H - margin * 2) / max_height,
    )
    result: list[Image.Image] = []
    for pose in poses:
        size = (
            max(1, round(pose.width * scale)),
            max(1, round(pose.height * scale)),
        )
        resized = pose.resize(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (CELL_W, CELL_H))
        x = (CELL_W - size[0]) // 2
        if anchor == "bottom":
            y = CELL_H - margin - size[1]
        else:
            y = (CELL_H - size[1]) // 2
        canvas.alpha_composite(resized, (x, y))
        result.append(clear_hidden_rgb(canvas))
    return result, scale


def write_frames(frames: list[Image.Image], directory: Path) -> list[str]:
    directory.mkdir(parents=True, exist_ok=True)
    for stale in directory.glob("*.png"):
        stale.unlink()
    paths: list[str] = []
    for index, frame in enumerate(frames):
        path = directory / f"pose-{index:02d}.png"
        frame.save(path, optimize=True)
        paths.append(path.as_posix())
    return paths


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--action", required=True)
    parser.add_argument(
        "--output-root", type=Path, default=Path("pet/miaomiao/pose-sources")
    )
    parser.add_argument("--anchor", choices=("center", "bottom"), default="center")
    parser.add_argument("--margin", type=int, default=5)
    parser.add_argument(
        "--mirror-action",
        help="Also write a horizontally mirrored action with the same frame order.",
    )
    args = parser.parse_args()

    with Image.open(args.input) as opened:
        sheet = opened.convert("RGBA")
    poses, metadata = extract_slots(sheet, args.columns, args.rows, args.count)
    frames, shared_scale = normalize(poses, args.anchor, args.margin)
    paths = write_frames(frames, args.output_root / args.action)

    mirror_paths: list[str] = []
    if args.mirror_action:
        mirrored = [
            frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in frames
        ]
        mirror_paths = write_frames(
            mirrored, args.output_root / args.mirror_action
        )

    report = {
        "source": args.input.as_posix(),
        "action": args.action,
        "frameCount": len(frames),
        "grid": {"columns": args.columns, "rows": args.rows},
        "cell": [CELL_W, CELL_H],
        "anchor": args.anchor,
        "sharedScale": round(shared_scale, 8),
        "independentlyDrawnPoses": True,
        "crossfade": False,
        "wholeSpriteBlend": False,
        "frames": paths,
        "mirroredAction": args.mirror_action,
        "mirroredFrames": mirror_paths,
        "sourceSlots": metadata,
    }
    report_path = args.output_root / f"{args.action}-extraction.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(report_path.resolve())


if __name__ == "__main__":
    main()
