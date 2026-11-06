# Version 2.1 – Änderungsplan (risikoarm, gezielt)

Grundsatz: kein Neubau, kein Redesign. Liquid-Glass-Design, Ansichten, Player-Designs, Mini-Player, Navigation,
EQ-Grundlogik, Audio-Engine, Hell/Dunkel, Datenbank und alle Nutzerdaten bleiben. Geändert wird nur, was ein
Punkt des Auftrags verlangt. Sicherung des Stands 2.0: Zweig `release-2.0` (Commit `3f7f899`) auf GitHub und
ein Quellarchiv außerhalb des Projekts.

## Gefundene Ursachen (aus dem Code)

| Fehler | Ursache | Behebung |
|---|---|---|
| „Hinzugefügt“ sortiert alphabetisch | Beim Einlesen bekommen **alle** neuen Titel denselben Zeitstempel (`now` des Scans); bei Gleichstand greift die alphabetische Ersatzsortierung | Hinzufügedatum je Datei (Apple Musik → Erstellungsdatum → Finder „Hinzugefügt“ → Import), Herkunft gespeichert, Rekonstruktion der vorhandenen Titel, nie überschrieben |
| EQ-Fenster: Schalter/Presets ohne Wirkung | Die Tafel zeigt einen lokalen Entwurf (`draft`) an, solange er existiert; bleibt er nach einem Ziehen hängen, wirken Schalter und Presets zwar im Hintergrund, die Anzeige bleibt aber stehen, und beim Schließen schreibt der alte Entwurf die Einstellung zurück | Entwurf nur während des Ziehens; jede Taste/jedes Preset verwirft ihn; Sicherheits-Übernahme nach kurzer Ruhe |
| Visualizer: ruhende Punkte | (1) An-/Abschalten hing an `onAppear`/`onDisappear` des Players – bei einem Ansichtswechsel kann das Abschalten nach dem Einschalten kommen; (2) der Tap des Mischers liefert nur alle ≈ 100 ms Daten, dazwischen fallen die Balken auf 0 | Zählung sichtbarer Anzeigen; Abgriff je Renderzyklus (≈ 11 ms) in einen Ringpuffer, FFT auf Abruf (30 Bilder/s), Pause → sanftes Abklingen |
| Tonhöhe klingt verzerrt | macOS nutzt Apples `AVAudioUnitTimePitch` (Phasen-Vocoder mit Standard-Überlappung 8); Android nutzt einen eigenen hochwertigen Phasen-Vocoder (4096er-FFT, Phasenkopplung, Anschlagerkennung) + Sinc-Resampler | Portierung der Android-Klangverarbeitung nach Swift als eigene Audio-Unit in derselben Kette; Messung (Frequenz, Störabstand) gegen Apple-Verfahren |

## Umsetzung je Punkt

- **§3 Hinzugefügt:** Spalte `dateAddedSource` (additiv, Version 2.0 kann die Datenbank weiter öffnen),
  Tabelle `app_meta`; `DateAddedResolver` (getestet); Rekonstruktion einmalig im Hintergrund, Apple-Musik-Abgleich
  über die freigegebene Mediathek-XML bzw. auf Wunsch über das iTunesLibrary-Framework (Systemfreigabe nötig).
  Alben: neuestes Datum ihrer Titel.
- **§4 Löschen:** Kontextmenüs für Titel und Alben; Dialog mit zwei getrennten Wegen „Aus der Musikbibliothek
  entfernen“ (Datei bleibt, wird beim Neu-Einlesen nicht wieder aufgenommen) und „In den Papierkorb legen“;
  Abbrechen ist Standard; Anzahl Titel/Dateien wird genannt.
- **§5 Visualizer:** siehe oben; Balken passen sich der Breite an, Hell/Dunkel.
- **§6 Tonhöhe:** siehe oben.
- **§7 EQ:** siehe oben; Klangtest je Preset (offline gemessen).
- **§8 Werkzeugleiste:** feste Zeile unter dem Seitentitel, bleibt beim Scrollen stehen.
- **§9 Zufall:** Alben-Ansicht → Zufall nach Alben (ganzes Album in Titelreihenfolge, dann nächstes zufälliges);
  sonst Titel der jeweiligen Auswahl; neuer Durchgang bei „Wiederholen“ ohne direkte Wiederholung.
- **§10 Mehrfachauswahl:** Aufziehen mit der Maus, ⇧-Bereich, ⌘-Einzeln; Leiste mit Anzahl; Sammelbearbeitung
  (nur geänderte Felder werden geschrieben, gemischte Werte bleiben unberührt); „Als Album zusammenfassen …“.
- **§11 Cover:** Regler bis 560 pt, Spaltenzahl folgt der Breite.
- **§12 Player-Hintergrund:** Automatisch, Rauchglas, Weiß, Schwarz, Hellgrau, Dunkelgrau, Rosa, Blau, Violett,
  eigene Farbe (macOS-Farbwähler); Schriftfarbe automatisch.
- **§13 Mini-Player:** zusätzlich „Sehr groß“ und „Riesig“ mit eigenem Layout; bisherige Größen unverändert.
- **Zusatz:** Bitrate/Format und Hinzufügedatum im großen Player; Glas-Karten in Equalizer-, Einstellungs- und
  Informationsfenster.

## Prüfung

Logik-Tests (Hinzufügedatum, Zufall nach Alben, Datenbank-Migration), Klangtests (Presets, Tonhöhe),
Vorschaubilder aller neuen Zustände (inkl. aller fünf Mini-Player-Größen), Messlauf mit 10.000 Titeln.
