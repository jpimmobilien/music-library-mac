#!/bin/bash
# Erstellt dist/AndroidBridge.dmg (Hintergrundbild, App, Verknüpfung „Programme“) und prüft sie.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Android Bridge.app"
OUT="dist/AndroidBridge.dmg"
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

"$PY" -m dmgbuild -s scripts/dmg_settings.py -D app="$APP" -D background="$BG" "Android Bridge" "$OUT"

echo "▸ Prüfe DMG …"
hdiutil verify "$OUT"
MNT="$(mktemp -d)"
hdiutil attach "$OUT" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
ls -la "$MNT"
test -d "$MNT/Android Bridge.app"
test -L "$MNT/Programme"
test "$(readlink "$MNT/Programme")" = "/Applications"
lipo "$MNT/Android Bridge.app/Contents/MacOS/AndroidBridge" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$MNT/Android Bridge.app"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MNT/Android Bridge.app/Contents/Info.plist"
hdiutil detach "$MNT" >/dev/null
(cd dist && shasum -a 256 AndroidBridge.dmg | tee AndroidBridge.dmg.sha256)
echo "✓ $OUT"
