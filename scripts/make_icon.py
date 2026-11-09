#!/usr/bin/env python3
"""Erzeugt das App-Symbol von Android Bridge 4.0 (Resources/AppIcon.iconset + AppIcon-1024.png).

Motiv „Midnight Glass“: auf einer tiefen Graphitfläche steht ein Telefon, dessen Bildschirm im Signal-Grün
leuchtet; ein Lichtbogen führt zu einem kleinen Notebook. Weiches Licht statt Linien, Glasreflex oben.
macOS-Symbolraster (1024 px, Fläche 824 px, Eckenradius ≈ 185 px). Eigene Zeichnung, keine fremden Motive.
Aufruf:  python3 scripts/make_icon.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "Resources")
S = 4                     # Überabtastung
N = 1024 * S


def px(v):
    return int(round(v * S))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def vertical_gradient(size, top, bottom):
    w, h = size
    g = Image.new("RGBA", (1, 256))
    for y in range(256):
        g.putpixel((0, y), lerp(top, bottom, y / 255))
    return g.resize((w, h), Image.BILINEAR)


def radial(size, center, radius, color, alpha):
    w, h = size
    layer = Image.new("RGBA", size, color + (0,))
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    steps = 60
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(alpha * (1 - i / steps) ** 1.6)
        d.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r], fill=a)
    layer.putalpha(mask)
    return layer


def rounded(size, box, radius, fill):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius, fill=fill)
    return layer


def main():
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    x0, y0, x1, y1 = px(100), px(100), px(924), px(924)
    radius = px(185)
    size = (N, N)

    # Grundfläche
    base = vertical_gradient((x1 - x0, y1 - y0), (34, 40, 46, 255), (5, 7, 9, 255))
    plate = Image.new("RGBA", size, (0, 0, 0, 0))
    plate.paste(base, (x0, y0))
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=255)

    # Lichtfelder
    plate = Image.alpha_composite(plate, radial(size, (px(300), px(760)), px(560), (50, 120, 255), 150))
    plate = Image.alpha_composite(plate, radial(size, (px(820), px(200)), px(420), (140, 90, 255), 110))
    plate = Image.alpha_composite(plate, radial(size, (px(700), px(900)), px(380), (255, 95, 170), 55))

    # Lichtbogen Telefon → Notebook (unter den Geräten)
    beam = Image.new("RGBA", size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(beam)
    pts = []
    for i in range(101):
        t = i / 100
        # kubische Bézier
        p0, p1, p2, p3 = (455, 640), (560, 760), (640, 560), (740, 590)
        x = (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t ** 2 * p2[0] + t ** 3 * p3[0]
        y = (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t ** 2 * p2[1] + t ** 3 * p3[1]
        pts.append((px(x), px(y)))
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(pts, fill=(90, 150, 255, 230), width=px(60), joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(px(30)))
    plate = Image.alpha_composite(plate, glow)
    bd.line(pts, fill=(215, 230, 255, 255), width=px(9), joint="curve")
    plate = Image.alpha_composite(plate, beam)

    # Notebook (rechts, klein)
    lx0, ly0, lx1, ly1 = px(600), px(400), px(870), px(580)
    plate = Image.alpha_composite(plate, rounded(size, [lx0, ly0, lx1, ly1], px(14), (70, 78, 88, 255)))
    plate = Image.alpha_composite(plate, rounded(size, [lx0 + px(7), ly0 + px(7), lx1 - px(7), ly1 - px(4)], px(9), (8, 10, 13, 255)))
    screen = vertical_gradient((lx1 - lx0 - px(22), ly1 - ly0 - px(22)), (20, 50, 110, 255), (40, 20, 90, 255))
    sc = Image.new("RGBA", size, (0, 0, 0, 0))
    sc.paste(screen, (lx0 + px(11), ly0 + px(11)))
    plate = Image.alpha_composite(plate, sc)
    plate = Image.alpha_composite(plate, rounded(size, [lx0 - px(26), ly1, lx1 + px(26), ly1 + px(16)], px(8), (150, 158, 168, 255)))

    # Telefon (links, groß) mit Schatten
    fx0, fy0, fx1, fy1 = px(250), px(230), px(470), px(760)
    shadow = rounded(size, [fx0 + px(10), fy0 + px(30), fx1 + px(10), fy1 + px(30)], px(46), (0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(30)))
    plate = Image.alpha_composite(plate, shadow)
    plate = Image.alpha_composite(plate, rounded(size, [fx0, fy0, fx1, fy1], px(46), (120, 128, 138, 255)))
    plate = Image.alpha_composite(plate, rounded(size, [fx0 + px(5), fy0 + px(5), fx1 - px(5), fy1 - px(5)], px(42), (10, 12, 15, 255)))
    sx0, sy0, sx1, sy1 = fx0 + px(16), fy0 + px(16), fx1 - px(16), fy1 - px(16)
    scr = vertical_gradient((sx1 - sx0, sy1 - sy0), (90, 160, 255, 255), (120, 80, 240, 255))
    smask = Image.new("L", (sx1 - sx0, sy1 - sy0), 0)
    ImageDraw.Draw(smask).rounded_rectangle([0, 0, sx1 - sx0 - 1, sy1 - sy0 - 1], radius=px(32), fill=255)
    scr.putalpha(smask)
    sl = Image.new("RGBA", size, (0, 0, 0, 0))
    sl.paste(scr, (sx0, sy0), scr)
    plate = Image.alpha_composite(plate, sl)
    # Lichtpunkt auf dem Bildschirm
    plate = Image.alpha_composite(plate, radial(size, (px(330), px(360)), px(200), (255, 255, 255), 110))
    # Kameraloch
    cam = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(cam).ellipse([px(352), px(258), px(368), px(274)], fill=(8, 10, 12, 255))
    plate = Image.alpha_composite(plate, cam)
    # Pfeilsymbol (Übertragung) auf dem Bildschirm
    arrow = Image.new("RGBA", size, (0, 0, 0, 0))
    ad = ImageDraw.Draw(arrow)
    ad.line([(px(300), px(500)), (px(392), px(500))], fill=(255, 255, 255, 240), width=px(24))
    ad.polygon([(px(380), px(450)), (px(380), px(550)), (px(432), px(500))], fill=(255, 255, 255, 240))
    plate = Image.alpha_composite(plate, arrow)

    # Glasreflex oben und feine Lichtkante
    sheen = Image.new("RGBA", size, (255, 255, 255, 0))
    sm = Image.new("L", size, 0)
    sd = ImageDraw.Draw(sm)
    for i in range(80):
        a = int(46 * (1 - i / 80))
        sd.rectangle([x0, y0 + px(i * 4), x1, y0 + px(i * 4 + 4)], fill=a)
    sheen.putalpha(sm)
    plate = Image.alpha_composite(plate, sheen)
    edge = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([x0, y0, x1, y1], radius=radius, outline=(255, 255, 255, 60), width=px(3))
    plate = Image.alpha_composite(plate, edge)

    plate.putalpha(Image.composite(plate.getchannel("A"), Image.new("L", size, 0), mask))

    # Schlagschatten des Symbols
    drop = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(drop).rounded_rectangle([x0, y0 + px(14), x1, y1 + px(14)], radius=radius, fill=(0, 0, 0, 120))
    drop = drop.filter(ImageFilter.GaussianBlur(px(18)))
    canvas = Image.alpha_composite(canvas, drop)
    canvas = Image.alpha_composite(canvas, plate)

    final = canvas.resize((1024, 1024), Image.LANCZOS)
    final.save(os.path.join(OUT, "AppIcon-1024.png"))
    iconset = os.path.join(OUT, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            dim = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            final.resize((dim, dim), Image.LANCZOS).save(os.path.join(iconset, name))
    print("AppIcon erzeugt.")


if __name__ == "__main__":
    main()
