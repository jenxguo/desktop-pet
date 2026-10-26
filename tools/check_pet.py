#!/usr/bin/env python3
"""Checks a pet folder before you run the app, and draws a preview sheet.

    python3 tools/check_pet.py            # checks Pet/
    python3 tools/check_pet.py path/to/Pet

Errors (exit 1): things the app can't start without, or frames of the wrong
size. Warnings: things that will look off — feet not on the ground line,
mouth point not on the pet, a missing frame the app will stand in for.

Writes build/pet-preview.png: every frame at 4x on a checkerboard, with the
ground line (red) and mouth point (cyan) from pet.json drawn on top. Look
at it to check the pet faces right and every frame lines up.
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from petlib import (CORE_SPRITES, FEATURE_SPRITES, OPTIONAL_SPRITES, ROOT, default_pet_dir, feature_props,
                    frame_names, load_pet)

errors, warnings = [], []


def check_frame(path, name, cfg):
    sprite = cfg['sprite']
    w, h = int(sprite['frameWidth']), int(sprite['frameHeight'])
    im = Image.open(path)
    if im.size != (w, h):
        errors.append(f'{name}.png is {im.size[0]}x{im.size[1]}, but pet.json says frames are {w}x{h}')
        return None
    if im.mode not in ('RGBA', 'LA', 'P') or 'A' not in im.convert('RGBA').getbands():
        warnings.append(f'{name}.png has no transparency')
    im = im.convert('RGBA')
    alpha = im.getchannel('A')
    bbox = alpha.point(lambda a: 255 if a > 127 else 0).getbbox()
    if bbox is None:
        errors.append(f'{name}.png is fully transparent')
        return im

    # Corners should be see-through, or the pet walks around in a box.
    corners = [alpha.getpixel(p) for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    if max(corners) > 127:
        warnings.append(f'{name}.png has an opaque corner — is the background removed?')

    feet = int(sprite['feetY'])
    lowest = bbox[3] - 1
    if abs(lowest - feet) > 2:
        warnings.append(f'{name}.png: lowest pixel is row {lowest}, pet.json feetY is {feet} '
                        f'(it will {"float" if lowest < feet else "sink"} {abs(lowest - feet)}px)')

    colors = len({px for px in im.getdata() if px[3] > 127})
    if colors > 64:
        warnings.append(f'{name}.png has {colors} colors — not very pixel-arty; '
                        f'try tools/pixelate.py --colors 24')

    if name in ('stand', 'walk_0'):
        mx, my = (int(v) for v in sprite['mouth'])
        near = any(
            0 <= mx + dx < w and 0 <= my + dy < h and alpha.getpixel((mx + dx, my + dy)) > 127
            for dx in range(-3, 4) for dy in range(-3, 4)
        )
        if not near:
            warnings.append(f'{name}.png: mouth point {[mx, my]} is not on the pet — '
                            f'carried props will float. Set sprite.mouth in pet.json.')
    return im


def main():
    pet_dir = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else default_pet_dir())
    sprites_dir = os.path.join(pet_dir, 'sprites')
    props_dir = os.path.join(pet_dir, 'props')
    cfg = load_pet(pet_dir)

    if not os.path.exists(os.path.join(pet_dir, 'pet.json')):
        warnings.append(f'no pet.json in {pet_dir} — using built-in defaults (name "Pet")')

    props_by_feature = feature_props()
    features = [f for f in ['photoDrop', *props_by_feature] if cfg['features'].get(f, True)]
    features = list(dict.fromkeys(features))
    print(f'{cfg["name"]} — {int(cfg["sprite"]["frameWidth"])}x{int(cfg["sprite"]["frameHeight"])} frames, '
          f'moments: {", ".join(features) or "none"}')

    wanted = list(CORE_SPRITES)
    for f in features:
        wanted += [s for s in FEATURE_SPRITES.get(f, []) if s not in wanted]

    if not os.path.exists(os.path.join(sprites_dir, 'stand.png')):
        errors.append('sprites/stand.png is required')
    for name in wanted:
        if not os.path.exists(os.path.join(sprites_dir, name + '.png')):
            warnings.append(f'sprites/{name}.png missing — the app will use a stand-in frame')
    if not any(os.path.exists(os.path.join(sprites_dir, n)) for n in ('portrait.png', 'portrait.svg')):
        warnings.append('sprites/portrait.png missing — no picture in the menu or app icon')

    for f in features:
        for prop in props_by_feature.get(f, []):
            if not os.path.exists(os.path.join(props_dir, prop + '.png')):
                errors.append(f'props/{prop}.png is required for "{f}" (or set features.{f} to false)')

    # Every frame the app might load, in a sensible order.
    singles = ['stand', 'sit', 'sleep', 'eat', 'play_bow'] + OPTIONAL_SPRITES
    names = [n for n in singles if os.path.exists(os.path.join(sprites_dir, n + '.png'))]
    for anim in ('walk', 'run', 'carry_ball'):
        names += frame_names(sprites_dir, anim)

    frames = []
    for name in names:
        im = check_frame(os.path.join(sprites_dir, name + '.png'), name, cfg)
        if im is not None:
            frames.append((name, im))

    if frames:
        out = os.path.join(ROOT, 'build', 'pet-preview.png')
        draw_preview(frames, cfg, out)
        print(f'preview: {os.path.relpath(out, os.getcwd())}')

    for w in warnings:
        print(f'  ⚠️  {w}')
    for e in errors:
        print(f'  ❌ {e}')
    if not warnings and not errors:
        print('  ✅ all good')
    sys.exit(1 if errors else 0)


def draw_preview(frames, cfg, out, scale=4, cols=5, pad=16, label_h=14):
    w, h = int(cfg['sprite']['frameWidth']), int(cfg['sprite']['frameHeight'])
    cell_w, cell_h = w * scale, h * scale
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * (cell_w + pad) + pad, rows * (cell_h + pad + label_h) + pad), '#F6F1E7')
    draw = ImageDraw.Draw(sheet)
    feet = int(cfg['sprite']['feetY'])
    mx, my = (int(v) for v in cfg['sprite']['mouth'])

    for i, (name, im) in enumerate(frames):
        x0 = pad + (i % cols) * (cell_w + pad)
        y0 = pad + (i // cols) * (cell_h + pad + label_h)
        draw.text((x0, y0), name, fill='#3B2219')
        y0 += label_h
        # checkerboard so transparency is visible
        for cy in range(0, cell_h, 8):
            for cx in range(0, cell_w, 8):
                if (cx // 8 + cy // 8) % 2:
                    draw.rectangle([x0 + cx, y0 + cy, x0 + cx + 7, y0 + cy + 7], fill='#E6DCCB')
                else:
                    draw.rectangle([x0 + cx, y0 + cy, x0 + cx + 7, y0 + cy + 7], fill='#FFFDF8')
        sheet.alpha_composite(im.resize((cell_w, cell_h), Image.NEAREST), (x0, y0))
        ground = y0 + (feet + 1) * scale
        draw.line([x0, ground, x0 + cell_w, ground], fill='#E0443E', width=1)
        if name in ('stand', 'walk_0', 'walk_1', 'walk_2', 'walk_3', 'run_0', 'run_1', 'run_2', 'run_3'):
            cx, cy = x0 + mx * scale + scale // 2, y0 + my * scale + scale // 2
            draw.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], outline='#2AA7C0', width=2)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)


if __name__ == '__main__':
    main()
