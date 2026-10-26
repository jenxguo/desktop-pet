#!/usr/bin/env python3
"""Makes an .icns app icon from Pet/sprites/portrait.png: the pixel portrait,
scaled up crisp, on a rounded square in the theme's background color.

    python3 tools/make_icon.py build/AppIcon.icns
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from petlib import default_pet_dir, load_pet


def icon(portrait, size, background, border):
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    inset = round(size * 0.1)  # macOS icons leave a margin around the tile
    tile = [inset, inset, size - inset - 1, size - inset - 1]
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(tile, radius=round(size * 0.18), fill=background,
                           outline=border, width=max(1, size // 128))

    room = (size - 2 * inset) * 0.78
    factor = max(1, int(room // max(portrait.size)))  # whole-number scale keeps pixels square
    scaled = portrait.resize((portrait.width * factor, portrait.height * factor), Image.NEAREST)
    if max(scaled.size) > room:  # tiny sizes: fall back to a smooth fit
        ratio = room / max(portrait.size)
        scaled = portrait.resize((max(1, round(portrait.width * ratio)), max(1, round(portrait.height * ratio))),
                                 Image.LANCZOS)
    canvas.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    return canvas


def main():
    out = sys.argv[1]
    pet_dir = default_pet_dir()
    cfg = load_pet(pet_dir)
    portrait_path = os.path.join(pet_dir, 'sprites', 'portrait.png')
    if not os.path.exists(portrait_path):
        raise SystemExit('no Pet/sprites/portrait.png — skipping the icon')
    portrait = Image.open(portrait_path).convert('RGBA')
    bbox = portrait.getchannel('A').getbbox()
    if bbox:
        portrait = portrait.crop(bbox)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, 'AppIcon.iconset')
        os.makedirs(iconset)
        for base in (16, 32, 128, 256, 512):
            for mult, suffix in ((1, ''), (2, '@2x')):
                size = base * mult
                icon(portrait, size, cfg['theme']['background'], cfg['theme']['border']).save(
                    os.path.join(iconset, f'icon_{base}x{base}{suffix}.png'))
        subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', out], check=True)
    print(f'icon: {out}')


if __name__ == '__main__':
    main()
