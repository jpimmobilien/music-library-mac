#!/bin/bash
# Startet Panora in einem Automatikmodus. Hängt die App länger als <Sekunden>, wird ein Stichprobenprofil
# (sample) des Prozesses gesichert und die App beendet; bei einem Absturz wird der Bericht gesichert.
#   scripts/run_app_mode.sh <App> <Sekunden> <Argumente …>
set -uo pipefail
APP="$1"; TIMEOUT="$2"; shift 2
BIN="$APP/Contents/MacOS/Panora"
LOG="${RUN_LOG:-logs/app-run.log}"
mkdir -p "$(dirname "$LOG")"
"$BIN" "$@" -ApplePersistenceIgnoreState YES >> "$LOG" 2>&1 &
PID=$!
STATUS=""
for _ in $(seq 1 "$TIMEOUT"); do
    if ! kill -0 "$PID" 2>/dev/null; then wait "$PID"; STATUS=$?; break; fi
    sleep 1
done
if [ -z "$STATUS" ]; then
    echo "✗ Panora reagiert nach ${TIMEOUT} s nicht – Stichprobe wird gesichert"
    /usr/bin/sample "$PID" 5 -file "${LOG%.log}-sample.txt" >/dev/null 2>&1 || true
    kill -9 "$PID" 2>/dev/null
    STATUS=124
    if [ -f "${LOG%.log}-sample.txt" ]; then
        echo "── Hauptthread (Auszug)"
        sed -n '/Thread_[0-9]*.*DispatchQueue_1/,/^ *$/p' "${LOG%.log}-sample.txt" | head -80
        sed -n '/Sort by top of stack/,/^$/p' "${LOG%.log}-sample.txt" | head -30
    fi
fi
tail -n 40 "$LOG" || true
if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 124 ]; then
    echo "✗ Panora beendet mit Status $STATUS"
    for _ in $(seq 1 20); do ls "$HOME"/Library/Logs/DiagnosticReports/Panora* >/dev/null 2>&1 && break; sleep 1; done
    for f in "$HOME"/Library/Logs/DiagnosticReports/Panora*; do
        [ -e "$f" ] || continue
        cp "$f" "$(dirname "$LOG")/"
        echo "── Absturzbericht $(basename "$f") (Auszug)"
        grep -E '"symbol"|Thread|abort|assert|crashed|Exception' "$f" | head -60 || true
    done
fi
exit "$STATUS"
