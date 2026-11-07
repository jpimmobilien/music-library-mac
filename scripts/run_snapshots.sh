#!/bin/bash
# Erzeugt Bildschirmfotos (alle Themes, mehrere Fenstergrößen) mit echten Messwerten zur Sichtprüfung.
#   scripts/run_snapshots.sh "build/AETHER.app" snapshots/macos26
set -euo pipefail
APP="$1"; OUT="$2"
mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"
BIN="$APP/Contents/MacOS/AETHER"
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
set +e
perl -e 'alarm shift; exec @ARGV' 600 ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --snapshot "$OUT_ABS" > "$OUT_ABS/run.log" 2>&1
STATUS=$?
set -e
tail -n 30 "$OUT_ABS/run.log" || true
if [ $STATUS -ne 0 ]; then
    echo "✗ App beendet mit Status $STATUS"
    for _ in $(seq 1 30); do ls "$HOME"/Library/Logs/DiagnosticReports/AETHER* >/dev/null 2>&1 && break; sleep 1; done
    for f in "$HOME"/Library/Logs/DiagnosticReports/AETHER*; do [ -e "$f" ] && cp "$f" "$OUT_ABS/"; done
    exit $STATUS
fi
test -f "$OUT_ABS/manifest.json" || { echo "✗ manifest.json fehlt"; exit 1; }
echo "▸ $(ls "$OUT_ABS"/*.png 2>/dev/null | wc -l | tr -d ' ') Bilder"
