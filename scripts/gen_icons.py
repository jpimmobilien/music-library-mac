#!/usr/bin/env python3
"""Erzeugt Sources/MusicLibrary/Design/IconData.swift aus den Vektor-Symbolen der Android-App.

Aufruf:  python3 scripts/gen_icons.py <android-res-drawable-ordner>

Die Android-App verwendet Material Symbols Rounded (Apache License 2.0, Google) und eigene Zeichnungen
(Genre-Symbole, Vinyl, Pitch). Die Pfade werden unverändert übernommen, damit die Mac-App dieselbe
Symbolsprache spricht.
"""
import os
import sys
import xml.etree.ElementTree as ET

A = "{http://schemas.android.com/apk/res/android}"
SKIP = {"ic_launcher_foreground", "ic_launcher_monochrome", "ic_notification"}


def swift_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def alpha_of(color: str) -> float:
    if not color or not color.startswith("#"):
        return 1.0
    hexpart = color[1:]
    if len(hexpart) == 8:
        return int(hexpart[0:2], 16) / 255.0
    return 1.0


def main():
    src = sys.argv[1]
    out = os.path.join(os.path.dirname(__file__), "..", "Sources", "MusicLibrary", "Design", "IconData.swift")
    entries = []
    keys = set()
    names = []
    for name in sorted(os.listdir(src)):
        if not name.endswith(".xml"):
            continue
        stem = name[:-4]
        if not (stem.startswith("ic_") or stem.startswith("genre_")) or stem in SKIP:
            continue
        root = ET.parse(os.path.join(src, name)).getroot()
        if root.tag != "vector":
            continue
        vw = float(root.get(A + "viewportWidth"))
        vh = float(root.get(A + "viewportHeight"))
        paths = []
        for p in root.iter("path"):
            d = p.get(A + "pathData")
            fill = p.get(A + "fillColor", "#00000000")
            stroke = p.get(A + "strokeColor")
            sw = float(p.get(A + "strokeWidth", "0"))
            cap = p.get(A + "strokeLineCap", "butt")
            join = p.get(A + "strokeLineJoin", "miter")
            even = p.get(A + "fillType", "nonZero") == "evenOdd"
            fill_alpha = alpha_of(fill) * float(p.get(A + "fillAlpha", "1"))
            stroke_alpha = (alpha_of(stroke) if stroke else 0.0) * float(p.get(A + "strokeAlpha", "1"))
            paths.append(
                f"IconPath(d: {swift_str(d)}, fill: {fill_alpha:.3f}, evenOdd: {'true' if even else 'false'}, "
                f"stroke: {stroke_alpha if sw > 0 else 0:.3f}, lineWidth: {sw}, cap: .{cap}, join: .{join})"
            )
        key = stem[3:] if stem.startswith("ic_") else stem
        keys.add(key)
        names.append(key)
        entries.append(f"        case {swift_str(key)}: return IconSpec(width: {vw}, height: {vh}, paths: [\n            "
                       + ",\n            ".join(paths) + "\n        ])")
    # Zusätzliche Material Symbols Rounded (SVG, viewBox 0 -960 960 960) für Mac-Funktionen ohne Android-Gegenstück
    extra = os.path.join(os.path.dirname(__file__), "material-symbols")
    for name in sorted(os.listdir(extra)):
        if not name.endswith(".svg"):
            continue
        key = name[:-4]
        if key in keys:
            continue  # das Android-Symbol hat Vorrang
        names.append(key)
        root = ET.parse(os.path.join(extra, name)).getroot()
        if root.get("viewBox"):
            vb = [float(v) for v in root.get("viewBox").split()]
        else:  # ältere Symbole ohne viewBox: Koordinaten in width × height
            vb = [0.0, 0.0, float(root.get("width", "24")), float(root.get("height", "24"))]
        paths = []
        for el in root.iter("{http://www.w3.org/2000/svg}path"):
            paths.append(f"IconPath(d: {swift_str(el.get('d'))}, fill: 1.000, evenOdd: false, stroke: 0.000, lineWidth: 0.0, cap: .butt, join: .miter)")
        entries.append(f"        case {swift_str(key)}: return IconSpec(width: {vb[2]}, height: {vb[3]}, minY: {vb[1]}, paths: [\n            "
                       + ",\n            ".join(paths) + "\n        ])")
    with open(out, "w", encoding="utf-8") as f:
        f.write("// Automatisch erzeugt mit scripts/gen_icons.py aus den Vektor-Symbolen der Android-App – nicht von Hand ändern.\n")
        f.write("// Material Symbols Rounded: Apache License 2.0 (Google). Genre-, Vinyl- und Pitch-Symbole: eigene Zeichnungen.\n\n")
        f.write("enum IconData {\n    // swiftlint:disable:next cyclomatic_complexity function_body_length\n")
        f.write("    static func spec(_ name: String) -> IconSpec? {\n        switch name {\n")
        f.write("\n".join(entries))
        f.write("\n        default: return nil\n        }\n    }\n\n")
        f.write("    static let names: [String] = [" + ", ".join(swift_str(k) for k in names) + "]\n}\n")
    print(f"{len(entries)} Symbole → {os.path.normpath(out)}")


if __name__ == "__main__":
    main()
