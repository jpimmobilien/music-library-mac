# Installation – AETHER für macOS

**Voraussetzungen:** macOS 13 Ventura oder neuer, Apple Silicon (M1 und neuer) oder Intel-Mac. Die App ist ein
**Universal Binary**: Dieselbe Datei läuft auf beiden Prozessortypen nativ. Auf macOS 26 Tahoe nutzt sie natives Liquid
Glass, auf macOS 13–15 eine gleichwertige Glasdarstellung.

## 1. Installieren

1. `AETHER-macOS-Universal.dmg` doppelklicken.
2. Im Fenster **AETHER** auf den Ordner **Programme** ziehen.
3. Die DMG auswerfen.

## 2. Erster Start

AETHER ist **ad-hoc signiert**, aber nicht von Apple notariell beglaubigt (dafür ist ein kostenpflichtiges
Apple-Entwicklerkonto nötig). macOS fragt deshalb beim **ersten** Start einmal nach.

**macOS 15 Sequoia und macOS 26 Tahoe**

1. AETHER im Programme-Ordner doppelklicken. Es erscheint „Apple konnte nicht überprüfen, ob ‚AETHER‘ frei von
   Schadsoftware ist …“. Dort **Fertig** wählen.
2. **Systemeinstellungen → Datenschutz & Sicherheit** öffnen und ganz nach unten scrollen.
3. Bei „‚AETHER‘ wurde blockiert …“ auf **Dennoch öffnen** klicken, bestätigen und im nächsten Dialog nochmals
   **Dennoch öffnen** wählen.

**macOS 13 Ventura und macOS 14 Sonoma**

**Rechtsklick** auf AETHER → **Öffnen** → nochmals **Öffnen**.

**Alternative (Terminal):** `xattr -dr com.apple.quarantine /Applications/AETHER.app`

## 3. Berechtigungen

Version 0.2.0 braucht **keine** Freigaben: keine Administratorrechte, keinen Festplattenvollzugriff, keine
Ortungsdienste. Spätere Versionen fragen nur bei Bedarf und mit Erklärung:

- Ordnerzugriff, sobald der Dateimanager (Phase 6) Schreibtisch, Dokumente oder Downloads öffnet;
- Ortungsdienste nur für den WLAN-Namen (Phase 7, Vorgabe von Apple).

## 4. Daten und Deinstallation

Einstellungen liegen in `~/Library/Preferences/de.projectaether.macos.plist`. Zum Deinstallieren die App in den
Papierkorb legen und, falls gewünscht, diese Datei löschen. AETHER legt keine weiteren Dateien an und startet keine
Hintergrunddienste.
