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
| **DMG** | ✅ `Music Library.dmg` (≈ 13,0 MB) mit App, Verknüpfung „Programme“ und Hintergrund; `hdiutil verify` gültig; SHA-256 `72e0738af2559ce616d32839d2406b3a3ea748d37c2088e84c087d449790d13c` (Lauf 15, Commit `d9fdaf2`) |
| **Tests macOS 26, Intel (Xcode 26.6)** | ✅ **426 von 426 bestanden** |
| **Tests macOS 15, Intel (Xcode 16.4)** | ✅ **426 von 426 bestanden** |
| davon neu in Version 2 | 57 Logik-Tests (Sortierungen, Filter, Facetten, intelligente Playlists, Ansichtsoptionen, eigene EQ-Voreinstellungen, Tonhöhe, Einstellungen) · 6 Listen-Tests mit großer Bibliothek · 2 Klangtests der Feinstimmung |
| Klangkette (offline gemessen) | ✅ Tonhöhe **−0,1 Halbton → 437,5 Hz** (erwartet 437,47), **+0,5 Halbton → 453,3 Hz** (erwartet 452,9), +12 → 880 Hz; Tempo 1,5× hält 440 Hz; EQ 1 kHz +12 dB → +12,0 dB; Bass +6 dB → +5,6 dB bei 50 Hz; 300 % Lautstärke → Spitze 0,95 (Limiter greift) |
| **Starttest der DMG** | ✅ auf macOS 14.8 installiert (Prüfsumme, `codesign --verify`) und gestartet – nativ (arm64) und mit dem Intel-Teil über Rosetta (x86_64) |
| **Vorschaubilder** | ✅ **alle 65 Ansichten × hell/dunkel = 130 Bilder** auf macOS 14 (arm64), 22 Ansichten × 2 über Rosetta (fehlerfrei erzeugt); die arm64-Bilder wurden angesehen. Liquid Glass (macOS 26) in dieser Runde nicht abgebildet (s. o.) |
| **Messlauf 10.000 Titel** | ✅ auf macOS 14 nativ und über Rosetta, Vergleich mit Version 1.0 und A/B-Vergleiche – siehe [PERFORMANCE.md](PERFORMANCE.md) |

## Fehler, die bei der Prüfung gefunden und behoben wurden

- **Langsamere Cover-Darstellung** (zwischenzeitliche Umstellung ohne `GeometryReader`): per A/B-Messung auf
  demselben Rechner erkannt (Detailliste und kompaktes Raster bis zu 2× langsamer) und zurückgenommen.
- **Vorschau-Szenarien**: eigene EQ-Voreinstellungen wurden bei jedem Durchlauf erneut angelegt („Abend (2)“ …),
  das Filter-Szenario zeigte keine Treffer – Testdaten korrigiert (kein Fehler der App).
- **Hänger beim Start (erster Build von Version 2):** Vorschau- und Messmodus lieferten nach 15 bzw.
  20 Minuten kein einziges Bild. Wahrscheinliche Ursache (aus dem Code, nicht per Profil belegt, weil zu
  diesem Zeitpunkt noch kein Wächter eingebaut war): Einstellungen wurden auch bei unverändertem Wert
  veröffentlicht; zusammen mit der Bindung des Menüleisten-Symbols konnte eine Endlosschleife entstehen.
  Behoben (nur echte Änderungen werden veröffentlicht, Bindung mit Gleichheitsprüfung); seitdem laufen alle
  Ansichten und der Messlauf in jedem Lauf durch, und ein eingebauter Wächter würde einen erneuten Hänger
  mit Profil aufzeichnen.
- **Unsichtbare Menüs im Metadaten-Fenster** („Kopieren/Einfügen/Verwerfen“ und Genre-Auswahl nutzten `Menu`
  mit eigenem Symbol, das unter macOS 13 unsichtbar bleibt) → Glas-Popover.
- **Sprungweite** im Menü und im Kontrollzentrum war fest 10 s → folgt jetzt der Einstellung.
- **Pfeiltasten in Listen** wurden wegen zusätzlicher Tastenflags nicht erkannt → behoben.
- **„Bereich beim Start“** hatte keine Wirkung → wird jetzt beim Start angewendet.
- **Lautstärke per Tastatur** konnte über die eingestellte Höchstlautstärke hinaus gespeichert werden → begrenzt.

## Nicht geprüft

Siehe [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md): macOS 13 Ventura, echte Intel-Hardware, Bedienung von Hand,
Wiedergabe über Lautsprecher, echte Musiksammlung, Gatekeeper beim ersten Start.
