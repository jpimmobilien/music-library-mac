#!/bin/bash
# Erstellt „Music Library.dmg“ mit Hintergrundbild, App und Verknüpfung zum Programme-Ordner.
# Nutzt dmgbuild (Python, ohne Finder/AppleScript – zuverlässig auf CI-Maschinen).
#
#   scripts/make_dmg.sh            → dist/Music Library.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Music Library.app"
OUT="dist/Music Library.dmg"
test -d "$APP" || { echo "Zuerst scripts/build_app.sh ausführen"; exit 1; }
mkdir -p dist
rm -f "$OUT"

# dmgbuild in eigener virtueller Umgebung (Homebrew-Python erlaubt keine globalen pip-Installationen)
PY="build/dmg-venv/bin/python3"
if [ ! -x "$PY" ]; then
    python3 -m venv build/dmg-venv
    "$PY" -m pip install --quiet --upgrade pip
    "$PY" -m pip install --quiet "dmgbuild>=1.6,<2"
fi

BG="Resources/DMG/background.png"
if command -v tiffutil >/dev/null && [ -f Resources/DMG/background@2x.png ]; then
    mkdir -p build
    tiffutil -cathidpicheck Resources/DMG/background.png Resources/DMG/background@2x.png -out build/dmg-background.tiff
    BG="build/dmg-background.tiff"
fi

"$PY" -m dmgbuild -s scripts/dmg_settings.py -D app="$APP" -D background="$BG" "Music Library" "$OUT"

echo "▸ Prüfe DMG …"
hdiutil verify "$OUT"
MNT="$(mktemp -d)"
hdiutil attach "$OUT" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
ls -la "$MNT"
test -d "$MNT/Music Library.app"
test -L "$MNT/Programme" || test -L "$MNT/Applications"
codesign --verify --deep --strict "$MNT/Music Library.app"
hdiutil detach "$MNT" >/dev/null
shasum -a 256 "$OUT" | tee "$OUT.sha256"
echo "✓ $OUT"
