# Implementierungsplan PROJECT AETHER

Stand 27.10.2026 · nach Phase 3

Grundsatz: Jede Phase endet mit einer installierbaren, ehrlich dokumentierten Version. Spätere Phasen bauen auf den
Schnittstellen der früheren auf, statt sie zu ersetzen. Die Modulgrenzen stehen seit Phase 1 fest
([ENTSCHEIDUNGEN.md](ENTSCHEIDUNGEN.md) §2).

| Phase | Inhalt | Ergebnis | Stand |
|---|---|---|---|
| **1** | Projekt, Werkzeugkette, Architektur, Designsystem-Grundlage, Navigation, erste echte Funktionen (nur lesend) | ausführbare Grundlage | **umgesetzt** – siehe [STATUS.md](STATUS.md) |
| 2 | Liquid-Glass-Designsystem verfeinern | konsistentes Grundprodukt | Bausteine für den Dateimanager umgesetzt; Rückmeldung vom Gerätetest steht aus |
| **3** | Dateimanager | nutzbarer Dateimanager | **umgesetzt** (0.3.0) – inkl. SD-Karte/USB aus Phase 4 und Papierkorb aus Phase 5 |
| 4 | SD-Karte, USB-Speicher | erweiterte Dateiverwaltung | mit Phase 3 umgesetzt (über „Zugriff auf alle Dateien“); offen: Prüfung auf Geräten |
| 5 | Speicherassistent | Analyse, große Dateien, Duplikate | geplant (Papierkorb vorgezogen) |
| 6 | Device Intelligence | Sensorliste, Live-Sensoren, Diagnose | „Bewegung“ vorgezogen (GPS, Satelliten, Barometer, Kompass); Sensor-Explorer offen |
| 7 | Themes und Individualisierung | personalisierbares Produkt | Theme/Akzent/Effektstärke vorgezogen |
| 8 | Qualitätssicherung, Polishing, APK | stabile Version | – |

## Phase 1 – was umgesetzt ist

* Gradle-Projekt mit **derselben Werkzeugkette** wie Filmbibliothek, Musikbibliothek und DriveGlass (AGP 9.3.1,
  Gradle 9.6.1, Kotlin 2.4.21, Compose-BOM 2026.09.00) – Android Studio muss nichts Neues laden.
* Fünf Module: `app`, `ui:designsystem`, `core:model` (reines Kotlin, JVM-getestet), `platform:storage`,
  `platform:device`.
* Designsystem: Farbrollen für **fünf Themes** und **sieben Akzentfarben + Systemfarbe**, drei Effektstärken,
  Glasmaterial mit echter Hintergrundunschärfe für schwebende Leisten, Typografie (Inter), eigener Symbolsatz,
  Bausteine, Diagramme, Bewegungssystem mit „Animationen entfernen“.
* Navigation: Reiterleiste aus Glas (Telefon) bzw. Seitenleiste (breite Fenster), getrennte Verläufe je Bereich,
  Zurück-Logik, Unterseiten.
* Echte Werte (ohne Berechtigung): Speicherorte und Kapazität, Akku, Akku-Temperatur, Thermalstatus und thermische
  Reserve, Geräteübersicht, Arbeitsspeicher, Display, Anzahl Sensoren; Hinweise aus echten Befunden.
* Einstellungen: Theme, Akzent, Effektstärke, Bewegung – lokal gespeichert.

**Vorgezogen aus Phase 2/7:** alle fünf Themes, Akzentfarben und Effektstärke. Grund: Die Regel „jede Komponente in
jedem Theme prüfen“ lässt sich nur einhalten, wenn man die Themes von Anfang an umschalten kann.

## Phase 3 – was umgesetzt ist (0.3.0)

* **Zugriff:** „Zugriff auf alle Dateien“ mit Erklärung vorab und Rückkehr-Erkennung; ohne ihn bleibt die App voll
  nutzbar und „Dateien“ erklärt, wozu er dient.
* **`core:files`** (neues reines Kotlin-Modul, gegen echte Dateien JVM-getestet): Dateiarten, natürliche Sortierung,
  Namensregeln (FAT/exFAT), Auflisten, Papierkorb je Speicher, Journal für unfertige Dateien, Textvorschau, Suche im
  Dateisystem, Prüfsummen und die **Dateivorgänge**: Kopieren, Verschieben (atomar bzw. mit Prüfung über
  Speichergrenzen), In den Papierkorb, Wiederherstellen, Endgültig löschen, Umbenennen, Ordner erstellen,
  Komprimieren/Entpacken (ZIP), Text sicher sichern – mit Fortschritt, Abbruch, Konfliktfragen und ehrlichem Bericht.
* **Oberfläche:** Startseite „Dateien“ (Speicherorte mit Belegung, Favoriten, Schnellzugriff, Kategorien, zuletzt
  geöffnet, Papierkorb), Ordner (Liste/Raster, Sortierung, versteckte Objekte, Pfadleiste, Auswahl mit
  Werkzeugleiste, Aktionsblatt), Kategorien aus dem Medienindex, Suche (schnell/gründlich), Papierkorb, Schnellansicht
  (Bild mit Zoom, Text mit Bearbeiten, PDF, ZIP-Inhalt), Informationen (inkl. EXIF, Medien, APK, SHA-256),
  Ziel-Auswahl, Fortschritt mit Restzeit, Konfliktdialog, Rückmeldung mit „Widerrufen“.
* **Weitergabe:** Öffnen, Öffnen mit, Teilen, APK installieren über den eigenen FileProvider.
* **Hintergrund:** lange Vorgänge als Vordergrunddienst mit Benachrichtigung und „Abbrechen“; Medienindex wird nach
  jedem Vorgang nachgezogen.
* **SD-Karte und USB-Speicher** (aus Phase 4): wie der interne Speicher, inklusive eigenem Papierkorb und geprüftem
  Verschieben zwischen den Speichern; „nur lesbar“ eingebundene Speicher werden erkannt.
* **Bewegung** (aus Phase 6): Geschwindigkeit, Kurs, Höhe (Meeresspiegel ab Android 14, Ellipsoid, Druckhöhe),
  Satelliten je System mit Signalstärke und Zweifrequenz, Kompass (magnetisch/geografisch), Messung seit dem Öffnen
  (Dauer, Strecke, Höchst-/Durchschnittsgeschwindigkeit, Anstieg/Abstieg).

## Phase 2 – Designsystem verfeinern (offen)

1. Rückmeldung vom ersten Gerätetest einarbeiten (Glas, Unschärfe, Schatten, Lesbarkeit auf beiden Geräten).
2. Großer Titel, der beim Scrollen in eine Glas-Kopfleiste übergeht (mit Unschärfe).
3. Informationsdichte „Standard/Kompakt“ als Token-Satz.
4. Bildschirm-Vorschau ohne Gerät (Compose-Zeichencode auf der JVM), damit Themes vor der Auslieferung sichtbar
   geprüft werden können.

## Nächste Schritte im Dateimanager (nach dem Gerätetest)

* Eingeschränkter Modus ohne „Zugriff auf alle Dateien“ (Ordnerfreigabe über den Android-Auswahldialog), falls
  gewünscht.
* Ziehen und Ablegen auf Tablets, Mehrfenster.
* Prüfung des Dateisystems eines Ziels (FAT32) vor großen Kopien, sobald Android es zuverlässig meldet.

## Phase 5 – Speicherassistent

* Analyse im Hintergrund (`WorkManager` nur, wenn sie das Schließen der App überdauern soll; sonst Coroutine im
  ViewModel), Fortschritt, Abbruch, Teilergebnisse, Liste nicht zugänglicher Bereiche.
* Große Dateien mit anpassbaren Schwellen, Verteilung nach Typ, alte Downloads.
* Duplikate: Größe → Teil-Prüfsumme (Anfang/Ende) → SHA-256 der ganzen Datei; „bestätigt identisch“ vs. „möglich“.
* Bereinigungsablauf mit Vorschau der tatsächlichen Ersparnis über den Papierkorb aus Phase 3. Nie automatisch
  löschen.

## Phase 6 – Device Intelligence

* Sensor-Explorer (`SensorManager`): Name, Hersteller, Typ, Auflösung, Messbereich, Leistungsaufnahme, Einheit
  („Bewegung“ ist seit 0.3.0 vorhanden).
* Live-Monitor mit angemessener Abtastrate (`SENSOR_DELAY_UI`), Abmelden beim Verlassen, Diagramme.
* Sensor-Diagnose mit den Stufen „vorhanden“, „Daten empfangen“, „Werte ändern sich“ – ohne Hardware-Garantie.
* Verlauf von Akku-Temperatur und Thermalstatus, solange die Ansicht offen ist.

## Phase 7 – Individualisierung

Dashboard-Karten auswählen und anordnen, Schnellzugriffe, zeitbasierter Theme-Wechsel, Standardansicht und
-sortierung, Informationsdichte.

## Phase 8 – Qualitätssicherung

Lint (`NewApi` u. a.), Profiling (Recomposition, Scrollen mit Tausenden Dateien), TalkBack, große Schrift,
Querformat/Tablet, alle Themes, Fehlerfälle aus dem Auftrag §15, signiertes Release-APK.
