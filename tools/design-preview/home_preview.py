#!/usr/bin/env python3
"""
Design-Vorschau der Übersicht ohne Gerät – NACHGEBAUT in HTML/CSS, kein Bildschirmfoto der App.

Farben, Deckkräfte, Radien, Abstände und Schriftgrößen werden direkt aus dem Quelltext gelesen
(PaletteSpec.kt, Tokens.kt-Werte unten gespiegelt). Zweck: Farbwirkung, Materialtiefe und Lesbarkeit der
Themes vergleichen, bevor ein Gerät verfügbar ist. Layout und Unschärfe sind angenähert (CSS backdrop-filter).

Aufruf (im Projektordner):  python3 tools/design-preview/home_preview.py out.html [Akzent]
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = (ROOT / "ui/designsystem/src/main/java/de/privateapp/aether/design/PaletteSpec.kt").read_text()
FONTS = ROOT / "ui/designsystem/src/main/res/font"

def parse_bases():
    bases = {}
    for m in re.finditer(r"val (\w+) = BaseSpec\((.*?)\n    \)", SPEC, re.S):
        name, body = m.group(1), m.group(2)
        vals = {}
        for k, v in re.findall(r"(\w+) = (0x[0-9A-Fa-f]+|true|false|[0-9.]+f)", body):
            vals[k] = v
        bases[name] = vals
    return bases

def accents():
    out = {}
    for name, l, d in re.findall(r"AccentChoice\.(\w+) to AccentSpec\((0x[0-9A-F]+), (0x[0-9A-F]+)\)", SPEC):
        out[name] = (l, d)
    return out

def rgba(v, mult=1.0):
    x = int(v, 16)
    a = ((x >> 24) & 255) / 255 * mult
    return f"rgba({(x>>16)&255},{(x>>8)&255},{x&255},{a:.3f})"

def hexrgb(v):
    x = int(v, 16); return (x >> 16) & 255, (x >> 8) & 255, x & 255

def page(name, b, acc_hex, intensity=0.7, sheen=0.8):
    dark = b["isDark"] == "true"
    glass = b["glass"] == "true"
    ar, ag, ab = hexrgb(acc_hex)
    acc = f"rgb({ar},{ag},{ab})"
    accA = float(b["atmosphereAccentAlpha"].rstrip("f")) * intensity
    mix = 0.28 if dark else 0.08
    glow = f"rgb({round(ar+(255-ar)*mix)},{round(ag+(255-ag)*mix)},{round(ab+(255-ab)*mix)})"
    t1, t2, t3 = rgba(b["text"]), rgba(b["textSecondary"]), rgba(b["textTertiary"])
    soft = f"rgba({ar},{ag},{ab},{0.20 if dark else 0.13})"
    pt, pb = rgba(b["panelTop"]), rgba(b["panelBottom"])
    et, eb = rgba(b["panelEdgeTop"]), rgba(b["panelEdgeBottom"])
    sh = rgba(b["sheen"], sheen if glass else 0)
    shadow = rgba(b["shadow"]) if not dark else "transparent"
    fill = rgba(b["fill"])
    tint = rgba(b["glassTint"]) if glass else rgba(b["glassTintSolid"])
    gl, gd = rgba(b["glassEdgeLight"]), rgba(b["glassEdgeDark"])
    success, warning = rgba(b["success"]), rgba(b["warning"])
    succSoft = rgba(b["success"], 0.16 if dark else 0.10)
    atmo = ""
    if accA > 0:
        atmo += f"radial-gradient(circle at -5% 4%, rgba({ar},{ag},{ab},{accA:.3f}), transparent 62%),"
    cool, warm = b["atmosphereCool"], b["atmosphereWarm"]
    if int(cool, 16) >> 24: atmo += f"radial-gradient(circle at 108% 30%, {rgba(cool, intensity)}, transparent 56%),"
    if int(warm, 16) >> 24: atmo += f"radial-gradient(circle at 25% 102%, {rgba(warm, intensity)}, transparent 62%),"
    bg = f"{atmo} linear-gradient(180deg, {rgba(b['backgroundTop'])} 0%, {rgba(b['background'])} 55%, {rgba(b['backgroundBottom'])} 100%)"
    used = 0.63
    deg = used * 360
    panel = f"background: linear-gradient(180deg,{sh} 0%, transparent 40%), linear-gradient(180deg,{pt},{pb}); box-shadow: 0 6px 20px {shadow}, inset 0 1px 0 {et}, inset 0 -1px 0 {eb};"
    if not glass:
        panel = f"background: {rgba(b['surface'])}; box-shadow: 0 4px 14px {shadow}, inset 0 0 0 1px {rgba(b['hairline'])};"
    return f"""
<div class="phone" style="background:{bg}; color:{t1}">
  <div class="status" style="color:{t1}">18:06 <span style="float:right">●●● 82 %</span></div>
  <div class="content">
    <div class="eyebrow" style="color:{acc}">AETHER</div>
    <div class="large">Pixel 6 Pro</div>
    <div class="callout" style="color:{t2}">Speicher zu 63 % belegt · Akku 82 % · thermisch normal</div>
    <div class="panel" style="{panel}">
      <div class="hdr"><div class="badge" style="background:{soft};color:{acc}">◍</div><div><div class="headline">Interner Speicher</div><div class="foot" style="color:{t2}">Android-Speicherstatistik</div></div><div class="chev" style="color:{t3}">›</div></div>
      <div class="row">
        <div class="ring" style="background: conic-gradient({acc} 0deg, {glow} {deg}deg, {fill} {deg}deg 360deg);">
          <div class="hole" style="background:linear-gradient(180deg,{pt},{pb}), {rgba(b['background'])}"><div class="num">63 %</div><div class="cap" style="color:{t2}">belegt</div></div>
        </div>
        <div class="legend">
          <div class="lg"><i style="background:{acc}"></i><span style="color:{t2}">Belegt</span><b>80,6 GB</b></div>
          <div class="lg"><i style="background:{rgba(b['fillStrong'])}"></i><span style="color:{t2}">Frei</span><b>47,4 GB</b></div>
          <div class="hl" style="background:{rgba(b['hairline'])}"></div>
          <div class="lg"><i></i><span style="color:{t2}">Gesamt</span><b>128 GB</b></div>
        </div>
      </div>
    </div>
    <div class="panel" style="{panel}">
      <div class="hdr"><div class="badge" style="background:{soft};color:{acc}">∿</div><div><div class="headline">Gerätestatus</div><div class="foot" style="color:{t2}">Akku und Wärme</div></div><div class="chev" style="color:{t3}">›</div></div>
      <div class="srow"><div class="batt" style="border-color:{t2}"><div style="width:82%;background:{acc}"></div></div><div class="sl"><div class="body">Akku</div><div class="foot" style="color:{t2}">Entlädt</div></div><b>82 %</b></div>
      <div class="hl" style="background:{rgba(b['hairline'])}"></div>
      <div class="srow"><div class="badge s" style="background:{fill};color:{t2}">🌡</div><div class="sl"><div class="body">Akku-Temperatur</div><div class="foot" style="color:{t2}">Sensor im Akku</div></div><b>31,4 °C</b></div>
      <div class="hl" style="background:{rgba(b['hairline'])}"></div>
      <div class="srow"><div class="badge s" style="background:{succSoft};color:{success}">◉</div><div class="sl"><div class="body">Thermalstatus</div><div class="foot" style="color:{t2}">Keine Einschränkung wegen Wärme.</div></div><span class="pill" style="background:{succSoft};color:{success}">✓ Normal</span></div>
    </div>
  </div>
  <div class="bar">
    <div class="tabs" style="background:{tint}; box-shadow: 0 10px 30px {shadow}, inset 0 0 0 0.8px {gl};">
      <div class="lens" style="background:{soft}"></div>
      <div class="t sel"><span style="color:{acc}">⌂</span><em style="color:{t1}">Übersicht</em></div>
      <div class="t"><span style="color:{t2}">▭</span><em style="color:{t2}">Dateien</em></div>
      <div class="t"><span style="color:{t2}">◔</span><em style="color:{t2}">Speicher</em></div>
      <div class="t"><span style="color:{t2}">▯</span><em style="color:{t2}">Gerät</em></div>
    </div>
    <div class="circle" style="background:{tint}; box-shadow: 0 10px 30px {shadow}, inset 0 0 0 0.8px {gl}; color:{t1}">⚙</div>
  </div>
  <div class="label" style="color:{t3}">{name}</div>
</div>"""

def main(out, accent="OCEAN"):
    bases = parse_bases(); acc = accents()[accent]
    names = [("GlassLight", "Liquid Glass Hell"), ("GlassDark", "Liquid Glass Dunkel"), ("MinimalLight", "Minimal Hell"), ("DeepDark", "Deep Dark")]
    phones = "".join(page(label, bases[k], acc[1] if bases[k]["isDark"] == "true" else acc[0]) for k, label in names)
    css = f"""
@font-face {{ font-family: Inter; src: url('{FONTS}/inter_regular.ttf'); font-weight: 400; }}
@font-face {{ font-family: Inter; src: url('{FONTS}/inter_medium.ttf'); font-weight: 500; }}
@font-face {{ font-family: Inter; src: url('{FONTS}/inter_semibold.ttf'); font-weight: 600; }}
@font-face {{ font-family: InterDisplay; src: url('{FONTS}/inter_display_semibold.ttf'); font-weight: 600; }}
@font-face {{ font-family: InterDisplay; src: url('{FONTS}/inter_display_light.ttf'); font-weight: 300; }}
body {{ margin:0; background:#888; display:flex; gap:24px; padding:24px; font-family: Inter; }}
.phone {{ width:360px; height:800px; position:relative; overflow:hidden; border-radius:28px; flex:none; }}
.status {{ height:32px; padding:8px 20px 0; font-size:13px; font-weight:500 }}
.content {{ padding:20px 20px 0; }}
.eyebrow {{ font-size:12px; font-weight:600; letter-spacing:.12em; }}
.large {{ font-family:InterDisplay; font-weight:600; font-size:32px; line-height:38px; letter-spacing:-.02em; margin-top:4px }}
.callout {{ font-size:14px; line-height:20px; margin:4px 0 16px }}
.panel {{ border-radius:24px; padding:18px; margin-bottom:14px }}
.hdr {{ display:flex; align-items:center; gap:12px }} .hdr>div:nth-child(2) {{ flex:1 }}
.badge {{ width:36px; height:36px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:18px }}
.badge.s {{ width:32px; height:32px; font-size:15px }}
.headline {{ font-weight:600; font-size:16px; line-height:22px }} .foot {{ font-size:13px; line-height:18px }}
.chev {{ font-size:24px }}
.row {{ display:flex; align-items:center; gap:20px; margin-top:16px }}
.ring {{ width:136px; height:136px; border-radius:50%; display:flex; align-items:center; justify-content:center; flex:none }}
.hole {{ width:106px; height:106px; border-radius:50%; display:flex; flex-direction:column; align-items:center; justify-content:center }}
.num {{ font-family:InterDisplay; font-weight:600; font-size:24px; font-feature-settings:'tnum' }} .cap {{ font-size:12px; font-weight:500 }}
.legend {{ flex:1 }} .lg {{ display:flex; align-items:center; gap:8px; padding:3px 0; font-size:13px }} .lg span {{ flex:1 }}
.lg i {{ width:9px; height:9px; border-radius:50%; display:inline-block }} .lg b, .srow b {{ font-weight:500; font-size:15px; font-feature-settings:'tnum' }}
.hl {{ height:1px; margin:8px 0 }}
.srow {{ display:flex; align-items:center; gap:12px; }} .sl {{ flex:1 }} .body {{ font-weight:500; font-size:15px }}
.batt {{ width:40px; height:20px; border:1.7px solid; border-radius:6px; padding:2px; box-sizing:border-box; margin-right:6px }} .batt div {{ height:100%; border-radius:3px }}
.pill {{ font-size:12px; font-weight:500; padding:5px 10px; border-radius:99px }}
.bar {{ position:absolute; left:12px; right:12px; bottom:16px; display:flex; gap:8px }}
.tabs {{ flex:1; height:64px; border-radius:32px; display:flex; position:relative; backdrop-filter: blur(26px) saturate(1.35); }}
.lens {{ position:absolute; left:3px; top:6px; bottom:6px; width:calc(25% - 6px); border-radius:26px }}
.t {{ flex:1; display:flex; flex-direction:column; align-items:center; justify-content:center; position:relative; font-size:20px }}
.t em {{ font-style:normal; font-size:11px; font-weight:500; margin-top:3px }}
.circle {{ width:64px; height:64px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:22px; backdrop-filter: blur(26px) }}
.label {{ position:absolute; top:10px; left:0; right:0; text-align:center; font-size:11px }}
"""
    pathlib.Path(out).write_text(f"<!doctype html><meta charset='utf-8'><style>{css}</style>{phones}")
    print(out)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "home_preview.html", sys.argv[2] if len(sys.argv) > 2 else "OCEAN")
