"""KI-Hörspiel – Referenzanalyse: Was macht eine (alte) Hörspielproduktion aus?

Erfasst nur allgemeine, beschreibende Merkmale – keine Stimmabdrücke realer Personen werden gespeichert:
- Sprecher: Anzahl (Sprechererkennung über Stimmmerkmale + Gruppierung), Redeanteile, Rollen-Vermutung
- je Sprecher: Tonhöhe, Tonumfang, Tempo, Helligkeit, Ausdrucksstärke, Pausen → Stimmbeschreibung
- Dialog: Wechseltempo, Pausen zwischen Repliken, Länge der Repliken, Erzähleranteil
- Aufnahme: Lautheit, Bandbreite, Grundrauschen, Brumm, Nachhall (geschätzt), Stereobreite
- Musik/Geräusche: Anteile ohne Sprache, Musikbrücken (Anzahl, Länge)

Modelle: Silero VAD und SpeechBrain-ECAPA (Sprechermerkmale) über mlx-audio, Whisper (mlx-whisper) für Text
und Wortzeiten. Alle Werte sind Messungen bzw. Schätzungen – die Ausgabe sagt bei jedem Wert, was er ist.
"""

import math
import re
import time

import numpy as np
from scipy import signal
from scipy.cluster.hierarchy import fcluster, linkage

import hs_audio as A

SR16 = 16000
VAD_REPO = "mlx-community/silero-vad"
ECAPA_REPO = "aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX"
WHISPER_REPO = "mlx-community/whisper-large-v3-turbo"


# MARK: Modelle

class Models:
    def __init__(self, log=print, whisper=True):
        from mlx_audio.codec.models.ecapa_tdnn import EcapaSpeakerEmbeddingExtractor
        from mlx_audio.vad import load as load_vad
        t0 = time.time()
        self.vad = load_vad(VAD_REPO)
        self.ecapa = EcapaSpeakerEmbeddingExtractor.from_pretrained(ECAPA_REPO)
        self.whisper = WHISPER_REPO if whisper else None
        self.load_seconds = round(time.time() - t0, 1)
        self.log = log

    def embed(self, x16):
        return np.array(self.ecapa.encode(np.asarray(x16, dtype=np.float32)), dtype=np.float32)

    def speech(self, x16, min_silence_ms=250):
        ts = self.vad.get_speech_timestamps(np.asarray(x16, dtype=np.float32), sample_rate=SR16,
                                            min_silence_duration_ms=min_silence_ms, speech_pad_ms=40,
                                            return_seconds=True)
        return [(float(t["start"]), float(t["end"])) for t in ts]

    def transcribe(self, path_or_audio, language="de"):
        import mlx_whisper
        r = mlx_whisper.transcribe(path_or_audio, path_or_hf_repo=self.whisper, language=language,
                                   word_timestamps=True, condition_on_previous_text=False)
        words = []
        for seg in r.get("segments", []):
            for w in seg.get("words", []) or []:
                words.append({"start": float(w["start"]), "end": float(w["end"]), "word": w["word"].strip()})
        return r.get("text", "").strip(), words


# MARK: Tonhöhe (YIN)

def f0_yin(x, sr=SR16, fmin=60.0, fmax=650.0, hop=0.01, threshold=0.15):
    """Grundfrequenz je 10 ms (NaN = stimmlos). Vektorisiert über FFT."""
    x = np.asarray(x, dtype=np.float64)
    W = int(0.025 * sr)
    tmin, tmax = int(sr / fmax), int(sr / fmin)
    L = W + tmax
    h = int(hop * sr)
    if len(x) < L + h:
        return np.array([])
    n = 1 + (len(x) - L) // h
    out = np.full(n, np.nan)
    for b0 in range(0, n, 2000):
        idx = np.arange(b0, min(n, b0 + 2000))
        frames = np.stack([x[i * h: i * h + L] for i in idx])
        frames = frames - frames.mean(axis=1, keepdims=True)
        energy = np.sqrt(np.mean(frames[:, :W] ** 2, axis=1))
        nfft = 1 << (2 * L - 1).bit_length()
        Fx = np.fft.rfft(frames, nfft)
        Fw = np.fft.rfft(frames[:, :W], nfft)
        r = np.fft.irfft(Fx * np.conj(Fw), nfft)[:, : tmax + 1]  # Σ x[j] x[j+τ], j < W
        sq = np.cumsum(frames ** 2, axis=1)
        e0 = sq[:, W - 1][:, None]
        taus = np.arange(tmax + 1)
        e_tau = sq[:, taus + W - 1] - np.where(taus > 0, sq[:, np.maximum(taus - 1, 0)], 0)
        d = e0 + e_tau - 2 * r
        d[:, 0] = 0
        cum = np.cumsum(d[:, 1:], axis=1) / np.arange(1, tmax + 1)
        cmnd = np.ones_like(d)
        cmnd[:, 1:] = d[:, 1:] / np.maximum(cum, 1e-12)
        seg = cmnd[:, tmin:]
        below = seg < threshold
        first = np.where(below.any(axis=1), below.argmax(axis=1), seg.argmin(axis=1))
        # bis zum lokalen Minimum weiterlaufen
        best = first.copy()
        for k in range(len(best)):
            j = best[k]
            while j + 1 < seg.shape[1] and seg[k, j + 1] < seg[k, j]:
                j += 1
            best[k] = j
        val = seg[np.arange(len(best)), best]
        tau = best + tmin
        voiced = (val < 0.35) & (energy > 10 ** (-48 / 20))
        out[idx] = np.where(voiced, sr / tau, np.nan)
    return out


def semitones(f):
    return 12 * np.log2(np.asarray(f) / 100.0)


# MARK: Sprechererkennung

def windows(segments, win=1.5, hop=0.75, min_len=0.6):
    out = []
    for s, e in segments:
        if e - s < min_len:
            continue
        if e - s <= win:
            out.append((s, e))
            continue
        t = s
        while t + win <= e + 1e-6:
            out.append((t, t + win))
            t += hop
        if out[-1][1] < e - 0.3:
            out.append((e - win, e))
    return out


def cluster(emb, threshold=0.65, min_share=0.03, n_speakers=None):
    """Gruppierung nach Stimmähnlichkeit (Kosinus, average linkage). Kleine Gruppen → nächste große Gruppe.
    n_speakers: bekannte Anzahl Stimmen (vom Nutzer) – siehe cluster_known."""
    if len(emb) < 2:
        return np.zeros(len(emb), dtype=int)
    if n_speakers:
        return cluster_known(emb, int(n_speakers), threshold, min_share)
    Z = linkage(emb, method="average", metric="cosine")
    labels = fcluster(Z, t=threshold, criterion="distance") - 1
    counts = np.bincount(labels)
    big = [c for c in range(len(counts)) if counts[c] >= max(3, min_share * len(labels))]
    if not big:
        big = [int(np.argmax(counts))]
    cent = {c: _unit(emb[labels == c].mean(axis=0)) for c in big}
    for i, l in enumerate(labels):
        if l not in cent:
            labels[i] = max(cent, key=lambda c: float(emb[i] @ cent[c]))
    remap = {c: k for k, c in enumerate(sorted(set(labels), key=lambda c: -np.sum(labels == c)))}
    return np.array([remap[l] for l in labels])


def cluster_known(emb, n, threshold=0.7, min_share=0.03):
    """Bekannte Stimmenzahl: zuerst wie ohne Angabe gruppieren; sind es zu wenige Gruppen, die Schwelle schrittweise
    senken; sind es zu viele, die ähnlichsten Gruppen zusammenlegen. Stimmt die geschätzte Zahl schon, ist das
    Ergebnis dasselbe wie ohne Angabe (gemessen: „maxclust“ verschlechterte eine richtige Trennung, deshalb so)."""
    labels = cluster(emb, threshold, min_share)
    for thr in [t for t in (0.65, 0.6, 0.55, 0.5, 0.45, 0.4, 0.35, 0.3) if t < threshold]:
        if len(set(labels)) >= n:
            break
        labels = cluster(emb, thr, min_share)
    labels = np.array(labels)
    while len(set(labels)) > n:
        ids = sorted(set(labels))
        cent = {c: _unit(emb[labels == c].mean(axis=0)) for c in ids}
        best = max(((a, b) for i, a in enumerate(ids) for b in ids[i + 1:]), key=lambda ab: float(cent[ab[0]] @ cent[ab[1]]))
        small, big = sorted(best, key=lambda c: np.sum(labels == c))
        labels[labels == small] = big
    remap = {c: k for k, c in enumerate(sorted(set(labels), key=lambda c: -np.sum(labels == c)))}
    return np.array([remap[l] for l in labels])


def _unit(v):
    return v / max(np.linalg.norm(v), 1e-9)


def turns_from(wins, labels, gap=0.6):
    """Fenster mit gleicher Gruppe zu Repliken zusammenfassen."""
    turns = []
    for (s, e), l in sorted(zip(wins, labels), key=lambda t: t[0][0]):
        if turns and turns[-1]["speaker"] == l and s - turns[-1]["end"] <= gap:
            turns[-1]["end"] = max(turns[-1]["end"], e)
        elif turns and s < turns[-1]["end"]:
            # Überlappung: Grenze in die Mitte
            mid = (s + turns[-1]["end"]) / 2
            turns[-1]["end"] = mid
            turns.append({"start": mid, "end": e, "speaker": int(l)})
        else:
            turns.append({"start": s, "end": e, "speaker": int(l)})
    return turns


def diarize(models, x16, threshold=0.65, segments=None, n_speakers=None):
    segments = segments if segments is not None else models.speech(x16)
    wins = windows(segments)
    if not wins:
        return segments, [], np.zeros((0, 192)), np.array([])
    emb = np.stack([models.embed(x16[int(s * SR16): int(e * SR16)]) for s, e in wins])
    labels = cluster(emb, threshold, n_speakers=n_speakers)
    return segments, wins, emb, labels


def evaluate_diarization(turns, truth, step=0.05):
    """Vergleich mit bekannten Sprechern: Rahmen-Fehlerrate nach bester Zuordnung (ohne Überlappungen)."""
    from scipy.optimize import linear_sum_assignment
    end = max([t["end"] for t in turns] + [t["end"] for t in truth] + [0])
    n = int(end / step) + 1
    hyp, ref = np.full(n, -1), np.full(n, -1)
    ref_ids = {s: i for i, s in enumerate(sorted({t["speaker"] for t in truth}, key=str))}
    for t in truth:
        ref[int(t["start"] / step): int(t["end"] / step)] = ref_ids[t["speaker"]]
    for t in turns:
        hyp[int(t["start"] / step): int(t["end"] / step)] = t["speaker"]
    nh, nr = max(hyp.max() + 1, 1), max(len(ref_ids), 1)
    M = np.zeros((nh, nr))
    both = (hyp >= 0) & (ref >= 0)
    np.add.at(M, (hyp[both], ref[both]), 1)
    ri, ci = linear_sum_assignment(-M)
    correct = M[ri, ci].sum()
    speech = (ref >= 0).sum()
    missed = ((ref >= 0) & (hyp < 0)).sum()
    false_alarm = ((ref < 0) & (hyp >= 0)).sum()
    confusion = both.sum() - correct
    return {"speakers_true": nr, "speakers_found": int(nh), "der": round(float((missed + false_alarm + confusion) / max(speech, 1)), 3),
            "missed": round(float(missed / max(speech, 1)), 3), "false_alarm": round(float(false_alarm / max(speech, 1)), 3),
            "confusion": round(float(confusion / max(speech, 1)), 3)}


# MARK: Merkmale

_VOWELS = re.compile(r"[aeiouyäöü]+", re.I)


def syllables(word):
    return max(1, len(_VOWELS.findall(word)))


def spectral(x, sr):
    """Helligkeit (Schwerpunkt) und Bandbreite (99 %-Grenze) über das Leistungsspektrum."""
    f, P = signal.welch(A.to_mono(x), fs=sr, nperseg=4096)
    P = np.maximum(P, 1e-20)
    centroid = float((f * P).sum() / P.sum())
    c = np.cumsum(P) / P.sum()
    return centroid, float(f[np.searchsorted(c, 0.99)]), f, P


def describe_voice(sp, ref_brightness=None):
    """Allgemeine Stimmbeschreibung (deutsch und englisch für das Design-Modell). Nur geschätzt.

    Gemessen am 16.11.2026: „female or teenage voice with medium pitch“ ergab beim Stimm-Design 250–314 Hz statt
    ~200 Hz (3,6–8,8 Halbtöne zu hoch). Deshalb eindeutige Wörter (adult man/woman) und die Tonlage ausdrücklich;
    die App wählt beim Entwerfen außerdem unter mehreren Kandidaten den mit der passendsten Tonhöhe."""
    f0 = sp.get("f0_median_hz") or 0
    if not f0:
        return "Stimme nicht auswertbar", "A natural voice speaking German"
    if f0 < 158:
        g_de, g_en, kind = "männlich (geschätzt)", "adult man", "m"
    elif f0 < 265:
        g_de, g_en, kind = "weiblich (geschätzt)", "adult woman", "w"
    else:
        g_de, g_en, kind = "kindlich oder sehr hoch (geschätzt)", "child", "k"
    norm = {"m": 118, "w": 205, "k": 290}[kind]
    if f0 < norm * 0.85:
        pitch_de, pitch_en = "tief", "a deep, low-pitched voice"
    elif f0 < norm * 0.95:
        pitch_de, pitch_en = "eher tief", "a fairly low voice"
    elif f0 > norm * 1.15:
        pitch_de, pitch_en = "hoch", "a high-pitched voice"
    elif f0 > norm * 1.05:
        pitch_de, pitch_en = "eher hoch", "a slightly high voice"
    else:
        pitch_de, pitch_en = "mittel", "a medium-pitched voice"
    rate = sp.get("syllables_per_second") or 0
    tempo_de, tempo_en = (("langsam", "slow") if rate and rate < 3.6 else ("schnell", "fast") if rate > 5.4
                          else ("mittleres Tempo", "moderate pace"))
    expr = sp.get("f0_std_semitones") or 0
    expr_de, expr_en = (("ruhig, gleichmäßig", "calm, even") if expr < 2.2 else
                        ("sehr lebhaft, ausdrucksstark", "very lively and expressive") if expr > 4.0 else
                        ("lebendig", "lively"))
    bright = sp.get("brightness_hz") or 0
    # Helligkeit relativ zu den anderen Stimmen derselben Aufnahme (die Bandbreite der Aufnahme verschiebt alle gleich)
    ref = ref_brightness or 1200
    timbre_de, timbre_en = (("dunkel, warm", "dark, warm") if bright and bright < ref * 0.85 else
                            ("hell, klar", "bright, clear") if bright > ref * 1.15 else ("ausgewogen", "balanced"))
    de = f"{g_de}, Tonlage {pitch_de} (~{round(f0)} Hz), {timbre_de}, {tempo_de}, {expr_de}"
    en = (f"An {g_en} with {pitch_en}, {timbre_en} timbre, {tempo_en} delivery, {expr_en}. "
          f"Speaks native German.").replace("An child", "A child")
    return de, en


def speaker_features(x16, turns, spk, words):
    segs = [t for t in turns if t["speaker"] == spk]
    total = sum(t["end"] - t["start"] for t in segs)
    # Für Tonhöhe/Helligkeit höchstens 150 s je Sprecher (gleichmäßig verteilt)
    budget, chunks = 150.0, []
    step = max(1, int(math.ceil(total / budget))) if total > budget else 1
    for t in segs[::step]:
        chunks.append(x16[int(t["start"] * SR16): int(t["end"] * SR16)])
    audio = np.concatenate(chunks) if chunks else np.zeros(SR16)
    f0 = f0_yin(audio)
    f0 = f0[np.isfinite(f0)]
    my_words = [w for w in words if any(t["start"] - 0.1 <= (w["start"] + w["end"]) / 2 <= t["end"] + 0.1 for t in segs)]
    syl = sum(syllables(w["word"]) for w in my_words)
    centroid, _, _, _ = spectral(audio, SR16) if len(audio) > 4096 else (0, 0, 0, 0)
    frames = audio[: len(audio) // 400 * 400].reshape(-1, 400)
    lv = 20 * np.log10(np.maximum(np.sqrt(np.mean(frames ** 2, axis=1)), 1e-6)) if len(frames) else np.array([0])
    lv = lv[lv > lv.max() - 40] if len(lv) else lv
    sp = {"talk_seconds": round(total, 1), "turns": len(segs),
          "mean_turn_seconds": round(total / max(1, len(segs)), 2),
          "f0_median_hz": round(float(np.median(f0)), 1) if f0.size > 20 else None,
          "f0_range_semitones": round(float(np.percentile(semitones(f0), 95) - np.percentile(semitones(f0), 5)), 1) if f0.size > 20 else None,
          "f0_std_semitones": round(float(np.std(semitones(f0))), 2) if f0.size > 20 else None,
          "syllables_per_second": round(syl / max(total, 1e-6), 2) if my_words else None,
          "words": len(my_words), "brightness_hz": round(centroid), "loudness_variation_db": round(float(np.std(lv)), 1)}
    sp["description_de"], sp["voice_en"] = describe_voice(sp)
    sp["sample_lines"] = []
    for t in segs[:40]:
        txt = " ".join(w["word"] for w in my_words if t["start"] - 0.1 <= (w["start"] + w["end"]) / 2 <= t["end"] + 0.1)
        if len(txt.split()) >= 4:
            sp["sample_lines"].append(txt)
        if len(sp["sample_lines"]) >= 3:
            break
    return sp


def guess_roles(speakers):
    """Rolle aus dem Sprechverhalten schätzen: Erzähler = lange Passagen + hoher Anteil, Rest nach Redeanteil."""
    if not speakers:
        return
    total = sum(s["talk_seconds"] for s in speakers) or 1
    cand = max(speakers, key=lambda s: s["mean_turn_seconds"] * (s["talk_seconds"] / total))
    narrator = cand if cand["mean_turn_seconds"] > 4.0 and cand["talk_seconds"] / total > 0.12 else None
    rest = sorted([s for s in speakers if s is not narrator], key=lambda s: -s["talk_seconds"])
    for s in speakers:
        s["share"] = round(s["talk_seconds"] / total, 3)
    if narrator:
        narrator["role_guess"] = "Erzähler (geschätzt)"
    for i, s in enumerate(rest):
        s["role_guess"] = "Hauptfigur (geschätzt)" if i < 4 and s["share"] >= 0.06 else "Nebenfigur (geschätzt)"


def recording_features(x, sr, segments):
    """Klangcharakter der Aufnahme. x in Originalrate (Mono oder Stereo)."""
    mono = A.to_mono(x)
    out = {"sample_rate": sr, "channels": 1 if np.ndim(x) == 1 else int(x.shape[0]),
           "loudness_lufs": A.loudness_lufs(x, sr), "peak_dbfs": round(A.peak_db(x), 1)}
    centroid, bw, f, P = spectral(mono[: sr * 600], sr)
    out["bandwidth_hz"] = round(bw)
    out["brightness_hz"] = round(centroid)
    # Grundrauschen: leiseste 5 % der 50-ms-Rahmen
    hop = int(0.05 * sr)
    fr = mono[: len(mono) // hop * hop].reshape(-1, hop)
    lv = 20 * np.log10(np.maximum(np.sqrt(np.mean(fr ** 2, axis=1)), 1e-7))
    quiet = fr[lv <= np.percentile(lv, 5)]
    out["noise_floor_dbfs"] = round(float(np.percentile(lv, 5)), 1)
    if quiet.size > 4096:
        fq, Pq = signal.welch(quiet.reshape(-1), fs=sr, nperseg=4096)
        flat = float(np.exp(np.mean(np.log(Pq + 1e-20))) / (np.mean(Pq) + 1e-20))
        out["noise_flatness"] = round(flat, 3)
        hum = {}
        for base in (50, 60):
            k = np.argmin(np.abs(fq - base))
            neigh = np.median(Pq[max(0, k - 8): k + 8])
            hum[base] = round(10 * math.log10((Pq[k] + 1e-20) / (neigh + 1e-20)), 1)
        out["hum_db_over_floor"] = hum
    # Stereobreite
    if np.ndim(x) == 2 and x.shape[0] == 2:
        c = np.corrcoef(x[0][: sr * 600], x[1][: sr * 600])[0, 1]
        out["stereo_correlation"] = round(float(c), 3)
    # Nachhall (grob): Abklingen nach Sprachende
    x16 = A.resample(mono, sr, SR16) if sr != SR16 else mono
    slopes = []
    for k, (s, e) in enumerate(segments):
        nxt = segments[k + 1][0] if k + 1 < len(segments) else e + 1.0
        if nxt - e < 0.45 or e - s < 0.8:
            continue
        seg = x16[int((e - 0.05) * SR16): int((e + 0.4) * SR16)]
        if len(seg) < int(0.4 * SR16):
            continue
        en = 10 * np.log10(np.maximum(np.mean(seg[: len(seg) // 160 * 160].reshape(-1, 160) ** 2, axis=1), 1e-12))
        p = int(np.argmax(en[:10]))
        tail = en[p: p + 25]
        floor = out["noise_floor_dbfs"] + 6
        tail = tail[tail > floor]
        if len(tail) >= 5 and tail[0] - tail[-1] > 8:
            slope = np.polyfit(np.arange(len(tail)) * 0.01, tail, 1)[0]
            if slope < -5:
                slopes.append(-60 / slope)
    out["reverb_rt60_estimate_s"] = round(float(np.median(slopes)), 2) if len(slopes) >= 5 else None
    out["reverb_measurements"] = len(slopes)
    return out


def non_speech_content(x, sr, segments, noise_floor_db):
    """Abschnitte ohne Sprache mit hörbarem Inhalt (Musik/Geräusche) – Anzahl, Längen, Tonalität."""
    mono = A.to_mono(x)
    dur = len(mono) / sr
    gaps, t = [], 0.0
    for s, e in segments + [(dur, dur)]:
        if s - t > 1.0:
            gaps.append((t, s))
        t = max(t, e)
    found = []
    for s, e in gaps:
        seg = mono[int(s * sr): int(e * sr)]
        lvl = A.rms_db(seg)
        if lvl > noise_floor_db + 12:
            f, P = signal.welch(seg, fs=sr, nperseg=min(4096, len(seg)))
            flat = float(np.exp(np.mean(np.log(P + 1e-20))) / (np.mean(P) + 1e-20))
            found.append({"start": round(s, 2), "end": round(e, 2), "level_dbfs": round(lvl, 1),
                          "kind_guess": "Musik (tonal, geschätzt)" if flat < 0.05 else "Geräusch/Atmo (geschätzt)"})
    music = [g for g in found if g["kind_guess"].startswith("Musik") and g["end"] - g["start"] >= 2.5]
    return {"segments": found[:200], "content_seconds": round(sum(g["end"] - g["start"] for g in found), 1),
            "music_bridges": len(music),
            "music_bridge_mean_seconds": round(float(np.mean([g["end"] - g["start"] for g in music])), 1) if music else None}


DEFAULT_THRESHOLD = 0.7  # gemessen am 16.11.2026 (Apple Silicon): 0.65 → 6 statt 5 Sprecher, 0.7 → 5, Verwechslung 0 %


def analyze(path, models, log=print, threshold=DEFAULT_THRESHOLD, language="de", truth=None, n_speakers=None):
    """Vollständige Referenzanalyse einer Datei. truth: optionale Sprecher-Wahrheit [{start,end,speaker}]."""
    t0 = time.time()
    x, sr = A.load_audio(path)
    mono = A.to_mono(x)
    x16 = A.resample(mono, sr, SR16)
    dur = len(x16) / SR16
    log(f"[Analyse] {path}: {dur / 60:.1f} min")
    segments, wins, emb, labels = diarize(models, x16, threshold, n_speakers=n_speakers)
    turns = turns_from(wins, labels)
    t1 = time.time()
    text, words = models.transcribe(x16.astype(np.float32), language) if models.whisper else ("", [])
    t2 = time.time()
    speakers = []
    for spk in sorted(set(int(l) for l in labels)):
        sp = speaker_features(x16, turns, spk, words)
        sp["id"] = f"S{spk + 1}"
        speakers.append(sp)
    bright = [sp["brightness_hz"] for sp in speakers if sp.get("brightness_hz")]
    if len(bright) > 1:
        med = float(np.median(bright))
        for sp in speakers:
            sp["description_de"], sp["voice_en"] = describe_voice(sp, med)
    guess_roles(speakers)
    rec = recording_features(x, sr, segments)
    speech = sum(e - s for s, e in segments)
    gaps = [b["start"] - a["end"] for a, b in zip(turns, turns[1:]) if a["speaker"] != b["speaker"] and b["start"] > a["end"]]
    dialog = {"speech_share": round(speech / max(dur, 1e-6), 3), "turns": len(turns),
              "turns_per_minute": round(len(turns) / max(dur / 60, 1e-6), 1),
              "median_gap_between_speakers_s": round(float(np.median(gaps)), 2) if gaps else None,
              "median_turn_seconds": round(float(np.median([t["end"] - t["start"] for t in turns])), 2) if turns else None,
              "words_per_minute_overall": round(len(words) / max(speech / 60, 1e-6), 1) if words else None}
    content = non_speech_content(x, sr, segments, rec["noise_floor_dbfs"])
    result = {"file": path, "duration_s": round(dur, 1), "speakers": speakers, "dialog": dialog, "recording": rec,
              "non_speech": content, "transcript_excerpt": text[:1500], "threshold": threshold,
              "speakers_given": n_speakers,
              "seconds": {"diarization": round(t1 - t0, 1), "transcription": round(t2 - t1, 1),
                          "total": round(time.time() - t0, 1)},
              "turns": [{"start": round(t["start"], 2), "end": round(t["end"], 2), "speaker": f"S{t['speaker'] + 1}"} for t in turns]}
    if truth is not None:
        hyp = [{"start": t["start"], "end": t["end"], "speaker": t["speaker"]} for t in turns]
        result["evaluation"] = evaluate_diarization(hyp, truth)
        sweep = {}
        for thr in (0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8):
            lab = cluster(emb, thr)
            sweep[str(thr)] = evaluate_diarization(turns_from(wins, lab), truth)
        result["threshold_sweep"] = sweep
        n_true = len({t["speaker"] for t in truth})
        result["known_count_evaluation"] = evaluate_diarization(turns_from(wins, cluster(emb, n_speakers=n_true)), truth)
    result["summary_de"] = summary_de(result)
    return result


def summary_de(r):
    rec, d, ns = r["recording"], r["dialog"], r["non_speech"]
    lines = [f"Dauer {r['duration_s'] / 60:.1f} min, Sprachanteil {round(100 * d['speech_share'])} %, "
             f"{len(r['speakers'])} Stimmen erkannt (geschätzt)."]
    for s in r["speakers"]:
        lines.append(f"- {s['id']} – {s.get('role_guess', '')}: {round(100 * s.get('share', 0))} % Redeanteil, "
                     f"{s['description_de']}")
    lines.append(f"Dialog: {d['turns_per_minute']} Sprecherwechsel/min, Pause zwischen Repliken ~"
                 f"{d['median_gap_between_speakers_s']} s, Repliken ~{d['median_turn_seconds']} s.")
    bw = rec["bandwidth_hz"]
    lines.append(f"Aufnahme: {rec['loudness_lufs']} LUFS, Bandbreite bis ~{round(bw / 1000, 1)} kHz"
                 f"{' (begrenzt wie Band/Kassette)' if bw < 14000 else ''}, Grundrauschen {rec['noise_floor_dbfs']} dBFS"
                 + (f", Nachhall ~{rec['reverb_rt60_estimate_s']} s (geschätzt)" if rec.get("reverb_rt60_estimate_s") else "")
                 + (", Mono" if rec.get("channels") == 1 or (rec.get("stereo_correlation") or 0) > 0.97 else ""))
    lines.append(f"Ohne Sprache: {ns['content_seconds']} s Musik/Geräusche, {ns['music_bridges']} Musikbrücken"
                 + (f" (~{ns['music_bridge_mean_seconds']} s)" if ns.get("music_bridge_mean_seconds") else "") + ".")
    return "\n".join(lines)


def style_profile(result, name="Referenz"):
    """Wiederverwendbares Stilprofil (nur allgemeine Merkmale, keine Stimmabdrücke)."""
    return {"name": name, "kind": "Stilprofil (beschreibend)", "speakers": [
        {k: s.get(k) for k in ("id", "role_guess", "share", "description_de", "voice_en", "f0_median_hz",
                                "f0_std_semitones", "syllables_per_second", "brightness_hz")} for s in result["speakers"]],
        "dialog": result["dialog"], "recording": {k: result["recording"].get(k) for k in (
            "bandwidth_hz", "noise_floor_dbfs", "reverb_rt60_estimate_s", "loudness_lufs", "stereo_correlation")},
        "music_bridges": result["non_speech"]["music_bridges"],
        "music_bridge_mean_seconds": result["non_speech"]["music_bridge_mean_seconds"],
        "summary_de": result["summary_de"]}
