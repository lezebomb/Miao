#!/usr/bin/env python3
"""Build a compact labeled contact sheet from the local identity photos."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = (
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    )
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--photos", type=Path, default=Path("references/photos"))
    parser.add_argument("--output", type=Path, default=Path("assets/reference-contact-sheet.jpg"))
    parser.add_argument("--columns", type=int, default=4)
    args = parser.parse_args()

    paths = sorted(
        path
        for path in args.photos.iterdir()
        if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    )
    if not paths:
        raise SystemExit(f"No images found under {args.photos}")

    cell_w, image_h, label_h, margin = 320, 320, 42, 16
    rows = (len(paths) + args.columns - 1) // args.columns
    sheet = Image.new(
        "RGB",
        (
            margin + args.columns * (cell_w + margin),
            margin + rows * (image_h + label_h + margin),
        ),
        "#ece8df",
    )
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)

    for index, path in enumerate(paths):
        row, column = divmod(index, args.columns)
        x = margin + column * (cell_w + margin)
        y = margin + row * (image_h + label_h + margin)
        with Image.open(path) as source:
            image = ImageOps.exif_transpose(source).convert("RGB")
            fitted = ImageOps.fit(image, (cell_w, image_h), method=Image.Resampling.LANCZOS)
        sheet.paste(fitted, (x, y))
        label = path.stem
        bounds = draw.textbbox((0, 0), label, font=font)
        tx = x + max(0, (cell_w - (bounds[2] - bounds[0])) // 2)
        draw.text((tx, y + image_h + 8), label, fill="#28231f", font=font)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output, quality=92, optimize=True)
    print(args.output.resolve())


if __name__ == "__main__":
    main()
