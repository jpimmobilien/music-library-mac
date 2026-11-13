#!/usr/bin/env python3
"""Fasst die JUnit-Ergebnisse aller Module zusammen (Anzahl, Fehler, übersprungen) – für den Build-Bericht."""
import pathlib
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
totals = {}
failures = []
for xml in sorted(root.glob("**/build/test-results/**/*.xml")):
    module = str(xml.relative_to(root)).split("/build/")[0]
    variant = xml.parent.name
    key = f"{module} ({variant})"
    t = ET.parse(xml).getroot()
    n, f, e, s = (int(t.get(k, 0)) for k in ("tests", "failures", "errors", "skipped"))
    c = totals.setdefault(key, [0, 0, 0])
    c[0] += n
    c[1] += f + e
    c[2] += s
    for case in t.iter("testcase"):
        for bad in list(case.findall("failure")) + list(case.findall("error")):
            failures.append(f"{key}: {case.get('classname')}.{case.get('name')} – {(bad.get('message') or '').strip()[:300]}")
all_n = sum(v[0] for v in totals.values())
all_f = sum(v[1] for v in totals.values())
for k, (n, f, s) in totals.items():
    print(f"{k:55s} {n:4d} Tests  {f:3d} fehlgeschlagen  {s:3d} übersprungen")
print(f"{'GESAMT':55s} {all_n:4d} Tests  {all_f:3d} fehlgeschlagen")
for line in failures:
    print("FEHLER", line)
