#!/bin/bash
# Profil des Leerlaufs mit Wiedergabe im Messlauf: startet den Messlauf (ML_BENCH_QUICK) und nimmt, sobald die
# Phase „Leerlauf mit Wiedergabe“ beginnt, 7 s lang Stichproben des Prozesses auf (/usr/bin/sample).
#   scripts/profile_idle.sh "App.app" ausgabeordner
set -uo pipefail
APP="$1"; OUT="$2"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
BIN="$APP/Contents/MacOS/MusicLibrary"
ML_BENCH_QUICK=1 BENCHMARK_TIMEOUT=900 scripts/run_benchmark.sh "$APP" "$OUT/bench" 10000 > "$OUT/bench.out" 2>&1 &
RUNNER=$!
for _ in $(seq 1 900); do
    if grep -q "Player öffnen/schließen" "$OUT/bench/run.log" 2>/dev/null; then break; fi
    kill -0 "$RUNNER" 2>/dev/null || break
    sleep 0.2
done
PID=$(pgrep -f "$BIN" | head -1)
if [ -n "$PID" ]; then
    sleep 1.2   # settle(1 s) vor der Messung
    /usr/bin/sample "$PID" 7 1 -mayDie -file "$OUT/leerlauf-sample.txt" > /dev/null 2>&1
    echo "Stichproben von PID $PID gespeichert"
else
    echo "Prozess nicht gefunden"
fi
wait "$RUNNER"
grep -E "Leerlauf|Großer" "$OUT/bench/benchmark.txt" || tail -5 "$OUT/bench.out"
