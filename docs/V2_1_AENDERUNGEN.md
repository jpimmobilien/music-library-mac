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

Siehe [STATUS.md](STATUS.md) (Zahlen aus den Build-Läufen).

## 4. Einschränkungen

Siehe [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md).
