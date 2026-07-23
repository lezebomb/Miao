#!/usr/bin/env python3
"""Render representative pet cells on light and dark Codex-like surfaces."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CELL_W, CELL_H = 192, 208


def font(size: int):
    for candidate in (
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def cell(atlas: Image.Image, row: int, column: int) -> Image.Image:
    return atlas.crop(
        (
            column * CELL_W,
            row * CELL_H,
            (column + 1) * CELL_W,
            (row + 1) * CELL_H,
        )
    )


def render(atlas: Image.Image, background: str, foreground: str, output: Path) -> None:
    examples = [
        ("待机", 0, 0),
        ("向右", 1, 2),
        ("向左", 2, 2),
        ("抬爪", 3, 2),
        ("侧躺", 5, 5),
        ("坐下", 6, 4),
        ("踩奶", 7, 3),
        ("洗脸", 8, 3),
        ("看右", 9, 4),
        ("看左", 10, 4),
    ]
    margin, card_w, card_h = 24, 224, 268
    columns = 5
    rows = 2
    canvas = Image.new(
        "RGBA",
        (
            margin + columns * (card_w + margin),
            72 + rows * (card_h + margin),
        ),
        background,
    )
    draw = ImageDraw.Draw(canvas)
    title_font = font(24)
    label_font = font(17)
    draw.text((margin, 18), "妙妙 · Codex 桌宠主题可见性测试", fill=foreground, font=title_font)
    for index, (label, row, column) in enumerate(examples):
        grid_row, grid_column = divmod(index, columns)
        x = margin + grid_column * (card_w + margin)
        y = 64 + grid_row * (card_h + margin)
        card_color = "#ffffff" if background == "#f4f5f7" else "#20242b"
        outline = "#d8dbe0" if background == "#f4f5f7" else "#343a44"
        draw.rounded_rectangle(
            (x, y, x + card_w, y + card_h),
            radius=14,
            fill=card_color,
            outline=outline,
            width=2,
        )
        sprite = cell(atlas, row, column)
        canvas.alpha_composite(sprite, (x + 16, y + 16))
        bounds = draw.textbbox((0, 0), label, font=label_font)
        label_x = x + (card_w - (bounds[2] - bounds[0])) // 2
        draw.text((label_x, y + 228), label, fill=foreground, font=label_font)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output, quality=94)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("previews"))
    args = parser.parse_args()
    with Image.open(args.atlas) as opened:
        atlas = opened.convert("RGBA")
    render(atlas, "#f4f5f7", "#191b20", args.output_dir / "theme-light.png")
    render(atlas, "#12151a", "#f1f3f5", args.output_dir / "theme-dark.png")
    print(args.output_dir.resolve())


if __name__ == "__main__":
    main()
