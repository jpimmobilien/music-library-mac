#!/usr/bin/env python3
"""Prüft den Ladeweg der App ohne Mac: download.py lädt ein kleines Modell in einen leeren HF_HOME (genau wie der
Installer, mit festem Stand), danach muss der Rechenprozess es ohne Netz über den Repo-Namen finden.

Aufruf: python3 offline_check.py <ausgabeordner> [repo] [revision]
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DOWNLOAD = os.path.join(HERE, "..", "..", "Resources", "HoerspielEngine", "download.py")


def main():
    out = sys.argv[1]
    repo = sys.argv[2] if len(sys.argv) > 2 else "mlx-community/silero-vad"
    revision = sys.argv[3] if len(sys.argv) > 3 else ""
    os.makedirs(out, exist_ok=True)
    home = tempfile.mkdtemp(prefix="hf-")
    env = dict(os.environ, HF_HOME=home)
    env.pop("HF_HUB_OFFLINE", None)
    p = subprocess.run([sys.executable, "-I", os.path.abspath(DOWNLOAD), repo, revision], env=env,
                       capture_output=True, text=True, timeout=1800)
    events = [json.loads(line) for line in p.stdout.splitlines() if line.startswith("{")]
    done = next((e for e in events if e.get("event") == "done"), None)
    result = {"repo": repo, "revision": revision, "download_exit": p.returncode, "events": len(events),
              "done": done, "stderr": p.stderr[-1500:]}
    # Offline wie die App: HF_HUB_OFFLINE=1, Laden über den Repo-Namen
    code = ("import sys; from huggingface_hub import snapshot_download; "
            f"print(snapshot_download({repo!r}))")
    off = subprocess.run([sys.executable, "-I", "-c", code], env=dict(env, HF_HUB_OFFLINE="1"),
                         capture_output=True, text=True, timeout=300)
    result["offline_exit"] = off.returncode
    result["offline_path"] = off.stdout.strip()
    result["offline_error"] = off.stderr.strip()[-800:]
    files = {}
    snap = result["offline_path"]
    if os.path.isdir(snap):
        for root, _, names in os.walk(snap):
            for n in names:
                fp = os.path.join(root, n)
                files[os.path.relpath(fp, snap)] = {"bytes": os.path.getsize(fp) if os.path.exists(fp) else None,
                                                    "link": os.path.islink(fp)}
    result["files"] = files
    store = []
    for root, _, names in os.walk(home):
        for n in names:
            fp = os.path.join(root, n)
            store.append((os.path.relpath(fp, home), os.path.islink(fp), os.path.getsize(fp) if os.path.exists(fp) else None))
    result["store"] = sorted(store)
    # Alles muss im Ordner des Modells liegen (sonst stimmen Größe und Entfernen in der App nicht)
    repo_dir = os.path.join(home, "hub", "models--" + repo.replace("/", "--"))
    outside = [f for f in files if not os.path.realpath(os.path.join(snap, f)).startswith(os.path.realpath(repo_dir) + os.sep)]
    real = 0
    for root, _, names in os.walk(repo_dir):
        for n in names:
            fp = os.path.join(root, n)
            if not os.path.islink(fp):
                real += os.path.getsize(fp)
    result["outside_repo_folder"] = outside
    result["repo_folder_bytes"] = real
    result["download_reported_bytes"] = (done or {}).get("bytes")
    result["ok"] = not outside and p.returncode == 0 and off.returncode == 0 and bool(done) and \
        (not revision or done.get("revision") == revision) and result["offline_path"].endswith(done["revision"])
    with open(os.path.join(out, "offline.json"), "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print("[Offline]", json.dumps({k: result[k] for k in ("repo", "download_exit", "offline_exit", "offline_path", "ok", "files", "outside_repo_folder", "repo_folder_bytes", "download_reported_bytes")}))
    for row in result["store"]:
        print("[Offline] Speicher", row)
    if not result["ok"]:
        print(result["stderr"], result["offline_error"], sep="\n")
    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
