#!/bin/bash
# Doppelklick im Finder: baut AETHER.app und AETHER-macOS-Universal.dmg auf diesem Mac.
cd "$(dirname "$0")" || exit 1
echo "AETHER – Universal-Build auf diesem Mac"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    echo "Die Befehlszeilenwerkzeuge von Apple fehlen – das Installationsfenster wird geöffnet."
    xcode-select --install
    read -r -p "Eingabetaste zum Schließen …" _
    exit 1
fi
set -e
swift test
CLEAN=1 scripts/build_app.sh
scripts/make_dmg.sh
echo
echo "Fertig: $(pwd)/AETHER-macOS-Universal.dmg"
open -R AETHER-macOS-Universal.dmg
read -r -p "Eingabetaste zum Schließen …" _
