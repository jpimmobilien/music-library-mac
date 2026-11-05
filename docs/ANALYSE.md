# Phase 1 – Analyse: Android 1.3.0 → macOS

Grundlage: das Android-Projekt *Musikbibliothek 1.3.0* (Kotlin/Compose, unverändert gelassen) und der
Master-Prompt. Die PDF-Designstudie diente nur als Funktionsreferenz, nicht als Vorlage.

## Leitlinien

- **Keine iTunes-Kopie.** Keine Apple-Music-Seitenleiste, keine Tabellen. Stattdessen das Android-Konzept,
  für große Fenster weitergedacht: schwebende Glas-Navigation mit sechs Bereichen und Rosé-Linse, große
  Titel mit eigener Suche, kompakte Glas-Titelleiste beim Scrollen, schwebender Mini-Player, Vollbild-Player,
  der die Bibliothek verkleinert zurücktreten lässt.
- **Dieselben Regeln wie Android:** Die gesamte Fachlogik (Gruppierung, Sortierung, Suche, Warteschlange,
  Zufall, Zählregeln, Fortsetzen, Sleep-Timer, Equalizer-Modell, Duplikate, Liedtext, Coverfarben,
  Renderer der Player-Designs) wurde 1:1 aus dem Kotlin-Code nach Swift übertragen und mit den
  Android-Testfällen plus eigenen Tests geprüft.
- **Mac-Ergänzungen:** Musikordner statt Medienbibliothek, Mehrfachauswahl, Ziehen & Ablegen, Kontextmenüs,
  Tastaturkürzel und Menüleiste, Seitenleiste für Warteschlange/Liedtext, Mini-Player-Fenster,
  Menüleisten-Player, Medientasten/Kontrollzentrum, vollständige Metadaten-Bearbeitung mit Sicherung.

## Funktionsabgleich

| Bereich | Android 1.3.0 | macOS |
|---|---|---|
| Bibliotheksquelle | MediaStore (automatisch) | gewählte Ordner (Lesezeichen), FSEvents-Überwachung, Laufwerke ein/aus, Abgleich per Größe/Datum/Dateinummer (`SyncPlanner`) |
| Tags lesen | eigene Leser (ID3, MP4, Vorbis, RIFF, AIFF) | TagLib 2.3.2 (MP3, M4A/AAC/ALAC, FLAC, Ogg Vorbis/Opus/FLAC/Speex, WAV, AIFF, WMA, WavPack, TTA, DSF/DFF) |
| Tags schreiben | – | **neu**: alle Felder, mehrere Cover, Liedtext (auch synchron), Mehrfachbearbeitung, Kopieren/Einfügen; sichere Schreibstrategie mit Sicherung, Kopie, Prüfung, Ersetzen und Rückgängig |
| Sechs Bereiche | Titel · Alben · Playlists · Interpreten · Genres · Favoriten | gleich (⌘1–⌘6), je eigene Suche und gespeicherte Sortierung |
| Alben | mehrere CDs = ein Album, gleichnamige getrennt | gleich (`AlbumGrouping`, Android-Testfälle) |
| Interpreten | inkl. Album-Interpreten und „feat.“ | gleich (`ArtistNames`) |
| Genres | 26 Familien + 5 Titelbilder | gleich, Symbole und Titelbilder aus Android übernommen |
| Playlists | eigene + Favoriten/Meistgespielt/Am wenigsten/Jahrzehnte | gleich; Reihenfolge per Ziehen, Titel per Ziehen hinzufügen, Duplizieren |
| Favoriten | Titel und Alben getrennt | gleich |
| Duplikate | – | **neu** (`DuplicateFinder`) |
| Verlauf, Fortsetzen | Zähler, zuletzt gespielt | **neu**: Wiedergabeverlauf; Position langer Titel wird gemerkt; Start mit letzter Warteschlange |
| Player-Designs | Vinyl Studio, Classic, Cassette Studio, Portable CD | alle vier, Renderer 1:1 portiert (Bildebenen gegen die Kotlin-Renderer verglichen) |
| Visualisierung | optional | optional (FFT 16 Bänder + Pegel L/R) |
| Equalizer | 10 Bänder ±12 dB, Voreinstellungen, Bass, Aussteuerung | gleich (AVAudioUnitEQ + Kuhschwanz) |
| Tonhöhe | Tonhöhe (Tempo bleibt) / Schallplatte | gleich + **Tempo** separat (AVAudioUnitTimePitch / Varispeed) |
| Lautstärke | 0–300 % mit Limiter | gleich (Mischer + AUPeakLimiter) |
| Sleep-Timer | Minuten, Ende des Titels, sanftes Ausblenden | gleich |
| Systemsteuerung | Medienkarte, Widgets | Kontrollzentrum/Medientasten (MPRemoteCommandCenter), Dock-Menü, Menüleisten-Player, Mini-Player-Fenster |
| Löschen | Papierkorb mit Rückgängig | Papierkorb des Finders |
| Darstellung | hell/dunkel/System | gleich; Liquid Glass ab macOS 26, sonst Unschärfe-Glas |

## Architektur

Siehe [ARCHITEKTUR.md](ARCHITEKTUR.md).

## Risiken (zu Beginn)

| Risiko | Umgang |
|---|---|
| Keine macOS-Build-Umgebung in der Entwicklungsumgebung (Linux) | Reine Module unter Linux gebaut und getestet; App-Ziel nur auf macOS baubar → GitHub Actions (macOS 26 arm64, macOS 15 Intel) bzw. `Build.command` auf dem eigenen Mac |
| Ogg wird von macOS nicht abgespielt | Ogg Vorbis über stb_vorbis; Opus offen (siehe NICHT_UMGESETZT.md) |
| Tags schreiben kann Dateien beschädigen | Schreiben nur auf Kopie, erneutes Lesen und Vergleichen, atomares Ersetzen, Sicherung + Journal + Rückgängig; getestet mit 16 Formaten |
| Liquid Glass nur mit macOS-26-SDK | `#if compiler(>=6.2)` + `#available(macOS 26)`; Rückfall mit Unschärfe, Tönung, Glanzkante |
| Ad-hoc-Signatur | Gatekeeper-Rückfrage beim ersten Start, dokumentiert in INSTALLATION.md |
