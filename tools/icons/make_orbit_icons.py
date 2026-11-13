#!/usr/bin/env python3
"""ORBIT-Startsymbol für Android aus der Vorlage des Auftraggebers (tools/icons/orbit-icon-source.png).

Adaptive Symbole (Android 8+, hier minSdk 31) bestehen aus drei Ebenen à 108 × 108 dp, von denen das System die
inneren 72 dp in der Form des Herstellers (Kreis, Squircle …) zeigt:
  - Hintergrund: der Farbverlauf der Vorlage. Er wird aus den Pixeln der Vorlage geschätzt (Ausgleichsfläche
    2. Ordnung je Farbkanal über alle Verlaufspixel) und randlos über die ganze Ebene fortgesetzt.
  - Vordergrund: Chip mit „i“ – exakt aus der Vorlage freigestellt (weiche Kanten aus dem Rotkanal gegen den
    geschätzten Verlauf, das „i“ bleibt unverändert).
  - Monochrom (Android 13 „Designsymbole“): Chip als Silhouette, „i“ ausgespart.
Abbildung: Der Körper der Vorlage (abgerundetes Quadrat) entspricht den sichtbaren 72 dp – Chip und „i“ behalten
damit ihre Proportionen und liegen vollständig in der 66-dp-Schutzzone.
Ausgabe: app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_{background,foreground,monochrome}.png
sowie docs/design/orbit-symbol-vorschau.png.
"""
import pathlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

root = pathlib.Path(__file__).resolve().parent.parent.parent
src = Image.open(root / "tools" / "icons" / "orbit-icon-source.png").convert("RGB")
a = np.asarray(src).astype(np.float64)
h, w, _ = a.shape
sat = a.max(axis=2) - a.min(axis=2)

# Körper (abgerundetes Quadrat) und Chip-Bereich
body = ndimage.binary_fill_holes(sat > 46)
ys, xs = np.nonzero(body)
bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
side = max(bx1 - bx0, by1 - by0) + 1
cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2

# Verlaufspixel: im Körper (mit Abstand zum Rand), gesättigt, nicht in der Nähe des weißen Chips
white = (a.min(axis=2) > 200) & (sat < 60)
near_white = ndimage.binary_dilation(white, iterations=14)
inner = ndimage.binary_erosion(body, iterations=18)
grad = inner & ~near_white & (sat > 120)
gy, gx = np.nonzero(grad)
u = (gx - cx) / side
v = (gy - cy) / side
design = np.stack([np.ones_like(u), u, v, u * u, u * v, v * v], axis=1)
coef = [np.linalg.lstsq(design, a[gy, gx, c], rcond=None)[0] for c in range(3)]
resid = np.concatenate([np.abs(design @ coef[c] - a[gy, gx, c]) for c in range(3)])
print(f"Verlauf geschätzt aus {len(gx)} Pixeln, mittlere Abweichung {resid.mean():.1f}/255")


def gradient(uu, vv):
    d = np.stack([np.ones_like(uu), uu, vv, uu * uu, uu * vv, vv * vv], axis=-1)
    return np.stack([np.clip(d @ coef[c], 0, 255) for c in range(3)], axis=-1)


# Vordergrund: Deckkraft aus dem Rotkanal (Weiß ≈ 248, Verlauf ≈ 0–60) gegen den geschätzten Verlauf
yy, xx = np.mgrid[0:h, 0:w]
bg_src = gradient((xx - cx) / side, (yy - cy) / side)
white_ref = 248.0
alpha_w = np.clip((a[..., 0] - bg_src[..., 0]) / np.maximum(white_ref - bg_src[..., 0], 1), 0, 1)
alpha_w[~ndimage.binary_erosion(body, iterations=10)] = 0  # Kante des Körpers gegen den weißen Grund ausnehmen
# Restrauschen der Verlaufsschätzung (wenige Prozent) nicht als Deckkraft werten
alpha_w = np.clip((alpha_w - 0.08) / 0.92, 0, 1)
chip_core = ndimage.binary_fill_holes(alpha_w > 0.5)  # Chip inkl. „i“
chip_core = ndimage.binary_erosion(chip_core, iterations=2)
alpha_fg = np.where(chip_core, 1.0, alpha_w)
# Farbe ohne Vormultiplikation: C = α·F + (1−α)·B  →  F = (C − (1−α)·B) / α
safe = np.maximum(alpha_fg, 1e-3)[..., None]
fg_rgb = np.clip((a - (1 - alpha_fg[..., None]) * bg_src) / safe, 0, 255)
fg_rgb = np.where(chip_core[..., None], a, fg_rgb)
# Silhouette für Designsymbole: nur Weiß, „i“ ausgespart
alpha_mono = alpha_w

# Ebenen auf 108-dp-Fläche: Körper (side px) ≙ 72 dp  →  108 dp ≙ 1.5 · side
L = int(round(side * 1.5))
ox, oy = int(round(L / 2 - cx)), int(round(L / 2 - cy))


def layer(rgb, alpha):
    img = Image.new("RGBA", (L, L), (0, 0, 0, 0))
    rgba = np.dstack([rgb, alpha[..., None] * 255]).astype(np.uint8)
    img.alpha_composite(Image.fromarray(rgba, "RGBA"), (ox, oy))
    return img


fg = layer(fg_rgb, alpha_fg)
mono = layer(np.full_like(a, 255), alpha_mono)
uu, vv = np.meshgrid((np.arange(L) - L / 2) / side, (np.arange(L) - L / 2) / side)
bg = Image.fromarray(gradient(uu, vv).astype(np.uint8), "RGB").convert("RGBA")

res = root / "app" / "src" / "main" / "res"
for name, scale in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
    px = int(108 * scale)
    d = res / f"mipmap-{name}"
    d.mkdir(parents=True, exist_ok=True)
    bg.resize((px, px), Image.LANCZOS).save(d / "ic_launcher_background.png", optimize=True)
    fg.resize((px, px), Image.LANCZOS).save(d / "ic_launcher_foreground.png", optimize=True)
    mono.resize((px, px), Image.LANCZOS).save(d / "ic_launcher_monochrome.png", optimize=True)

# Vorschau: Kreis, Squircle, abgerundetes Quadrat, Designsymbol (hell/dunkel)
P = 216
comp = Image.alpha_composite(bg, fg).resize((P * 3 // 2, P * 3 // 2), Image.LANCZOS)
crop = comp.crop((P // 4, P // 4, P // 4 + P, P // 4 + P))


def masked(shape):
    m = Image.new("L", (P * 4, P * 4), 0)
    dr = ImageDraw.Draw(m)
    if shape == "circle":
        dr.ellipse((0, 0, P * 4 - 1, P * 4 - 1), fill=255)
    elif shape == "rounded":
        dr.rounded_rectangle((0, 0, P * 4 - 1, P * 4 - 1), radius=P * 4 // 5, fill=255)
    else:
        n = 4.6
        t = np.linspace(0, 2 * np.pi, 720)
        r = P * 2
        pts = [(r + r * np.sign(np.cos(x)) * abs(np.cos(x)) ** (2 / n), r + r * np.sign(np.sin(x)) * abs(np.sin(x)) ** (2 / n)) for x in t]
        dr.polygon(pts, fill=255)
    m = m.resize((P, P), Image.LANCZOS)
    out = Image.new("RGBA", (P, P), (0, 0, 0, 0))
    out.paste(crop, (0, 0), m)
    return out


sheet = Image.new("RGBA", (P * 5 + 6 * 24, P + 48), (236, 240, 246, 255))
for i, s in enumerate(("circle", "squircle", "rounded")):
    sheet.alpha_composite(masked(s), (24 + i * (P + 24), 24))
for j, (tile, ink) in enumerate((((214, 228, 250, 255), (30, 60, 120)), ((30, 36, 48, 255), (170, 200, 245)))):
    t = Image.new("RGBA", (P, P), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.ellipse((0, 0, P - 1, P - 1), fill=tile)
    g = mono.resize((P * 3 // 2, P * 3 // 2), Image.LANCZOS).crop((P // 4, P // 4, P // 4 + P, P // 4 + P))
    ink_img = Image.new("RGBA", (P, P), ink + (255,))
    t.paste(ink_img, (0, 0), g.getchannel("A"))
    sheet.alpha_composite(t, (24 + (3 + j) * (P + 24), 24))
(root / "docs" / "design").mkdir(parents=True, exist_ok=True)
sheet.convert("RGB").save(root / "docs" / "design" / "orbit-symbol-vorschau.png", optimize=True)
print("Startsymbole (5 Dichten × 3 Ebenen) und docs/design/orbit-symbol-vorschau.png erzeugt")
