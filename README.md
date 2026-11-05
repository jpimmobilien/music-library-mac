# Music Library für macOS

Die Mac-Fassung der privaten Android-App *Musikbibliothek 1.3.0* – eine lokale Musikbibliothek im
Liquid-Glass-Stil: Rosé-Akzent, Inter, eigene Symbole, schwebende Glas-Navigation, großer schwebender
Mini-Player. Keine iTunes-Kopie: keine Seitenleiste, keine grauen Tabellen, keine Cloud, kein Konto.

**Version 2** bringt fünf Ansichten in allen Bereichen (Raster, kompaktes Raster, Liste, Detailliste,
Cover Flow), vollständige Sortierung und Filter, sieben Player-Designs (Vinyl Studio, Classic, Cassette
Studio in sieben Farben, Portable CD, Modern Glass, Aurora, Studio Reel), einen neuen Mini-Player mit
Tonhöhe und Equalizer im Popover, eigene Equalizer-Voreinstellungen, 16 Einstellungskategorien und eine
gründliche Überarbeitung der Geschwindigkeit.

> **Stand:** gebaut und geprüft mit GitHub Actions: Universal-DMG (Xcode 26.6, macOS-26-SDK),
> 426 von 426 Tests auf Intel (macOS 26 und macOS 15), Starttest der DMG auf macOS 14 mit allen 65 Ansichten
> in Hell und Dunkel (arm64) und einer Auswahl mit dem Intel-Teil über Rosetta, Messlauf mit 10.000 Titeln.
> Nicht von Hand bedient, nicht auf macOS 13 und nicht auf echter Intel-Hardware gestartet – Details:
> [docs/STATUS.md](docs/STATUS.md).

| | |
|---|---|
| macOS | 13 Ventura oder neuer (Liquid Glass ab macOS 26 Tahoe, davor gleichwertige Glas-Darstellung) |
| Prozessoren | Apple Silicon und Intel (Universal Binary) |
| Bauen | macOS mit Xcode 16+ (für Liquid Glass: Xcode 26) oder den Befehlszeilenwerkzeugen |

## Inhalt

- [docs/INSTALLATION.md](docs/INSTALLATION.md) – Installation, Update, erster Start, Signieren/Beglaubigen
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
