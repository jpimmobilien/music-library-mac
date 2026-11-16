#!/bin/bash
# Baut Panora.app (Apple Silicon, arm64) mit XcodeGen + xcodebuild, signiert ad hoc und prüft das Bundle.
# Läuft auch auf Intel-Macs (Cross-Compile für arm64) – starten lässt sich die App dann nur auf Apple Silicon.
#   VERSION=0.1.0 BUILD_NUMBER=1 scripts/build_app.sh
# Voraussetzungen: Xcode 26 oder neuer (mit Metal Toolchain), XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
mkdir -p Xcode build logs

echo "▸ Info.plist (Version $VERSION, Build $BUILD_NUMBER)"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > Xcode/Info.plist

if command -v iconutil >/dev/null; then
    echo "▸ App-Symbol (iconutil)"
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi

command -v xcodegen >/dev/null || { echo "✗ XcodeGen fehlt – brew install xcodegen"; exit 1; }
xcodegen generate --spec project.yml

echo "▸ Pakete auflösen"
xcodebuild -resolvePackageDependencies -project Panora.xcodeproj -scheme Panora -clonedSourcePackagesDirPath build/spm \
    > logs/resolve.txt 2>&1 || { tail -40 logs/resolve.txt; exit 1; }
grep -E "Resolved source packages|: https" logs/resolve.txt | head -20 || true

echo "▸ Kompilieren (Release, arm64)"
set +e
xcodebuild -project Panora.xcodeproj -scheme Panora -configuration Release \
    -derivedDataPath build/xcode -clonedSourcePackagesDirPath build/spm \
    -destination 'generic/platform=macOS' \
    -skipPackagePluginValidation -skipMacroValidation \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build > logs/xcodebuild.txt 2>&1
STATUS=$?
set -e
grep -E "error:|BUILD (SUCCEEDED|FAILED)" logs/xcodebuild.txt | sed "s|$(pwd)/||g" | sort -u | head -150 > logs/errors.txt || true
grep -E "warning:" logs/xcodebuild.txt | grep "Sources/Panora" | sed "s|$(pwd)/||g" | sort -u | head -200 > logs/warnings.txt || true
cat logs/errors.txt
if [ $STATUS -ne 0 ]; then
    echo "✗ xcodebuild fehlgeschlagen (Status $STATUS)"
    tail -60 logs/xcodebuild.txt
    exit $STATUS
fi

APP_SRC="build/xcode/Build/Products/Release/Panora.app"
rm -rf build/Panora.app
ditto "$APP_SRC" build/Panora.app
APP="build/Panora.app"

echo "▸ Bundle prüfen"
test -x "$APP/Contents/MacOS/Panora"
echo "  Architektur: $(lipo -archs "$APP/Contents/MacOS/Panora")"
lipo "$APP/Contents/MacOS/Panora" -verify_arch arm64
test -f "$APP/Contents/Resources/AppIcon.icns" || { echo "✗ AppIcon.icns fehlt"; exit 1; }
METALLIB="$(find "$APP" -name '*.metallib' | head -1)"
if [ -z "$METALLIB" ]; then
    echo "✗ Keine MLX-Metal-Shader (*.metallib) im Bundle – MLX würde zur Laufzeit scheitern"
    find "$APP" -maxdepth 4 | head -60
    exit 1
fi
echo "  Metal-Shader: ${METALLIB#$APP/}"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"

echo "▸ Ad-hoc-Signatur"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
du -sh "$APP"
echo "✓ $APP"
