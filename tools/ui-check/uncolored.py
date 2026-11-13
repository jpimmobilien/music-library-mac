#!/usr/bin/env python3
"""
Prüft die kritische Regel „kein Text wird in einem Theme unlesbar“ statisch im Quelltext.

Aufruf (im Projektordner):  python3 tools/ui-check/uncolored.py [-v]

1. Jeder Aufruf von Text(…), BasicText(…) und Icon(…) in app/ und ui/designsystem/ muss seine Farbe ausdrücklich
   aus dem Theme setzen (Text: color =, Icon: tint =). Geerbte Farben sind die Ursache des Dunkelmodus-Fehlers
   aus Musikbibliothek 1.2.0 (Compose nimmt ohne Angabe Schwarz an).
2. Feste Farben (Color(0x…), Color.Black/White/Gray …) sind nur in den Dateien des Designsystems erlaubt, die
   Farben definieren oder Licht zeichnen (Palette, Glas, Diagramme, Bausteine).
3. Das Theme muss LocalContentColor zentral setzen; GlassSurface und Panel ebenfalls.
Exit-Code 1 bei Verstoß.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DIRS = [ROOT / "app/src/main/java", ROOT / "ui/designsystem/src/main/java"]
verbose = "-v" in sys.argv
NEEDS = {"Text": "color", "BasicText": "color", "Icon": "tint"}
# Dateien, in denen feste Farbwerte erlaubt sind (Definition oder Lichteffekte)
COLOR_ALLOWED = {"PaletteSpec.kt", "Palette.kt", "Glass.kt", "Charts.kt", "Icons.kt", "Theme.kt", "Components.kt"}

def args_of(src, i):
    depth = 0; j = i
    while j < len(src):
        c = src[j]
        if c in "([{": depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0: return src[i + 1:j]
        elif c == '"':
            if src.startswith('"""', j):
                j = src.index('"""', j + 3) + 2
            else:
                k = j + 1
                while src[k] != '"':
                    if src[k] == "\\": k += 1
                    k += 1
                j = k
        j += 1
    return None

def top_level_parts(a):
    parts, cur, depth = [], "", 0
    for c in a:
        if c in "([{": depth += 1
        elif c in ")]}": depth -= 1
        if c == "," and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += c
    parts.append(cur)
    return [p for p in parts if p.strip()]

problems = []
count = 0
for d in DIRS:
    for f in sorted(d.rglob("*.kt")):
        src = f.read_text()
        rel = f.relative_to(ROOT)
        for m in re.finditer(r"(?<![\w.])(Text|BasicText|Icon)\s*\(", src):
            name = m.group(1)
            before = src[max(0, m.start() - 12):m.start()]
            if re.search(r"fun\s+$", before):
                continue
            a = args_of(src, m.end() - 1)
            if a is None:
                continue
            count += 1
            parts = top_level_parts(a)
            named = {re.match(r"\s*(\w+)\s*=(?!=)", p).group(1) for p in parts if re.match(r"\s*(\w+)\s*=(?!=)", p)}
            if NEEDS[name] in named:
                continue
            positional = [p for p in parts if not re.match(r"\s*\w+\s*=(?!=)", p)]
            # Icon(icon, desc, modifier, tint) bzw. Text(text, modifier, color) positionell
            if name == "Icon" and len(positional) >= 4:
                continue
            if name in ("Text", "BasicText") and len(positional) >= 3:
                continue
            line = src.count("\n", 0, m.start()) + 1
            problems.append(f"{rel}:{line}: {name}(…) ohne {NEEDS[name]} = …")
        if f.name not in COLOR_ALLOWED:
            for m in re.finditer(r"Color\(0x[0-9A-Fa-f]{6,8}\)|Color\.(Black|White|Gray|DarkGray|LightGray|Red|Green|Blue|Yellow|Cyan|Magenta)\b", src):
                line = src.count("\n", 0, m.start()) + 1
                problems.append(f"{rel}:{line}: feste Farbe {m.group(0)} außerhalb des Designsystems")

theme = (ROOT / "ui/designsystem/src/main/java/de/privateapp/aether/design/Theme.kt").read_text()
if "LocalContentColor provides colors.text" not in theme:
    problems.append("Theme.kt setzt LocalContentColor nicht zentral")
glass = (ROOT / "ui/designsystem/src/main/java/de/privateapp/aether/design/Glass.kt").read_text()
if "LocalContentColor provides colors.text" not in glass:
    problems.append("GlassSurface setzt keine Inhaltsfarbe")
comp = (ROOT / "ui/designsystem/src/main/java/de/privateapp/aether/design/Components.kt").read_text()
if "LocalContentColor provides colors.text" not in comp:
    problems.append("Panel setzt keine Inhaltsfarbe")

print(f"{count} Text-/Symbol-Aufrufe geprüft.")
for p in problems:
    print("  " + p)
if problems:
    print(f"{len(problems)} Verstoß/Verstöße.")
    sys.exit(1)
print("Keine Verstöße: Jede Schrift und jedes Symbol bezieht seine Farbe ausdrücklich aus dem Theme.")
