#!/usr/bin/env python3
"""Erzeugt das App-Symbol von Android Bridge (Resources/AppIcon.iconset + AppIcon-1024.png).

Motiv: ein Telefon und ein Mac-Laptop, verbunden durch einen leuchtenden Brückenbogen,
auf einer glasigen Fläche im Verlauf Bridge-Grün → Türkis → Blau (macOS-Symbolraster, 1024 px).
Aufruf:  python3 scripts/make_icon.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "Resources")
S = 4  # Überabtastung für glatte Kanten
N = 1024 * S


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def diagonal_gradient(size, stops):
    w, h = size
    grad = Image.new("RGB", (256, 1))
    px = grad.load()
    for x in range(256):
        t = x / 255
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                px[x, 0] = lerp(c0, c1, (t - t0) / (t1 - t0))
                break
    grad = grad.resize((w * 2, h * 2), Image.BILINEAR).rotate(-38, resample=Image.BICUBIC, expand=False)
    left = (grad.width - w) // 2
    top = (grad.height - h) // 2
    return grad.crop((left, top, left + w, top + h))


def main():
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    # macOS-Raster: Körper 824 px mit 100 px Rand, Radius ≈ 185 px
    margin = 100 * S
    body = (margin, margin, N - margin, N - margin)
    radius = 186 * S

    # Schatten
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sm = rounded_mask((N, N), (body[0], body[1] + 18 * S, body[2], body[3] + 18 * S), radius)
    shadow.putalpha(sm.point(lambda v: int(v * 0.34)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28 * S))
    canvas = Image.alpha_composite(canvas, shadow)

    # Fläche mit Verlauf
    mask = rounded_mask((N, N), body, radius)
    fill = diagonal_gradient((N, N), [(0.0, (52, 205, 140)), (0.45, (28, 168, 186)), (1.0, (44, 104, 236))]).convert("RGBA")
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    layer.paste(fill, (0, 0), mask)

    # Glanz oben (Liquid-Glass-Anmutung)
    sheen = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(sheen)
    d.ellipse((body[0] - 220 * S, body[1] - 560 * S, body[2] + 220 * S, body[1] + 330 * S), fill=48)
    sheen = sheen.filter(ImageFilter.GaussianBlur(40 * S))
    sheen = ImageChops.multiply(sheen, mask)
    white = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    white.putalpha(sheen)
    layer = Image.alpha_composite(layer, white)

    # Lichtkante
    edge = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(body, radius=radius, outline=(255, 255, 255, 90), width=5 * S)
    layer = Image.alpha_composite(layer, edge)
    canvas = Image.alpha_composite(canvas, layer)

    art = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    a = ImageDraw.Draw(art)
    white_c = (255, 255, 255, 255)

    # Telefon (links)
    px0, py0 = 268 * S, 452 * S
    pw, ph = 158 * S, 300 * S
    a.rounded_rectangle((px0, py0, px0 + pw, py0 + ph), radius=34 * S, fill=white_c)
    a.rounded_rectangle((px0 + 14 * S, py0 + 26 * S, px0 + pw - 14 * S, py0 + ph - 26 * S), radius=20 * S, fill=(40, 150, 190, 255))
    a.ellipse((px0 + pw / 2 - 7 * S, py0 + 9 * S, px0 + pw / 2 + 7 * S, py0 + 23 * S), fill=(40, 150, 190, 255))

    # Laptop (rechts)
    lx0, ly0 = 560 * S, 540 * S
    lw, lh = 230 * S, 150 * S
    a.rounded_rectangle((lx0, ly0, lx0 + lw, ly0 + lh), radius=18 * S, fill=white_c)
    a.rounded_rectangle((lx0 + 13 * S, ly0 + 13 * S, lx0 + lw - 13 * S, ly0 + lh - 9 * S), radius=8 * S, fill=(36, 120, 214, 255))
    a.rounded_rectangle((lx0 - 34 * S, ly0 + lh + 4 * S, lx0 + lw + 34 * S, ly0 + lh + 30 * S), radius=13 * S, fill=white_c)

    # Brückenbogen vom Telefon zum Laptop
    start = (px0 + pw / 2, py0 - 18 * S)
    end = (lx0 + lw / 2, ly0 - 18 * S)
    ctrl = ((start[0] + end[0]) / 2, 170 * S)
    pts = []
    for i in range(241):
        t = i / 240
        x = (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * ctrl[0] + t ** 2 * end[0]
        y = (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * ctrl[1] + t ** 2 * end[1]
        pts.append((x, y))
    def stroke(draw, radius, fill):
        # dichte Kreise entlang der Kurve: glatter Strich ohne Gehrungsartefakte
        dense = []
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            steps = max(1, int(math.hypot(x1 - x0, y1 - y0) / (2 * S)))
            for k in range(steps):
                t = k / steps
                dense.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
        dense.append(pts[-1])
        for (x, y) in dense:
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)

    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    stroke(ImageDraw.Draw(glow), 30 * S, (255, 255, 255, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(28 * S))
    art = Image.alpha_composite(glow, art)
    a = ImageDraw.Draw(art)
    stroke(a, 15 * S, white_c)
    for p in (pts[0], pts[-1]):
        r = 15 * S
        a.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=white_c)
    # Datenpunkte auf dem Bogen
    for t in (0.3, 0.5, 0.7):
        i = int(t * 240)
        x, y = pts[i]
        r = 21 * S
        a.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, 255))
        r2 = 11 * S
        a.ellipse((x - r2, y - r2, x + r2, y + r2), fill=(34, 176, 160, 255))

    # leichter Schatten der Motive
    sh = art.split()[3].filter(ImageFilter.GaussianBlur(10 * S))
    shadow_art = Image.new("RGBA", (N, N), (10, 40, 70, 0))
    shadow_art.putalpha(sh.point(lambda v: int(v * 0.28)))
    shadow_art = ImageChops.offset(shadow_art, 0, 10 * S)
    canvas = Image.alpha_composite(canvas, shadow_art)
    canvas = Image.alpha_composite(canvas, art)

    icon = canvas.resize((1024, 1024), Image.LANCZOS)
    icon.save(os.path.join(OUT, "AppIcon-1024.png"))

    iconset = os.path.join(OUT, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
    # Rückfall-ICNS (auf macOS erzeugt build_app.sh die Datei mit iconutil neu)
    icon.save(os.path.join(OUT, "AppIcon.icns"), sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("App-Symbol erzeugt")


def dmg_background():
    for scale, name in ((1, "background.png"), (2, "background@2x.png")):
        w, h = 660 * scale, 420 * scale
        img = diagonal_gradient((w, h), [(0.0, (246, 250, 249)), (1.0, (231, 240, 247))]).convert("RGBA")
        blobs = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(blobs)
        d.ellipse((-120 * scale, -160 * scale, 300 * scale, 220 * scale), fill=(52, 205, 140, 60))
        d.ellipse((420 * scale, 200 * scale, 820 * scale, 560 * scale), fill=(44, 104, 236, 45))
        blobs = blobs.filter(ImageFilter.GaussianBlur(70 * scale))
        img = Image.alpha_composite(img, blobs)
        d = ImageDraw.Draw(img)
        # Pfeil zwischen App (170, 205) und Programme (490, 205)
        y = 205 * scale
        x0, x1 = 262 * scale, 398 * scale
        d.line([(x0, y), (x1, y)], fill=(60, 140, 150, 200), width=5 * scale)
        d.polygon([(x1 + 18 * scale, y), (x1 - 6 * scale, y - 15 * scale), (x1 - 6 * scale, y + 15 * scale)], fill=(60, 140, 150, 200))
        try:
            from PIL import ImageFont
            font = None
            for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
                         "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
                if os.path.exists(path):
                    font = ImageFont.truetype(path, 17 * scale)
                    break
            text = "Android Bridge in den Ordner „Programme“ ziehen"
            if font:
                tw = d.textlength(text, font=font)
                d.text(((w - tw) / 2, 330 * scale), text, fill=(70, 86, 98, 255), font=font)
        except Exception as exc:  # noqa: BLE001
            print("Schrift nicht verfügbar:", exc)
        img.convert("RGB").save(os.path.join(OUT, "DMG", name))
    print("DMG-Hintergrund erzeugt")


if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "DMG"), exist_ok=True)
    main()
    dmg_background()
