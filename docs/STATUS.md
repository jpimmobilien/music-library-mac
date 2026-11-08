# Prüfstand – was gebaut und getestet ist (ehrlich)

Stand: 09.11.2026 · Version 2.2.0 (Build-Lauf 19, Commit `90af16d`)

Alle Ergebnisse stammen aus echten Läufen auf GitHub-Rechnern (virtuelle Macs). Entwickelt unter Linux; reine
Logik (`MLCore`, `MLStudio`) dort zusätzlich nativ übersetzt und getestet.

## Übersicht Version 2.2

| Stufe | Ergebnis |
|---|---|
| **App gebaut** | ✅ Universal Binary (`x86_64 arm64`), Xcode 26 (Swift 6.3.3), Mindestversion in beiden Teilen macOS 13.0, ad-hoc signiert, `codesign --verify` ohne Befund |
| **DMG** | ✅ `Music Library.dmg` (17,3 MB), `hdiutil verify` gültig, SHA-256 `416baa2307a624da67a4ab6b6068b3fddbaa322f80e0ed56cb76e1eea9a3c10d` |
| **Tests macOS 26, Apple Silicon** | ✅ **577 Tests, 0 Fehler** (4 nur auf Wunsch aktive Zusatzprüfungen übersprungen) |
| **Tests macOS 15, Intel** | ✅ **577 Tests, 0 Fehler** (4 übersprungen) |
| **Tests macOS 26, Intel** | ✅ 577 Tests, 0 Fehler (Entwicklungslauf mit demselben Stand) |
| **Vorschaubilder macOS 26** | ✅ **125 Ansichten × Hell/Dunkel = 250 Bilder mit echtem Liquid Glass**, dazu 250 in der Rückfall-Darstellung; neu: 28 Ansichten des Audio Studios (angesehen) |
| **Starttest aus der DMG, macOS 15 Apple Silicon** | ✅ nativ (alle Ansichten) und Intel-Teil über Rosetta (Auswahl) – im Build-Lauf |
| **Abnahme aus der DMG, macOS 26** | ✅ Apple Silicon, Intel und Rosetta: Prüfsumme, Einhängen, Installieren, Architekturen, Signatur, Version 2.2.0; 250 bzw. 72 Bilder (Rosetta) |
| **Aktualisierung 2.1 → 2.2 → 2.1** (normaler Start, echte Dateien) | ✅ auf **Apple Silicon und Intel (macOS 26)**: 2.1 liest 8 Testdateien ein, dazu Favoriten, Playlist, Bewertung, Wiedergabezahl, Wiedergabeposition; 2.2 startet zweimal (mit neuer Datei) – **alle Daten unverändert**; danach öffnet 2.1 die Datenbank weiterhin. Kein Absturz |
| **Intel, macOS 15 (virtueller Mac)** | ⚠️ 2.1 **und** 2.2 stürzen beim normalen Start gleichermaßen ab: Metal-Fehler der virtuellen Grafik („Target device architecture is nil“ in SwiftUI/RenderBox). Kein Fehler von 2.2; Tests laufen dort vollständig |
| **Geschwindigkeit 2.1 ↔ 2.2** (gleicher Rechner) | ✅ Scrollen und Bereichswechsel gleich innerhalb der Streuung; Leerlauf mit Wiedergabe streut stark (2.1: 12–27 %, 2.2: 15–29 % Hauptthread), im Profil ohne Studio-Anteile – siehe [PERFORMANCE.md](PERFORMANCE.md) |

## Audio Studio – Prüfungen

| Bereich | Prüfung | Ergebnis |
|---|---|---|
| Logik (`MLStudioTests`) | Formate, Hinweise, Dateinamen, Quellen-Erkennung, yt-dlp-Zuordnung, Warteschlange, Doppelte, Wellenform, Zeiten, Einstellungen | bestanden (macOS und zusätzlich unter Linux) |
| Export jedes Formats | MP3 alle 7 Bitraten, WAV 16/24/32 Float, FLAC, AAC, M4A, AIFF bei 22,05–96 kHz: Lesbarkeit, Endung, Dauer, Abtastrate, Kanäle, Bittiefe, Bitrate, Tags + Cover (MLTags und ffprobe) | bestanden; MP3-Bitrate exakt; Störabstand MP3 26 dB (96 kbit/s) bis 77 dB (320 kbit/s), M4A 56–71 dB, 16 Bit mit Dither 86 dB, 24 Bit/Float bitgenau |
| Schnittgenauigkeit | Klickmarken | 0 Frames Versatz (WAV/FLAC/AIFF, auch aus MP3- und M4A-Quellen) |
| Ohne Neukodierung | MP3 und M4A | Dauer Δ 0,00 ms, Audioframes byteweise wie die Quelle; WAV/FLAC/AIFF bitgenau |
| Robustheit | beschädigte Dateien, Abbruch (keine Restdatei), Pause, 30-min-Datei, 0,2-s-Ausschnitt, Video- und Ogg-Eingänge | bestanden; Wellenform 1 h WAV in < 1 s |
| Werkzeuge | Installation mit Prüfsumme (falsche Prüfsumme → nichts installiert), Entfernen, Suche, Abbruch beendet Unterprozesse | bestanden (mit lokalen Ersatz-Veröffentlichungen) und echt: yt-dlp 2026.10.26 + Deno 2.9.8 von GitHub installiert |
| SoundCloud (CC BY 4.0) | Analyse, Vorschaubild, Laden, Export MP3-Ausschnitt mit Tags und Cover | ✅ bestanden (ffprobe: MP3, 30,00 s, 44,1 kHz, Titel/Interpret, Cover) |
| Spotify | Metadaten, Download | ✅ Titel und Cover; Download mit DRM-Hinweis abgelehnt |
| YouTube (CC BY 3.0) | Analyse | ⚠️ **blockiert**: YouTube verlangt auf GitHub-Rechnern eine Anmeldung („Sign in to confirm you're not a bot“) – nicht umgangen, daher nicht nachgewiesen |
| Abläufe (`StudioModelTests`) | Reihenfolge, ein aktiver Auftrag, Pause/Fortsetzen/Abbrechen/Wiederholen, Fehler → nächster, Verlauf, freier Dateiname, Doppelte, **Original ersetzen mit Sicherung und Rückgängig** | 23 Tests mit echten Dateien in temporären Ordnern |
| Eingebundene Bibliotheken | LAME 3.100 und libFLAC 1.5.0 gegen die offiziellen Tarbälle (SHA-256 wie Homebrew) | libFLAC 54/54 Dateien identisch; LAME inhaltlich identisch (18 Dateien unterscheiden sich nur in der CVS-Zeile `$Id$`) |
| Oberfläche | 28 Ansichten in Hell/Dunkel mit Liquid Glass | angesehen; **nicht von Hand bedient** |

## Nicht geprüft

Siehe [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md): Bedienung von Hand (Ziehen, Zoom, Ablegen, Tastatur), Anhören über
Lautsprecher, YouTube auf echten Inhalten, Apple-Musik-Zugriff mit echter Mediathek, macOS 13, echte Intel-Hardware
mit Grafikkarte, Gatekeeper beim ersten Start.

## Version 2.1 (zum Vergleich)

470 Tests auf macOS 26 (Apple Silicon) und macOS 15 (Intel), 194 Liquid-Glass-Bilder, Aktualisierung 2.0 → 2.1 → 2.0
ohne Befund – Einzelheiten im Verlauf dieser Datei (Git) und in [V2_1_AENDERUNGEN.md](V2_1_AENDERUNGEN.md).
