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
| 10 | Einstellungen wurden auch bei **unverändertem** Wert veröffentlicht; eine Bindung, die beim Aufbau zurückschreibt (Menüleisten-Symbol), löste so die nächste Aktualisierung aus | im ersten Build von Version 2 **hing die Oberfläche** beim Start (Vorschau- und Messmodus brachen nach 15 bzw. 20 Minuten ohne ein einziges Bild ab); wahrscheinliche Ursache, nach der Änderung nicht mehr aufgetreten | `AppModel.settings` meldet nur noch echte Änderungen; Bindung mit Gleichheitsprüfung; eingebauter Hänger-Wächter nimmt bei > 6 s Blockade ein Profil auf |
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

Alle Zahlen: Mittelwert (p95) in Millisekunden im Hauptthread, 10.000 Titel. Ein Bild bei 60 Hz = 16,7 ms.
„v1“ = Version 1.0 (Zweig `baseline-v1`, gebaut mit Xcode 26), „v2“ = ausgelieferte Version 2.0 (Lauf 15,
Commit `d9fdaf2`). Gleicher Rechnertyp (virtueller Mac, macOS 14.8, Apple M1).

### Apple Silicon (arm64)

| Messung | v1 | v2 | |
|---|---|---|---|
| Alben-Raster scrollen (je Schritt) | 64,8 (185,9) | **14,3 (25,4)** | ≈ 4,5× schneller, p95 unter 2 Bildern |
| Interpreten scrollen (Raster) | 52,3 (99,9) | **15,2 (26,9)** | ≈ 3,4× schneller |
| Titel-Liste scrollen | 23,6 (39,0) | **21,7 (35,9)** | gleich bis leicht besser |
| Bereich wechseln | 266,6 (445,0) | **196,0 (263,4)** | ≈ 25 % schneller, Spitzen ≈ 40 % niedriger |
| Suche: je Tastendruck | 73,9 (118,5) | **14,7 (101,0)** | ≈ 5× weniger Arbeit; Ergebnis nach 0,2 s sichtbar (im Hintergrund berechnet) |
| Player öffnen/schließen | 184,2 (254,9) – 4 Designs | **147,0 (227,3)** – 7 Designs | schneller trotz aufwendigerer Designs |
| Leerlauf mit Wiedergabe (Mini-Player mit drehender Platte) | – | **5,3 % Hauptthread**, 5,5 % CPU gesamt | |
| Großer Vinyl-Player läuft | – | **7,3 % Hauptthread**, 7,5 % CPU gesamt | |

Neue Ansichten in v2 (arm64): Titel-Raster 13,8 (19,5) · Titel-Detailliste 39,5 (65,1) · Alben kompakt
33,3 (90,2) · Alben-Liste 54,6 (124,5) · Alben-Detailliste 36,5 (54,8) · Interpreten kompakt 42,8 (98,2) ·
**Titel kompakt 131,4 (253,1)** – das kompakte Raster mit 10.000 Titeln ist die langsamste Ansicht
(viele kleine Kacheln je Zeile) und für so große Listen nicht zu empfehlen.

### Intel-Teil der App über Rosetta (x86_64)

| Messung | v1 | v2 |
|---|---|---|
| Alben-Raster scrollen | 48,2 (107,1) | 69,0 (117,8) |
| Interpreten scrollen (Raster) | 134,7 (219,2) | **63,3 (95,9)** |
| Titel-Liste scrollen | 51,7 (100,9) | 73,0 (128,9) |
| Bereich wechseln | 467,6 (803,7) | 550,4 (728,7) |
| Suche: je Tastendruck | 214,8 (406,4) | **81,5 (361,0)** |
| Leerlauf mit Wiedergabe / großer Vinyl-Player | – | 5,8 % / 7,4 % Hauptthread |

Der Rosetta-Rechner war in diesem Lauf spürbar langsamer als beim Messen von v1 (reine Rechenzeit ohne
Oberfläche: Listen berechnen 980 statt 781 ms, Index 316 statt 242 ms, also ≈ 25–30 % langsamer). Ein Teil der
Unterschiede ist deshalb Rechnerschwankung; eine sichere Aussage „schneller als v1“ ist unter Rosetta nur für
Interpreten und Suche möglich. **Rosetta ist kein Ersatz für einen echten Intel-Mac** (dort läuft der Intel-Code
nativ und mit echter Grafikkarte) – auf dem MacBook Pro 2017 ist die App nicht gemessen.

### Vergleichsmessung A/B (gleicher Rechner, gleiche App, abwechselnd, je zweimal)

Workflow `abtest.yml`. Gemessen wurde, ob zwei Änderungen wirklich helfen:

| Scrollschritt (Mittel, zwei Läufe) | Cover mit GeometryReader | ohne GeometryReader | ohne Farbraum-Vorbereitung¹ |
|---|---|---|---|
| Titel-Detailliste | **53,9 / 48,1** | 147,0 / 85,1 | 98,8 / 134,9 |
| Titel kompakt | **116,7 / 120,2** | 177,6 / 145,9 | 148,9 / 195,6 |
| Alben kompakt | **56,6 / 62,6** | 103,8 / 68,8 | 123,8 / 97,6 |
| Alben-Liste | **47,1 / 92,7** | 115,3 / 88,0 | 147,7 / 99,1 |

¹ ohne GeometryReader und ohne Farbraum-Vorbereitung. Ergebnis: Die zwischenzeitlich eingebaute Variante
„ohne GeometryReader“ war **langsamer** und wurde zurückgenommen; die Vorbereitung im Bildschirmfarbraum hilft
(gegenüber ohne). Ausgeliefert ist: GeometryReader + Farbraum-Vorbereitung.

### Was die Zahlen nicht zeigen

- Die virtuellen Rechner haben keine echte Grafikkarte und schwanken stark; echte Macs sind beim Zeichnen
  meist schneller.
- Der Hänger-Wächter meldet im Messlauf eine Blockade beim Start: Das ist der Messlauf selbst (er erzeugt die
  10.000 Testtitel samt Covern und rechnet die Listen zur Zeitmessung einmal bewusst im Hauptthread), nicht die
  App im normalen Betrieb.
- Die Listenberechnung (Sortieren, Filtern, Suchen, intelligente Playlists) dauert bei 10.000 Titeln rund
  0,4–0,5 s auf Apple Silicon und läuft im Hintergrund; auf einem älteren Intel-Mac ist mit etwa dem Doppelten zu
  rechnen. Die Oberfläche bleibt dabei bedienbar, das Ergebnis erscheint entsprechend später.

## 4. Version 2.1

### Messlauf auf macOS 26 (Apple Silicon, Build-Lauf 18)

Gleiches Messprogramm, 10.000 Titel, **macOS 26.7 mit echtem Liquid Glass** (virtueller Mac, Apple M1). Die Zahlen
aus Abschnitt 3 stammen von macOS 14 (dort gibt es kein Liquid Glass) und sind deshalb **nicht direkt
vergleichbar** – GitHub bietet macOS 14 nicht mehr an.

| Messung (Mittel (p95) in ms bzw. %) | 2.1 auf macOS 26 |
|---|---|
| Alben-Raster scrollen | 33,3 (74,9) |
| Interpreten-Raster scrollen | 46,7 (85,9) |
| Titel-Liste scrollen | 47,0 (80,9) |
| Titel-Detailliste scrollen | 45,0 (63,1) |
| Bereich wechseln | 282,7 (620,0) |
| Suche: je Tastendruck | 23,4 (107,5) |
| Player öffnen/schließen (alle Designs) | 211,9 (558,0) |
| Leerlauf mit Wiedergabe (Mini-Player) | 22,2 % Hauptthread, 22,7 % CPU gesamt |
| Großer Vinyl-Player läuft | 33,1 % Hauptthread, 33,5 % CPU gesamt |

<!-- A/B -->
