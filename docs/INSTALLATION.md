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

AETHER braucht **keine Administratorrechte** und startet keine Hintergrunddienste. macOS fragt nur nach, wenn Sie eine
Funktion nutzen, die es schützt – jeweils mit einer Erklärung von AETHER:

| Wann | Was macOS fragt | Ohne Freigabe |
|---|---|---|
| Sie öffnen unter **Dateien** Schreibtisch, Dokumente oder Downloads bzw. analysieren sie unter **Speicher** | Zugriff auf diesen Ordner | der Ordner zeigt „Kein Zugriff“ mit Knopf zu den Datenschutz-Einstellungen |
| Wechselmedien oder Netzlaufwerke öffnen | Zugriff auf Wechselmedien bzw. Netzlaufwerke | wie oben |
| **Netzwerk → WLAN → „Ortungsfreigabe erlauben …“** (nur auf Klick) | Ortungsdienste – Apple gibt den WLAN-Namen nur so heraus | beim Netzwerknamen steht „Ortungsfreigabe nötig“, alle anderen WLAN-Werte bleiben sichtbar |
| optional: vollständige Speicheranalyse (z. B. Mail, Nachrichten) | Festplattenvollzugriff (selbst in den Systemeinstellungen zu erteilen) | diese Ordner zählen als „nicht lesbar“ |

## 4. Menüleiste und Live-Monitor

- **Live-Monitor:** Fenster → Live-Monitor (⌥⌘M).
- **Menüleiste:** Einstellungen → „In der Menüleiste zeigen“. Dann läuft AETHER auch bei geschlossenem Fenster weiter
  (Messung höchstens alle 5 Sekunden) und wird über das Menüleistensymbol → „Beenden“ geschlossen.

## 5. Daten und Deinstallation

- Einstellungen: `~/Library/Preferences/de.projectaether.macos.plist`
- Verlauf (nur wenn eingeschaltet): `~/Library/Application Support/AETHER/history.sqlite` – in den Einstellungen löschbar

Zum Deinstallieren die App in den Papierkorb legen und, falls gewünscht, diese beiden Dateien löschen.
