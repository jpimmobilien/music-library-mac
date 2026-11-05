# Version 2 – Funktionsmatrix Android → macOS

Grundlage: Android-App *Musikbibliothek 1.3.0* (unverändert) und der Master-Prompt für Version 2.
Spalte **Prüfung**:

- **T** – automatischer Test in der Build-Pipeline (Unit-, Audio- oder Listen-Test, macOS 26 arm64 und macOS 15 Intel)
- **B** – Vorschaubild aus der laufenden App, hell und dunkel: alle 65 Ansichten auf macOS 14 (Apple Silicon),
  eine Auswahl mit dem Intel-Teil über Rosetta. Bilder mit echtem Liquid Glass (macOS 26) konnten in dieser Runde
  nicht erzeugt werden, weil GitHub keine macOS-26-Apple-Silicon-Rechner zuteilte (siehe STATUS.md).
- **M** – im Messlauf mit 10.000 Titeln ausgeführt
- **–** – gebaut, aber ohne Bildschirm/Trackpad/Lautsprecher nicht automatisch prüfbar (bitte beim ersten Start ausprobieren)

## Bibliothek

| Funktion | Android 1.3.0 | macOS Version 2 | Prüfung |
|---|---|---|---|
| Bereiche | Titel · Alben · Playlists · Interpreten · Genres · Favoriten | gleich, ⌘1–⌘6, Startbereich einstellbar | B |
| Darstellung | Liste bzw. Raster je Bereich | **Raster, kompaktes Raster, Liste, Detailliste (Spalten), Cover Flow** in **allen** Bereichen (auch Favoriten-Titel/-Alben), je Bereich gespeichert | B, M |
| Covergröße, Abstand | – | Regler (90–320 pt, 6–40 pt) und Zwei-Finger-Zoom, je Bereich gespeichert | B (Regler), – (Zoom) |
| Zusatzinfos | – | ein-/ausblendbar (Jahr, Genre, Anzahl); Detailliste mit wählbaren Spalten, Sortieren per Klick auf die Spaltenüberschrift | B |
| Cover Flow | – | räumlich gedrehte Nachbarcover mit Spiegelung; Ziehen, Trackpad, Mausrad, ← →, Positionsregler; Doppelklick/Eingabe spielt bzw. öffnet | B, – (Gesten) |
| Überfahren | – | Kachel hebt sich, Abspiel- und Herz-Schaltfläche erscheinen | – |
| Mehrfachauswahl | lange drücken | ⌘-/⇧-Klick, ⌘A, Pfeiltasten, in allen Ansichten | – |
| Ziehen & Ablegen | Playlist-Reihenfolge | Titel/Alben auf Playlists, „Neue Playlist“, Reihenfolge in Playlists, aus dem Finder | – |
| Kontextmenüs | lange drücken | Rechtsklick auf Titel, Alben, Interpreten, Genres, Playlists (auf die ganze Auswahl) | – |
| Sortierung | je Bereich | je Bereich gespeichert, **neu**: Album, Album-Interpret, Hinzugefügt, Bewertung, BPM (Titel); Hinzugefügt, Titelanzahl (Alben); Albenanzahl (Interpreten); Erstellt, Geändert (Playlists); Hinzugefügt, Bewertung (Favoriten) | T, B |
| Filter | – | **neu**: Genres, Jahrzehnte, Interpreten (durchsuchbar), Formate, Schnellfilter (Favoriten, Nie gespielt, Neu in 30 Tagen, Verlustfrei, Mit Liedtext, Ohne Cover, Gut bewertet); aktive Filter als Chips, Anzeige „x von y“ | T, B |
| Suche | ein Begriff | mehrere Begriffe (alle müssen passen), je Bereich, verzögert und im Hintergrund | T, M |
| Große Bibliotheken | MediaStore | 10.000 Titel im Messlauf, Listen im Hintergrund, Cover vorab verkleinert und zwischengespeichert | T, M |

## Player

| Funktion | Android 1.3.0 | macOS Version 2 | Prüfung |
|---|---|---|---|
| Player-Designs | Vinyl Studio, Classic, Cassette Studio, Portable CD | diese vier plus **Modern Glass**, **Aurora** (Lichtring, folgt mit Visualisierung dem echten Pegel) und **Studio Reel** (Tonbandmaschine mit VU-Metern); jederzeit umschaltbar (Popover mit Live-Vorschau), gespeichert | B |
| Vinyl | drehender Teller, Tonarm | Tonarm hebt/senkt sich, Teller läuft an/aus, Cover als Label, Licht und Reflexe | B |
| Kassette | Bandspulen | **neu**: sechs Gehäusefarben + „wie das Cover“; Bandmenge folgt dem Fortschritt | B |
| CD | drehende CD | drehende CD mit Cover-Label, Coverschein | B |
| Bedienung | Wiedergabe, Spulen, Zufall, Wiederholen, Favorit, Warteschlange, Liedtext, Timer, EQ, Tonhöhe | alles davon; Vor-/Zurückspringen mit einstellbarer Weite (5/10/15/30 s); Interpret/Album anklickbar; Lautstärke bis zur eingestellten Höchstlautstärke | T (Logik), B |
| Liedtext, Warteschlange | eigene Seiten | im großen Player anstelle des Mittelstücks oder als Seitenleiste; Schriftgröße, automatisches Mitscrollen, .lrc-Dateien einstellbar | B |
| Designwechsel-Animation | – | Überblenden und Skalieren (abhängig von „Animationen“ und „Bewegung reduzieren“) | – |

## Mini-Player (neu gestaltet)

| Funktion | macOS Version 2 | Prüfung |
|---|---|---|
| Aussehen | schwebende Glas-Kapsel in drei Größen (Kompakt 64 pt, Standard 84 pt, Groß 112 pt), Tönung aus der Coverfarbe | B |
| Design im Kleinen | drehende Platte, Kassette mit Naben, CD, Spulen, Aurora-Ring – passend zum gewählten Player-Design (abschaltbar) | B |
| Bedienung | Wiedergabe/Pause, zurück/vor, Zufall, Wiederholen, Fortschritt (ziehbar), Zeiten, Lautstärke (breit: direkt, schmal: Popover), Favorit | B |
| Tonhöhe | Popover mit Wert auf der Schaltfläche, ±1 und ±0,1 Halbtöne, Cent-Anzeige, „Original“, Modus Tonhöhe/Tempo bzw. 33⅓↔45 | T (Klang), B |
| Equalizer | Popover: Ein/Aus, eingebaute und eigene Voreinstellungen, Kurve, „Alle Einstellungen …“ | B |
| Warteschlange, Liedtext | Seitenleiste ein/aus | B |
| Großer Player | Klick auf Cover/Design/Titel, Wischen nach oben | – (Wischen) |
| Mini-Player-Fenster, Menüleiste | eigenes schwebendes Fenster (⌥⌘M), Player in der Menüleiste (abschaltbar) | B (Fenster) |

## Klang

| Funktion | Android 1.3.0 | macOS Version 2 | Prüfung |
|---|---|---|---|
| Equalizer | 10 Bänder ±12 dB, Voreinstellungen, Bass | gleich, plus **eigene Voreinstellungen** speichern, umbenennen, überschreiben, löschen; Regler live hörbar, gespeichert beim Loslassen | T (Klangkette), B |
| Tonhöhe | Halbtöne, Schallplatte | Feinschritte 0,1 Halbton (+ Cent-Anzeige), Tempo getrennt, Zurücksetzen, „beim Neustart behalten“ einstellbar | T (±0,1 und +0,5 Halbtöne im Klang gemessen) |
| Lautstärke | 0–300 % mit Limiter | gleich, Höchstlautstärke einstellbar (100–300 %) | T |
| Sleep-Timer | Minuten, Titelende, Ausblenden | gleich, Ausblenden abschaltbar | T (Logik) |

## Metadaten, Playlists, Import

| Funktion | Android 1.3.0 | macOS Version 2 | Prüfung |
|---|---|---|---|
| Tag-Editor | – | alle Felder (Titel, Interpret, Album, Album-Interpret, Komponist, Gruppierung, Genre, Jahr, Titel-/CD-Nummer, Compilation, Bewertung, BPM, Kommentar, Liedtext, Cover), Mehrfachbearbeitung, Kopieren/Einfügen (jetzt sichtbares Glas-Menü), Rückgängig, sichere Schreibstrategie | T, B |
| Intelligente Playlists | Favoriten, Meistgespielt, Am wenigsten, Jahrzehnte | **neu**: Zuletzt hinzugefügt, Zuletzt gespielt, Nie gespielt, nach Genre, Gut bewertet | T, B |
| Musikordner | MediaStore | Ordner mit Lesezeichen, Überwachung (abschaltbar), Abgleich beim Start (abschaltbar), externe Laufwerke | T (Abgleich-Logik) |
| Duplikate, Verlauf | – | wie Version 1 | T, B |

## Einstellungen (16 Kategorien, alle mit Wirkung)

Allgemein · Erscheinungsbild · Player-Designs · Bibliothek · Import & Musikordner · Sortierung · Wiedergabe ·
Equalizer · Tonhöhe · Lautstärke · Liedtexte · Metadaten · Tastaturkurzbefehle · Speicher & Cache ·
Datenschutz · Über die App. Das Zahnrad öffnet das Einstellungsfenster jetzt auf allen macOS-Versionen
(eigenes Fenster statt der `Settings`-Szene; ⌘, und Menü „Einstellungen …“ ebenso). — Prüfung: B (6 Kategorien
als Vorschaubild), T (Speichern/Laden aller Felder).

## Desktop-Bedienung

| Funktion | macOS Version 2 | Prüfung |
|---|---|---|
| Tastatur | Leertaste (Wiedergabe), ⌘1–⌘6 (Bereiche), ⌘F (Suchen), ⇧⌘F (Player), ⌥⌘U (Warteschlange), ⌘L (Liedtext), ⌘[ (zurück), ⌘←/→ (Titel), ⌥⌘←/→ (springen um die eingestellte Weite), ⌘↑/↓ (Lautstärke), ⇧⌘L (Favorit), ⌘I (Informationen), ⌘N (neue Playlist), ⇧⌘O (Ordner), ⌘R (neu einlesen), ⌥⌘Z (Tag-Änderung widerrufen), ⌥⌘M (Mini-Player), ⌥⌘E (Equalizer), ⌘, (Einstellungen); Pfeiltasten, Eingabe, ⌘A und Löschen in Listen; ← → im Cover Flow | – |
| Trackpad | Zwei-Finger-Zoom (Covergröße), Wischen mit drei Fingern („Zwischen Seiten blättern“): rechts = zurück, oben = Player öffnen, unten = schließen; Maustaste „Zurück“ | – |
| Medientasten, Kontrollzentrum | Wiedergabe, Titel, Position, Springen mit eingestellter Weite (abschaltbar) | – |
| Menüleiste, Dock-Menü, Vollbild | vorhanden | – |

## Eigene Ideen (Version 2)

- **Dynamische Coverfarben** im Hintergrund der App, im Mini-Player und im großen Player (abschaltbar).
- **Aurora** und **Studio Reel** als zusätzliche Player-Designs; Aurora und VU-Meter folgen dem echten Pegel.
- **Live-Vorschau** aller Player-Designs im Design-Popover.
- **Cover Flow** in jedem Bereich, auch für Interpreten, Genres und Playlists.
- **Filter-Chips** mit „x von y“, Schnellfilter wie „Verlustfrei“ oder „Ohne Cover“ (findet Lücken in der Sammlung).
- **Eigene Equalizer-Voreinstellungen** im Mini-Player erreichbar.
- **„Transparenz reduzieren“ / Animationsstufe** für ältere Macs; folgt auch den Systemeinstellungen.
- **Speicher & Cache**: belegten Platz von Covern, Ogg-Umwandlungen und Datenbank anzeigen und leeren.
