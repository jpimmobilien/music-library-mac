#!/bin/bash
# Baut „Music Library.app“ als Universal Binary (arm64 + x86_64), ad-hoc signiert
# (mit SIGN_IDENTITY="Developer ID Application: …" stattdessen mit Developer-ID-Zertifikat).
#
#   scripts/build_app.sh                 → build/Music Library.app
#   VERSION=1.0.0 BUILD_NUMBER=42 scripts/build_app.sh
#
# Voraussetzung: macOS 14.5 oder neuer mit Xcode 16 (oder neuer) bzw. den passenden Befehlszeilenwerkzeugen
# (xcode-select --install). Ältere Swift-Versionen (Xcode 15) werden nicht unterstützt.
# Liquid Glass wird nur mit dem macOS-26-SDK einkompiliert; ältere SDKs bauen die gleichwertige Rückfalllösung.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-2.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/Music Library.app"

echo "▸ Swift: $(swift --version 2>&1 | head -1)"
# Je Architektur getrennt bauen und mit lipo zusammenfügen – funktioniert mit Xcode und mit den
# Befehlszeilenwerkzeugen allein (der Mehrarchitektur-Build von SwiftPM bräuchte Xcode).
SLICES=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx13.0"
    echo "▸ Baue $ARCH ($TRIPLE) …"
    swift build -c release --triple "$TRIPLE" --product MusicLibrary
    BIN_DIR="$(swift build -c release --triple "$TRIPLE" --show-bin-path)"
    test -f "$BIN_DIR/MusicLibrary" || { echo "Binärdatei fehlt: $BIN_DIR/MusicLibrary"; exit 1; }
    SLICES+=("$BIN_DIR/MusicLibrary")
done
mkdir -p build
BIN="build/MusicLibrary-universal"
lipo -create "${SLICES[@]}" -output "$BIN"

echo "▸ Erstelle App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Resources/GenreArt" "$APP/Contents/Resources/Licenses"
cp "$BIN" "$APP/Contents/MacOS/MusicLibrary"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp Resources/GenreArt/*.webp "$APP/Contents/Resources/GenreArt/"
cp Resources/Licenses/* "$APP/Contents/Resources/Licenses/"


echo "▸ Prüfe Architekturen …"
lipo -info "$APP/Contents/MacOS/MusicLibrary"
lipo "$APP/Contents/MacOS/MusicLibrary" -verify_arch arm64 x86_64

echo "▸ Mindest-macOS je Architektur:"
otool -l "$APP/Contents/MacOS/MusicLibrary" -arch arm64 | grep -A3 LC_BUILD_VERSION | grep minos || true
otool -l "$APP/Contents/MacOS/MusicLibrary" -arch x86_64 | grep -A3 LC_BUILD_VERSION | grep minos || true

xattr -cr "$APP"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    # Developer-ID-Signatur mit „Hardened Runtime“ (Voraussetzung für die Beglaubigung durch Apple)
    echo "▸ Signatur mit „$SIGN_IDENTITY“ …"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/MusicLibrary"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    echo "▸ Ad-hoc-Signatur …"
    codesign --force --deep --sign - --timestamp=none "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "✓ $APP"
