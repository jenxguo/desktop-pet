"""Mars's sprites, drawn from code.

This is the example of the "Claude draws it" route in
docs/MAKE_YOUR_OWN_PET.md: the dog is built from ellipses and limbs (body
parts), shaded with a fixed palette, outlined, and rendered at 68x46 per
frame. To make your own pet this way, copy this file, change the palette
and the body-part numbers to match your pet's photos, and export:

    python3 tools/examples/make_mars_sprites.py --frames Pet/sprites
    python3 tools/check_pet.py
"""
import math, numpy as np
from PIL import Image

PAL = {'o':'#5a3220','d':'#8a5233','s':'#b0703f','m':'#c98c55','l':'#ddaa72','h':'#eecb98','c':'#f5e2bf',
       'r':'#9c5530','R':'#7a4026','n':'#3b2219','e':'#1c120d','t':'#e2788a','T':'#62bccb','U':'#3a8c9e',
       'w':'#fbf7ee','g':'#d9dee6','G':'#9aa6b5','y':'#d6e05a','Y':'#9fae32','k':'#c2453a','K':'#8e2c25',
       'p':'#7fb069','q':'#e6a15c','B':'#6f7a8a'}
SHADES = ['h','l','m','s','d']
W, H = 68, 46

def hx(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))

class Canvas:
    def __init__(s):
        s.part = np.full((H,W), -1, int)   # part index
        s.parts = []                        # (kind, cx, cy, rx, ry)
        s.over = {}                         # explicit pixel overrides (after shading)
    def add(s, kind, mask, cx, cy, rx, ry):
        idx = len(s.parts); s.parts.append((kind,cx,cy,rx,ry))
        s.part[mask] = idx
    def ell(s, kind, cx, cy, rx, ry, ang=0):
        yy, xx = np.mgrid[0:H,0:W] + 0.5
        dx, dy = xx-cx, yy-cy
        c, si = math.cos(ang), math.sin(ang)
        u, v = dx*c+dy*si, -dx*si+dy*c
        s.add(kind, (u/rx)**2+(v/ry)**2 <= 1, cx, cy, rx, ry)
    def limb(s, kind, x0, y0, x1, y1, w0, w1):
        yy, xx = np.mgrid[0:H,0:W] + 0.5
        vx, vy = x1-x0, y1-y0; L2 = vx*vx+vy*vy
        t = np.clip(((xx-x0)*vx+(yy-y0)*vy)/L2, 0, 1)
        px, py = x0+t*vx, y0+t*vy
        r = w0+(w1-w0)*t
        s.add(kind, (xx-px)**2+(yy-py)**2 <= r*r, (x0+x1)/2, (y0+y1)/2, max(w0,w1), math.sqrt(L2)/2)
    def px(s, x, y, k):
        if 0 <= x < W and 0 <= y < H: s.over[(int(y),int(x))] = k

    def render(s):
        g = np.full((H,W), '.', dtype='<U1')
        for y in range(H):
            for x in range(W):
                i = s.part[y,x]
                if i < 0: continue
                kind, cx, cy, rx, ry = s.parts[i]
                t = (y+0.5-cy)/max(ry,1)*0.9 - (x+0.5-cx)/max(rx,1)*0.25
                lvl = 0 if t < -0.75 else 1 if t < -0.3 else 2 if t < 0.35 else 3 if t < 0.75 else 4
                # curl texture
                hsh = (x*7 + y*13) % 11
                if hsh == 0: lvl -= 1
                elif (x*5 + y*3) % 13 == 0: lvl += 1
                if kind == 'fur':  k = SHADES[min(4,max(0,lvl))]
                elif kind == 'far': k = SHADES[min(4,max(1,lvl+1))]
                elif kind == 'ear': k = ['l','m','r','r','R'][min(4,max(0,lvl))]
                elif kind == 'farear': k = ['r','r','R','R','R'][min(4,max(0,lvl))]
                elif kind == 'beard': k = ['c','c','h','h','l'][min(4,max(0,lvl))]
                elif kind == 'harn': k = 'T' if lvl < 3 else 'U'
                elif kind == 'ball': k = 'y' if lvl < 3 else 'Y'
                elif kind == 'bowl': k = 'k' if lvl < 3 else 'K'
                else: k = kind
                g[y,x] = k
        # curly silhouette: grow bumps on the edge of fur parts
        base = g.copy(); bp = s.part.copy()
        for y in range(1,H-1):
            for x in range(1,W-1):
                if base[y,x] != '.' or y >= 42: continue
                for dy,dx in ((0,-1),(0,1),(-1,0),(1,0)):
                    j = bp[y+dy,x+dx]
                    if j >= 0 and s.parts[j][0] in ('fur','far','ear','farear','beard') and (x*3+y*5) % 4 == 0:
                        g[y,x] = base[y+dy,x+dx]; s.part[y,x] = j; break
        # outline on silhouette edge (fur-ish parts only get dark brown outline)
        m = g != '.'
        pad = np.pad(m, 1)
        edge = m & ~(pad[2:,1:-1] & pad[:-2,1:-1] & pad[1:-1,2:] & pad[1:-1,:-2])
        for y, x in zip(*np.where(edge)):
            kind = s.parts[s.part[y,x]][0]
            g[y,x] = {'harn':'U','ball':'Y','bowl':'K','w':'G','g':'G'}.get(kind, 'o')
        # separation lines between ear and head, far parts and near parts
        for y in range(1,H-1):
            for x in range(1,W-1):
                i = s.part[y,x]
                if i < 0 or g[y,x] == 'o': continue
                kind = s.parts[i][0]
                if kind in ('ear',):
                    for dy,dx in ((1,0),(0,1),(0,-1)):
                        j = s.part[y+dy,x+dx]
                        if j >= 0 and s.parts[j][0] in ('fur','beard'):
                            g[y,x] = 'R'; break
                if kind == 'fur':
                    j = s.part[y,x-1]
                    if j >= 0 and s.parts[j][0] == 'far': g[y,x] = 'd'
        for (y,x), k in s.over.items(): g[y,x] = k
        return g

def to_img(g, scale=1):
    a = np.zeros((H,W,4), np.uint8)
    for y in range(H):
        for x in range(W):
            if g[y,x] != '.': a[y,x,:3] = hx(PAL[g[y,x]]); a[y,x,3] = 255
    im = Image.fromarray(a)
    return im.resize((W*scale,H*scale), Image.NEAREST) if scale > 1 else im

def to_svg(g, scale=1):
    rects = []
    for y in range(H):
        x = 0
        while x < W:
            k = g[y,x]
            if k == '.': x += 1; continue
            x2 = x
            while x2+1 < W and g[y,x2+1] == k: x2 += 1
            rects.append(f'<rect x="{x}" y="{y}" width="{x2-x+1}" height="1" fill="{PAL[k]}"/>')
            x = x2+1
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W*scale}" height="{H*scale}" '
            f'shape-rendering="crispEdges">' + ''.join(rects) + '</svg>')

# ---------- Mars, facing right ----------
def head(c, hx_, hy, ear_swing=0.0, mouth='closed', eyes='open', tilt=0.0, prop=None):
    # far ear peeks behind head
    c.ell('farear', hx_+1, hy+5, 3, 6, 0.2)
    # topknot + skull
    c.ell('fur', hx_+1, hy-1, 7.5, 7.5)
    c.ell('fur', hx_-2, hy-6, 3.2, 2.6)
    c.ell('fur', hx_+3, hy-7, 3.2, 2.4)
    # muzzle and beard
    c.ell('fur', hx_+8, hy+2, 5.5, 4)
    c.ell('beard', hx_+8.5, hy+5.5, 4.6, 3.2)
    c.ell('beard', hx_+6.5, hy+7.5, 3.2, 2.4)
    # near ear: long, wavy, darker red
    c.ell('ear', hx_-2.5 - ear_swing, hy+7, 3.8, 9, 0.15 + ear_swing*0.08)
    c.ell('ear', hx_-3.6 - ear_swing*1.4, hy+14.5, 3.0, 2.6)
    tx, ty = int(hx_-3.6 - ear_swing*1.4), int(hy+16)
    for dx in (-2,0,2): c.px(tx+dx, ty, 'l'); c.px(tx+dx+1, ty-1, 'm')
    # nose, eye, mouth (overrides)
    nx, ny = int(hx_+13), int(hy+1)
    for (dx,dy) in ((0,0),(1,0),(0,1),(1,1),(-1,0)): c.px(nx+dx, ny+dy, 'n')
    ex, ey = int(hx_+5), int(hy-1)
    if eyes == 'open':
        c.px(ex,ey,'e'); c.px(ex+1,ey,'e'); c.px(ex,ey+1,'e'); c.px(ex+1,ey+1,'e'); c.px(ex+1,ey,'w')
        c.px(ex-1,ey-2,'d'); c.px(ex,ey-2,'d'); c.px(ex+1,ey-2,'d')   # brow fringe
    else:
        c.px(ex-1,ey+1,'o'); c.px(ex,ey+1,'o'); c.px(ex+1,ey+1,'o')
    if mouth == 'open':
        for (dx,dy,k) in ((9,5,'o'),(10,5,'o'),(11,5,'o'),(9,6,'t'),(10,6,'t'),(10,7,'t'),(9,7,'t'),(11,6,'o')):
            c.px(int(hx_+dx), int(hy+dy), k)
    elif mouth == 'smile':
        c.px(int(hx_+10), int(hy+4), 'o'); c.px(int(hx_+11), int(hy+4), 'o')

def harness(c, nx, ny, gx, gy0, gy1):
    # neck band (diagonal) + girth strap + D-ring
    c.limb('harn', nx-2, ny-3, nx+3, ny+5, 1.7, 1.7)
    c.limb('harn', gx, gy0+3, gx-1, gy1, 1.5, 1.5)
    c.px(nx+3, ny+5, 'w')

def dog(pose='stand', frame=0, prop=None):
    c = Canvas()
    if pose in ('stand','walk','run','carry'):
        run = pose == 'run'
        ph = frame/4*2*math.pi
        sw = (3.5 if pose=='walk' or pose=='carry' else 6.0 if run else 0)
        a1, a2 = math.sin(ph)*sw, math.sin(ph+math.pi)*sw
        bob = (abs(math.sin(ph))*1.0 if pose in ('walk','carry') else abs(math.sin(ph))*2 if run else 0)
        by = 25 - bob
        # tail plume (behind)
        tail_up = 0 if not run else 4
        c.ell('fur', 9, by-6+tail_up*0.3, 3.2, 5.5, -0.5 - tail_up*0.1)
        c.ell('fur', 6.5, by-11+tail_up*0.6, 2.8, 3.2)
        # far legs
        c.limb('far', 16, by+5, 16-a2*0.8, 41, 3.0, 2.6); c.ell('far', 16-a2*0.8+0.5, 41.5, 3.2, 2.2)
        c.limb('far', 34, by+5, 34-a1*0.8, 41, 2.8, 2.4); c.ell('far', 34-a1*0.8+0.8, 41.5, 3.2, 2.2)
        # body
        c.ell('fur', 22, by, 14.5, 9.5)
        c.ell('fur', 35, by+1, 7.5, 9.5)
        # near legs
        c.limb('fur', 13, by+5, 13+a1*0.9, 41, 3.4, 2.7); c.ell('fur', 13+a1*0.9+0.6, 41.6, 3.4, 2.3)
        c.limb('fur', 32, by+5, 32+a2*0.9, 41, 3.0, 2.5); c.ell('fur', 32+a2*0.9+0.8, 41.6, 3.4, 2.3)
        # neck + head
        c.ell('fur', 39, by-6, 6, 8, 0.35)
        hx_, hy = 42, by-13 + (1 if run else 0)
        harness(c, 38, by-5, 30, by-7, by+8)
        head(c, hx_, hy, ear_swing=(a1*0.25 if pose!='stand' else 0) + (2.5 if run else 0),
             mouth='open' if (run or pose=='stand') and prop is None else 'closed')
        c.px(37, by+3, 'w'); c.px(38, by+3, 'c'); c.px(37, by+4, 'c')   # white chest spot
        if prop: carry(c, prop, hx_+11, hy+6)
    elif pose == 'sit':
        c.ell('fur', 8, 40, 6, 2.6)                     # tail on floor
        c.ell('far', 30, 40, 3.2, 2.2)
        c.ell('fur', 18, 33, 10, 8.5)                   # haunch
        c.ell('fur', 27, 26, 8, 11, 0.25)               # upright torso
        c.ell('fur', 17, 41.5, 5.5, 2.4)                # hind paw
        c.limb('fur', 31, 26, 31.5, 41, 3.0, 2.6); c.ell('fur', 32.5, 41.6, 3.4, 2.3)
        c.ell('fur', 33, 15, 6, 8, 0.35)
        harness(c, 32, 17, 25, 18, 32)
        head(c, 36, 8, mouth='open' if prop is None else 'closed')
        c.px(32, 24, 'w'); c.px(33, 24, 'c'); c.px(32, 25, 'c')
        if prop: carry(c, prop, 47, 14)
    elif pose == 'alert':
        # Same sit, but ears pulled back and eyes wide — she doesn't have
        # ears that can stand up (long and floppy, true to her), so this is
        # how a dog like her actually shows "I noticed you."
        c.ell('fur', 8, 40, 6, 2.6)
        c.ell('far', 30, 40, 3.2, 2.2)
        c.ell('fur', 18, 33, 10, 8.5)
        c.ell('fur', 27, 26, 8, 11, 0.25)
        c.ell('fur', 17, 41.5, 5.5, 2.4)
        c.limb('fur', 31, 26, 31.5, 41, 3.0, 2.6); c.ell('fur', 32.5, 41.6, 3.4, 2.3)
        c.ell('fur', 33, 15, 6, 8, 0.35)
        harness(c, 32, 17, 25, 18, 32)
        head(c, 36, 8, ear_swing=-1.8, eyes='open', mouth='closed')
        c.px(32, 24, 'w'); c.px(33, 24, 'c'); c.px(32, 25, 'c')
    elif pose == 'bow':
        c.ell('fur', 7, 11, 3, 5.5, -0.4); c.ell('fur', 5, 6, 2.6, 3)    # tail high
        c.limb('far', 15, 24, 14, 41, 2.8, 2.4); c.ell('far', 14.6, 41.5, 3.2, 2.2)
        c.ell('fur', 20, 23, 12, 8.5, 0.35)
        c.limb('fur', 12, 25, 12, 41, 3.3, 2.7); c.ell('fur', 12.8, 41.6, 3.4, 2.3)
        c.ell('fur', 32, 33, 7, 7)
        c.limb('far', 34, 38, 46, 40.5, 2.4, 2.2)
        c.limb('fur', 33, 39, 44, 41.5, 2.6, 2.3); c.ell('fur', 45, 41.6, 3.2, 2.2)
        harness(c, 36, 30, 27, 26, 37)
        head(c, 39, 26, ear_swing=-1, mouth='open')
    elif pose == 'sleep':
        c.ell('fur', 8, 39, 6, 2.5)
        c.ell('fur', 24, 36, 17, 7)
        c.ell('fur', 15, 38, 7, 5)
        c.limb('fur', 36, 41, 50, 42, 2.4, 2.2); c.ell('fur', 51, 42, 3, 2)
        harness(c, 36, 33, 28, 31, 42)
        head(c, 40, 32, ear_swing=-0.5, eyes='closed')
        for (x,y) in ((52,22),(53,22),(54,22),(53,23),(52,24),(53,24),(54,24),(56,18),(57,18),(57,19),(56,20),(57,20)):
            c.px(x, y, 'G')
    elif pose == 'eat':
        c.ell('fur', 8, 15, 3, 5.5, -0.4); c.ell('fur', 6, 10, 2.6, 3)
        c.limb('far', 16, 28, 16, 41, 3.0, 2.6); c.ell('far', 16.5, 41.5, 3.2, 2.2)
        c.limb('far', 33, 30, 34, 41, 2.8, 2.4); c.ell('far', 34.8, 41.5, 3.2, 2.2)
        c.ell('fur', 22, 26, 14, 9, 0.12)
        c.limb('fur', 13, 30, 13, 41, 3.4, 2.7); c.ell('fur', 13.6, 41.6, 3.4, 2.3)
        c.limb('fur', 32, 31, 32, 41, 3.0, 2.5); c.ell('fur', 32.8, 41.6, 3.4, 2.3)
        c.ell('fur', 37, 28, 6, 7, 0.9)
        harness(c, 35, 26, 27, 21, 34)
        head(c, 41, 30, ear_swing=1)
        c.ell('bowl', 50, 41, 7, 3.4)
        for x in range(45, 56): c.px(x, 38, 'K')
    return c.render()

def carry(c, prop, x, y):
    x, y = int(x), int(y)
    if prop == 'ball':
        c.ell('ball', x+1.5, y+0.5, 3.4, 3.4)
        for (dx,dy) in ((0,-2),(1,-1),(2,0),(3,1)): c.px(x+dx, y+dy, 'w')
    elif prop == 'photo':
        for yy in range(y-6, y+7):
            for xx in range(x-1, x+10): c.px(xx, yy, 'w')
        for yy in range(y-5, y+3):
            for xx in range(x, x+9):
                k = 'p' if yy < y-2 else 'q'
                if (xx-x-4)**2 + (yy-y+1)**2 <= 5: k = 'm'
                c.px(xx, yy, k)
        for xx in range(x-1, x+10): c.px(xx, y-7, 'G'); c.px(xx, y+7, 'G')
        for yy in range(y-7, y+8): c.px(x-2, yy, 'G'); c.px(x+10, yy, 'G')
    elif prop == 'shot':
        for yy in range(y-6, y+6):
            for xx in range(x-1, x+9): c.px(xx, yy, 'g')
        for yy in range(y-4, y+1):
            for xx in range(x+1, x+7): c.px(xx, yy, 'B' if yy == y-4 else 'T')
        for xx in range(x-1, x+9): c.px(xx, y-7, 'G'); c.px(xx, y+6, 'G')
        for yy in range(y-7, y+7): c.px(x-2, yy, 'G'); c.px(x+9, yy, 'G')
        c.px(x+7, y-6, 'G'); c.px(x+8, y-5, 'G')

# Every frame the app uses, as (file name, pose, frame index, carried prop).
FRAMES = ([('stand', 'stand', 0, None), ('sit', 'sit', 0, None), ('sleep', 'sleep', 0, None),
           ('eat', 'eat', 0, None), ('play_bow', 'bow', 0, None)]
          + [(f'walk_{i}', 'walk', i, None) for i in range(4)]
          + [(f'run_{i}', 'run', i, None) for i in range(4)]
          + [(f'carry_ball_{i}', 'carry', i, 'ball') for i in range(4)])

if __name__ == '__main__':
    import sys, os
    if len(sys.argv) == 3 and sys.argv[1] == '--frames':
        # python3 tools/examples/make_mars_sprites.py --frames Pet/sprites
        os.makedirs(sys.argv[2], exist_ok=True)
        for name, pose, frame, prop in FRAMES:
            to_img(dog(pose, frame, prop)).save(os.path.join(sys.argv[2], name + '.png'))
        print(f'wrote {len(FRAMES)} frames to {sys.argv[2]}')
        sys.exit()
    # python3 tools/examples/make_mars_sprites.py preview.png  →  one contact sheet
    out = sys.argv[1]
    sheet = [('stand',0,None),('walk',0,None),('walk',1,None),('walk',2,None),('walk',3,None),('run',1,None),
             ('sit',0,None),('alert',0,None),('bow',0,None),('sleep',0,None),('eat',0,None),
             ('carry',1,'ball'),('carry',1,'photo'),('carry',1,'shot'),('sit',0,'photo')]
    S = 6
    ims = [to_img(dog(p,f,pr), S) for p,f,pr in sheet]
    cols = 5; rows = math.ceil(len(ims)/cols)
    big = Image.new('RGBA', (cols*W*S + (cols+1)*20, rows*H*S + (rows+1)*20), (246,241,231,255))
    for i, im in enumerate(ims):
        big.alpha_composite(im, (20 + (i%cols)*(W*S+20), 20 + (i//cols)*(H*S+20)))
    big.save(out)
