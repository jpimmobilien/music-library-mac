#!/bin/bash
# Erzeugt Bildschirmfotos aller Hauptansichten (hell/dunkel) zur Sichtprüfung.
#   scripts/run_snapshots.sh "build/Android Bridge.app" snapshots/macos26
set -euo pipefail
APP="$1"; OUT="$2"
mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"
BIN="$APP/Contents/MacOS/AndroidBridge"
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
set +e
perl -e 'alarm shift; exec @ARGV' 600 ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --snapshot "$OUT_ABS" > "$OUT_ABS/run.log" 2>&1
STATUS=$?
set -e
tail -n 30 "$OUT_ABS/run.log" || true
test $STATUS -eq 0 || { echo "✗ App beendet mit Status $STATUS"; for f in "$HOME"/Library/Logs/DiagnosticReports/AndroidBridge*; do [ -e "$f" ] && cp "$f" "$OUT_ABS/"; done; exit $STATUS; }
test -f "$OUT_ABS/manifest.json" || { echo "✗ manifest.json fehlt"; exit 1; }
echo "▸ $(ls "$OUT_ABS"/*.png 2>/dev/null | wc -l | tr -d ' ') Bilder"
