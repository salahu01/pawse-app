"""Builds Resources/AppIcon.icns + docs/icon.png from a 3D render of Mochi.
usage: python3 tools/make_icon.py <cat_render.png>
(render with: PAWSE_RENDER_SIZE=1400 .build/release/Pawse --render-pet cat asking cat.png)"""
import sys, os, subprocess, shutil, math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024
canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

def rounded_mask(size, box, r):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, r, fill=255)
    return m

box = (100, 100, 924, 924)
mask = rounded_mask(S, box, 186)

# soft drop shadow (macOS icon grid)
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh.putalpha(rounded_mask(S, (100, 112, 924, 936), 186).point(lambda v: v * 0.35))
canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))

# vertical gradient sky -> lavender, with a warm glow behind the pet
grad = Image.new("RGBA", (S, S))
top, bot = (178, 222, 255), (233, 214, 255)
px = grad.load()
for y in range(S):
    t = y / S
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    for x in range(S):
        px[x, y] = c + (255,)
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((262, 300, 762, 800), fill=150)
glow = glow.filter(ImageFilter.GaussianBlur(90))
grad = Image.composite(Image.new("RGBA", (S, S), (255, 248, 236, 255)), grad, glow)
tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
tile.paste(grad, (0, 0), mask)
canvas.alpha_composite(tile)

# the pet
cat = Image.open(sys.argv[1]).convert("RGBA")
bb = cat.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
cat = cat.crop(bb)
h = 650
cat = cat.resize((int(cat.width * h / cat.height), h), Image.LANCZOS)
pet = Image.new("RGBA", (S, S), (0, 0, 0, 0))
pet.alpha_composite(cat, ((S - cat.width) // 2 - 10, 924 - h - 38))
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(pet, (0, 0), ImageChops.multiply(pet.getchannel("A"), mask))
canvas.alpha_composite(clipped)

d = ImageDraw.Draw(canvas)
# water drop, top-left
def drop(cx, cy, r):
    pts = [(cx, cy - r * 1.9)]
    for a in range(-30, 211, 6):
        rad = math.radians(a)
        pts.append((cx + r * math.cos(rad), cy + r * math.sin(rad)))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(pts, fill=(64, 156, 255, 255))
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse((cx - r * 0.55, cy - r * 0.6, cx - r * 0.15, cy - r * 0.05), fill=(255, 255, 255, 190))
    sh = layer.filter(ImageFilter.GaussianBlur(6)); sh.putalpha(sh.getchannel("A").point(lambda v: v * 0.25))
    canvas.alpha_composite(sh, (0, 6)); canvas.alpha_composite(layer); canvas.alpha_composite(hl)
drop(250, 300, 52)

# pause badge, bottom-right
cx, cy, r = 778, 778, 92
b = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(b)
bd.ellipse((cx - r, cy - r + 8, cx + r, cy + r + 8), fill=(80, 60, 140, 70))
b = b.filter(ImageFilter.GaussianBlur(8))
bd = ImageDraw.Draw(b)
bd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 255))
for dx in (-30, 30):
    bd.rounded_rectangle((cx + dx - 16, cy - 42, cx + dx + 16, cy + 42), 14, fill=(255, 112, 140, 255))
canvas.alpha_composite(b)

os.makedirs(f"{ROOT}/docs", exist_ok=True)
canvas.save(f"{ROOT}/docs/icon.png")

iconset = "/tmp/Pawse.iconset"
shutil.rmtree(iconset, ignore_errors=True); os.makedirs(iconset)
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px_ = base * scale
        canvas.resize((px_, px_), Image.LANCZOS).save(f"{iconset}/icon_{base}x{base}{'@2x' if scale == 2 else ''}.png")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", f"{ROOT}/Resources/AppIcon.icns"], check=True)
print("wrote docs/icon.png and Resources/AppIcon.icns")
