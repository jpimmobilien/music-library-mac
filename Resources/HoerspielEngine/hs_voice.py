"""KI-Hörspiel – Stimmen: Sprachausgabe (TTS) mit lokalen Modellen über mlx-audio.

Grundidee für gleichbleibende Stimmen über eine ganze Produktion:
1. Eine Stimme wird aus einer Beschreibung entworfen („Voice Design“) – es entsteht ein kurzer Referenzsatz.
2. Alle Sätze der Figur werden danach aus diesem Referenzsatz geklont. So klingt die Figur in Kapitel 12 wie in
   Kapitel 1. Der Referenzsatz ist eine erzeugte, keine reale Stimme.
Echte Stimmen realer Personen werden nur mit dokumentierter Berechtigung als Referenz verwendet (siehe
hs_consent) – nie aus einer analysierten Referenzaufnahme.
"""

import gc
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
