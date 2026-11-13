#!/usr/bin/env python3
"""KI-Musik – Modell von Hugging Face laden (nur auf ausdrücklichen Wunsch in der App).

Aufruf:  python -I download.py <repo> <zielordner>
Ausgabe (je Zeile JSON):  {"event": "total", "bytes": …, "revision": "…"}
                          {"event": "progress", "bytes": …}
                          {"event": "done", "revision": "…"}   bzw.   {"event": "error", "message": "…"}
Abgebrochene Downloads setzt huggingface_hub beim nächsten Aufruf fort. Keine Anmeldung, kein Token.
"""

import json
import os
import sys
import threading
import time

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
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def main():
    repo, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)
    from huggingface_hub import HfApi, snapshot_download
    info = HfApi().model_info(repo, files_metadata=True, token=False)
    total = sum((s.size or 0) for s in (info.siblings or []))
    emit({"event": "total", "bytes": total, "revision": info.sha})
    start = disk_bytes(dest)
    stop = threading.Event()

    def poll():
        while not stop.wait(1.0):
            emit({"event": "progress", "bytes": max(0, disk_bytes(dest) - start), "existing": start})

    t = threading.Thread(target=poll, daemon=True)
    t.start()
    try:
        snapshot_download(repo_id=repo, local_dir=dest, revision=info.sha, token=False)
    finally:
        stop.set()
    emit({"event": "done", "revision": info.sha, "bytes": disk_bytes(dest)})


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        emit({"event": "error", "message": str(e)[:1500]})
        sys.exit(1)
