#!/bin/bash
# Erzeugt Bildschirmfotos aller Hauptansichten (hell/dunkel) zur Sichtprüfung.
#   scripts/run_snapshots.sh "build/Android Bridge.app" snapshots/macos26
# Jede Szenario-Gruppe läuft in einem eigenen Prozess: Die virtuelle Grafik der Intel-Build-Rechner bricht nach
# einer begrenzten Zahl Aufnahmen ab (MTLLoader „Target device architecture is nil“) – so gehen nicht alle
# folgenden Ansichten verloren.
set -uo pipefail
APP="$1"; OUT="$2"
mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"
BIN="$APP/Contents/MacOS/AndroidBridge"
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
GROUPS_LIST="${SNAPSHOT_GROUPS:-01 02 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 03- 03b 03c 03d}"
FAILED=0
for G in $GROUPS_LIST; do
  echo "== Gruppe $G" >> "$OUT_ABS/run.log"
  SNAPSHOT_ONLY="$G" perl -e 'alarm shift; exec @ARGV' 120 ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --snapshot "$OUT_ABS" >> "$OUT_ABS/run.log" 2>&1
  S=$?
  if [ $S -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "✗ Gruppe $G: Status $S" | tee -a "$OUT_ABS/run.log"
  fi
done
for f in "$HOME"/Library/Logs/DiagnosticReports/AndroidBridge*; do [ -e "$f" ] && cp "$f" "$OUT_ABS/"; done
N=$(ls "$OUT_ABS"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "▸ $N Bilder, $FAILED Gruppen mit Abbruch"
test "$N" -gt 0
