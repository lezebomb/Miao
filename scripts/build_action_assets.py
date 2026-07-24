#!/usr/bin/env python3
"""Build Miaomiao action assets without crossfading complete cat images.

Every emitted frame is either an untouched, validated atlas keyframe or an
independently drawn pose placed in ``pet/miaomiao/pose-sources/<action>``.
This file intentionally contains no alpha-blend, tween, optical-flow, or
whole-sprite interpolation path.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

CELL_W, CELL_H = 192, 208

ACTIONS = {
    "idle": {
        "row": 0,
        "source_frames": 6,
        "duration_ms": 155,
        "loop": True,
        "target_range": [8, 10],
    },
    "running-right": {
        "row": 1,
        "source_frames": 8,
        "duration_ms": 85,
        "loop": True,
        "target_range": [8, 12],
    },
    "running-left": {
        "row": 2,
        "source_frames": 8,
        "duration_ms": 85,
        "loop": True,
        "target_range": [8, 12],
    },
    "roll": {
        "row": 5,
        "source_frames": 8,
        "duration_ms": 120,
        "loop": False,
        "target_range": [14, 20],
    },
    "knead": {
        "row": 7,
        "source_frames": 6,
        "duration_ms": 115,
        "loop": True,
        "target_range": [12, 16],
    },
    "wash-face": {
        "row": 8,
        "source_frames": 6,
        "duration_ms": 130,
        "loop": False,
        "target_range": [12, 16],
    },
}


def extract_row(atlas: Image.Image, row: int, count: int) -> list[Image.Image]:
    """Extract original cells byte-for-pixel; never blend or resample them."""
    return [
        atlas.crop(
            (
                column * CELL_W,
                row * CELL_H,
                (column + 1) * CELL_W,
                (row + 1) * CELL_H,
            )
        )
        for column in range(count)
    ]


def load_independent_poses(directory: Path) -> list[Image.Image]:
    paths = sorted(directory.glob("*.png"))
    frames: list[Image.Image] = []
    for path in paths:
        with Image.open(path) as opened:
            frame = opened.convert("RGBA")
        if frame.size != (CELL_W, CELL_H):
            raise ValueError(
                f"Independent pose {path} must be {CELL_W}x{CELL_H}; got {frame.size}"
            )
        frames.append(frame)
    return frames


def alpha_centroid(frame: Image.Image) -> tuple[float, float]:
    alpha = np.asarray(frame.getchannel("A"), dtype=np.float32)
    total = float(alpha.sum())
    if total <= 0:
        return CELL_W / 2, CELL_H / 2
    yy, xx = np.indices(alpha.shape, dtype=np.float32)
    return float((xx * alpha).sum() / total), float((yy * alpha).sum() / total)


def erode(mask: np.ndarray, iterations: int) -> np.ndarray:
    result = mask.copy()
    for _ in range(iterations):
        padded = np.pad(result, 1, constant_values=False)
        result = (
            padded[1:-1, 1:-1]
            & padded[:-2, 1:-1]
            & padded[2:, 1:-1]
            & padded[1:-1, :-2]
            & padded[1:-1, 2:]
        )
    return result


def connected_component_areas(mask: np.ndarray) -> list[int]:
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    areas: list[int] = []
    for y, x in np.argwhere(mask):
        if visited[y, x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(y), int(x))])
        visited[y, x] = True
        area = 0
        while queue:
            cy, cx = queue.popleft()
            area += 1
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if (
                    0 <= ny < height
                    and 0 <= nx < width
                    and mask[ny, nx]
                    and not visited[ny, nx]
                ):
                    visited[ny, nx] = True
                    queue.append((ny, nx))
        areas.append(area)
    return sorted(areas, reverse=True)


def frame_quality(frame: Image.Image) -> dict:
    alpha = np.asarray(frame.getchannel("A"), dtype=np.uint8)
    visible = alpha >= 16
    opaque = alpha >= 245
    interior = erode(visible, 4)
    semi = (alpha >= 16) & (alpha < 245)
    internal_semi = semi & interior
    boundary = visible & ~erode(visible, 1)
    components = connected_component_areas(opaque)
    main_component = components[0] if components else 0
    significant_components = [
        area for area in components if main_component and area >= main_component * 0.02
    ]
    visible_area = int(visible.sum())
    internal_count = int(internal_semi.sum())
    return {
        "visibleArea": visible_area,
        "opaqueArea": int(opaque.sum()),
        "semiTransparentPixels": int(semi.sum()),
        "internalSemiTransparentPixels": internal_count,
        "internalSemiTransparentRatio": round(
            internal_count / max(1, int(interior.sum())), 6
        ),
        "contourPixels": int(boundary.sum()),
        "contourToAreaRatio": round(int(boundary.sum()) / max(1, visible_area), 6),
        "opaqueComponentAreas": components[:6],
        "significantOpaqueComponents": len(significant_components),
    }


def action_validation(frames: list[Image.Image], target_range: list[int]) -> dict:
    boxes: list[tuple[int, int, int, int]] = []
    centroids: list[tuple[float, float]] = []
    frame_metrics: list[dict] = []
    for frame in frames:
        if frame.mode != "RGBA" or frame.size != (CELL_W, CELL_H):
            raise ValueError(f"Invalid frame geometry: mode={frame.mode}, size={frame.size}")
        box = frame.getchannel("A").getbbox()
        if box is None:
            raise ValueError("Animation contains an empty frame")
        boxes.append(box)
        centroids.append(alpha_centroid(frame))
        frame_metrics.append(frame_quality(frame))

    areas = np.asarray([metric["visibleArea"] for metric in frame_metrics], dtype=float)
    contours = np.asarray(
        [metric["contourToAreaRatio"] for metric in frame_metrics], dtype=float
    )
    median_area = float(np.median(areas))
    median_contour = float(np.median(contours))
    area_ratios = areas / max(1.0, median_area)
    abnormal_area = [
        index for index, ratio in enumerate(area_ratios) if ratio > 1.38
    ]
    internal_semi = [
        index
        for index, metric in enumerate(frame_metrics)
        if metric["internalSemiTransparentRatio"] > 0.01
    ]
    doubled_contour = [
        index
        for index, metric in enumerate(frame_metrics)
        if (
            metric["significantOpaqueComponents"] > 2
            or (
                metric["contourToAreaRatio"] > median_contour * 1.45
                and metric["visibleArea"] > median_area * 1.12
            )
        )
    ]
    ghosting_failures = sorted(set(internal_semi + doubled_contour))

    widths = [box[2] - box[0] for box in boxes]
    heights = [box[3] - box[1] for box in boxes]
    return {
        "frameCount": len(frames),
        "targetFrameRange": target_range,
        "targetFrameCountReached": target_range[0] <= len(frames) <= target_range[1],
        "size": [CELL_W, CELL_H],
        "mode": "RGBA",
        "boundingWidth": {"min": min(widths), "max": max(widths)},
        "boundingHeight": {"min": min(heights), "max": max(heights)},
        "centroidX": {
            "min": round(min(point[0] for point in centroids), 2),
            "max": round(max(point[0] for point in centroids), 2),
        },
        "centroidY": {
            "min": round(min(point[1] for point in centroids), 2),
            "max": round(max(point[1] for point in centroids), 2),
        },
        "ghostingChecks": {
            "largeInternalSemiTransparencyFrames": internal_semi,
            "abnormalSilhouetteExpansionFrames": abnormal_area,
            "doubleContourHeuristicFrames": doubled_contour,
            "combinedGhostingFailureFrames": ghosting_failures,
            "verdict": "fail" if ghosting_failures else "pass",
            "method": (
                "interior-alpha + robust silhouette-area + opaque-component/"
                "contour-density heuristics"
            ),
        },
        "frames": frame_metrics,
    }


def composite_on(frame: Image.Image, color: tuple[int, int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", frame.size, color)
    canvas.alpha_composite(frame)
    return canvas


def checker_frame(frame: Image.Image) -> Image.Image:
    checker = Image.new("RGBA", frame.size, (245, 245, 245, 255))
    draw = ImageDraw.Draw(checker)
    block = 16
    for y in range(0, CELL_H, block):
        for x in range(0, CELL_W, block):
            if (x // block + y // block) % 2:
                draw.rectangle(
                    (x, y, x + block - 1, y + block - 1),
                    fill=(224, 224, 224, 255),
                )
    checker.alpha_composite(frame)
    return checker


def save_gif(
    frames: list[Image.Image],
    path: Path,
    duration_ms: int,
    background: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rendered: list[Image.Image] = []
    for frame in frames:
        if background == "black":
            composed = composite_on(frame, (0, 0, 0, 255))
        elif background == "white":
            composed = composite_on(frame, (255, 255, 255, 255))
        else:
            composed = checker_frame(frame)
        rendered.append(composed.convert("P", palette=Image.Palette.ADAPTIVE))
    rendered[0].save(
        path,
        save_all=True,
        append_images=rendered[1:],
        duration=duration_ms,
        loop=0,
        disposal=2,
        optimize=False,
    )


def save_contact_sheet(
    action_frames: dict[str, list[Image.Image]], output: Path, background: str
) -> None:
    names = list(action_frames)
    columns = 8
    label_h = 30
    rows_per_action = {
        name: (len(action_frames[name]) + columns - 1) // columns for name in names
    }
    height = sum(label_h + rows_per_action[name] * CELL_H for name in names)
    sheet = Image.new("RGBA", (columns * CELL_W, height), "#17191d")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    y = 0
    for name in names:
        draw.text(
            (8, y + 8),
            f"{name} - {len(action_frames[name])} independent frames",
            fill="white",
            font=font,
        )
        y += label_h
        for index, frame in enumerate(action_frames[name]):
            x = (index % columns) * CELL_W
            frame_y = y + (index // columns) * CELL_H
            if background == "black":
                rendered = composite_on(frame, (0, 0, 0, 255))
            elif background == "white":
                rendered = composite_on(frame, (255, 255, 255, 255))
            else:
                rendered = checker_frame(frame)
            sheet.alpha_composite(rendered, (x, frame_y))
        y += rows_per_action[name] * CELL_H
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(output, quality=94)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas", type=Path, default=Path("pet/miaomiao/spritesheet.webp"))
    parser.add_argument("--output-root", type=Path, default=Path("pet/miaomiao/actions"))
    parser.add_argument(
        "--pose-sources-root",
        type=Path,
        default=Path("pet/miaomiao/pose-sources"),
    )
    parser.add_argument("--preview-root", type=Path, default=Path("previews/actions-v2"))
    parser.add_argument(
        "--visual-verdict",
        choices=("pending_manual_review", "pass", "fail"),
        default="pending_manual_review",
    )
    parser.add_argument(
        "--visual-note",
        default="Black/white previews require explicit visual inspection.",
    )
    args = parser.parse_args()

    with Image.open(args.atlas) as opened:
        atlas = opened.convert("RGBA")
    if atlas.size != (1536, 2288):
        raise SystemExit(f"Expected 1536x2288 v2 atlas, got {atlas.size}")

    built: dict[str, list[Image.Image]] = {}
    action_manifest: dict[str, dict] = {}
    provenance: dict[str, str] = {}
    for name, spec in ACTIONS.items():
        independent_dir = args.pose_sources_root / name
        independent = (
            load_independent_poses(independent_dir) if independent_dir.exists() else []
        )
        if independent:
            frames = independent
            source_kind = "independently-drawn-poses"
            source_path = independent_dir.as_posix()
        else:
            frames = extract_row(atlas, spec["row"], spec["source_frames"])
            source_kind = "original-clean-atlas-keyframes"
            source_path = f"{args.atlas.as_posix()}#row-{spec['row']}"
        provenance[name] = source_path
        built[name] = frames

        action_dir = args.output_root / name
        action_dir.mkdir(parents=True, exist_ok=True)
        for stale in action_dir.glob("frame-*.png"):
            stale.unlink()
        relative_frames: list[str] = []
        for index, frame in enumerate(frames):
            path = action_dir / f"frame-{index:02d}.png"
            frame.save(path, optimize=True)
            relative_frames.append(path.relative_to(args.output_root.parent).as_posix())

        for background in ("checker", "black", "white"):
            target = (
                args.preview_root / f"{name}.gif"
                if background == "checker"
                else args.preview_root / background / f"{name}.gif"
            )
            save_gif(frames, target, spec["duration_ms"], background)

        action_manifest[name] = {
            "frames": relative_frames,
            "frameDurationMs": spec["duration_ms"],
            "loop": spec["loop"],
            "sourceAtlasRow": spec["row"],
            "sourceFrameCount": spec["source_frames"],
            "frameGeneration": source_kind,
            "source": source_path,
            "crossfadeInterpolation": False,
        }

    manifest = {
        "formatVersion": 2,
        "cell": {"width": CELL_W, "height": CELL_H},
        "actions": action_manifest,
        "events": {
            "petOrHover": {"random": ["roll", "knead"], "weights": [0.5, 0.5]},
            "dragLeft": "running-left",
            "dragRight": "running-right",
            "idle": {
                "default": "idle",
                "random": [{"action": "wash-face", "weight": 0.12}],
                "specialCooldownMs": [35000, 65000],
            },
        },
    }
    manifest_path = args.output_root.parent / "behavior.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    contact_paths = {}
    for background in ("checker", "black", "white"):
        filename = (
            "contact-sheet.jpg"
            if background == "checker"
            else f"contact-sheet-{background}.jpg"
        )
        path = args.preview_root / filename
        save_contact_sheet(built, path, background)
        contact_paths[background] = path.as_posix()

    validations = {
        name: action_validation(frames, ACTIONS[name]["target_range"])
        for name, frames in built.items()
    }
    deterministic_ok = all(
        result["ghostingChecks"]["verdict"] == "pass"
        for result in validations.values()
    )
    overall_ok = deterministic_ok and args.visual_verdict == "pass"
    validation = {
        "ok": overall_ok,
        "deterministicChecksPassed": deterministic_ok,
        "identitySource": args.atlas.as_posix(),
        "frameProvenance": provenance,
        "generationPolicy": {
            "crossfadeDisabled": True,
            "wholeSpriteAlphaBlendDisabled": True,
            "tweenLoopDisabled": True,
            "acceptedFrames": [
                "original clean atlas keyframes",
                "independently drawn complete poses",
            ],
        },
        "sourceVideoReferences": [
            "references/videos/撒娇打滚.mp4",
            "references/videos/踩奶.mp4",
            "references/videos/躺着用爪子洗脸.mp4",
        ],
        "actions": validations,
        "visualReview": {
            "contactSheets": contact_paths,
            "gifDirectories": {
                "checker": args.preview_root.as_posix(),
                "black": (args.preview_root / "black").as_posix(),
                "white": (args.preview_root / "white").as_posix(),
            },
            "verdict": args.visual_verdict,
            "note": args.visual_note,
            "automaticPassForbidden": True,
        },
    }
    (args.preview_root / "validation.json").write_text(
        json.dumps(validation, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(manifest_path.resolve())


if __name__ == "__main__":
    main()
