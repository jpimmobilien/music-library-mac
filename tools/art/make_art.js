// Erzeugt den DMG-Hintergrund (1× und 2×) aus HTML/SVG mit Chromium (Playwright).
// Aufruf: node tools/art/make_art.js  → Resources/DMG/background.png, background@2x.png
// Das App-Symbol kommt seit ORBIT 2.0 aus der Vorlage des Auftraggebers: python3 tools/art/make_orbit_icon.py
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const root = path.resolve(__dirname, '..', '..');

// DMG-Hintergrund (660 × 420 pt): Pearl White mit Arctic Blue, Electric Cyan und Soft Violet (ORBIT-Palette),
// zwei feine Umlaufbahnen, Pfeil, zweisprachiger Hinweis.
function background(scale) {
  return `<!doctype html><html><head><style>
  html,body{margin:0;padding:0}
  body{width:660px;height:420px;overflow:hidden;font-family:-apple-system,"Inter","Helvetica Neue",Arial,sans-serif;
       background:linear-gradient(180deg,#F7F9FC 0%,#E9EEF5 100%);position:relative}
  .g{position:absolute;border-radius:50%;filter:blur(40px)}
  .a{width:360px;height:360px;left:-120px;top:-150px;background:#8EC5FF;opacity:.55}
  .b{width:320px;height:320px;right:-110px;bottom:-140px;background:#C9B8FF;opacity:.5}
  .c{width:260px;height:260px;left:300px;top:250px;background:#8FEFFF;opacity:.35}
  .title{position:absolute;left:0;right:0;top:38px;text-align:center;font-size:22px;font-weight:700;letter-spacing:6px;color:#0F1524}
  .sub{position:absolute;left:0;right:0;top:70px;text-align:center;font-size:11.5px;letter-spacing:1.5px;color:#566072}
  .hint{position:absolute;left:0;right:0;top:330px;text-align:center;font-size:13px;color:#3D4657}
  .hint2{position:absolute;left:0;right:0;top:350px;text-align:center;font-size:11px;color:#7A8393}
  .note{position:absolute;left:0;right:0;bottom:14px;text-align:center;font-size:10px;color:#8A93A3}
  svg{position:absolute;left:0;top:0}
  </style></head><body>
  <div class="g a"></div><div class="g b"></div><div class="g c"></div>
  <div class="title">ORBIT</div>
  <div class="sub">SYSTEM INTELLIGENCE &amp; FILE EXPLORER · UNIVERSAL · INTEL &amp; APPLE SILICON</div>
  <svg width="660" height="420" viewBox="0 0 660 420">
    <defs><linearGradient id="ar" x1="0" x2="1"><stop offset="0" stop-color="#3D8BFF" stop-opacity=".35"/><stop offset="1" stop-color="#0A7CFF"/></linearGradient></defs>
    <ellipse cx="330" cy="205" rx="300" ry="112" fill="none" stroke="#0A7CFF" stroke-opacity=".10" stroke-width="1.2"/>
    <ellipse cx="330" cy="205" rx="250" ry="84" fill="none" stroke="#18D6F0" stroke-opacity=".14" stroke-width="1"/>
    <path d="M262 205 C 300 190, 360 190, 398 205" fill="none" stroke="url(#ar)" stroke-width="4" stroke-linecap="round"/>
    <path d="M390 194 L 412 207 L 389 217 Z" fill="#0A7CFF"/>
  </svg>
  <div class="hint">ORBIT in den Ordner „Programme“ ziehen</div>
  <div class="hint2">Drag ORBIT to the Applications folder</div>
  <div class="note">macOS 13 Ventura oder neuer · Liquid Glass auf macOS 26</div>
  </body></html>`;
}

(async () => {
  const browser = await chromium.launch();
  fs.mkdirSync(path.join(root, 'Resources', 'DMG'), { recursive: true });
  for (const scale of [1, 2]) {
    const page = await browser.newPage({ viewport: { width: 660, height: 420 }, deviceScaleFactor: scale });
    await page.setContent(background(scale));
    await page.screenshot({ path: path.join(root, 'Resources', 'DMG', scale === 1 ? 'background.png' : 'background@2x.png') });
  }
  await browser.close();
  console.log('DMG-Hintergrund erzeugt');
})();
