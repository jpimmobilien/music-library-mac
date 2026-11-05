#!/bin/bash
# Messlauf mit großer, erfundener Bibliothek (Standard 10.000 Titel).
#
#   scripts/run_benchmark.sh "build/Music Library.app" benchmark/macos26 [Titelanzahl]
#   SNAPSHOT_ARCH=x86_64 scripts/run_benchmark.sh …   (Intel-Teil über Rosetta)
set -euo pipefail
APP="$1"
OUT="$2"
COUNT="${3:-10000}"
LIMIT="${BENCHMARK_TIMEOUT:-1200}"
mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"
if [ -f "$APP" ]; then BIN="$APP"; else BIN="$APP/Contents/MacOS/MusicLibrary"; fi
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
echo "▸ Messlauf mit $COUNT Titeln → $OUT_ABS (Rechner $(uname -m), App-Architektur ${SNAPSHOT_ARCH:-nativ})"
set +e
perl -e 'alarm shift; exec @ARGV' "$LIMIT" ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --benchmark "$OUT_ABS" --tracks "$COUNT" > "$OUT_ABS/run.log" 2>&1
STATUS=$?
set -e
cat "$OUT_ABS/benchmark.txt" 2>/dev/null || tail -n 40 "$OUT_ABS/run.log"
if [ $STATUS -ne 0 ]; then
    echo "✗ Messlauf beendet mit Status $STATUS"
    sleep 8
    for f in "$HOME"/Library/Logs/DiagnosticReports/MusicLibrary*; do
        [ -e "$f" ] && cp "$f" "$OUT_ABS/" && echo "  Absturzbericht: $(basename "$f")"
    done
    exit $STATUS
fi
test -f "$OUT_ABS/benchmark.json"
echo "✓ Messlauf abgeschlossen"
