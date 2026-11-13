#!/usr/bin/env python3
"""Zweiter Teil der KI-Probe: objektive Ersatzprüfungen für das, was ein Mensch hören würde.

- Gesangstrennung mit demucs-mlx (Stimme vom Rest trennen) – Zeit und Pegel der Spuren
- Spracherkennung (mlx-whisper, Deutsch) auf den Gesangsstücken: Wie viel vom vorgegebenen Text ist
  verständlich? (Wortfehlerrate; niedrig = gut verständlich). Ersetzt keinen Hörtest.

Aufruf:  python probe_listen.py <out>   (in einer eigenen Umgebung mit demucs-mlx und mlx-whisper)
"""

import json
import os
import re
import subprocess
import sys
import time
import traceback

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "out")
WHISPER = os.environ.get("KI_WHISPER", "mlx-community/whisper-large-v3-turbo")
probe_path = os.path.join(OUT, "probe.json")
if os.path.exists(probe_path):
    probe = json.load(open(probe_path))
else:
    # Prüfstand KI-E2E: Ordner audio/<fall>/*.flac; Gesang mit Referenztext 03-text-de.txt
    probe = {"cases": []}
    audio_dir = os.path.join(OUT, "audio")
    ref_path = os.path.join(audio_dir, "03-text-de.txt")
    reference = open(ref_path).read() if os.path.exists(ref_path) else ""
    for case in sorted(os.listdir(audio_dir)) if os.path.isdir(audio_dir) else []:
        d = os.path.join(audio_dir, case)
        if not os.path.isdir(d):
            continue
        files = [{"path": os.path.relpath(os.path.join(d, f), OUT)} for f in sorted(os.listdir(d)) if f.endswith((".flac", ".wav", ".mp3"))]
        vocal = "gesang" in case
        probe["cases"].append({"id": case if case != "01-instrumental-en" else "01-instrumental-en", "files": files,
                               "params": {"instrumental": not vocal, "lyrics": reference if vocal else "[Instrumental]"}})
result = {"whisper_model": WHISPER, "separation": [], "transcripts": []}


def save():
    with open(os.path.join(OUT, "listen.json"), "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)


def words(text):
    text = re.sub(r"\[[^\]]*\]", " ", text or "")
    return re.findall(r"[a-zäöüß]+", text.lower())


def wer(ref, hyp):
    r, h = words(ref), words(hyp)
    if not r:
        return None
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev = cur
    return round(d[len(h)] / len(r), 3)


def transcribe(path, ref, label):
    entry = {"file": os.path.relpath(path, OUT), "label": label}
    try:
        import mlx_whisper
        t0 = time.time()
        r = mlx_whisper.transcribe(path, path_or_hf_repo=WHISPER, language="de", condition_on_previous_text=False)
        entry.update(seconds=round(time.time() - t0, 1), text=r.get("text", "").strip(), wer=wer(ref, r.get("text", "")),
                     reference_words=len(words(ref)))
    except Exception as e:
        entry.update(error=repr(e), trace=traceback.format_exc()[-2000:])
    result["transcripts"].append(entry)
    save()
    print(f"[Hören] {label}: WER {entry.get('wer')} – {entry.get('text', entry.get('error'))[:200]}", flush=True)


def separate(path, label):
    entry = {"file": os.path.relpath(path, OUT), "label": label}
    dest = os.path.join(OUT, "separated")
    try:
        t0 = time.time()
        p = subprocess.run(["demucs-mlx", "-n", "htdemucs", "-o", dest, path], capture_output=True, text=True, timeout=1800)
        entry.update(seconds=round(time.time() - t0, 1), returncode=p.returncode, log=(p.stdout + p.stderr)[-1500:])
        stems = []
        for root, _, files in os.walk(dest):
            for f in files:
                if os.path.splitext(os.path.basename(path))[0] in root:
                    stems.append(os.path.join(root, f))
        entry["stems"] = [os.path.relpath(s, OUT) for s in sorted(stems)]
    except Exception as e:
        entry.update(error=repr(e))
    result["separation"].append(entry)
    save()
    print(f"[Trennen] {label}: {entry.get('seconds')} s, Spuren {entry.get('stems')}", flush=True)
    return entry.get("stems", [])


lyrics_by_case = {}
for c in probe.get("cases", []):
    if c.get("params", {}).get("instrumental") is False:
        lyrics_by_case[c["id"]] = c["params"].get("lyrics", "")

for c in probe.get("cases", []):
    if c["id"] not in lyrics_by_case:
        continue
    for f in c.get("files", []):
        path = os.path.join(OUT, f["path"])
        transcribe(path, lyrics_by_case[c["id"]], c["id"] + " (Mix)")
        stems = separate(path, c["id"])
        vocal = next((s for s in stems if "vocals" in os.path.basename(s)), None)
        if vocal:
            transcribe(os.path.join(OUT, vocal), lyrics_by_case[c["id"]], c["id"] + " (getrennte Stimme)")

# Gegenprobe: ein Instrumentalstück sollte (fast) keinen erkannten Text enthalten
inst = next((c for c in probe.get("cases", []) if c["id"] == "01-instrumental-en" and c.get("files")), None)
if inst:
    path = os.path.join(OUT, inst["files"][0]["path"])
    transcribe(path, "", "01-instrumental-en (Gegenprobe, sollte leer sein)")
    separate(path, "01-instrumental-en")

result["finished"] = True
save()
