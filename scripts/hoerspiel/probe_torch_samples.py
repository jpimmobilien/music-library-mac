#!/usr/bin/env python3
"""Hörproben ohne Apple-Silicon-Rechner: dieselben Qwen3-TTS-Gewichte mit dem PyTorch-Original (qwen-tts) auf Linux.

Wofür: Solange GitHub keine Mac-Prüfrechner zuteilt, lässt sich so trotzdem hören und messen, wie die gewählten
Stimmen Deutsch sprechen. Es ist NICHT der Code der App (die nutzt mlx-audio auf dem Mac) – Klang und Aussprache
kommen aus denselben Modellgewichten, Geschwindigkeit und Details der Umsetzung sind nicht übertragbar.

Ablauf wie in der App: Stimme aus der Figurenbeschreibung entwerfen (VoiceDesign, Referenzsatz) → jede Zeile aus
dieser Referenz klonen (Base). Danach:
  1. Prüfsätze (Umlaute, Zahlen, Komposita, Gefühle) für Erzähler und Mädchen
  2. erste Szene(n) der Geschichte als Hörspiel gemischt (Raumklang, Panorama, Retro-Klang, Lautheit) – ohne
     Geräusche und Musik (die kommen auf dem Mac aus Stable Audio und der KI-Musik)
  3. Erkennbarkeit mit Whisper (faster-whisper large-v3-turbo, CPU)

Aufruf: python probe_torch_samples.py <story.json> <out> [sekunden_szene=90]
"""

import json
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "Resources", "HoerspielEngine"))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
import torch  # noqa: E402

import hs_audio as A  # noqa: E402
import hs_produce as P  # noqa: E402
from hs_text import normalize_for_speech, chunk_text  # noqa: E402
from hs_voice import REFERENCE_TEXT, design_instruct  # noqa: E402

STORY = sys.argv[1]
OUT = os.path.abspath(sys.argv[2])
SCENE_SECONDS = float(sys.argv[3]) if len(sys.argv) > 3 else 90
os.makedirs(OUT, exist_ok=True)
REPORT = {"steps": [], "lines": [], "tests": []}


def step(name, **kw):
    kw["name"] = name
    kw["time"] = time.strftime("%H:%M:%S")
    REPORT["steps"].append(kw)
    print("[Probe]", name, json.dumps({k: v for k, v in kw.items() if k not in ("name", "trace")}, ensure_ascii=False)[:600],
          flush=True)
    with open(os.path.join(OUT, "proben.json"), "w") as f:
        json.dump(REPORT, f, ensure_ascii=False, indent=2)


def mp3(wav, bitrate="128k"):
    out = wav[:-4] + ".mp3"
    os.system(f'ffmpeg -loglevel error -y -i "{wav}" -b:a {bitrate} "{out}"')
    return out


torch.set_num_threads(os.cpu_count() or 4)
DTYPE = torch.bfloat16 if os.environ.get("HS_TORCH_DTYPE", "bf16") == "bf16" else torch.float32
from qwen_tts import Qwen3TTSModel  # noqa: E402

story = json.load(open(STORY))
figs = {f["id"]: f for f in story["concept"]["figuren"]}

# Auswahl: Szenen von vorn, bis etwa SCENE_SECONDS Sprechzeit (≈ 2,3 Wörter/s)
lines_all = P.line_list(story)
budget_words = SCENE_SECONDS * 2.3
chosen_scenes, words = [], 0
for si, s in enumerate(story["scenes"]):
    w = sum(len(it["text"].split()) for it in s["items"] if it["type"] == "line")
    if chosen_scenes and words + w > budget_words * 1.3:
        break
    chosen_scenes.append(si)
    words += w
sub = {"concept": story["concept"], "scenes": [story["scenes"][i] for i in chosen_scenes]}
lines = P.line_list(sub)
speakers = sorted({ln["speaker"] for ln in lines}, key=lambda x: (x != "ERZÄHLER", x))
step("Auswahl", scenes=[story["scenes"][i]["title"] for i in chosen_scenes], lines=len(lines), words=words, speakers=speakers)

TESTS = [
    ("01_umlaute", "Grüß Gott, Frau Müller! Ihre Brötchen sind heute aber besonders knusprig."),
    ("02_zahlen", "Am 14. Juli 1984 um 22:15 Uhr verschwand der Nachtzug nach Hamburg."),
    ("03_komposita", "Eisenbahnverkehrsunternehmen, Fahrkartenschalter und Bahnhofsvorsteher: Das ist unser Fall."),
    ("04_aufgeregt", "Hast du das gehört? Da drüben, hinter der Güterhalle – da bewegt sich etwas!"),
    ("05_fluesternd", "Psst, leise. Wenn uns hier jemand findet, sind wir geliefert."),
]
test_voices = [s for s in speakers if s == "ERZÄHLER"][:1] + [s for s in speakers if s != "ERZÄHLER"][:1]

# 1. Stimmen entwerfen
refs = {}
try:
    t0 = time.time()
    design = Qwen3TTSModel.from_pretrained("Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign", device_map="cpu", dtype=DTYPE)
    step("VoiceDesign geladen", seconds=round(time.time() - t0, 1), dtype=str(DTYPE))
    for i, sp in enumerate(speakers):
        torch.manual_seed(100 + i)
        t1 = time.time()
        instr = design_instruct(figs.get(sp, {"id": sp}))
        wavs, sr = design.generate_voice_design(text=REFERENCE_TEXT, instruct=instr, language="German")
        a = A.trim_silence(np.asarray(wavs[0], dtype=np.float32), sr)
        path = os.path.join(OUT, "stimmen", f"{sp}.wav")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        sf.write(path, a, sr)
        refs[sp] = path
        dur = len(a) / sr
        step(f"Stimme {sp}", instruct=instr, duration=round(dur, 2), seconds=round(time.time() - t1, 1),
             rtf=round((time.time() - t1) / max(dur, 0.1), 2))
    del design
except Exception as e:  # noqa: BLE001
    step("VoiceDesign Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])
    sys.exit(1)

# 2. Zeilen klonen
voice_files = {}
try:
    t0 = time.time()
    base = Qwen3TTSModel.from_pretrained("Qwen/Qwen3-TTS-12Hz-1.7B-Base", device_map="cpu", dtype=DTYPE)
    step("Base geladen", seconds=round(time.time() - t0, 1))
    prompts = {sp: base.create_voice_clone_prompt(ref_audio=p, ref_text=REFERENCE_TEXT, x_vector_only_mode=False)
               for sp, p in refs.items()}

    def speak(text, sp, path, seed):
        parts, sr = [], 24000
        for chunk in chunk_text(normalize_for_speech(text), 220):
            torch.manual_seed(seed)
            wavs, sr = base.generate_voice_clone(text=chunk, language="German", voice_clone_prompt=prompts[sp])
            parts += [A.trim_silence(np.asarray(wavs[0], dtype=np.float32), sr), np.zeros(int(0.12 * sr), np.float32)]
        a = np.concatenate(parts[:-1])
        os.makedirs(os.path.dirname(path), exist_ok=True)
        sf.write(path, a, sr)
        return len(a) / sr

    total_audio, t_lines = 0.0, time.time()
    for n, ln in enumerate(lines):
        path = os.path.join(OUT, "zeilen", f"{ln['key']}.wav")
        t1 = time.time()
        dur = speak(ln["text"], ln["speaker"], path, 1000 + n)
        voice_files[ln["key"]] = path
        total_audio += dur
        REPORT["lines"].append({**ln, "path": path, "duration": round(dur, 2), "seconds": round(time.time() - t1, 1)})
        if n % 5 == 0:
            step(f"Zeile {n + 1}/{len(lines)}", audio_s=round(total_audio, 1), rtf=round((time.time() - t_lines) / max(total_audio, 0.1), 2))
    step("Zeilen fertig", lines=len(lines), audio_s=round(total_audio, 1), seconds=round(time.time() - t_lines, 1),
         rtf=round((time.time() - t_lines) / max(total_audio, 0.1), 2))
    for sp in test_voices:
        for tid, text in TESTS:
            path = os.path.join(OUT, "pruefsaetze", f"{sp}_{tid}.wav")
            t1 = time.time()
            dur = speak(text, sp, path, 7)
            REPORT["tests"].append({"voice": sp, "id": tid, "text": text, "spoken": normalize_for_speech(text), "path": path,
                                    "duration": round(dur, 2), "seconds": round(time.time() - t1, 1)})
    step("Prüfsätze fertig", count=len(REPORT["tests"]))
    del base
except Exception as e:  # noqa: BLE001
    step("Klonen Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])

# 3. Mischen (ohne Geräusche/Musik)
try:
    sub2 = {"concept": sub["concept"], "scenes": []}
    for s in sub["scenes"]:
        s2 = dict(s)
        s2["items"] = [it for it in s["items"] if it["type"] in ("line", "pause")]
        sub2["scenes"].append(s2)
    # Schlüssel neu zuordnen (ohne Geräuschzeilen verschieben sich die Positionen)
    remap = {}
    for (old, new) in zip(lines, P.line_list(sub2)):
        remap[new["key"]] = voice_files.get(old["key"])
    remap = {k: v for k, v in remap.items() if v}
    master, stems, tl, metrics, chapters = P.assemble(sub2, remap, {}, {}, retro_amount=0.6)
    wav = os.path.join(OUT, "hoerprobe-szene.wav")
    A.write_wav(wav, master, P.SR)
    P.export_mp3(wav, os.path.join(OUT, "hoerprobe-szene.mp3"), chapters,
                 {"title": story["concept"].get("titel", "Hörprobe"), "artist": "KI-Hörspiel (Hörprobe, Linux/PyTorch)",
                  "comment": "Stimmen entworfen mit Qwen3-TTS, keine realen Personen. Ohne Geräusche und Musik."},
                 metrics["duration_s"], bitrate="192k")
    if not metrics.get("speech_to_background_db") or metrics["speech_to_background_db"] > 120:
        metrics["speech_to_background_db"] = None  # ohne Geräusche/Musik nicht aussagekräftig
    step("Gemischt", metrics=metrics)
except Exception as e:  # noqa: BLE001
    step("Mischen Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])

# 4. Erkennbarkeit (Whisper)
try:
    from faster_whisper import WhisperModel
    from probe_common import wer
    wm = WhisperModel("large-v3-turbo", device="cpu", compute_type="int8")

    def hear(path):
        # Audio selbst laden (faster-whisper öffnet Dateien über PyAV; dessen neue Fassung kennt
        # „metadata_errors“ nicht mehr – erster Lauf scheiterte daran)
        a, sr = sf.read(path, dtype="float32", always_2d=False)
        if a.ndim > 1:
            a = a.mean(axis=1)
        a = A.resample(a, sr, 16000).astype(np.float32)
        segs, _ = wm.transcribe(a, language="de", beam_size=5)
        return " ".join(s.text.strip() for s in segs)

    for t in REPORT["tests"]:
        t["hyp"] = hear(t["path"])
        t["wer"] = wer(t["spoken"], t["hyp"])
    for ln in REPORT["lines"]:
        ln["hyp"] = hear(ln["path"])
        ln["wer"] = wer(normalize_for_speech(ln["text"]), ln["hyp"])
    ws = [x["wer"] for x in REPORT["tests"] + REPORT["lines"] if x.get("wer") is not None]
    step("Whisper", wer_mean=round(float(np.mean(ws)), 3) if ws else None,
         wer_tests=round(float(np.mean([t["wer"] for t in REPORT["tests"]])), 3) if REPORT["tests"] else None,
         wer_lines=round(float(np.mean([x["wer"] for x in REPORT["lines"]])), 3) if REPORT["lines"] else None)
except Exception as e:  # noqa: BLE001
    step("Whisper Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])

# MP3 für den Ergebniszweig
for root, _, names in os.walk(OUT):
    for n in names:
        if n.endswith(".wav"):
            p = os.path.join(root, n)
            if not os.path.exists(p[:-4] + ".mp3"):  # Hörprobe hat schon ihre MP3 mit Kapiteln (192 kbit/s)
                mp3(p, "128k" if "stimmen" in root or "pruefsaetze" in root else "96k")
            os.remove(p)
step("Fertig")
