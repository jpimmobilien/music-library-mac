#!/usr/bin/env python3
"""Prüft in der CI, ob die Repositories des Startkatalogs auf Hugging Face existieren.
Bei fehlenden Einträgen werden über den Suchbegriff passende MLX-Repositories vorgeschlagen."""
import json
import re
import sys
import urllib.parse
import urllib.request

source = open("Sources/PanoraCore/Catalog.swift", encoding="utf-8").read()
entries = re.findall(r'entry\("([^"]+)",.*?hint: "([^"]+)"', source, flags=re.S)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Panora-CI"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:  # noqa: BLE001
        return 0, str(e)


missing = 0
for repo, hint in entries:
    status, data = get(f"https://huggingface.co/api/models/{repo}?blobs=true")
    if status == 200:
        files = data.get("siblings", [])
        size = sum((f.get("size") or 0) for f in files if f.get("rfilename", "").endswith(".safetensors"))
        lic = (data.get("cardData") or {}).get("license") or next((t[8:] for t in data.get("tags", []) if t.startswith("license:")), "?")
        print(f"OK      {repo:60s} {size/1e9:6.1f} GB  Lizenz: {lic}")
    else:
        missing += 1
        q = urllib.parse.urlencode({"search": hint, "author": "mlx-community", "sort": "downloads", "direction": "-1", "limit": "6"})
        s, results = get(f"https://huggingface.co/api/models?{q}")
        names = [r.get("id") for r in (results or [])] if isinstance(results, list) else []
        print(f"FEHLT   {repo:60s} (Status {status}) Vorschläge: {', '.join(names) or '–'}")

print(f"\n{len(entries)} Einträge, {missing} nicht gefunden")
sys.exit(0)
