"""KI-Hörspiel – Stimmen: Sprachausgabe (TTS) mit lokalen Modellen über mlx-audio.

Grundidee für gleichbleibende Stimmen über eine ganze Produktion:
1. Eine Stimme wird aus einer Beschreibung entworfen („Voice Design“) – es entsteht ein kurzer Referenzsatz.
2. Alle Sätze der Figur werden danach aus diesem Referenzsatz geklont. So klingt die Figur in Kapitel 12 wie in
   Kapitel 1. Der Referenzsatz ist eine erzeugte, keine reale Stimme.
Echte Stimmen realer Personen werden nur mit dokumentierter Berechtigung als Referenz verwendet (siehe
hs_consent) – nie aus einer analysierten Referenzaufnahme.
"""

import gc
import math
import time

import numpy as np

import hs_audio as A
from hs_text import chunk_text, normalize_for_speech

QWEN_DESIGN = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
QWEN_BASE = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
VOXCPM = "mlx-community/VoxCPM2-8bit"
CHATTERBOX = "mlx-community/chatterbox-multilingual-v3"

REFERENCE_TEXT = ("Ich weiß nicht genau, was hier los ist. Aber eins ist sicher: Wir sollten vorsichtig sein "
                  "und ganz genau hinschauen.")

# Referenzsatz je Sprache: Die entworfene Stimme spricht ihn einmal, danach wird jede Zeile daraus geklont.
REFERENCE_TEXTS = {
    "de": REFERENCE_TEXT,
    "en": "I'm not quite sure what's going on here. But one thing is certain: we should be careful and look very closely.",
    "fr": "Je ne sais pas vraiment ce qui se passe ici. Mais une chose est sûre : nous devons être prudents et regarder de très près.",
    "es": "No sé muy bien qué está pasando aquí. Pero una cosa es segura: debemos tener cuidado y mirar con mucha atención.",
    "it": "Non so bene cosa stia succedendo qui. Ma una cosa è certa: dobbiamo stare attenti e guardare molto da vicino.",
}


def reference_text(language="de"):
    return REFERENCE_TEXTS.get(language, REFERENCE_TEXT)


def prepare_text(text, language="de"):
    """Text für die Sprachausgabe: deutsche Zahlen/Abkürzungen ausschreiben; andere Sprachen nur Leerraum glätten."""
    if language == "de":
        return normalize_for_speech(text)
    return " ".join((text or "").split())


LANG_QWEN = {"de": "german", "en": "english", "fr": "french", "es": "spanish", "it": "italian", "pt": "portuguese",
             "ru": "russian", "zh": "chinese", "ja": "japanese", "ko": "korean"}


def _np(audio):
    return np.array(audio, dtype=np.float32).reshape(-1)


def _collect(results):
    parts, sr = [], None
    for r in results:
        parts.append(_np(r.audio))
        sr = r.sample_rate
    if not parts:
        raise RuntimeError("Das Sprachmodell hat kein Audio geliefert")
    return np.concatenate(parts), sr


def free_memory():
    gc.collect()
    try:
        import mlx.core as mx
        (getattr(mx, "clear_cache", None) or mx.metal.clear_cache)()
    except Exception:  # noqa: BLE001
        pass


def peak_memory_mb():
    try:
        import mlx.core as mx
        f = getattr(mx, "get_peak_memory", None) or mx.metal.get_peak_memory
        return round(f() / 2**20, 1)
    except Exception:  # noqa: BLE001
        return None


def reset_peak_memory():
    try:
        import mlx.core as mx
        (getattr(mx, "reset_peak_memory", None) or mx.metal.reset_peak_memory)()
    except Exception:  # noqa: BLE001
        pass


def seed(n):
    try:
        import mlx.core as mx
        mx.random.seed(int(n))
    except Exception:  # noqa: BLE001
        pass
    np.random.seed(int(n) % 2**32)


class TTSModel:
    """Gemeinsame Hülle: Laden mit Zeitmessung, Entladen."""

    repo = None

    def __init__(self, repo=None, log=print):
        from mlx_audio.tts.utils import load_model
        self.repo = repo or self.repo
        self.log = log
        reset_peak_memory()
        t0 = time.time()
        self.model = load_model(self.repo)
        self.load_seconds = round(time.time() - t0, 1)
        self.sample_rate = getattr(self.model, "sample_rate", None)

    def unload(self):
        self.model = None
        free_memory()


class QwenDesign(TTSModel):
    """Qwen3-TTS VoiceDesign: Stimme aus einer Beschreibung (Apache-2.0)."""

    repo = QWEN_DESIGN

    def speak(self, text, instruct, language="de", seed_value=None):
        if seed_value is not None:
            seed(seed_value)
        return _collect(self.model.generate_voice_design(text=text, instruct=instruct,
                                                         language=LANG_QWEN.get(language, "auto")))


class QwenClone(TTSModel):
    """Qwen3-TTS Base: Stimme aus einem Referenzsatz klonen (Apache-2.0)."""

    repo = QWEN_BASE

    def speak(self, text, ref_audio, ref_text, language="de", seed_value=None):
        if seed_value is not None:
            seed(seed_value)
        return _collect(self.model.generate(text=text, ref_audio=ref_audio, ref_text=ref_text,
                                            lang_code=LANG_QWEN.get(language, "auto"), split_pattern="\n"))


class VoxCPM(TTSModel):
    """VoxCPM2 (2B, 48 kHz): Voice Design über Beschreibung, Klonen über Referenz (Apache-2.0)."""

    repo = VOXCPM

    def design(self, text, instruct, seed_value=None):
        if seed_value is not None:
            seed(seed_value)
        return _collect(self.model.generate(text=text, instruct=instruct))

    def speak(self, text, ref_audio, ref_text=None, instruct=None, seed_value=None):
        if seed_value is not None:
            seed(seed_value)
        kw = {"ref_audio": ref_audio}
        if ref_text:
            kw["ref_text"] = ref_text
        if instruct:
            kw["instruct"] = instruct
        return _collect(self.model.generate(text=text, **kw))


class Chatterbox(TTSModel):
    """Chatterbox Multilingual v3 (0,5B): Klonen mit einstellbarer Ausdrucksstärke (MIT, mit Wasserzeichen)."""

    repo = CHATTERBOX

    def speak(self, text, ref_audio, language="de", exaggeration=0.5, cfg_weight=0.5, seed_value=None):
        if seed_value is not None:
            seed(seed_value)
        return _collect(self.model.generate(text=text, ref_audio=ref_audio, lang_code=language,
                                            exaggeration=exaggeration, cfg_weight=cfg_weight))


# MARK: Stimmen einer Produktion

EMOTION_HINTS = {
    "flüster": "whispering softly", "leise": "speaking quietly", "aufgeregt": "excited and fast",
    "ängstlich": "frightened, trembling", "angst": "frightened, trembling", "wütend": "angry and loud",
    "schreit": "shouting", "ruft": "calling out loudly", "lacht": "laughing", "traurig": "sad",
    "erschrocken": "startled", "triumph": "triumphant", "spöttisch": "mocking", "nervös": "nervous",
    "streng": "stern", "erleichtert": "relieved", "keuchend": "out of breath",
}


def emotion_en(emotion):
    e = (emotion or "").lower()
    return next((v for k, v in EMOTION_HINTS.items() if k in e), "")


def measure_voice(audio, sr, text):
    """Tonhöhe (Median, Hz) und Silben je Sekunde einer gesprochenen Referenz."""
    import hs_analyze as H
    x16 = A.resample(A.trim_silence(audio, sr), sr, 16000)
    f0 = H.f0_yin(x16)
    f0 = f0[np.isfinite(f0)]
    syl = sum(H.syllables(w) for w in (text or "").split())
    dur = max(len(x16) / 16000, 0.1)
    return (round(float(np.median(f0)), 1) if f0.size > 20 else None), round(syl / dur, 2)


def voice_distance(f0, rate, target):
    """Abstand zum Ziel: Halbtöne Tonhöhe + halbes Gewicht für das Tempo (Silben/s)."""
    d = 0.0
    if target.get("f0_median_hz") and f0:
        d += abs(12 * math.log2(f0 / target["f0_median_hz"]))
    if target.get("syllables_per_second") and rate:
        d += 0.5 * abs(rate - target["syllables_per_second"])
    return d


# Tonlagen-Wörter von tief nach hoch (wie hs_analyze.describe_voice sie schreibt)
PITCH_PHRASES = ["a very deep, low voice", "a deep, low-pitched voice", "a fairly low voice", "a medium-pitched voice",
                 "a slightly high voice", "a high-pitched voice"]


def design_matching(model, text, instruct, language, target, candidates=3, seed_base=1):
    """Mehrere Kandidaten entwerfen und den mit der passendsten Tonhöhe/Tempo nehmen (allgemeine Merkmale, keine
    Nachbildung einer Person). Liegen alle Kandidaten mehr als 2 Halbtöne daneben, wird das Tonlagen-Wort der
    Beschreibung in die richtige Richtung verschoben und noch zweimal versucht (gemessen: das Stimm-Design-Modell
    trifft „medium pitch“ bei Frauen 3–6 Halbtöne zu hoch). Gibt (audio, sr, seed, f0, rate, liste) zurück."""
    best, tried = None, []

    def attempt(instr, seed):
        nonlocal best
        audio, sr = model.speak(text, instr, language, seed)
        f0, rate = measure_voice(audio, sr, text)
        d = voice_distance(f0, rate, target or {})
        tried.append({"seed": seed, "f0_median_hz": f0, "syllables_per_second": rate, "distance": round(d, 2),
                      "instruct": instr})
        if best is None or d < best[0]:
            best = (d, audio, sr, seed, f0, rate, instr)

    for k in range(max(1, candidates)):
        attempt(instruct, seed_base + k * 7919)
    want = (target or {}).get("f0_median_hz")
    phrase = next((p for p in PITCH_PHRASES if p in instruct), None)
    if want and best[4] and phrase and candidates > 1:
        err = 12 * math.log2(best[4] / want)
        if abs(err) > 2:
            i = PITCH_PHRASES.index(phrase)
            step = -2 if err > 4 else -1 if err > 0 else 2 if err < -4 else 1
            j = max(0, min(len(PITCH_PHRASES) - 1, i + step))
            if j != i:
                instr2 = instruct.replace(phrase, PITCH_PHRASES[j])
                for k in range(2):
                    attempt(instr2, seed_base + (candidates + k) * 7919)
    _, audio, sr, s, f0, rate, _ = best
    return audio, sr, s, f0, rate, tried


def design_instruct(figure):
    """Stimmbeschreibung für das Design-Modell (englisch, wie es die Modelle am besten verstehen)."""
    base = (figure.get("voice_en") or figure.get("stimme") or "").strip()
    if not base:
        g = "female" if str(figure.get("geschlecht", "")).lower().startswith(("w", "f")) else "male"
        base = f"A natural {g} voice, about {figure.get('alter', 40)} years old"
    return base.rstrip(".") + ". Speaks native German with clear, natural pronunciation."


class Casting:
    """Stimmen aller Figuren: Referenzsätze entwerfen und speichern, danach jede Zeile klonen."""

    def __init__(self, workdir, language="de", log=print):
        self.workdir = workdir
        self.language = language
        self.log = log
        self.voices = {}  # id → {"ref_audio", "ref_text", "instruct", "seconds"}

    def design_all(self, figures, seed_base=1984):
        import os
        model = QwenDesign(log=self.log)
        self.log(f"[Stimmen] Design-Modell geladen ({model.load_seconds} s)")
        for i, f in enumerate(figures):
            instruct = design_instruct(f)
            t0 = time.time()
            audio, sr = model.speak(REFERENCE_TEXT, instruct, self.language, seed_base + i)
            audio = A.trim_silence(audio, sr)
            path = os.path.join(self.workdir, "stimmen", f"{f['id']}.wav")
            A.write_wav(path, audio, sr)
            self.voices[f["id"]] = {"ref_audio": path, "ref_text": REFERENCE_TEXT, "instruct": instruct,
                                    "seconds": round(time.time() - t0, 1), "duration": round(len(audio) / sr, 2),
                                    "kind": "entworfen", "source": "Qwen3-TTS VoiceDesign"}
            self.log(f"[Stimmen] {f['id']}: entworfen in {self.voices[f['id']]['seconds']} s – {instruct}")
        model.unload()
        return self.voices

    def speak_lines(self, lines, out_dir, progress=None):
        """lines: [{"key", "speaker", "text", "emotion"}] → Dateien je Zeile. Liefert Messwerte je Zeile."""
        import os
        model = QwenClone(log=self.log)
        self.log(f"[Stimmen] Klon-Modell geladen ({model.load_seconds} s)")
        results = []
        for n, ln in enumerate(lines):
            v = self.voices.get(ln["speaker"]) or self.voices.get("ERZÄHLER")
            text = normalize_for_speech(ln["text"])
            if not text:
                continue
            t0 = time.time()
            parts = []
            sr = None
            for chunk in chunk_text(text, 220):
                a, sr = model.speak(chunk, v["ref_audio"], v["ref_text"], self.language)
                parts.append(A.trim_silence(a, sr))
                parts.append(np.zeros(int(0.12 * sr), dtype=np.float32))
            audio = np.concatenate(parts[:-1]) if parts else np.zeros(1, dtype=np.float32)
            path = os.path.join(out_dir, f"{ln['key']}.wav")
            A.write_wav(path, audio, sr)
            sec = time.time() - t0
            results.append({**ln, "spoken": text, "path": path, "duration": round(len(audio) / sr, 2),
                            "seconds": round(sec, 2), "sample_rate": sr})
            if progress:
                progress((n + 1) / len(lines), f"Zeile {n + 1} von {len(lines)}")
        model.unload()
        return results
