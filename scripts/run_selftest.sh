#!/bin/bash
# Startet die App im Selbsttestmodus und prüft das Ergebnis.
#   scripts/run_selftest.sh "/Applications/Android Bridge.app" out/selftest.json   (SNAPSHOT_ARCH=x86_64 für Rosetta)
set -euo pipefail
APP="$1"; OUT="$2"
mkdir -p "$(dirname "$OUT")"
BIN="$APP/Contents/MacOS/AndroidBridge"
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
set +e
perl -e 'alarm shift; exec @ARGV' 120 ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --selftest "$OUT" > "$OUT.log" 2>&1
STATUS=$?
set -e
tail -n 30 "$OUT.log" || true
test $STATUS -eq 0 || { echo "✗ App beendet mit Status $STATUS"; for f in "$HOME"/Library/Logs/DiagnosticReports/AndroidBridge*; do [ -e "$f" ] && cp "$f" "$(dirname "$OUT")/"; done; exit $STATUS; }
cat "$OUT"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('ok') else 1)" "$OUT"
echo "✓ Selbsttest bestanden"
