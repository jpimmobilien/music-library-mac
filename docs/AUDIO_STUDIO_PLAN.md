# Audio Studio (Version 2.2) – Analyse und Umsetzungsplan

Erweiterung der bestehenden App, kein Neubau. Bibliothek, Player, EQ, Tonhöhe und Wiedergabe bleiben
unverändert; die Datenbank wird nicht verändert (Verlauf und Einstellungen des Studios liegen getrennt).

## 1. Analyse des Bestands

| Bereich | Befund | Folge für das Audio Studio |
|---|---|---|
| Aufbau | Swift-Paket: `MLCore` (reine Logik), `MLStore` (SQLite), `MLTags` (TagLib 2.3.2), `OggVorbis`, App `MusicLibrary` (SwiftUI + AppKit) | neue Module `MLStudio` (reine Logik, unter Linux testbar) und `StudioEngine` (Verarbeitung, macOS); Oberfläche in `MusicLibrary/Studio` |
| Navigation | schwebende Glas-Leiste mit sechs Bereichen (`NavBar`, `LibrarySection`), je Bereich ein Navigationsstapel | siebter Eintrag „Studio“ als eigener Modus (`AppModel.studioOpen`), `LibrarySection` bleibt unverändert (gespeicherte Einstellungen bleiben gültig) |
| Design | `glassSurface`, `MusicColors`, `Typo`, `Motion`, eigene Symbole (`Icons`/`IconData`), Liquid Glass ab macOS 26 mit Rückfall | Studio verwendet ausschließlich diese Bausteine |
| Tags | `MLTags.TagFile.write` (MP3, M4A, FLAC, WAV, AIFF inkl. Cover) | Metadaten und Cover beim Export über MLTags; roher AAC-Datenstrom kann keine Tags tragen (ehrlich angezeigt) |
| Bibliothek | `LibraryService.rescan` liest neue Dateien ein (Hinzufügedatum, Tags, Cover), `refreshTrack(uid:)` für geänderte Dateien | Import = Datei in einen Musikordner legen und einlesen; ersetzte Originale behalten Pfad, Kennung, Favoriten, Playlists und Statistik |
| Wiedergabe | eigene Audio-Kette (`AudioEngine`, `PlayerService`) | Vorhören über einen eigenen, getrennten `AVAudioEngine` |
| Build | GitHub Actions (Xcode 26, Universal Binary), Vorschaubilder im Demo-Modus | neuer Workflow `studio.yml` für Entwicklungsstände; Release über `build.yml` |

## 2. Entscheidungen

- **Spotify:** Audio ist kopiergeschützt (DRM). Das Umgehen wäre eine Umgehung von Zugriffsbeschränkungen und
  wird **nicht** umgesetzt. Spotify-Links liefern Titel und Cover (öffentliche oEmbed-Schnittstelle) und eine klare Meldung.
- **YouTube und SoundCloud:** über das Open-Source-Werkzeug **yt-dlp** (Unlicense). YouTube braucht zusätzlich die
  JavaScript-Laufzeit **Deno** (MIT). Beide werden **nicht** mit der App ausgeliefert, sondern auf ausdrücklichen
  Wunsch („Werkzeuge installieren“) von den offiziellen GitHub-Veröffentlichungen geladen, per SHA-256 geprüft und
  in „Application Support“ abgelegt; vorhandene Installationen (z. B. Homebrew) werden erkannt. Keine Anmeldung,
  keine Cookies, keine Umgehung von Altersbeschränkungen, privaten Inhalten oder Bezahlschranken – solche Quellen
  werden mit einer verständlichen Meldung abgelehnt. Kurze Hörproben (z. B. SoundCloud Go+) werden erkannt.
- **Kein FFmpeg in der App.** Lesen über AVFoundation (MP3, AAC/M4A, ALAC, WAV, AIFF, FLAC, CAF, Video MP4/MOV/M4V)
  und den vorhandenen Ogg-Vorbis-Decoder; Schreiben nativ (WAV, AIFF, AAC, M4A über AudioToolbox), **MP3 mit LAME
  3.100** (LGPL, als Quelltext eingebunden) und **FLAC mit libFLAC 1.5** (BSD). Ein installiertes FFmpeg wird nur
  für exotische lokale Formate (z. B. WebM, MKV) genutzt, falls vorhanden.
- **Ehrlichkeit:** Hinweise, wenn verlustbehaftete Quellen verlustfrei gespeichert oder höher abgetastet werden;
  die Angaben nach dem Export werden aus der fertigen Datei gelesen.
- **Sicherheit:** keine Downloads ohne Nutzeraktion, keine versteckten Hintergrundprozesse, keine Weitergabe von
  Adressen an Dritte, keine Zugangsdaten.

## 3. Funktionen

1. **Quelle:** Adressfeld (mehrere Zeilen = mehrere Aufträge), Einfügen aus der Zwischenablage, Drag & Drop und
   „Öffnen …“ für Audio- und Videodateien; Karte mit Vorschaubild, Titel, Dauer, Format und Metadaten.
2. **Editor:** Wellenform (Hüllkurve in Stufen, flüssig auch bei langen Dateien), Start/Ende durch Ziehen, exakte
   Zeitfelder, Zoom (Regler, Trackpad, Mausrad mit ⌘), Vorhören der Auswahl, Wiedergabe/Pause, ganze Datei oder
   Ausschnitt, Ein-/Ausblenden.
3. **Format und Qualität:** MP3 (96–320 kbit/s), WAV (16/24/32 Float; 44,1/48/96 kHz), FLAC (Stufe 0–8, Bittiefe
   und Abtastrate wie Quelle), AAC, M4A, AIFF – mit sinnvollen Standardwerten.
4. **Dateiname und Metadaten:** „Interpret – Titel“, „Titel – Interpret“, „Titel“ oder eigener Name; Interpret,
   Titel, Album, Jahr, Genre, Titelnummer, Cover (aus Vorschaubild, Datei oder Einfügen).
5. **Ziel:** nur speichern (frei wählbarer Ordner) oder in einen Musikordner der Bibliothek (Unterordner wählbar)
   und einlesen; Doppel-Warnung (gleicher Titel/Interpret/Dauer oder Quelle schon exportiert); „Im Finder zeigen“.
6. **Warteschlange:** mehrere Quellen, Format je Auftrag, gemeinsame Einstellungen, Anhalten/Fortsetzen,
   Abbrechen, Wiederholen, Fortschritt und Fehler je Auftrag, nach einem Fehler weiter mit dem nächsten,
   Exportverlauf (JSON, 500 Einträge).
7. **Schneiden vorhandener Songs** (Nachtrag vom 08.11.2026): Rechtsklick auf einen Titel → „Im Audio Studio
   schneiden …“. Speichern als neue Datei neben dem Original (Standard) oder „Original ersetzen“ (Sicherung vorher,
   Bestätigung, „Rückgängig“ im Verlauf). „Format wie Original“: MP3 an Frame-Grenzen und M4A ohne Neukodierung,
   verlustfreie Formate exakt. Alle Tags, Cover und Liedtexte bleiben erhalten; Favoriten, Playlists und Statistik
   bleiben beim Ersetzen am Titel.

## 4. Architektur

```
MLStudio (rein)            StudioEngine (macOS)                      MusicLibrary/Studio (Oberfläche)
 Formate, Optionen          Decoder (AVFoundation, Ogg)               StudioModel  ── Zustand, Abläufe, Warteschlange
 Aufträge, Warteschlange    Resampler/Dither/Schnitt/Blenden          StudioView   ── Quelle · Editor · Export · Warteschlange
 Dateinamen, Doppelte       Encoder: LAME, libFLAC, AudioToolbox      WaveformEditor, ExportPanel, MetadataPanel …
 Wellenform-Stufen          Tags (MLTags), Wellenform, Vorhören       Demo-Dienste für Vorschaubilder
 yt-dlp-JSON, Zeiten        Werkzeuge (yt-dlp/Deno), Downloader
 Protokolle (Dienste)       lokale Analyse
```

Alle Dienste sind Protokolle (`StudioServiceSet`); alles Langsame läuft in abbrechbaren Hintergrund-Tasks.

## 5. Tests

- `MLStudioTests` (auch unter Linux): Optionen, Hinweise, Dateinamen, Quellen-Erkennung, yt-dlp-Zuordnung,
  Warteschlange, Doppelte, Wellenform-Stufen, Zeiten, Einstellungen.
- `StudioEngineTests` (macOS): Export jedes Formats aus erzeugten Signalen (MP3 alle Bitraten, WAV 16/24/32F,
  44,1/48/96 kHz, FLAC, AAC, M4A, AIFF) mit Prüfung von Dauer, Endung, Abtastrate, Bitrate, Tags und Cover
  (zusätzlich ffprobe), Schnittgenauigkeit, Blenden, ohne Neukodierung, lange Dateien, kurze Ausschnitte,
  fehlerhafte Dateien, Abbruch, unterschiedliche Abtastraten, Klangvergleich (Störabstand) gegen die Quelle.
- App: Warteschlange mit Ersatzdiensten (Reihenfolge, Pause, Abbruch, Fehler), Import in die Bibliothek,
  Ersetzen mit Sicherung und Rückgängig.
- Internet-Quellen: nur frei lizenzierte Testinhalte, sofern GitHub-Rechner nicht blockiert werden.
- Vorschaubilder aller Studio-Ansichten in Hell und Dunkel (Liquid Glass).

## 6. Auslieferung

Version 2.2.0, Universal-DMG (arm64 + x86_64), Abnahme mit Aktualisierungstest (2.1 → 2.2).
