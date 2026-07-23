#!/usr/bin/env python3
"""Extract evenly spaced keyframes and per-video contact sheets."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
VENDORED_PACKAGES = PROJECT_ROOT / ".tools" / "python"
if VENDORED_PACKAGES.exists():
    sys.path.insert(0, str(VENDORED_PACKAGES))

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont, ImageOps


def font(size: int):
    for candidate in (
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def video_metadata(path: Path) -> dict:
    reader = imageio_ffmpeg.read_frames(str(path), pix_fmt="rgb24")
    metadata = next(reader)
    reader.close()
    return metadata


def extract_frame(ffmpeg: str, source: Path, timestamp: float, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{timestamp:.3f}",
        "-i",
        str(source),
        "-frames:v",
        "1",
        "-q:v",
        "2",
        "-y",
        str(output),
    ]
    subprocess.run(command, check=True)


def make_contact_sheet(paths: list[Path], timestamps: list[float], output: Path) -> None:
    columns = 4
    tile_w, tile_h, label_h, margin = 320, 240, 36, 12
    rows = (len(paths) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (
            margin + columns * (tile_w + margin),
            margin + rows * (tile_h + label_h + margin),
        ),
        "#ece8df",
    )
    draw = ImageDraw.Draw(sheet)
    label_font = font(17)
    for index, (path, timestamp) in enumerate(zip(paths, timestamps)):
        row, column = divmod(index, columns)
        x = margin + column * (tile_w + margin)
        y = margin + row * (tile_h + label_h + margin)
        with Image.open(path) as source:
            image = ImageOps.exif_transpose(source).convert("RGB")
            fitted = ImageOps.fit(image, (tile_w, tile_h), method=Image.Resampling.LANCZOS)
        sheet.paste(fitted, (x, y))
        draw.text((x + 8, y + tile_h + 7), f"{timestamp:.2f}s", fill="#28231f", font=label_font)
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, quality=91, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--videos", type=Path, default=Path("references/videos"))
    parser.add_argument("--output", type=Path, default=Path("assets/video-keyframes"))
    parser.add_argument("--frames", type=int, default=12)
    args = parser.parse_args()

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    report: list[dict] = []
    for video in sorted(args.videos.glob("*.mp4")):
        metadata = video_metadata(video)
        duration = float(metadata.get("duration") or 0)
        if duration <= 0:
            raise RuntimeError(f"Could not determine duration for {video}")
        # Avoid first/last decode edges while still sampling the complete gesture.
        timestamps = [
            duration * (index + 0.5) / args.frames for index in range(args.frames)
        ]
        video_dir = args.output / video.stem
        frames: list[Path] = []
        for index, timestamp in enumerate(timestamps):
            output = video_dir / f"frame-{index:02d}-{timestamp:06.2f}s.jpg"
            extract_frame(ffmpeg, video, timestamp, output)
            frames.append(output)
        contact_sheet = args.output / f"{video.stem}-contact-sheet.jpg"
        make_contact_sheet(frames, timestamps, contact_sheet)
        report.append(
            {
                "video": str(video),
                "duration_seconds": duration,
                "fps": metadata.get("fps"),
                "source_size": metadata.get("source_size"),
                "keyframes": [str(path) for path in frames],
                "contact_sheet": str(contact_sheet),
            }
        )

    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "metadata.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
