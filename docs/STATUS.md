# Prüfstand – was gebaut und getestet ist (ehrlich)

Stand: 05.11.2026 · Version 1.0.0 (erste macOS-Fassung)

## Umgebung

Entwickelt unter Linux, gebaut und geprüft mit GitHub Actions auf echten macOS-Rechnern
(Workflow `.github/workflows/build.yml`, Ergebnisse jedes Laufs im Zweig `ci-ergebnisse`):

| Rechner | System | Werkzeuge | Aufgabe |
|---|---|---|---|
| Apple Silicon | macOS 26.6 | Xcode 26.6, Swift 6.3.3 | Build, Tests, Vorschaubilder (Liquid Glass + Rückfall), DMG |
| Intel (x86_64) | macOS 15.7 | Xcode 16.4, Swift 6.1.2 | alle Tests nativ in x86_64 |
| Apple Silicon | macOS 14.8 | – | DMG installieren, App starten (arm64 und Intel-Teil über Rosetta) |

## Übersicht

| Stufe | Ergebnis |
|---|---|
| **App gebaut** | ✅ Universal Binary (arm64 + x86_64), Mindestversion in beiden Teilen macOS 13.0 (`minos 13.0`), ad-hoc signiert, `codesign --verify --deep --strict` ohne Befund |
| **DMG** | ✅ `Music Library.dmg` (≈ 10,6 MB): App, Verknüpfung „Programme“, Hintergrund, Volume-Icon; `hdiutil verify` gültig; SHA-256 in `Music Library.dmg.sha256` |
| **Tests macOS 26, Apple Silicon** | ✅ **361 von 361 bestanden** |
| **Tests macOS 15, Intel** | ✅ **361 von 361 bestanden** (nativ x86_64) |
| davon | MLCore 199 · MLTags 76 (inkl. Audio-Unversehrtheit mit ffmpeg) · MLRender 46 · MLStore 11 · OggVorbis 5 · App 24 |
| Klangkette (gemessen in den App-Tests, offline) | ✅ neutral bit-nah (Spitze 0,49999 bei 0,5), 50 % → 0,25, EQ 1 kHz +12 dB → +12,0 dB, 16-kHz-Band bei 125 Hz → 0,0 dB, Aussteuerung −12 dB gleicht aus, Bass +6 dB → +5,6 dB bei 50 Hz und 0,0 dB bei 5 kHz, Tonhöhe +12 HT → 880 Hz, Tempo 1,5× → Tonhöhe bleibt 440 Hz, Drehzahl 2× → 880 Hz, **300 % Lautstärke → Spitze 0,95 (Limiter greift)** |
| **Starttest der DMG** | ✅ auf macOS 14 installiert und gestartet – nativ (arm64) und der Intel-Teil über Rosetta (x86_64): jeweils alle 58 Ansichten gezeichnet |
| **Vorschaubilder** | ✅ 29 Ansichten × hell/dunkel, auf macOS 26 mit Liquid Glass und mit Rückfall-Glas, auf macOS 14 (arm64 und x86_64) – angesehen; gefundene Fehler behoben (schwarzer Streifen oben, weißes Glas in Classic/Cassette bei hellem Design, abgeschnittene Schaltflächen und Platzhalter, Jahreszahl mit Tausenderpunkt) |
| Tags schreiben – Unversehrtheit der Musik | ✅ 16 Formate: Audiodaten nach Bearbeiten, Leeren und erneutem Bearbeiten bit-identisch (ffmpeg-MD5), auf Linux und macOS |

## Bekannte Einschränkung der Prüfung

- Die **Intel-Maschinen von GitHub sind virtuelle Rechner ohne Metal-Grafik**. Dort bricht die Oberfläche
  beim Zeichnen mit einer Metal-Meldung des Systems ab (`Target device architecture is nil`). Echte
  Intel-Macs haben eine Grafikkarte; der Intel-Teil der App wurde deshalb über Rosetta auf Apple Silicon
  gezeichnet und alle Tests nativ auf Intel ausgeführt. **Auf echter Intel-Hardware ist die Oberfläche
  nicht gesehen.**

## Nicht geprüft

- **macOS 13 Ventura**: kein Testrechner verfügbar (GitHub bietet macOS 13 nicht mehr an). Die App ist
  dafür gebaut (Mindestversion 13.0, keine neueren Schnittstellen ohne Abfrage), aber dort nicht gestartet.
- **Bedienung von Hand**: Klicken, Ziehen & Ablegen, Tastenkürzel, Menüs, Kontextmenüs, Fenster verschieben.
- **Tatsächliche Wiedergabe über Lautsprecher**, Medientasten, Kontrollzentrum, Sleep-Timer in Echtzeit.
- **Einlesen einer echten Musiksammlung** (Geschwindigkeit großer Bibliotheken, externe Laufwerke,
  Dateiüberwachung) und **Tags schreiben über die Oberfläche** an echten Dateien (die Schreiblogik selbst ist getestet).
- **Erster Start nach dem Herunterladen** (Gatekeeper): Schritte nach Apples Dokumentation beschrieben, nicht ausprobiert.
