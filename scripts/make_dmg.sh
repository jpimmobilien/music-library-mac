#!/bin/bash
# Erstellt ORBIT-macOS-Universal.dmg (Hintergrund, Volume-Symbol, App, Verknüpfung „Programme“) und prüft sie:
# einhängen, Inhalt, Link, Architekturen, Signatur, Version, aushängen. Ablage im Projektverzeichnis und in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/ORBIT.app"
NAME="ORBIT-macOS-Universal.dmg"
OUT="dist/$NAME"
test -d "$APP" || { echo "Zuerst scripts/build_app.sh ausführen"; exit 1; }
mkdir -p dist
rm -f "$OUT" "$NAME"

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
ICON="build/ORBIT.app/Contents/Resources/AppIcon.icns"

"$PY" -m dmgbuild -s scripts/dmg_settings.py -D app="$APP" -D background="$BG" -D icon="$ICON" "ORBIT" "$OUT"

echo "▸ Prüfe DMG"
hdiutil verify "$OUT"
hdiutil imageinfo "$OUT" | grep -E "^Format:|Checksum Type|Partition Scheme|Total" || true
MNT="$(mktemp -d)"
hdiutil attach "$OUT" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true' EXIT
ls -la "$MNT"
test -d "$MNT/ORBIT.app" || { echo "✗ ORBIT.app fehlt in der DMG"; exit 1; }
test -L "$MNT/Programme" || { echo "✗ Verknüpfung „Programme“ fehlt"; exit 1; }
test "$(readlink "$MNT/Programme")" = "/Applications"
ls -la "$MNT"/.background* 2>/dev/null || true
echo "  Architekturen: $(lipo -archs "$MNT/ORBIT.app/Contents/MacOS/ORBIT")"
lipo "$MNT/ORBIT.app/Contents/MacOS/ORBIT" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$MNT/ORBIT.app"
echo "  Version: $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MNT/ORBIT.app/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$MNT/ORBIT.app/Contents/Info.plist"))"
cmp -s "$MNT/ORBIT.app/Contents/MacOS/ORBIT" "$APP/Contents/MacOS/ORBIT" || { echo "✗ Programmdatei in der DMG weicht vom Build ab"; exit 1; }
echo "  ✓ Programmdatei identisch mit dem Build"
hdiutil detach "$MNT" >/dev/null
trap - EXIT

cp "$OUT" "$NAME"
(cd dist && shasum -a 256 "$NAME" | tee "$NAME.sha256")
echo "✓ $OUT ($(du -h "$OUT" | cut -f1)) – Kopie im Projektverzeichnis: $(pwd)/$NAME"
