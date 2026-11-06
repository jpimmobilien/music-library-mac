# Version 2.1 – Änderungsübersicht

Gezielte Verbesserungen und Fehlerbehebungen auf Grundlage von Version 2.0 – kein Neubau, kein Redesign.
Design, Ansichten, Player-Designs, Mini-Player, Navigation, Audio-Engine und alle Nutzerdaten bleiben erhalten.
Sicherung des Stands 2.0: Zweig `release-2.0` (Commit `3f7f899`).

## 1. Behobene Fehler

| Fehler | Ursache | Behebung |
|---|---|---|
| **„Hinzugefügt“ sortierte alphabetisch** | Beim Einlesen bekamen alle Titel denselben Zeitstempel; bei Gleichstand greift die alphabetische Ersatzsortierung | Hinzufügedatum **je Datei**: Apple Musik („Hinzugefügt“) → Erstellungsdatum der Datei → Finder „Hinzugefügt“ → erster Import. Das Änderungsdatum wird nie verwendet. Vorhandene Titel werden beim ersten Start einmalig im Hintergrund neu bestimmt; ein Datum wird nie durch eine schwächere Quelle ersetzt und beim erneuten Einlesen nie überschrieben. Alben: neuestes Datum ihrer Titel (wie iTunes). |
| **EQ-Fenster: Schalter und Presets ohne Wirkung** | Die Tafel zeigte einen hängengebliebenen Entwurf eines Reglers statt der echten Einstellung; beim Schließen schrieb der alte Entwurf die Einstellung zurück | Entwurf nur noch während des Ziehens; Schalter, Presets, eigene Presets und „Zurücksetzen“ verwerfen ihn und wirken sofort (Regler, Auswahl und Klang). Ausgeschalteter EQ ist eindeutig erkennbar (Bänder abgeblendet, Hinweis). |
| **Visualizer: ruhende Punkte** | Die Pegelanalyse wurde an das Ein-/Ausblenden des Players gekoppelt (bei einem Ansichtswechsel konnte das Abschalten nach dem Einschalten kommen) und bekam nur alle ≈ 100 ms Daten | Abgriff in **jedem** Audiozyklus (≈ 11 ms) in einen Ringpuffer, FFT bei Bedarf (höchstens 30 Bilder/s), Zählung der sichtbaren Anzeigen; Balken passen sich der Breite an, klingen bei Pause/Stopp aus |
| **Tonhöhe klang verzerrt** | macOS nutzte Apples `AVAudioUnitTimePitch`; es verschmiert Anschläge stark (gemessen: Vorecho nur 6–10 dB unter dem Anschlag) | Das Verfahren der Android-App (Phasen-Vocoder mit Anschlagerkennung und Phasenkopplung, Sinc-Umrechnung) nach Swift portiert und als eigene Audio-Unit in die Kette eingesetzt: Vorecho 25–32 dB unter dem Anschlag; Wechsel zwischen zwei Tonhöhen lückenlos überblendet |
| **Absturz unter macOS 26** (auch in 2.0) | Kompaktes Album-Raster mit immer sichtbaren Rollbalken: Rollbalken ↔ Kachelgröße schaukelten sich auf, AppKit brach mit einer Layout-Endlosschleife ab | Rasterspalten mit fester, aus der Fenstergröße berechneter Breite |
| Leertaste/Eingabe in Dialogen | wurden als Wiedergabe-Tasten abgefangen | Dialoge erhalten ihre Tasten selbst |

## 2. Neue Funktionen

- **Löschen per Kontextmenü** (Titel, Alben, Mehrfachauswahl): Dialog mit zwei klar getrennten Wegen –
  „Aus der Musikbibliothek entfernen“ (Datei bleibt, wird beim Neu-Einlesen nicht wieder aufgenommen, direkt
  danach rückgängig) und „In den Papierkorb legen“ (mit zweiter Bestätigung). „Abbrechen“ ist Standard; die
  Eingabetaste löst nie etwas Zerstörerisches aus. Bei Alben steht „Album „X“ – 12 Titel, 12 Dateien“ dabei.
- **Kontextmenüs** nach Vorgabe: Titel (Wiedergeben, Zur Warteschlange, Zu Playlist, Informationen bearbeiten,
  Favorit, Titel löschen …), Alben (Album wiedergeben, Zur Warteschlange, Albuminformationen bearbeiten,
  Album löschen …).
- **Feste Werkzeugleiste**: Ansicht, Sortierung, Filter, Darstellung und Einstellungen bleiben beim Scrollen
  in allen Bereichen und Ansichten sichtbar.
- **Mehrfachauswahl**: Aufziehen mit der Maus (auf freier Fläche sofort, auf einem Eintrag nach kurzem
  Halten – so bleibt Ziehen & Ablegen erhalten), ⇧-Klick (Bereich), ⌘-Klick (einzeln), ⌘A; Auswahlleiste
  mit Anzahl („3 Alben ausgewählt (38 Titel)“) und Aktionen: Wiedergeben, Zur Warteschlange, Zu Playlist,
  Informationen (Sammelbearbeitung – unterschiedliche Werte als „Gemischt“, nur geänderte Felder werden
  geschrieben), **Als Album zusammenfassen …** (Album, Album-Interpret, optional Jahr, Genre, Compilation,
  fortlaufende Titelnummern), Löschen …
- **Zufall je Bereich**: Alben → zufällige Alben, jedes in Titelreihenfolge, danach das nächste zufällige
  Album (auch beim Einschalten von „Zufall“ im Player, wenn aus der Alben-Ansicht gestartet); Titel → alle
  Titel der aktuellen Ansicht; Playlist, Interpreten, Genres, Favoriten → jeweilige Auswahl. Bei
  „Wiederholen“ beginnt jeder neue Durchgang neu gemischt ohne direkte Wiederholung.
- **Größere Cover**: Regler bis 560 pt (bisher 320), Spaltenzahl folgt der Fensterbreite, große Kacheln laden
  große Cover (scharf auf Retina).
- **Player-Hintergrund**: Automatisch (Cover), Rauchglas, Weiß, Schwarz, Hellgrau, Dunkelgrau, Rosa, Blau,
  Violett, eigene Farbe (macOS-Farbwähler); Schrift passt sich automatisch an; auf Wunsch leichte Tönung des
  Mini-Players. In den Einstellungen und im „…“-Menü des Players.
- **Mini-Player „Sehr groß“ und „Riesig“** mit eigenem Layout (Klein/Mittel/Groß unverändert): großes Cover,
  zweizeiliger Titel, großzügige Bedienung, Lautstärke, EQ- und Tonhöhen-Schaltfläche mit Wert.
- **Großer Player**: Format, Bitrate, Abtastrate, Bittiefe und „Hinzugefügt am …“ (Quelle als Hinweis).
- **Liquid Glass durchgängig**: Equalizer-, Einstellungs- und Informationsfenster mit Glaskarten.
- **Einstellungen → Bibliothek → Hinzufügedatum**: „Aus Apple Musik übernehmen …“ und „Neu bestimmen“.

## 3. Durchgeführte Tests

Alle Ergebnisse stammen aus echten Build-Läufen auf GitHub-Rechnern (virtuelle Macs) – Einzelheiten in
[STATUS.md](STATUS.md) und [PERFORMANCE.md](PERFORMANCE.md).

| Prüfung | Rechner | Ergebnis |
|---|---|---|
| Alle automatischen Tests (470, davon 44 neu) | macOS 26 Apple Silicon · macOS 15 Intel | 470/470 · 470/470 bestanden |
| Equalizer: jedes Preset im Klang gemessen, EQ aus = neutral | beide | bestanden (≤ 1,5 dB Abweichung) |
| Tonhöhe: Frequenzgenauigkeit, Bass, Höhen, Mono/Stereo, Anschläge, Akkord | beide | bestanden; Vorecho −25/−32 dB statt −6/−10 dB |
| Visualizer-Analyse (Ton im richtigen Band, Ruhe ohne Audio) | beide | bestanden |
| Alle 97 Ansichten hell/dunkel mit echtem Liquid Glass + Rückfall-Darstellung | macOS 26 Apple Silicon | 388 Bilder fehlerfrei, neue Ansichten angesehen |
| Absturz im kompakten Album-Raster (auch 2.0) | macOS 26 Apple Silicon | nachgestellt, behoben, erneut geprüft |
| DMG prüfen, installieren, Signatur, Architekturen | macOS 26 Intel | bestanden |
| Aktualisierung 2.0 → 2.1 → 2.0 im normalen Start mit echten Dateien und Nutzerdaten | macOS 26 Intel | ohne Befund: alle Daten erhalten, Hinzufügedatum je Datei, 2.0 öffnet die Datenbank weiterhin |
| Geschwindigkeit 2.0 ↔ 2.1 auf demselben Rechner (10.000 Titel) | macOS 26 Intel | Scrollen, Bereichswechsel, Suche gleich; Leerlauf ≈ +1,5 Prozentpunkte |

## 4. Einschränkungen

- **Nicht von Hand bedient:** Klicks im Löschdialog, Aufziehen der Auswahl, Ziehen & Ablegen, Farbwähler,
  Gesten – gebaut und als Vorschaubild geprüft, aber nicht automatisch bedienbar.
- **Nicht angehört:** EQ und Tonhöhe sind mit Messsignalen geprüft, nicht über Lautsprecher mit echter Musik.
- **DMG auf Apple Silicon:** GitHub teilte am 06.11.2026 keine Apple-Silicon-Rechner zu; die DMG wurde auf
  Intel installiert und gestartet. Dasselbe App-Bundle lief im Build auf Apple Silicon (Tests, alle Ansichten).
- **Apple-Musik-Übernahme** mit echter Mediathek, **macOS 13**, **echter Intel-Mac mit Grafikkarte** und
  **Gatekeeper** beim ersten Start: nicht ausprobiert.
- **Tonhöhe:** ≈ 0,14 s Verzögerung, solange die Tonhöhe verändert ist (wie Android); bei stehenden Akkorden ist
  Apples altes Verfahren minimal sauberer.
- **Hinzufügedatum ohne Apple Musik** = Erstellungsdatum der Datei (bei kopierten Dateien der Kopierzeitpunkt).
- **Leerlauf** mit Wiedergabe ≈ 1,5 Prozentpunkte höher als 2.0 (Ursache nicht eingegrenzt).

Vollständige Liste: [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md).
