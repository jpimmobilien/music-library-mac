#!/usr/bin/env python3
"""KI-Hörbücher & Hörspiele – lokaler Rechenprozess der Music Library.

Die App startet diesen Prozess bei Bedarf mit dem Python der eigenen Hörspiel-Umgebung und spricht über
stdin/stdout mit ihm (eine JSON-Zeile je Nachricht). Kein Netzwerk-Port, keine Cloud: Modelle werden nur aus dem
lokalen Speicher gelesen (HF_HUB_OFFLINE), der Prozess läuft in einer Sandbox ohne Netzwerkzugriff.

Anfragen   {"id": "…", "cmd": "…", …}
Antworten  {"id": "…", "event": "progress", "value": 0.42, "text": "…"}
           {"id": "…", "event": "result", …}   bzw.   {"id": "…", "event": "error", "message": "…"}

Befehle: status · load_llm · concept · scene · summarize · unload_llm · design_voice · speak · unload_tts ·
         sfx · analyze · verify_consent · mix · unload · quit
"""

import json
import os
import sys
import threading
import time
import traceback

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["DO_NOT_TRACK"] = "1"
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
for _k in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy"):
    os.environ.pop(_k, None)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

_out_lock = threading.Lock()
_real_stdout = sys.stdout
sys.stdout = sys.stderr  # stdout gehört allein dem Protokoll


def send(msg):
    line = json.dumps(msg, ensure_ascii=False, default=str)
    with _out_lock:
        _real_stdout.write(line + "\n")
        _real_stdout.flush()


class Engine:
    def __init__(self):
        self.llm = None
        self.llm_name = None
        self.design = None
        self.clone = None
        self.sfx_model = None
        self.analysis = None

    # MARK: Zustand

    def status(self, req, progress):
        info = {"llm": self.llm_name, "tts": {"design": self.design is not None, "clone": self.clone is not None},
                "sfx": self.sfx_model is not None, "analysis": self.analysis is not None, "python": sys.version.split()[0]}
        try:
            import mlx.core as mx
            info["mlx"] = getattr(mx, "__version__", "?")
            info["device"] = str(mx.default_device())
        except Exception as e:  # noqa: BLE001
            info["mlx_error"] = repr(e)
        try:
            import mlx_audio
            info["mlx_audio"] = getattr(mlx_audio, "__version__", "?")
        except Exception as e:  # noqa: BLE001
            info["mlx_audio_error"] = repr(e)
        return info

    def unload(self, req=None, progress=None):
        self.llm = self.design = self.clone = self.sfx_model = self.analysis = None
        self.llm_name = None
        from hs_voice import free_memory
        free_memory()
        return {}

    # MARK: Geschichte

    def load_llm(self, req, progress):
        path = req["model"]
        if self.llm_name != path:
            self.unload()
            progress(0.1, "Sprachmodell wird geladen …")
            from hs_story import MLXChat
            self.llm = MLXChat(path, log=lambda *a: print(*a, file=sys.stderr))
            self.llm_name = path
        return {"model": path, "load_seconds": getattr(self.llm, "load_seconds", 0)}

    def _writer(self):
        if self.llm is None:
            raise RuntimeError("Kein Sprachmodell geladen.")
        from hs_story import StoryWriter
        return StoryWriter(self.llm, log=lambda *a: print(*a, file=sys.stderr))

    def concept(self, req, progress):
        progress(0.1, "Konzept wird entwickelt …")
        c = self._writer().concept(req["prompt"], float(req.get("minutes", 10)), req.get("mode", "hoerspiel"),
                                   req.get("characters") or None, req.get("style") or None, req.get("narration") or None,
                                   req.get("language") or "de")
        return {"concept": c, "stats": self.llm.stats}

    def scene(self, req, progress):
        w = self._writer()
        progress(0.1, "Szene wird geschrieben …")
        sc = w.write_scene(req["concept"], int(req["index"]), req.get("summaries", []), req.get("tail", ""),
                           int(req.get("target_words", 200)))
        progress(0.85, "Zusammenfassung …")
        sc["summary"] = w.summarize(sc["text"])
        return {"scene": sc, "stats": self.llm.stats}

    def summarize(self, req, progress):
        return {"summary": self._writer().summarize(req["text"])}

    def review(self, req, progress):
        """Lektorat: Widersprüche und Logiklücken der ganzen Geschichte (scenes: [{"title", "text"}])."""
        progress(0.1, "Lektorat …")
        return {"problems": self._writer().review(req["concept"], req.get("scenes", [])), "stats": self.llm.stats}

    def revise_scene(self, req, progress):
        """Eine Szene gezielt korrigieren; scene ist null, wenn die Überarbeitung verworfen wurde."""
        w = self._writer()
        progress(0.1, "Szene wird überarbeitet …")
        sc = w.revise_scene(req["concept"], int(req["index"]), req["text"], req.get("problems", []),
                            int(req.get("target_words", 200)))
        if sc:
            progress(0.85, "Zusammenfassung …")
            sc["summary"] = w.summarize(sc["text"])
        return {"scene": sc, "stats": self.llm.stats}

    def rewrite_line(self, req, progress):
        progress(0.2, "Replik wird neu formuliert …")
        return {"text": self._writer().rewrite_line(req["concept"], req.get("scene_text", ""), req["speaker"], req["line"],
                                                    req.get("hint", ""))}

    def music_plan(self, req, progress):
        """Musikstücke, die eine Produktion braucht (Titel, Übergang, Spannung, Finale, Abspann)."""
        import hs_produce as P
        cues, pieces = P.music_plan(req["story"])
        return {"cues": cues, "pieces": pieces}

    def unload_llm(self, req, progress):
        self.llm = None
        self.llm_name = None
        from hs_voice import free_memory
        free_memory()
        return {}

    # MARK: Stimmen

    def design_voice(self, req, progress):
        import hs_audio as A
        import hs_voice as V
        if self.design is None:
            self.clone = None
            V.free_memory()
            progress(0.1, "Stimm-Design-Modell wird geladen …")
            self.design = V.QwenDesign(req.get("repo") or V.QWEN_DESIGN)
        progress(0.5, "Stimme wird entworfen …")
        t0 = time.time()
        language = req.get("language", "de")
        text = req.get("text") or V.reference_text(language)
        target = req.get("target") or {}
        extra = {}
        if target and int(req.get("candidates", 1)) > 1:
            audio, sr, seed, f0, rate, tried = V.design_matching(self.design, text, req["instruct"], language, target,
                                                                 int(req.get("candidates", 3)), int(req.get("seed") or 1))
            extra = {"seed": seed, "f0_median_hz": f0, "syllables_per_second": rate, "candidates": tried}
        else:
            audio, sr = self.design.speak(text, req["instruct"], language, req.get("seed"))
        audio = A.trim_silence(audio, sr)
        A.write_wav(req["out"], audio, sr)
        return {**extra, "path": req["out"], "text": text, "duration": round(len(audio) / sr, 2),
                "seconds": round(time.time() - t0, 1)}

    def speak(self, req, progress):
        import numpy as np
        import hs_audio as A
        import hs_voice as V
        from hs_text import chunk_text
        if self.clone is None:
            self.design = None
            V.free_memory()
            progress(0.02, "Stimmmodell wird geladen …")
            self.clone = V.QwenClone(req.get("repo") or V.QWEN_BASE)
        lines = req["lines"]
        results = []
        for n, ln in enumerate(lines):
            text = V.prepare_text(ln["text"], req.get("language", "de"))
            if not text:
                results.append({"key": ln["key"], "skipped": True})
                continue
            t0 = time.time()
            parts, sr = [], 24000
            for chunk in chunk_text(text, 220):
                a, sr = self.clone.speak(chunk, ln["ref_audio"], ln["ref_text"], req.get("language", "de"), ln.get("seed"))
                parts += [A.trim_silence(a, sr), np.zeros(int(0.12 * sr), dtype=np.float32)]
            audio = np.concatenate(parts[:-1])
            A.write_wav(ln["out"], audio, sr)
            results.append({"key": ln["key"], "path": ln["out"], "spoken": text, "duration": round(len(audio) / sr, 2),
                            "seconds": round(time.time() - t0, 2)})
            progress((n + 1) / len(lines), f"Zeile {n + 1} von {len(lines)}")
        return {"results": results}

    def unload_tts(self, req, progress):
        self.design = self.clone = None
        from hs_voice import free_memory
        free_memory()
        return {}

    # MARK: Geräusche

    def sfx(self, req, progress):
        import hs_produce as P
        if self.sfx_model is None:
            progress(0.1, "Geräuschmodell wird geladen …")
            self.sfx_model = P.SFXGenerator(req["library"])
        progress(0.4, "Geräusch wird erzeugt …")
        path, took = self.sfx_model.get(req["prompt"], float(req.get("seconds", 4)), int(req.get("seed", 7)))
        return {"path": path, "seconds": took}

    # MARK: Analyse

    def _analysis(self, progress):
        if self.analysis is None:
            progress(0.05, "Analysemodelle werden geladen …")
            import hs_analyze as H
            self.analysis = H.Models(log=lambda *a: print(*a, file=sys.stderr))
        return self.analysis

    def analyze(self, req, progress):
        import hs_analyze as H
        models = self._analysis(progress)
        progress(0.15, "Sprecher, Text und Klang werden analysiert …")
        r = H.analyze(req["path"], models, log=lambda *a: print(*a, file=sys.stderr),
                      threshold=float(req.get("threshold", H.DEFAULT_THRESHOLD)), language=req.get("language", "de"))
        if req.get("out"):
            with open(req["out"], "w") as f:
                json.dump(r, f, ensure_ascii=False, indent=2, default=str)
        return {"result": r, "profile": H.style_profile(r, req.get("name", "Referenz"))}

    def verify_consent(self, req, progress):
        """Einwilligung prüfen: dieselbe Stimme wie die Stimmprobe? Hat die Person den Satz gesagt?"""
        import numpy as np
        import hs_audio as A
        models = self._analysis(progress)
        progress(0.4, "Stimmen werden verglichen …")
        a, _ = A.load_audio(req["consent"], sr=16000, mono=True)
        b, _ = A.load_audio(req["sample"], sr=16000, mono=True)
        ea, eb = models.embed(A.trim_silence(a, 16000)), models.embed(A.trim_silence(b, 16000))
        sim = float(np.dot(ea, eb) / max(np.linalg.norm(ea) * np.linalg.norm(eb), 1e-9))
        progress(0.6, "Einwilligung wird mitgehört …")
        text, _ = models.transcribe(a.astype(np.float32), req.get("language", "de"))
        progress(0.8, "Stimmprobe wird mitgehört …")
        sample_text, _ = models.transcribe(b.astype(np.float32), req.get("language", "de"))
        return {"similarity": round(sim, 3), "transcript": text, "sample_transcript": sample_text,
                "sample_seconds": round(len(b) / 16000, 1)}

    # MARK: Mischung

    def mix(self, req, progress):
        import hs_produce as P
        progress(0.1, "Zeitleiste wird aufgebaut …")
        story = req["story"]
        master, stems, tl, metrics, chapters = P.assemble(story, req["voice_files"], req.get("sfx_files", {}),
                                                          req.get("music_files", {}),
                                                          retro_amount=float(req.get("retro", 0)),
                                                          target_lufs=float(req.get("lufs", -16)))
        out = req["out_dir"]
        os.makedirs(out, exist_ok=True)
        progress(0.75, "Zeitleiste und Spuren werden gespeichert …")
        timeline = tl.save(out)
        timeline["chapters"] = chapters
        with open(os.path.join(out, "zeitleiste.json"), "w") as f:
            json.dump(timeline, f, ensure_ascii=False, indent=1)
        return self._write_mix(out, master, stems, tl, metrics, chapters, req.get("stems", True))

    def render_timeline(self, req, progress):
        """Bearbeitete Zeitleiste (Mehrspur-Editor) neu abmischen."""
        import hs_audio as A
        import hs_produce as P
        out = req["out_dir"]
        progress(0.1, "Clips werden geladen …")
        tl = A.Timeline.load(req["timeline"], out)
        progress(0.4, "Abmischen …")
        master, stems, tl, metrics = P.mix(tl, float(req.get("retro", 0)), float(req.get("lufs", -16)))
        chapters = req["timeline"].get("chapters", [])
        with open(os.path.join(out, "zeitleiste.json"), "w") as f:
            json.dump({**req["timeline"]}, f, ensure_ascii=False, indent=1)
        return self._write_mix(out, master, stems, tl, metrics, chapters, req.get("stems", True))

    def _write_mix(self, out, master, stems, tl, metrics, chapters, write_stems):
        import hs_audio as A
        import hs_produce as P
        A.write_wav(os.path.join(out, "master.wav"), master, P.SR)
        stem_files = {}
        if write_stems:
            for name, st in stems.items():
                p = os.path.join(out, "spuren", f"{name.replace(' ', '_')}.wav")
                A.write_wav(p, st, P.SR, bits=16)
                stem_files[name] = p
        with open(os.path.join(out, "schnittliste.json"), "w") as f:
            json.dump({"chapters": chapters, "clips": tl.clips(), "metrics": metrics}, f, ensure_ascii=False, indent=2)
        return {"master": os.path.join(out, "master.wav"), "stems": stem_files, "chapters": chapters, "metrics": metrics,
                "timeline": os.path.join(out, "zeitleiste.json")}


def main():
    engine = Engine()
    send({"event": "ready", "pid": os.getpid()})
    commands = {name: getattr(engine, name) for name in (
        "status", "load_llm", "concept", "scene", "summarize", "review", "revise_scene", "rewrite_line", "music_plan", "unload_llm", "design_voice", "speak", "unload_tts",
        "sfx", "analyze", "verify_consent", "mix", "render_timeline", "unload")}
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            send({"event": "error", "message": "Ungültige Anfrage"})
            continue
        rid, cmd = req.get("id"), req.get("cmd")

        def progress(value, text, rid=rid):
            send({"id": rid, "event": "progress", "value": value, "text": text})

        try:
            if cmd == "quit":
                send({"id": rid, "event": "result"})
                break
            fn = commands.get(cmd)
            if fn is None:
                raise RuntimeError(f"Unbekannter Befehl: {cmd}")
            result = fn(req, progress)
            send({"id": rid, "event": "result", **(result or {})})
        except Exception as e:  # noqa: BLE001
            traceback.print_exc(file=sys.stderr)
            send({"id": rid, "event": "error", "message": str(e)[:2000]})


if __name__ == "__main__":
    main()
