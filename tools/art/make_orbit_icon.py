#!/usr/bin/env python3
"""ORBIT-App-Symbol aus der Vorlage des Auftraggebers (Resources/OrbitIconSource.png).

Die Vorlage ist ein RGB-Bild ohne Transparenz: abgerundetes Quadrat auf fast weißem Grund mit leichtem Schatten.
Dieses Skript
  1. stellt die Form freigestellt (Maske aus der Farbsättigung, vierfach überabgetastet → weiche Kanten),
  2. setzt sie nach Apples macOS-Raster (1024er Fläche, Körper 824 × 824 ab Punkt 100, weicher Schlagschatten)
     → Resources/AppIcon-1024.png,
und ruft danach tools/art/make_iconset.py für Iconset und AppIcon.icns auf.
Die Grafik selbst (Chip, „i“, Verlauf) bleibt unverändert – nur Freistellung und Platzierung.
"""
import pathlib
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

root = pathlib.Path(__file__).resolve().parent.parent.parent
src_path = root / "Resources" / "OrbitIconSource.png"
src = Image.open(src_path).convert("RGB")
w, h = src.size

# 1. Maske: Sättigung > Schwelle. Überabgetastet, damit die Kante nach dem Verkleinern weich ist.
SS = 4
big = src.resize((w * SS, h * SS), Image.BICUBIC)
arr = np.asarray(big).astype(np.int16)
sat = arr.max(axis=2) - arr.min(axis=2)
# Der weiße Chip ist ungesättigt – er ist ein „Loch“ in der Maske und wird gefüllt (scipy.ndimage).
filled = ndimage.binary_fill_holes(sat > 46)
mask_big = Image.fromarray((filled * 255).astype(np.uint8))
# Einzelne Ausreißer am Rand entfernen (kleiner Medianfilter), dann zurück auf Originalgröße → Antialiasing.
mask_big = mask_big.filter(ImageFilter.MedianFilter(5))
mask = mask_big.resize((w, h), Image.LANCZOS)

bbox = mask.point(lambda v: 255 if v > 128 else 0).getbbox()
if bbox is None:
    sys.exit("Keine Form in der Vorlage gefunden")
x0, y0, x1, y1 = bbox
side = max(x1 - x0, y1 - y0)
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
box = (round(cx - side / 2), round(cy - side / 2), round(cx + side / 2), round(cy + side / 2))

body = src.crop(box).convert("RGBA")
body.putalpha(mask.crop(box))

# 2. macOS-Raster: 1024er Fläche, Körper 824 × 824 bei (100, 100), Schatten nach unten.
CANVAS, BODY, OFFSET = 1024, 824, 100
body = body.resize((BODY, BODY), Image.LANCZOS)
canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
shadow_alpha = body.getchannel("A").point(lambda v: int(v * 0.30))
shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
shadow_layer = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 255))
shadow_layer.putalpha(shadow_alpha)
shadow.paste(shadow_layer, (OFFSET, OFFSET + 10), shadow_layer)
shadow = shadow.filter(ImageFilter.GaussianBlur(14))
canvas = Image.alpha_composite(canvas, shadow)
canvas.alpha_composite(body, (OFFSET, OFFSET))
canvas.save(root / "Resources" / "AppIcon-1024.png", optimize=True)
print(f"AppIcon-1024.png aus {src_path.name} (Körper {box}, {side} px)")

subprocess.run([sys.executable, str(root / "tools" / "art" / "make_iconset.py")], check=True)
