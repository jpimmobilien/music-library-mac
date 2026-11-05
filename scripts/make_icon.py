#!/usr/bin/env python3
"""Erzeugt das App-Icon (Resources/AppIcon.icns + Resources/AppIcon-1024.png) aus dem Android-App-Icon.

Motiv wie unter Android (ic_launcher_foreground.xml: schwarze LP mit Lichtreflex, Rosé-Label, Tonarm auf
warmem Graphit), eingesetzt in die macOS-Icon-Form (Squircle 824/1024 mit Schatten). Gerendert wird das
SVG mit Chromium (Playwright); die .icns-Datei wird ohne Apple-Werkzeuge geschrieben (PNG-Einträge).

Aufruf: python3 scripts/make_icon.py <android-res-drawable-ordner>
"""
import io
import os
import struct
import sys
import xml.etree.ElementTree as ET

from PIL import Image

A = "{http://schemas.android.com/apk/res/android}"
ROOT = os.path.join(os.path.dirname(__file__), "..")


def android_to_svg_paths(xml_path):
    root = ET.parse(xml_path).getroot()
    out = []
    for p in root.iter("path"):
        d = p.get(A + "pathData")
        fill = p.get(A + "fillColor", "#00000000")
        stroke = p.get(A + "strokeColor")
        sw = p.get(A + "strokeWidth", "0")
        cap = p.get(A + "strokeLineCap", "butt")
        join = p.get(A + "strokeLineJoin", "miter")

        def css(c):
            if not c:
                return "none", 0
            c = c.lstrip("#")
            if len(c) == 8:
                a = int(c[0:2], 16) / 255
                return "#" + c[2:], a
            return "#" + c, 1

        f, fa = css(fill)
        s, sa = css(stroke)
        attrs = f'd="{d}" fill="{f if fa > 0 else "none"}" fill-opacity="{fa:.3f}"'
        if stroke and float(sw) > 0:
            attrs += f' stroke="{s}" stroke-opacity="{sa:.3f}" stroke-width="{sw}" stroke-linecap="{cap}" stroke-linejoin="{join}"'
        out.append(f"<path {attrs}/>")
    return "\n".join(out)


def build_svg(drawable_dir):
    paths = android_to_svg_paths(os.path.join(drawable_dir, "ic_launcher_foreground.xml"))
    # Sichtbarer Bereich des adaptiven Android-Icons: Mitte 54 ± 37 Einheiten → Squircle 824 px
    scale = 824 / 74.0
    tx = 512 - 54 * scale
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2B2427"/>
      <stop offset="0.55" stop-color="#181415"/>
      <stop offset="1" stop-color="#0E0B0C"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.28" cy="0.16" r="0.75">
      <stop offset="0" stop-color="#F27A93" stop-opacity="0.30"/>
      <stop offset="1" stop-color="#F27A93" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glow2" cx="0.9" cy="0.95" r="0.6">
      <stop offset="0" stop-color="#8C2F48" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#8C2F48" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.10"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
    <filter id="recordShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#000000" flood-opacity="0.55"/>
    </filter>
    <clipPath id="sq"><rect x="100" y="100" width="824" height="824" rx="185" ry="185"/></clipPath>
  </defs>
  <g filter="url(#shadow)">
    <rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="url(#bg)"/>
  </g>
  <g clip-path="url(#sq)">
    <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>
    <rect x="100" y="100" width="824" height="824" fill="url(#glow2)"/>
    <g transform="translate({tx:.2f},{tx:.2f}) scale({scale:.4f})" filter="url(#recordShadow)">
{paths}
    </g>
  </g>
  <rect x="101" y="101" width="822" height="822" rx="184" ry="184" fill="none" stroke="url(#edge)" stroke-width="2.5"/>
</svg>"""


def render_png(svg, size=1024):
    from playwright.sync_api import sync_playwright
    html = f"<html><body style='margin:0;background:transparent'>{svg}</body></html>"
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={"width": size, "height": size}, device_scale_factor=1)
        page.set_content(html)
        png = page.locator("svg").screenshot(omit_background=True)
        b.close()
    return Image.open(io.BytesIO(png)).convert("RGBA")


def write_icns(img, path):
    entries = [("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
    chunks = b""
    for kind, size in entries:
        buf = io.BytesIO()
        img.resize((size, size), Image.LANCZOS).save(buf, format="PNG")
        data = buf.getvalue()
        chunks += kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    drawable = sys.argv[1]
    svg = build_svg(drawable)
    res = os.path.join(ROOT, "Resources")
    with open(os.path.join(res, "AppIcon.svg"), "w") as f:
        f.write(svg)
    img = render_png(svg)
    img.save(os.path.join(res, "AppIcon-1024.png"))
    write_icns(img, os.path.join(res, "AppIcon.icns"))
    print("AppIcon.icns geschrieben")


if __name__ == "__main__":
    main()
