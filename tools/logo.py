"""PallyPower Integrator logo: blessing tiles, a golden arrow, a unit frame.
Drawn at 4x and downscaled for clean edges.  usage: python logo.py out.png [size] [icon_dir]
icon_dir holds the game icons as <name>.jpg (from wow.zamimg.com/images/wow/icons/large/);
without it the tiles use drawn glyphs instead."""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

K = 4                       # supersample
W = 512                     # design space
out_path = sys.argv[1]
out_size = int(sys.argv[2]) if len(sys.argv) > 2 else 512


def s(v):
    return int(round(v * K))


def box(b):
    return [s(x) for x in b]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


img = Image.new("RGBA", (s(W), s(W)), (0, 0, 0, 255))


def layer():
    return Image.new("RGBA", img.size, (0, 0, 0, 0))


def comp(l):
    img.alpha_composite(l)


def radial_bg():
    small = Image.new("RGBA", (256, 256))
    px = small.load()
    c_in, c_out = hexc("#232633"), hexc("#090a0e")
    for y in range(256):
        for x in range(256):
            d = math.hypot(x - 150, y - 118) / 190
            px[x, y] = lerp(c_in, c_out, min(1, d) ** 1.3)
    img.alpha_composite(small.resize(img.size, Image.BICUBIC))


def glow(draw_fn, radius, alpha=255):
    l = layer()
    draw_fn(ImageDraw.Draw(l))
    l = l.filter(ImageFilter.GaussianBlur(s(radius)))
    if alpha < 255:
        a = l.getchannel("A").point(lambda v: v * alpha // 255)
        l.putalpha(a)
    comp(l)


def grad_rrect(b, c1, c2, r):
    x0, y0, x1, y1 = box(b)
    g = Image.new("RGBA", (x1 - x0, y1 - y0))
    gd = ImageDraw.Draw(g)
    for y in range(y1 - y0):
        gd.line([(0, y), (x1 - x0, y)], fill=lerp(c1, c2, y / max(1, y1 - y0 - 1)))
    m = Image.new("L", g.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, g.size[0] - 1, g.size[1] - 1], s(r), fill=255)
    l = layer()
    l.paste(g, (x0, y0), m)
    comp(l)


# ---------------------------------------------------------------- glyphs
CREAM = hexc("#fff4d6")
SHADE = (0, 0, 0, 110)


def glyph(fn, cx, cy, sc):
    """draw a glyph with a soft drop shadow; fn(d, cx, cy, sc, colour)"""
    l = layer()
    fn(ImageDraw.Draw(l), cx + 2 * sc / 40, cy + 3 * sc / 40, sc, SHADE)
    comp(l.filter(ImageFilter.GaussianBlur(s(2 * sc / 40))))
    l = layer()
    fn(ImageDraw.Draw(l), cx, cy, sc, CREAM)
    comp(l)


def P(cx, cy, sc, pts):
    return [(s(cx + x * sc / 40), s(cy + y * sc / 40)) for x, y in pts]


def sword(d, cx, cy, sc, c):
    d.polygon(P(cx, cy, sc, [(0, -30), (6, -22), (5, 12), (-5, 12), (-6, -22)]), fill=c)
    d.polygon(P(cx, cy, sc, [(-17, 11), (17, 11), (17, 17), (-17, 17)]), fill=c)
    d.polygon(P(cx, cy, sc, [(-3.5, 17), (3.5, 17), (3.5, 28), (-3.5, 28)]), fill=c)
    (x, y), = P(cx, cy, sc, [(0, 32)])
    r = s(5.5 * sc / 40)
    d.ellipse([x - r, y - r, x + r, y + r], fill=c)


def book(d, cx, cy, sc, c):
    d.polygon(P(cx, cy, sc, [(-2, -16), (-28, -22), (-28, 18), (-2, 24)]), fill=c)
    d.polygon(P(cx, cy, sc, [(2, -16), (28, -22), (28, 18), (2, 24)]), fill=c)
    # a radiant star above the pages
    for a in range(0, 360, 45):
        ln = 9 if a % 90 == 0 else 5
        x1 = math.sin(math.radians(a)) * ln
        y1 = -math.cos(math.radians(a)) * ln
        d.line(P(cx, cy, sc, [(0, -27), (x1, -27 + y1)]), fill=c, width=s(2.6 * sc / 40))


def crown(d, cx, cy, sc, c):
    d.polygon(P(cx, cy, sc, [(-26, 18), (-28, -14), (-14, 2), (0, -22), (14, 2), (28, -14), (26, 18)]), fill=c)
    d.polygon(P(cx, cy, sc, [(-26, 21), (26, 21), (26, 27), (-26, 27)]), fill=c)
    for x, y in [(-28, -17), (0, -26), (28, -17)]:
        (px, py), = P(cx, cy, sc, [(x, y)])
        r = s(4.5 * sc / 40)
        d.ellipse([px - r, py - r, px + r, py + r], fill=c)


def shield(d, cx, cy, sc, c):
    pts = [(-24, -24), (24, -24), (24, 0)]
    for i in range(1, 12):
        t = i / 12
        pts.append((24 * (1 - t), t * 28 + (1 - t) * 0 + math.sin(t * math.pi) * 2))
    pts += [(0, 30)]
    for i in range(11, 0, -1):
        t = i / 12
        pts.append((-24 * (1 - t), t * 28 + math.sin(t * math.pi) * 2))
    pts += [(-24, 0)]
    d.polygon(P(cx, cy, sc, pts), fill=c)
    # the cross, cut back out in the tile colour's shadow
    cut = (0, 0, 0, 0) if c[3] < 255 else hexc("#1c6b52")
    d.polygon(P(cx, cy, sc, [(-3.5, -17), (3.5, -17), (3.5, 19), (-3.5, 19)]), fill=cut)
    d.polygon(P(cx, cy, sc, [(-15, -6), (15, -6), (15, 1), (-15, 1)]), fill=cut)


BLESSINGS = [  # name, top colour, bottom colour, glyph, game icon (PallyPower's Greater Blessing icons)
    ("Might", "#f2a33a", "#a52a1c", sword, "spell_holy_greaterblessingofkings"),
    ("Wisdom", "#5fb0ff", "#1d3f93", book, "spell_holy_greaterblessingofwisdom"),
    ("Kings", "#c99bf0", "#4b1f78", crown, "spell_magic_greaterblessingofkings"),
    ("Salvation", "#5fe0b0", "#1c6b52", shield, "spell_holy_greaterblessingofsalvation"),
]

# optional third argument: a folder of <icon>.jpg game icons to use instead of the drawn glyphs
ICON_DIR = sys.argv[3] if len(sys.argv) > 3 else None


def game_icon(name, size):
    """the game icon, its baked-in edge trimmed (as EllesmereUI squares icons), at size x size"""
    import os
    path = os.path.join(ICON_DIR, name + ".jpg")
    if not (ICON_DIR and os.path.exists(path)):
        return None
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    t = round(w * 0.07)
    return im.crop((t, t, w - t, h - t)).resize((s(size), s(size)), Image.LANCZOS)


def tile(x, y, size, bless, picked=False):
    name, top, bot, fn, icon = bless
    if picked:
        glow(lambda d: d.rounded_rectangle(box([x - 6, y - 6, x + size + 6, y + size + 6]), s(16),
                                           fill=hexc("#ffcf5a")), 9, 230)
    # dark border, then the game icon or a gradient body with a drawn glyph
    grad_rrect([x - 3, y - 3, x + size + 3, y + size + 3], (8, 8, 10, 255), (8, 8, 10, 255), 13)
    art = game_icon(icon, size) if ICON_DIR else None
    if art:
        m = Image.new("L", art.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, art.size[0] - 1, art.size[1] - 1], s(10), fill=255)
        l = layer()
        l.paste(art, (s(x), s(y)), m)
        comp(l)
    else:
        grad_rrect([x, y, x + size, y + size], hexc(top), hexc(bot), 10)
    l = layer()
    d = ImageDraw.Draw(l)
    d.rounded_rectangle(box([x + 2, y + 2, x + size - 2, y + size - 2]), s(9),
                        outline=(255, 255, 255, 55 if art else 70), width=s(1.5))
    if not art:
        # glossy top sheen
        d.rounded_rectangle(box([x + 4, y + 4, x + size - 4, y + size * 0.45]), s(8), fill=(255, 255, 255, 28))
    comp(l)
    if not art:
        glyph(fn, x + size / 2, y + size / 2, size * 0.42)
    if picked:
        l = layer()
        ImageDraw.Draw(l).rounded_rectangle(box([x - 3, y - 3, x + size + 3, y + size + 3]), s(13),
                                            outline=hexc("#ffd970"), width=s(3))
        comp(l)


# ---------------------------------------------------------------- scene
radial_bg()

# soft paladin-gold halo behind the frame
glow(lambda d: d.ellipse(box([210, 130, 500, 380]), fill=hexc("#f5c860")), 70, 60)

# blessing column
T, G, X0, Y0 = 82, 18, 40, 58
for i, b in enumerate(BLESSINGS):
    tile(X0, Y0 + i * (T + G), T, b, picked=(i == 2))

# ---- unit frame
FX0, FY0, FX1, FY1 = 222, 226, 482, 330      # outer
PW = FY1 - FY0                                 # square portrait
glow(lambda d: d.rectangle(box([FX0, FY0, FX1, FY1]), fill=(0, 0, 0, 255)), 10, 200)
l = layer()
d = ImageDraw.Draw(l)
d.rectangle(box([FX0 - 3, FY0 - 3, FX1 + 3, FY1 + 3]), fill=hexc("#050506"))
comp(l)

# portrait: a paladin helm on deep blue
grad_rrect([FX0, FY0, FX0 + PW, FY1], hexc("#2c3f72"), hexc("#111a33"), 0)
l = layer()
d = ImageDraw.Draw(l)
hx = FX0 + PW / 2
fig = hexc("#9fb2dd")
d.ellipse(box([hx - 19, FY0 + 20, hx + 19, FY0 + 58]), fill=fig)            # head
# shoulders: the top half of an ellipse whose centre sits on the frame's bottom edge
d.chord(box([hx - 40, FY0 + 64, hx + 40, 2 * FY1 - (FY0 + 64)]), 180, 360, fill=fig)
comp(l)

# health (paladin pink) and power bars
BX = FX0 + PW + 2
HY1 = FY0 + 72
grad_rrect([BX, FY0, FX1, HY1], hexc("#151519"), hexc("#0c0c0f"), 0)
grad_rrect([BX, FY0, BX + (FX1 - BX) * 0.82, HY1], hexc("#ffa8d0"), hexc("#d9679c"), 0)
grad_rrect([BX, HY1 + 2, FX1, FY1], hexc("#4f93ff"), hexc("#2456c4"), 0)

# the blessing icon on the frame, with a cooldown swipe
IS = 50
IX, IY = FX1 - IS - 10, FY0 + (72 - IS) / 2
tile(IX, IY, IS, BLESSINGS[2])
l = layer()
ImageDraw.Draw(l).pieslice(box([IX - 12, IY - 12, IX + IS + 12, IY + IS + 12]), -90, -90 + 110,
                           fill=(0, 0, 0, 150))
m = Image.new("L", img.size, 0)
ImageDraw.Draw(m).rounded_rectangle(box([IX, IY, IX + IS, IY + IS]), s(8), fill=255)
l.putalpha(Image.composite(l.getchannel("A"), Image.new("L", img.size, 0), m))
comp(l)

# ---- the arrow: from the picked tile, arcing over to the icon on the frame
p0 = (X0 + T + 16, Y0 + 2 * (T + G) + T / 2)
p2 = (IX + IS / 2, IY - 16)
p1 = (300, 70)


def bez(t):
    return ((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
            (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])


pts = [bez(i / 120) for i in range(0, 109)]   # stop short: the head covers the end
tx, ty = p2[0] - bez(0.97)[0], p2[1] - bez(0.97)[1]
n = math.hypot(tx, ty)
tx, ty = tx / n, ty / n
nx, ny = -ty, tx
HL, HW = 34, 22
base = (p2[0] - tx * HL, p2[1] - ty * HL)
head = [p2, (base[0] + nx * HW, base[1] + ny * HW), (base[0] + tx * 6, base[1] + ty * 6),
        (base[0] - nx * HW, base[1] - ny * HW)]


def draw_arrow(d, width, colour):
    d.line([(s(x), s(y)) for x, y in pts], fill=colour, width=s(width), joint="curve")
    x, y = pts[0]
    r = s(width / 2)
    d.ellipse([s(x) - r, s(y) - r, s(x) + r, s(y) + r], fill=colour)
    hd = [(s(x), s(y)) for x, y in head]
    d.polygon(hd, fill=colour)
    if width > 14:
        d.line(hd + [hd[0]], fill=colour, width=s(width - 14), joint="curve")


glow(lambda d: draw_arrow(d, 20, hexc("#ffcf5a")), 10, 200)
l = layer()
draw_arrow(ImageDraw.Draw(l), 22, hexc("#1a1206"))
comp(l)
l = layer()
draw_arrow(ImageDraw.Draw(l), 13, hexc("#ffd767"))
comp(l)
# a bright core along the shaft
l = layer()
ImageDraw.Draw(l).line([(s(x), s(y - 1.5)) for x, y in pts[4:-6]], fill=hexc("#fff6d2"), width=s(4),
                       joint="curve")
comp(l.filter(ImageFilter.GaussianBlur(s(0.8))))

# scroll-wheel hint: a small mouse under the frame
mx, my = 352, 372
l = layer()
d = ImageDraw.Draw(l)
d.rounded_rectangle(box([mx - 22, my, mx + 22, my + 62]), s(20), outline=hexc("#d8dbe6"), width=s(4))
d.line(box([mx - 22, my + 24, mx + 22, my + 24]), fill=hexc("#d8dbe6"), width=s(3))
d.line(box([mx, my, mx, my + 24]), fill=hexc("#d8dbe6"), width=s(3))
d.rounded_rectangle(box([mx - 4, my + 6, mx + 4, my + 19]), s(4), fill=hexc("#ffcf5a"))
for sgn in (-1, 1):   # up (^) above, down (v) below, either side of the mouse
    cy = my + 31 + sgn * 15
    for side in (-1, 1):
        cx = mx + side * 44
        tip, wing = cy + sgn * 5, cy - sgn * 5
        d.line(box([cx - 9, wing, cx, tip]), fill=hexc("#ffcf5a"), width=s(4))
        d.line(box([cx, tip, cx + 9, wing]), fill=hexc("#ffcf5a"), width=s(4))
comp(l)

img.convert("RGB").resize((out_size, out_size), Image.LANCZOS).save(out_path, optimize=True)
print("wrote", out_path, out_size)
