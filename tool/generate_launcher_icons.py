"""Generates the Android launcher icons from the store icon (needs Pillow).

Usage: python3 tool/generate_launcher_icons.py branding/store_icon_512.png android/app/src/main/res <preview_dir>
"""
import math, sys
from PIL import Image, ImageFilter, ImageDraw, ImageChops
SRC, RES, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
im = Image.open(SRC).convert('RGB')
N = 512
R = 118          # corner radius of the artwork's rounded square
px = im.load()

# 1) Full-bleed square: extend the gradient radially into the white rounded corners.
full = im.copy(); fp = full.load()
for cx, cy, xs, ys in [(R, R, range(0, R), range(0, R)), (N-1-R, R, range(N-R, N), range(0, R)),
                       (R, N-1-R, range(0, R), range(N-R, N)), (N-1-R, N-1-R, range(N-R, N), range(N-R, N))]:
    for y in ys:
        for x in xs:
            dx, dy = x - cx, y - cy
            d = math.hypot(dx, dy)
            if d > R - 10:
                s = (R - 12) / d
                fp[x, y] = px[round(cx + dx * s), round(cy + dy * s)]
# light anti-aliased rim on the straight edges: copy from 3 px inside
for i in range(N):
    for k in range(3):
        fp[i, k] = fp[i, 3]; fp[i, N-1-k] = fp[i, N-4]; fp[k, i] = fp[3, i]; fp[N-1-k, i] = fp[N-4, i]
full.save(f'{OUT}/full_bleed.png')

# 2) Adaptive icon layer (108 dp): artwork at 68 dp in the centre, edges extended + blurred around it.
def adaptive(size):
    inner = round(size * 68 / 108)  # content stays inside the 66 dp safe circle
    off = (size - inner) // 2
    art = full.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new('RGB', (size, size))
    ap = art.load(); cp = canvas.load()
    for y in range(size):
        for x in range(size):
            cp[x, y] = ap[min(max(x - off, 0), inner - 1), min(max(y - off, 0), inner - 1)]
    blurred = canvas.filter(ImageFilter.GaussianBlur(size / 30))
    mask = Image.new('L', (size, size), 255)
    ImageDraw.Draw(mask).rectangle([off + 2, off + 2, off + inner - 3, off + inner - 3], fill=0)
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    return Image.composite(blurred, canvas, mask)

# 3) Legacy icon (pre-Android 8): the artwork with transparent rounded corners.
def legacy(size):
    big = full.resize((size * 4, size * 4), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', big.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, big.size[0] - 1, big.size[1] - 1], radius=round(R / N * big.size[0]), fill=255)
    big.putalpha(m)
    return big.resize((size, size), Image.LANCZOS)

dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, f in dens.items():
    adaptive(round(108 * f)).save(f'{RES}/mipmap-{name}/ic_launcher_background.png', optimize=True)
    legacy(round(48 * f)).save(f'{RES}/mipmap-{name}/ic_launcher.png', optimize=True)

# Previews of common launcher masks (circle, squircle, rounded square) at 432 px.
layer = adaptive(432)
vis = layer.crop((18 * 4, 18 * 4, 90 * 4, 90 * 4))  # visible 72 dp
row = Image.new('RGB', (3 * 300 + 40, 320), 'white')
for i, shape in enumerate(['circle', 'squircle', 'rounded']):
    v = vis.resize((288, 288), Image.LANCZOS)
    m = Image.new('L', (288, 288), 0); d = ImageDraw.Draw(m)
    if shape == 'circle': d.ellipse([0, 0, 287, 287], fill=255)
    elif shape == 'squircle': d.rounded_rectangle([0, 0, 287, 287], radius=100, fill=255)
    else: d.rounded_rectangle([0, 0, 287, 287], radius=40, fill=255)
    row.paste(v, (10 + i * 310, 16), m)
row.save(f'{OUT}/preview_masks.png')
