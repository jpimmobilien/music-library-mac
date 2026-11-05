# Performance – Ursachen, Änderungen, Messungen

Ausgangspunkt: Rückmeldung zu Version 1.0 „läuft sehr laggy“ (Intel MacBook Pro 15" 2017, Bibliothek mit
1.640 Alben). Ziel für Version 2: flüssig mit **10.000 Titeln** auch auf einem Intel-Mac von 2017.

## 1. Ursachen in Version 1.0 (Code-Analyse)

| # | Ursache | Wirkung | Änderung in Version 2 |
|---|---|---|---|
| 1 | Bis zu zehn einzelne `@Published`-Listen in `AppModel` (Titel, Alben, Interpreten, Genres, Playlists, Favoriten …), nacheinander zugewiesen | jede Zuweisung löst eine eigene Neuberechnung **aller** beobachtenden Ansichten aus (bis zu 10 Durchläufe pro Änderung) | eine einzige `lists`-Struktur, die einmal pro Neuberechnung zugewiesen wird |
| 2 | Einstellungen wurden bei **jedem** Reglerschritt (EQ, Tonhöhe, Lautstärke, Covergröße) gespeichert und veröffentlicht | Schreiben auf die Platte + Neuberechnung des ganzen Fensters bis zu 60× pro Sekunde | Regler arbeiten lokal, sind über `previewEffects`/`previewPitch`/`setLiveVolume` sofort hörbar und werden erst beim Loslassen gespeichert; Speichern zusätzlich verzögert und gebündelt |
| 3 | `PlayerService` veröffentlichte die Restzeit des Sleep-Timers 4× pro Sekunde | alle Ansichten, die den Player beobachten (Fenster, Mini-Player, Listen), wurden 4× pro Sekunde neu berechnet | Restzeit, Position und Dauer laufen nur noch über `PlaybackClock`; nur kleine Unteransichten beobachten sie, und die Restzeit ändert sich nur einmal pro Sekunde |
| 4 | Cover wurden als `NSImage` „faul“ geladen, die JPEG-/PNG-Dekodierung passierte erst beim Zeichnen auf dem Hauptthread | Ruckeln beim Scrollen durch Alben-Raster (große Bibliothek → viele neue Cover pro Sekunde) | Dekodierung vollständig im Hintergrund (`CGImageSource` mit `ShouldCacheImmediately`), vorab verkleinerte Größen je nach Kachel (ab 150 px), Speicher-Cache 320 MB |
| 5 | Die Suche wurde bei jedem Tastendruck neu berechnet | Eingabe stockt bei großen Bibliotheken | Suche 0,12 s verzögert, Berechnung im Hintergrund |
| 6 | Intelligente Playlists wurden bei jedem Zugriff auf dem Hauptthread neu berechnet | Öffnen einer intelligenten Playlist hakt | werden zusammen mit den übrigen Listen im Hintergrund berechnet |
| 7 | Echte Unschärfe (`NSVisualEffectView`/`.blur`) auf vielen Flächen, auch auf Inhalten | hohe GPU-Last, besonders auf Intel-Grafik | Unschärfe nur noch für schwebende Elemente (Navigation, Mini-Player, Popover); Inhalte mit halbtransparenten Füllungen; Einstellung „Transparenz reduzieren“ schaltet auch das ab |
| 8 | Animierter Hintergrund mit Weichzeichnung | dauerhafte GPU-Last | Hintergrund aus vorberechneten Verläufen, nur bei Titelwechsel überblendet |
| 9 | `Menu` mit eigener Beschriftung (Sortieren) | unter macOS 13 unsichtbar (kein Performance-, aber ein Bedienfehler) | eigene `GlassMenuButton`-Popover |

### Gefunden mit Profilaufnahmen (`sample`) während der Arbeit an Version 2

| # | Ursache | Wirkung | Änderung |
|---|---|---|---|
| 10 | Einstellungen wurden auch bei **unverändertem** Wert veröffentlicht; eine Bindung, die beim Aufbau zurückschreibt (Menüleisten-Symbol), löste so die nächste Aktualisierung aus | im ersten Build von Version 2 **hing die Oberfläche** beim Start (Vorschau- und Messmodus brachen nach 15 bzw. 20 Minuten ohne ein einziges Bild ab) | `AppModel.settings` meldet nur noch echte Änderungen; Bindung mit Gleichheitsprüfung; eingebauter Hänger-Wächter nimmt bei > 6 s Blockade ein Profil auf |
| 11 | Jeder Tastendruck im Suchfeld veröffentlichte die Suche im `AppModel` | das ganze Fenster mit bis zu 10.000 Zeilen wurde bei **jedem Buchstaben** neu ausgewertet | getippter Text bleibt im Suchfeld; das Modell übernimmt ihn gebündelt nach 0,12 s und rechnet im Hintergrund |
| 12 | Cover wurden erst beim Anzeigen in den Farbraum des Bildschirms umgerechnet (`CA::Render::copy_image` → `vImageConvert_AnyToAny` im Hauptthread) | bis zu **12 % der Hauptthread-Zeit** beim Scrollen von Rastern | Cover werden im Hintergrund direkt im Farbraum und Pixelformat des Bildschirms erzeugt (BGRA, vormultipliert) |
| 13 | Jede Zeile/Kachel war Ablageziel für Ziehen & Ablegen und jedes Cover hatte einen eigenen `GeometryReader` | zusätzliche Arbeit für jede beim Scrollen neu entstehende Zeile | Ablageziele nur noch in Playlists; Cover ohne `GeometryReader` |

## 2. Messverfahren

Die App hat einen eingebauten Messmodus (`--benchmark <Ordner> --tracks N`, Quelltext
`Sources/MusicLibrary/Snapshot/Benchmark.swift`). Er erzeugt eine künstliche Bibliothek (10.000 Titel, ca. 6 Titel
pro Album, 320 echte Coverbilder), öffnet das echte Hauptfenster und misst mit der Uhr des Prozesses:

- Aufbau von Index und Listen (Hintergrundberechnung) und die Suche (Berechnung),
- Bereichswechsel und Ansichtswechsel je Bereich (Raster, kompaktes Raster, Liste, Detailliste, Cover Flow),
- Scrollen: 60 Schritte à 360 pt, je Schritt die Zeit für Layout + Zeichnen im Hauptthread
  (unter 16,7 ms = ein Bild bei 60 Hz),
- Tippen im Suchfeld und die Zeit bis zum sichtbaren Ergebnis,
- Öffnen/Schließen des großen Players in allen sieben Designs,
- Leerlauf bei laufender Wiedergabe: Rechenzeit des Hauptthreads und des ganzen Prozesses in Prozent
  (Mini-Player mit drehender Platte bzw. großer Vinyl-Player).

Zusätzlich misst der Vorschaumodus bei jedem Bild die Auslastung des Hauptthreads.

Hinweise zur Aussagekraft:

- Gemessen wird auf den GitHub-Rechnern: **virtuelle Macs** (Apple M1, geteilte Hardware). Die Werte schwanken
  von Lauf zu Lauf deutlich (gleicher Code: bis Faktor 2); verglichen werden deshalb mehrere Läufe.
- Auf den Testrechnern ist die Systemeinstellung „Bewegung reduzieren“ **eingeschaltet**. Damit die Kosten der
  Animationen trotzdem gemessen werden, übergeht der Messlauf diese Einstellung (`ML_IGNORE_REDUCE_MOTION=1`).
- Die Werte für Version 1.0 stammen aus demselben Messprogramm, angewendet auf den unveränderten Code von
  Version 1.0 (Zweig `baseline-v1`; dort ohne Ansichtswechsel, weil es die Ansichten noch nicht gab).
- Eine Messung „Verspätung je Bild“ aus früheren Läufen ist nicht aussagekräftig (die virtuellen Rechner
  wecken kurze Wartezeiten unregelmäßig auf, auch bei untätigem Hauptthread) und wird nicht verwendet.

## 3. Ergebnisse

_Wird nach dem letzten Messlauf mit den endgültigen Zahlen ergänzt._
