#!/bin/bash
# Erzeugt Bildschirmfotos (alle Themes, mehrere Fenstergrößen) mit echten Messwerten zur Sichtprüfung.
#   scripts/run_snapshots.sh "build/AETHER.app" snapshots/macos26
# Stürzt die App bei einem Szenario ab (z. B. Metal-Assertion auf virtuellen Intel-Macs ohne Grafikgerät), wird der
# Absturzbericht gesichert, das Szenario im Protokoll benannt und der Rest in einem neuen Prozess fortgesetzt.
# Der Exit-Status bleibt dann ≠ 0 – ein Absturz wird nie verschwiegen.
set -euo pipefail
APP="$1"; OUT="$2"
mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"
BIN="$APP/Contents/MacOS/AETHER"
RUNNER=()
if [ -n "${SNAPSHOT_ARCH:-}" ]; then RUNNER=(arch "-$SNAPSHOT_ARCH"); fi
# SNAPSHOT_LANG=de: Oberfläche auf Deutsch (wie „Sprache der App“ in den Systemeinstellungen)
LANG_ARGS=()
if [ -n "${SNAPSHOT_LANG:-}" ]; then LANG_ARGS=(-AppleLanguages "($SNAPSHOT_LANG)" -AppleLocale "${SNAPSHOT_LANG}_DE"); fi

SKIP=""
CRASHED=""
FINAL=0
: > "$OUT_ABS/run.log"
for ATTEMPT in 1 2 3 4 5 6; do
    rm -f "$OUT_ABS/current.txt"
    set +e
    AETHER_SNAPSHOT_SKIP="$SKIP" perl -e 'alarm shift; exec @ARGV' 600 ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" --snapshot "$OUT_ABS" \
        ${LANG_ARGS[@]+"${LANG_ARGS[@]}"} >> "$OUT_ABS/run.log" 2>&1
    STATUS=$?
    set -e
    if [ $STATUS -eq 0 ]; then break; fi
    FINAL=$STATUS
    echo "✗ App beendet mit Status $STATUS (Versuch $ATTEMPT)" | tee -a "$OUT_ABS/run.log"
    for _ in $(seq 1 30); do ls "$HOME"/Library/Logs/DiagnosticReports/AETHER* >/dev/null 2>&1 && break; sleep 1; done
    for f in "$HOME"/Library/Logs/DiagnosticReports/AETHER*; do [ -e "$f" ] && mv "$f" "$OUT_ABS/"; done
    CURRENT="$(cat "$OUT_ABS/current.txt" 2>/dev/null || true)"
    [ -n "$CURRENT" ] || break
    echo "✗ Absturz bei Szenario: $CURRENT" | tee -a "$OUT_ABS/run.log"
    CRASHED="$CRASHED $CURRENT"
    DONE="$(ls "$OUT_ABS"/*.png 2>/dev/null | xargs -n1 basename 2>/dev/null | sed -E 's/-(en|de)-[0-9]+x[0-9]+\.png$//' | tr '\n' ',')"
    SKIP="${DONE}$(echo $CRASHED | tr ' ' ',')"
done
tail -n 40 "$OUT_ABS/run.log" || true
if [ -n "$CRASHED" ]; then
    echo "✗ Abgestürzte Szenarien:$CRASHED"
    exit "${FINAL:-1}"
fi
test -f "$OUT_ABS/manifest.json" || { echo "✗ manifest.json fehlt"; exit 1; }
echo "▸ $(ls "$OUT_ABS"/*.png 2>/dev/null | wc -l | tr -d ' ') Bilder"
