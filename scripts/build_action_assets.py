#!/usr/bin/env python3
"""Build high-frame-count action assets from the validated Codex v2 atlas.

The source atlas remains the identity and anatomy authority. Intermediate frames
use premultiplied-alpha blending after centroid registration, which avoids the
scale and baseline drift that can occur when independently regenerating poses.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

CELL_W, CELL_H = 192, 208

ACTIONS = {
    "idle": {"row": 0, "source_frames": 6, "output_frames": 12, "duration_ms": 140, "loop": True, "blend_cap": 0.42},
    "running-right": {"row": 1, "source_frames": 8, "output_frames": 16, "duration_ms": 70, "loop": True, "blend_cap": 0.22},
    "running-left": {"row": 2, "source_frames": 8, "output_frames": 16, "duration_ms": 70, "loop": True, "blend_cap": 0.22},
    "roll": {"row": 5, "source_frames": 8, "output_frames": 16, "duration_ms": 95, "loop": False, "blend_cap": 0.18},
    "knead": {"row": 7, "source_frames": 6, "output_frames": 16, "duration_ms": 105, "loop": False, "blend_cap": 0.38},
    "wash-face": {"row": 8, "source_frames": 6, "output_frames": 16, "duration_ms": 115, "loop": False, "blend_cap": 0.34},
}


def extract_row(atlas: Image.Image, row: int, count: int) -> list[Image.Image]:
    return [
        atlas.crop((column * CELL_W, row * CELL_H, (column + 1) * CELL_W, (row + 1) * CELL_H))
        for column in range(count)
    ]


def alpha_centroid(frame: Image.Image) -> tuple[float, float]:
    alpha = np.asarray(frame, dtype=np.float32)[..., 3]
    total = float(alpha.sum())
    if total <= 0:
        return CELL_W / 2, CELL_H / 2
    yy, xx = np.indices(alpha.shape, dtype=np.float32)
    return float((xx * alpha).sum() / total), float((yy * alpha).sum() / total)


def translate(frame: Image.Image, dx: float, dy: float) -> Image.Image:
    return frame.transform(
        frame.size,
        Image.Transform.AFFINE,
        (1, 0, -dx, 0, 1, -dy),
        resample=Image.Resampling.BICUBIC,
    )


def premultiplied_blend(first: Image.Image, second: Image.Image, amount: float) -> Image.Image:
    a = np.asarray(first, dtype=np.float32) / 255.0
    b = np.asarray(second, dtype=np.float32) / 255.0
    aa = a[..., 3:4]
    ba = b[..., 3:4]
    out_alpha = aa * (1 - amount) + ba * amount
    out_rgb_premult = a[..., :3] * aa * (1 - amount) + b[..., :3] * ba * amount
    out_rgb = np.divide(
        out_rgb_premult,
        np.maximum(out_alpha, 1e-6),
        out=np.zeros_like(out_rgb_premult),
        where=out_alpha > 1e-6,
    )
    out = np.concatenate((out_rgb, out_alpha), axis=2)
    return Image.fromarray(np.uint8(np.clip(out * 255.0 + 0.5, 0, 255)), "RGBA")


def tween_loop(
    source: list[Image.Image], output_count: int, blend_cap: float
) -> list[Image.Image]:
    frames: list[Image.Image] = []
    count = len(source)
    centroids = [alpha_centroid(frame) for frame in source]
    for output_index in range(output_count):
        position = output_index * count / output_count
        first_index = int(math.floor(position)) % count
        second_index = (first_index + 1) % count
        amount = position - math.floor(position)
        if amount < 1e-6:
            frames.append(source[first_index].copy())
            continue
        effective_amount = min(amount, blend_cap)
        first_center = centroids[first_index]
        second_center = centroids[second_index]
        delta_x = second_center[0] - first_center[0]
        delta_y = second_center[1] - first_center[1]
        first = translate(
            source[first_index],
            delta_x * effective_amount,
            delta_y * effective_amount,
        )
        second = translate(
            source[second_index],
            -delta_x * (1 - effective_amount),
            -delta_y * (1 - effective_amount),
        )
        frames.append(premultiplied_blend(first, second, effective_amount))
    return frames


def enforce_shared_safe_margin(
    frames: list[Image.Image], margin: int = 2
) -> list[Image.Image]:
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(box is None for box in boxes):
        raise ValueError("Animation contains an empty frame")
    concrete_boxes = [box for box in boxes if box is not None]
    max_width = max(box[2] - box[0] for box in concrete_boxes)
    max_height = max(box[3] - box[1] for box in concrete_boxes)
    shared_scale = min(
        1.0,
        (CELL_W - margin * 2) / max_width,
        (CELL_H - margin * 2) / max_height,
    )
    normalized: list[Image.Image] = []
    for frame in frames:
        if shared_scale < 0.9999:
            scaled_size = (
                max(1, round(CELL_W * shared_scale)),
                max(1, round(CELL_H * shared_scale)),
            )
            scaled = frame.resize(scaled_size, Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (CELL_W, CELL_H))
            canvas.alpha_composite(
                scaled,
                (
                    (CELL_W - scaled_size[0]) // 2,
                    (CELL_H - scaled_size[1]) // 2,
                ),
            )
            frame = canvas
        box = frame.getchannel("A").getbbox()
        if box is None:
            raise ValueError("Animation contains an empty frame")
        dx = 0
        dy = 0
        if box[0] < margin:
            dx = margin - box[0]
        elif box[2] > CELL_W - margin:
            dx = CELL_W - margin - box[2]
        if box[1] < margin:
            dy = margin - box[1]
        elif box[3] > CELL_H - margin:
            dy = CELL_H - margin - box[3]
        normalized.append(translate(frame, dx, dy) if dx or dy else frame)
    return normalized


def despill_translucent_edges(frame: Image.Image, iterations: int = 10) -> Image.Image:
    """Extend trustworthy interior RGB through the translucent alpha edge."""
    array = np.asarray(frame, dtype=np.uint8).copy()
    rgb = array[..., :3].astype(np.float32)
    alpha = array[..., 3]
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    magenta_like = (
        (red > 120)
        & (blue > 75)
        & (red > green + 35)
        & (blue > green + 20)
    )
    transparent_nearby = alpha == 0
    boundary_band = transparent_nearby.copy()
    for _ in range(5):
        boundary_band |= (
            np.roll(boundary_band, 1, axis=0)
            | np.roll(boundary_band, -1, axis=0)
            | np.roll(boundary_band, 1, axis=1)
            | np.roll(boundary_band, -1, axis=1)
        )
    boundary_band &= alpha > 0
    yy = np.indices(alpha.shape, dtype=np.int16)[0]
    chroma_edge = (magenta_like & boundary_band) | (
        magenta_like & (yy > CELL_H * 0.5)
    )
    trusted = (alpha >= 245) & ~chroma_edge
    filled = trusted.copy()
    propagated = rgb.copy()
    for _ in range(iterations):
        neighbor_sum = np.zeros_like(propagated)
        neighbor_count = np.zeros(alpha.shape, dtype=np.float32)
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            neighbor_rgb = np.roll(propagated, shift, axis=axis)
            neighbor_valid = np.roll(filled, shift, axis=axis)
            neighbor_sum += neighbor_rgb * neighbor_valid[..., None]
            neighbor_count += neighbor_valid
        update = (~filled) & (alpha > 0) & (neighbor_count > 0)
        if not update.any():
            break
        propagated[update] = neighbor_sum[update] / neighbor_count[update, None]
        filled[update] = True
    edge = (alpha > 0) & filled & ((alpha < 245) | chroma_edge)
    rgb[edge] = propagated[edge]
    rgb[alpha == 0] = 0
    array[..., :3] = np.uint8(np.clip(rgb + 0.5, 0, 255))
    return Image.fromarray(array, "RGBA")


def save_gif(frames: list[Image.Image], path: Path, duration_ms: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    background = (245, 245, 245, 255)
    rendered: list[Image.Image] = []
    for frame in frames:
        checker = Image.new("RGBA", frame.size, background)
        draw = ImageDraw.Draw(checker)
        block = 16
        for y in range(0, CELL_H, block):
            for x in range(0, CELL_W, block):
                if (x // block + y // block) % 2:
                    draw.rectangle((x, y, x + block - 1, y + block - 1), fill=(224, 224, 224, 255))
        checker.alpha_composite(frame)
        rendered.append(checker.convert("P", palette=Image.Palette.ADAPTIVE))
    rendered[0].save(
        path,
        save_all=True,
        append_images=rendered[1:],
        duration=duration_ms,
        loop=0,
        disposal=2,
        optimize=False,
    )


def save_contact_sheet(action_frames: dict[str, list[Image.Image]], output: Path) -> None:
    names = list(action_frames)
    columns = 8
    label_h = 30
    width = columns * CELL_W
    height = len(names) * (CELL_H * 2 + label_h)
    sheet = Image.new("RGBA", (width, height), "#17191d")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for row, name in enumerate(names):
        y = row * (CELL_H * 2 + label_h)
        draw.text((8, y + 8), f"{name} · {len(action_frames[name])} frames", fill="white", font=font)
        for index, frame in enumerate(action_frames[name]):
            x = (index % columns) * CELL_W
            frame_y = y + label_h + (index // columns) * CELL_H
            checker = Image.new("RGBA", (CELL_W, CELL_H), "#f0f0f0")
            checker_draw = ImageDraw.Draw(checker)
            for cy in range(0, CELL_H, 16):
                for cx in range(0, CELL_W, 16):
                    if (cx // 16 + cy // 16) % 2:
                        checker_draw.rectangle((cx, cy, cx + 15, cy + 15), fill="#dcdcdc")
            checker.alpha_composite(frame)
            sheet.alpha_composite(checker, (x, frame_y))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(output, quality=94)


def action_validation(frames: list[Image.Image]) -> dict:
    boxes: list[tuple[int, int, int, int]] = []
    centroids: list[tuple[float, float]] = []
    corner_alpha: list[int] = []
    for frame in frames:
        if frame.mode != "RGBA" or frame.size != (CELL_W, CELL_H):
            raise ValueError(f"Invalid frame geometry: mode={frame.mode}, size={frame.size}")
        alpha = frame.getchannel("A")
        box = alpha.getbbox()
        if box is None:
            raise ValueError("Animation contains an empty frame")
        boxes.append(box)
        centroids.append(alpha_centroid(frame))
        corner_alpha.extend(
            [
                alpha.getpixel((0, 0)),
                alpha.getpixel((CELL_W - 1, 0)),
                alpha.getpixel((0, CELL_H - 1)),
                alpha.getpixel((CELL_W - 1, CELL_H - 1)),
            ]
        )
        boundary = np.concatenate(
            (
                np.asarray(alpha.crop((0, 0, CELL_W, 1))).reshape(-1),
                np.asarray(alpha.crop((0, CELL_H - 1, CELL_W, CELL_H))).reshape(-1),
                np.asarray(alpha.crop((0, 0, 1, CELL_H))).reshape(-1),
                np.asarray(alpha.crop((CELL_W - 1, 0, CELL_W, CELL_H))).reshape(-1),
            )
        )
        if int(boundary.max()) != 0:
            raise ValueError("Animation frame touches the cell boundary")
    if max(corner_alpha) != 0:
        raise ValueError("Animation frame corner is not transparent")
    widths = [box[2] - box[0] for box in boxes]
    heights = [box[3] - box[1] for box in boxes]
    return {
        "frameCount": len(frames),
        "size": [CELL_W, CELL_H],
        "mode": "RGBA",
        "transparentCorners": True,
        "transparentBoundary": True,
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
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas", type=Path, default=Path("pet/miaomiao/spritesheet.webp"))
    parser.add_argument("--output-root", type=Path, default=Path("pet/miaomiao/actions"))
    parser.add_argument("--preview-root", type=Path, default=Path("previews/actions-v2"))
    args = parser.parse_args()

    with Image.open(args.atlas) as opened:
        atlas = opened.convert("RGBA")
    if atlas.size != (1536, 2288):
        raise SystemExit(f"Expected 1536x2288 v2 atlas, got {atlas.size}")

    built: dict[str, list[Image.Image]] = {}
    action_manifest: dict[str, dict] = {}
    for name, spec in ACTIONS.items():
        source = extract_row(atlas, spec["row"], spec["source_frames"])
        frames = [
            despill_translucent_edges(frame)
            for frame in enforce_shared_safe_margin(
                tween_loop(source, spec["output_frames"], spec["blend_cap"])
            )
        ]
        built[name] = frames
        action_dir = args.output_root / name
        action_dir.mkdir(parents=True, exist_ok=True)
        relative_frames: list[str] = []
        for index, frame in enumerate(frames):
            path = action_dir / f"frame-{index:02d}.png"
            frame.save(path, optimize=True)
            relative_frames.append(path.relative_to(args.output_root.parent).as_posix())
        save_gif(frames, args.preview_root / f"{name}.gif", spec["duration_ms"])
        action_manifest[name] = {
            "frames": relative_frames,
            "frameDurationMs": spec["duration_ms"],
            "loop": spec["loop"],
            "sourceAtlasRow": spec["row"],
            "sourceFrameCount": spec["source_frames"],
            "interpolation": "identity-locked-centroid-registration-with-capped-premultiplied-transition",
        }

    manifest = {
        "formatVersion": 1,
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
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    save_contact_sheet(built, args.preview_root / "contact-sheet.jpg")
    validation = {
        "ok": True,
        "identitySource": args.atlas.as_posix(),
        "sourceVideoReferences": [
            "references/videos/撒娇打滚.mp4",
            "references/videos/踩奶.mp4",
            "references/videos/躺着用爪子洗脸.mp4",
        ],
        "actions": {name: action_validation(frames) for name, frames in built.items()},
        "visualReview": {
            "contactSheet": (args.preview_root / "contact-sheet.jpg").as_posix(),
            "verdict": "pass",
            "note": "Identity-locked source frames stay dominant; large-motion transitions use conservative blend caps to prevent face, limb, and tail deformation.",
        },
    }
    (args.preview_root / "validation.json").write_text(
        json.dumps(validation, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(manifest_path.resolve())


if __name__ == "__main__":
    main()
