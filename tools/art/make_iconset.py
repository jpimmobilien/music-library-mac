#!/usr/bin/env python3
"""Erzeugt Resources/AppIcon.iconset (alle Größen) und Resources/AppIcon.icns aus Resources/AppIcon-1024.png.
Auf dem Mac erzeugt scripts/build_app.sh das .icns zusätzlich mit iconutil; diese Datei ist der Rückfall."""
import pathlib
from PIL import Image

root = pathlib.Path(__file__).resolve().parent.parent.parent
src = Image.open(root / "Resources" / "AppIcon-1024.png").convert("RGBA")
iconset = root / "Resources" / "AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        src.resize((px, px), Image.LANCZOS).save(iconset / name, optimize=True)
src.save(root / "Resources" / "AppIcon.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
print("Iconset und AppIcon.icns erzeugt")
