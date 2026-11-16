"""KI-Hörspiel – Produktion: Drehbuch → Stimmen → Geräusche → Musik → Mischung → Export.

Jeder Schritt schreibt seine Ergebnisse in den Arbeitsordner der Produktion und kann einzeln wiederholt werden
(fehlerhafte Szene/Zeile neu erzeugen, ohne den Rest anzufassen). Die Mischung ist eine Zeitleiste mit Spuren
(Erzähler, je Figur eine Spur, Musik, Geräusche, Atmo) – dieselbe Schnittliste nutzt später der Mehrspur-Editor.
"""

import hashlib
import json
import os
import shutil
import subprocess
import time

import numpy as np

import hs_audio as A

SR = A.SR

# Abstände zwischen Repliken (s) – Hörspieltempo, keine künstliche Verlängerung
GAP_SAME = 0.22
GAP_CHANGE = 0.38
GAP_NARRATOR = 0.55
GAP_SCENE = 0.9

MUSIC_STYLE = ("instrumental, 1980s German radio drama score, analog synthesizer, warm tape sound, "
               "no vocals")


def _key(text):
    return hashlib.sha1(text.encode()).hexdigest()[:12]


# MARK: Geräusche

class SFXGenerator:
    """Geräusche/Atmo mit Stable Audio 3 small (sfx) über mlx-audio. Ergebnisse landen in einer Bibliothek
    (wiederverwendbar, mit Beschreibung und Herkunft)."""

    repo = "mlx-community/stable-audio-3-small-sfx"

    def __init__(self, library_dir, log=print):
        from mlx_audio.music import load
        t0 = time.time()
        self.model = load(self.repo)
        self.load_seconds = round(time.time() - t0, 1)
        self.library = library_dir
        os.makedirs(library_dir, exist_ok=True)
        self.log = log

    def get(self, prompt, seconds, seed=7):
        name = f"{_key(prompt + str(int(seconds)))}.wav"
        path = os.path.join(self.library, name)
        if os.path.exists(path):
            return path, 0.0
        t0 = time.time()
        res = None
        for r in self.model.generate(text=prompt, duration=float(seconds), steps=8, seed=seed):
            res = r
        audio = np.array(res.audio, dtype=np.float32)
        if audio.ndim == 2 and audio.shape[0] > audio.shape[1]:
            audio = audio.T
        A.write_wav(path, audio, res.sample_rate)
        with open(path + ".json", "w") as f:
            json.dump({"prompt": prompt, "seconds": seconds, "seed": seed, "source": self.repo,
                       "license": "Stability AI Community License (Modell); erzeugtes Audio"}, f, ensure_ascii=False)
        return path, round(time.time() - t0, 1)

    def unload(self):
        self.model = None
        from hs_voice import free_memory
        free_memory()


# MARK: Musik über die KI-Musik (ACE-Step-Prozess der App)

class KIMusicClient:
    """Spricht mit Resources/KIEngine/engine.py (JSON-Zeilen über stdin/stdout) – dieselbe Engine wie „KI-Musik“."""

    def __init__(self, python, engine_py, ace_root, checkpoints, log=print):
        env = dict(os.environ, KI_ACE_ROOT=ace_root, KI_CHECKPOINTS=checkpoints)
        self.proc = subprocess.Popen([python, engine_py], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=open(os.path.join(os.path.dirname(checkpoints), "ki-musik-hoerspiel.log"), "a"),
                                     text=True, env=env, cwd=ace_root)
        self.log = log
        self.n = 0
        first = json.loads(self.proc.stdout.readline())
        if first.get("event") != "ready":
            raise RuntimeError(f"KI-Musik startet nicht: {first}")

    def request(self, cmd, **payload):
        self.n += 1
        rid = str(self.n)
        self.proc.stdin.write(json.dumps({"id": rid, "cmd": cmd, **payload}) + "\n")
        self.proc.stdin.flush()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("KI-Musik-Prozess beendet")
            msg = json.loads(line)
            if msg.get("id") != rid:
                continue
            if msg.get("event") == "result":
                return msg
            if msg.get("event") == "error":
                raise RuntimeError(msg.get("message"))

    def generate(self, caption, seconds, save_dir, seed=1984):
        # dieselben Parameter wie KIGenerationRequest.engineParams (Qualität „Schnell“, instrumental)
        r = self.request("generate", params={"task_type": "text2music", "caption": caption, "lyrics": "[Instrumental]",
                                             "instrumental": True, "vocal_language": "unknown",
                                             "duration": float(round(seconds)), "inference_steps": 8,
                                             "guidance_scale": 1.0, "thinking": False, "seed": seed},
                         seeds=[seed], save_dir=save_dir, format="flac", use_lm=False)
        return r["files"][0]["path"], r.get("seconds")

    def close(self):
        try:
            self.request("quit")
        except Exception:  # noqa: BLE001
            pass
        self.proc.wait(timeout=30)


def music_plan(story):
    """Musik-Hinweise der Szenen zu wenigen Stücken bündeln: Titel, Übergang, Spannung, Finale, Abspann."""
    cues = []
    scenes = story["scenes"]
    for si, s in enumerate(scenes):
        for ii, it in enumerate(s["items"]):
            if it["type"] != "music":
                continue
            de = it["de"].lower()
            if si == 0 and ii < 3 or "titel" in de or "intro" in de:
                kind = "titel"
            elif si == len(scenes) - 1 and (ii >= len(s["items"]) - 3 or "abspann" in de or "ende" in de):
                kind = "abspann"
            elif "final" in de or "höhepunkt" in de or "showdown" in de:
                kind = "finale"
            elif "spannung" in de or "bedroh" in de or "gefahr" in de:
                kind = "spannung"
            else:
                kind = "uebergang"
            cues.append({"scene": si, "item": ii, "kind": kind, "en": it["en"]})
    kinds = {c["kind"] for c in cues}
    # Titel und Abspann gibt es immer; Übergänge zwischen Szenen ohne eigene Musik ebenfalls
    if "titel" not in kinds:
        cues.insert(0, {"scene": 0, "item": -1, "kind": "titel", "en": ""})
    if "abspann" not in kinds:
        cues.append({"scene": len(scenes) - 1, "item": 10**6, "kind": "abspann", "en": ""})
    pieces = {}
    seconds = {"titel": 24, "abspann": 22, "uebergang": 12, "spannung": 20, "finale": 16}
    base = {"titel": "memorable main title theme, driving synth bass, catchy lead melody",
            "abspann": "closing theme, reprise of the main title, upbeat",
            "uebergang": "short scene transition sting, synth arpeggio",
            "spannung": "tense suspense underscore, pulsing low synth, mysterious",
            "finale": "dramatic climax music, urgent drums and synth brass"}
    for c in cues:
        if c["kind"] not in pieces:
            extra = c["en"] if c["en"] and len(c["en"]) < 160 else ""
            pieces[c["kind"]] = {"caption": f"{base[c['kind']]}, {extra + ', ' if extra else ''}{MUSIC_STYLE}",
                                 "seconds": seconds[c["kind"]]}
    return cues, pieces


# MARK: Zeitleiste

def speaking_figures(story):
    used = {it["speaker"] for s in story["scenes"] for it in s["items"] if it["type"] == "line"}
    return [f for f in story["concept"]["figuren"] if f["id"] in used]


def line_list(story):
    out = []
    for si, s in enumerate(story["scenes"]):
        for ii, it in enumerate(s["items"]):
            if it["type"] == "line":
                out.append({"key": f"s{si + 1:02d}_{ii:03d}", "scene": si, "item": ii, "speaker": it["speaker"],
                            "text": it["text"], "emotion": it.get("emotion", "")})
    return out


def pan_positions(figures):
    others = [f["id"] for f in figures if f["id"] != "ERZÄHLER"]
    spread = np.linspace(-0.35, 0.35, num=max(2, len(others)))
    pos = {fid: float(spread[i % len(spread)]) for i, fid in enumerate(others)}
    pos["ERZÄHLER"] = 0.0
    return pos


def assemble(story, voice_files, sfx_files, music_files, retro_amount=1.0, target_lufs=-16.0, log=print):
    """Zeitleiste bauen und abmischen. voice_files: key → wav, sfx_files: prompt → wav, music_files: kind → wav."""
    figures = speaking_figures(story)
    pos = pan_positions(figures)
    tl = A.Timeline(SR)
    cues, _ = music_plan(story)
    music_at = {(c["scene"], c["item"]): c["kind"] for c in cues}
    chapters = []
    t = 0.0

    def music_clip(kind):
        a, sr = A.load_audio(music_files[kind], sr=SR)
        return A.to_stereo(a)

    # Titelmusik vor allem anderen, falls im Drehbuch nicht platziert
    if (0, -1) in music_at and "titel" in music_files:
        m = music_clip("titel")
        tl.add("Musik", m, 0.0, gain_db=-3, fade_out=3.0, label="Titel")
        t = min(m.shape[1] / SR - 4.0, 8.0)

    for si, s in enumerate(story["scenes"]):
        scene_start = t
        chapters.append({"title": f"Szene {si + 1}: {s['title']}", "start": round(t, 2)})
        prev_speaker = None
        for ii, it in enumerate(s["items"]):
            kind = it["type"]
            if kind == "line":
                key = f"s{si + 1:02d}_{ii:03d}"
                path = voice_files.get(key)
                if not path:
                    continue
                a, _ = A.load_audio(path, sr=SR, mono=True)
                a = A.voice_eq(a, SR)
                room = "trocken" if it["speaker"] == "ERZÄHLER" else (s.get("room") or "zimmer")
                if "telefon" in (it.get("emotion") or "").lower():
                    room = "telefon"
                st = A.room(A.pan(a, pos.get(it["speaker"], 0.0)) if room != "telefon" else a, SR, room)
                if prev_speaker is not None:
                    t += GAP_NARRATOR if "ERZÄHLER" in (prev_speaker, it["speaker"]) and prev_speaker != it["speaker"] \
                        else GAP_SAME if prev_speaker == it["speaker"] else GAP_CHANGE
                track = "Erzähler" if it["speaker"] == "ERZÄHLER" else f"Sprecher {it['speaker']}"
                tl.add(track, st, t, label=f"{it['speaker']}: {it['text'][:60]}")
                t += st.shape[1] / SR
                prev_speaker = it["speaker"]
            elif kind == "sfx":
                path = sfx_files.get(it["en"])
                if not path:
                    continue
                a, _ = A.load_audio(path, sr=SR)
                a = A.trim_silence(A.to_stereo(a), SR, -50)
                a = A.fade(a, SR, 0.01, min(0.4, a.shape[1] / SR / 3))
                tl.add("Geräusche", a, t + 0.1, gain_db=-6, label=it["de"])
                t += min(a.shape[1] / SR * 0.7, 1.6) + 0.1
                prev_speaker = None
            elif kind == "music":
                mk = music_at.get((si, ii))
                if mk and mk in music_files:
                    m = music_clip(mk)
                    dur = m.shape[1] / SR
                    if mk == "titel":
                        tl.add("Musik", m, t, gain_db=-3, fade_out=3.0, label="Titel")
                        t += min(dur - 4.0, 8.0)
                    elif mk == "abspann":
                        tl.add("Musik", m, t + 0.3, gain_db=-3, fade_in=0.5, fade_out=4.0, label="Abspann")
                        t += dur
                    elif mk in ("spannung", "finale"):
                        # Unterlegt den Rest der Szene; Länge wird nach der Szene angepasst
                        tl.add("Musik", m, t, gain_db=-12, fade_in=1.5, fade_out=2.5, label=mk.title())
                        t += 0.4
                    else:
                        tl.add("Musik", m, t + 0.2, gain_db=-4, fade_in=0.05, fade_out=2.0, label="Übergang")
                        t += min(dur * 0.7, 6.0)
                prev_speaker = None
            elif kind == "pause":
                t += it.get("seconds", 1.5)
                prev_speaker = None
        # Atmo über die ganze Szene (Beschreibung aus dem Drehbuch oder dem Szenenplan)
        atmo_prompt = next((it["en"] for it in s["items"] if it["type"] == "atmo"), s.get("atmo_en"))
        if atmo_prompt and atmo_prompt in sfx_files:
            a, _ = A.load_audio(sfx_files[atmo_prompt], sr=SR)
            length = max(2.0, t - scene_start + 1.0)
            tl.add("Atmo", A.fit_length(a, SR, length), scene_start, gain_db=-17, fade_in=1.2, fade_out=1.5,
                   label=f"Atmo: {atmo_prompt[:50]}")
        # Übergang zur nächsten Szene: eigene Musik, falls das Drehbuch keine gesetzt hat
        if si < len(story["scenes"]) - 1:
            has_music_end = any(it["type"] == "music" for it in s["items"][-2:])
            if not has_music_end and "uebergang" in music_files:
                m = music_clip("uebergang")
                tl.add("Musik", m, t + 0.4, gain_db=-5, fade_in=0.05, fade_out=2.0, label="Übergang")
                t += min(m.shape[1] / SR * 0.7, 6.0)
            t += GAP_SCENE
    if (len(story["scenes"]) - 1, 10**6) in music_at and "abspann" in music_files:
        m = music_clip("abspann")
        tl.add("Musik", m, t + 0.5, gain_db=-3, fade_in=0.3, fade_out=4.0, label="Abspann")
    return mix(tl, retro_amount, target_lufs) + (chapters,)


def is_voice(track):
    return track == "Erzähler" or track.startswith("Sprecher")


def mix(tl, retro_amount=1.0, target_lufs=-16.0):
    """Abmischen: Spuren (mit Stummschalten/Solo/Pegel), Ducking von Musik/Atmo/Geräuschen unter Sprache,
    Bus-Kompressor, Retro-Klang, Lautheit. Liefert Master, Stems und Messwerte."""
    length = tl.duration + 0.5
    names = list(tl.tracks)
    stems = {n: tl.render_track(n, length) for n in names}
    n_samples = int(length * SR) + 1
    voice = np.zeros((2, n_samples), dtype=np.float32)
    for n in names:
        if is_voice(n) and tl.audible(n):
            voice += stems[n]
    duck_music = A.duck_gain(voice, SR, depth_db=-13, threshold_db=-42)
    duck_atmo = A.duck_gain(voice, SR, depth_db=-6, threshold_db=-42)
    duck_sfx = A.duck_gain(voice, SR, depth_db=-3, threshold_db=-42)
    for n in names:
        if n == "Musik":
            stems[n] = stems[n] * duck_music[None, :]
        elif n == "Atmo":
            stems[n] = stems[n] * duck_atmo[None, :]
        elif n == "Geräusche":
            stems[n] = stems[n] * duck_sfx[None, :]
    bus = np.zeros((2, n_samples), dtype=np.float32)
    for n in names:
        if tl.audible(n):
            bus += stems[n]
    bus = A.compressor(bus, SR, threshold_db=-22, ratio=2.0, attack=0.015, release=0.25, makeup_db=0)
    if retro_amount > 0:
        bus = A.retro(bus, SR, retro_amount)
    master = A.normalize_lufs(bus, SR, target_lufs, -1.0)
    # Sprachverständlichkeit: Abstand Sprache ↔ Hintergrund während gesprochen wird
    bg = np.zeros_like(voice)
    for n in names:
        if n in ("Musik", "Atmo", "Geräusche") and tl.audible(n):
            bg += stems[n]
    env = A.envelope(voice, SR, 0.01, 0.2)
    speaking = env > A.gain(-40)
    ratio = None
    if speaking.any():
        ratio = round(A.rms_db(A.to_mono(voice)[speaking]) - A.rms_db(A.to_mono(bg)[speaking]), 1)
    return master, stems, tl, {"speech_to_background_db": ratio, "duration_s": round(master.shape[1] / SR, 1),
                               "loudness_lufs": A.loudness_lufs(master, SR), "peak_dbfs": round(A.peak_db(master), 2)}


# MARK: Export

def export_mp3(wav_path, mp3_path, chapters, meta, duration, bitrate="192k"):
    """MP3 mit Kapitelmarken (ID3 CHAP) über ffmpeg – im Prüfstand. Die App exportiert über ihren eigenen Exporter."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    meta_path = mp3_path + ".ffmeta"
    with open(meta_path, "w") as f:
        f.write(";FFMETADATA1\n")
        for k, v in meta.items():
            f.write(f"{k}={str(v).replace('=', ' ').replace(chr(10), ' ')}\n")
        end_total = int(duration * 1000)
        for i, c in enumerate(chapters):
            start = int(c["start"] * 1000)
            end = int(chapters[i + 1]["start"] * 1000) if i + 1 < len(chapters) else end_total
            f.write(f"[CHAPTER]\nTIMEBASE=1/1000\nSTART={start}\n")
            if end:
                f.write(f"END={end}\n")
            f.write(f"title={c['title']}\n")
    subprocess.run([ffmpeg, "-v", "error", "-y", "-i", wav_path, "-i", meta_path, "-map_metadata", "1",
                    "-map_chapters", "1", "-codec:a", "libmp3lame", "-b:a", bitrate, "-id3v2_version", "3", mp3_path],
                   check=True)
    os.remove(meta_path)
    return mp3_path
