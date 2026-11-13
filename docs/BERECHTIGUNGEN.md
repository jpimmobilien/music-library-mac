# Berechtigungen

Stand 27.10.2026 · AETHER 0.3.0 (Phase 3)

Grundsätze: Vor jeder Anfrage steht eine Erklärung. Gefragt wird erst auf Tippen bzw. im passenden Moment, nie beim
Start. Ablehnung und Entzug sind normale Zustände mit verständlichem Hinweis. Keine Berechtigung „auf Vorrat“. Den
aktuellen Stand jeder Berechtigung zeigt **Einstellungen › Datenschutz und Berechtigungen** – mit einem Tipp zur
passenden Android-Einstellung.

## Deklariert in Version 0.3.0

| Berechtigung | Wofür | Wann gefragt | Ohne sie |
|---|---|---|---|
| `MANAGE_EXTERNAL_STORAGE` („Zugriff auf alle Dateien“) | Dateimanager: alle Ordner und Dateitypen lesen, ändern, löschen – interner Speicher, SD-Karte, USB-Speicher; Kategorien und Suche über den Medienindex | Unter „Dateien“ nach einer Erklärung; Tippen öffnet die Android-Einstellung (Xiaomi: „Verwaltung aller Dateien erlauben“) | „Dateien“ zeigt die Erklärung und die Speicherorte; alles andere der App funktioniert |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Nur „Gerät › Bewegung“: Geschwindigkeit, Höhe, Kurs, Satelliten | Auf der Seite „Bewegung“ nach einer Erklärung (Android-Dialog „Bei Nutzung der App“) | Kompass und Luftdruck funktionieren weiter; GPS-Werte erklären, was fehlt. Nur „ungefähr“ reicht für Live-Werte nicht (wird erklärt) |
| `POST_NOTIFICATIONS` (Android 13+) | Fortschritt langer Dateivorgänge in einer Benachrichtigung mit „Abbrechen“ | Einmal, beim ersten langen Vorgang (Kopieren, Verschieben …) | Der Vorgang läuft trotzdem; der Fortschritt steht in der App |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | Lange Dateivorgänge laufen weiter, wenn man die App verlässt (Dienst-Typ `dataSync`) | Keine Abfrage (Normalberechtigung) | – |
| `REQUEST_INSTALL_PACKAGES` | Ein angetipptes App-Paket (APK) an den Installer von Android übergeben | Android fragt einmalig „Aus dieser Quelle zulassen“; AETHER erklärt das vorher | APKs lassen sich nicht installieren, alles andere geht |

**Bewusst nicht deklariert:** `INTERNET` (AETHER kann keine Daten senden – auch keine Dateien oder Positionen),
`ACCESS_BACKGROUND_LOCATION` (kein Standort im Hintergrund), Kontakte, Kamera, Mikrofon, `READ_MEDIA_*`
(überflüssig mit „Zugriff auf alle Dateien“).

## Ohne Berechtigung

| Funktion | Schnittstelle |
|---|---|
| Speicherorte, Zustand, Kapazität | `StorageManager`, `StorageStatsManager`, `StatFs` |
| Akku, Thermalstatus, Gerät, Display, Sensoranzahl | wie in Phase 1 |
| Kompass | `TYPE_ROTATION_VECTOR` (Ersatz: geomagnetischer Rotationsvektor bzw. Beschleunigung + Magnetfeld) |
| Luftdruck, Druckhöhe | `TYPE_PRESSURE` |
| Standort-Schalter des Systems (an/aus) | `LocationManager.isLocationEnabled`, Broadcast `PROVIDERS_CHANGED` |

## Was auch „Zugriff auf alle Dateien“ nicht erlaubt

* `Android/data` und `Android/obb` anderer Apps: seit Android 11 für jede App gesperrt. AETHER zeigt dort „Von Android
  gesperrt“ mit Erklärung und umgeht die Sperre nicht.
* Systempartitionen und die privaten Daten anderer Apps (`/data/data`).

## Weitergabe an andere Apps

Öffnen, Teilen und Installieren übergeben nie einen Dateipfad, sondern eine `content://`-Adresse des eigenen
FileProviders – nur für die eine Datei und nur zum Lesen. Der Provider ist nicht exportiert; ohne diese ausdrückliche
Freigabe kann keine App über ihn auf Dateien zugreifen.
