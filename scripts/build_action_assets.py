#!/usr/bin/env python3
"""Build Miaomiao actions exclusively from independent opaque poses.

Whole-character alpha blending/crossfading is deliberately unsupported.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

CELL_W, CELL_H = 192, 208
ROLL_DURATIONS = [
    340, 320, 300, 280, 260, 240, 210, 190, 350,
    350, 260, 240, 260, 300, 340, 360, 340, 260,
]
KNEAD_DURATIONS = [140, 120, 140, 170, 200, 150, 120, 140, 170, 200, 180, 150]
WASH_FACE_DURATIONS = [300, 320, 360, 420, 450, 380, 300, 320, 360, 420, 450, 380]
KNEAD_OUTRO_DURATIONS = [120, 180, 180, 120]

ACTIONS = {
    "idle": {"atlas": (0, 6), "durations": [1000] * 6, "loop": False},
    "running-right": {"atlas": (1, 8), "durations": [105] * 8, "loop": True},
    "running-left": {"atlas": (2, 8), "durations": [105] * 8, "loop": True},
    "roll": {
        "poses": 18,
        "durations": ROLL_DURATIONS,
        "loop": False,
        "maxExpansion": 2.3,
    },
    "knead": {"poses": 12, "durations": KNEAD_DURATIONS, "loop": False, "repeat": 3},
    "wash-face": {"poses": 12, "durations": WASH_FACE_DURATIONS, "loop": False},
}


def atlas_frames(atlas: Image.Image, row: int, count: int) -> list[Image.Image]:
    return [
        atlas.crop((i * CELL_W, row * CELL_H, (i + 1) * CELL_W, (row + 1) * CELL_H))
        for i in range(count)
    ]


def pose_frames(root: Path, name: str, count: int) -> list[Image.Image]:
    frames = []
    for index in range(count):
        path = root / name / f"pose-{index:02d}.png"
        if not path.is_file():
            raise SystemExit(f"Missing independent pose: {path}")
        with Image.open(path) as opened:
            frame = opened.convert("RGBA")
        if frame.size != (CELL_W, CELL_H):
            raise SystemExit(f"Wrong pose size {frame.size}: {path}")
        frames.append(frame)
    return frames


def transition_toward_idle(
    frame: Image.Image,
    idle: Image.Image,
    fraction: float,
) -> Image.Image:
    """Scale one opaque pose toward idle size without blending silhouettes."""
    source_box = frame.getchannel("A").getbbox()
    idle_box = idle.getchannel("A").getbbox()
    if source_box is None or idle_box is None:
        raise ValueError("Cannot build transition from an empty frame")
    crop = frame.crop(source_box)
    source_height = source_box[3] - source_box[1]
    idle_height = idle_box[3] - idle_box[1]
    target_height = round(source_height + (idle_height - source_height) * fraction)
    scale = target_height / crop.height
    size = (max(1, round(crop.width * scale)), max(1, target_height))
    resized = crop.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CELL_W, CELL_H))
    x = (CELL_W - size[0]) // 2
    y = CELL_H - size[1] - 4
    canvas.alpha_composite(resized, (x, y))
    return canvas


def render_background(frame: Image.Image, color: str) -> Image.Image:
    background = Image.new("RGBA", frame.size, color)
    background.alpha_composite(frame)
    return background.convert("P", palette=Image.Palette.ADAPTIVE)


def save_gif(frames: list[Image.Image], durations: list[int], path: Path, color: str) -> None:
    rendered = [render_background(frame, color) for frame in frames]
    path.parent.mkdir(parents=True, exist_ok=True)
    rendered[0].save(
        path, save_all=True, append_images=rendered[1:], duration=durations,
        loop=0, disposal=2, optimize=False,
    )


def save_contact_sheet(actions: dict[str, list[Image.Image]], path: Path, color: str) -> None:
    columns, label_h = 10, 26
    rows = sum((len(frames) + columns - 1) // columns for frames in actions.values())
    sheet = Image.new("RGBA", (columns * CELL_W, rows * CELL_H + len(actions) * label_h), color)
    draw, font, y = ImageDraw.Draw(sheet), ImageFont.load_default(), 0
    for name, frames in actions.items():
        draw.text((8, y + 7), f"{name}: {len(frames)} independent poses", fill="white" if color == "black" else "black", font=font)
        y += label_h
        for index, frame in enumerate(frames):
            x = (index % columns) * CELL_W
            fy = y + (index // columns) * CELL_H
            sheet.alpha_composite(frame, (x, fy))
            number_color = "white" if color == "black" else "black"
            draw.rectangle((x + 4, fy + 4, x + 31, fy + 22), fill=color)
            draw.text((x + 8, fy + 6), f"{index:02d}", fill=number_color, font=font)
        y += ((len(frames) + columns - 1) // columns) * CELL_H
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path, quality=94)


def component_areas(mask: np.ndarray) -> list[int]:
    seen = np.zeros(mask.shape, dtype=bool)
    height, width = mask.shape
    result: list[int] = []
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        queue = deque([(int(sy), int(sx))])
        seen[sy, sx] = True
        area = 0
        while queue:
            y, x = queue.popleft()
            area += 1
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        result.append(area)
    return sorted(result, reverse=True)


def validate_action(
    frames: list[Image.Image],
    durations: list[int],
    repeat: int,
    max_expansion: float = 1.55,
) -> dict:
    areas, semi_ratios, significant_components = [], [], []
    for frame in frames:
        alpha = np.asarray(frame.getchannel("A"), dtype=np.uint8)
        mask = alpha >= 32
        area = int(mask.sum())
        if area == 0:
            raise ValueError("Empty animation frame")
        areas.append(area)
        interior = alpha >= 32
        semi_ratios.append(float(((alpha >= 32) & (alpha <= 220)).sum()) / area)
        components = component_areas(mask)
        significant_components.append(sum(value >= area * 0.02 for value in components))
        boundary = np.concatenate((alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]))
        if int(boundary.max()) != 0:
            raise ValueError("Character touches frame boundary")
    median_area = float(np.median(areas))
    expansion = max(areas) / median_area
    semi_max = max(semi_ratios)
    component_max = max(significant_components)
    warnings: list[str] = []
    if semi_max > 0.08:
        warnings.append("large interior semi-transparent region")
    if expansion > max_expansion:
        warnings.append("silhouette area expands abnormally")
    if component_max > 1:
        warnings.append("multiple large disconnected contours")
    return {
        "frameCount": len(frames),
        "singleCycleDurationMs": sum(durations),
        "repeatCount": repeat,
        "effectivePlaybackDurationMs": sum(durations) * repeat,
        "maxInteriorSemiTransparentRatio": round(semi_max, 5),
        "maxSilhouetteAreaVsMedian": round(expansion, 4),
        "maxAllowedSilhouetteAreaVsMedian": max_expansion,
        "maxSignificantContourCount": component_max,
        "ghostingHeuristicsPassed": not warnings,
        "warnings": warnings,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--atlas",
        type=Path,
        default=Path("legacy/codex-native/pet/miaomiao/spritesheet.webp"),
    )
    parser.add_argument("--pose-root", type=Path, default=Path("pet/miaomiao/pose-sources"))
    parser.add_argument("--output-root", type=Path, default=Path("pet/miaomiao/actions"))
    parser.add_argument("--preview-root", type=Path, default=Path("previews/actions-v3"))
    parser.add_argument("--visual-verdict", choices=("pending_manual_review", "pass", "fail"), default="pending_manual_review")
    args = parser.parse_args()

    with Image.open(args.atlas) as opened:
        atlas = opened.convert("RGBA")
    if atlas.size != (1536, 2288):
        raise SystemExit(f"Expected 1536x2288 atlas, got {atlas.size}")
    idle_return = atlas_frames(atlas, 0, 1)[0]

    built: dict[str, list[Image.Image]] = {}
    manifest_actions: dict[str, dict] = {}
    validation_actions: dict[str, dict] = {}
    for name, spec in ACTIONS.items():
        if "poses" in spec:
            frames = pose_frames(args.pose_root, name, spec["poses"])
            durations = list(spec["durations"])
            provenance = "independently-drawn-pose-sheet"
        else:
            frames = atlas_frames(atlas, *spec["atlas"])
            durations = list(spec["durations"])
            provenance = "clean-original-atlas-keyframes"
        if name == "roll":
            frames[-2] = transition_toward_idle(frames[-2], idle_return, 0.55)
            frames[-1] = idle_return.copy()
            provenance = "independent-poses-with-two-frame-idle-return"
        elif name == "knead":
            frames[-1] = frames[0].copy()
            provenance = "independent-poses-with-closed-support-cycle"
        elif name == "wash-face":
            roll_transitions = pose_frames(args.pose_root, "roll", 18)
            frames.extend([
                transition_toward_idle(roll_transitions[16], idle_return, 0.6),
                idle_return.copy(),
            ])
            durations.extend([300, 240])
            provenance = "independent-poses-with-two-frame-idle-return"
        repeat = int(spec.get("repeat", 1))
        built[name] = frames
        action_dir = args.output_root / name
        action_dir.mkdir(parents=True, exist_ok=True)
        for old in action_dir.glob("frame-*.png"):
            old.unlink()
        paths = []
        for index, frame in enumerate(frames):
            path = action_dir / f"frame-{index:02d}.png"
            frame.save(path, optimize=True)
            paths.append(path.relative_to(args.output_root.parent).as_posix())

        preview_frames = frames * repeat
        preview_durations = durations * repeat
        if name == "knead":
            knead_preview_roll = pose_frames(args.pose_root, "roll", 18)
            preview_frames.extend([
                frames[0],
                transition_toward_idle(knead_preview_roll[15], idle_return, 0.75),
                transition_toward_idle(knead_preview_roll[16], idle_return, 0.75),
                idle_return.copy(),
            ])
            preview_durations.extend(KNEAD_OUTRO_DURATIONS)
        save_gif(preview_frames, preview_durations, args.preview_root / "black" / f"{name}.gif", "black")
        save_gif(preview_frames, preview_durations, args.preview_root / "white" / f"{name}.gif", "white")
        save_gif(
            preview_frames,
            [duration * 2 for duration in preview_durations],
            args.preview_root / "black-0.5x" / f"{name}.gif",
            "black",
        )
        save_gif(
            preview_frames,
            [duration * 2 for duration in preview_durations],
            args.preview_root / "white-0.5x" / f"{name}.gif",
            "white",
        )
        manifest_actions[name] = {
            "frames": paths,
            "frameDurationMs": durations[0],
            "frameDurationsMs": durations,
            "repeatCount": repeat,
            "loop": bool(spec["loop"]),
            "frameProvenance": provenance,
            "interpolation": "none-independent-poses-only",
        }
        validation_actions[name] = validate_action(
            frames,
            durations,
            repeat,
            float(spec.get("maxExpansion", 1.55)),
        )
        if name == "knead":
            validation_actions[name]["outroDurationMs"] = sum(KNEAD_OUTRO_DURATIONS)
            validation_actions[name]["effectivePlaybackDurationMs"] += sum(KNEAD_OUTRO_DURATIONS)

    raw_roll_transitions = pose_frames(args.pose_root, "roll", 18)
    knead_outro_frames = [
        built["knead"][0],
        transition_toward_idle(raw_roll_transitions[15], idle_return, 0.75),
        transition_toward_idle(raw_roll_transitions[16], idle_return, 0.75),
        idle_return.copy(),
    ]
    built["knead-outro"] = knead_outro_frames
    knead_outro_dir = args.output_root / "knead-outro"
    knead_outro_dir.mkdir(parents=True, exist_ok=True)
    for old in knead_outro_dir.glob("frame-*.png"):
        old.unlink()
    knead_outro_paths = []
    for index, frame in enumerate(knead_outro_frames):
        path = knead_outro_dir / f"frame-{index:02d}.png"
        frame.save(path, optimize=True)
        knead_outro_paths.append(path.relative_to(args.output_root.parent).as_posix())
    save_contact_sheet(built, args.preview_root / "contact-sheet-black.jpg", "black")
    save_contact_sheet(built, args.preview_root / "contact-sheet-white.jpg", "white")

    idle_frames = manifest_actions["idle"]["frames"]
    manifest_actions["idle"] = {
        **manifest_actions["idle"],
        "frames": [idle_frames[0]],
        "frameDurationMs": 1000,
        "frameDurationsMs": [1000],
    }
    manifest_actions.update({
        "blink": {
            "frames": [idle_frames[0], idle_frames[1], idle_frames[2]],
            "frameDurationMs": 180,
            "frameDurationsMs": [180, 260, 180],
            "repeatCount": 1,
            "loop": False,
            "frameProvenance": "clean-original-atlas-keyframes",
            "interpolation": "none-independent-poses-only",
        },
        "look-aside": {
            "frames": [idle_frames[0], idle_frames[3], idle_frames[5]],
            "frameDurationMs": 300,
            "frameDurationsMs": [300, 850, 350],
            "repeatCount": 1,
            "loop": False,
            "frameProvenance": "clean-original-atlas-keyframes",
            "interpolation": "none-independent-poses-only",
        },
        "ear-twitch": {
            "frames": [idle_frames[0], idle_frames[2], idle_frames[0]],
            "frameDurationMs": 220,
            "frameDurationsMs": [220, 280, 220],
            "repeatCount": 1,
            "loop": False,
            "frameProvenance": "clean-original-atlas-keyframes",
            "interpolation": "none-independent-poses-only",
        },
        "tail-sway": {
            "frames": [idle_frames[0], idle_frames[5], idle_frames[2], idle_frames[0]],
            "frameDurationMs": 300,
            "frameDurationsMs": [300, 450, 450, 300],
            "repeatCount": 1,
            "loop": False,
            "frameProvenance": "clean-original-atlas-keyframes",
            "interpolation": "none-independent-poses-only",
        },
        "knead-outro": {
            "frames": knead_outro_paths,
            "frameDurationMs": KNEAD_OUTRO_DURATIONS[0],
            "frameDurationsMs": KNEAD_OUTRO_DURATIONS,
            "repeatCount": 1,
            "loop": False,
            "frameProvenance": "independent-poses-with-two-frame-idle-return",
            "interpolation": "none-independent-poses-only",
        },
    })
    manifest_actions["knead"]["outroAction"] = "knead-outro"

    manifest = {
        "formatVersion": 2,
        "cell": {"width": CELL_W, "height": CELL_H},
        "actions": manifest_actions,
        "events": {
            "petOrHover": {
                "random": ["roll", "knead"], "weights": [0.5, 0.5],
                "ignoreWhilePlaying": True,
            },
            "dragLeft": "running-left",
            "dragRight": "running-right",
            "idle": {
                "default": "idle",
                "microActions": [
                    {"action": "blink", "weight": 0.4},
                    {"action": "look-aside", "weight": 0.25},
                    {"action": "ear-twitch", "weight": 0.2},
                    {"action": "tail-sway", "weight": 0.15},
                ],
                "random": [{"action": "wash-face", "weight": 0.3}],
                "specialCheckIntervalMs": [30000, 60000],
            },
        },
    }
    behavior_path = args.output_root.parent / "behavior.json"
    behavior_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    timing_ok = (
        18 <= len(built["roll"]) <= 22
        and 5000 <= validation_actions["roll"]["effectivePlaybackDurationMs"] <= 6000
        and 10 <= len(built["knead"]) <= 12
        and validation_actions["knead"]["repeatCount"] == 3
        and 1700 <= validation_actions["knead"]["singleCycleDurationMs"] <= 2100
        and 5100 <= validation_actions["knead"]["effectivePlaybackDurationMs"] <= 6300
        and 10 <= len(built["wash-face"]) <= 14
        and 4000 <= validation_actions["wash-face"]["effectivePlaybackDurationMs"] <= 6000
    )
    heuristics_ok = all(item["ghostingHeuristicsPassed"] for item in validation_actions.values())
    validation = {
        "ok": timing_ok and heuristics_ok and args.visual_verdict == "pass",
        "generationPolicy": {
            "wholeCharacterCrossfade": "forbidden",
            "premultipliedBlend": "not implemented",
            "allOutputFrames": "independent opaque poses or clean original keyframes",
        },
        "timingRequirementsPassed": timing_ok,
        "ghostingHeuristicsPassed": heuristics_ok,
        "actions": validation_actions,
        "previews": {
            "black": (args.preview_root / "black").as_posix(),
            "white": (args.preview_root / "white").as_posix(),
            "blackHalfSpeed": (args.preview_root / "black-0.5x").as_posix(),
            "whiteHalfSpeed": (args.preview_root / "white-0.5x").as_posix(),
            "contactSheetBlack": (args.preview_root / "contact-sheet-black.jpg").as_posix(),
            "contactSheetWhite": (args.preview_root / "contact-sheet-white.jpg").as_posix(),
        },
        "visualReview": {
            "verdict": args.visual_verdict,
            "note": "Verdict is never auto-promoted to pass; inspect both background previews before selecting pass.",
        },
    }
    (args.preview_root / "validation.json").write_text(
        json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(behavior_path.resolve())


if __name__ == "__main__":
    main()
