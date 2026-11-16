#!/usr/bin/env python3
"""Lädt ein kleines MLX-Modell von Hugging Face für den Ende-zu-Ende-Test in der CI.
   python3 tools/fetch_model.py mlx-community/Qwen3-0.6B-4bit e2e-models"""
import json
import os
import sys
import urllib.request

repo, target = sys.argv[1], sys.argv[2]
folder = os.path.join(target, repo.replace("/", "__"))
os.makedirs(folder, exist_ok=True)
req = urllib.request.Request(f"https://huggingface.co/api/models/{repo}?blobs=true", headers={"User-Agent": "Panora-CI"})
info = json.loads(urllib.request.urlopen(req, timeout=60).read().decode())
wanted = (".safetensors", ".json", ".model", ".txt", ".jinja", ".tiktoken")
for f in info.get("siblings", []):
    name = f["rfilename"]
    if name.startswith(".") or not name.endswith(wanted):
        continue
    dest = os.path.join(folder, name)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    url = f"https://huggingface.co/{repo}/resolve/main/{name}"
    print("lade", name, f.get("size"))
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Panora-CI"}), timeout=600) as r, open(dest, "wb") as out:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
print(folder)
