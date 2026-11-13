# Änderungen

## Version 0.3.0 (versionCode 2) – Phase 3: Dateimanager und Bewegung

### Neu – Dateien
- **Zugriff auf alle Dateien** mit Erklärung vorab (was er erlaubt, was nicht, dass nichts das Gerät verlässt) und
  direktem Weg in die Android-Einstellung; AETHER erkennt die Rückkehr sofort. Hinweis für Xiaomi/HyperOS.
- **Startseite „Dateien“:** Suche, Speicherorte mit Belegung (intern, SD-Karte, USB), Favoriten (auch „gerade nicht
  verfügbar“), Schnellzugriff, elf Kategorien mit Anzahl und Größe, zuletzt geöffnet, Papierkorb.
- **Ordner:** Liste oder Raster mit Vorschaubildern (Bild, Video, Albumcover, erste PDF-Seite, App-Symbol), natürliche
  Sortierung nach Name/Datum/Größe/Art, versteckte Objekte ein/aus, antippbare Pfadleiste, Live-Aktualisierung,
  ehrliche Zustände (leer, gesperrt durch Android, nicht mehr vorhanden, nur lesbar).
- **Auswahl** per langem Drücken mit Werkzeugleiste an der Stelle der Reiterleiste (Teilen, Kopieren, Verschieben,
  Löschen, Mehr) und **Aktionsblatt** je Objekt: Öffnen, Öffnen mit, Teilen, Informationen, Umbenennen, Kopieren nach,
  Verschieben nach, Duplizieren, Komprimieren, Entpacken (hierher / nach), Favorit, Papierkorb, Endgültig löschen.
- **Vorgänge** sicher und nachvollziehbar: erst vollständig schreiben, dann ersetzen; Verschieben über Speichergrenzen
  mit SHA-256-Prüfung, bevor das Original entfernt wird; Fortschritt mit Restzeit; Abbrechen ohne Halbfertiges;
  Konfliktfrage mit Vergleich (Ersetzen, Beide behalten, Überspringen, Zusammenführen, „für alle“); Bericht mit
  genauen Gründen; Warteschlange; Vordergrunddienst mit Benachrichtigung für lange Vorgänge; Medienindex wird
  nachgezogen; Aufräumen nach einem Absturz.
- **Papierkorb je Speicher** mit „Widerrufen“ direkt nach dem Löschen, Wiederherstellen an den ursprünglichen Ort,
  endgültig Löschen und Leeren nur nach Bestätigung. Nichts wird automatisch gelöscht.
- **Kategorien** aus dem Medienindex (Bilder, Videos, Musik, Audio, Dokumente, PDFs, Text, Archive, App-Pakete,
  Downloads, Zuletzt hinzugefügt).
- **Suche:** schnell (Medienindex, alle Speicher) oder gründlich (Dateisystem, auch Verstecktes), Suchverlauf.
- **Schnellansicht:** Bilder mit Zoom und Wischen, Text mit Bearbeiten und sicherem Sichern, PDF, ZIP-Inhalt.
- **Informationen:** Größe, Ordnerinhalt, Ort, Speicher, Änderungsdatum, Rechte, Typ; Bildmaße, Aufnahmedatum,
  Kamera, Hinweis auf Standortdaten; Dauer und Titel von Medien; Seitenzahl von PDFs; Angaben aus App-Paketen;
  SHA-256 auf Wunsch.
- **Weitergabe:** Öffnen, Teilen und APK-Installation über einen nicht exportierten FileProvider.

### Neu – Bewegung (Gerät › Bewegung)
- Geschwindigkeit mit Messgenauigkeit, Kurs, Höhe über dem Meeresspiegel (Android 14+), Ellipsoidhöhe, Druckhöhe,
  Satelliten je System mit Signalstärke und Zweifrequenz, Kompass (magnetisch/geografisch, Kalibrierhinweis),
  Messung seit dem Öffnen (Dauer, Strecke, Höchst- und Durchschnittsgeschwindigkeit, Anstieg/Abstieg).
- Standort nur „bei Nutzung“, nur solange die Seite offen ist; Koordinaten standardmäßig verborgen.

### Neu – übrige App
- Übersicht: Schnellzugriff auf Downloads, Bilder, Dokumente, Zuletzt hinzugefügt und Bewegung.
- Einstellungen: Bereich „Dateien“ (versteckte Objekte, Verlauf löschen); Datenschutz zeigt den aktuellen Stand jeder
  Berechtigung mit Weg in die Android-Einstellung.
- Designsystem: Blätter, Dialoge, Eingabefelder, Werkzeugleiste, Auswahlmarke, Kompass, Messkacheln; 37 neue
  Symbole (70 insgesamt).

### Berechtigungen
- Neu: `MANAGE_EXTERNAL_STORAGE`, Standort (genau/ungefähr), `POST_NOTIFICATIONS`, Vordergrunddienst (`dataSync`),
  `REQUEST_INSTALL_PACKAGES` – jeweils mit Erklärung, erst im passenden Moment. Weiterhin **keine
  Internet-Berechtigung**. Details: docs/BERECHTIGUNGEN.md.

### Tests
- **226 JVM-Tests grün:** 155 Dateivorgänge gegen echte Dateien (`core:files`: Kopieren, Verschieben mit Prüfsumme,
  Papierkorb, Archive, Umbenennen, Text sichern, Abbruch und Teilberichte, Groß-/Kleinschreibung, Absturz-Journal,
  Suche …), 65 Fachlogik (`core:model`, davon 25 Bewegung), 6 Kontrast (neu: gefüllte Flächen, Auswahl, Blätter –
  fand und behob Werte bis 2,9 : 1).
- Typprüfung aller sieben Module gegen Android-API-36- (erweitert um `android.location` und `android.graphics.pdf`) und
  AndroidX-Schnittstellen: 0 Fehler, 0 Warnungen. Prüfskript Theme-Farben: 215 Aufrufe, 0 Verstöße.
- Zwei unabhängige Durchsichten (Engine/Plattform/Oberfläche/Bewegung sowie Schnellansicht/Informationen), Befunde
  mit eigenen Tests gegen echte Dateien nachgestellt: **5 kritische** (u. a. Überschreiben einer anders geschriebenen
  Datei auf groß-/kleinschreibungs-empfindlichen Speichern, Sichern veränderte unberührte Bytes, ungesicherte
  Änderungen ohne Rückfrage verloren, Absturz durch präpariertes ZIP), **5 hohe** (u. a. irreführender Bericht nach
  Abbruch, „Widerrufen“ ohne Wirkung) und alle mittleren behoben; Details in docs/TESTPLAN.md §1.5.
- Kein Gradle-Build/APK und kein Gerätetest in der Entwicklungsumgebung; Checkliste: docs/TESTPLAN.md §3.

## Version 0.1.0 (versionCode 1) – Phase 1: Fundament

Erste Version von PROJECT AETHER.

### Neu
- Projekt mit fünf Modulen (`app`, `ui:designsystem`, `core:model`, `platform:storage`, `platform:device`) und
  derselben Werkzeugkette wie Filmbibliothek, Musikbibliothek und DriveGlass.
- Designsystem „Aether“: fünf Themes (Adaptiv, Liquid Glass Hell, Liquid Glass Dunkel, Minimal Hell, Deep Dark),
  sieben Akzentfarben und Systemfarbe, drei Effektstärken (Minimal = Leistungsmodus), Glas mit echter
  Hintergrundunschärfe für schwebende Leisten, Atmosphäre, Inter-Typografie, eigener Symbolsatz (33 Symbole),
  Bausteine und Diagramme, Bewegungssystem mit „Animationen entfernen“ bzw. „Bewegung reduzieren“.
- Navigation: Glas-Reiterleiste mit Einstellungs-Schaltfläche (Telefon), Seitenleiste (breite Fenster), getrennte
  Verläufe je Bereich, Unterseiten mit Zurück.
- Übersicht: Gerätename, Statuszeile, Speicherring, Hinweise aus echten Befunden (Speicher fast voll, SD-Karte/USB
  erkannt, nur lesbar, nicht lesbar, Wärme, Akkuzustand), Gerätestatus, weitere Speicherorte.
- Speicher: alle Speicherorte mit Zustand, Kapazität, Belegung; intern zusätzlich Datenpartition, sofort verfügbarer
  Platz, freigebbarer Zwischenspeicher und Anteil außerhalb der Datenpartition (als „berechnet“ gekennzeichnet).
- Gerät: Akku (Stand, Ladezustand, Quelle, Zustand, Spannung, Technologie, Ladezyklen), Akku-Temperatur,
  Thermalstatus mit Stufenskala und Bedeutung, thermische Reserve, Geräteübersicht, Arbeitsspeicher, Display,
  Anzahl Sensoren.
- Einstellungen: Theme (mit Vorschau), Akzent, Effektstärke, Bewegung, Zurücksetzen; Datenschutz; Lizenzen.
- Keine Berechtigungen, keine Internet-Berechtigung, keine Sicherung/Geräteübertragung der Einstellungen.

### Tests
- 44 JVM-Tests grün (39 Fachlogik in `core:model`, 5 Kontrast über alle Theme-/Akzent-Kombinationen).
- Typprüfung aller fünf Module gegen Android-API-36- und AndroidX-Schnittstellen: 0 Fehler, 0 Warnungen; Gegenprobe
  mit absichtlichen Fehlern. Prüfskript Theme-Farben: 0 Verstöße.
- Unabhängige Durchsicht: 14 Befunde (u. a. Seitenleiste im Querformat, Aufblitzen des falschen Themes, falsche
  Aussage zur thermischen Reserve, TalkBack-Rollen) – alle behoben.
- Kein Gradle-Build/APK in der Entwicklungsumgebung (Google Maven gesperrt); Details: docs/TESTPLAN.md.
