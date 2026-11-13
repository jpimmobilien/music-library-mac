#!/usr/bin/env python3
"""KI-Musik – lokaler Rechenprozess der Music Library (ACE-Step 1.5).

Die App startet diesen Prozess bei Bedarf mit dem Python der eigenen KI-Umgebung und spricht über stdin/stdout
mit ihm: eine JSON-Zeile je Nachricht. Kein Netzwerk-Port, keine Cloud – Modelle werden nur gelesen, nie
nachgeladen (HF_HUB_OFFLINE). Beendet die App den Prozess (Abbrechen, Leerlauf, Beenden), ist aller Speicher frei.

Anfragen   {"id": "…", "cmd": "status" | "load" | "generate" | "write_lyrics" | "unload" | "quit", …}
Antworten  {"id": "…", "event": "progress", "value": 0.42, "text": "…"}
           {"id": "…", "event": "result", …}   bzw.   {"id": "…", "event": "error", "message": "…"}
"""

import json
import os
import sys
import threading
import time
import traceback

# Nur lokal: keine Downloads, keine Telemetrie, keine Proxy-Variablen der Umgebung
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["DO_NOT_TRACK"] = "1"
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
for _k in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy"):
    os.environ.pop(_k, None)

_out_lock = threading.Lock()
_real_stdout = sys.stdout
# Bibliotheken schreiben gern auf stdout – das gehört allein dem Protokoll. Alles andere geht ins Protokoll (stderr).
sys.stdout = sys.stderr


def send(msg):
    line = json.dumps(msg, ensure_ascii=False, default=str)
    with _out_lock:
        _real_stdout.write(line + "\n")
        _real_stdout.flush()


class Engine:
    def __init__(self, ace_root, checkpoints):
        self.ace_root = ace_root
        self.checkpoints = checkpoints
        self.dit = None
        self.llm = None
        self.loaded = {}
        sys.path.insert(0, ace_root)

    # MARK: Zustand

    def status(self):
        info = {"ace_root": self.ace_root, "checkpoints": self.checkpoints, "loaded": self.loaded}
        try:
            import torch
            info["torch"] = torch.__version__
            info["mps"] = bool(torch.backends.mps.is_available())
        except Exception as e:  # noqa: BLE001
            info["torch_error"] = repr(e)
        try:
            import mlx.core as mx
            info["mlx"] = getattr(mx, "__version__", "?")
        except Exception as e:  # noqa: BLE001
            info["mlx_error"] = repr(e)
        models = {}
        if os.path.isdir(self.checkpoints):
            for name in sorted(os.listdir(self.checkpoints)):
                p = os.path.join(self.checkpoints, name)
                if os.path.isdir(p):
                    models[name] = any(f.endswith((".safetensors", ".bin")) for f in os.listdir(p))
        info["models"] = models
        return info

    def load(self, req, progress):
        dit_model = req.get("dit", "acestep-v15-turbo")
        lm_model = req.get("lm")  # None = ohne Sprachmodell
        from acestep.model_downloader import check_main_model_exists
        if not check_main_model_exists(self.checkpoints):
            raise RuntimeError("Die Modelle sind nicht vollständig installiert.")
        if self.loaded.get("dit") != dit_model:
            progress(0.05, "Musikmodell wird geladen …")
            from acestep.handler import AceStepHandler
            self.dit = AceStepHandler()
            # Überschreibbar für Prüfstände auf virtuellen Rechnern (dort fehlen GPU-Speicher bzw. Metal-Funktionen)
            device = os.environ.get("KI_DIT_DEVICE", "auto")
            use_mlx = os.environ.get("KI_MLX_DIT", "1") != "0"
            msg, ok = self.dit.initialize_service(project_root=self.ace_root, config_path=dit_model, device=device,
                                                  offload_to_cpu=False, offload_dit_to_cpu=False, use_mlx_dit=use_mlx,
                                                  prefer_source="huggingface")
            if not ok and device != "cpu" and "out of memory" in str(msg).lower():
                # Zu wenig Grafikspeicher (z. B. kleine Rechner): auf dem Prozessor weiter – langsam, aber es läuft
                progress(0.3, "Zu wenig Grafikspeicher – Musikmodell läuft auf dem Prozessor (langsamer) …")
                self.dit = AceStepHandler()
                msg, ok = self.dit.initialize_service(project_root=self.ace_root, config_path=dit_model, device="cpu",
                                                      offload_to_cpu=False, offload_dit_to_cpu=False, use_mlx_dit=False,
                                                      prefer_source="huggingface")
                device = "cpu"
            if not ok:
                self.dit = None
                raise RuntimeError(f"Musikmodell konnte nicht geladen werden: {msg}")
            self.loaded["dit"] = dit_model
            self.loaded["dit_device"] = device
        if lm_model and self.loaded.get("lm") != lm_model:
            progress(0.6, "Sprachmodell wird geladen …")
            from acestep.llm_inference import LLMHandler
            self.llm = LLMHandler()
            backend = os.environ.get("KI_LM_BACKEND", "mlx")
            msg, ok = self.llm.initialize(checkpoint_dir=self.checkpoints, lm_model_path=lm_model, backend=backend,
                                          device="cpu" if backend == "pt" else "auto", offload_to_cpu=False, dtype=None)
            if not ok:
                self.llm = None
                raise RuntimeError(f"Sprachmodell konnte nicht geladen werden: {msg}")
            self.loaded["lm"] = lm_model
            self.loaded["lm_backend"] = backend
        progress(1.0, "Bereit")
        return {"loaded": self.loaded}

    def unload(self):
        self.dit = None
        self.llm = None
        self.loaded = {}
        import gc
        gc.collect()
        try:
            import torch
            if torch.backends.mps.is_available():
                torch.mps.empty_cache()
        except Exception:  # noqa: BLE001
            pass
        return {"loaded": {}}

    # MARK: Erzeugen

    # MLX-Kernel lassen sich auf manchen Rechnern nicht übersetzen (beobachtet auf einem virtuellen Mac mit
    # macOS 26). Dann einmal mit PyTorch weitermachen statt abzubrechen.
    @staticmethod
    def _metal_failure(text):
        return "metal::Device" in text or "Unable to load kernel" in text

    def _lm_fallback(self, progress):
        if self.llm is None or self.loaded.get("lm_backend") == "pt":
            return False
        progress(0.05, "Sprachmodell wechselt auf PyTorch …")
        from acestep.llm_inference import LLMHandler
        lm_model = self.loaded.get("lm")
        self.llm = LLMHandler()
        msg, ok = self.llm.initialize(checkpoint_dir=self.checkpoints, lm_model_path=lm_model, backend="pt",
                                      device="auto", offload_to_cpu=False, dtype=None)
        if not ok:
            self.llm = None
            self.loaded.pop("lm", None)
            return False
        self.loaded["lm_backend"] = "pt"
        print(f"[KI] Sprachmodell auf PyTorch umgestellt: {msg}", file=sys.stderr)
        return True

    def generate(self, req, progress):
        try:
            return self._generate(req, progress)
        except RuntimeError as e:
            if self._metal_failure(str(e)) and req.get("use_lm", True) and self._lm_fallback(progress):
                return self._generate(req, progress)
            raise

    def _generate(self, req, progress):
        if self.dit is None:
            raise RuntimeError("Das Musikmodell ist nicht geladen.")
        from acestep.inference import GenerationConfig, GenerationParams, generate_music
        p = req.get("params", {})
        allowed = {f for f in GenerationParams.__dataclass_fields__}
        params = GenerationParams(**{k: v for k, v in p.items() if k in allowed})
        seeds = req.get("seeds")
        config = GenerationConfig(batch_size=int(req.get("batch_size", 1)), audio_format=req.get("format", "flac"),
                                  use_random_seed=not seeds, seeds=seeds)
        save_dir = req["save_dir"]
        os.makedirs(save_dir, exist_ok=True)

        def cb(value, desc=None, **_):
            try:
                progress(float(value), desc or "")
            except Exception:  # noqa: BLE001
                pass

        use_lm = req.get("use_lm", True) and self.llm is not None
        t0 = time.time()
        res = generate_music(self.dit, self.llm if use_lm else None, params=params, config=config,
                             save_dir=save_dir, progress=cb)
        if not res.success:
            raise RuntimeError(res.error or res.status_message or "Erzeugen fehlgeschlagen")
        files = []
        for a in res.audios:
            path = a.get("path") or ""
            if not path or not os.path.exists(path):
                continue
            ap = a.get("params") or {}
            files.append({"path": path, "seed": ap.get("seed") if isinstance(ap, dict) else None,
                          "sample_rate": a.get("sample_rate")})
        meta = {}
        lm = (res.extra_outputs or {}).get("lm_metadata") if isinstance(res.extra_outputs, dict) else None
        if isinstance(lm, dict):
            meta = {k: lm.get(k) for k in ("caption", "lyrics", "bpm", "keyscale", "duration", "language", "timesignature") if k in lm}
        return {"files": files, "seconds": round(time.time() - t0, 2), "metadata": meta}

    def write_lyrics(self, req, progress):
        try:
            return self._write_lyrics(req, progress)
        except RuntimeError as e:
            if self._metal_failure(str(e)) and self._lm_fallback(progress):
                return self._write_lyrics(req, progress)
            raise

    def _write_lyrics(self, req, progress):
        if self.llm is None:
            raise RuntimeError("Das Sprachmodell ist nicht geladen.")
        from acestep.inference import create_sample, format_sample
        progress(0.1, "Songtext wird geschrieben …")
        if req.get("lyrics"):
            r = format_sample(self.llm, caption=req.get("caption", ""), lyrics=req["lyrics"],
                              user_metadata={"language": req["language"]} if req.get("language") else None)
        else:
            r = create_sample(self.llm, query=req.get("query", ""), instrumental=bool(req.get("instrumental")),
                              vocal_language=req.get("language") or None)
        if not getattr(r, "success", False):
            raise RuntimeError(getattr(r, "error", None) or getattr(r, "status_message", "") or "Fehlgeschlagen")
        return {k: getattr(r, k, None) for k in ("caption", "lyrics", "bpm", "duration", "keyscale", "language", "timesignature")}


def main():
    ace_root = os.environ["KI_ACE_ROOT"]
    checkpoints = os.environ["KI_CHECKPOINTS"]
    engine = Engine(ace_root, checkpoints)
    send({"event": "ready", "pid": os.getpid()})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            send({"event": "error", "message": "Ungültige Anfrage"})
            continue
        rid = req.get("id")
        cmd = req.get("cmd")

        def progress(value, text, rid=rid):
            send({"id": rid, "event": "progress", "value": value, "text": text})

        try:
            if cmd == "quit":
                send({"id": rid, "event": "result"})
                break
            if cmd == "status":
                result = engine.status()
            elif cmd == "load":
                result = engine.load(req, progress)
            elif cmd == "unload":
                result = engine.unload()
            elif cmd == "generate":
                result = engine.generate(req, progress)
            elif cmd == "write_lyrics":
                result = engine.write_lyrics(req, progress)
            else:
                raise RuntimeError(f"Unbekannter Befehl: {cmd}")
            send({"id": rid, "event": "result", **(result or {})})
        except Exception as e:  # noqa: BLE001
            traceback.print_exc(file=sys.stderr)
            send({"id": rid, "event": "error", "message": str(e)[:2000]})


if __name__ == "__main__":
    main()
