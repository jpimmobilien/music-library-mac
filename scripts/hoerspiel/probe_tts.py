#!/usr/bin/env python3
"""Hörspiel-Probe 1: Deutsche Sprachausgabe im Vergleich (Apple Silicon, mlx-audio).

Vier entworfene Rollen × acht deutsche Prüfsätze (Umlaute, Komposita, Zahlen, Gefühle, Flüstern) mit:
  qwen_design   Qwen3-TTS 1.7B VoiceDesign – jede Zeile direkt aus der Beschreibung
  qwen_clone    Qwen3-TTS 1.7B Base – jede Zeile aus dem entworfenen Referenzsatz geklont
  voxcpm_clone  VoxCPM2 (8 bit) – eigener entworfener Referenzsatz, dann geklont
  chatterbox    Chatterbox Multilingual v3 – aus den Qwen-Referenzen geklont (Ausdruck 0,5 / 0,85)
  piper         Piper de_DE-thorsten-high – klassische Sprachausgabe als Vergleich (eine Stimme)
Danach objektive Ersatzprüfungen: Whisper-Wortfehlerrate, Stimmähnlichkeit (ECAPA) zur Referenz und zwischen
Rollen, Tonhöhe, Geschwindigkeit, Speicher. Hören kann diese Probe nichts.

Aufruf: python probe_tts.py <out>
"""

import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_common import (A, Listener, Report, cos, f0_stats, log, to_mp3, wer)  # noqa: E402

import hs_voice as V  # noqa: E402
from hs_text import normalize_for_speech  # noqa: E402

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "out")
AUDIO = os.path.join(OUT, "tts")
os.makedirs(AUDIO, exist_ok=True)
ONLY = set(filter(None, os.environ.get("HS_TTS_ONLY", "").split(",")))

VOICES = {
    "ERZAEHLER": "A calm, warm, deep male narrator in his fifties, measured pace, clear articulation, friendly",
    "JUNGE": "A cheeky 14-year-old boy, bright and slightly hoarse voice, quick speech, energetic",
    "MAEDCHEN": "A clever 14-year-old girl, clear bright voice, confident and quick",
    "ALTER_MANN": "A gruff man in his sixties, low raspy voice, slow and suspicious",
}
SENTENCES = [
    ("01_neutral", "", "Über den Gleisen des alten Bahnhofs lag ein seltsamer Nebel, und niemand wusste, woher die Geräusche kamen."),
    ("02_aufgeregt", "excited, fast", "Hast du das gehört? Da drüben, hinter der Güterhalle – da bewegt sich etwas!"),
    ("03_neutral", "", "Der Schlüssel muss irgendwo im Stellwerk liegen. Wir suchen zuerst unter den Hebeln."),
    ("04_zahlen", "", "Am 14. Juli 1984 um 22:15 Uhr verschwand der Nachtzug nach Hamburg."),
    ("05_umlaute", "", "Grüß Gott, Frau Müller! Ihre Brötchen sind heute aber besonders knusprig."),
    ("06_komposita", "", "Eisenbahnverkehrsunternehmen, Fahrkartenschalter und Bahnhofsvorsteher: Das ist unser Fall."),
    ("07_aengstlich", "frightened, trembling", "Nein! Lass mich los! Ich habe nichts damit zu tun!"),
    ("08_fluesternd", "whispering softly", "Psst, leise. Wenn uns hier jemand findet, sind wir geliefert."),
]
EMOTIONAL = {"02_aufgeregt", "07_aengstlich", "08_fluesternd"}

report = Report(os.path.join(OUT, "tts.json"))
clips = []  # {"engine", "voice", "sentence", "path", "text", "seconds", "duration", "ref"}


def run(engine):
    return not ONLY or engine in ONLY


def save_clip(engine, voice, sid, text, audio, sr, seconds, ref=None, extra=None):
    path = os.path.join(AUDIO, engine, f"{voice}_{sid}.wav")
    audio = A.trim_silence(audio, sr)
    A.write_wav(path, audio, sr)
    c = {"engine": engine, "voice": voice, "sentence": sid, "path": path, "text": text, "seconds": round(seconds, 2),
         "duration": round(len(audio) / sr, 2), "ref": ref, **(extra or {})}
    c["rtf"] = round(c["seconds"] / max(c["duration"], 0.01), 2)
    clips.append(c)
    report.data["clips"] = clips
    report.save()
    return path


refs = {}

# 1. Qwen3-TTS VoiceDesign
if run("qwen_design") or run("qwen_clone") or run("chatterbox"):
    try:
        m = V.QwenDesign()
        report.step("Qwen VoiceDesign geladen", seconds=m.load_seconds, repo=m.repo)
        for i, (vid, desc) in enumerate(VOICES.items()):
            t0 = time.time()
            a, sr = m.speak(V.REFERENCE_TEXT, desc + ". Speaks native German.", "de", 100 + i)
            refs[vid] = save_clip("qwen_design", vid, "00_referenz", V.REFERENCE_TEXT, a, sr, time.time() - t0)
        if run("qwen_design"):
            for i, (vid, desc) in enumerate(VOICES.items()):
                for sid, emo, text in SENTENCES:
                    instr = desc + (f", {emo}" if emo else "") + ". Speaks native German."
                    t0 = time.time()
                    a, sr = m.speak(normalize_for_speech(text), instr, "de", 100 + i)
                    save_clip("qwen_design", vid, sid, text, a, sr, time.time() - t0, refs[vid])
        report.step("Qwen VoiceDesign fertig", peak_mb=V.peak_memory_mb())
        m.unload()
    except Exception as e:  # noqa: BLE001
        report.step("Qwen VoiceDesign Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

# 2. Qwen3-TTS Base (Klonen aus der entworfenen Referenz)
if run("qwen_clone") and refs:
    try:
        V.reset_peak_memory()
        m = V.QwenClone()
        report.step("Qwen Base geladen", seconds=m.load_seconds, repo=m.repo)
        for vid in VOICES:
            for sid, emo, text in SENTENCES:
                t0 = time.time()
                a, sr = m.speak(normalize_for_speech(text), refs[vid], V.REFERENCE_TEXT, "de")
                save_clip("qwen_clone", vid, sid, text, a, sr, time.time() - t0, refs[vid])
        # Gegenprobe: Ziffern ohne Ausschreiben
        t0 = time.time()
        a, sr = m.speak(SENTENCES[3][2], refs["ERZAEHLER"], V.REFERENCE_TEXT, "de")
        save_clip("qwen_clone_ziffern", "ERZAEHLER", "04_zahlen_roh", SENTENCES[3][2], a, sr, time.time() - t0,
                  refs["ERZAEHLER"])
        report.step("Qwen Base fertig", peak_mb=V.peak_memory_mb())
        m.unload()
    except Exception as e:  # noqa: BLE001
        report.step("Qwen Base Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

# 3. VoxCPM2
if run("voxcpm_clone"):
    try:
        V.reset_peak_memory()
        m = V.VoxCPM()
        report.step("VoxCPM2 geladen", seconds=m.load_seconds, repo=m.repo)
        vrefs = {}
        for i, (vid, desc) in enumerate(VOICES.items()):
            t0 = time.time()
            a, sr = m.design(V.REFERENCE_TEXT, desc, 200 + i)
            vrefs[vid] = save_clip("voxcpm_clone", vid, "00_referenz", V.REFERENCE_TEXT, a, sr, time.time() - t0)
        for vid in VOICES:
            for sid, emo, text in SENTENCES:
                t0 = time.time()
                a, sr = m.speak(normalize_for_speech(text), vrefs[vid], V.REFERENCE_TEXT)
                save_clip("voxcpm_clone", vid, sid, text, a, sr, time.time() - t0, vrefs[vid])
        for vid in VOICES:
            for sid, emo, text in SENTENCES:
                if sid in EMOTIONAL:
                    try:
                        t0 = time.time()
                        a, sr = m.speak(normalize_for_speech(text), vrefs[vid], None, instruct=emo)
                        save_clip("voxcpm_emotion", vid, sid, text, a, sr, time.time() - t0, vrefs[vid])
                    except Exception as e:  # noqa: BLE001
                        report.step("VoxCPM2 Gefühl nicht möglich", error=repr(e))
                        break
        report.step("VoxCPM2 fertig", peak_mb=V.peak_memory_mb())
        m.unload()
    except Exception as e:  # noqa: BLE001
        report.step("VoxCPM2 Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

# 4. Chatterbox Multilingual v3
if run("chatterbox") and refs:
    try:
        V.reset_peak_memory()
        m = V.Chatterbox()
        report.step("Chatterbox geladen", seconds=m.load_seconds, repo=m.repo)
        for vid in VOICES:
            for sid, emo, text in SENTENCES:
                t0 = time.time()
                a, sr = m.speak(normalize_for_speech(text), refs[vid], "de", exaggeration=0.5)
                save_clip("chatterbox", vid, sid, text, a, sr, time.time() - t0, refs[vid])
                if sid in EMOTIONAL:
                    t0 = time.time()
                    a, sr = m.speak(normalize_for_speech(text), refs[vid], "de", exaggeration=0.85, cfg_weight=0.35)
                    save_clip("chatterbox_expressiv", vid, sid, text, a, sr, time.time() - t0, refs[vid])
        report.step("Chatterbox fertig", peak_mb=V.peak_memory_mb())
        m.unload()
    except Exception as e:  # noqa: BLE001
        report.step("Chatterbox Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

# 5. Piper (klassisch, Vergleich)
if run("piper"):
    try:
        import subprocess
        vdir = os.path.join(OUT, "piper-voices")
        os.makedirs(vdir, exist_ok=True)
        subprocess.run([sys.executable, "-m", "piper.download_voices", "--download-dir", vdir, "de_DE-thorsten-high"],
                       check=True, capture_output=True, text=True)
        from piper import PiperVoice
        t0 = time.time()
        voice = PiperVoice.load(os.path.join(vdir, "de_DE-thorsten-high.onnx"))
        report.step("Piper geladen", seconds=round(time.time() - t0, 1))
        import numpy as np
        for sid, emo, text in SENTENCES:
            t0 = time.time()
            chunks = list(voice.synthesize(normalize_for_speech(text)))
            a = np.concatenate([c.audio_float_array for c in chunks])
            save_clip("piper", "THORSTEN", sid, text, a, chunks[0].sample_rate, time.time() - t0)
    except Exception as e:  # noqa: BLE001
        report.step("Piper Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

# MARK: Auswertung
try:
    V.free_memory()
    L = Listener()
    report.step("Prüfwerkzeuge geladen")
    embs = {}
    for c in clips:
        try:
            c["hyp"] = L.transcribe(c["path"])
            c["wer"] = wer(c["text"], c["hyp"])
            e = L.embedding(c["path"])
            embs[c["path"]] = e
            if c.get("ref"):
                if c["ref"] not in embs:
                    embs[c["ref"]] = L.embedding(c["ref"])
                c["sim_ref"] = round(cos(e, embs[c["ref"]]), 3)
            c.update(f0_stats(c["path"]))
        except Exception as ex:  # noqa: BLE001
            c["eval_error"] = repr(ex)
        report.save()
    # Zusammenfassung je Verfahren
    import numpy as np
    summary = {}
    for eng in sorted({c["engine"] for c in clips}):
        cs = [c for c in clips if c["engine"] == eng and c["sentence"] != "00_referenz"]
        if not cs:
            continue
        s = {"clips": len(cs),
             "wer_mean": round(float(np.mean([c["wer"] for c in cs if c.get("wer") is not None])), 3) if any(c.get("wer") is not None for c in cs) else None,
             "rtf_mean": round(float(np.mean([c["rtf"] for c in cs])), 2),
             "sim_ref_mean": round(float(np.mean([c["sim_ref"] for c in cs if "sim_ref" in c])), 3) if any("sim_ref" in c for c in cs) else None}
        # Unterscheidbarkeit: mittlere Ähnlichkeit zwischen verschiedenen Rollen
        cent = {}
        for v in {c["voice"] for c in cs}:
            vs = [embs[c["path"]] for c in cs if c["voice"] == v and c["path"] in embs]
            if vs:
                m = np.mean(vs, axis=0)
                cent[v] = m / np.linalg.norm(m)
        keys = sorted(cent)
        cross = [cos(cent[a], cent[b]) for i, a in enumerate(keys) for b in keys[i + 1:]]
        s["sim_between_voices_mean"] = round(float(np.mean(cross)), 3) if cross else None
        # Gleichbleibende Stimme: Ähnlichkeit der Sätze einer Rolle untereinander
        within = []
        for v in keys:
            vs = [embs[c["path"]] for c in cs if c["voice"] == v and c["path"] in embs]
            within += [cos(a, b) for i, a in enumerate(vs) for b in vs[i + 1:]]
        s["sim_within_voice_mean"] = round(float(np.mean(within)), 3) if within else None
        # Ausdruck: Tonhöhenschwankung gefühlvoller vs. neutraler Sätze
        emo = [c["f0_std_semitones"] for c in cs if c["sentence"] in EMOTIONAL and c.get("f0_std_semitones")]
        neu = [c["f0_std_semitones"] for c in cs if c["sentence"] not in EMOTIONAL and c.get("f0_std_semitones")]
        s["f0_std_emotional"] = round(float(np.mean(emo)), 2) if emo else None
        s["f0_std_neutral"] = round(float(np.mean(neu)), 2) if neu else None
        summary[eng] = s
    report.data["summary"] = summary
    report.step("Auswertung fertig", summary=summary)
except Exception as e:  # noqa: BLE001
    report.step("Auswertung Fehler", error=repr(e), trace=traceback.format_exc()[-2500:])

# Hörproben als MP3 (für den Menschen, der hören kann)
for c in clips:
    try:
        c["mp3"] = os.path.relpath(to_mp3(c["path"]), OUT)
        os.remove(c["path"])
    except Exception:  # noqa: BLE001
        pass
report.save()
log("[Probe] TTS fertig")
