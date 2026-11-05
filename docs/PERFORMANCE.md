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

## 2. Messverfahren

Die App hat einen eingebauten Messmodus (`--benchmark <Ordner> --tracks N`, Quelltext
`Sources/MusicLibrary/Snapshot/Benchmark.swift`). Er erzeugt eine künstliche Bibliothek (N Titel, ca. 6 Titel
pro Album, 320 echte Coverbilder), öffnet das echte Hauptfenster und misst mit der Uhr des Prozesses:

- Aufbau von Index und Listen (Hintergrundberechnung),
- Suche (Berechnung),
- Bereichswechsel (Layout + Zeichnen),
- Ansichtswechsel je Bereich (Raster, kompakt, Liste, Detailliste, Cover Flow),
- Scrollen (je Schritt Layout + Zeichnen),
- Tippen im Suchfeld,
- Öffnen/Schließen des Players für jedes Design,
- Leerlauf (Bilder pro Sekunde ohne Eingabe).

Gemessen wird auf den GitHub-Rechnern (virtuelle Macs ohne echte Grafikkarte, also eher pessimistisch).
Die Werte für Version 1.0 stammen aus demselben Messprogramm, angewendet auf den unveränderten Code von
Version 1.0 (Zweig `baseline-v1`; dort ohne Ansichtswechsel, weil es die Ansichten noch nicht gab).

## 3. Ergebnisse

_Wird nach dem Messlauf mit den echten Zahlen ergänzt._
