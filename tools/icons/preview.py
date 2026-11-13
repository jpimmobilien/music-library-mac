#!/usr/bin/env python3
"""
Vorschau des Symbolsatzes „Aether Line“ ohne Gerät.

Liest die Pfade direkt aus ui/designsystem/.../Icons.kt (einschließlich circle(...) und gefüllter „F:“-Pfade)
und schreibt eine HTML-Seite mit allen Symbolen in hell und dunkel, in 24 dp und vergrößert.
Aufruf (im Projektordner):  python3 tools/icons/preview.py out.html
Ein Bild erzeugt man z. B. mit Playwright/Chromium (Bildschirmfoto der Seite).
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "ui/designsystem/src/main/java/de/privateapp/aether/design/Icons.kt"

def circle(cx, cy, r):
    return f"M{cx} {cy - r} A{r} {r} 0 1 1 {cx} {cy + r} A{r} {r} 0 1 1 {cx} {cy - r} Z"

def parse():
    src = SRC.read_text()
    icons = []
    for m in re.finditer(r'val (\w+): ImageVector by lazy \{\s*icon\((.*?)\)\s*\}', src, re.S):
        name, args = m.group(1), m.group(2)
        parts = []
        for tok in re.finditer(r'("F:"\s*\+\s*circle\(([^)]*)\))|(circle\(([^)]*)\))|("([^"]*)")', args):
            if tok.group(1):
                nums = [float(x.strip().rstrip('f')) for x in tok.group(2).split(',')]
                parts.append(("fill", circle(*nums)))
            elif tok.group(3):
                nums = [float(x.strip().rstrip('f')) for x in tok.group(4).split(',')]
                parts.append(("stroke", circle(*nums)))
            else:
                s = tok.group(6)
                if s.startswith("F:"): parts.append(("fill", s[2:]))
                else: parts.append(("stroke", s))
        parts = parts[1:]  # erster String ist der Name
        icons.append((name, parts))
    return icons

def svg(parts, size, color):
    els = []
    for kind, d in parts:
        if kind == "fill": els.append(f'<path d="{d}" fill="{color}"/>')
        else: els.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>')
    return f'<svg width="{size}" height="{size}" viewBox="0 0 24 24">{"".join(els)}</svg>'

def main(out):
    icons = parse()
    rows = []
    for bg, fg, label in [("#EDF1F6", "#0E141C", "hell"), ("#0A0E14", "#F2F4F7", "dunkel")]:
        cells = "".join(f'<div class="c"><div>{svg(p, 72, fg)}</div><div>{svg(p, 24, fg)}</div><span style="color:{fg}">{n}</span></div>' for n, p in icons)
        rows.append(f'<section style="background:{bg}"><h2 style="color:{fg}">{label}</h2><div class="g">{cells}</div></section>')
    html = f"""<!doctype html><meta charset="utf-8"><style>
body{{margin:0;font:12px system-ui}} section{{padding:16px}} h2{{margin:0 0 8px;font-size:14px}}
.g{{display:grid;grid-template-columns:repeat(8,1fr);gap:10px}} .c{{display:flex;flex-direction:column;align-items:center;gap:4px}}
</style>{''.join(rows)}"""
    pathlib.Path(out).write_text(html)
    print(f"{len(icons)} Symbole → {out}")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icons.html")
