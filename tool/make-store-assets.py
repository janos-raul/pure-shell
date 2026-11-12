#!/usr/bin/env python3
# Microsoft Store logo images, rendered from the vector master icon
# (assets/icon/pure-shell-icon.svg), never from a small raster:
#   store-assets/windows/box-art-2160x2160.png     1:1 box art
#   store-assets/windows/poster-art-1440x2160.png  9:16 poster art
# Brand colours as in the icon: background #0C0C0C, green #33FF66.
# Needs ImageMagick (convert) and Pillow. Run: python3 tool/make-store-assets.py
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG = os.path.join(ROOT, "assets/icon/pure-shell-icon.svg")
OUT = os.path.join(ROOT, "store-assets/windows")
BG = (0x0C, 0x0C, 0x0C)
GREEN = (0x33, 0xFF, 0x66)
BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"


def icon(size):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "i.png")
        # density 72 * size / 512 renders the 512 px SVG at exactly `size`.
        subprocess.run(["convert", "-background", "none", "-density",
                        str(72 * size / 512), SVG, "-resize", f"{size}x{size}",
                        "PNG32:" + p], check=True)
        return Image.open(p).convert("RGB")


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote store-assets/windows/" + name, img.size)


def main():
    # 1:1 box art: icon 1296 px (60 %), centred.
    box = Image.new("RGB", (2160, 2160), BG)
    box.paste(icon(1296), (432, 432))
    save(box, "box-art-2160x2160.png")

    # 9:16 poster art: icon 960 px in the upper middle, name below it.
    poster = Image.new("RGB", (1440, 2160), BG)
    poster.paste(icon(960), (240, 420))
    d = ImageDraw.Draw(poster)
    font = ImageFont.truetype(BOLD, 190)
    d.text((720, 1640), "Pure-Shell", font=font, fill=GREEN, anchor="mm")
    save(poster, "poster-art-1440x2160.png")


main()
