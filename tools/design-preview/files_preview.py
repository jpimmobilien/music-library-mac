#!/usr/bin/env python3
"""
Design-Vorschau „Dateien“ und „Bewegung“ ohne Gerät – NACHGEBAUT in HTML/CSS, kein Bildschirmfoto der App.

Farben aus PaletteSpec.kt, Symbole aus Icons.kt (echte Pfade), Schrift Inter. Zeigt vier Bildschirme in vier Themes:
Dateien-Startseite (Liquid Glass Hell), Ordner als Liste mit Auswahl und Werkzeugleiste (Liquid Glass Dunkel),
Ordner als Raster (Minimal Hell), Bewegung (Deep Dark). Layout, Unschärfe und Vorschaubilder sind angenähert;
die Inhalte sind Beispielwerte für die Vorschau.

Aufruf (im Projektordner):  python3 tools/design-preview/files_preview.py out.html [Akzent]
"""
import importlib.util, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

home = load("home_preview", HERE / "home_preview.py")
icons = load("icon_preview", ROOT / "tools/icons/preview.py")
ICONS = dict(icons.parse())

def ic(name, size, color):
    return icons.svg(ICONS[name], size, color)

def theme(b, acc_hex, intensity=0.7, sheen=0.8):
    rgba, hexrgb = home.rgba, home.hexrgb
    dark = b["isDark"] == "true"
    glass = b["glass"] == "true"
    ar, ag, ab = hexrgb(acc_hex)
    t = dict(
        dark=dark, glass=glass, acc=f"rgb({ar},{ag},{ab})", soft=f"rgba({ar},{ag},{ab},{0.20 if dark else 0.13})",
        t1=rgba(b["text"]), t2=rgba(b["textSecondary"]), t3=rgba(b["textTertiary"]), fill=rgba(b["fill"]),
        fillS=rgba(b["fillStrong"]), hair=rgba(b["hairline"]), onAcc=rgba(b["onAccent"]),
        tint=rgba(b["glassTint"]) if glass else rgba(b["glassTintSolid"]), gl=rgba(b["glassEdgeLight"]),
        shadow=rgba(b["shadow"]) if not dark else "transparent",
        info=rgba(b["info"]), infoS=rgba(b["info"], 0.16 if dark else 0.10),
        succ=rgba(b["success"]), succS=rgba(b["success"], 0.16 if dark else 0.10),
        warn=rgba(b["warning"]), warnS=rgba(b["warning"], 0.16 if dark else 0.10),
        crit=rgba(b["critical"]), critS=rgba(b["critical"], 0.16 if dark else 0.10),
    )
    accA = float(b["atmosphereAccentAlpha"].rstrip("f")) * intensity
    atmo = ""
    if accA > 0:
        atmo += f"radial-gradient(circle at -5% 4%, rgba({ar},{ag},{ab},{accA:.3f}), transparent 62%),"
    cool, warm = b["atmosphereCool"], b["atmosphereWarm"]
    if int(cool, 16) >> 24: atmo += f"radial-gradient(circle at 108% 30%, {rgba(cool, intensity)}, transparent 56%),"
    if int(warm, 16) >> 24: atmo += f"radial-gradient(circle at 25% 102%, {rgba(warm, intensity)}, transparent 62%),"
    t["bg"] = f"{atmo} linear-gradient(180deg, {rgba(b['backgroundTop'])} 0%, {rgba(b['background'])} 55%, {rgba(b['backgroundBottom'])} 100%)"
    sh = rgba(b["sheen"], sheen if glass else 0)
    if glass:
        t["panel"] = f"background: linear-gradient(180deg,{sh} 0%, transparent 40%), linear-gradient(180deg,{rgba(b['panelTop'])},{rgba(b['panelBottom'])}); box-shadow: 0 6px 20px {t['shadow']}, inset 0 1px 0 {rgba(b['panelEdgeTop'])}, inset 0 -1px 0 {rgba(b['panelEdgeBottom'])};"
    else:
        t["panel"] = f"background: {rgba(b['surface'])}; box-shadow: 0 4px 14px {t['shadow']}, inset 0 0 0 1px {t['hair']};"
    t["glassbar"] = f"background:{t['tint']}; box-shadow: 0 10px 30px {t['shadow']}, inset 0 0 0 0.8px {t['gl']};"
    return t

def badge(t, name, tone="acc", size=36):
    fg = t["t2"] if tone == "neutral" else t[tone]; bg = t["soft"] if tone == "acc" else (t[tone + "S"] if tone in ("info", "succ", "warn", "crit") else t["fill"])
    return f'<div class="badge" style="width:{size}px;height:{size}px;background:{bg}">{ic(name, round(size*0.56), fg)}</div>'

def tabbar(t, selected):
    items = [("Home", "Übersicht"), ("Folder", "Dateien"), ("StorageRing", "Speicher"), ("Phone", "Gerät")]
    cells = "".join(f'<div class="t">{ic(i, 22, t["acc"] if n == selected else t["t2"])}<em style="color:{t["t1"] if n == selected else t["t2"]}">{n}</em></div>' for i, n in items)
    idx = [n for _, n in items].index(selected)
    return f'''<div class="bar"><div class="tabs" style="{t['glassbar']}"><div class="lens" style="background:{t['soft']};left:calc({idx}*25% + 3px)"></div>{cells}</div>
      <div class="circle" style="{t['glassbar']}">{ic("Sliders", 22, t["t1"])}</div></div>'''

def row(t, icon, tone, name, detail, selected=None, location=None, divider=True):
    sel = ""
    if selected is not None:
        sel = (f'<div class="mark" style="background:{t["acc"]}">{ic("Check", 15, t["onAcc"])}</div>' if selected
               else f'<div class="mark" style="border:1.5px solid {t["t3"]}"></div>')
    bg = f"background:{t['fill']};" if selected else ""
    loc = f'<div class="cap" style="color:{t["t2"] if selected else t["t3"]}">{location}</div>' if location else ""
    more = "" if selected is not None else f'<div class="more">{ic("More", 20, t["t2"])}</div>'
    div = f'<div class="div" style="background:{t["hair"]};margin-left:{96 if selected is not None else 60}px"></div>' if divider else ""
    thumb = f'<div class="thumb" style="background:{t[tone + "S"] if tone in ("info","succ","warn","crit") else (t["soft"] if tone == "acc" else t["fill"])}">{ic(icon, 23, t[tone] if tone != "neutral" else t["t2"])}</div>'
    return f'''<div class="frow" style="{bg}">{sel}{thumb}<div class="fl"><div class="fname">{name}</div><div class="foot" style="color:{t["t2"]}">{detail}</div>{loc}</div>{more}</div>{div}'''

def files_home(name, t):
    p = t["panel"]
    cats = [("FileImage", "Bilder", "4.812 Dateien<br>21,3 GB", "info"), ("FileVideo", "Videos", "212 Dateien<br>38,1 GB", "info"),
            ("FileAudio", "Musik", "1.104 Dateien<br>6,2 GB", "succ"), ("Document", "Dokumente", "96 Dateien<br>412 MB", "neutral"),
            ("FilePdf", "PDFs", "58 Dateien<br>230 MB", "crit"), ("Download", "Downloads", "143 Dateien<br>3,4 GB", "acc")]
    catcells = "".join(f'<div class="cat" style="background:{t["fill"]}">{badge(t, i, tone, 34)}<div><div class="sub">{l}</div><div class="cap" style="color:{t["t2"]}">{d}</div></div></div>' for i, l, d, tone in cats)
    quick = "".join(f'<div class="qt" style="background:{t["fill"]}">{ic("Folder", 26, t["acc"])}<div class="cap">{q}</div></div>' for q in ["Downloads", "Kamera", "Dokumente"])
    return f'''<div class="phone" style="background:{t['bg']};color:{t['t1']}">
  <div class="status">18:06 <span style="float:right">82 %</span></div>
  <div class="content">
    <div class="large">Dateien</div>
    <div class="callout" style="color:{t['t2']}">Interner Speicher, SD-Karten und USB-Speicher</div>
    <div class="search" style="background:{t['fill']};color:{t['t2']}">{ic("Search", 20, t["t2"])}<span>Dateien und Ordner suchen</span></div>
    <div class="panel" style="{p}">
      <div class="hdr">{badge(t, "Drive")}<div><div class="headline">Speicherorte</div><div class="foot" style="color:{t['t2']}">Antippen zum Durchsuchen</div></div></div>
      <div class="vrow">{badge(t, "Phone")}<div class="fl"><div class="body">Interner Speicher</div><div class="foot" style="color:{t['t2']}">47,4 GB frei von 128 GB</div><div class="cbar" style="background:{t['fill']}"><div style="width:63%;background:{t['acc']}"></div></div></div>{ic("ChevronRight", 20, t["t3"])}</div>
      <div class="div" style="background:{t['hair']}"></div>
      <div class="vrow">{badge(t, "SdCard")}<div class="fl"><div class="body">SanDisk SD-Karte</div><div class="foot" style="color:{t['t2']}">88,2 GB frei von 119 GB</div><div class="cbar" style="background:{t['fill']}"><div style="width:26%;background:{t['acc']}"></div></div></div>{ic("ChevronRight", 20, t["t3"])}</div>
    </div>
    <div class="panel" style="{p}">
      <div class="hdr">{badge(t, "Layers")}<div><div class="headline">Kategorien</div><div class="foot" style="color:{t['t2']}">Aus dem Medienindex von Android</div></div></div>
      <div class="cats">{catcells}</div>
    </div>
    <div class="panel" style="{p}">
      <div class="hdr">{badge(t, "Folder")}<div><div class="headline">Schnellzugriff</div><div class="foot" style="color:{t['t2']}">Häufige Ordner im internen Speicher</div></div></div>
      <div class="quick">{quick}</div>
    </div>
  </div>
  {tabbar(t, "Dateien")}
  <div class="label" style="color:{t['t3']}">{name} · Dateien</div>
</div>'''

def folder_list(name, t):
    rows = "".join([
        row(t, "Folder", "acc", "Urlaub 2026", "Gestern, 21:14", selected=False),
        row(t, "FileImage", "info", "IMG_20261026_181203.jpg", "4,2 MB · Gestern, 18:12", selected=True),
        row(t, "FileImage", "info", "IMG_20261026_181547.jpg", "3,9 MB · Gestern, 18:15", selected=True),
        row(t, "FilePdf", "crit", "Mietvertrag.pdf", "812 kB · 12. März", selected=False),
        row(t, "FileArchive", "warn", "Fotos-Export.zip", "1,2 GB · 03.11.25", selected=True),
        row(t, "FileText", "neutral", "notizen.md", "2,1 kB · Heute, 09:41", selected=False),
        row(t, "FilePackage", "warn", "Musikbibliothek-1.3.0.apk", "18,4 MB · Heute, 08:02", selected=False, divider=False),
    ])
    tools = [("Share", "Teilen", t["t1"]), ("Copy", "Kopieren", t["t1"]), ("MoveTo", "Verschieben", t["t1"]), ("Trash", "Papierkorb", t["crit"]), ("More", "Mehr", t["t1"])]
    bar = "".join(f'<div class="t">{ic(i, 22, c)}<em style="color:{c}">{l}</em></div>' for i, l, c in tools)
    return f'''<div class="phone" style="background:{t['bg']};color:{t['t1']}">
  <div class="status">18:06 <span style="float:right">82 %</span></div>
  <div class="content">
    <div class="hrow"><div class="cbtn" style="{t['glassbar']}">{ic("Close", 22, t["t1"])}</div><div class="title2">3 ausgewählt</div><div class="pillb" style="background:{t['fill']}">{ic("SelectAll", 16, t["t1"])}<span>Alle</span></div></div>
    <div class="path"><span style="color:{t['acc']}">Interner Speicher</span>{ic("ChevronRight", 14, t["t3"])}<span style="color:{t['acc']}">DCIM</span>{ic("ChevronRight", 14, t["t3"])}<b>Camera</b></div>
    {rows}
  </div>
  <div class="bar"><div class="tabs tb" style="{t['glassbar']}">{bar}</div></div>
  <div class="label" style="color:{t['t3']}">{name} · Ordner mit Auswahl</div>
</div>'''

def folder_grid(name, t):
    tiles = [("Folder", "acc", "Screenshots", True), ("Folder", "acc", "WhatsApp", True)] + [("FileImage", "info", f"IMG_{n}.jpg", False) for n in (4401, 4402, 4403, 4410, 4411, 4415, 4420)] + [("FileVideo", "info", "VID_4421.mp4", False), ("FileImage", "info", "IMG_4425.jpg", False), ("FileImage", "info", "IMG_4426.jpg", False)]
    cells = ""
    hues = [210, 28, 160, 340, 48, 190, 260, 12, 120, 300]
    for k, (i, tone, n, folder) in enumerate(tiles):
        if folder:
            img = f'<div class="gt" style="background:transparent">{ic("Folder", 70, t["acc"])}</div>'
        else:
            h = hues[k % len(hues)]
            img = f'<div class="gt" style="background:linear-gradient(135deg,hsl({h},45%,62%),hsl({(h+40)%360},50%,38%))">{ic("FileVideo", 22, "rgba(255,255,255,.9)") if i == "FileVideo" else ""}</div>'
        cells += f'<div class="gc">{img}<div class="cap gname" style="color:{t["t1"]}">{n}</div></div>'
    return f'''<div class="phone" style="background:{t['bg']};color:{t['t1']}">
  <div class="status">18:06 <span style="float:right">82 %</span></div>
  <div class="content">
    <div class="hrow"><div class="cbtn" style="{t['glassbar']}">{ic("ChevronLeft", 22, t["t1"])}</div><div><div class="title">Camera</div><div class="foot" style="color:{t['t2']}">412 Objekte · 3 versteckt</div></div><div style="flex:1"></div><div class="cbtn" style="{t['glassbar']}">{ic("More", 22, t["t1"])}</div></div>
    <div class="path"><span style="color:{t['acc']}">Interner Speicher</span>{ic("ChevronRight", 14, t["t3"])}<span style="color:{t['acc']}">DCIM</span>{ic("ChevronRight", 14, t["t3"])}<b>Camera</b></div>
    <div class="grid">{cells}</div>
  </div>
  <div class="hud" style="{t['glassbar']}"><div class="fl"><div class="body">412 Objekte kopieren</div><div class="cbar" style="background:{t['fill']}"><div style="width:41%;background:{t['acc']}"></div></div><div class="cap" style="color:{t['t2']}">1,4 GB von 3,4 GB · noch etwa 2 Min.</div></div>{ic("Close", 18, t["t2"])}</div>
  {tabbar(t, "Dateien")}
  <div class="label" style="color:{t['t3']}">{name} · Raster und Fortschritt</div>
</div>'''

def motion(name, t):
    p = t["panel"]
    tiles = [("Mountain", "Höhe", "312", "m", "über Meeresspiegel"), ("Compass", "Kurs", "245°", "", "Südwest"), ("LocationPin", "Genauigkeit", "± 4", "m", "horizontal"), ("Satellite", "Satelliten", "18", "/ 31", "in Verwendung")]
    tl = "".join(f'<div class="mt" style="{p}"><div class="mh">{ic(i, 16, t["acc"])}<span style="color:{t["t2"]}">{l}</span></div><div class="mv">{v}<small style="color:{t["t2"]}"> {u}</small></div><div class="cap" style="color:{t["t3"]}">{c}</div></div>' for i, l, v, u, c in tiles)
    return f'''<div class="phone" style="background:{t['bg']};color:{t['t1']}">
  <div class="status">18:06 <span style="float:right">82 %</span></div>
  <div class="content">
    <div class="hrow"><div class="cbtn" style="{t['glassbar']}">{ic("ChevronLeft", 22, t["t1"])}</div><div class="title">Bewegung</div></div>
    <div class="panel" style="{p}">
      <div class="mh">{ic("Gauge", 16, t["acc"])}<span style="color:{t['t2']}">Geschwindigkeit · GPS</span><span class="pill" style="background:{t['succS']};color:{t['succ']}">Live</span></div>
      <div class="hero">48<small style="color:{t['t2']}"> km/h</small></div>
      <div class="foot" style="color:{t['t2']}">± 1,1 km/h · Fix vor 1 s</div>
    </div>
    <div class="tiles">{tl}</div>
    <div class="panel" style="{p}">
      <div class="hdr">{badge(t, "Compass")}<div><div class="headline">Kompass</div><div class="foot" style="color:{t['t2']}">Geografisch Nord (Missweisung + 3,8°)</div></div></div>
      <div class="dial" style="border-color:{t['hair']}"><div class="needle" style="background:{t['acc']}"></div><span style="color:{t['t1']}">245°</span><b style="color:{t['crit']}">N</b></div>
    </div>
  </div>
  <div class="label" style="color:{t['t3']}">{name} · Bewegung</div>
</div>'''

CSS = """
body { margin:0; background:#888; display:flex; gap:24px; padding:24px; font-family: Inter; }
.phone { width:360px; height:800px; position:relative; overflow:hidden; border-radius:28px; flex:none; }
.status { height:32px; padding:8px 20px 0; font-size:13px; font-weight:500 }
.content { padding:16px 20px 0; }
.large { font-family:InterDisplay; font-weight:600; font-size:32px; line-height:38px; letter-spacing:-.02em; }
.title { font-family:InterDisplay; font-weight:600; font-size:24px; line-height:30px } .title2 { font-family:InterDisplay; font-weight:600; font-size:19px; flex:1 }
.callout { font-size:14px; line-height:20px; margin:4px 0 14px }
.search { height:44px; border-radius:14px; display:flex; align-items:center; gap:8px; padding:0 12px; font-size:15px; margin-bottom:14px }
.panel { border-radius:24px; padding:16px; margin-bottom:14px }
.hdr { display:flex; align-items:center; gap:12px; margin-bottom:8px } .hdr>div:nth-child(2) { flex:1 }
.badge { border-radius:50%; display:flex; align-items:center; justify-content:center; flex:none }
.headline { font-weight:600; font-size:16px; line-height:22px } .foot { font-size:13px; line-height:18px } .body { font-weight:500; font-size:15px }
.sub { font-weight:500; font-size:13px } .cap { font-size:12px; line-height:16px; font-weight:500 }
.vrow { display:flex; align-items:center; gap:12px; padding:6px 0 } .fl { flex:1; min-width:0 }
.cbar { height:4px; border-radius:2px; margin-top:6px; overflow:hidden } .cbar div { height:100%; border-radius:2px }
.div { height:.5px; margin:4px 0 }
.cats { display:grid; grid-template-columns:1fr 1fr; gap:10px } .cat { display:flex; gap:8px; align-items:center; padding:10px; border-radius:14px }
.quick { display:grid; grid-template-columns:1fr 1fr 1fr; gap:10px } .qt { display:flex; flex-direction:column; align-items:center; gap:4px; padding:12px 0; border-radius:14px }
.hrow { display:flex; align-items:center; gap:14px; margin-bottom:6px }
.cbtn { width:52px; height:52px; border-radius:50%; display:flex; align-items:center; justify-content:center; flex:none }
.pillb { display:flex; gap:6px; align-items:center; padding:8px 14px; border-radius:99px; font-size:14px; font-weight:500 }
.path { display:flex; align-items:center; gap:2px; font-size:13px; margin:6px 0 10px } .path b { font-weight:500 }
.frow { display:flex; align-items:center; gap:12px; padding:9px 4px; border-radius:14px; min-height:46px }
.mark { width:24px; height:24px; border-radius:50%; display:flex; align-items:center; justify-content:center; flex:none; box-sizing:border-box }
.thumb { width:44px; height:44px; border-radius:11px; display:flex; align-items:center; justify-content:center; flex:none }
.fname { font-weight:500; font-size:15px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis }
.more { width:36px; display:flex; justify-content:center }
.grid { display:grid; grid-template-columns:repeat(3,1fr); gap:14px 10px }
.gc { display:flex; flex-direction:column; align-items:center; gap:4px } .gt { width:100%; aspect-ratio:1; border-radius:12px; display:flex; align-items:center; justify-content:center }
.gname { text-align:center; max-width:100%; white-space:nowrap; overflow:hidden; text-overflow:ellipsis }
.hud { position:absolute; left:20px; right:20px; bottom:100px; border-radius:24px; padding:12px 14px 12px 16px; display:flex; align-items:center; gap:10px; backdrop-filter: blur(26px) saturate(1.35) }
.bar { position:absolute; left:12px; right:12px; bottom:16px; display:flex; gap:8px }
.tabs { flex:1; height:64px; border-radius:32px; display:flex; position:relative; backdrop-filter: blur(26px) saturate(1.35); }
.lens { position:absolute; top:6px; bottom:6px; width:calc(25% - 6px); border-radius:26px }
.t { flex:1; display:flex; flex-direction:column; align-items:center; justify-content:center; position:relative }
.t em { font-style:normal; font-size:11px; font-weight:500; margin-top:3px }
.circle { width:64px; height:64px; border-radius:50%; display:flex; align-items:center; justify-content:center; backdrop-filter: blur(26px) }
.label { position:absolute; top:10px; left:0; right:0; text-align:center; font-size:11px }
.mh { display:flex; align-items:center; gap:6px; font-size:12px; font-weight:500 } .mh .pill { margin-left:auto }
.pill { font-size:12px; font-weight:500; padding:4px 10px; border-radius:99px }
.hero { font-family:InterDisplay; font-weight:300; font-size:76px; line-height:84px; letter-spacing:-.03em; font-feature-settings:'tnum' } .hero small { font-family:Inter; font-size:20px; font-weight:500; letter-spacing:0 }
.tiles { display:grid; grid-template-columns:1fr 1fr; gap:12px; margin-bottom:14px } .mt { border-radius:22px; padding:14px }
.mv { font-family:InterDisplay; font-weight:600; font-size:24px; margin:8px 0 2px; font-feature-settings:'tnum' } .mv small { font-family:Inter; font-size:13px; font-weight:500 }
.dial { width:150px; height:150px; margin:6px auto 0; border:2px solid; border-radius:50%; position:relative; display:flex; align-items:center; justify-content:center; font-family:InterDisplay; font-size:26px; font-weight:600 }
.dial b { position:absolute; top:8px; left:0; right:0; text-align:center; font-size:14px; font-family:Inter }
.needle { position:absolute; top:-6px; left:calc(50% - 2px); width:4px; height:18px; border-radius:2px }
"""

def main(out, accent="OCEAN"):
    bases = home.parse_bases(); acc = home.accents()[accent]
    def th(k): return theme(bases[k], acc[1] if bases[k]["isDark"] == "true" else acc[0])
    fonts = ROOT / "ui/designsystem/src/main/res/font"
    font_css = "".join(f"@font-face {{ font-family: {fam}; src: url('{fonts}/{f}'); font-weight: {w}; }}" for fam, f, w in [
        ("Inter", "inter_regular.ttf", 400), ("Inter", "inter_medium.ttf", 500), ("Inter", "inter_semibold.ttf", 600),
        ("InterDisplay", "inter_display_semibold.ttf", 600), ("InterDisplay", "inter_display_light.ttf", 300)])
    phones = files_home("Liquid Glass Hell", th("GlassLight")) + folder_list("Liquid Glass Dunkel", th("GlassDark")) + \
        folder_grid("Minimal Hell", th("MinimalLight")) + motion("Deep Dark", th("DeepDark"))
    pathlib.Path(out).write_text(f"<!doctype html><meta charset='utf-8'><style>{font_css}{CSS}</style>{phones}")
    print(out)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "files_preview.html", sys.argv[2] if len(sys.argv) > 2 else "OCEAN")
