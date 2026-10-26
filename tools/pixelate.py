#!/usr/bin/env python3
"""Turns a bigger image (AI-generated pixel art, a drawing, a cut-out photo)
into a real sprite frame: background removed, shrunk onto the pixel grid,
limited to a small palette, feet on pet.json's ground line.

One image → one frame:

    python3 tools/pixelate.py stand-big.png --name stand

A sprite sheet → many frames (cells read left-to-right, top-to-bottom),
all at the same scale and with one shared palette so the animation
doesn't flicker:

    python3 tools/pixelate.py walk-sheet.png --sheet 4x1 --name walk
        → Pet/sprites/walk_0.png … walk_3.png
    python3 tools/pixelate.py poses.png --sheet 3x2 --names stand,sit,sleep,eat,play_bow,-
        (use - to skip a cell)

Options worth knowing:
    --colors 24          palette size (fewer = chunkier)
    --palette stand.png  reuse an existing frame's colors, so new frames match
    --height 38          body height in pixels; pass the same number for every
                         frame you convert separately so the pet doesn't
                         change size between frames
    --flip               the source faces left (frames must face right)
    --outline            add a 1px outline in the palette's darkest color
    --bg none            source already has transparency; don't remove anything
    --size 38x56         output size instead of pet.json's frame size, bottom-
                         aligned — e.g. for the menu/app-icon portrait:
                         pixelate.py face.png --name portrait --size 38x56
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from petlib import default_pet_dir, load_pet


def remove_background(im, mode, tolerance):
    """Flood-fills the background from the edges and makes it transparent."""
    im = im.convert('RGBA')
    if mode == 'none':
        return im
    alpha = np.array(im.getchannel('A'))
    if mode == 'auto' and alpha.min() < 250:
        return im  # already has transparency

    rgb = im.convert('RGB')
    sentinel = (1, 254, 3)
    w, h = rgb.size
    seeds = [(x, y) for x in range(0, w, max(1, w // 16)) for y in (0, h - 1)]
    seeds += [(x, y) for y in range(0, h, max(1, h // 16)) for x in (0, w - 1)]
    for seed in seeds:
        if rgb.getpixel(seed) != sentinel:
            ImageDraw.floodfill(rgb, seed, sentinel, thresh=tolerance)
    mask = np.all(np.array(rgb) == sentinel, axis=-1)
    out = np.array(im)
    out[mask, 3] = 0
    return Image.fromarray(out)


def content(im):
    """Crops to the opaque part."""
    bbox = im.getchannel('A').point(lambda a: 255 if a > 127 else 0).getbbox()
    if bbox is None:
        raise SystemExit('nothing left after removing the background — try --bg none or a lower --tolerance')
    return im.crop(bbox)


def shrink(im, scale):
    w, h = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    small = im.resize((w, h), Image.BOX)
    a = np.array(small)
    a[..., 3] = np.where(a[..., 3] > 110, 255, 0)  # hard edges: pixel art has no half-transparent pixels
    return Image.fromarray(a)


def build_palette(images, colors, palette_from):
    if palette_from:
        ref = Image.open(palette_from).convert('RGBA')
        pixels = [p[:3] for p in ref.getdata() if p[3] > 127]
    else:
        pixels = [p[:3] for im in images for p in im.getdata() if p[3] > 127]
    strip = Image.new('RGB', (len(pixels), 1))
    strip.putdata(pixels)
    quantized = strip.quantize(colors=min(colors, 256), method=Image.MEDIANCUT)
    return quantized


def apply_palette(im, palette_image):
    rgb = im.convert('RGB').quantize(palette=palette_image, dither=Image.Dither.NONE).convert('RGB')
    out = np.array(im)
    out[..., :3] = np.array(rgb)
    return Image.fromarray(out)


def add_outline(im, palette_image):
    raw = palette_image.getpalette()
    pal = np.array(raw[:len(raw) // 3 * 3]).reshape(-1, 3)
    used = set(palette_image.getdata())
    darkest = min((pal[i] for i in used), key=lambda c: int(c.sum()))
    a = np.array(im)
    solid = a[..., 3] > 0
    grown = solid.copy()
    grown[1:] |= solid[:-1]
    grown[:-1] |= solid[1:]
    grown[:, 1:] |= solid[:, :-1]
    grown[:, :-1] |= solid[:, 1:]
    edge = grown & ~solid
    a[edge, :3] = darkest
    a[edge, 3] = 255
    return Image.fromarray(a)


def place(im, frame_w, frame_h, feet_y):
    """Centers horizontally with the lowest pixel on row feet_y."""
    if im.width > frame_w or feet_y + 1 - im.height < 0:
        raise SystemExit(f'converted image is {im.width}x{im.height}, too big for a {frame_w}x{frame_h} frame '
                         f'with feet at row {feet_y} — use a smaller --height')
    frame = Image.new('RGBA', (frame_w, frame_h), (0, 0, 0, 0))
    frame.alpha_composite(im, ((frame_w - im.width) // 2, feet_y + 1 - im.height))
    return frame


def split_sheet(im, spec):
    cols, rows = (int(v) for v in spec.lower().split('x'))
    cw, ch = im.width // cols, im.height // rows
    return [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)) for r in range(rows) for c in range(cols)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('input')
    ap.add_argument('--name', help='frame name (e.g. stand), or animation name with --sheet (e.g. walk)')
    ap.add_argument('--names', help='comma-separated frame names for each sheet cell; - skips a cell')
    ap.add_argument('--sheet', help='COLSxROWS grid, e.g. 4x1')
    ap.add_argument('--pet', default=default_pet_dir(), help='pet folder (default: Pet/)')
    ap.add_argument('--out', help='output folder (default: <pet>/sprites)')
    ap.add_argument('--colors', type=int, default=24)
    ap.add_argument('--palette', help='reuse the colors of this existing frame')
    ap.add_argument('--height', type=int, help='body height in pixels (default: as big as fits)')
    ap.add_argument('--flip', action='store_true', help='source faces left')
    ap.add_argument('--outline', action='store_true')
    ap.add_argument('--bg', choices=['auto', 'none', 'remove'], default='auto')
    ap.add_argument('--size', help='WxH output size (default: pet.json frame size, feet on feetY)')
    ap.add_argument('--tolerance', type=int, default=48, help='background color tolerance (0-255)')
    args = ap.parse_args()

    cfg = load_pet(args.pet)
    frame_w, frame_h = int(cfg['sprite']['frameWidth']), int(cfg['sprite']['frameHeight'])
    feet_y = int(cfg['sprite']['feetY'])
    if args.size:
        frame_w, frame_h = (int(v) for v in args.size.lower().split('x'))
        feet_y = frame_h - 1
    out_dir = args.out or os.path.join(args.pet, 'sprites')

    source = Image.open(args.input)
    cells = split_sheet(source, args.sheet) if args.sheet else [source]
    if args.names:
        names = args.names.split(',')
    elif args.sheet and args.name:
        names = [f'{args.name}_{i}' for i in range(len(cells))]
    elif args.name:
        names = [args.name]
    else:
        raise SystemExit('pass --name (or --names with --sheet)')
    if len(names) != len(cells):
        raise SystemExit(f'{len(cells)} cells but {len(names)} names')

    jobs = [(n, c) for n, c in zip(names, cells) if n != '-']
    cutouts = []
    for name, cell in jobs:
        cut = content(remove_background(cell, args.bg, args.tolerance))
        if args.flip:
            cut = cut.transpose(Image.FLIP_LEFT_RIGHT)
        cutouts.append((name, cut))

    # One scale for every frame from this run, so a walk cycle stays the same size.
    room_h = feet_y + 1 - (2 if args.outline else 0)
    room_w = frame_w - (2 if args.outline else 0)
    if args.height:
        tallest = max(c.height for _, c in cutouts)
        scale = args.height / tallest
    else:
        scale = min(min(room_w / c.width, room_h / c.height) for _, c in cutouts) * 0.995
    shrunk = [(n, shrink(c, scale)) for n, c in cutouts]

    palette = build_palette([s for _, s in shrunk], args.colors, args.palette)
    os.makedirs(out_dir, exist_ok=True)
    for name, small in shrunk:
        small = apply_palette(small, palette)
        if args.outline:
            padded = Image.new('RGBA', (small.width + 2, small.height + 2), (0, 0, 0, 0))
            padded.alpha_composite(small, (1, 1))
            small = add_outline(padded, palette)
        frame = place(small, frame_w, frame_h, feet_y)
        path = os.path.join(out_dir, name + '.png')
        frame.save(path)
        print(f'wrote {os.path.relpath(path)}  ({small.width}x{small.height} body)')
    print('next: python3 tools/check_pet.py')


if __name__ == '__main__':
    main()
