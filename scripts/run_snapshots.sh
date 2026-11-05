#!/bin/bash
# Startet die App im Vorschaumodus (erfundene Beispielbibliothek, kein Ton, keine Benutzerdaten)
# und prüft, dass alle Ansichten in Hell und Dunkel erzeugt wurden.
#
#   scripts/run_snapshots.sh "build/Music Library.app" snapshots/glass
#   ML_FORCE_GLASS_FALLBACK=1 scripts/run_snapshots.sh "build/Music Library.app" snapshots/fallback
set -euo pipefail
APP="$1"
OUT="$2"
LIMIT="${SNAPSHOT_TIMEOUT:-900}"
mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"
# Pfad zur App (…/Music Library.app) oder direkt zur Programmdatei
if [ -f "$APP" ]; then BIN="$APP"; else BIN="$APP/Contents/MacOS/MusicLibrary"; fi
test -x "$BIN" || { echo "Programmdatei fehlt: $BIN"; exit 1; }

# SNAPSHOT_ARCH=x86_64 startet den Intel-Teil des Universal Binary (auf Apple Silicon über Rosetta)
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
echo "▸ Vorschaubilder → $OUT_ABS (Zeitlimit ${LIMIT}s, Rechner $(uname -m), App-Architektur ${SNAPSHOT_ARCH:-nativ})"
# perl-alarm als portables Zeitlimit (macOS hat kein timeout)
set +e
perl -e 'alarm shift; exec @ARGV' "$LIMIT" ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --snapshot "$OUT_ABS" > "$OUT_ABS/run.log" 2>&1
STATUS=$?
set -e
tail -n 40 "$OUT_ABS/run.log" || true
if [ $STATUS -ne 0 ]; then
    echo "✗ App beendet mit Status $STATUS"
    # Absturzbericht zur Auswertung mitnehmen
    sleep 8
    for f in "$HOME"/Library/Logs/DiagnosticReports/MusicLibrary*; do
        [ -e "$f" ] && cp "$f" "$OUT_ABS/" && echo "  Absturzbericht: $(basename "$f")"
    done
    exit $STATUS
fi
test -f "$OUT_ABS/manifest.json" || { echo "✗ manifest.json fehlt"; exit 1; }
COUNT=$(ls "$OUT_ABS"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "▸ $COUNT Bilder erzeugt"
python3 - "$OUT_ABS/manifest.json" <<'PY'
import json, sys, os
m = json.load(open(sys.argv[1]))
entries = m["images"]
print(f"  macOS {m['macOS']} · {m['architecture']} · Liquid Glass: {m['liquidGlass']} · Inter: {m['interFont']}")
bad = [e for e in entries if not os.path.exists(os.path.join(os.path.dirname(sys.argv[1]), e["file"]))]
print(f"  Einträge: {len(entries)}, fehlende Dateien: {len(bad)}")
methods = {}
for e in entries:
    methods[e["method"]] = methods.get(e["method"], 0) + 1
    if e["method"] == "failed":
        print("  ✗", e["file"])
        bad.append(e)
print("  Aufnahmeverfahren:", methods)
sys.exit(1 if bad or not entries else 0)
PY
echo "✓ Vorschaubilder vollständig"
