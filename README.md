# PROJECT AETHER – macOS Edition

*System Intelligence & File Explorer* · Universal App für Intel und Apple Silicon · macOS 13 Ventura oder neuer,
Liquid Glass auf macOS 26 Tahoe.

AETHER vereint Systemmonitor, Prozessmanager, Hardware- und Energieanalyse, Speicheranalyse und einen erweiterten
Dateimanager. Das Markenzeichen: **Jede Zahl trägt ihre Herkunft.** Das kleine Symbol neben einem Wert zeigt auf Klick,
ob der Wert gemessen, berechnet, von macOS angegeben oder geschätzt ist – und aus welcher Schnittstelle er stammt.
Werte, die macOS nicht liefert, heißen „Nicht verfügbar“ mit Begründung. Erfunden wird nichts.

## Stand: 0.2.0 – Phase 1 und 2

| Bereich | Stand |
|---|---|
| Produkt- und Machbarkeitskonzept | [docs/KONZEPT.md](docs/KONZEPT.md) |
| Universal-Build arm64 + x86_64, DMG, Prüfungen | fertig, läuft auf echten macOS-Rechnern (GitHub Actions) |
| Designsystem, 6 Themes, Akzentfarben, Glasintensität, Bewegung, Dichte | fertig |
| Navigation mit 11 Bereichen | fertig |
| **Übersicht** mit echten Messwerten: CPU, Arbeitsspeicher, Speicherdruck, Swap, Thermalstatus, Batterie, Netzwerk, Volumes, SSD-Aktivität, GPU, Hardware | fertig |
| Puls (Systemstatus als Satz, nur aus Messwerten, Regeln offen einsehbar) | fertig |
| Einstellungen, Sprache Englisch/Deutsch | fertig |
| Aktivität, CPU & GPU, Arbeitsspeicher (Detailseiten) | Phase 4 |
| Temperatur & Lüfter (SMC), Batterie, Hardware (Detailseiten) | Phase 5 |
| Speicher, Dateien (Finder Plus) | Phase 6 |
| Netzwerk, lokaler Verlauf, Exporte | Phase 7 |

Was diese Version nicht kann und was macOS grundsätzlich nicht hergibt: [docs/GRENZEN.md](docs/GRENZEN.md).

## Installation

`AETHER-macOS-Universal.dmg` öffnen, AETHER auf „Programme“ ziehen. Die App ist ad-hoc signiert und nicht notariell
beglaubigt – beim ersten Start einmal „Dennoch öffnen“. Einzelheiten: [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Bauen

Auf einem Mac mit Xcode 16 oder neuer (bzw. den Befehlszeilenwerkzeugen): `Build.command` doppelklicken, oder

```
swift test
CLEAN=1 scripts/build_app.sh     # build/AETHER.app – Universal, geprüft
scripts/make_dmg.sh              # AETHER-macOS-Universal.dmg im Projektverzeichnis, eingehängt und geprüft
```

In Xcode: `Package.swift` öffnen, Schema „AETHER“ wählen.

**Automatisch:** Jeder Push in den Zweig `aether-macos` baut und prüft auf echten macOS-Rechnern
([Workflow](.github/workflows/aether-macos.yml)):

- Tests unter Linux, macOS 26 und Intel;
- Clean Build für arm64 + x86_64 mit `lipo`-Prüfung;
- Prüfung der Bundle-Ressourcen;
- Selbsttest mit echten Messwerten;
- Bildschirmfotos aller Themes;
- DMG mit Mount-Test;
- Installation aus der DMG und Start: nativ, über Rosetta und auf einem Intel-Mac.

Die Ergebnisse (DMG, Protokolle, Bilder) landen im Zweig `ci-ergebnisse-aether-macos`.

**Signatur:** ohne Zugangsdaten ad-hoc. Mit den GitHub-Secrets `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`,
`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` und `NOTARY_PASSWORD` signiert der Build mit Developer ID (Hardened Runtime),
notarisiert und heftet das Ticket an.

## Aufbau

```
Package.swift
Sources/AetherCore     reine Logik, auch unter Linux getestet: Herkunft, CPU-/Speicher-/Raten-Mathematik, Puls,
                       Formatierung, Theme-Paletten (Kontraste per Test geprüft), Parser
Sources/AetherSystem   Messquellen (Darwin, IOKit, Metal, IOPowerSources) mit Fähigkeitserkennung
Sources/AETHER         die App: App/, Design/, Monitoring/, Views/, Support/
Tests/AetherCoreTests
Resources/             Info.plist, Icon, DMG-Hintergrund, Localization/{en,de}.lproj
scripts/               build_app.sh, make_dmg.sh, dmg_settings.py, notarize.sh, run_selftest.sh, run_snapshots.sh
tools/                 check_l10n.py (Lokalisierungsprüfung), art/ (Icon und DMG-Grafik)
```

## Datenschutz

Keine Netzwerkverbindungen (vom Build geprüft: Die Programmdatei referenziert keine Verbindungs-APIs). Keine
Telemetrie, keine Konten, keine Administratorrechte, keine Hintergrundhelfer. Einstellungen bleiben lokal.
