"""BuffLedger logo: an open ledger with a bookmark ribbon and a fan of
class-coloured buff icons. Draws at 4x and downsamples. Produces an
icon-only version and one with the name."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 4
SIZE = 1024
W = SIZE * S
OUT = sys.argv[1]

GOLD = (232, 196, 106)
GOLD_DARK = (150, 112, 38)
PAGE = (236, 222, 186)
PAGE_SHADE = (214, 196, 156)
LINE = (150, 132, 100)
COVER = (72, 40, 24)
COVER_DARK = (46, 24, 14)
PURPLE = (163, 53, 238)
PURPLE_DARK = (110, 30, 170)
BG = (22, 17, 14)
BG_EDGE = (12, 9, 7)

# Class colours, as the bar draws them.
PALADIN = (245, 140, 186)
MAGE = (64, 199, 235)
PRIEST = (255, 255, 255)
DRUID = (255, 125, 10)
HUNTER = (171, 212, 115)
SHAMAN = (0, 112, 222)


def s(v):
    return int(round(v * S))


def mix(a, b, t):
    return tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3))


def radial_background():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    grad = Image.new("RGBA", (W, W), BG_EDGE + (255,))
    gd = ImageDraw.Draw(grad)
    steps = 60
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(W * 0.78 * t)
        c = tuple(int(BG_EDGE[k] + (BG[k] + 14 - BG_EDGE[k]) * (1 - t)) for k in range(3))
        gd.ellipse([W // 2 - r, W // 2 - r - s(60), W // 2 + r, W // 2 + r - s(60)], fill=c + (255,))
    grad = grad.filter(ImageFilter.GaussianBlur(s(40)))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=s(190), fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([s(14), s(14), W - s(14), W - s(14)], radius=s(178), outline=GOLD_DARK, width=s(14))
    d.rounded_rectangle([s(22), s(22), W - s(22), W - s(22)], radius=s(170), outline=GOLD, width=s(5))
    return img


def draw_book(d, cx, cy, width, height):
    """Open book centred at (cx, cy); the right page lists colour-coded entries."""
    half = width / 2
    spine = s(10)
    top, bottom = cy - height / 2, cy + height / 2
    pad = s(22)
    d.rounded_rectangle([cx - half - pad, top - pad, cx + half + pad, bottom + pad], radius=s(26), fill=COVER_DARK)
    d.rounded_rectangle([cx - half - pad + s(6), top - pad + s(6), cx + half + pad - s(6), bottom + pad - s(6)], radius=s(22), fill=COVER)
    for i in range(3, 0, -1):
        off = s(6) * i
        d.rounded_rectangle([cx - half - off, top + off, cx - spine, bottom + off], radius=s(10), fill=PAGE_SHADE)
        d.rounded_rectangle([cx + spine, top + off, cx + half + off, bottom + off], radius=s(10), fill=PAGE_SHADE)
    d.rounded_rectangle([cx - half, top, cx - spine, bottom], radius=s(10), fill=PAGE)
    d.rounded_rectangle([cx + spine, top, cx + half, bottom], radius=s(10), fill=PAGE)
    for i in range(18):
        t = i / 18
        c = mix(PAGE_SHADE, PAGE, t)
        d.rectangle([cx - spine - s(3) * (18 - i), top, cx - spine - s(3) * (17 - i), bottom], fill=c)
        d.rectangle([cx + spine + s(3) * (17 - i), top, cx + spine + s(3) * (18 - i), bottom], fill=c)
    d.rectangle([cx - spine, top - pad + s(6), cx + spine, bottom + pad - s(6)], fill=COVER_DARK)
    margin = s(40)
    lines = 7
    gap = (height - 2 * margin) / (lines - 1)
    for i in range(lines):
        y = top + margin + gap * i
        d.line([cx - half + margin, y, cx - spine - margin, y], fill=LINE, width=s(5))
        d.line([cx + spine + margin, y, cx + half - margin, y], fill=LINE, width=s(5))
    # Entries: a name on the left page, a coloured category chip on the right.
    chips = [SHAMAN, PALADIN, MAGE, HUNTER, DRUID]
    for i in range(1, lines - 1):
        y = top + margin + gap * i - s(18)
        d.rounded_rectangle([cx - half + margin, y + s(2), cx - half + margin + s(70 + (i * 37) % 60), y + s(14)], radius=s(6), fill=(110, 90, 60))
        x1 = cx + half - margin
        d.rounded_rectangle([x1 - s(34), y - s(8), x1, y + s(26) - s(8)], radius=s(5), fill=(60, 44, 30))
        d.rounded_rectangle([x1 - s(30), y - s(4), x1 - s(4), y + s(22) - s(8)], radius=s(3), fill=chips[(i - 1) % len(chips)])


def draw_ribbon(d, x, top, bottom):
    w = s(52)
    pts = [(x - w / 2, top), (x + w / 2, top), (x + w / 2, bottom), (x, bottom - s(40)), (x - w / 2, bottom)]
    d.polygon(pts, fill=PURPLE_DARK)
    inner = [(x - w / 2 + s(8), top), (x + w / 2 - s(8), top), (x + w / 2 - s(8), bottom - s(10)), (x, bottom - s(44)), (x - w / 2 + s(8), bottom - s(10))]
    d.polygon(inner, fill=PURPLE)


# --- buff tiles ---------------------------------------------------------

def glyph_star(d, c, r, fill):
    cx, cy = c
    pts = []
    for k in range(8):
        rad = r if k % 2 == 0 else r * 0.30
        import math
        a = math.pi / 2 + k * math.pi / 4
        pts.append((cx + rad * math.cos(a), cy - rad * math.sin(a)))
    d.polygon(pts, fill=fill)


def glyph_shield(d, c, r, fill):
    cx, cy = c
    pts = [(cx - r * 0.78, cy - r * 0.80), (cx + r * 0.78, cy - r * 0.80), (cx + r * 0.78, cy - r * 0.05),
           (cx + r * 0.55, cy + r * 0.50), (cx, cy + r * 0.95), (cx - r * 0.55, cy + r * 0.50), (cx - r * 0.78, cy - r * 0.05)]
    d.polygon(pts, fill=fill)


def glyph_cross(d, c, r, fill):
    cx, cy = c
    t = r * 0.30
    d.rounded_rectangle([cx - t, cy - r * 0.9, cx + t, cy + r * 0.9], radius=t * 0.5, fill=fill)
    d.rounded_rectangle([cx - r * 0.9, cy - t, cx + r * 0.9, cy + t], radius=t * 0.5, fill=fill)


def glyph_moon(img, c, r, fill):
    cx, cy = c
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([cx - r * 0.85, cy - r * 0.85, cx + r * 0.85, cy + r * 0.85], fill=255)
    off = r * 0.42
    md.ellipse([cx - r * 0.85 + off, cy - r * 0.85 - off * 0.5, cx + r * 0.85 + off, cy + r * 0.85 - off * 0.5], fill=0)
    solid = Image.new("RGBA", img.size, fill + (255,))
    img.paste(solid, (0, 0), mask)


def buff_tile(size, color, glyph):
    """One buff icon: category-coloured edge around a dark tinted face."""
    canvas = int(size * 1.5)
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    o = (canvas - size) / 2
    edge = s(12)
    d.rounded_rectangle([o, o, o + size, o + size], radius=s(12), fill=(12, 10, 8))
    d.rounded_rectangle([o + s(3), o + s(3), o + size - s(3), o + size - s(3)], radius=s(10), fill=color)
    # face: vertical gradient from a lit tint to a deep one
    inner = [o + edge, o + edge, o + size - edge, o + size - edge]
    face_h = inner[3] - inner[1]
    for i in range(int(face_h)):
        t = i / face_h
        c = mix(mix(color, (255, 255, 255), 0.05), mix(color, (0, 0, 0), 0.72), 0.35 + 0.65 * t)
        d.line([inner[0], inner[1] + i, inner[2], inner[1] + i], fill=c)
    # glint along the top of the face
    d.rectangle([inner[0], inner[1], inner[2], inner[1] + s(6)], fill=mix(color, (255, 255, 255), 0.5))
    centre = (canvas / 2, canvas / 2 + s(2))
    r = size * 0.30
    glyph_fill = mix(color, (255, 255, 255), 0.75)
    if glyph == "moon":
        glyph_moon(img, centre, r, glyph_fill)
    else:
        {"star": glyph_star, "shield": glyph_shield, "cross": glyph_cross}[glyph](d, centre, r, glyph_fill)
    return img


def place_tile(base, tile, cx, cy, angle):
    rotated = tile.rotate(angle, resample=Image.BICUBIC, expand=True)
    shadow = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 170), (0, 0), rotated.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(14)))
    x = int(cx - rotated.size[0] / 2)
    y = int(cy - rotated.size[1] / 2)
    base.alpha_composite(shadow, (x + s(6), y + s(14)))
    base.alpha_composite(rotated, (x, y))


def render(with_text):
    img = radial_background()
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    book_w, book_h = s(640), s(400)
    cx, cy = W // 2, W // 2 - (s(70) if with_text else s(10))
    sd.rounded_rectangle([cx - book_w / 2 - s(30), cy - book_h / 2 + s(30), cx + book_w / 2 + s(30), cy + book_h / 2 + s(60)], radius=s(40), fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(28)))
    img = Image.alpha_composite(img, shadow)

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    draw_book(d, cx, cy, book_w, book_h)
    draw_ribbon(d, cx + s(190), cy - book_h / 2 - s(24), cy + book_h / 2 + s(90))
    img = Image.alpha_composite(img, layer)

    # A fanned hand of buff icons over the bottom-left of the book.
    tile = s(150)
    base_y = cy + book_h / 2 + s(10)
    fan = [
        (-330, 22, 14, MAGE, "star"),
        (-215, -4, 5, PALADIN, "shield"),
        (-100, 6, -5, PRIEST, "cross"),
    ]
    for dx, dy, angle, color, glyph in fan:
        place_tile(img, buff_tile(tile, color, glyph), cx + s(dx), base_y + s(dy), angle)
    place_tile(img, buff_tile(tile, DRUID, "moon"), cx + s(15), base_y + s(28), -14)

    if with_text:
        text = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        td = ImageDraw.Draw(text)
        font = ImageFont.truetype("C:/Windows/Fonts/palab.ttf", s(118))
        label = "BuffLedger"
        bbox = td.textbbox((0, 0), label, font=font)
        tw = bbox[2] - bbox[0]
        tx = (W - tw) / 2 - bbox[0]
        ty = W - s(250)
        for dx, dy in [(-3, -3), (3, -3), (-3, 3), (3, 3), (0, 4), (4, 0), (-4, 0), (0, -4)]:
            td.text((tx + s(dx), ty + s(dy)), label, font=font, fill=(20, 12, 8))
        td.text((tx, ty + s(8)), label, font=font, fill=(0, 0, 0, 160))
        td.text((tx, ty), label, font=font, fill=GOLD)
        img = Image.alpha_composite(img, text)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


render(True).save(OUT + "/logo.png")
render(False).save(OUT + "/icon.png")
render(False).resize((256, 256), Image.LANCZOS).save(OUT + "/icon-256.png")
print("done")
