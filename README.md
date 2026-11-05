# Music Library für macOS

Die Mac-Fassung der privaten Android-App *Musikbibliothek 1.3.0* – gleiche Gestaltung (Rosé, Glas,
Inter, eigene Symbole), gleiche Regeln, vier Player-Designs (Vinyl Studio, Classic, Cassette Studio,
Portable CD), dazu Mac-typische Ergänzungen und vollständige Metadaten-Bearbeitung. Keine iTunes-Kopie:
keine Seitenleiste, keine Tabellen.

> **Stand:** Die Fachlogik, die Datenbank, das Lesen/Schreiben der Tags, die Player-Grafiken und der
> Ogg-Decoder sind gebaut und mit 337 Tests geprüft. Die **App selbst ist noch nicht auf einem Mac gebaut
> worden** – es gibt daher noch **keine DMG**. Details: [docs/STATUS.md](docs/STATUS.md).

| | |
|---|---|
| macOS | 13 Ventura oder neuer (Liquid Glass ab macOS 26 Tahoe) |
| Prozessoren | Apple Silicon und Intel (Universal Binary) |
| Bauen | macOS 14.5+ mit Xcode 16+ oder den Befehlszeilenwerkzeugen |

## Inhalt

- [docs/INSTALLATION.md](docs/INSTALLATION.md) – Installation und erster Start
- [docs/STATUS.md](docs/STATUS.md) – was gebaut und getestet ist
- [docs/NICHT_UMGESETZT.md](docs/NICHT_UMGESETZT.md) – offene Punkte
- [docs/ANALYSE.md](docs/ANALYSE.md) – Funktionsabgleich Android → macOS
- [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md) – Aufbau des Projekts
- [docs/PLAYER_SPEC.md](docs/PLAYER_SPEC.md) – Maße und Bewegungen der Player-Designs

## Bauen

**Auf dem eigenen Mac:** `Build.command` doppelklicken. Ergebnis: `dist/Music Library.dmg`.

**Im Terminal:**

```
swift test                       # alle Tests
scripts/build_app.sh             # build/Music Library.app (arm64 + x86_64, ad-hoc signiert)
scripts/run_snapshots.sh "build/Music Library.app" snapshots   # Vorschaubilder aller Ansichten
scripts/make_dmg.sh              # dist/Music Library.dmg
```

**Automatisch (GitHub Actions):** `.github/workflows/build.yml` baut bei jedem Push auf `main` die App
auf macOS 26 (Xcode 26), erzeugt Vorschaubilder aller Ansichten (mit und ohne Liquid Glass) und die DMG,
führt alle Tests aus und startet die DMG zur Probe auf Intel (macOS 15) und Apple Silicon (macOS 14).
DMG, Bilder und Protokolle landen als Artefakte und im Zweig `ci-ergebnisse`; bei einem Tag `v*`
entsteht ein GitHub-Release mit der DMG.

## Fremdbestandteile

| | Lizenz |
|---|---|
| Schrift Inter 4.1 | SIL Open Font License 1.1 |
| Material Symbols Rounded (Pfade) | Apache License 2.0 |
| TagLib 2.3.2 (unverändert) | Mozilla Public License 1.1 |
| stb_vorbis 1.22 (unverändert) | MIT / Public Domain |
| Genre-Titelbilder, App-Icon-Motiv | aus der Android-App (eigene Gestaltung) |

Die Lizenztexte liegen in `Resources/Licenses/` und werden in die App kopiert.
