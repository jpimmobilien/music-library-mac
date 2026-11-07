#!/bin/bash
# Baut AETHER.app als Universal Binary (arm64 + x86_64) und prüft das Ergebnis.
#
#   scripts/build_app.sh                       → build/AETHER.app
#   CLEAN=1 VERSION=0.2.0 BUILD_NUMBER=7 scripts/build_app.sh
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build_app.sh   (Hardened Runtime, für Notarisierung)
#
# Ohne SIGN_IDENTITY: ad-hoc signiert (keine erfundenen Zertifikate).
# Voraussetzung: Xcode 16+ bzw. die Befehlszeilenwerkzeuge. Liquid Glass wird nur mit dem macOS-26-SDK einkompiliert;
# ältere SDKs bauen die gleichwertige Rückfalldarstellung.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/AETHER.app"
EXE="AETHER"
MIN_MACOS="13.0"

if [ "${CLEAN:-0}" = "1" ]; then
    echo "▸ Clean Build: .build und build werden entfernt"
    rm -rf .build build
fi

echo "▸ Swift: $(swift --version 2>&1 | head -1)"
echo "▸ SDK:   $(xcrun --show-sdk-version 2>/dev/null || echo '?')"
echo "▸ Lokalisierung prüfen"
python3 tools/check_l10n.py

SLICES=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx$MIN_MACOS"
    echo "▸ Baue $ARCH ($TRIPLE) …"
    swift build -c release --triple "$TRIPLE" --product "$EXE"
    BIN_DIR="$(swift build -c release --triple "$TRIPLE" --show-bin-path)"
    test -f "$BIN_DIR/$EXE" || { echo "✗ Programmdatei fehlt: $BIN_DIR/$EXE"; exit 1; }
    ARCHS_SLICE="$(lipo -archs "$BIN_DIR/$EXE")"
    test "$ARCHS_SLICE" = "$ARCH" || { echo "✗ $BIN_DIR/$EXE enthält „$ARCHS_SLICE“ statt $ARCH"; exit 1; }
    SLICES+=("$BIN_DIR/$EXE")
done
mkdir -p build
lipo -create "${SLICES[@]}" -output "build/$EXE-universal"

echo "▸ App-Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "build/$EXE-universal" "$APP/Contents/MacOS/$EXE"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
for LANG_DIR in Resources/Localization/*.lproj; do
    cp -R "$LANG_DIR" "$APP/Contents/Resources/"
done
if command -v iconutil >/dev/null; then
    iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
else
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Prüfe Architekturen"
lipo -archs "$APP/Contents/MacOS/$EXE"
lipo "$APP/Contents/MacOS/$EXE" -verify_arch arm64 x86_64
echo "  ✓ arm64 und x86_64 nativ enthalten"
for ARCH in arm64 x86_64; do
    MINOS="$(otool -l -arch "$ARCH" "$APP/Contents/MacOS/$EXE" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
    SDK="$(otool -l -arch "$ARCH" "$APP/Contents/MacOS/$EXE" | awk '/LC_BUILD_VERSION/{f=1} f&&/sdk/{print $2; exit}')"
    echo "  $ARCH: macOS ab $MINOS, SDK $SDK"
    test "$MINOS" = "$MIN_MACOS" || { echo "✗ Mindestversion $ARCH ist $MINOS statt $MIN_MACOS"; exit 1; }
done

echo "▸ Prüfe Ressourcen"
plutil -lint "$APP/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")" = "$EXE"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION"
test -s "$APP/Contents/Resources/AppIcon.icns"
for L in en de; do
    test -s "$APP/Contents/Resources/$L.lproj/Localizable.strings" || { echo "✗ $L.lproj fehlt"; exit 1; }
    plutil -lint "$APP/Contents/Resources/$L.lproj/Localizable.strings"
    plutil -lint "$APP/Contents/Resources/$L.lproj/InfoPlist.strings"
done
echo "  ✓ Info.plist, Icon, Lokalisierungen (en, de)"

echo "▸ Verknüpfte Bibliotheken (nur System-Frameworks erlaubt)"
LIBS="$(otool -L "$APP/Contents/MacOS/$EXE" | grep -E "^[[:space:]]+/" | awk '{print $1}' | sort -u)"
echo "$LIBS"
FOREIGN="$(echo "$LIBS" | grep -v -E "^(/System/Library/|/usr/lib/)" || true)"
test -z "$FOREIGN" || { echo "✗ Nicht-System-Bibliothek verknüpft: $FOREIGN"; exit 1; }
echo "  ✓ Nur Systembibliotheken"

echo "▸ Keine Netzwerkverbindungen (Datenschutz): Programmdatei darf keine Verbindungs-APIs referenzieren"
for ARCH in arm64 x86_64; do
    NET="$(nm -u -arch "$ARCH" "$APP/Contents/MacOS/$EXE" 2>/dev/null \
        | grep -E 'NSURLSession|NSURLConnection|_nw_connection|_nw_endpoint|_CFSocket|_CFStreamCreatePairWithSocket|^_connect$|^_socket$|URLSession' || true)"
    test -z "$NET" || { echo "✗ $ARCH referenziert Netzwerk-APIs:"; echo "$NET"; exit 1; }
done
echo "  ✓ keine Netzwerk-APIs referenziert"

xattr -cr "$APP"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "▸ Signatur mit „$SIGN_IDENTITY“ (Hardened Runtime, Zeitstempel)"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$EXE"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    echo "▸ Ad-hoc-Signatur (keine Developer-ID hinterlegt)"
    codesign --force --deep --sign - --timestamp=none "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Format|Signature|flags|TeamIdentifier" || true
echo "✓ $APP ($(du -sh "$APP" | cut -f1))"
