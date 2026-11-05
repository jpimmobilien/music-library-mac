#!/usr/bin/env python3
"""Rendert das DMG-Hintergrundbild (1× und 2×) im Stil der App (helles Ambiente, Rosé-Akzent, Inter)."""
import os
from playwright.sync_api import sync_playwright

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FONTS = os.path.join(ROOT, "Resources", "Fonts")
HTML = f"""<html><head><style>
@font-face {{ font-family: InterDisplay; src: url('file://{FONTS}/InterDisplay-Bold.ttf'); font-weight: 700; }}
@font-face {{ font-family: Inter; src: url('file://{FONTS}/Inter-Medium.ttf'); font-weight: 500; }}
@font-face {{ font-family: Inter; src: url('file://{FONTS}/Inter-Regular.ttf'); font-weight: 400; }}
body {{ margin:0; width:660px; height:420px; overflow:hidden; font-family: Inter; }}
.bg {{ position:absolute; inset:0; background:#FBF8F7; }}
.g1 {{ position:absolute; inset:0; background: radial-gradient(circle at 0% 2%, rgba(244,184,197,.50), rgba(244,184,197,0) 58%); }}
.g2 {{ position:absolute; inset:0; background: radial-gradient(circle at 105% 36%, rgba(249,212,194,.45), rgba(249,212,194,0) 58%); }}
.g3 {{ position:absolute; inset:0; background: radial-gradient(circle at 18% 98%, rgba(226,211,238,.35), rgba(226,211,238,0) 58%); }}
h1 {{ position:absolute; top:34px; width:100%; text-align:center; margin:0; font-family: InterDisplay; font-weight:700; font-size:30px; letter-spacing:-0.6px; color:#1D1B1C; }}
p.sub {{ position:absolute; top:78px; width:100%; text-align:center; margin:0; font-size:14px; font-weight:500; color:#B93A5A; }}
p.note {{ position:absolute; bottom:18px; line-height:17px; width:100%; text-align:center; margin:0; font-size:11px; color:#6B6466; }}
svg {{ position:absolute; left:0; top:0; }}
</style></head><body>
<div class="bg"></div><div class="g1"></div><div class="g2"></div><div class="g3"></div>
<h1>Music Library</h1>
<p class="sub">Zum Installieren in den Ordner „Programme“ ziehen</p>
<svg width="660" height="420" viewBox="0 0 660 420">
  <defs><marker id="ah" markerUnits="userSpaceOnUse" markerWidth="14" markerHeight="14" refX="8" refY="7" orient="auto">
    <path d="M2,2 L9,7 L2,12" fill="none" stroke="#D4566F" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></marker></defs>
  <path d="M258,200 C300,168 360,168 402,200" fill="none" stroke="#D4566F" stroke-width="3" stroke-linecap="round" stroke-dasharray="2 9" marker-end="url(#ah)"/>
</svg>
<p class="note">Beim ersten Start fragt macOS einmal nach: Systemeinstellungen → Datenschutz &amp; Sicherheit → „Dennoch öffnen“.<br>Bis macOS 14: im Programme-Ordner Rechtsklick auf die App → „Öffnen“.</p>
</body></html>"""

import tempfile
tmp = tempfile.NamedTemporaryFile("w", suffix=".html", delete=False)
tmp.write(HTML)
tmp.close()

with sync_playwright() as p:
    b = p.chromium.launch()
    for scale, name in [(1, "background.png"), (2, "background@2x.png")]:
        page = b.new_page(viewport={"width": 660, "height": 420}, device_scale_factor=scale)
        page.goto("file://" + tmp.name)
        page.evaluate("document.fonts.ready")
        page.wait_for_timeout(300)
        page.screenshot(path=os.path.join(ROOT, "Resources", "DMG", name))
        page.close()
    b.close()
os.unlink(tmp.name)
print("DMG-Hintergrund erzeugt")
