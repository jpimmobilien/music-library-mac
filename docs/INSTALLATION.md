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

**Update von Version 1, 2.0 oder 2.1:** Die neue DMG öffnen, das App-Symbol wieder auf **Programme** ziehen
und „Ersetzen“ wählen. Bibliothek, Playlists, Favoriten, Zähler und Einstellungen bleiben erhalten. Die
Gatekeeper-Rückfrage kommt bei einer neuen, ad-hoc signierten Version noch einmal.

**Version 2.1 – Hinzufügedatum:** Beim ersten Start bestimmt die App im Hintergrund einmalig das
Hinzufügedatum aller vorhandenen Titel neu (aus der freigegebenen Apple-Musik-Mediathek, sonst aus dem
Erstellungsdatum der Datei). Danach sortiert „Hinzugefügt“ wie in iTunes. Die Datenbank wird dabei nur
ergänzt – Version 2.0 kann sie bei Bedarf weiterhin öffnen.
Wer die echten „Hinzugefügt“-Daten aus Apple Musik übernehmen möchte: **Einstellungen → Bibliothek →
Hinzufügedatum → „Aus Apple Musik übernehmen …“**. macOS fragt dann einmal nach dem Zugriff auf
*Medien & Apple Music* – bitte erlauben (es wird nur gelesen, nichts verändert). Alternativ in der
Musik-App unter *Einstellungen → Erweitert* „Mediathek-XML für andere Apps freigeben“ einschalten; diese
Datei liest Music Library ohne Rückfrage.

## 3. Musik hinzufügen

Beim ersten Start: **Ordner hinzufügen …** und den Musikordner wählen (z. B. „Musik“, einen Ordner auf
einer externen Festplatte oder den iTunes-/Musik-Medienordner). Mehrere Ordner sind möglich
(Einstellungen → Bibliothek). Die App findet neue, geänderte, verschobene und gelöschte Dateien danach
selbst; externe Laufwerke werden beim Anschließen wieder erkannt.

macOS fragt beim ersten Zugriff ggf. nach der Erlaubnis für die Ordner *Dokumente*, *Schreibtisch*,
*Downloads* oder für **Wechselmedien** (externe Laufwerke) – bitte erlauben, sonst sieht die App die
Dateien nicht.

## 3a. Audio Studio (ab 2.2)

Das Audio Studio (Navigation „Studio“ oder ⌘7) wandelt lokale Audio- und Videodateien um und schneidet Titel
der Bibliothek – dafür ist nichts weiter nötig.

**Internet-Quellen (YouTube, SoundCloud, Instagram):** Dafür braucht das Studio das Open-Source-Werkzeug **yt-dlp**, für
YouTube zusätzlich die JavaScript-Laufzeit **Deno**. Beide sind nicht in der App enthalten. Im Studio oben rechts
„Werkzeuge einrichten“ → „Installieren“: Die App lädt sie von den offiziellen GitHub-Veröffentlichungen, prüft die
SHA-256-Prüfsummen und legt sie unter `~/Library/Application Support/Music Library/Audio Studio/Tools` ab
(„Entfernen“ löscht sie wieder). Sind yt-dlp und Deno schon über Homebrew installiert, werden diese verwendet.
Ohne deinen Klick lädt die App nichts. Lade nur Inhalte, für die du die Rechte hast; Spotify-Audio ist
kopiergeschützt und wird nicht geladen (nur Titel, Interpret und Cover).

**Ersetzte Originale** (Schneiden → „Original ersetzen“) werden vorher gesichert unter
`~/Library/Application Support/Music Library/Audio Studio/Backups` und lassen sich im Verlauf rückgängig machen.
Die Sicherungen werden nicht automatisch gelöscht.

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

## 6. Signieren und Beglaubigen (optional, für den Entwickler)

Ohne Apple-Entwicklerkonto bleibt die App ad-hoc signiert (Rückfrage beim ersten Start, siehe oben).
Die Bauanleitung ist für die Beglaubigung durch Apple vorbereitet (`scripts/notarize.sh`, Schritte in
`.github/workflows/build.yml`); sie wird **nur** ausgeführt, wenn die Zugangsdaten als GitHub-Secrets
hinterlegt sind. Benötigt werden:

1. Mitgliedschaft im **Apple Developer Program** (99 € pro Jahr).
2. Ein Zertifikat **„Developer ID Application“** (Xcode → Einstellungen → Accounts → Zertifikate verwalten,
   oder developer.apple.com → Certificates), exportiert aus der Schlüsselbundverwaltung als `.p12` mit Passwort.
3. Ein **app-spezifisches Passwort** für die Apple-ID (appleid.apple.com → Anmeldung & Sicherheit).
4. Die **Team-ID** (developer.apple.com → Membership, 10 Zeichen).

In GitHub unter *Settings → Secrets and variables → Actions* anlegen:

| Secret | Inhalt |
|---|---|
| `MACOS_CERT_P12_BASE64` | Ausgabe von `base64 -i DeveloperID.p12` |
| `MACOS_CERT_PASSWORD` | Passwort der .p12-Datei |
| `NOTARY_APPLE_ID` | Apple-ID des Entwicklerkontos |
| `NOTARY_TEAM_ID` | Team-ID |
| `NOTARY_PASSWORD` | app-spezifisches Passwort |

Danach signiert der nächste Build mit „Hardened Runtime“, reicht die DMG bei Apple ein und heftet das
Beglaubigungsticket an – die Gatekeeper-Rückfrage entfällt. Dieser Weg ist vorbereitet, aber **ungetestet**,
weil dafür ein echtes Entwicklerkonto nötig ist.
