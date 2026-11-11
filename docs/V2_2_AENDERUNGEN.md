# Version 2.2 – Audio Studio

## 2.2.1 (11.11.2026) – Fehlerbehebung

- **Absturz beim Übergang zum nächsten Titel behoben** (gemeldet auf einem MacBook Pro 2017 mit macOS 13.7.8, betrifft
  auch 2.1 und 2.2.0): Wechselte der nächste Titel zwischen Mono und Stereo (bzw. das Format so, dass Knoten der
  Audio-Kette kurz verschiedene Ein- und Ausgangsformate hatten), brach AVAudioEngine mit einer Ausnahme ab
  (Fehler −10868). Ursache: Umverbinden bei nur pausierter Engine – dabei meldeten die eigene Tonhöhen-Unit und
  Apples Limiter einen Formatfehler. Jetzt wird die Engine beim Formatwechsel angehalten, alle Verbindungen werden
  gesetzt und gemeinsam vorbereitet; die Tonhöhen-Unit nimmt einen kurzzeitig ungleichen Zustand ohne Fehler hin.
- Neuer Test stellt den Absturz nach (vorher: Fehler −10868 auf macOS 15 und 26) und prüft Titelwechsel zwischen
  Mono/Stereo und 22,05–192 kHz mit und ohne Tonhöhe.


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

## Durchgeführte Tests

Alles auf echten Macs über GitHub Actions (Einzelheiten in [STATUS.md](STATUS.md)):

- **577 automatische Tests ohne Fehler** auf macOS 26 (Apple Silicon) und macOS 15 (Intel), davon rund 100 neu für
  das Audio Studio: jedes Format und jede MP3-Bitrate (Dauer, Abtastrate, Bitrate, Tags, Cover, Klang),
  Schnittgenauigkeit (0 Frames), Schneiden ohne Neukodierung, lange Dateien, beschädigte Dateien, Abbruch, Pause,
  Warteschlange, Ersetzen mit Sicherung und Rückgängig, Werkzeug-Installation mit Prüfsumme.
- **Echte Internet-Quellen:** SoundCloud (CC-lizenzierter Titel) bis zum fertigen MP3 mit Tags und Cover;
  Spotify liefert Titel und Cover und lehnt den Download ab. **YouTube** wurde auf den GitHub-Rechnern von YouTube
  blockiert (Anmeldung verlangt) – nicht umgangen, daher **nicht nachgewiesen**.
- **125 Ansichten** in Hell und Dunkel mit echtem Liquid Glass (davon 28 neu), angesehen.
- **Abnahme der DMG:** installiert und gestartet auf Apple Silicon (nativ und Rosetta) und Intel; Aktualisierung
  2.1 → 2.2 → 2.1 mit echten Dateien ohne Datenverlust; Geschwindigkeit wie 2.1 (innerhalb der Messstreuung).

## Einschränkungen

- YouTube nicht nachgewiesen (s. o.); Spotify-Audio bewusst nicht (DRM); keine Anmeldung/Cookies.
- Bedienung (Ziehen, Zoom, Ablegen, Tastatur) nicht von Hand geprüft; Klang gemessen, nicht angehört.
- Rohes AAC (.aac) ohne Tags und ≈ 60 ms länger – für die Bibliothek M4A verwenden.
- Opus/WebM/MKV-Dateien nur mit installiertem FFmpeg.
- Sicherungen ersetzter Originale werden nicht automatisch gelöscht.

Vollständige Liste: [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md).
