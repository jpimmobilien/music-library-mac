#!/bin/bash
# Erstellt Panora.dmg (Hintergrund, Volume-Symbol, App, Verknüpfung „Programme“) und prüft sie.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Panora.app"
NAME="Panora.dmg"
OUT="dist/$NAME"
test -d "$APP" || { echo "Zuerst scripts/build_app.sh ausführen"; exit 1; }
mkdir -p dist
rm -f "$OUT"

PY="build/dmg-venv/bin/python3"
if [ ! -x "$PY" ]; then
    python3 -m venv build/dmg-venv
    "$PY" -m pip install --quiet --upgrade pip
    "$PY" -m pip install --quiet "dmgbuild>=1.6,<2"
fi

BG="Resources/DMG/background.png"
if command -v tiffutil >/dev/null && [ -f Resources/DMG/background@2x.png ]; then
    tiffutil -cathidpicheck Resources/DMG/background.png Resources/DMG/background@2x.png -out build/dmg-background.tiff
    BG="build/dmg-background.tiff"
fi
ICON="$APP/Contents/Resources/AppIcon.icns"

"$PY" -m dmgbuild -s scripts/dmg_settings.py -D app="$APP" -D background="$BG" -D icon="$ICON" "Panora" "$OUT"

echo "▸ Prüfe DMG"
hdiutil verify "$OUT"
MNT="$(mktemp -d)"
hdiutil attach "$OUT" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true' EXIT
ls -la "$MNT"
test -d "$MNT/Panora.app" || { echo "✗ Panora.app fehlt in der DMG"; exit 1; }
test -L "$MNT/Programme" || { echo "✗ Verknüpfung „Programme“ fehlt"; exit 1; }
codesign --verify --deep --strict "$MNT/Panora.app"
cmp -s "$MNT/Panora.app/Contents/MacOS/Panora" "$APP/Contents/MacOS/Panora" || { echo "✗ Programmdatei weicht ab"; exit 1; }
hdiutil detach "$MNT" >/dev/null
trap - EXIT
(cd dist && shasum -a 256 "$NAME" | tee "$NAME.sha256")
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
