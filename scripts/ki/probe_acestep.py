#!/usr/bin/env python3
"""Machbarkeitsprobe KI-Musik (ACE-Step 1.5) – läuft im Prüfstand „KI-Probe“ auf einem Apple-Silicon-Rechner.

Erzeugt kurze Stücke über die Python-Schnittstelle von ACE-Step (lokal, ohne Cloud) und schreibt Zeiten,
Speicherbedarf, Gerät und objektive Messwerte nach <out>/probe.json. Hören kann diese Probe nichts –
die Messwerte zeigen nur, ob überhaupt Musik (keine Stille, kein Rauschen, richtige Länge) entsteht.

Aufruf (im Verzeichnis der ACE-Step-Installation):  uv run python probe_acestep.py <checkpoints> <out>
"""

import json
import os
import platform
import resource
import subprocess
import sys
import time
import traceback

# Erzwingt reinen Lokalbetrieb: keine Modell-Nachladungen, keine Cloud-Schnittstelle.
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")

CHECKPOINTS = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "checkpoints")
OUT = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else "out")
LM_MODEL = os.environ.get("KI_LM", "acestep-5Hz-lm-0.6B")
os.makedirs(os.path.join(OUT, "audio"), exist_ok=True)

report = {"lm_model": LM_MODEL, "steps": [], "cases": []}


def save():
    with open(os.path.join(OUT, "probe.json"), "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False, default=str)


def peak_rss_mb():
    r = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return round(r / (1024 * 1024) if sys.platform == "darwin" else r / 1024, 1)


def metal_mb():
    try:
        import mlx.core as mx
        f = getattr(mx, "get_peak_memory", None) or getattr(getattr(mx, "metal", None), "get_peak_memory", None)
        return round(f() / (1024 * 1024), 1) if f else None
    except Exception:
        return None


def environment():
    env = {"python": sys.version.split()[0], "machine": platform.machine(), "macos": platform.mac_ver()[0]}
    try:
        env["ram_gb"] = round(int(subprocess.check_output(["sysctl", "-n", "hw.memsize"])) / 2**30, 1)
        env["cpu"] = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"]).decode().strip()
        env["cores"] = int(subprocess.check_output(["sysctl", "-n", "hw.ncpu"]))
    except Exception as e:
        env["sysctl_error"] = str(e)
    try:
        import torch
        env["torch"] = torch.__version__
        env["mps_available"] = bool(torch.backends.mps.is_available())
        env["mps_built"] = bool(torch.backends.mps.is_built())
    except Exception as e:
        env["torch_error"] = repr(e)
    try:
        import mlx.core as mx
        env["mlx"] = getattr(mx, "__version__", "?")
        env["mlx_device"] = str(mx.default_device())
        a = mx.ones((256, 256))
        mx.eval(a @ a)
        env["mlx_metal_ok"] = True
    except Exception as e:
        env["mlx_error"] = repr(e)
    try:
        from acestep.gpu_config import get_gpu_memory_gb
        env["acestep_gpu_memory_gb"] = get_gpu_memory_gb()
    except Exception as e:
        env["gpu_config_error"] = repr(e)
    return env


def measure(path):
    """Objektive Kennwerte einer erzeugten Datei (keine Aussage über den Klang)."""
    try:
        import numpy as np
        import soundfile as sf
        data, rate = sf.read(path, always_2d=True, dtype="float32")
        mono = data.mean(axis=1)
        n = len(mono)
        if n == 0:
            return {"frames": 0}
        rms = float(np.sqrt(np.mean(mono ** 2)) + 1e-12)
        block = max(1, rate // 10)
        blocks = mono[: n - n % block].reshape(-1, block) if n >= block else mono.reshape(1, -1)
        block_db = 20 * np.log10(np.sqrt((blocks ** 2).mean(axis=1)) + 1e-12)
        spec = np.abs(np.fft.rfft(mono[: min(n, rate * 30)] * np.hanning(min(n, rate * 30))))
        freqs = np.fft.rfftfreq(min(n, rate * 30), 1 / rate)
        power = spec ** 2 + 1e-20
        flatness = float(np.exp(np.mean(np.log(power))) / np.mean(power))
        centroid = float((freqs * power).sum() / power.sum())
        return {
            "seconds": round(n / rate, 2), "rate": int(rate), "channels": int(data.shape[1]),
            "rms_db": round(20 * np.log10(rms), 1), "peak_db": round(20 * np.log10(float(np.abs(data).max()) + 1e-12), 1),
            "silent_share": round(float((block_db < -50).mean()), 3),
            "spectral_flatness": round(flatness, 4), "spectral_centroid_hz": round(centroid),
            "clipped_share": round(float((np.abs(data) >= 0.999).mean()), 5),
        }
    except Exception as e:
        return {"measure_error": repr(e)}


def step(name, fn):
    t0 = time.time()
    entry = {"name": name}
    try:
        msg = fn()
        entry.update(ok=True, message=str(msg)[:2000])
    except Exception as e:
        entry.update(ok=False, error=repr(e), trace=traceback.format_exc()[-3000:])
    entry.update(seconds=round(time.time() - t0, 1), peak_rss_mb=peak_rss_mb(), metal_peak_mb=metal_mb())
    report["steps"].append(entry)
    save()
    print(f"[Probe] {name}: {'OK' if entry.get('ok') else 'FEHLER'} {entry['seconds']} s", flush=True)
    return entry.get("ok", False)


report["environment"] = environment()
save()
print("[Probe] Umgebung:", json.dumps(report["environment"], ensure_ascii=False), flush=True)

from acestep.handler import AceStepHandler  # noqa: E402
from acestep.llm_inference import LLMHandler  # noqa: E402
from acestep.inference import GenerationConfig, GenerationParams, create_sample, generate_music  # noqa: E402

PROJECT = os.environ.get("ACE_ROOT", os.getcwd())
dit = AceStepHandler()
llm = LLMHandler()
state = {"dit": None, "llm": None}


def init_dit():
    # Modelle müssen vorhanden sein – initialize_service würde sonst selbst nachladen.
    from acestep.model_downloader import check_main_model_exists
    if not check_main_model_exists(CHECKPOINTS):
        raise RuntimeError("Hauptmodell fehlt im Ordner " + CHECKPOINTS)
    attempts = [dict(device="auto", use_mlx_dit=True), dict(device="cpu", use_mlx_dit=False)]
    errors = []
    for a in attempts:
        msg, ok = dit.initialize_service(project_root=PROJECT, config_path="acestep-v15-turbo",
                                         offload_to_cpu=False, offload_dit_to_cpu=False,
                                         prefer_source="huggingface", **a)
        if ok:
            state["dit"] = a
            report["dit_config"] = a
            return f"{a}: {msg}"
        errors.append(f"{a}: {msg}")
    raise RuntimeError(" | ".join(errors))


def init_llm():
    attempts = [dict(backend="mlx", device="auto"), dict(backend="pt", device="cpu")]
    errors = []
    for a in attempts:
        msg, ok = llm.initialize(checkpoint_dir=CHECKPOINTS, lm_model_path=LM_MODEL, offload_to_cpu=False,
                                 dtype=None, **a)
        if ok:
            state["llm"] = a
            report["llm_config"] = a
            return f"{a}: {msg}"
        errors.append(f"{a}: {msg}")
    raise RuntimeError(" | ".join(errors))


GERMAN_LYRICS = """[Verse]
Die Sonne sinkt am alten See
das Wasser glänzt wie Gold
wir laufen barfuß durch den Klee
der Abend ist uns hold

[Chorus]
Sommerabend, bleib noch hier
die Nacht gehört nur dir und mir
Sommerabend, sing mit mir
die Nacht gehört nur dir und mir"""


def generate(case_id, params, config, note=""):
    def run():
        t0 = time.time()
        res = generate_music(dit, llm if state["llm"] else None, params=params, config=config,
                             save_dir=os.path.join(OUT, "audio", case_id))
        elapsed = time.time() - t0
        files = []
        for a in res.audios:
            p = a.get("path") or ""
            if p and os.path.exists(p):
                files.append({"path": os.path.relpath(p, OUT), "seed": a.get("params", {}).get("seed") if isinstance(a.get("params"), dict) else None,
                              "measure": measure(p)})
        audio_seconds = sum(f["measure"].get("seconds", 0) for f in files)
        report["cases"].append({
            "id": case_id, "note": note, "ok": bool(res.success), "status": res.status_message[:500],
            "error": res.error, "seconds": round(elapsed, 1),
            "realtime_factor": round(audio_seconds / elapsed, 2) if elapsed > 0 and audio_seconds else None,
            "params": {k: getattr(params, k) for k in ("task_type", "caption", "lyrics", "instrumental", "vocal_language",
                                                         "bpm", "keyscale", "duration", "inference_steps", "seed", "thinking")
                       if hasattr(params, k)},
            "batch_size": config.batch_size, "files": files,
            "peak_rss_mb": peak_rss_mb(), "metal_peak_mb": metal_mb(),
        })
        save()
        if not res.success:
            raise RuntimeError(res.error or res.status_message)
        return f"{len(files)} Datei(en), {elapsed:.1f} s"
    return step("Erzeugen " + case_id, run)


if step("DiT laden (turbo)", init_dit):
    step(f"Sprachmodell laden ({LM_MODEL})", init_llm)

    base = dict(inference_steps=8, guidance_scale=1.0)
    generate("01-instrumental-en", GenerationParams(
        task_type="text2music", caption="Calm lo-fi hip hop with warm piano chords, soft vinyl crackle and a relaxed drum groove",
        lyrics="[Instrumental]", instrumental=True, duration=30, bpm=80, seed=1234, thinking=bool(state["llm"]), **base),
        GenerationConfig(batch_size=1, audio_format="flac", use_random_seed=False, seeds=[1234]),
        "Instrumental, englische Beschreibung, mit Sprachmodell (falls geladen)")

    generate("02-instrumental-de", GenerationParams(
        task_type="text2music", caption="Ruhiges Lo-Fi-Stück mit warmem Klavier, leisem Knistern und entspanntem Schlagzeug",
        lyrics="[Instrumental]", instrumental=True, duration=30, bpm=80, seed=1234, thinking=bool(state["llm"]), **base),
        GenerationConfig(batch_size=1, audio_format="flac", use_random_seed=False, seeds=[1234]),
        "Gleiche Beschreibung auf Deutsch – versteht das Modell deutsche Beschreibungen?")

    generate("03-gesang-de-eigener-text", GenerationParams(
        task_type="text2music", caption="Upbeat German pop song, female vocals, acoustic guitar, bright summer mood",
        lyrics=GERMAN_LYRICS, instrumental=False, vocal_language="de", duration=40, bpm=110, seed=42,
        thinking=bool(state["llm"]), **base),
        GenerationConfig(batch_size=1, audio_format="flac", use_random_seed=False, seeds=[42]),
        "Deutscher Gesang mit vorgegebenem Text (für Whisper-Verständlichkeitsprüfung)")

    if state["llm"]:
        def write_lyrics():
            r = create_sample(llm, query="Ein fröhlicher deutscher Popsong über einen Sommerabend am See",
                              instrumental=False, vocal_language="de")
            report["create_sample"] = {k: getattr(r, k, None) for k in
                                       ("success", "caption", "lyrics", "bpm", "duration", "keyscale", "language", "status_message", "error")}
            save()
            if not r.success:
                raise RuntimeError(r.error or r.status_message)
            return r.lyrics[:300]
        if step("KI schreibt deutschen Text (create_sample)", write_lyrics):
            s = report["create_sample"]
            generate("04-gesang-de-ki-text", GenerationParams(
                task_type="text2music", caption=s["caption"], lyrics=s["lyrics"], instrumental=False, vocal_language="de",
                bpm=s.get("bpm"), keyscale=s.get("keyscale") or "", duration=40, seed=7, thinking=True, **base),
                GenerationConfig(batch_size=1, audio_format="flac", use_random_seed=False, seeds=[7]),
                "Text und Beschreibung vom Sprachmodell, deutsch")

    generate("05-varianten-ohne-lm", GenerationParams(
        task_type="text2music", caption="Energetic synthwave with driving bass, bright arpeggios and punchy drums",
        lyrics="[Instrumental]", instrumental=True, duration=20, bpm=118, keyscale="A minor", seed=-1, thinking=False, **base),
        GenerationConfig(batch_size=2, audio_format="flac", use_random_seed=False, seeds=[11, 22]),
        "Zwei Varianten gleichzeitig, nur DiT (ohne Sprachmodell) – reine Erzeugungsgeschwindigkeit")

    first = next((c for c in report["cases"] if c["id"] == "01-instrumental-en" and c["files"]), None)
    if first:
        generate("06-remix-cover", GenerationParams(
            task_type="cover", src_audio=os.path.join(OUT, first["files"][0]["path"]),
            caption="Smooth jazz trio version with upright bass, brushed drums and jazz piano",
            lyrics="[Instrumental]", instrumental=True, audio_cover_strength=0.5, seed=5, **base),
            GenerationConfig(batch_size=1, audio_format="flac", use_random_seed=False, seeds=[5]),
            "Remix (cover) des ersten Stücks als Jazz-Version – Original bleibt unverändert")

report["finished"] = True
save()
print("[Probe] fertig", flush=True)
