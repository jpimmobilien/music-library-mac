#!/usr/bin/env python3
"""Hörspiel-Probe 4: Referenzanalyse, Stimmprofile und Prüfung für berechtigte Stimmen.

A  Mehrsprecher-Testaufnahme mit bekannter Wahrheit aus Multilingual LibriSpeech (Deutsch, CC BY 4.0):
   fünf echte Sprecher, Erzähler + Dialog, Raumklang, Musikbrücken, Kassettenklang → Sprecherzahl und Fehlerrate
B  die in Probe 3 produzierte Hörspielfassung (Sprecher-Wahrheit aus der Schnittliste)
C  eine echte deutsche Mehrsprecher-Lesung von LibriVox (gemeinfrei) – Sprecherzahl laut Besetzungsliste
D  Stimmprofile: aus den Profilen von A neue Stimmen entwerfen und nachmessen (Tonhöhe, Tempo)
E  Schwelle für die Stimmprüfung bei berechtigten Stimmen: Ähnlichkeit gleicher vs. verschiedener Sprecher (MLS)

Aufruf: python probe_analyze.py <out> [produktion-dir]
"""

import io
import json
import os
import re
import sys
import time
import traceback
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_common import A, Report, cos, log  # noqa: E402

import numpy as np  # noqa: E402

import hs_analyze as H  # noqa: E402

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "out")
PROD = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else None
WORK = os.path.join(OUT, "analyse")
os.makedirs(WORK, exist_ok=True)
report = Report(os.path.join(OUT, "analyze.json"))
rng = np.random.default_rng(42)


# MARK: Testmaterial

def mls_german(max_rows=1500):
    """Eine Testdatei von Multilingual LibriSpeech (Deutsch) laden: [{speaker, text, audio(16k)}]."""
    from huggingface_hub import HfApi, hf_hub_download
    import pyarrow.parquet as pq
    import soundfile as sf
    files = [f for f in HfApi().list_repo_files("facebook/multilingual_librispeech", repo_type="dataset")
             if "german" in f.lower() and f.endswith(".parquet") and ("test" in f or "dev" in f)]
    if not files:
        raise RuntimeError("Keine deutschen MLS-Parquet-Dateien gefunden")
    path = hf_hub_download("facebook/multilingual_librispeech", sorted(files)[0], repo_type="dataset")
    table = pq.read_table(path)
    cols = table.column_names
    rows = []
    for r in table.slice(0, max_rows).to_pylist():
        audio = r.get("audio") or {}
        data, sr = sf.read(io.BytesIO(audio["bytes"]), dtype="float32")
        if data.ndim == 2:
            data = data.mean(axis=1)
        rows.append({"speaker": str(r.get("speaker_id")), "text": r.get("transcript") or r.get("text") or "",
                     "audio": A.resample(data, sr, 16000)})
    return rows, {"file": os.path.basename(path), "columns": cols}


def chord(sr, seconds, root=220.0, seed=0):
    """Kurze Musikbrücke (Synthesizer-Akkord mit Hüllkurve) – nur Testmaterial."""
    t = np.arange(int(sr * seconds)) / sr
    x = np.zeros_like(t)
    for k, ratio in enumerate((1, 5 / 4, 3 / 2, 2)):
        x += np.sign(np.sin(2 * np.pi * root * ratio * t + k)) * 0.06
    x = A.lowpass(x.astype(np.float32), sr, 2500)
    env = np.minimum(1, t / 0.3) * np.minimum(1, (seconds - t) / 1.2)
    return (x * env).astype(np.float32)


def build_composite(rows, n_speakers=5, scenes=3):
    """Hörspielartige Testaufnahme mit bekannter Sprecherfolge."""
    by = {}
    for r in rows:
        by.setdefault(r["speaker"], []).append(r)
    cand = sorted([s for s, v in by.items() if len(v) >= 10], key=lambda s: -len(by[s]))[:n_speakers]
    if len(cand) < n_speakers:
        raise RuntimeError(f"Zu wenige Sprecher mit genug Aufnahmen ({len(cand)})")
    narrator, chars = cand[0], cand[1:]
    sr = 48000
    parts, truth, t = [], [], 0.0
    used = {s: 0 for s in cand}

    def put(audio16, speaker, room):
        nonlocal t
        a = A.resample(audio16, 16000, sr)
        a = A.room(a, sr, room)
        parts.append((t, a))
        truth.append({"start": round(t, 3), "end": round(t + a.shape[1] / sr - 0.05, 3), "speaker": speaker})
        t += a.shape[1] / sr

    rooms = ["zimmer", "halle", "draußen"]
    for sc in range(scenes):
        for _ in range(2):
            r = by[narrator][used[narrator] % len(by[narrator])]
            used[narrator] += 1
            put(r["audio"], narrator, "trocken")
            t += 0.5
        cast = [chars[(sc + k) % len(chars)] for k in range(3)]
        last = None
        for turn in range(9):
            s = rng.choice([c for c in cast if c != last])
            r = by[s][used[s] % len(by[s])]
            used[s] += 1
            seg = r["audio"][: int(16000 * min(len(r["audio"]) / 16000, 4.0 + rng.random() * 3))]
            put(seg, s, rooms[sc % len(rooms)])
            t += 0.25 + rng.random() * 0.35
            last = s
        m = chord(sr, 4.5, root=196 * (1 + 0.12 * sc))
        parts.append((t, A.to_stereo(m)))
        t += 5.0
    total = np.zeros((2, int(t * sr) + sr), dtype=np.float32)
    for start, a in parts:
        s = int(start * sr)
        total[:, s: s + a.shape[1]] += a
    total = A.retro(total, sr, 1.0)
    total = A.normalize_lufs(total, sr, -18)
    path = os.path.join(WORK, "mls-testhoerspiel.wav")
    A.write_wav(path, total, sr)
    return path, truth, {"narrator": narrator, "characters": chars}


def librivox_german_drama():
    """Erste deutsche Mehrsprecher-Lesung (Drama) von LibriVox suchen und den ersten Abschnitt laden."""
    titles = ["Woyzeck", "Leonce und Lena", "Minna von Barnhelm", "Nathan der Weise", "Der zerbrochne Krug",
              "Emilia Galotti", "Kabale und Liebe", "Die Räuber", "Wilhelm Tell", "Maria Stuart", "Dantons Tod",
              "Der Biberpelz", "Die Weber", "Iphigenie auf Tauris", "Prinz Friedrich von Homburg", "Der Talisman",
              "Einen Jux will er sich machen", "Der Verschwender", "Die Journalisten", "Der eingebildete Kranke"]
    tried = []
    for title in titles:
        url = ("https://librivox.org/api/feed/audiobooks/?format=json&extended=1&title="
               + urllib.parse.quote("^" + title))
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                data = json.loads(r.read())
        except Exception as e:  # noqa: BLE001
            tried.append(f"{title}: {e}")
            continue
        for book in data.get("books", []):
            if book.get("language") != "German":
                continue
            for sec in book.get("sections", []):
                readers = [x.get("display_name") for x in sec.get("readers", [])]
                if len(set(readers)) >= 3 and sec.get("listen_url"):
                    secs = int(sec.get("playtime") or 0)
                    if 240 <= secs <= 2400:
                        path = os.path.join(WORK, "librivox.mp3")
                        urllib.request.urlretrieve(sec["listen_url"], path)
                        desc = re.sub(r"<[^>]+>", " ", book.get("description", ""))
                        return path, {"title": book.get("title"), "section": sec.get("title"), "seconds": secs,
                                      "readers": readers, "url": book.get("url_librivox"),
                                      "description": re.sub(r"\s+", " ", desc)[:3000]}
        tried.append(f"{title}: keine passende deutsche Mehrsprecher-Lesung")
    raise RuntimeError("; ".join(tried)[:2000])


# MARK: Ablauf

models = H.Models(log=log)
report.step("Analysemodelle geladen", seconds=models.load_seconds)
results = {}

rows = None
try:
    t0 = time.time()
    rows, info = mls_german()
    report.step("MLS geladen", seconds=round(time.time() - t0, 1), rows=len(rows),
                speakers=len({r["speaker"] for r in rows}), info=info)
except Exception as e:  # noqa: BLE001
    report.step("MLS Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

if rows:
    try:
        path, truth, cast = build_composite(rows)
        r = H.analyze(path, models, log=log, truth=truth)
        results["A_mls"] = r
        report.step("A: MLS-Testhörspiel", cast=cast, evaluation=r["evaluation"], sweep=r["threshold_sweep"],
                    seconds=r["seconds"], summary=r["summary_de"])
    except Exception as e:  # noqa: BLE001
        report.step("A Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

if PROD and os.path.exists(os.path.join(PROD, "hoerspiel.mp3")):
    try:
        truth = json.load(open(os.path.join(PROD, "sprecher-wahrheit.json")))
        r = H.analyze(os.path.join(PROD, "hoerspiel.mp3"), models, log=log, truth=truth)
        results["B_produktion"] = r
        report.step("B: eigene Produktion", evaluation=r["evaluation"], sweep=r["threshold_sweep"],
                    seconds=r["seconds"], summary=r["summary_de"])
    except Exception as e:  # noqa: BLE001
        report.step("B Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])
else:
    report.step("B übersprungen", reason="keine Produktion aus Probe 3 vorhanden")

try:
    path, meta = librivox_german_drama()
    r = H.analyze(path, models, log=log)
    results["C_librivox"] = r
    report.step("C: LibriVox", meta=meta, speakers_found=len(r["speakers"]),
                readers_listed=len(set(meta["readers"])), seconds=r["seconds"], summary=r["summary_de"])
except Exception as e:  # noqa: BLE001
    report.step("C Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

for k, r in results.items():
    with open(os.path.join(WORK, f"{k}.json"), "w") as f:
        json.dump(r, f, indent=2, ensure_ascii=False, default=str)
    with open(os.path.join(WORK, f"{k}-stilprofil.json"), "w") as f:
        json.dump(H.style_profile(r, k), f, indent=2, ensure_ascii=False, default=str)

# E: Schwelle für die Stimmprüfung (gleiche vs. verschiedene Sprecher)
if rows:
    try:
        by = {}
        for r in rows:
            by.setdefault(r["speaker"], []).append(r)
        spk = [s for s, v in by.items() if len(v) >= 6][:20]
        emb = {s: [models.embed(A.trim_silence(x["audio"], 16000)) for x in by[s][:6]] for s in spk}
        same = [cos(a, b) for s in spk for i, a in enumerate(emb[s]) for b in emb[s][i + 1:]]
        diff = [cos(emb[s][0], emb[t][j]) for i, s in enumerate(spk) for t in spk[i + 1:] for j in range(2)]
        thr = sorted(diff)[int(0.999 * (len(diff) - 1))] if diff else None
        report.step("E: Stimmprüfung kalibriert", speakers=len(spk), pairs_same=len(same), pairs_diff=len(diff),
                    same_p5=round(float(np.percentile(same, 5)), 3), same_median=round(float(np.median(same)), 3),
                    diff_median=round(float(np.median(diff)), 3), diff_max=round(float(np.max(diff)), 3),
                    threshold_far_0_1=round(float(thr), 3) if thr is not None else None,
                    same_below_threshold=round(float(np.mean(np.array(same) < thr)), 3) if thr is not None else None)
    except Exception as e:  # noqa: BLE001
        report.step("E Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

# D: Stimmprofile → neue Stimmen → nachmessen
src = results.get("A_mls") or results.get("C_librivox")
if src:
    try:
        import hs_voice as V
        m = V.QwenDesign()
        text = V.REFERENCE_TEXT
        fid = []
        for i, sp in enumerate(src["speakers"]):
            a, sr = m.speak(text, sp["voice_en"], "de", 300 + i)
            a = A.trim_silence(a, sr)
            p = os.path.join(WORK, "profil-stimmen", f"{sp['id']}.wav")
            A.write_wav(p, a, sr)
            x16 = A.resample(a, sr, 16000)
            f0 = H.f0_yin(x16)
            f0 = f0[np.isfinite(f0)]
            segs = models.speech(x16)
            speech = sum(e - s for s, e in segs) or len(x16) / 16000
            syl = sum(H.syllables(w) for w in text.split())
            got = {"f0_median_hz": round(float(np.median(f0)), 1) if f0.size else None,
                   "syllables_per_second": round(syl / speech, 2)}
            want = {"f0_median_hz": sp.get("f0_median_hz"), "syllables_per_second": sp.get("syllables_per_second")}
            entry = {"speaker": sp["id"], "voice_en": sp["voice_en"], "want": want, "got": got}
            if want["f0_median_hz"] and got["f0_median_hz"]:
                entry["f0_error_semitones"] = round(float(12 * np.log2(got["f0_median_hz"] / want["f0_median_hz"])), 1)
            fid.append(entry)
        m.unload()
        report.step("D: Stimmprofile nachgemessen", results=fid)
    except Exception as e:  # noqa: BLE001
        report.step("D Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

for f in ("mls-testhoerspiel.wav",):
    p = os.path.join(WORK, f)
    if os.path.exists(p):
        from probe_common import to_mp3
        to_mp3(p, "128k")
        os.remove(p)
log("[Probe] Analyse fertig")
