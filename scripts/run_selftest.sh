#!/bin/bash
# Startet AETHER im Selbsttestmodus (echte Messungen) und prüft das Ergebnis.
#   scripts/run_selftest.sh "/Applications/AETHER.app" out/selftest.json      (SNAPSHOT_ARCH=x86_64 für Rosetta)
set -euo pipefail
APP="$1"; OUT="$2"
mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
BIN="$APP/Contents/MacOS/AETHER"
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
set +e
# -ApplePersistenceIgnoreState: keine Fensterwiederherstellung – nach einem früheren Absturz würde macOS sonst beim
# Start fragen, ob die Fenster wieder geöffnet werden sollen, und der Selbsttest bliebe an diesem Dialog hängen.
perl -e 'alarm shift; exec @ARGV' 180 ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --selftest "$OUT_ABS" -ApplePersistenceIgnoreState YES > "$OUT_ABS.log" 2>&1
STATUS=$?
set -e
tail -n 40 "$OUT_ABS.log" || true
if [ $STATUS -ne 0 ]; then
    echo "✗ App beendet mit Status $STATUS"
    # Absturzbericht abwarten (ReportCrash schreibt ihn erst nach einigen Sekunden) und ins Protokoll übernehmen
    for _ in $(seq 1 30); do ls "$HOME"/Library/Logs/DiagnosticReports/AETHER* >/dev/null 2>&1 && break; sleep 1; done
    for f in "$HOME"/Library/Logs/DiagnosticReports/AETHER*; do
        [ -e "$f" ] || continue
        cp "$f" "$(dirname "$OUT_ABS")/"
        echo "── Absturzbericht $(basename "$f") (Auszug)"; grep -E '"symbol"|"imageIndex"|Thread|abort|assert|crashed' "$f" | head -80 || true
    done
    exit $STATUS
fi
test -f "$OUT_ABS" || { echo "✗ Ergebnisdatei fehlt"; exit 1; }
cat "$OUT_ABS"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); bad=[c['name'] for c in d['checks'] if not c['ok']]; print('Fehlgeschlagen:', bad) if bad else None; sys.exit(0 if d.get('ok') else 1)" "$OUT_ABS"
echo "✓ Selbsttest bestanden ($(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['process'], 'Rosetta' if d['translated'] else 'nativ', d['macOS'])" "$OUT_ABS"))"
