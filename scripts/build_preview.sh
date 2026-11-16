#!/bin/bash
# Vorschau-Build ohne MLX für den Rechner, auf dem gebaut wird (z. B. Intel-Runner): Oberfläche, Selbsttest, Bilder.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
mkdir -p Xcode build logs
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > Xcode/Info.plist
command -v iconutil >/dev/null && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
xcodegen generate --spec project.yml
set +e
xcodebuild -project Panora.xcodeproj -scheme PanoraPreview -configuration Release -derivedDataPath build/preview \
    -clonedSourcePackagesDirPath build/spm -destination "platform=macOS,arch=$(uname -m)" \
    -skipPackagePluginValidation -skipMacroValidation ARCHS="$(uname -m)" EXCLUDED_ARCHS="" ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build > logs/xcodebuild-preview.txt 2>&1
STATUS=$?
set -e
grep -E "error:|BUILD (SUCCEEDED|FAILED)" logs/xcodebuild-preview.txt | sed "s|$(pwd)/||g" | sort -u | head -100
[ $STATUS -eq 0 ] || exit $STATUS
rm -rf build/PanoraPreview.app
ditto build/preview/Build/Products/Release/Panora.app build/PanoraPreview.app
codesign --force --deep --sign - build/PanoraPreview.app
echo "✓ build/PanoraPreview.app ($(lipo -archs build/PanoraPreview.app/Contents/MacOS/Panora))"
