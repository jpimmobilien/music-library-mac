"""Gemeinsame Hilfen der Hörspiel-Proben: Umgebung, Zeit/Speicher, Spracherkennung (WER), Stimmähnlichkeit."""

import json
import os
import platform
import re
import resource
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.abspath(os.path.join(HERE, "..", "..", "Resources", "HoerspielEngine"))
sys.path.insert(0, ENGINE)

import numpy as np  # noqa: E402

import hs_audio as A  # noqa: E402
from hs_text import normalize_for_speech  # noqa: E402


def log(*a):
    print(*a, flush=True)


def environment():
    env = {"python": sys.version.split()[0], "machine": platform.machine(), "system": platform.system()}
    try:
        if sys.platform == "darwin":
            env["macos"] = platform.mac_ver()[0]
            env["ram_gb"] = round(int(subprocess.check_output(["sysctl", "-n", "hw.memsize"])) / 2**30, 1)
            env["cpu"] = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"]).decode().strip()
            env["cores"] = int(subprocess.check_output(["sysctl", "-n", "hw.ncpu"]))
        else:
            env["cores"] = os.cpu_count()
            with open("/proc/meminfo") as f:
                env["ram_gb"] = round(int(f.readline().split()[1]) / 2**20, 1)
    except Exception as e:  # noqa: BLE001
        env["error"] = repr(e)
    for mod in ("mlx", "mlx_audio", "mlx_lm", "mlx_whisper"):
        try:
            m = __import__(mod)
            env[mod] = getattr(m, "__version__", None) or getattr(getattr(m, "version", None), "__version__", "?")
        except Exception:  # noqa: BLE001
            pass
    try:
        import mlx.core as mx
        env["mlx_device"] = str(mx.default_device())
    except Exception:  # noqa: BLE001
        pass
    return env


def peak_rss_mb():
    r = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return round(r / 2**20 if sys.platform == "darwin" else r / 1024, 1)


class Report:
    def __init__(self, path):
        self.path = path
        self.data = {"environment": environment(), "steps": []}
        self.save()

    def step(self, name, **kw):
        entry = {"name": name, "time": time.strftime("%H:%M:%S"), **kw}
        self.data["steps"].append(entry)
        self.save()
        log(f"[Probe] {name}: " + json.dumps({k: v for k, v in kw.items() if not isinstance(v, (list, dict))},
                                             ensure_ascii=False, default=str))
        return entry

    def save(self):
        with open(self.path, "w") as f:
            json.dump(self.data, f, indent=2, ensure_ascii=False, default=str)


# MARK: Wortfehlerrate

def _words(text):
    t = normalize_for_speech(text or "").lower()
    t = re.sub(r"[^a-zäöüß0-9 ]+", " ", t.replace("-", " "))
    return t.split()


def wer(ref, hyp):
    r, h = _words(ref), _words(hyp)
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


class Listener:
    """Whisper (mlx-whisper) und ECAPA (mlx-audio) – objektive Ersatzprüfungen, kein Hörtest."""

    def __init__(self, whisper_repo="mlx-community/whisper-large-v3-turbo"):
        from mlx_audio.codec.models.ecapa_tdnn import EcapaSpeakerEmbeddingExtractor
        self.whisper_repo = whisper_repo
        self.ecapa = EcapaSpeakerEmbeddingExtractor.from_pretrained("aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX")

    def transcribe(self, path, language="de"):
        import mlx_whisper
        x, _ = A.load_audio(path, sr=16000, mono=True)
        r = mlx_whisper.transcribe(x, path_or_hf_repo=self.whisper_repo, language=language,
                                   condition_on_previous_text=False)
        return r.get("text", "").strip()

    def embedding(self, path_or_audio, sr=None):
        if isinstance(path_or_audio, str):
            x, _ = A.load_audio(path_or_audio, sr=16000, mono=True)
        else:
            x = A.resample(A.to_mono(path_or_audio), sr, 16000)
        x = A.trim_silence(x, 16000, -45)
        return np.array(self.ecapa.encode(x.astype(np.float32)), dtype=np.float32)


def cos(a, b):
    return float(np.dot(a, b) / max(np.linalg.norm(a) * np.linalg.norm(b), 1e-9))


def f0_stats(path):
    from hs_analyze import f0_yin, semitones
    x, _ = A.load_audio(path, sr=16000, mono=True)
    f0 = f0_yin(x)
    f0 = f0[np.isfinite(f0)]
    if f0.size < 10:
        return {"f0_median_hz": None, "f0_std_semitones": None}
    return {"f0_median_hz": round(float(np.median(f0)), 1), "f0_std_semitones": round(float(np.std(semitones(f0))), 2)}


def to_mp3(path, bitrate="128k"):
    import shutil
    if not shutil.which("ffmpeg"):
        return path
    out = os.path.splitext(path)[0] + ".mp3"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-codec:a", "libmp3lame", "-b:a", bitrate, out], check=True)
    return out
