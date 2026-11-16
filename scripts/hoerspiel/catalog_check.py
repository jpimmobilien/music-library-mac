#!/usr/bin/env python3
"""Prüft den Modellkatalog der KI-Hörbücher gegen Hugging Face: gibt es das Repo, ist es frei zugänglich (nicht
„gated“), wie groß ist es wirklich, welche Lizenz steht in der Modellkarte? Nur Standardbibliothek.

Aufruf: python3 catalog_check.py <ausgabeordner> [Sources/MLStudio/HoerspielModels.swift]
Ergebnis: katalog.json und katalog.md im Ausgabeordner; Rückgabewert 1, wenn ein Katalogeintrag fehlt, gesperrt ist
oder seine Größe um mehr als 25 % abweicht.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

# Modelle, die nur im Prüfstand verglichen werden (nicht im App-Katalog)
EXTRA = [
    "mlx-community/VoxCPM2-8bit",
    "mlx-community/chatterbox-multilingual-v3",
    "mlx-community/gemma-4-e4b-it-4bit",
    "mlx-community/Qwen3-4B-Instruct-2507-4bit",
    "mlx-community/Qwen3.5-27B-4bit",
    "mlx-community/Qwen3.6-35B-A3B-4bit",
    "bartowski/google_gemma-4-26B-A4B-it-GGUF",
]


def catalog(swift_path):
    text = open(swift_path, encoding="utf-8").read()
    items = []
    for m in re.finditer(r'HSModel\(repo:\s*"([^"]+)".*?bytes:\s*([\d_]+).*?license:\s*"([^"]+)"', text, re.S):
        items.append({"repo": m.group(1), "catalog_bytes": int(m.group(2).replace("_", "")), "catalog_license": m.group(3)})
    return items


def fetch(repo):
    url = f"https://huggingface.co/api/models/{repo}?blobs=true"
    req = urllib.request.Request(url, headers={"User-Agent": "music-library-catalog-check"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def license_of(info):
    card = info.get("cardData") or {}
    lic = card.get("license")
    if lic == "other":
        lic = f"other ({card.get('license_name') or card.get('license_link') or '?'})"
    if not lic:
        tags = [t for t in info.get("tags", []) if t.startswith("license:")]
        lic = tags[0].split(":", 1)[1] if tags else None
    return lic


def main():
    out = sys.argv[1]
    swift = sys.argv[2] if len(sys.argv) > 2 else "Sources/MLStudio/HoerspielModels.swift"
    os.makedirs(out, exist_ok=True)
    rows = []
    problems = 0
    entries = catalog(swift) + [{"repo": r, "catalog_bytes": None, "catalog_license": None} for r in EXTRA]
    for e in entries:
        info, err = fetch(e["repo"])
        row = dict(e)
        if info is None:
            row.update(exists=False, error=err)
            if e["catalog_bytes"] is not None:
                problems += 1
        else:
            size = sum((s.get("size") or 0) for s in info.get("siblings", []))
            row.update(exists=True, bytes=size, gated=info.get("gated", False), license=license_of(info),
                       sha=info.get("sha"), last_modified=info.get("lastModified"),
                       files=len(info.get("siblings", [])), downloads=info.get("downloads"),
                       base_model=(info.get("cardData") or {}).get("base_model"))
            if e["catalog_bytes"]:
                row["deviation"] = round(size / e["catalog_bytes"] - 1, 3)
                if row["gated"] or abs(row["deviation"]) > 0.25:
                    problems += 1
        rows.append(row)
        print(f"[Katalog] {json.dumps(row, ensure_ascii=False)}", flush=True)
    with open(os.path.join(out, "katalog.json"), "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
    lines = ["| Repo | gibt es | gesperrt | Größe (GB) | Katalog (GB) | Abw. | Lizenz (Karte) | Lizenz (Katalog) |",
             "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        gb = f"{r['bytes'] / 1e9:.2f}" if r.get("bytes") is not None else "–"
        cgb = f"{r['catalog_bytes'] / 1e9:.2f}" if r.get("catalog_bytes") else "–"
        dev = f"{r['deviation'] * 100:+.0f} %" if "deviation" in r else "–"
        lines.append(f"| {r['repo']} | {'ja' if r.get('exists') else 'nein (' + str(r.get('error')) + ')'} | "
                     f"{r.get('gated', '–')} | {gb} | {cgb} | {dev} | {r.get('license') or '–'} | {r.get('catalog_license') or '–'} |")
    with open(os.path.join(out, "katalog.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"[Katalog] Probleme: {problems}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
