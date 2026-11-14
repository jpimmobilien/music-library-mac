# Music Library für macOS

Die Mac-Fassung der privaten Android-App *Musikbibliothek 1.3.0* – eine lokale Musikbibliothek im
Liquid-Glass-Stil: Rosé-Akzent, Inter, eigene Symbole, schwebende Glas-Navigation, großer schwebender
Mini-Player. Keine iTunes-Kopie: keine Seitenleiste, keine grauen Tabellen, keine Cloud, kein Konto.

**Version 2** bringt fünf Ansichten in allen Bereichen (Raster, kompaktes Raster, Liste, Detailliste,
Cover Flow), vollständige Sortierung und Filter, sieben Player-Designs (Vinyl Studio, Classic, Cassette
Studio in sieben Farben, Portable CD, Modern Glass, Aurora, Studio Reel), einen neuen Mini-Player mit
Tonhöhe und Equalizer im Popover, eigene Equalizer-Voreinstellungen, 16 Einstellungskategorien und eine
gründliche Überarbeitung der Geschwindigkeit.

**Version 2.1** ist ein gezieltes Verbesserungs-Update ohne Redesign: „Hinzugefügt“ sortiert wie iTunes, Löschen
per Kontextmenü, Visualizer und Equalizer-Fenster repariert, Tonhöhe mit dem Verfahren der Android-App, feste
Werkzeugleiste, Zufall nach Alben, Mehrfachauswahl mit Aufziehen, größere Cover, Player-Hintergründe, Mini-Player
„Sehr groß“ und „Riesig“, Format/Bitrate/Hinzufügedatum im großen Player – siehe
[docs/V2_1_AENDERUNGEN.md](docs/V2_1_AENDERUNGEN.md).

**Version 2.2** bringt das **Audio Studio** (Navigation „Studio“, ⌘7): Audio aus YouTube und SoundCloud laden
(über yt-dlp, auf Wunsch installiert) oder lokale Audio-/Videodateien öffnen, Ausschnitt in der Wellenform wählen,
nach MP3, WAV, FLAC, AAC, M4A oder AIFF umwandeln, Metadaten und Cover setzen, direkt in die Bibliothek übernehmen,
Warteschlange und Verlauf – und **vorhandene Songs schneiden** (neue Datei oder Original ersetzen mit Sicherung und
Rückgängig). Spotify liefert nur Titel und Cover (DRM). Siehe [docs/V2_2_AENDERUNGEN.md](docs/V2_2_AENDERUNGEN.md).

**Version 2.3** bringt **„Titel bearbeiten“** (Rechtsklick auf einen Titel): Lautstärke, automatische Verbesserung
(Lautheit, Rumpelfilter, Begrenzer, Stille), Tempo, Tonhöhe, Kammerton (z. B. 440 → 432 Hz, mit Erkennung),
Auto-Tune, Equalizer und Beschneiden – dauerhaft, mit Sicherung und Rückgängig. Siehe
[docs/V2_3_AENDERUNGEN.md](docs/V2_3_AENDERUNGEN.md).

**Version 2.5** bringt **„KI-Musik“** (⌘8): Musik aus einer Beschreibung erzeugen – lokal auf Macs mit Apple-Chip
(ACE-Step 1.5), ohne Cloud, Konto oder Kosten, mit eigener Ablage „Meine KI-Kreationen“. Siehe
[docs/V2_5_AENDERUNGEN.md](docs/V2_5_AENDERUNGEN.md). Auf Intel-Macs nicht verfügbar.

**Version 2.4** trennt das Audio Studio in zwei Einträge der Navigation: **„Hinzufügen“** (ganz rechts, seit 2.5 ⌘9) lädt neue Musik aus
dem Netz oder von deinem Mac, **„Studio“** (⌘7) bearbeitet nur Titel der Bibliothek – mit Titelauswahl, Suche und
dem gerade laufenden Titel. Eine gemeinsame Warteschlange, jeder Bereich mit eigenem Verlauf. Siehe
[docs/V2_4_AENDERUNGEN.md](docs/V2_4_AENDERUNGEN.md). Für die geplante **KI-Musik** (lokale Musikerzeugung mit
ACE-Step 1.5) gibt es einen Machbarkeitsbericht: [docs/KI_MUSIK_MACHBARKEIT.md](docs/KI_MUSIK_MACHBARKEIT.md).

> **Stand 2.2:** Universal-DMG (Xcode 26), 577 Tests ohne Fehler auf macOS 26 (Apple Silicon) und macOS 15 (Intel),
> 125 Ansichten in Hell und Dunkel mit echtem Liquid Glass, Abnahme aus der DMG mit Aktualisierung 2.1 → 2.2 → 2.1
> ohne Befund. YouTube auf GitHub-Rechnern blockiert (nicht nachgewiesen), Bedienung nicht von Hand geprüft –
> Details: [docs/STATUS.md](docs/STATUS.md).

> **Stand 2.1:** gebaut und geprüft mit GitHub Actions: Universal-DMG (Xcode 26, macOS-26-SDK), 470 von 470 Tests
> auf macOS 26 (Apple Silicon) und macOS 15 (Intel), alle 97 Ansichten in Hell und Dunkel mit echtem Liquid Glass,
> Messlauf mit 10.000 Titeln. Nicht von Hand bedient, nicht auf macOS 13 und nicht auf echter Intel-Hardware mit
> Grafikkarte gestartet – Details: [docs/STATUS.md](docs/STATUS.md).

| | |
|---|---|
| macOS | 13 Ventura oder neuer (Liquid Glass ab macOS 26 Tahoe, davor gleichwertige Glas-Darstellung) |
| Prozessoren | Apple Silicon und Intel (Universal Binary) |
| Bauen | macOS mit Xcode 16+ (für Liquid Glass: Xcode 26) oder den Befehlszeilenwerkzeugen |

## Inhalt

- [docs/INSTALLATION.md](docs/INSTALLATION.md) – Installation, Update, erster Start, Signieren/Beglaubigen
- [docs/V2_5_AENDERUNGEN.md](docs/V2_5_AENDERUNGEN.md) – KI-Musik (Version 2.5)
- [docs/V2_4_AENDERUNGEN.md](docs/V2_4_AENDERUNGEN.md) – „Hinzufügen“ und „Studio“ (Version 2.4)
- [docs/KI_MUSIK_MACHBARKEIT.md](docs/KI_MUSIK_MACHBARKEIT.md) – KI-Musik: technische Analyse und Machbarkeit
- [docs/V2_3_AENDERUNGEN.md](docs/V2_3_AENDERUNGEN.md) – Titel bearbeiten (Version 2.3)
- [docs/V2_2_AENDERUNGEN.md](docs/V2_2_AENDERUNGEN.md) – Audio Studio (Version 2.2)
- [docs/V2_1_AENDERUNGEN.md](docs/V2_1_AENDERUNGEN.md) – Änderungen in Version 2.1
- [docs/V2_FUNKTIONEN.md](docs/V2_FUNKTIONEN.md) – Funktionsmatrix Android → macOS mit Prüfstand je Funktion
- [docs/STATUS.md](docs/STATUS.md) – Testbericht: was gebaut und getestet ist
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) – Ursachen der Ruckler in Version 1, Änderungen, Messungen
- [docs/NICHT_UMGESETZT.md](docs/NICHT_UMGESETZT.md) – Einschränkungen und offene Punkte
- [docs/ANALYSE.md](docs/ANALYSE.md), [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md), [docs/PLAYER_SPEC.md](docs/PLAYER_SPEC.md)
- [docs/V2_MLCORE_CONTRACT.md](docs/V2_MLCORE_CONTRACT.md), [docs/V2_UI_CONTRACT.md](docs/V2_UI_CONTRACT.md) – Schnittstellen und Regeln für Version 2

## Bauen

**Auf dem eigenen Mac:** `Build.command` doppelklicken. Ergebnis: `dist/Music Library.dmg`.

**Im Terminal:**

```
swift test                       # alle Tests
scripts/build_app.sh             # build/Music Library.app (arm64 + x86_64, ad-hoc signiert)
scripts/run_snapshots.sh "build/Music Library.app" snapshots    # Vorschaubilder aller Ansichten
scripts/run_benchmark.sh "build/Music Library.app" benchmark     # Messlauf mit 10.000 Titeln
scripts/make_dmg.sh              # dist/Music Library.dmg
```

**Automatisch (GitHub Actions):** `.github/workflows/build.yml` baut bei jedem Push auf `main` die App mit
Xcode 26, führt alle Tests aus (auch nativ auf Intel, macOS 15), erstellt die DMG, startet sie zur Probe auf
macOS 14 (alle Ansichten nativ, Auswahl mit dem Intel-Teil über Rosetta) und führt den Messlauf aus.
DMG, Bilder und Protokolle landen im Zweig `ci-ergebnisse`. Mit hinterlegten Developer-ID-Zugangsdaten wird
die DMG zusätzlich signiert und von Apple beglaubigt (siehe INSTALLATION.md).
`profile.yml` und `abtest.yml` nehmen Profile auf bzw. vergleichen Varianten auf demselben Rechner.

## Fremdbestandteile

| | Lizenz |
|---|---|
| Schrift Inter 4.1 | SIL Open Font License 1.1 |
| Material Symbols Rounded (Pfade) | Apache License 2.0 |
| TagLib 2.3.2 (unverändert) | Mozilla Public License 1.1 |
| stb_vorbis 1.22 (unverändert) | MIT / Public Domain |
| Genre-Titelbilder, App-Icon-Motiv | aus der Android-App (eigene Gestaltung) |

Die Lizenztexte liegen in `Resources/Licenses/` und werden in die App kopiert.
