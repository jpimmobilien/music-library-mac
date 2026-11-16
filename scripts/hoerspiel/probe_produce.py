#!/usr/bin/env python3
"""Hörspiel-Probe 3: Aus einer geschriebenen Geschichte ein vollständiges Hörspiel produzieren.

Stimmen entwerfen (Qwen3-TTS VoiceDesign) → alle Zeilen klonen (Qwen3-TTS Base) → Geräusche/Atmo erzeugen
(Stable Audio 3 small sfx) → Musik über die KI-Musik der App (ACE-Step, Resources/KIEngine/engine.py) →
Zeitleiste, Ducking, Raumklang, Retro-Klang, Lautheit → WAV/MP3 mit Kapiteln, Spuren, Schnittliste.
Danach Prüfungen: Whisper je Zeile und auf der fertigen Mischung, Stimmkonsistenz je Figur (ECAPA).

Aufruf: python probe_produce.py <story.json> <out>
Umgebung: KI_PYTHON, KI_ACE_ROOT, KI_CHECKPOINTS (ACE-Step wie in der App), HS_RETRO (0–1, Standard 1)
"""

import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_common import ENGINE, A, Listener, Report, cos, log, to_mp3, wer  # noqa: E402

import numpy as np  # noqa: E402

import hs_produce as P  # noqa: E402
import hs_voice as V  # noqa: E402

STORY = os.path.abspath(sys.argv[1])
OUT = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else "out")
WORK = os.path.join(OUT, "produktion")
os.makedirs(WORK, exist_ok=True)
report = Report(os.path.join(OUT, "produce.json"))
story = json.load(open(STORY))
t_start = time.time()

figures = P.speaking_figures(story)
lines = P.line_list(story)
report.step("Drehbuch geladen", title=story["concept"].get("titel"), scenes=len(story["scenes"]), lines=len(lines),
            figures=[f["id"] for f in figures], words=story.get("words"))

# 1. Stimmen
casting = V.Casting(WORK, "de", log=log)
try:
    V.reset_peak_memory()
    t0 = time.time()
    casting.design_all(figures)
    report.step("Stimmen entworfen", seconds=round(time.time() - t0, 1), peak_mb=V.peak_memory_mb(),
                voices={k: {kk: vv for kk, vv in v.items() if kk != "ref_audio"} for k, v in casting.voices.items()})
    V.reset_peak_memory()
    t0 = time.time()
    voice_results = casting.speak_lines(lines, os.path.join(WORK, "zeilen"),
                                        progress=lambda p, t: log(f"[Stimmen] {t}") if int(p * 100) % 10 == 0 else None)
    total_audio = sum(r["duration"] for r in voice_results)
    report.step("Zeilen gesprochen", seconds=round(time.time() - t0, 1), lines=len(voice_results),
                speech_seconds=round(total_audio, 1), rtf=round((time.time() - t0) / max(total_audio, 1), 2),
                peak_mb=V.peak_memory_mb())
except Exception as e:  # noqa: BLE001
    report.step("Stimmen Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])
    sys.exit(1)
voice_files = {r["key"]: r["path"] for r in voice_results}

# 2. Geräusche und Atmo
sfx_files = {}
try:
    wanted = {}
    for s in story["scenes"]:
        atmo = next((it["en"] for it in s["items"] if it["type"] == "atmo"), s.get("atmo_en"))
        if atmo:
            wanted[atmo] = 20.0
        for it in s["items"]:
            if it["type"] == "sfx" and it["en"]:
                wanted.setdefault(it["en"], 4.0)
    gen = P.SFXGenerator(os.path.join(OUT, "geraeusche-bibliothek"), log=log)
    report.step("Geräuschmodell geladen", seconds=gen.load_seconds, repo=gen.repo, cues=len(wanted))
    t0 = time.time()
    for prompt, sec in wanted.items():
        try:
            path, took = gen.get(prompt, sec)
            sfx_files[prompt] = path
            log(f"[Geräusche] {took} s – {prompt}")
        except Exception as e:  # noqa: BLE001
            report.step("Geräusch Fehler", prompt=prompt, error=repr(e))
    report.step("Geräusche erzeugt", seconds=round(time.time() - t0, 1), count=len(sfx_files),
                peak_mb=V.peak_memory_mb())
    gen.unload()
except Exception as e:  # noqa: BLE001
    report.step("Geräusche Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])

# 3. Musik über die KI-Musik (ACE-Step)
music_files = {}
try:
    cues, pieces = P.music_plan(story)
    report.step("Musikplan", cues=len(cues), pieces={k: v["seconds"] for k, v in pieces.items()},
                captions={k: v["caption"] for k, v in pieces.items()})
    client = P.KIMusicClient(os.environ["KI_PYTHON"], os.path.join(ENGINE, "..", "KIEngine", "engine.py"),
                             os.environ["KI_ACE_ROOT"], os.environ["KI_CHECKPOINTS"], log=log)
    t0 = time.time()
    client.request("load", dit="acestep-v15-turbo")
    report.step("Musikmodell geladen", seconds=round(time.time() - t0, 1))
    for kind, p in pieces.items():
        t0 = time.time()
        path, took = client.generate(p["caption"], p["seconds"], os.path.join(WORK, "musik", kind))
        music_files[kind] = path
        report.step(f"Musik {kind}", seconds=round(time.time() - t0, 1), duration=p["seconds"])
    client.close()
except Exception as e:  # noqa: BLE001
    report.step("Musik Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])

# 4. Mischen und Exportieren
try:
    t0 = time.time()
    retro = float(os.environ.get("HS_RETRO", "1"))
    master, stems, tl, metrics, chapters = P.assemble(story, voice_files, sfx_files, music_files, retro_amount=retro)
    wav = os.path.join(OUT, "hoerspiel.wav")
    A.write_wav(wav, master, P.SR)
    title = story["concept"].get("titel", "KI-Hörspiel")
    mp3 = P.export_mp3(wav, os.path.join(OUT, "hoerspiel.mp3"), chapters,
                       {"title": title, "artist": "KI-Hörspiel (lokal erzeugt)", "album": "KI-Hörspiel Machbarkeit",
                        "genre": "Hörspiel", "comment": "Erzeugt mit lokalen Modellen; Stimmen sind entworfen, keine realen Personen"},
                       metrics["duration_s"], bitrate="192k")
    stem_dir = os.path.join(OUT, "spuren")
    os.makedirs(stem_dir, exist_ok=True)
    for name, st in stems.items():
        p = os.path.join(stem_dir, f"{name.replace(' ', '_')}.wav")
        A.write_wav(p, st, P.SR, bits=16)
        to_mp3(p, "64k")
        os.remove(p)
    with open(os.path.join(OUT, "schnittliste.json"), "w") as f:
        json.dump({"chapters": chapters, "clips": tl.clips(), "metrics": metrics}, f, indent=2, ensure_ascii=False)
    truth = [{"start": c["start"], "end": round(c["start"] + c["duration"], 3),
              "speaker": c["label"].split(":")[0]} for c in tl.clips()
             if c["track"] == "Erzähler" or c["track"].startswith("Sprecher")]
    with open(os.path.join(OUT, "sprecher-wahrheit.json"), "w") as f:
        json.dump(truth, f, ensure_ascii=False)
    report.step("Gemischt und exportiert", seconds=round(time.time() - t0, 1), chapters=len(chapters),
                metrics=metrics, mp3=os.path.basename(mp3 or ""), total_seconds=round(time.time() - t_start, 1))
except Exception as e:  # noqa: BLE001
    report.step("Mischen Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])
    sys.exit(1)

# 5. Prüfungen (Ersatz für einen Hörtest)
try:
    V.free_memory()
    L = Listener()
    refs = {k: L.embedding(v["ref_audio"]) for k, v in casting.voices.items()}
    per_line = []
    for r in voice_results:
        e = L.embedding(r["path"])
        hyp = L.transcribe(r["path"])
        per_line.append({"key": r["key"], "speaker": r["speaker"], "wer": wer(r["text"], hyp), "hyp": hyp,
                         "text": r["text"], "duration": r["duration"],
                         "sim_own_ref": round(cos(e, refs[r["speaker"]]), 3) if r["speaker"] in refs else None,
                         "sim_best_other": round(max([cos(e, v) for k, v in refs.items() if k != r["speaker"]] or [0]), 3)})
    by = {}
    for p in per_line:
        by.setdefault(p["speaker"], []).append(p)
    speakers = {k: {"lines": len(v), "wer_mean": round(float(np.mean([x["wer"] for x in v if x["wer"] is not None])), 3),
                    "sim_own_ref_mean": round(float(np.mean([x["sim_own_ref"] for x in v])), 3),
                    "sim_own_ref_min": round(float(np.min([x["sim_own_ref"] for x in v])), 3),
                    "closer_to_other_voice": sum(1 for x in v if x["sim_best_other"] > x["sim_own_ref"])}
                for k, v in by.items()}
    all_text = " ".join(r["text"] for r in voice_results)
    hyp_master = L.transcribe(wav)
    report.data["lines"] = per_line
    report.step("Prüfung", speakers=speakers,
                wer_lines_mean=round(float(np.mean([p["wer"] for p in per_line if p["wer"] is not None])), 3),
                wer_master=wer(all_text, hyp_master), master_transcript_excerpt=hyp_master[:1500])
except Exception as e:  # noqa: BLE001
    report.step("Prüfung Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])

# Zeilen-WAVs als MP3 (kleiner im Ergebniszweig)
for r in voice_results:
    try:
        to_mp3(r["path"], "64k")
        os.remove(r["path"])
    except Exception:  # noqa: BLE001
        pass
for v in casting.voices.values():
    try:
        to_mp3(v["ref_audio"], "128k")
    except Exception:  # noqa: BLE001
        pass
log("[Probe] Produktion fertig")
