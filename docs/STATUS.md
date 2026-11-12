# Prüfstand – was gebaut und getestet ist (ehrlich)

## Version 2.2.2 (12.11.2026, Build-Lauf 43308096148, Commit `e324bb4`)

| Stufe | Ergebnis |
|---|---|
| Neu | Abschnitte nach Erscheinungsjahr und „Hinzugefügt“ in den Übersichten Titel und Alben, mitlaufende Abschnitts-Kapsel |
| Tests | ✅ 584 Tests, 0 Fehler (4 Zusatzprüfungen übersprungen) auf macOS 26 Intel und macOS 15 Intel; 6 neue Tests zur Einteilung (davon einer mit > 3.000 Zeitpunkten an Monats-/Jahresgrenzen und Zeitumstellungen gegen die direkte Kalenderrechnung) – zusätzlich unter Linux |
| Übersetzen | ✅ Xcode 16 und Xcode 26 |
| Vorschaubilder | ✅ 7 neue Ansichten × Hell/Dunkel auf macOS 26 Intel (Liquid Glass), angesehen; nicht auf Apple Silicon (keine Rechner zugeteilt) |
| DMG | ✅ SHA-256 `96c5d4635a5cf70b378dd054147fb63d8b2b8a601c337a148e7aff0c232ffdff`, `hdiutil verify` gültig, `x86_64 arm64`, Signatur gültig; gebaut auf macOS 26 Intel (Apple-Silicon-Rechner nicht zugeteilt) |
| Kontrolle Build-Rechner | ✅ 2.2.1 auf Intel gebaut gegen 2.2.1 auf Apple Silicon gebaut: gleiche Messwerte (Listen berechnen 1.215–1.400 ms in beiden) |
| Abnahme | ✅ Intel macOS 26: Installation aus der DMG, Version 2.2.2, Aktualisierung 2.2.1 → 2.2.2 → 2.2.1 ohne Befund; Geschwindigkeit wie 2.2.1 (Listen 959/1.128 ms gegenüber 1.253 ms, Leerlauf 12,1/11,9 % gegenüber 12,8/12,6 %); Abschnitte „Hinzugefügt“ für 10.000 Titel + Alben 4,5–5,3 ms (ohne Zwischenspeicher 25–28 ms) · Intel macOS 15 (virtuell): Installation ✅, Start scheitert wie bei jeder Version am Metal-Fehler der virtuellen Maschine |
| Nicht geprüft | Apple Silicon (Abnahme, Starttest, Vorschaubilder – keine Rechner zugeteilt), macOS 13, Bedienung von Hand |
| Hinweis | Ein erster Vergleichslauf zeigte „Listen berechnen“ bei 2.2.2 um 30 % langsamer; bei Sortierung nach Titel (wie im Messlauf) rechnet die Abschnittseinteilung nicht. Kontroll- und Wiederholungslauf zeigen keinen Unterschied – Streuung des virtuellen Rechners |

## Version 2.2.1 (11.11.2026, Build-Lauf 43004398659, Commit `1f7eb94`)

| Stufe | Ergebnis |
|---|---|
| Fehler | Absturz beim Übergang zum nächsten Titel (Formatwechsel, z. B. Mono ↔ Stereo; AVAudioEngine-Ausnahme −10868) – gemeldet auf macOS 13.7.8, nachgestellt auf macOS 15 und 26 |
| Test | `testTrackChangeBetweenFormatsWhileRunning`: ohne Korrektur Fehler −10868, mit Korrektur bestanden (macOS 15 Intel, macOS 26 Intel, macOS 26 Apple Silicon) |
| Tests | ✅ 578 Tests, 0 Fehler (4 Zusatzprüfungen übersprungen) auf macOS 26 Apple Silicon und macOS 15 Intel |
| DMG | ✅ SHA-256 `62f01d11e6c02a8a1947f66ccedb7c34aa38819a986eaf652e4225add1c5941a`, `hdiutil verify` gültig, `x86_64 arm64`, Signatur gültig |
| Abnahme | ✅ Apple Silicon und Intel (macOS 26): Installation aus der DMG, Aktualisierung 2.2.0 → 2.2.1 → 2.2.0 ohne Befund, Leerlauf gleich (20,5/21,0 % gegenüber 20,5/20,5 %; Intel 12,7/12,1 % gegenüber 12,3/12,0 %); Rosetta: Installation ✅ · Intel macOS 15 (virtuell): Start scheitert wie bei jeder Version am Metal-Fehler der virtuellen Maschine |
| Nicht geprüft | macOS 13 (keine Testrechner mehr), Starttest aus der DMG auf macOS 15 Apple Silicon (nicht zugeteilt); Titel mit 96/192 kHz setzen im Offline-Testmodus nach Formatwechseln verspätet ein (mit 2.1 genauso) – im Echtbetrieb nicht geprüft |


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
