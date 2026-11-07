#!/bin/bash
# Erzeugt AETHER.xcodeproj aus project.yml (XcodeGen) neu – nötig, wenn Quelldateien hinzukommen oder wegfallen.
# Ein erzeugtes Projekt liegt bereits im Repository. Danach in Xcode öffnen oder:
#   xcodebuild -project AETHER.xcodeproj -scheme AETHER-App -configuration Release build
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(grep -m1 'VERSION:' .github/workflows/aether-macos.yml | sed -E 's/.*"(.*)".*/\1/')}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
command -v xcodegen >/dev/null || { echo "✗ XcodeGen fehlt – installieren mit: brew install xcodegen"; exit 1; }
mkdir -p Xcode
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > Xcode/Info.plist
test -f Resources/AppIcon.icns || { echo "✗ Resources/AppIcon.icns fehlt"; exit 1; }
xcodegen generate --spec project.yml
echo "✓ AETHER.xcodeproj erzeugt (Version $VERSION, Build $BUILD_NUMBER)"
