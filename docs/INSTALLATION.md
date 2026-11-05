# Installation – Music Library für macOS

**Voraussetzungen:** macOS 13 Ventura oder neuer · Apple Silicon (M1 und neuer) oder Intel-Mac.
Die App ist ein **Universal Binary** – dieselbe Datei läuft auf beiden Prozessortypen.
Auf macOS 26 Tahoe nutzt sie Liquid Glass, auf macOS 13–15 eine gleichwertige Glas-Darstellung.

## 1. Installieren

1. `Music Library.dmg` doppelklicken.
2. Im Fenster das App-Symbol auf den Ordner **Programme** ziehen.
3. DMG auswerfen (Auswerfen-Taste im Finder).

## 2. Erster Start

Die App ist **ad-hoc signiert**, aber nicht von Apple notariell beglaubigt (dafür ist ein kostenpflichtiges
Apple-Entwicklerkonto nötig). macOS fragt deshalb beim **ersten** Start nach. Danach startet sie normal.

**macOS 15 Sequoia und macOS 26 Tahoe**

1. *Music Library* im Programme-Ordner doppelklicken. Es erscheint „Apple konnte nicht überprüfen, ob
   ‚Music Library‘ frei von Schadsoftware ist …“ → **Fertig** klicken (nicht „In den Papierkorb legen“).
2. **Systemeinstellungen → Datenschutz & Sicherheit** öffnen und ganz nach unten scrollen.
3. Bei „‚Music Library‘ wurde blockiert …“ auf **Dennoch öffnen** klicken, mit Passwort/Touch ID
   bestätigen und im nächsten Dialog nochmals **Dennoch öffnen** wählen.

**macOS 13 Ventura und macOS 14 Sonoma**

1. Im Programme-Ordner mit **Rechtsklick** (oder ctrl-Klick) auf *Music Library* → **Öffnen**.
2. Im Dialog nochmals **Öffnen** klicken.

**Alternative für alle Versionen (Terminal):**

```
xattr -dr com.apple.quarantine "/Applications/Music Library.app"
```

## 3. Musik hinzufügen

Beim ersten Start: **Ordner hinzufügen …** und den Musikordner wählen (z. B. „Musik“, einen Ordner auf
einer externen Festplatte oder den iTunes-/Musik-Medienordner). Mehrere Ordner sind möglich
(Einstellungen → Bibliothek). Die App findet neue, geänderte, verschobene und gelöschte Dateien danach
selbst; externe Laufwerke werden beim Anschließen wieder erkannt.

macOS fragt beim ersten Zugriff ggf. nach der Erlaubnis für die Ordner *Dokumente*, *Schreibtisch*,
*Downloads* oder für **Wechselmedien** (externe Laufwerke) – bitte erlauben, sonst sieht die App die
Dateien nicht.

## 4. Daten und Deinstallation

- Bibliothek, Playlists, Favoriten, Zähler, Verlauf: `~/Library/Application Support/Music Library/`
- Sicherungen vor dem Ändern von Tags: `~/Library/Application Support/Music Library/Backups/`
  (Aufbewahrung einstellbar)
- Zwischenspeicher (Cover, umgewandelte Ogg-Dateien): `~/Library/Caches/Music Library/`

Deinstallieren: App in den Papierkorb legen; wer auch die Daten entfernen will, löscht zusätzlich die
beiden Ordner oben. **Deine Musikdateien liegen nie in diesen Ordnern** und bleiben immer, wo sie sind.

## 5. Selbst bauen (optional)

Auf einem Mac mit macOS 14.5 oder neuer und Xcode 16+ oder den Befehlszeilenwerkzeugen
(`xcode-select --install`):
`Build.command` im Projektordner doppelklicken – erzeugt `dist/Music Library.dmg`.
Blockiert macOS das Skript (heruntergeladene Datei), im Terminal ausführen: `bash ` eingeben, ein
Leerzeichen, `Build.command` aus dem Finder ins Terminalfenster ziehen und Eingabetaste drücken.
Oder im Terminal: `scripts/build_app.sh && scripts/make_dmg.sh`.
