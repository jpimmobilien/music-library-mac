#!/bin/bash
# Erstellt AETHER-macOS-Universal.dmg (Hintergrund, Volume-Symbol, App, Verknüpfung „Programme“) und prüft sie:
# einhängen, Inhalt, Link, Architekturen, Signatur, Version, aushängen. Ablage im Projektverzeichnis und in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/AETHER.app"
NAME="AETHER-macOS-Universal.dmg"
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
ICON="build/AETHER.app/Contents/Resources/AppIcon.icns"

"$PY" -m dmgbuild -s scripts/dmg_settings.py -D app="$APP" -D background="$BG" -D icon="$ICON" "AETHER" "$OUT"

echo "▸ Prüfe DMG"
hdiutil verify "$OUT"
hdiutil imageinfo "$OUT" | grep -E "^Format:|Checksum Type|Partition Scheme|Total" || true
MNT="$(mktemp -d)"
hdiutil attach "$OUT" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true' EXIT
ls -la "$MNT"
test -d "$MNT/AETHER.app" || { echo "✗ AETHER.app fehlt in der DMG"; exit 1; }
test -L "$MNT/Programme" || { echo "✗ Verknüpfung „Programme“ fehlt"; exit 1; }
test "$(readlink "$MNT/Programme")" = "/Applications"
ls -la "$MNT"/.background* 2>/dev/null || true
echo "  Architekturen: $(lipo -archs "$MNT/AETHER.app/Contents/MacOS/AETHER")"
lipo "$MNT/AETHER.app/Contents/MacOS/AETHER" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$MNT/AETHER.app"
echo "  Version: $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MNT/AETHER.app/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$MNT/AETHER.app/Contents/Info.plist"))"
cmp -s "$MNT/AETHER.app/Contents/MacOS/AETHER" "$APP/Contents/MacOS/AETHER" || { echo "✗ Programmdatei in der DMG weicht vom Build ab"; exit 1; }
echo "  ✓ Programmdatei identisch mit dem Build"
hdiutil detach "$MNT" >/dev/null
trap - EXIT

cp "$OUT" "$NAME"
(cd dist && shasum -a 256 "$NAME" | tee "$NAME.sha256")
echo "✓ $OUT ($(du -h "$OUT" | cut -f1)) – Kopie im Projektverzeichnis: $(pwd)/$NAME"
