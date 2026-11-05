# Prüfstand – was gebaut und getestet ist (ehrlich)

Stand: 05.11.2026 · Version 2.0.0

## Umgebung

Entwickelt unter Linux, gebaut und geprüft mit GitHub Actions auf macOS-Rechnern
(Workflows `.github/workflows/build.yml` und `profile.yml`, Ergebnisse im Zweig `ci-ergebnisse`):

| Rechner | System | Werkzeuge | Aufgabe |
|---|---|---|---|
| Intel (x86_64) | macOS 26.6 | Xcode 26.6, Swift 6.3.3 | Universal-Build (arm64 + x86_64) mit dem macOS-26-SDK (Liquid Glass), alle Tests, DMG |
| Intel (x86_64) | macOS 15.7 | Xcode 16.4, Swift 6.1.2 | alle Tests nativ in x86_64, Kompilierprüfung mit älterem SDK |
| Apple Silicon | macOS 14.8 | – | DMG installieren, App starten: alle Ansichten nativ (arm64), Auswahl mit dem Intel-Teil über Rosetta; Messlauf mit 10.000 Titeln (beide Architekturen) |
| Apple Silicon | macOS 14.8 / 15.8 | Xcode 16 | Profilaufnahmen (`sample`) einzelner Ansichten und des Messlaufs |

**Hinweis zum Build-Rechner:** Die Apple-Silicon-Rechner mit macOS 26 bzw. 15 waren bei GitHub am 05.11.2026
über Stunden nicht verfügbar (Aufträge wurden nach 15 Minuten Warten ohne Rechner abgebrochen – bekanntes
Problem auf GitHubs Seite, `actions/runner#4833`). Gebaut wurde deshalb auf dem macOS-26-Intel-Rechner mit
demselben Xcode 26.6; das Ergebnis ist dieselbe Universal-App. Die Vorschaubilder **mit echtem Liquid Glass**
(nur auf macOS 26 mit Grafik möglich) konnten in dieser Runde deshalb nicht erzeugt werden; auf macOS 14 ist
die Rückfall-Glasdarstellung zu sehen.

## Übersicht

| Stufe | Ergebnis |
|---|---|
| **App gebaut** | ✅ Universal Binary (`x86_64 arm64`), Mindestversion in beiden Teilen macOS 13.0 (`minos 13.0`), ad-hoc signiert, `codesign --verify --deep --strict` ohne Befund |
| **DMG** | ✅ `Music Library.dmg` mit App, Verknüpfung „Programme“ und Hintergrund; `hdiutil verify` gültig; SHA-256 in `Music Library.dmg.sha256` |
| **Tests macOS 26, Intel (Xcode 26.6)** | ✅ **426 von 426 bestanden** |
| **Tests macOS 15, Intel (Xcode 16.4)** | ✅ **426 von 426 bestanden** |
| davon neu in Version 2 | 57 Logik-Tests (Sortierungen, Filter, Facetten, intelligente Playlists, Ansichtsoptionen, eigene EQ-Voreinstellungen, Tonhöhe, Einstellungen) · 6 Listen-Tests mit großer Bibliothek · 2 Klangtests der Feinstimmung |
| Klangkette (offline gemessen) | ✅ Tonhöhe **−0,1 Halbton → 437,5 Hz** (erwartet 437,47), **+0,5 Halbton → 453,3 Hz** (erwartet 452,9), +12 → 880 Hz; Tempo 1,5× hält 440 Hz; EQ 1 kHz +12 dB → +12,0 dB; Bass +6 dB → +5,6 dB bei 50 Hz; 300 % Lautstärke → Spitze 0,95 (Limiter greift) |
| **Starttest der DMG** | _siehe unten (wird nach dem Lauf ergänzt)_ |
| **Vorschaubilder** | _siehe unten_ |
| **Messlauf 10.000 Titel** | _siehe PERFORMANCE.md_ |

## Fehler, die bei der Prüfung gefunden und behoben wurden

- **Hänger beim Start (erster Build von Version 2):** Vorschau- und Messmodus lieferten nach 15 bzw.
  20 Minuten kein einziges Bild. Ursache: Einstellungen wurden auch bei unverändertem Wert veröffentlicht;
  zusammen mit der Bindung des Menüleisten-Symbols entstand eine Endlosschleife. Behoben; seitdem laufen
  alle Ansichten durch, und ein eingebauter Wächter würde einen erneuten Hänger mit Profil aufzeichnen.
- **Unsichtbare Menüs im Metadaten-Fenster** („Kopieren/Einfügen/Verwerfen“ und Genre-Auswahl nutzten `Menu`
  mit eigenem Symbol, das unter macOS 13 unsichtbar bleibt) → Glas-Popover.
- **Sprungweite** im Menü und im Kontrollzentrum war fest 10 s → folgt jetzt der Einstellung.
- **Pfeiltasten in Listen** wurden wegen zusätzlicher Tastenflags nicht erkannt → behoben.
- **„Bereich beim Start“** hatte keine Wirkung → wird jetzt beim Start angewendet.
- **Lautstärke per Tastatur** konnte über die eingestellte Höchstlautstärke hinaus gespeichert werden → begrenzt.

## Nicht geprüft

Siehe [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md): macOS 13 Ventura, echte Intel-Hardware, Bedienung von Hand,
Wiedergabe über Lautsprecher, echte Musiksammlung, Gatekeeper beim ersten Start.
