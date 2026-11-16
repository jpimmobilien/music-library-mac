#!/bin/bash
# Startet Panora in einem Automatikmodus und sichert bei einem Absturz den Bericht.
#   scripts/run_app_mode.sh <App> <Sekunden> <Argumente …>
#   z. B. scripts/run_app_mode.sh build/Panora.app 180 --selftest logs/selftest.json
set -uo pipefail
APP="$1"; TIMEOUT="$2"; shift 2
BIN="$APP/Contents/MacOS/Panora"
LOG="${RUN_LOG:-logs/app-run.log}"
mkdir -p "$(dirname "$LOG")"
perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$BIN" "$@" -ApplePersistenceIgnoreState YES >> "$LOG" 2>&1
STATUS=$?
tail -n 40 "$LOG" || true
if [ $STATUS -ne 0 ]; then
    echo "✗ Panora beendet mit Status $STATUS"
    for _ in $(seq 1 20); do ls "$HOME"/Library/Logs/DiagnosticReports/Panora* >/dev/null 2>&1 && break; sleep 1; done
    for f in "$HOME"/Library/Logs/DiagnosticReports/Panora*; do
        [ -e "$f" ] || continue
        cp "$f" "$(dirname "$LOG")/"
        echo "── Absturzbericht $(basename "$f") (Auszug)"
        grep -E '"symbol"|Thread|abort|assert|crashed|Exception' "$f" | head -60 || true
    done
fi
exit $STATUS
