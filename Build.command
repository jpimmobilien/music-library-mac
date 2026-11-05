#!/bin/bash
# Doppelklick im Finder: baut „Music Library.app“ und „Music Library.dmg“ auf diesem Mac.
# Benötigt die Befehlszeilenwerkzeuge von Apple (werden bei Bedarf angeboten) oder Xcode.
cd "$(dirname "$0")" || exit 1
echo "Music Library – Build auf diesem Mac"
echo
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    echo "Die Befehlszeilenwerkzeuge von Apple fehlen. Das Installationsfenster wird geöffnet –"
    echo "nach der Installation diese Datei bitte erneut doppelklicken."
    xcode-select --install
    read -r -p "Eingabetaste zum Schließen …" _
    exit 1
fi
SWIFT_MAJOR="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\)\..*/\1/p' | head -1)"
if [ -n "$SWIFT_MAJOR" ] && [ "$SWIFT_MAJOR" -lt 6 ]; then
    echo "Gefunden: $(swift --version 2>&1 | head -1)"
    echo "Benötigt wird Xcode 16 oder neuer bzw. die Befehlszeilenwerkzeuge dazu (Swift 6)."
    echo "Bitte über die Softwareaktualisierung aktualisieren und erneut starten."
    read -r -p "Eingabetaste zum Schließen …" _
    exit 1
fi
set -e
scripts/build_app.sh
scripts/make_dmg.sh
echo
echo "Fertig: dist/Music Library.dmg"
open dist
read -r -p "Eingabetaste zum Schließen …" _
