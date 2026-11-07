// Erzeugt App-Icon (1024 px) und DMG-Hintergrund (1× und 2×) aus HTML/SVG mit Chromium (Playwright).
// Aufruf: node tools/art/make_art.js  → Resources/AppIcon-1024.png, Resources/DMG/background.png, background@2x.png
// Danach: python3 tools/art/make_iconset.py (Iconset + .icns)
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const root = path.resolve(__dirname, '..', '..');

// App-Icon: schwebende Glaslinse über einem leuchtenden Äther-Ring auf tiefem Nachtblau.
const icon = `<!doctype html><html><head><style>
html,body{margin:0;padding:0;background:transparent}
svg{display:block}
</style></head><body>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#1B2346"/>
      <stop offset="0.55" stop-color="#0C1126"/>
      <stop offset="1" stop-color="#060914"/>
    </linearGradient>
    <radialGradient id="glowA" cx="0.22" cy="0.18" r="0.7">
      <stop offset="0" stop-color="#4A55F0" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#4A55F0" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glowB" cx="0.86" cy="0.92" r="0.6">
      <stop offset="0" stop-color="#0FB5C8" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#0FB5C8" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7DF3FF"/>
      <stop offset="0.45" stop-color="#6E8BFF"/>
      <stop offset="0.8" stop-color="#B07CFF"/>
      <stop offset="1" stop-color="#5CE1E6"/>
    </linearGradient>
    <filter id="blur24" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="24"/></filter>
    <filter id="blur8" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
    <radialGradient id="lens" cx="0.38" cy="0.32" r="0.75">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.34"/>
      <stop offset="0.55" stop-color="#C9D6FF" stop-opacity="0.12"/>
      <stop offset="1" stop-color="#9FB4FF" stop-opacity="0.06"/>
    </radialGradient>
    <linearGradient id="lensEdge" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.15"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.55"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="squircle"><rect x="100" y="100" width="824" height="824" rx="185" ry="185"/></clipPath>
    <clipPath id="lensClip"><circle cx="560" cy="470" r="215"/></clipPath>
  </defs>
  <g filter="drop-shadow(0 18px 28px rgba(0,0,0,0.35))">
    <rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="url(#bg)"/>
  </g>
  <g clip-path="url(#squircle)">
    <rect x="100" y="100" width="824" height="824" fill="url(#glowA)"/>
    <rect x="100" y="100" width="824" height="824" fill="url(#glowB)"/>
    <!-- Äther-Ring: leuchtender Halo + scharfer Ring -->
    <ellipse cx="490" cy="560" rx="270" ry="270" fill="none" stroke="url(#ring)" stroke-width="58" opacity="0.55" filter="url(#blur24)"/>
    <ellipse cx="490" cy="560" rx="270" ry="270" fill="none" stroke="url(#ring)" stroke-width="30"/>
    <ellipse cx="490" cy="560" rx="270" ry="270" fill="none" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="4"/>
    <!-- Messpunkt auf dem Ring -->
    <circle cx="300" cy="752" r="22" fill="#E9FDFF"/>
    <circle cx="300" cy="752" r="44" fill="#7DF3FF" opacity="0.35" filter="url(#blur8)"/>
    <!-- Glaslinse: vergrößert/verschoben den Ring darunter -->
    <g clip-path="url(#lensClip)">
      <rect x="300" y="200" width="520" height="520" fill="#0A1030" opacity="0.35"/>
      <ellipse cx="470" cy="590" rx="320" ry="320" fill="none" stroke="url(#ring)" stroke-width="44" opacity="0.9" filter="url(#blur8)"/>
      <circle cx="560" cy="470" r="215" fill="url(#lens)"/>
      <ellipse cx="520" cy="330" rx="170" ry="70" fill="url(#sheen)" opacity="0.8"/>
    </g>
    <circle cx="560" cy="470" r="215" fill="none" stroke="url(#lensEdge)" stroke-width="5"/>
    <circle cx="560" cy="470" r="232" fill="none" stroke="#000000" stroke-opacity="0.18" stroke-width="12" filter="url(#blur8)"/>
    <!-- feine Innenkante des Icons -->
    <rect x="102" y="102" width="820" height="820" rx="183" ry="183" fill="none" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="3"/>
  </g>
</svg></body></html>`;

// DMG-Hintergrund (660 × 420 pt): Perle mit Eisblau/Flieder, Pfeil, zweisprachiger Hinweis.
function background(scale) {
  return `<!doctype html><html><head><style>
  html,body{margin:0;padding:0}
  body{width:660px;height:420px;overflow:hidden;font-family:-apple-system,"Inter","Helvetica Neue",Arial,sans-serif;
       background:linear-gradient(180deg,#F7F9FC 0%,#E9EEF5 100%);position:relative}
  .g{position:absolute;border-radius:50%;filter:blur(40px)}
  .a{width:360px;height:360px;left:-120px;top:-150px;background:#9CC8FF;opacity:.55}
  .b{width:320px;height:320px;right:-110px;bottom:-140px;background:#D5C6FF;opacity:.55}
  .c{width:260px;height:260px;left:300px;top:250px;background:#A8EBDD;opacity:.35}
  .title{position:absolute;left:0;right:0;top:38px;text-align:center;font-size:22px;font-weight:700;letter-spacing:6px;color:#0F1524}
  .sub{position:absolute;left:0;right:0;top:70px;text-align:center;font-size:11.5px;letter-spacing:1.5px;color:#566072}
  .hint{position:absolute;left:0;right:0;top:330px;text-align:center;font-size:13px;color:#3D4657}
  .hint2{position:absolute;left:0;right:0;top:350px;text-align:center;font-size:11px;color:#7A8393}
  .note{position:absolute;left:0;right:0;bottom:14px;text-align:center;font-size:10px;color:#8A93A3}
  svg{position:absolute;left:0;top:0}
  </style></head><body>
  <div class="g a"></div><div class="g b"></div><div class="g c"></div>
  <div class="title">AETHER</div>
  <div class="sub">SYSTEM INTELLIGENCE &amp; FILE EXPLORER · UNIVERSAL · INTEL &amp; APPLE SILICON</div>
  <svg width="660" height="420" viewBox="0 0 660 420">
    <defs><linearGradient id="ar" x1="0" x2="1"><stop offset="0" stop-color="#5A8BFF" stop-opacity=".35"/><stop offset="1" stop-color="#2563EB"/></linearGradient></defs>
    <path d="M262 205 C 300 190, 360 190, 398 205" fill="none" stroke="url(#ar)" stroke-width="4" stroke-linecap="round"/>
    <path d="M390 194 L 412 207 L 389 217 Z" fill="#2563EB"/>
  </svg>
  <div class="hint">AETHER in den Ordner „Programme“ ziehen</div>
  <div class="hint2">Drag AETHER to the Applications folder</div>
  <div class="note">macOS 13 Ventura oder neuer · Liquid Glass auf macOS 26</div>
  </body></html>`;
}

(async () => {
  const browser = await chromium.launch();
  const iconPage = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await iconPage.setContent(icon);
  await iconPage.screenshot({ path: path.join(root, 'Resources', 'AppIcon-1024.png'), omitBackground: true });

  fs.mkdirSync(path.join(root, 'Resources', 'DMG'), { recursive: true });
  for (const scale of [1, 2]) {
    const page = await browser.newPage({ viewport: { width: 660, height: 420 }, deviceScaleFactor: scale });
    await page.setContent(background(scale));
    await page.screenshot({ path: path.join(root, 'Resources', 'DMG', scale === 1 ? 'background.png' : 'background@2x.png') });
  }
  await browser.close();
  console.log('Icon und DMG-Hintergrund erzeugt');
})();
