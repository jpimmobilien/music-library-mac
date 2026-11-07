#!/usr/bin/env python3
"""Fügt Übersetzungen aus einer Python-Datei (DE = {...}) in de.lproj/Localizable.strings ein (sortiert, ohne Dubletten).
   python3 tools/merge_de.py übersetzungen.py"""
import importlib.util
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
target = root / "Resources" / "Localization" / "de.lproj" / "Localizable.strings"
spec = importlib.util.spec_from_file_location("de_new", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
entry = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
unesc = lambda s: s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
table = {}
for line in target.read_text(encoding="utf-8").splitlines():
    m = entry.match(line)
    if m:
        table[unesc(m.group(1))] = unesc(m.group(2))
table.update(module.DE)
lines = ["/* AETHER – Deutsch */", ""] + [f'"{esc(k)}" = "{esc(v)}";' for k, v in sorted(table.items(), key=lambda kv: kv[0].lower())]
target.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"de.lproj: {len(table)} Einträge")
