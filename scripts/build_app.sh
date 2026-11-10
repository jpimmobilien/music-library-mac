#!/bin/bash
# Baut „Android Bridge.app“ als Universal Binary (arm64 + x86_64).
# Ad-hoc signiert; mit SIGN_IDENTITY="Developer ID Application: …" stattdessen mit Developer-ID-Zertifikat.
#
#   scripts/build_app.sh                         → build/Android Bridge.app
#   VERSION=1.0.0 BUILD_NUMBER=42 scripts/build_app.sh
#
# Voraussetzung: Xcode 16 oder neuer bzw. die passenden Befehlszeilenwerkzeuge.
# Liquid Glass wird nur mit dem macOS-26-SDK einkompiliert; ältere SDKs bauen die Rückfalldarstellung.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-5.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/Android Bridge.app"
EXE="AndroidBridge"

echo "▸ Swift: $(swift --version 2>&1 | head -1)"
echo "▸ SDK:   $(xcrun --show-sdk-version 2>/dev/null || echo '?')"
SLICES=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx13.0"
    echo "▸ Baue $ARCH ($TRIPLE) …"
    swift build -c release --triple "$TRIPLE" --product "$EXE"
    BIN_DIR="$(swift build -c release --triple "$TRIPLE" --show-bin-path)"
    test -f "$BIN_DIR/$EXE" || { echo "Programmdatei fehlt: $BIN_DIR/$EXE"; exit 1; }
    SLICES+=("$BIN_DIR/$EXE")
done
mkdir -p build
lipo -create "${SLICES[@]}" -output "build/$EXE-universal"

echo "▸ Erstelle App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "build/$EXE-universal" "$APP/Contents/MacOS/$EXE"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if command -v iconutil >/dev/null; then
    iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
else
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Prüfe Architekturen …"
lipo -info "$APP/Contents/MacOS/$EXE"
lipo "$APP/Contents/MacOS/$EXE" -verify_arch arm64 x86_64
echo "▸ Mindest-macOS je Architektur:"
otool -l -arch arm64 "$APP/Contents/MacOS/$EXE" | grep -A3 LC_BUILD_VERSION | grep minos || true
otool -l -arch x86_64 "$APP/Contents/MacOS/$EXE" | grep -A3 LC_BUILD_VERSION | grep minos || true
echo "▸ Verknüpfte Bibliotheken (nur System-Frameworks erwartet):"
LIBS="$(otool -L "$APP/Contents/MacOS/$EXE" | grep -E "^[[:space:]]+/" | awk '{print $1}' | sort -u)"
echo "$LIBS"
FOREIGN="$(echo "$LIBS" | grep -v -E "^(/System/Library/|/usr/lib/)" || true)"
if [ -n "$FOREIGN" ]; then
    echo "✗ Nicht-System-Bibliothek verknüpft: $FOREIGN"; exit 1
fi
echo "✓ Nur Systembibliotheken – nichts muss mitgeliefert werden"

xattr -cr "$APP"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "▸ Signatur mit „$SIGN_IDENTITY“ (Hardened Runtime) …"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$EXE"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    echo "▸ Ad-hoc-Signatur …"
    codesign --force --deep --sign - --timestamp=none "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "✓ $APP"
