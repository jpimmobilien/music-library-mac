# Version 2.6 – KI-Hörbücher & Hörspiele (lokal)

Neuer Eintrag **„KI-Hörbücher“** in der Navigation (⌘0, zwischen „KI-Musik“ und „Hinzufügen“). Aus einer Idee wird
ein Hörbuch oder ein Hörspiel – Geschichte, Stimmen, Geräusche, Musik und Mischung entstehen vollständig auf dem Mac,
ohne Cloud, Konto oder Kosten. Grundlage, Messungen und Lizenzen: [KI_HOERSPIEL_MACHBARKEIT.md](KI_HOERSPIEL_MACHBARKEIT.md).

## Voraussetzungen

- Mac mit **Apple-Chip** und macOS 14 oder neuer (geprüft: macOS 15 und 26). Auf Intel-Macs zeigt „KI-Hörbücher“
  nur einen Hinweis – die Bibliothek bleibt unverändert nutzbar.
- Einmalige Einrichtung auf Knopfdruck: eigene Python-Umgebung (uv, feste Paketstände), Geschichtenmodell und
  zwei Stimmmodelle. Mit 32 GB und mehr: **Gemma 4 26B-A4B** (15,4 GB); 16–32 GB: Qwen3.5 9B; 8–16 GB: Qwen3.5 4B.
  Stimmen: Qwen3-TTS 1.7B VoiceDesign und Base (je 4,5 GB). Optional: Geräusche (Stable Audio 3 small, 3,5 GB) und
  Referenzanalyse (Whisper, Silero VAD, SpeechBrain ECAPA, 1,7 GB). Alles unter
  `~/Library/Application Support/Music Library/KI-Hoerspiel`, einzeln oder vollständig entfernbar.
- Musik kommt aus der vorhandenen **KI-Musik** (wenn eingerichtet); ohne sie entsteht die Mischung ohne Musik.

## Bereiche

- **Hörspiel erstellen / Hörbuch erstellen:** Idee wie im Gespräch („Ein Jugendkrimi im Sommer 1984 …“), Vorlagen,
  Länge 5–120 Minuten oder frei (2–180), eigene Figuren, Stilreferenz, Sprache (Deutsch, Englisch, Französisch,
  Spanisch, Italienisch), Klang der 1980er (Hörspiel) bzw. Erzählstil (Hörbuch), Musik und Geräusche an/aus.
  Danach läuft die ganze Produktion in acht Schritten mit Fortschritt; nach jedem Teilschritt gespeichert –
  abgebrochene Produktionen setzen fort, einzelne Schritte lassen sich neu ausführen.
- **Geschichte:** Konzept mit Figuren, Kapiteln, Szenen und **Spurenplan**; jede Szene einzeln mit dem Stand der
  bisherigen Handlung; danach ein **Lektorat**, das Widersprüche und Logiklücken sucht und betroffene Szenen gezielt
  überarbeitet (die vorige Fassung bleibt erhalten; schlechtere Überarbeitungen werden verworfen). Eigene Geschichten –
  genannte Serien dienen nur als allgemeine Stilrichtung.
- **Geschichten-Editor:** Kapitel und Szenen ansehen, Titel/Raum/Inhalt ändern, Repliken bearbeiten, Sprecher und
  Tonfall wechseln, Repliken vom Sprachmodell neu formulieren oder neu sprechen lassen, Szenen neu schreiben,
  frühere Fassungen wiederherstellen, Figuren hinzufügen/entfernen, eigene Aussprache. Das Lektorat zeigt seine
  Hinweise mit Sprung zur Szene und kann erneut laufen. Änderungen markieren nur die abhängigen Schritte als veraltet.
- **Mehrspur:** Spuren für Erzähler, jeden Sprecher, Musik, Geräusche, Atmo – Solo, Stumm, Lautstärke je Spur; Clips
  verschieben, schneiden, ein-/ausblenden, Pegel; Pausen ab der Abspielposition einfügen/entfernen; „Neu abmischen“.
- **Stimmenstudio:** Stimmen aus Einstellungen (Geschlecht, Alter, Tonhöhe, Klangfarbe, Tempo, Artikulation,
  Stimmung, Akzent) oder freier Beschreibung entwerfen. Drei Arten, jede deutlich gekennzeichnet: **entworfen**
  (synthetisch), **Stilprofil** (nur allgemeine Merkmale aus einer Referenz, kann nicht sprechen – daraus lässt sich
  eine eigenständige Stimme entwerfen, die Tonhöhe und Tempo trifft), **berechtigt** (Stimme einer realen Person nur
  mit gesprochener Einwilligung; die App prüft per Spracherkennung und Stimmvergleich).
- **Referenz analysieren:** eigene Aufnahmen (z. B. ein altes Hörspiel) auswerten – Sprecher und Redeanteile,
  Rollen (geschätzt), Tonhöhe, Tempo, Klangfarbe, Pausen, Dialogtempo, Bandbreite, Rauschen, Nachhall, Musikbrücken.
  Optional die bekannte Zahl der Stimmen. Gespeichert werden nur allgemeine Merkmale.
- **Sounddesign:** Geräusche aus einer Beschreibung erzeugen, eigene Dateien mit Herkunft/Lizenz aufnehmen,
  Bibliothek durchsuchen und vorhören. Geräusche werden unter die Sprache „geduckt“.
- **Meine Produktionen:** Liste mit Stand, Länge, Lautheit; Anhören, Umbenennen, Papierkorb, Ordner zeigen;
  **Export** als MP3 (128–320 kbit/s), M4A, FLAC oder WAV – ganz (MP3/M4A mit **Kapitelmarken**), je Kapitel, je
  Szene oder als Einzelspuren, mit Titel, Interpret, Genre und Cover.

## Technik und Datenschutz

- Eigener Python-Prozess (mlx-lm, mlx-audio, mlx-whisper) in einer **Sandbox ohne Netzwerk**, mit niedriger
  Priorität; Modelle werden nacheinander geladen und nach einstellbarer Leerlaufzeit entladen. Die Oberfläche bleibt
  bedienbar, die Bibliothek ist nicht betroffen.
- Downloads nur auf Knopfdruck, mit geprüftem Stand (Commit) je Modell; ohne Anmeldung oder Token.
- Produktionen liegen als Dateien in `~/Music/KI-Hörspiele` – **keine Änderung der Bibliotheksdatenbank**.
- Lizenzen von Code und Gewichten getrennt geprüft (Qwen3-TTS, Gemma 4, Qwen3.5, Whisper, Silero, ECAPA:
  Apache-2.0/MIT; Stable Audio 3: Stability AI Community License, kostenlos unter 1 Mio. US-Dollar Jahresumsatz).

## Geprüft

App-Abnahme mit der gebauten App auf Apple Silicon (macOS 15.8 und 26.7, virtuelle M1): je **25 von 25**
Prüfungen – Einrichtung, Hörspiel mit Lektorat, Stimmen, Geräuschen und Kapiteln, Replik neu formulieren und neu
sprechen, Mehrspur, alle Exporte, Hörbuch mit Abbrechen mitten in „Stimmen erzeugen“ und Fortsetzen (fertige Zeilen
bleiben unverändert), Stimmenstudio, Referenzanalyse. Details und Grenzen:
[KI_HOERSPIEL_MACHBARKEIT.md](KI_HOERSPIEL_MACHBARKEIT.md) und [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md).
