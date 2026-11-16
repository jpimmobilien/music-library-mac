"""KI-Hörspiel – Audiowerkzeuge: Laden, Lautheit (ITU-R BS.1770), Filter, Hall, Kompressor, Ducking, Retro-Klang
und eine einfache Spuren-Zeitleiste zum Abmischen. Nur numpy/scipy (plus soundfile oder ffmpeg zum Laden).

Alle Signale sind float32, Mono als (n,) und Stereo als (2, n).
"""

import math
import os
import shutil
import subprocess
import wave

import numpy as np
from scipy import signal

SR = 48000


# MARK: Laden und Schreiben

def load_audio(path, sr=None, mono=False):
    """Datei laden (WAV/FLAC/MP3/OGG über soundfile, sonst ffmpeg). Liefert (Signal, Abtastrate)."""
    data, file_sr = None, None
    try:
        import soundfile as sf
        data, file_sr = sf.read(path, dtype="float32", always_2d=True)
        data = data.T  # (Kanäle, n)
    except Exception:  # noqa: BLE001 – Formate, die libsndfile nicht kennt (M4A …)
        data = None
    if data is None:
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            raise RuntimeError(f"Kann {os.path.basename(path)} nicht lesen (kein passender Decoder)")
        target = sr or SR
        raw = subprocess.run([ffmpeg, "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(target), "-"],
                             capture_output=True, check=True).stdout
        data = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).T.copy()
        file_sr = target
    if sr and file_sr != sr:
        data = resample(data, file_sr, sr)
        file_sr = sr
    if mono:
        data = data.mean(axis=0)
    elif data.shape[0] == 1:
        data = data[0]
    return data.astype(np.float32), file_sr


def write_wav(path, audio, sr, bits=24):
    """WAV schreiben (24 bit, ohne Zusatzpakete). Clipping wird hart begrenzt."""
    a = np.asarray(audio, dtype=np.float64)
    if a.ndim == 1:
        a = a[None, :]
    a = np.clip(a, -1.0, 1.0).T  # (n, Kanäle)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(a.shape[1])
        w.setframerate(int(sr))
        if bits == 16:
            w.setsampwidth(2)
            w.writeframes((a * 32767).astype("<i2").tobytes())
        else:
            w.setsampwidth(3)
            ints = (a * 8388607).astype("<i4").reshape(-1)
            b = ints.view(np.uint8).reshape(-1, 4)[:, :3]
            w.writeframes(b.tobytes())
    return path


def resample(x, sr_from, sr_to):
    if sr_from == sr_to:
        return x
    g = math.gcd(int(sr_from), int(sr_to))
    return signal.resample_poly(x, int(sr_to) // g, int(sr_from) // g, axis=-1).astype(np.float32)


def to_stereo(x):
    x = np.asarray(x, dtype=np.float32)
    return np.stack([x, x]) if x.ndim == 1 else x


def to_mono(x):
    x = np.asarray(x, dtype=np.float32)
    return x if x.ndim == 1 else x.mean(axis=0)


def db(g):
    return 20 * math.log10(max(float(g), 1e-12))


def gain(db_value):
    return 10 ** (db_value / 20)


def rms_db(x):
    x = np.asarray(x, dtype=np.float64)
    return db(math.sqrt(float(np.mean(x ** 2))) if x.size else 0)


def peak_db(x):
    return db(float(np.max(np.abs(x))) if np.size(x) else 0)


# MARK: Lautheit nach ITU-R BS.1770-4 / EBU R128

def _k_weighting(sr):
    # Vorfilter (Kopfeffekt) + RLB-Hochpass, für beliebige Abtastraten hergeleitet wie in libebur128
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / sr)
    Vh = 10 ** (G / 20)
    Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = np.array([(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0])
    a1 = np.array([1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0])
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / sr)
    d = 1 + K / Q + K * K
    b2 = np.array([1.0, -2.0, 1.0])
    a2 = np.array([1.0, 2 * (K * K - 1) / d, (1 - K / Q + K * K) / d])
    return (b1, a1), (b2, a2)


def loudness_lufs(x, sr):
    """Integrierte Lautheit in LUFS (Gating −70 LUFS absolut, −10 LU relativ)."""
    x = to_stereo(x).astype(np.float64)
    (b1, a1), (b2, a2) = _k_weighting(sr)
    y = signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=-1), axis=-1)
    block, step = int(0.4 * sr), int(0.1 * sr)
    if y.shape[-1] < block:
        return -70.0
    n = 1 + (y.shape[-1] - block) // step
    idx = np.arange(block)[None, :] + step * np.arange(n)[:, None]
    z = np.mean(y[:, idx] ** 2, axis=-1).sum(axis=0)  # Summe über Kanäle (L, R Gewicht 1)
    with np.errstate(divide="ignore"):
        lk = -0.691 + 10 * np.log10(np.maximum(z, 1e-20))
    z = z[lk > -70]
    if z.size == 0:
        return -70.0
    rel = -0.691 + 10 * math.log10(float(np.mean(z))) - 10
    z2 = z[(-0.691 + 10 * np.log10(z)) > rel]
    return round(-0.691 + 10 * math.log10(float(np.mean(z2 if z2.size else z))), 2)


def normalize_lufs(x, sr, target=-16.0, ceiling_db=-1.0):
    """Auf Ziel-Lautheit bringen, Spitzen weich begrenzen."""
    current = loudness_lufs(x, sr)
    y = x * gain(target - current)
    return limiter(y, sr, ceiling_db)


def limiter(x, sr, ceiling_db=-1.0, release=0.08):
    """Einfacher Spitzenbegrenzer mit Vorschau (5 ms) und weicher Rückstellung."""
    ceiling = gain(ceiling_db)
    a = to_stereo(x) if np.ndim(x) == 1 else x
    from scipy.ndimage import maximum_filter1d
    look = max(1, int(0.005 * sr))
    peak = maximum_filter1d(np.max(np.abs(a), axis=0), size=2 * look + 1)
    g = np.minimum(1.0, ceiling / np.maximum(peak, 1e-9))
    # Rückstellung glätten (nur Anstieg verzögern)
    coef = math.exp(-1 / (release * sr))
    g = signal.lfilter([1 - coef], [1, -coef], g)
    g = np.minimum(g, ceiling / np.maximum(peak, 1e-9))
    y = a * g[None, :]
    y = np.clip(y, -ceiling, ceiling)
    return (y[0] if np.ndim(x) == 1 else y).astype(np.float32)


# MARK: Filter

def _sos(kind, freq, sr, order=2):
    nyq = sr / 2
    if kind == "bandpass":
        lo, hi = freq
        return signal.butter(order, [lo / nyq, min(hi / nyq, 0.99)], btype="bandpass", output="sos")
    return signal.butter(order, min(freq / nyq, 0.99), btype=kind, output="sos")


def highpass(x, sr, freq, order=2):
    return signal.sosfilt(_sos("highpass", freq, sr, order), x, axis=-1).astype(np.float32)


def lowpass(x, sr, freq, order=2):
    return signal.sosfilt(_sos("lowpass", freq, sr, order), x, axis=-1).astype(np.float32)


def bandpass(x, sr, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", (lo, hi), sr, order), x, axis=-1).astype(np.float32)


def peaking(x, sr, freq, gain_db, q=1.0):
    """Glockenfilter (RBJ)."""
    A = 10 ** (gain_db / 40)
    w0 = 2 * math.pi * freq / sr
    alpha = math.sin(w0) / (2 * q)
    b = np.array([1 + alpha * A, -2 * math.cos(w0), 1 - alpha * A])
    a = np.array([1 + alpha / A, -2 * math.cos(w0), 1 - alpha / A])
    return signal.lfilter(b / a[0], a / a[0], x, axis=-1).astype(np.float32)


def voice_eq(x, sr):
    """Sprach-EQ wie im Studio: Rumpeln weg, etwas Präsenz, Härte bei 3 kHz nicht anheben."""
    y = highpass(x, sr, 80, order=2)
    y = peaking(y, sr, 250, -1.5, 0.9)   # Dröhnen
    y = peaking(y, sr, 4500, 1.5, 0.8)   # Präsenz
    return y


# MARK: Dynamik

def envelope(x, sr, attack=0.005, release=0.12):
    """Hüllkurve (Spitzenfolger) mit getrennten Zeiten für Anstieg und Abfall."""
    v = np.abs(to_mono(x)).astype(np.float64)
    # Für lange Signale: zuerst auf 1 kHz verdichten, dann Folger in reiner Python-Schleife (schnell genug)
    hop = max(1, sr // 1000)
    n = len(v) // hop
    if n == 0:
        return np.zeros(len(v))
    frames = v[: n * hop].reshape(n, hop).max(axis=1)
    fr = sr / hop
    ca, cr = math.exp(-1 / (attack * fr)), math.exp(-1 / (release * fr))
    env = np.empty(n)
    e = 0.0
    for i, s in enumerate(frames):
        c = ca if s > e else cr
        e = c * e + (1 - c) * s
        env[i] = e
    out = np.repeat(env, hop)
    if len(out) < len(v):
        out = np.concatenate([out, np.full(len(v) - len(out), env[-1])])
    return out


def compressor(x, sr, threshold_db=-20.0, ratio=3.0, attack=0.01, release=0.15, makeup_db=0.0, knee_db=6.0):
    env = envelope(x, sr, attack, release)
    with np.errstate(divide="ignore"):
        lvl = 20 * np.log10(np.maximum(env, 1e-9))
    over = lvl - threshold_db
    # weiches Knie
    gr = np.where(over <= -knee_db / 2, 0.0,
                  np.where(over >= knee_db / 2, over * (1 - 1 / ratio),
                           (1 - 1 / ratio) * (over + knee_db / 2) ** 2 / (2 * knee_db)))
    g = 10 ** ((makeup_db - gr) / 20)
    return (x * (g[None, :] if np.ndim(x) == 2 else g)).astype(np.float32)


def duck_gain(key, sr, depth_db=-12.0, threshold_db=-40.0, attack=0.08, release=0.6):
    """Absenkkurve für Musik/Atmo unter Sprache (Sidechain): 1.0 ohne Sprache, gain(depth_db) mit Sprache."""
    env = envelope(key, sr, attack, release)
    with np.errstate(divide="ignore"):
        lvl = 20 * np.log10(np.maximum(env, 1e-9))
    amount = np.clip((lvl - threshold_db) / 10.0, 0.0, 1.0)  # weicher Übergang über 10 dB
    return (1.0 - amount * (1.0 - gain(depth_db))).astype(np.float32)


# MARK: Raum und Klangfarbe

ROOMS = {
    # Nachhallzeit (s), Anteil Hall, Erstreflexionen (ms)
    "trocken": (0.12, 0.05, (3, 7)),
    "zimmer": (0.35, 0.12, (5, 11, 17)),
    "küche": (0.45, 0.15, (4, 9, 15)),
    "auto": (0.12, 0.08, (2, 4)),
    "büro": (0.5, 0.14, (6, 13, 21)),
    "keller": (0.9, 0.2, (7, 15, 26)),
    "treppenhaus": (1.4, 0.24, (9, 19, 33)),
    "halle": (1.8, 0.26, (14, 29, 47)),
    "bahnhofshalle": (2.4, 0.28, (18, 37, 61)),
    "kirche": (3.0, 0.32, (21, 43, 70)),
    "draußen": (0.25, 0.04, (31,)),
    "wald": (0.5, 0.07, (23, 41)),
    "telefon": (0.0, 0.0, ()),
}


def impulse_response(sr, rt60, early=(), seed=7):
    rng = np.random.default_rng(seed)
    n = max(int(sr * max(rt60, 0.05) * 1.2), 32)
    t = np.arange(n) / sr
    decay = np.exp(-6.91 * t / max(rt60, 0.05))
    ir = np.stack([rng.standard_normal(n), rng.standard_normal(n)]) * decay
    ir = lowpass(ir, sr, 7000 if rt60 > 1 else 9000, order=1)  # Luftdämpfung
    ir[:, : int(0.002 * sr)] *= np.linspace(0, 1, int(0.002 * sr))
    for ms in early:
        k = int(ms * sr / 1000)
        if k < n:
            ir[0, k] += 0.5 * (0.8 ** (ms / 10))
            ir[1, min(n - 1, k + int(0.0007 * sr))] += 0.5 * (0.8 ** (ms / 10))
    return (ir / np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))).astype(np.float32)


def room(x, sr, name):
    """Sprache in einen Raum setzen. Unbekannte Räume → trocken."""
    key = (name or "trocken").lower()
    key = next((k for k in ROOMS if k in key), "trocken")
    if key == "telefon":
        y = bandpass(to_mono(x), sr, 320, 3400, order=3)
        y = np.tanh(y * 2.2) / 2.2
        return to_stereo(y)
    rt60, wet, early = ROOMS[key]
    dry = to_stereo(x)
    ir = impulse_response(sr, rt60, early)
    tail = np.stack([signal.fftconvolve(dry[0], ir[0]), signal.fftconvolve(dry[1], ir[1])])[:, : dry.shape[1]]
    return ((1 - wet) * dry + wet * tail * 0.7).astype(np.float32)


def pan(mono, position):
    """Konstante Leistung: −1 links … +1 rechts."""
    p = (float(position) + 1) * math.pi / 4
    m = to_mono(mono)
    return np.stack([m * math.cos(p), m * math.sin(p)]).astype(np.float32)


def fade(x, sr, fade_in=0.0, fade_out=0.0):
    y = np.array(x, dtype=np.float32, copy=True)
    n = y.shape[-1]
    fi, fo = min(int(fade_in * sr), n), min(int(fade_out * sr), n)
    if fi:
        y[..., :fi] *= np.sin(np.linspace(0, math.pi / 2, fi)) ** 2
    if fo:
        y[..., n - fo:] *= np.cos(np.linspace(0, math.pi / 2, fo)) ** 2
    return y


def fit_length(x, sr, seconds, crossfade=1.5):
    """Atmo/Musik auf eine Länge bringen: kürzen oder mit Überblendung wiederholen (keine harten Schleifen)."""
    target = int(seconds * sr)
    x = to_stereo(x)
    if x.shape[1] >= target:
        return fade(x[:, :target], sr, 0.0, min(crossfade, seconds / 4))
    cf = min(int(crossfade * sr), x.shape[1] // 3)
    out = x.copy()
    while out.shape[1] < target:
        seg = x
        ramp = np.linspace(0, 1, cf)
        head = out[:, -cf:] * np.cos(ramp * math.pi / 2) ** 2 + seg[:, :cf] * np.sin(ramp * math.pi / 2) ** 2
        out = np.concatenate([out[:, :-cf], head, seg[:, cf:]], axis=1)
    return fade(out[:, :target], sr, 0.0, min(crossfade, seconds / 4))


def trim_silence(x, sr, threshold_db=-45.0, pad=0.04):
    """Stille am Anfang/Ende entfernen (Sprachausgabe beginnt oft mit Luft)."""
    m = np.abs(to_mono(x))
    above = np.where(m > gain(threshold_db))[0]
    if above.size == 0:
        return x
    a = max(0, above[0] - int(pad * sr))
    b = min(len(m), above[-1] + int(pad * sr))
    return x[..., a:b]


def retro(x, sr, amount=1.0, seed=3):
    """Klang einer Hörspielkassette der 1980er (allgemeine Merkmale, keine Kopie einer Aufnahme):
    begrenzte Bandbreite, leichte Bandsättigung, minimales Rauschen und Gleichlaufschwankung, schmaleres Stereobild."""
    if amount <= 0:
        return x
    y = to_stereo(x).astype(np.float64)
    y = highpass(y, sr, 55, order=2)
    y = lowpass(y, sr, 15500 - 3500 * amount, order=2)
    y = peaking(y, sr, 180, 1.0 * amount, 0.8)     # etwas „Wärme“
    drive = 1 + 0.6 * amount
    y = np.tanh(y * drive) / np.tanh(drive)          # Bandsättigung
    # Gleichlauf (Wow 0,55 Hz ±0,25 ms, Flutter 6,5 Hz ±0,03 ms)
    n = y.shape[1]
    t = np.arange(n) / sr
    delay = (0.00025 * np.sin(2 * math.pi * 0.55 * t) + 0.00003 * np.sin(2 * math.pi * 6.5 * t)) * amount * sr
    idx = np.clip(np.arange(n) - delay - 0.0004 * sr, 0, n - 1)
    lo = np.floor(idx).astype(int)
    frac = idx - lo
    hi = np.minimum(lo + 1, n - 1)
    y = y[:, lo] * (1 - frac) + y[:, hi] * frac
    # schmaleres Stereobild
    mid, side = (y[0] + y[1]) / 2, (y[0] - y[1]) / 2 * (1 - 0.4 * amount)
    y = np.stack([mid + side, mid - side])
    # Bandrauschen (rosa, sehr leise)
    rng = np.random.default_rng(seed)
    hiss = signal.lfilter([0.049922035, -0.095993537, 0.050612699, -0.004408786],
                          [1, -2.494956002, 2.017265875, -0.522189400], rng.standard_normal((2, n)), axis=-1)
    hiss = highpass(hiss, sr, 2500, order=1)
    hiss *= gain(-64 + 4 * amount) / max(float(np.sqrt(np.mean(hiss ** 2))), 1e-9)
    return (y + hiss).astype(np.float32)


# MARK: Zeitleiste

class Timeline:
    """Spuren mit Clips (Start in Sekunden) – bearbeitbar (verschieben, schneiden, blenden, Lautstärke) und speicherbar.
    Ein Clip verweist auf sein Quellsignal (bereits mit Raumklang/Panorama); Blenden und Pegel werden erst beim
    Abmischen angewendet, damit jede Änderung verlustfrei bleibt."""

    def __init__(self, sr=SR):
        self.sr = sr
        self.tracks = {}       # Name → [Clip]
        self.track_settings = {}  # Name → {"gain_db", "mute", "solo"}
        self._n = 0

    def add(self, track, audio, start, gain_db=0.0, pan_pos=0.0, fade_in=0.0, fade_out=0.0, label="", clip_id=None,
            offset=0.0, duration=None, file=None):
        a = np.asarray(audio, dtype=np.float32)
        a = pan(a, pan_pos) if a.ndim == 1 else a
        self._n += 1
        full = a.shape[1] / self.sr
        clip = {"id": clip_id or f"c{self._n:04d}", "track": track, "source": a, "start": max(0.0, float(start)),
                "offset": max(0.0, float(offset)), "duration": float(duration if duration is not None else full - offset),
                "gain_db": float(gain_db), "fade_in": float(fade_in), "fade_out": float(fade_out), "label": label, "file": file}
        clip["duration"] = max(0.0, min(clip["duration"], full - clip["offset"]))
        self.tracks.setdefault(track, []).append(clip)
        self.track_settings.setdefault(track, {"gain_db": 0.0, "mute": False, "solo": False})
        return clip

    @property
    def duration(self):
        ends = [c["start"] + c["duration"] for clips in self.tracks.values() for c in clips]
        return max(ends) if ends else 0.0

    def clip_audio(self, c):
        a = c["source"][:, int(c["offset"] * self.sr): int((c["offset"] + c["duration"]) * self.sr)]
        return fade(a, self.sr, c["fade_in"], c["fade_out"]) * gain(c["gain_db"])

    def render_track(self, track, length=None):
        n = int((length or self.duration) * self.sr) + 1
        out = np.zeros((2, n), dtype=np.float32)
        for c in self.tracks.get(track, []):
            s = int(c["start"] * self.sr)
            a = self.clip_audio(c)[:, : max(0, n - s)]
            out[:, s: s + a.shape[1]] += a
        return out * gain(self.track_settings.get(track, {}).get("gain_db", 0.0))

    def audible(self, track):
        """Spur hörbar? (Stummschalten, Solo)"""
        st = self.track_settings.get(track, {})
        if st.get("mute"):
            return False
        solos = [t for t, v in self.track_settings.items() if v.get("solo")]
        return not solos or track in solos

    def clips(self):
        """Schnittliste (für Kapitelmarken, Prüfungen und den Mehrspur-Editor)."""
        return [{"id": c["id"], "track": t, "start": round(c["start"], 3), "duration": round(c["duration"], 3), "label": c["label"],
                 "gain_db": c["gain_db"]} for t, clips in self.tracks.items() for c in clips]

    def save(self, folder):
        """Clips als WAV und die bearbeitbare Zeitleiste als Dict (→ JSON)."""
        os.makedirs(os.path.join(folder, "clips"), exist_ok=True)
        out = {"sample_rate": self.sr, "tracks": [], "clips": []}
        for t, clips in self.tracks.items():
            out["tracks"].append({"name": t, **self.track_settings.get(t, {"gain_db": 0.0, "mute": False, "solo": False})})
            for c in clips:
                if not c.get("file"):
                    c["file"] = os.path.join("clips", f"{c['id']}.wav")
                    write_wav(os.path.join(folder, c["file"]), c["source"], self.sr, bits=16)
                out["clips"].append({k: (round(v, 4) if isinstance(v, float) else v) for k, v in c.items() if k != "source"})
        return out

    @classmethod
    def load(cls, data, folder, sr=SR):
        tl = cls(sr)
        cache = {}
        for t in data.get("tracks", []):
            tl.track_settings[t["name"]] = {"gain_db": float(t.get("gain_db", 0)), "mute": bool(t.get("mute")), "solo": bool(t.get("solo"))}
            tl.tracks.setdefault(t["name"], [])
        for c in data.get("clips", []):
            path = c["file"] if os.path.isabs(c["file"]) else os.path.join(folder, c["file"])
            if path not in cache:
                cache[path] = to_stereo(load_audio(path, sr=sr)[0])
            tl.add(c["track"], cache[path], c["start"], c.get("gain_db", 0.0), 0.0, c.get("fade_in", 0.0), c.get("fade_out", 0.0),
                   c.get("label", ""), clip_id=c.get("id"), offset=c.get("offset", 0.0), duration=c.get("duration"), file=c["file"])
        return tl
