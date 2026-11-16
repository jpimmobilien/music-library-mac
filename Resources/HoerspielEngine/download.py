#!/usr/bin/env python3
"""KI-Hörspiel – Modell von Hugging Face in den lokalen Modellspeicher laden (nur auf Knopfdruck in der App).

Die Modelle landen im Hugging-Face-Zwischenspeicher unter HF_HOME (von der App gesetzt, im Ordner
„KI-Hörspiel/Modelle“). Der Rechenprozess liest sie dort ohne Netz (HF_HUB_OFFLINE).

Aufruf:  python -I download.py <repo> [revision]
Ausgabe (je Zeile JSON):  {"event": "total", "bytes": …, "revision": "…"}
                          {"event": "progress", "bytes": …, "existing": …}
                          {"event": "done", "revision": "…", "path": "…"}   bzw.   {"event": "error", "message": "…"}
Abgebrochene Downloads setzt huggingface_hub fort. Keine Anmeldung, kein Token.
"""

import json
import os
import sys
import threading

os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["DO_NOT_TRACK"] = "1"
os.environ.pop("HF_HUB_OFFLINE", None)
os.environ.pop("HF_TOKEN", None)
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"

_out = sys.stdout
sys.stdout = sys.stderr


def emit(msg):
    _out.write(json.dumps(msg) + "\n")
    _out.flush()


def disk_bytes(path):
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            p = os.path.join(root, f)
            if not os.path.islink(p):
                try:
                    total += os.path.getsize(p)
                except OSError:
                    pass
    return total


def main():
    repo = sys.argv[1]
    revision = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
    from huggingface_hub import HfApi, snapshot_download
    from huggingface_hub.constants import HF_HUB_CACHE
    info = HfApi().model_info(repo, revision=revision, files_metadata=True, token=False)
    total = sum((s.size or 0) for s in (info.siblings or []))
    emit({"event": "total", "bytes": total, "revision": info.sha})
    folder = os.path.join(HF_HUB_CACHE, "models--" + repo.replace("/", "--"))
    start = disk_bytes(folder)
    stop = threading.Event()

    def poll():
        while not stop.wait(1.0):
            emit({"event": "progress", "bytes": max(0, disk_bytes(folder) - start), "existing": start})

    t = threading.Thread(target=poll, daemon=True)
    t.start()
    try:
        path = snapshot_download(repo_id=repo, revision=info.sha, token=False)
    finally:
        stop.set()
    emit({"event": "done", "revision": info.sha, "path": path, "bytes": disk_bytes(folder)})


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        emit({"event": "error", "message": str(e)[:1500]})
        sys.exit(1)
