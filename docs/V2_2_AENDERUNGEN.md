# Version 2.2 – Audio Studio

Erweiterung der bestehenden App, kein Neubau: Bibliothek, Player, Equalizer, Tonhöhe, Wiedergabe, Design und
Datenbank bleiben unverändert. Neu ist der Bereich **Studio** in der Navigation (⌘7). Plan und Architektur:
[AUDIO_STUDIO_PLAN.md](AUDIO_STUDIO_PLAN.md).

## Neue Funktionen

- **Quellen:** Adresse einfügen (YouTube, SoundCloud; mehrere Zeilen oder Playlists/Sets = mehrere Aufträge, höchstens
  200), Einfügen aus der Zwischenablage, Audio- und Videodateien ziehen oder öffnen (MP3, AAC/M4A, ALAC, WAV, AIFF,
  FLAC, CAF, Ogg Vorbis, MP4/MOV/M4V; mit installiertem FFmpeg auch WebM, MKV, Opus). Quellkarte mit Vorschaubild,
  Titel, Hochlader, Dauer, Format und Metadaten; verständliche Meldungen bei Live-Übertragungen, Hörproben, privaten,
  altersbeschränkten oder gesperrten Inhalten.
- **Spotify:** nur Titel und Cover (Spotify-Audio ist kopiergeschützt; es wird nicht geladen).
- **Werkzeuge für Internet-Quellen:** yt-dlp und Deno auf Knopfdruck von den offiziellen GitHub-Veröffentlichungen,
  SHA-256-geprüft, in „Application Support“; vorhandene Homebrew-Installationen werden genutzt. Keine Anmeldung,
  keine Cookies, keine Umgehung von Sperren.
- **Editor:** Wellenform (auch bei Stunden-Dateien flüssig), Start/Ende ziehen, exakte Zeitfelder (↑/↓ ±0,1 s),
  I/O setzen Start/Ende am Abspielkopf, Zoom (Regler, Trackpad, ⌘-Mausrad), Vorhören mit Leertaste (eigener
  Wiedergabeweg, Hauptplayer unberührt), Ein-/Ausblenden, ganze Datei oder Ausschnitt.
- **Formate:** MP3 96–320 kbit/s (LAME 3.100), WAV 16/24/32 Float bei 44,1/48/96 kHz, FLAC Stufe 0–8 mit Bittiefe
  und Abtastrate der Quelle (libFLAC 1.5.0), AAC, M4A, AIFF – mit Standardwerten und ehrlichen Hinweisen
  (z. B. „verlustbehaftete Quelle wird durch WAV nicht besser“).
- **Dateiname und Metadaten:** „Interpret – Titel“, „Titel – Interpret“, „Titel“ oder eigener Name; Interpret,
  Titel, Album, Jahr, Genre, Titelnummer, Cover (Vorschaubild, Datei, Einfügen, Ziehen).
- **Ziel:** in einen Musikordner der Bibliothek (Unterordner wählbar) und automatisch einlesen, oder nur speichern;
  Warnung bei möglichen Dubletten und bei schon exportierten Quellen; „Im Finder zeigen“.
- **Warteschlange:** mehrere Aufträge, Format je Auftrag, Anhalten/Fortsetzen (auch mitten im Laden), Abbrechen,
  Wiederholen, Fortschritt und Fehler je Auftrag, nach einem Fehler weiter mit dem nächsten; Exportverlauf mit Suche.
- **Schneiden vorhandener Songs:** Rechtsklick auf einen Titel → „Im Audio Studio schneiden …“. Speichern als neue
  Datei neben dem Original (Standard) oder **Original ersetzen** (Sicherung mit Prüfsumme vorher, Bestätigung,
  „Rückgängig“ im Verlauf). „Format wie Original“: MP3 und M4A **ohne Neukodierung**, WAV/FLAC/AIFF bitgenau.
  Tags, Cover und Liedtexte bleiben; beim Ersetzen bleiben Favoriten, Playlists und Statistik am Titel.
- **Einstellungen → Audio Studio:** Werkzeuge, Standardformat, Ziel, Dateiname.

## Technik

- Neue Module `MLStudio` (reine Logik, auch unter Linux getestet) und `StudioEngine` (Verarbeitung); Oberfläche in
  `MusicLibrary/Studio`. Alles Langsame in abbrechbaren Hintergrund-Tasks.
- Eingebundene Bibliotheken als Quelltext: LAME 3.100 (LGPL, gegen den offiziellen Tarball geprüft), libFLAC 1.5.0
  (BSD-3, gegen den offiziellen Tarball geprüft). Lizenztexte im App-Paket. Kein FFmpeg in der App.
- Keine Datenbankänderung. Verlauf (`history.json`), Werkzeuge, Zwischenspeicher und Sicherungen unter
  `~/Library/Application Support/Music Library/Audio Studio`; Einstellungen unter einem eigenen Schlüssel.

## Tests

Siehe [STATUS.md](STATUS.md).

## Einschränkungen

Siehe [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md).
