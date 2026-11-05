# Player-Spezifikation (macOS) – Vinyl Studio · Classic Music · Cassette Studio · Portable CD

Diese Datei ist die **einzige Vorlage** für die SwiftUI-Umsetzung des Vollbild-Players, des Mini-Players
und der Player-Blätter. Sie beschreibt die Android-App (Kotlin/Compose, Stand der Portierung) exakt;
wo der Mac bewusst abweichen sollte, steht das ausdrücklich als **Mac-Hinweis** dabei.

Die rechenintensive Grafik (Plattenspieler, Kassette, CD-Player) kommt fertig aus dem Modul
**`MLRender`** (bitgenau gleiche Pixel wie Android). Die Oberfläche legt diese Ebenen nur noch
übereinander, dreht/verschiebt sie und zeichnet wenige Details live (Labels, Tonarm-Lage, Bandweg,
Anzeige, Leuchten).

---

## 0. Konventionen

| Thema | Regel |
|---|---|
| Längen | Android **dp → pt 1:1**. Werte in **px** sind echte Bildschirmpixel (pt × `backingScaleFactor`). |
| Schrift | Android-Material-Stile (`headlineSmall`, `bodyMedium` …) → gleichnamige `TextStyle`-Token der App (`Design/Theme.swift`, dort bereits auf den Mac skaliert). Feste `sp`-Angaben im Player (z. B. Zählwerk 20 sp) → gleiche Zahl × 0,875 pt (Verhältnis der Mac-Token). Text **in Gerätegrafiken** (Kassettenetikett, CD-Anzeige) ist in mm der Grafik angegeben → Größe in px = mm · k, in pt = mm · k / backingScale (unabhängig von Systemschriftgröße). |
| Farben | `0xAARRGGBB`. „α 0,3“ = Deckkraft der angegebenen Farbe auf 0,3 gesetzt (`Color.copy(alpha=)`), nicht multipliziert – außer wo „× “ steht. |
| Winkel | Grad, **im Uhrzeigersinn positiv**, 0° = nach rechts (Bildschirm, y nach unten) – wie `rotationEffect(.degrees(x))` in SwiftUI. |
| Zeiten | ms bzw. s. `tween(N)` ohne Angabe = **FastOutSlowIn** `cubic-bezier(0.4, 0, 0.2, 1)` über N ms (`MLRender.CubicBezierEasing.fastOutSlowIn`; SwiftUI `.timingCurve(0.4, 0, 0.2, 1, duration:)`). `linear` steht dabei. |
| Federn | Compose `spring(dampingRatio ζ, stiffness k)` (Masse 1) → SwiftUI `.interpolatingSpring(stiffness: k, damping: 2·ζ·√k)`. Compose-Standard ohne Angabe: `animateFloatAsState`/`animateColorAsState` → Feder ζ = 1, k = 1500; `Crossfade`/`fadeIn` ohne Spec → `tween(300)`. `Motion.standardSpring` = ζ 0,86 / k 420 (in der App als `Motion.standardSpring`). |
| „Bildschleife“ | Drehungen/Arm laufen pro Bild (`TimelineView(.animation)` oder `CVDisplayLink`), dt in s, **auf 0,1 s begrenzt**, nur solange der Player sichtbar ist (Fenster nicht verdeckt/minimiert, App aktiv – Android: Lifecycle ≥ STARTED) und solange sich etwas bewegt (sonst Schleife beenden). |
| Zustände | `isPlaying` = Player spielt tatsächlich (false beim Puffern), `playWhenReady` = Wiedergabe gewünscht, `playing = playWhenReady && !ended` (Wiedergabetaste), `hasMedia = currentUid != nil`, `buffering`, `speed` = Wiedergabetempo (Pitch-Modus „Schallplatte“ ≠ 1). |
| Position | `position` wird alle **250 ms** vom Player abgefragt, solange `isPlaying` und sichtbar; sonst einmal bei jeder Änderung von Titel, `isPlaying`, Dauer, `positionEpoch` (Spulen), Verbindung, Sichtbarkeit. `duration = player.durationMs > 0 ? player.durationMs : track.durationMs`; `progress = duration > 0 ? position / duration : 0`. |

### 0.1 Rasterbilder aus MLRender

* Alle Renderer liefern `RasterImage` (`width`, `height`, `pixels: [UInt32]` = `0xAARRGGBB`, **nicht**
  vormultipliziert, Zeile für Zeile, oben links beginnend).
* In `CGImage` umwandeln (einmal je Ebene, nicht pro Bild):

```swift
func makeCGImage(_ r: RasterImage) -> CGImage? {
    let data = r.pixels.withUnsafeBytes { Data($0) } as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(width: r.width, height: r.height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: r.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                            | CGImageAlphaInfo.first.rawValue),   // nicht vormultipliziert
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}
```

  (Alternative: `r.premultipliedPixels()` + `CGImageAlphaInfo.premultipliedFirst`.)
* Ein Cover (NSImage/CGImage) → `RasterImage`: in einen 32-Bit-`CGContext` (sRGB,
  `premultipliedFirst | byteOrder32Little`) zeichnen und auf nicht vormultipliziert zurückrechnen.
* **Ebenen in genau der Pixelgröße rechnen und 1:1 zeichnen** (Bildpunkt = Gerätepixel, Interpolation
  hoch nur für Drehungen). Die Größe in px ergibt sich aus der Fläche in pt × `backingScaleFactor`.

### 0.2 Zwischenspeicher der Ebenen (wie `SizedAssetCache`)

* Je Design ein Speicher, Schlüssel = Größe in px, **höchstens 3 Größen** (zuletzt benutzte bleiben;
  z. B. Player + kleine Vorschauen), Berechnung im Hintergrund auf allen Kernen, laufende Berechnungen
  werden von allen Anfragen derselben Größe geteilt und laufen zu Ende, auch wenn die Ansicht weg ist.
  Fehler (Speicher) → `nil` → Platzhalter bleibt.
* Bis die Ebenen da sind: **Platzhalter** (je Design unten), dann Einblenden der fertigen Grafik
  (Deckkraft 0→1, `tween(420)` Plattenspieler bzw. `tween(380)` Kassette/CD). Danach Platzhalter weg.
* Android zeigt nach einer Größenänderung bis zur Neuberechnung den Platzhalter. **Mac-Hinweis:** beim
  Ziehen der Fenstergröße die zuletzt fertige Grafik skaliert weiterzeigen, die neue Größe erst nach
  ≈ 150 ms Ruhe rechnen und dann ohne Platzhalter austauschen (sonst flackert der Platzhalter).
* Rechenzeiten (Release, 2 Kerne, siehe Bericht): Plattenspieler ≈ 0,1–0,2 s bei S = 1040 px,
  CD-Player ≈ 0,3 s bei 1040 px Breite.

---

## 1. Gemeinsamer Vollbild-Player (alle vier Designs)

### 1.1 Einblenden / Schließen (AppRoot)

* Der Player liegt als Ebene über der Bibliothek. Öffnungsgrad `f` (0…1) animiert mit Feder
  ζ 0,9 / k 340 (öffnen und schließen; in der App `Motion.playerSpring`).
* Bibliothek dahinter: Skalierung `1 − 0,07·f`, Eckenradius `30·f` pt, darunter Schwarz; darüber
  Abdunklung Schwarz α (0,55 dunkel / 0,38 hell) × `f`.
* Player: um `(1 − f) · Höhe` nach unten verschoben, obere Ecken 30 pt rund, solange `f < 0,999`.
* Ziehen nach unten am **Griff** (Kopfzeile; zusätzlich das Mittelstück, wenn die Seite nicht scrollen
  muss) folgt dem Finger (`f −= Δy / Höhe`); Loslassen: `f < 0,8` oder Geschwindigkeit > 1800 pt/s →
  schließen (Feder 0,9/340), sonst zurück (Feder ζ 0,85 / k 420).
* Der Player fängt alle Klicks ab (nichts geht zur Bibliothek durch).
* Mini-Player blendet beim Öffnen aus: α = clamp(1 − 1,6·f, 0, 1).

### 1.2 Farben je Design (`PlayerThemeColors`)

Innerhalb des Players (inkl. Menüs und Blätter, die daraus geöffnet werden) gilt der Farbsatz des Designs:

| Design | Farbsatz |
|---|---|
| Vinyl Studio | App-Farben (hell **oder** dunkel, folgt der App) |
| Portable CD | App-Farben (hell oder dunkel); das Gerät selbst ist immer Graphit |
| Classic Music | `ClassicColors` (immer dunkel), Tabelle unten |
| Cassette Studio | `CassetteColors` (immer dunkel), Tabelle unten |

App-Farben (`Tokens.kt` = `Design/Theme.swift`):

| Feld | Hell | Dunkel |
|---|---|---|
| background | 0xFFFBF8F7 | 0xFF0F0D0E |
| backgroundGrouped | 0xFFF4EFEE | 0xFF151213 |
| surface | 0xFFFFFFFF | 0xFF1C1819 |
| surfaceMuted | 0xFFF1ECEB | 0xFF231F20 |
| textPrimary | 0xFF1D1B1C | 0xFFF6F2F3 |
| textSecondary | 0xFF6B6466 | 0xFFABA3A6 |
| textTertiary | 0xFF716A6C | 0xFF8E8689 |
| accent | 0xFFD4566F | 0xFFF27A93 |
| accentText | 0xFFB93A5A | 0xFFFF8FA6 |
| accentStrong | 0xFFC23C5C | 0xFFFF6F8F |
| accentSoft | 0x1FD4566F | 0x29F27A93 |
| onAccent | 0xFFFFFFFF | 0xFF2A0E17 |
| heart | 0xFFC93D5C | 0xFFFF6F8F |
| hairline | 0x141D1B1C | 0x17FFFFFF |
| glassTint / glassTintStrong | 0x9EFFFFFF / 0xCCFFFFFF | 0xA81E1A1C / 0xD1241F21 |
| glassEdgeLight / glassEdgeDark | 0xE6FFFFFF / 0x40FFFFFF | 0x38FFFFFF / 0x0DFFFFFF |
| glassSheen / glassShadow | 0x59FFFFFF / 0x24301018 | 0x14FFFFFF / 0x8C000000 |
| scrim | 0x52140A0E | 0x8C000000 |

`ClassicColors` = Dunkel, außer: background 0xFF121012, textPrimary 0xFFFFFFFF, textSecondary
0xB8FFFFFF, textTertiary 0x8FFFFFFF, accent 0xFFFF8FA6, accentText 0xFFFFA8BA, accentSoft 0x33FF8FA6,
hairline 0x1FFFFFFF, glassTint 0x21FFFFFF, glassTintStrong 0x2BFFFFFF, glassEdgeLight 0x40FFFFFF,
glassEdgeDark 0x12FFFFFF, glassSheen 0x17FFFFFF, glassShadow 0x66000000.

`CassetteColors` = Dunkel, außer: background 0xFF141012, backgroundGrouped 0xFF181315, surface
0xFF211B1D, textSecondary 0xFFB3A8A9, textTertiary 0xFFA8A0A2, accent 0xFFFF8FA6, accentText
0xFFFF9DB2, accentSoft 0x2EFF9DB2, glassTint 0x24FFE9E0, glassTintStrong 0x2EFFE9E0, glassEdgeLight
0x3DFFF1EA, glassEdgeDark 0x0FFFFFFF, glassSheen 0x14FFF4EE.

### 1.3 Aufbau und Maße

Reihenfolge in allen Designs: **Hintergrund → Kopfzeile → Mittelstück („Hero“) → [Frequenzbalken] →
Titelangaben → Fortschritt → Wiedergabetasten → Lautstärke → Werkzeugleiste.** Der Hintergrund füllt das
ganze Fenster; Inhalte liegen innerhalb der sicheren Fläche.

Konstanten: `TOP_BAR_HEIGHT = 52`, `CONTROLS_HEIGHT = 418` (Höhe aller Bedienelemente unter dem
Mittelstück, nur zur Größenberechnung), `VISUALIZER_HEIGHT = 34`. `showBars = Visualisierung aktiv &&
Design ≠ Cassette`.

**Querformat** (`Breite > Höhe && Breite ≥ 560`) – auf dem Mac der Normalfall:
* Zeile, horizontaler Innenabstand 20, vertikal zentriert.
* Links Spalte (zentriert): Hero mit Seitenlänge
  `side = min(Höhe − 24 − (showBars ? 34 : 0), Breite · 0,48)`; bei `showBars` darunter 8 Abstand und
  eine Box der Breite `side` mit den Frequenzbalken (zentriert). Diese Spalte ist Zieh-Griff.
* 24 Abstand.
* Rechts Spalte (füllt den Rest, volle Höhe, vertikal scrollbar, vertikaler Innenabstand 8, Inhalt
  vertikal zentriert): Kopfzeile, 8 Abstand, Bedienelemente (1.5).

**Hochformat:**
* Spalte, scrollbar, horizontaler Innenabstand 22, Inhalte zentriert.
* `reserved = 52 + 418 + (showBars ? 34 : 0)`;
  `side = max(200, min(Breite − 44, Höhe − reserved, 520))`; `free = max(0, Höhe − reserved − side)`.
* Kopfzeile (Griff) → Abstand `clamp(free/2, 4, 28)` → Hero (`side`) → [8 + Balken] →
  Abstand `clamp(free/2, 10, 28)` → Bedienelemente (max. Breite 560) → 12.

**Hero** = quadratische Fläche `side × side`, Inhalt je Design (Kapitel 2–5). Designwechsel:
Überblendung des Hero-Inhalts `tween(420)`, der Hintergrund wechselt ohne Überblendung.

### 1.4 Kopfzeile (Höhe 52)

* Links `GlassIconButton` 38 pt, Symbol `expand_more` 22 pt, „Player schließen“.
* Mitte (füllt, Innenabstand horizontal 10, zentriert):
  * Zeile 1: `(single ? "WIEDERGABE" : "SPIELT AUS") + (queueSize > 1 ? " · \(currentIndex + 1) VON \(queueSize)" : "")`,
    Stil `sectionLabel` (Inter SemiBold 12/16, Laufweite 0,04 em), Farbe textSecondary, 1 Zeile.
    `single = Quelle fehlt || Quelle.kind == SINGLE_TRACK`.
  * Zeile 2: `!single ? Quelle.label : (queueSize > 1 ? "Einzelner Titel mit Warteschlange" : "Einzelner Titel")`,
    `labelLarge`, textPrimary, 1 Zeile, Auslassung.
  * Zeile 3 nur bei laufendem Sleep-Timer: Symbol `bedtime_fill` 11 pt + 3 Abstand + Text (Stil `time`,
    11 sp, accentText): „Titelende“ bzw. Restzeit `Formatting.countdown(rest)` (sekündlich, auf die
    volle Sekunde ausgerichtet aktualisiert).
* Rechts `GlassIconButton` 38/22 `more_vert` „Weitere Aktionen“ → Menü (Eckenradius 18, Grund
  `surface`), Einträge mit Symbol:
  1. „Zu Playlist hinzufügen …“ (`playlist_add`)
  2. „Album öffnen“ (`album`) – nur wenn der Titel zu einem Album gehört; schließt den Player
  3. „Player-Design …“ (`vinyl`) → Blatt *Design* (8.7)
  4. „Klangvisualisierung aus“ / „… an“ (`graphic_eq`) – schaltet die Einstellung um
  5. „Songinformationen“ (`info`) → Blatt *Songinfo* (8.6)

### 1.5 Bedienelemente (Spalte, volle Breite)

1. **Titelangaben** (Zeile):
   * Spalte (füllt), beim Titelwechsel Überblendung (neu `fadeIn 280`, alt `fadeOut 180`, gleichzeitig,
     Schlüssel = Titel-ID):
     * Titel – `headlineSmall` (Inter Display Bold 22/28), textPrimary, 1 Zeile, **Laufschrift**
       (endlos, Start nach 2,5 s, Pause 2,5 s zwischen Durchläufen, 30 pt/s, Abstand ⅓ Breite).
     * Interpret – `titleMedium`, accentText, 1 Zeile, Auslassung; fehlt → „Unbekannter Interpret“.
     * Album – `bodyMedium`, textSecondary, 1 Zeile; fehlt → „Unbekanntes Album“; klickbar („Album
       öffnen“, schließt den Player), wenn ein Album existiert.
   * 8 Abstand, `GlassSurface` Kreis 44 pt mit `HeartButton` (Symbol 22, Tippfläche 44, inaktiv
     textPrimary α 0,7; aktiv `heart`, kleine Feder 0,7→1 beim Favorisieren, Feder ζ 0,6 / k 500).
2. 14 Abstand.
3. **Fortschritt** (`SeekArea`):
   * `MusicSlider` (Anhang A.1), Wert = Anteil; aus, wenn Dauer = 0. Während des Ziehens zeigt der Regler
     und die Zeit den Zugwert; beim Loslassen `seekTo(anteil · dauer)`. Danach wird der gewählte Wert bis
     zu 1,5 s gehalten, solange die gemeldete Position mehr als 1,2 s davon abweicht (kein Zurückspringen).
   * Zeile darunter: links Zeit `Formatting.duration(shown)` (Stil `time` = Inter Medium 12/16,
     Ziffern gleich breit, textSecondary, Breite 56) · flexibler Abstand · `IconTap` `shuffle`
     (19/40, accentText wenn an, sonst textSecondary) · 18 · `IconTap` `repeat`/`repeat_one`
     (19/40, accentText wenn ≠ aus) · flexibler Abstand · rechts „−“ + Restzeit (rechtsbündig, Breite 56).
4. 6 Abstand.
5. **Wiedergabetasten** – Stil je Design (Funktionen gleich, Reihenfolge siehe Tabelle):

| Stil | Designs | Reihenfolge links → rechts |
|---|---|---|
| ICONS | Vinyl Studio, Classic | −10 s · vorheriger · Play/Pause · nächster · +10 s |
| DECK_KEYS | Cassette | vorheriger · −10 s · Play/Pause · +10 s · nächster |
| CD_BUTTONS | Portable CD | −10 s · vorheriger · Play/Pause · nächster · +10 s |

   *ICONS*: Zeile, gleichmäßig verteilt (`SpaceEvenly`), vertikal zentriert:
   `replay_10` (Symbol 26, Fläche 48, textSecondary) · `fast_rewind` (40/60) ·
   `play`/`pause` (58/76, Überblendung 160 ms) · `fast_forward` (40/60, aus wenn kein nächster Titel) ·
   `forward_10` (26/48, textSecondary). Play/Pause zeigt `playing` (= playWhenReady && !ended).
   Vorheriger = „Vorheriger Titel bzw. Titelanfang“ (`controller.previous()`), ±10 s = `seekBy(±10 000)`.
   *DECK_KEYS* → 4.6, *CD_BUTTONS* → 5.6.
6. 10 Abstand.
7. **Lautstärke** (App-Lautstärke 0–300 %):
   * Zeile: `IconTap` (`volume_off` bei 0, sonst `volume_down`; 18/36, textSecondary; setzt auf 100 %)
     · `MusicSlider` (Bereich 0…3, Markierung bei 1 mit Rosé darüber, horizontaler Innenabstand 4,
     füllt) · Prozent `Formatting.percent(v)` (Stil `time`, Breite 48, rechtsbündig, accentText wenn
     > 100 %, sonst textSecondary).
   * Ziehen rastet: `|v − 1| < 0,04 → 1`, sonst auf 5 % (`round(v·20)/20`).
   * Bei > 100 % darunter (`labelSmall`, textSecondary, Einzug 40): Limiter-Reduktion < −0,5 dB →
     „Verstärkung aktiv · Limiter begrenzt Spitzen (−x dB)“, sonst „Digitale Verstärkung über 100 % aktiv“
     (Limiterwert alle 300 ms abfragen, nur bei Wiedergabe).
8. 14 Abstand.
9. **Werkzeugleiste**: `GlassSurface` volle Breite, Höhe 68, Eckenradius 30, `strong` (Tönung
   glassTintStrong, **ohne** Hintergrundunschärfe im Player), Zeile mit 6 Innenabstand, fünf gleich breite
   Felder (volle Höhe, Eckenradius 18 beim Klicken, vertikal 6 Innenabstand): Kapsel 40 × 28 (Grund
   accentSoft wenn aktiv) mit Symbol 21 (accentText aktiv, sonst textPrimary), 3 Abstand, Text
   `labelSmall` (accentText aktiv, sonst textSecondary, 1 Zeile):

| Feld | Symbol | Text | aktiv wenn | öffnet |
|---|---|---|---|---|
| Equalizer | `tune` | EQ an & nicht neutral → Name der Voreinstellung oder „Eigen“; sonst Bass ≠ 0 → „Bass +x“; sonst „Equalizer“ | EQ an & nicht neutral, oder Bass ≠ 0 | 8.2 |
| Tonhöhe | `pitch` | „Tonhöhe“ bzw. „+2 HT“, „−1,5 HT“ | Halbtöne ≠ 0 | 8.3 |
| Sleep-Timer | `bedtime` / aktiv `bedtime_fill` | „Timer“ bzw. Restzeit / „Titelende“ | Timer läuft | 8.4 |
| Liste | `queue_music` | „Liste“ | nie | 8.5 |
| Info | `info` | „Info“ | nie | 8.6 |

   Kurzzahl („+2“, „−1,5“): auf 0,1 runden, Vorzeichen „+“ bzw. „−“ (U+2212), ganze Zahl ohne
   Nachkomma, sonst Dezimalkomma.

### 1.6 Frequenzbalken unter dem Hero (`SpectrumBars`)

Nur bei `showBars`. Breite 72 % (Hochformat: der Spalte; Querformat: von `side`), Höhe 26, zentriert,
8 Abstand über dem Hero-Unterrand. Zeichnung und Daten → Kapitel 6.

### 1.7 Statusabhängiges Verhalten (Übersicht)

| Ereignis | Vinyl Studio | Classic | Cassette | Portable CD |
|---|---|---|---|---|
| Wiedergabe startet | Teller läuft an (τ 0,18 s), Arm senkt sich (480 ms), LED hell | Cover wächst 0,86→1 (520 ms) | Naben laufen an (τ 0,15 s), LED PLAY | CD läuft an (τ 0,14 s), ▶ leuchtet, LED hell |
| Pause | Teller läuft aus (τ 0,28 s), Arm hebt sich (480 ms), LED gedimmt | Cover schrumpft auf 0,86 | Naben laufen aus (τ 0,22 s), LED PAUSE | CD läuft aus (τ 0,32 s), ❚❚ leuchtet, LED gedimmt |
| Puffern (nach Spulen) | wie Pause (folgt `isPlaying`) | wie Pause | wie Pause | **dreht weiter** (`isPlaying || playWhenReady && buffering`), Anzeige bleibt ▶ |
| Spulen | Arm schwenkt angehoben zur neuen Stelle, wenn Sprung > 3 % | – | Wickelradien springen sofort | nur Zeitanzeige ändert sich |
| Titelwechsel | Label blendet über (380 ms), Arm springt auf Einlauf | Cover blendet über (420 ms) | Cover blendet über (320 ms), Wickel springen auf links voll | Label blendet über (380 ms), Titelnummer/Zeit neu |
| kein Titel | Arm in Ruhestellung (−1), Platte steht | – | Wickel links voll | Hinterleuchtung 0,4 statt 1, Doppelpunkt/▶/❚❚ unbeleuchtet, Titel „--“, LED fast aus (0,08) |
| Tempo ≠ 1 (Pitch „Schallplatte“) | 200°/s · Tempo, LED wechselt auf „45“ bei Tempo > 1,17 | – | Naben · clamp(Tempo, 0,25, 4) | 216°/s · clamp(Tempo, 0,5, 2) |

Es gibt **keine** Gesten auf dem Mittelstück (kein Ziehen des Tonarms, kein Scratchen); Spulen nur über
den Fortschrittsregler und die ±10-s-Tasten. Das Mittelstück dient lediglich als Zieh-Griff zum
Schließen.

---

## 2. Vinyl Studio

### 2.1 Hintergrund (unterste Ebene, ganzes Fenster)

1. `AmbientBackground` der App (Grundfarbe + drei weiche Farbflächen).
2. Nur wenn Cover vorhanden **und** Glas-Effekte an: das Cover, `aspectFill` über das ganze Fenster,
   Weichzeichner Radius 90 pt (Ränder geklemmt), Skalierung 1,25 (um die Mitte), Deckkraft 0,85 (dunkel)
   bzw. 0,75 (hell); Coverwechsel blendet 600 ms über.
3. Nur in demselben Fall: senkrechter Verlauf `background` α 0,52 → α 0,80 (dunkel) bzw. 0,58 → 0,84
   (hell), oben → unten.
4. „Studiolicht“: radialer Verlauf Weiß α 0,07 (dunkel) / 0,22 (hell) → transparent, Mitte
   (0,28·B, 0,12·H), Radius 0,95·B.

### 2.2 Hero

Box `side × side`, darin:
* **Bodenschatten** hinter allem: Kreis mit radialem Verlauf Schwarz α 0,55 (dunkel) / 0,22 (hell) →
  transparent, Mitte (0,5·side, 0,56·side), Radius 0,62·side.
* **Plattenspieler** füllt die Box (quadratisch), mit Schlagschatten der Form „Rechteck mit 7 %
  Eckenradius“ (Android-Elevation 24 dp, Umgebungsfarbe glassShadow, Spot Schwarz α 0,5;
  Mac: z. B. `.shadow(color: .black.opacity(0.5·0.6), radius: 12, y: 12)` + `.shadow(color: glassShadow, radius: 12)`).

### 2.3 Plattenspieler – Ebenen von unten nach oben

`S` = Seitenlänge in px (`round(side · scale)`, mindestens 64). Geometrie: `TurntableGeometry`
(alles relativ zu S). Hilfsgrößen:

* `recordPx = VinylRenderer.recordSizePx(S)` (= round(2·0,415·1,035·S) ≈ 0,859·S)
* `labelPx = VinylRenderer.labelSizePx(S)` (= round(2·0,34·0,415·S) ≈ 0,282·S)
* `recordLeft = round(0,455·S − recordPx/2)`, `recordTop = round(0,5·S − recordPx/2)` (px, ganzzahlig)

| # | Ebene | Quelle | Lage | dreht? |
|---|---|---|---|---|
| 0 | Platzhalter (nur bis die Ebenen fertig sind) | live: abgerundetes Rechteck 0xFF1B191A, Radius 0,07·S, volle Fläche; Kreis 0xFF0B0A0B, Radius 0,415·S, Mitte (0,455·S, 0,5·S) | ganze Fläche | nein |
| 1 | Gehäuse | `VinylRenderer.plinth(S)` (S×S) | (0, 0) | nein |
| 2 | Platte + Tellerrand | `VinylRenderer.record(recordPx)` | (recordLeft, recordTop) | **ja**, um die Mitte des recordPx-Quadrats |
| 3 | Label | siehe 2.4, Größe labelPx, mittig auf Ebene 2 | Mitte der Platte | **ja** (mit Ebene 2) |
| 4 | Papier-Anmutung des Labels | live, siehe 2.4 | wie 3 | **ja** |
| 5 | Lichtreflexe, Labelglanz, Spindel | `VinylRenderer.sheen(recordPx)` | (recordLeft, recordTop) | **nein** (steht still!) |
| 6 | Betriebsleuchte | live, 2.6 | – | nein |
| 7 | Tonarm-Schatten | `VinylRenderer.tonearm(S).shadow` | `TonearmPose` (2.5) | Armwinkel |
| 8 | Tonarm | `VinylRenderer.tonearm(S).arm` | `TonearmPose` | Armwinkel |

Ebenen 1–8 werden zusammen eingeblendet (2.8). Ebenen 2–4 bilden **eine** Gruppe, die als Ganzes per
Transformation gedreht wird (keine Neuberechnung pro Bild).

### 2.4 Label (dreht sich mit)

Inhalt wechselt per Überblendung **380 ms**, Schlüssel = (Titel-ID, Cover-Bild, Cover lädt):

* **Cover lädt noch und kein Bild:** Kreis 0xFF1A1718 (volle Labelgröße) + Kreisring 0xFF2A2526,
  Radius 0,46·labelPx, Strichbreite 0,012·labelPx. (Nie das Cover des vorigen Titels zeigen.)
* **Cover vorhanden:** `CoverLabel.circular(coverRaster, size: labelPx)` (mittig quadratisch
  zugeschnitten, geglätteter runder Rand) – im Hintergrund erzeugen, nur bei Titel-/Cover-Wechsel. Bis es
  fertig ist (wenige ms) wird nichts gezeichnet (die dunkle Platte darunter ist sichtbar); schlägt es
  fehl, das Cover selbst (aspectFill, kreisrund beschnitten).
* **Kein Cover:** `VinylRenderer.fallbackLabel(labelPx)` (gedecktes Rosé mit Ringen) und darauf Text
  (dreht mit): Spalte mittig, Breite 62 % des Labels, unterer Innenabstand 4 % der Labelbreite;
  `base = clamp(labelBreite_pt · 0,085, 7, 14)` pt;
  Titel Inter SemiBold `base`, Zeilenhöhe 1,15·base, Farbe 0xFFF3E6DE (Creme), zentriert, max. 2 Zeilen;
  Interpret (falls vorhanden) Inter Medium 0,8·base, Creme α 0,8, 1 Zeile.

Darüber (Ebene 4, live, ebenfalls drehend), `r = labelPx/2`:
1. Kreis Radius r mit radialem Verlauf ab Mitte: Stopp 0,80 transparent → 0,97 Schwarz α 0,32 → 1,0
   Schwarz α 0,55 (Randabschattung).
2. Kreisring Weiß α 0,10, Radius 0,90·r, Strich 0,012·r (eingepresster Ring).
3. Kreisring Schwarz α 0,18, Radius 0,915·r, Strich 0,01·r.

### 2.5 Tonarm

**Geometrie** (`TurntableGeometry`, Einheiten von S): Drehpunkt (0,875; 0,20); Rohr 0,505, Tonkopf
0,07 unter 22° abgewinkelt; Ruhewinkel **84°**; Nadel bei Fortschritt 0 auf 0,945·R (Einlauf), bei 1 auf
0,42·R (Auslauf). `TurntableGeometry.armAngleForProgress(p)`:

| p | Winkel |
|---|---|
| −1 (Ruhe) | 84,000° |
| 0 (Einlauf) | 99,889° |
| 0,35 | 108,424° |
| 1 (Auslauf) | 124,274° |

Für p ≥ 0 ist der Winkel **linear in p** zwischen Einlauf- und Auslaufwinkel (nicht linear im Radius);
für −1 ≤ p < 0 linear zwischen Ruhe und Einlauf.

**Zeichnen** (je Bild): `let pose = TonearmPose(size: S, arm: armRaster, progress: motion.progress, lift: motion.lift)`
1. Schatten: Bild `armRaster.shadow` mit linker oberer Ecke bei `(pose.shadowOriginX, pose.shadowOriginY)`,
   gedreht um `pose.angleDegrees` um den Punkt `shadowOrigin + (armRaster.pivotX, armRaster.pivotY)`,
   Deckkraft `pose.shadowAlpha` (= 1 − 0,4·lift). Versatz = S·(0,006 + 0,020·lift) nach rechts und
   ×1,3 nach unten.
2. Arm: `armRaster.arm` bei `(pose.armOriginX, pose.armOriginY)` (= Drehpunkt der Fläche − Drehpunkt im
   Bild), gedreht um denselben Winkel um `armOrigin + pivot`, zusätzlich um denselben Punkt skaliert mit
   `pose.armScale` (= 1 + 0,03·lift → wirkt „näher“).
   SwiftUI: `Image(arm).frame(w,h).scaleEffect(armScale, anchor: pivotAnchor).rotationEffect(.degrees(angle), anchor: pivotAnchor).offset(armOrigin)` mit `pivotAnchor = UnitPoint(x: pivotX/w, y: pivotY/h)`.

**Bewegung** – `MLRender.TonearmMotion` (je Bild `step(dt)`), entspricht genau Android:
* Ziel: `hasMedia ? clamp(progress, 0, 1) : −1` → bei jeder Änderung `setTarget(_)`; Ziele werden
  nacheinander abgearbeitet, während einer laufenden Bewegung wartet nur das neueste.
* Abstand > **0,03**: Arm hebt an (`jumpLift` 0→1 in 160 ms, FastOutSlowIn) und schwenkt gleichzeitig per
  Feder (k 110, ζ 0,92, Ende bei Restauslenkung < 0,01 → ≈ 0,4–0,5 s); wenn beides fertig ist, senkt er
  sich (`jumpLift` → 0 in 260 ms). Auslöser: Titelwechsel, Spulen, Wiederholen, Wegfall des Titels
  (Ziel −1 = Ruhestellung).
* Abstand ≤ 0,03: **lineares** Nachführen in 260 ms (bei Wiedergabe kommt alle 250 ms ein neues Ziel →
  gleichmäßiges Wandern nach innen).
* Pause/Wiedergabe: `setPlaying(isPlaying)` → `pauseLift` → 1 bzw. 0 in **480 ms** (FastOutSlowIn,
  Neustart vom aktuellen Wert bei Richtungswechsel).
* `lift = max(pauseLift, jumpLift)`.
* Startzustand beim Öffnen: Ziel ohne Animation, `pauseLift` = 0 (spielt) bzw. 1 (Pause).
* Statische Vorschau (`still`): `snap(to:playing:)` – keine Bewegung.

### 2.6 Betriebsleuchte (33/45)

Farbe 0xFFFF7D98. Knopf `i = speed > 1,17 ? 1 (45) : 0 (33)`; Mitte
`(SPEED_BUTTONS[2i]·S, (SPEED_BUTTONS[2i+1] − 0,032)·S)` = (0,072·S bzw. 0,125·S; 0,908·S);
`r = 0,0042·S`. `glow` animiert `tween(400)` → 1 bei `isPlaying`, sonst 0,25.
* Hof: Kreis Radius 4,5·r, radialer Verlauf Farbe α 0,55·glow → transparent.
* Punkt: Kreis Radius r, Farbe α (0,35 + 0,65·glow).

### 2.7 Drehung der Platte

`MLRender.TurntableSpin`: Ziel `targetSpeed(playing: isPlaying, speed:)` = **200 °/s · Tempo**
(33⅓ U/min), nicht begrenzt; je Bild `step(target:dt:)`:
`v += (Ziel − v)·(1 − e^(−dt/τ))`, τ = 0,18 s beim Beschleunigen, 0,28 s beim Abbremsen; |Ziel − v|
< 0,5 → v = Ziel; `Winkel = (Winkel + v·dt) mod 360` (im Uhrzeigersinn). Schleife endet, wenn Ziel und v
0 sind. Unsichtbar/Vorschau → `stop()` (v = 0, Winkel bleibt). Die Drehung hängt **nur** vom
Wiedergabezustand ab, nie von der Position.

### 2.8 Sonstiges

* Einblenden der fertigen Ebenen: Deckkraft 0→1 in `tween(420)`; Platzhalter (Ebene 0) nur, solange
  Deckkraft < 1.
* Rechnen der Ebenen (parallel): `plinth(S)`, `record(recordPx)`, `sheen(recordPx)`, `tonearm(S)`,
  `fallbackLabel(labelPx)`.
* Bedienungshilfe: „Plattenspieler, keine Wiedergabe“ / „Plattenspieler: Platte dreht sich, Tonarm
  aufgesetzt“ / „Plattenspieler: angehalten, Tonarm angehoben“.
* Hell/Dunkel: Plattenspieler-Grafik identisch; nur Hintergrund (2.1), Bodenschatten (2.2) und die
  App-Farben der Bedienelemente ändern sich.

---

## 3. Classic Music

### 3.1 Hintergrund

Farben aus `CoverPalette` (MLCore): `top`, `bottom`, `glow`; jede Farbe wechselt mit
Farbanimation **900 ms** (`tween`).
1. Senkrechter Verlauf `top` → `bottom` (ganze Fläche).
2. Radialer Verlauf `glow` α 0,30 → transparent, Mitte (0,5·B, 0,30·H), Radius 0,9·B.
3. Senkrechter Verlauf: bei 55 % transparent → bei 100 % Schwarz α 0,35.

Palette (`rememberCoverPalette`): aus dem Cover, auf **32 × 32** verkleinert (ganzes Bild, nicht
zugeschnitten: `CoverLabel.scaled(cover, width: 32, height: 32)`), → `CoverPalette.from(pixels:)`. Ohne
Cover: 64 Pixel in der Farbe der Genre-Familie (`GenrePalette.forCategory(...)`, wie das Ersatz-Cover).
Neutral (`CoverPalette.neutral`) als Startwert. Während das Cover lädt, bleibt die bisherige Palette
stehen; Ergebnisse je `coverKey + Ladezustand` zwischenspeichern (32 Einträge).

### 3.2 Hero

* Fläche 94 % von `side` (mittig), skaliert mit `scale` = 1 bei `isPlaying`, sonst **0,86**
  (`tween(520)`).
* Darin das Cover (`ArtworkBox`, aspectFill, Eckenradius 14, Ersatz: Genre-Bild in großer Fassung bzw.
  Verlauf + Symbol mit 40 % Größe; beim Laden neutrale Fläche) mit weichem Schatten: Elevation 34 dp,
  Umgebungsfarbe `glow` α 0,5, Spot Schwarz α 0,55 (Mac: zwei `.shadow` – farbig weich ≈ Radius 17,
  dunkel ≈ Radius 17, y 17).
* Titelwechsel (Schlüssel Titel-ID): neues Cover `fadeIn 420` + `scaleIn` von 0,96 (420), altes
  `fadeOut 260`, gleichzeitig.

Wiedergabetasten Stil ICONS. Farben `ClassicColors`.

---

## 4. Cassette Studio

### 4.1 Hintergrund

1. Senkrechter Verlauf 0xFF2A2224 → 0xFF161213 → 0xFF0E0B0C (gleichmäßig).
2. Radialer Verlauf 0x24FFB8A0 → transparent, Mitte (0,5·B, 0), Radius 1,1·B.
3. Waagerechte Linien (1 px) alle 3 pt ab y = 0, solange y < 0,62·H: Weiß α 0,018 bei jeder dritten
   Linie (i % 3 == 0), sonst α 0,008.

### 4.2 Hero-Aufbau

Spalte, volle Breite von `side`, im Quadrat vertikal zentriert:
1. **Kassettenfach**: volle Breite, Seitenverhältnis 1,43 (B/H), Eckenradius 22, Grund senkrechter
   Verlauf 0xFF1F1A1C → 0xFF0C0A0B, Rand 1 pt mit senkrechtem Verlauf Schwarz α 0,7 → Weiß α 0,10.
   Darin, übereinander, alles zentriert:
   1. Innenlicht: radialer Verlauf 0x33FF9DB2 → transparent, Mitte (0,5·B, 0), Radius 0,75·B.
   2. **Kassette**: Breite 94 % des Fachs → `W` px (gerundet, ≥ 64); Höhe
      `CassetteRenderer.heightFor(W)` px. Inhalt 4.3, Einblenden `tween(380)`.
   3. Glasscheibe: Rechteck mit linearem Verlauf von (0,0) nach (B,H): 0 Weiß α 0,07 · 0,35 Weiß
      α 0,015 · 0,36 transparent · 1 transparent; Linie Weiß α 0,12 von (0,06·B, 1,5 px) nach
      (0,94·B, 1,5 px), 1,5 px stark.
2. 10 Abstand, **Statusleiste** (4.5) – nur im Player, nicht in Vorschauen.

### 4.3 Kassette – Ebenen (Koordinaten in px der Kassettenbox)

`k = CassetteRenderer.pxPerMm(W)` (= W / 108,4), `m = MARGIN_MM = 4`, `X(mm) = (mm + m)·k` (für x **und**
y). Geometrie `CassetteGeometry` (mm): Naben (28,9 | 71,5; 30,5), Rollen (13,6 | 86,8; 53,2) r 2,3,
Band auf y = 55,5.

| # | Ebene | Quelle / Zeichnung |
|---|---|---|
| 1 | Rückwand, Innenleben, Schatten | `CassetteRenderer.back(W)` bei (0,0) |
| 2 | Wickel links | `CassetteRenderer.pack(W)` mit Mitte auf (X(28,9), X(30,5)) (linke obere Ecke = Mitte − pack.width/2), **beschnitten** auf Kreis Radius `packLeft·k` um diese Mitte |
| 3 | Wickel rechts | ebenso bei X(71,5), Radius `packRight·k` |
| 4 | Bandweg (live) | Farbe 0xFF2A1D18, Strich `s = max(0,42·k, 1)` px: (a) von `tangentPoint(Nabe links, packLeft·k, von: L, left: true)` nach `L = (X(13,6 − 2,3), X(53,2))`, runde Enden; (b) von `tangentPoint(Nabe rechts, packRight·k, von: R, left: false)` nach `R = (X(86,8 + 2,3), X(53,2))`, rund; (c) waagerecht von (X(13,6), X(55,5)) nach (X(86,8), X(55,5)), Strich 1,1·s, stumpfe Enden |
| 5 | Nabe links | `CassetteRenderer.hub(W)` bei ganzzahliger Ecke (Int(cx − hub.width/2), Int(cy − hub.width/2)), gedreht um `angleLeft` um (cx, cy) = (X(28,9), X(30,5)) |
| 6 | Nabe rechts | ebenso mit `angleRight` um (X(71,5), X(30,5)) |
| 7 | Vorderschale + Etikettpapier | `CassetteRenderer.front(W)` bei (0,0) |
| 8 | Etikettinhalt (live) | 4.4 |

`tangentPoint` = `CassetteGeometry.tangentPoint(cx:cy:r:fromX:fromY:left:)` (alles in px).

**Wickelradien:** `(packLeft, packRight) = CassetteGeometry.packRadii(hasMedia ? progress : 0)` in mm
(Flächenerhalt: links voll = 21,6 mm, rechts leer = 8,6 mm bei 0; umgekehrt bei 1). Sie folgen dem
Fortschritt **direkt ohne Animation** (Spulen/Titelwechsel → Sprung).

**Naben-Drehung:** `MLRender.CassetteReels` je Bild
`step(target: targetMotor(playing: isPlaying, speed:), radiusLeftMm: packLeft, radiusRightMm: packRight, dt:)`:
Motorfaktor folgt dem Ziel (`clamp(Tempo, 0,25, 4)` bzw. 0) mit τ 0,15 s (Anlauf) / 0,22 s (Auslauf),
Einrasten bei |Δ| < 0,01; jede Nabe dreht mit `CassetteGeometry.degreesPerSecond(radius, motor)` =
47,6 mm/s · motor / r · 180/π (voller Wickel ≈ 126 °/s, leerer ≈ 317 °/s) **gegen den Uhrzeigersinn**
(Winkel nimmt ab). Startwinkel links 0°, rechts 37°. Schleife endet, wenn alles steht.

Platzhalter bis zur fertigen Grafik: keiner (das leere Fach ist sichtbar), Einblenden 380 ms.

### 4.4 Etikett (live, über Ebene 7)

* **Cover**: linke obere Ecke (Int(X(4,6 + 1,3)), Int(X(3,6 + 1,0))), Kantenlänge
  `coverPx = Int((15,4 − 3,6 − 2,8)·k)`; `ArtworkBox` mit Eckenradius 2 pt, Ersatz-Symbol 55 %; beim
  Titelwechsel Überblendung **320 ms**; beim Laden neutrale Fläche.
* **Text**: links `textLeft = X(5,9) + coverPx + 2,2·k`, oben Int(X(3,6 + 1,2)), Breite
  `X(95,8 − 9) − textLeft`:
  * Titel: Inter SemiBold, Größe 2,7·k px, Zeilenhöhe 3,4·k, Farbe 0xFF2A2125, 1 Zeile, Auslassung;
  * Interpret: Inter Regular 2,1·k px, Zeilenhöhe 2,8·k, Farbe 0xFF6E6064, 1 Zeile („Unbekannter
    Interpret“).
  * Text wechselt beim Titelwechsel sofort (ohne Überblendung).
* **„A“** (Seite): Inter Bold 4,4·k px, Farbe 0xFFD4566F, Ecke (Int(X(95,8 − 6,6)), Int(X(3,6 + 1,6))).

### 4.5 Statusleiste (`DeckStatus`)

Zeile, volle Breite, Höhe 46, Eckenradius 14, Grund senkrechter Verlauf 0xFF0D0B0C → 0xFF171314, Rand
1 pt senkrechter Verlauf Schwarz α 0,6 → Weiß α 0,08, horizontaler Innenabstand 14, vertikal zentriert.
`warm = 0xFFFF9DB2`.
1. **Zählwerk**: `Formatting.duration(position)` (m:ss bzw. h:mm:ss), Inter SemiBold 20 sp/22 sp,
   gleich breite Ziffern, Farbe warm; dahinter Rechteck mit radialem Verlauf warm α 0,10 →
   transparent (Mitte des Textfelds, Radius 0,8·Textbreite). Aktualisierung wie die Position (250 ms).
2. 14 Abstand.
3. Spalte (3 Abstand): Leuchte „PLAY“ (an bei `isPlaying`, Farbe warm), Leuchte „PAUSE“ (an bei
   `hasMedia && !isPlaying`, Farbe 0xFFF3B37A). Leuchte: Punkt 6 pt rund, Farbe α (0,18 + 0,82·g), darüber
   (auf den Punkt beschnitten) Farbe α 0,35·g; 5 Abstand; Text `sectionLabel` 8,5 sp / 10 sp, Weiß
   α (0,35 + 0,45·g). `g` animiert `tween(260)` 0↔1.
4. 14 Abstand.
5. Rest (füllt, volle Höhe): mit Visualisierung **Pegelanzeigen** (`VuMeters`, volle Breite, Höhe 22,
   Kapitel 6) – sonst rechtsbündig „−“ + Restzeit `Formatting.duration(max(0, dauer − position))`, Stil
   `time`, Farbe 0xFFABA3A6.

### 4.6 Laufwerkstasten (`DECK_KEYS`)

Zeile, volle Breite, Höhe 62, Abstand 8; fünf Tasten (Gewicht 1 · 1 · **1,5** · 1 · 1): `fast_rewind`
(vorheriger), `replay_10`, `play`/`pause` (Symbol 30, mit Lampe), `forward_10`, `fast_forward`
(nächster; aus ohne nächsten Titel). Taste:
* volle Höhe, Eckenradius 14, Grund senkrechter Verlauf 0xFF3A3235 (α 1 − 0,25·p) → 0xFF1E191B, Rand
  1 pt senkrechter Verlauf Weiß α (0,16 − 0,08·p) → Schwarz α 0,5; beim Drücken um 2·p pt nach unten
  verschoben. `p` = gedrückt (`tween(90)`).
* Symbol mittig, Weiß α 0,92 (aus: 0,3), Größe 22 (Play 30).
* Lampe (nur Play/Pause, an bei `playing`): Kapsel 14 × 3 oben mittig (6 Abstand von oben),
  0xFFFF8FA6 α (0,25 + 0,75·l), `l` animiert `tween(260)`; unsichtbar wenn l = 0 und aus.

### 4.7 Sonstiges

Farben `CassetteColors`; keine Frequenzbalken unter dem Hero (Pegel in der Statusleiste). Rechnen der
Ebenen parallel: `back(W)`, `front(W)`, `pack(W)`, `hub(W)`. Bedienungshilfe: „Kassette: ‹Titel›, läuft“
bzw. „…, angehalten“.

---

## 5. Portable CD

### 5.1 Hintergrund

1. `AmbientBackground` der App (hell/dunkel).
2. Radialer Verlauf `palette.glow` (CoverPalette wie 3.1, Farbanimation 900 ms) α 0,22 (dunkel) /
   0,16 (hell) → transparent, Mitte (0,5·B, 0,30·H), Radius 0,85·B.
3. Radialer Verlauf Weiß α 0,05 (dunkel) / 0,30 (hell) → transparent, Mitte (0,2·B, 0,04·H), Radius B.

### 5.2 Größe und Lage

Im Hero-Quadrat zentriert: `W = clamp(CdGeometry.widthToFit(side_px, side_px), 64, 1440)` px
(Seitenverhältnis 152:170 → W ≈ 0,894·side), Höhe `CdGeometry.heightFor(W)`. `k = CdGeometry.pxPerMm(W)`
(= W/152). CD-Mitte `CdGeometry.discCenterPx(W)` = (76·k, 75·k). Gerätemaße `CdGeometry` (mm, Ursprung
oben links am Gehäuse, Rand 6 mm): Gehäuse 140 × 158, Radius 30; Fenster r 63,6; Ring bis 65,8; Anzeige
Mitte (70; 145,6), 68 × 14,4; Leuchte (23,5; 145,6).

### 5.3 Ebenen

| # | Ebene | Quelle | Lage | dreht? |
|---|---|---|---|---|
| 0 | Platzhalter (bis fertig) | live: abgerundetes Rechteck 0xFF242022 bei (6k, 6k), 140k × 158k, Radius 30k; Kreis 0xFF0E0C0D, Radius 63,6k um die CD-Mitte | – | nein |
| 1 | Gehäuse (Graphit, rosé Fensterring, Schacht, Anzeigefenster, Scharnier, Schieber, Schatten) | `CdRenderer.body(W)` | (0,0) | nein |
| 2 | CD mit Laufwerksteller und Spindel | `CdRenderer.disc(W)` (Kante `discSizePx`) | Ecke (round(cx − d/2), round(cy − d/2)) | **ja**, um ihre Mitte |
| 3 | Label (Cover-Ring) | 5.4, Kante `labelSizePx(W)` = Int(82·k), mittig auf Ebene 2 | CD-Mitte | **ja** (mit 2) |
| 4 | Reflexe, Regenbogen, Deckelscheibe | `CdRenderer.overlay(W)` (Kante `overlaySizePx`) | Ecke (round(cx − o/2), round(cy − o/2)) | **nein** |
| 5 | Anzeige (LCD) | live, 5.5 | 5.5 | nein |
| 6 | Betriebsleuchte | live, 5.5 | – | nein |

Rechnen **nacheinander** (je Ebene auf allen Kernen): `body`, `disc`, `overlay`,
`fallbackLabel(labelSizePx(W))`. Einblenden `tween(380)`.

### 5.4 Label (dreht mit)

Überblendung **380 ms**, Schlüssel = (Titel-ID, Cover-Bild, lädt, Titel, Interpret):
* **lädt & kein Bild** → „schlichter Druck“: Ring Farbe 0xFF2A2527, Mittelradius (r + i)/2, Breite r − i
  (r = Labelradius, i = r·`CdGeometry.LABEL_HOLE_FRACTION` ≈ 0,2866·r).
* **Cover** → `CoverLabel.cdRing(coverRaster, size: labelPx)` (Ring, Mitte frei, geglättet); bis fertig
  bzw. bei Fehler: schlichter Druck (nie ein volles Quadrat – Loch, klarer Ring und Spindel bleiben frei).
* **kein Cover** → `CdRenderer.fallbackLabel(labelPx)` + Text (dreht mit): Spalte unten mittig, unterer
  Innenabstand 15 % der Labelbreite, Breite 60 %; `base = clamp(labelBreite_pt · 0,062, 6, 15)`;
  Titel Inter SemiBold `base`, Zeilenhöhe 1,15·base, 0xFF2C2428, zentriert, 1 Zeile;
  Interpret Inter Medium 0,78·base, Zeilenhöhe 0,95·base, 0xFF6A5E62, 1 Zeile.

### 5.5 Anzeige (LCD) und Leuchte

Fläche: linke obere Ecke (round((70 − 34 + 6)·k), round((145,6 − 7,2 + 6)·k)) = (round(42k),
round(144,4k)), Größe 68k × 14,4k. Innerhalb `mm(v) = v·k`. Farben: `LIT = 0xFFFFB6C6`,
`GHOST = LIT α 0,075`.
* `bl` (Hinterleuchtung) animiert `tween(400)` → 1 bei `hasMedia`, sonst 0,4. `lit = LIT α (0,35 + 0,65·bl)`.
* Grund: abgerundetes Rechteck (ganze Fläche, Radius mm(2,9)) mit radialem Verlauf `LIT α 0,10·bl` →
  `LIT α 0,03·bl`, Mitte (0,5·w, 0,45·h), Radius 0,6·w.
* `play = playWhenReady && !ended && hasMedia` („Wiedergabe gewünscht“; flackert beim Puffern nicht).
* ▶ Dreieck (4,2; 4,9) – (8,0; 7,2) – (4,2; 9,5) mm: `lit` wenn `hasMedia && play`, sonst GHOST.
* ❚❚ zwei abgerundete Rechtecke bei (9,6; 4,9) und (11,6; 4,9), je 1,2 × 4,6 mm, Radius 0,3 mm: `lit`
  wenn `hasMedia && !play`, sonst GHOST.
* „TRACK“ bei (16,2; 1,6) mm (linke obere Ecke der Textzeile), Inter SemiBold, Größe mm(1,75),
  Laufweite mm(0,12), Farbe `lit` mit α × 0,75.
* **Ziffern** (Sieben-Segment): Feld `dw = 3,7`, `dh = 7,0`, Strich `t = 0,78`, Teilung `pitch = 4,7`,
  Oberkante `dy = 4,9` (alles mm).
  * Titelnummer `CdDisplay.trackText(currentIndex + 1)` („03“, „120“, „--“ ohne Titel, „----“ ab
    10000): Ziffer i bei x = 16,2 + i·pitch·ts, y = dy + dh·(1 − ts), Größe dw·ts × dh·ts, Strich t·ts;
    `ts = 0,74` bei ≥ 4 Zeichen, sonst 1 (unten bündig).
  * Zeit `CdDisplay.timeText(position)` → (Minuten, Sekunden), z. B. (" 1", "23"), ("10", "00"), ("100",
    "05"). Sekunden ab `sx = 55 − 2·pitch + (pitch − dw)` = 46,6 mm, Ziffer i bei sx + i·pitch.
    Doppelpunkt: x = sx − 1,55 = 45,05 mm, zwei Kreise Radius 0,42 mm bei y = dy + 0,32·dh und
    dy + 0,70·dh, Farbe `lit` wenn `hasMedia`, sonst GHOST (**blinkt nicht**). Minuten ab
    `mx = (sx − 1,55) − 1,55 − n·pitch + (pitch − dw)` (n = Zeichenzahl), Ziffer i bei mx + i·pitch.
  * Ziffer zeichnen: `CdDisplay.segmentRects(w, h, t)` liefert 7 Rechtecke (a–g); Eckenradius 0,45·t;
    Schrägstellung: jedes Segment um `0,10·w·(1 − (y + h_seg/2)/h)` nach rechts verschoben;
    Farbe `lit`, wenn Bit i in `CdDisplay.segments(ch)` gesetzt, sonst GHOST (Leerzeichen = nur GHOST).
* „RPT“ bzw. „RPT 1“ (Wiederholen: Titel) bei (57,4; 3,0) mm, „SHUF“ bei (57,4; 8,2) mm, Stil wie
  „TRACK“; Farbe `lit` wenn an (Wiederholen ≠ aus bzw. Zufall an), sonst LIT α 0,16.
* Es blinkt nichts; alle Werte folgen sofort dem Zustand (Zeit im 250-ms-Takt der Position).

**Leuchte** (Farbe 0xFFFF7D98): Mitte ((23,5 + 6)·k, (145,6 + 6)·k), `r = 1,15·k`; `glow` `tween(400)` →
1 bei `play`, 0,3 bei `hasMedia`, sonst 0,08. Hof Kreis 4,2·r radialer Verlauf α 0,5·glow →
transparent; Punkt Radius r α (0,25 + 0,75·glow); Glanz Weiß α 0,35·glow, Radius 0,4·r bei
(cx − 0,25·r, cy − 0,3·r).

### 5.6 CD-Tasten (`CD_BUTTONS`)

Zeile, volle Breite, Höhe 76, `SpaceEvenly`, vertikal zentriert:

| Taste | Ø | Symbol | Besonderheit |
|---|---|---|---|
| `replay_10` | 48 | 21 | |
| `fast_rewind` (vorheriger) | 56 | 26 | |
| `play`/`pause` | 72 | 34 | rosé Ring, leuchtet bei `playing` |
| `fast_forward` (nächster) | 56 | 26 | aus ohne nächsten Titel |
| `forward_10` | 48 | 21 | |

Taste (r = Ø/2, `p` gedrückt `tween(90)`, Skalierung 1 − 0,04·p; Leuchten `g` `tween(300)`); gezeichnet
**unbeschnitten** hinter dem Symbol:
1. Schatten: Kreis Schwarz α 0,28, Radius 1,02·r, Mitte um 0,07·r nach unten.
2. Nur Play mit g > 0: Kreis 1,5·r, radialer Verlauf 0xFFE88AA0 α 0,32·g → transparent.
3. Ring: Kreis r, linearer Verlauf (0,0)→(Ø,Ø): Play 0xFFF2B4C2 → 0xFFB45C72 → 0xFFE59AAC; sonst
   0xFF5A5457 → 0xFF1A1718.
4. Fläche: Kreis `f = r·(Play ? 0,86 : 0,9)`, radialer Verlauf Mitte (cx − 0,35f, cy − 0,45f), Radius
   1,7f: 0xFF4A4447 (α 1 − 0,2·p) → 0xFF242022 → 0xFF1B1819.
5. Kreislinie Weiß α (0,10 − 0,05·p), Radius f, 1 pt.
6. Symbol Weiß α 0,93 (aus: 0,3). Klickfläche = Kreis.

### 5.7 Drehung

`MLRender.CdSpin`: Ziel `targetSpeed(playing: isPlaying || (playWhenReady && buffering), speedFactor: speed)`
= **216 °/s** · clamp(Tempo, 0,5, 2) (36 U/min); je Bild
`v = CdSpin.velocity(current: v, target:, dt:)` (τ 0,14 s Anlauf, 0,32 s Auslauf, Einrasten < 0,5 °/s),
`angle = CdSpin.angle(current: angle, velocity: v, dt:)` (0…360, im Uhrzeigersinn). Unabhängig von der
Position (Spulen ändert nur die Anzeige). Bedienungshilfe: „CD-Player: ‹Titel›, keine Wiedergabe“ /
„…, CD dreht sich“ / „…, angehalten“.

---

## 6. Klangvisualisierung

* Aktiv nur wenn: Einstellung „Klangvisualisierung“ an **und** Player sichtbar **und** keine reduzierte
  Bewegung (Mac: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`). Nur dann analysiert die
  Audio-Kette (LevelAnalyzer: 16 log. Bänder 50 Hz–14 kHz + Pegel L/R, je 0…1 über −60…0 dBFS, mit
  Latenzausgleich). Inaktiv → keine Balken/Pegel (Cassette zeigt Restzeit).
* Takt: höchstens 30 Aktualisierungen/s (≥ 33 ms). Glättung `MLRender.VisualizerSmoothing.step(raw:)`
  (Bänder: steigen mit Faktor 0,55, fallen mit 0,14; Pegel 0,5 / 0,12; ohne frische Werte → Richtung 0).
  Nicht spielend und Energie < 0,01 → Schleife beenden.
* **SpectrumBars** (Breite w, Höhe h, Farbe = `accent` des Designs): n = 16, `gap = 0,012·w`,
  `bw = (w − 15·gap)/16`, Eckenradius bw/2. Für Band i (Wert v): Grundpunkt (x = i·(bw + gap),
  y = h − bw, bw × bw) Farbe α 0,18; Balken Höhe `max(h·(0,06 + 0,94·v²), bw)`, unten bündig, Farbe
  α (0,35 + 0,55·v).
* **VuMeters** (Cassette, w × 22): 14 Segmente, Zeilenhöhe `rh = 0,36·h`, `gap = 0,012·w`,
  `sw = (w − 13·gap)/14`, Eckenradius rh/3; Zeile links bei y = 0, rechts bei y = h − rh;
  `lit = Int(Wert·14)`; Segment s: Farbe 0xFFF3B37A für s ≥ 11, sonst warm (0xFFFF9DB2); α 0,9 wenn
  s < lit, sonst 0,12.

---

## 7. Mini-Player

* Schwebende Glaskapsel direkt über der Navigationsleiste (seitlich 12 Abstand zum Fensterrand, 10 Abstand zur Leiste darunter; die Leiste hat 10 Abstand zum unteren Rand), Höhe 60
  (Mac-Token `miniPlayerHeight` = 62), Eckenradius 30, `GlassSurface` **mit** Hintergrundunschärfe der
  Bibliothek, `strong`, erhöht (Schatten 18 dp, ohne Glas 6 dp, Farbe glassShadow).
* Erscheinen: Einblenden + von halber Höhe hochgleiten (280 ms); Verschwinden 160 ms.
* Inhalt (Zeile, Innenabstand links 10, rechts 6, vertikal zentriert): Cover 42 × 42, Eckenradius 7
  (Überblendung 220 ms, beim Laden neutral) · 12 · Spalte (füllt; Titelwechsel `fadeIn 220`/`fadeOut 160`):
  Titel `bodyLarge` Medium textPrimary 1 Zeile, Interpret `bodySmall` textSecondary 1 Zeile ·
  `IconTap` Play/Pause (Symbol 30, Fläche 46; zeigt `playing`) · `IconTap` `fast_forward` (26/44, aus ohne
  nächsten Titel).
* Fortschritt: Linie unten in der Kapsel, horizontal 22 eingerückt, Höhe 2, Radius 1: Spur
  textPrimary α 0,08, Füllung `accent` über `progress · Breite` (Position alle **500 ms**).
* Klick auf die Kapsel öffnet den Player; Ziehen nach oben > 24 pt ebenfalls.

---

## 8. Blätter (Sheets)

### 8.1 Gemeinsamer Rahmen

Unteres Blatt, immer ganz geöffnet, Grund `backgroundGrouped`, Inhalt textPrimary, Abdunklung `scrim`,
obere Ecken 30, Griff 32 × 4 (Farbe textTertiary α 0,45, 22 Abstand oben/unten). Farben = Farbsatz des
aktuellen Player-Designs. Inhalt scrollbar, Innenabstand links/rechts 20, unten 22; Kopf: Titel
`headlineSmall` + rechts optionales Element; 14 Abstand. `SheetCard` = Fläche `surface`, Radius 18,
Innenabstand 16. Hinweise = `bodySmall`, textSecondary. **Mac-Hinweis:** als Fenster-Sheet oder
eingeblendete Tafel unten; Inhalt und Maße bleiben.

### 8.2 Equalizer

* Kopf rechts: Schalter „Equalizer ein/aus“ (Schalterfarben: an = accent mit weißem Knopf; aus =
  textPrimary α 0,12).
* Zeile (waagerecht scrollbar, Abstand 8) mit `ChoiceChip` je Voreinstellung: Neutral, Bass Boost, Rock,
  Pop, Klassik, Jazz, Gesang, Elektronisch (gewählt = EQ an && aktive Voreinstellung); ohne passende
  Voreinstellung zusätzlich deaktiviert „Eigene Einstellung“ (gewählt = EQ an).
* 14 · **Bass**-Karte: Zeile „Bass“ (`titleMedium`) · Wert („0 dB“ bzw. `Formatting.decibel`, Stil time
  15 sp, accentText wenn ≠ 0) · bei ≠ 0 `IconTap clear` (16/36) „auf 0 dB“. `MusicSlider` −12…+12,
  Markierung 0, **bipolar**, aktiv `accent`; Ziehen: |v| < 0,6 → 0, sonst 0,5-dB-Schritte. Darunter
  „weniger“ … „mehr“. Wenn begrenzt: „Wirksam: ‹x dB› – der Equalizer hebt die Bässe bereits an
  (zusammen höchstens +12 dB).“ sonst „Tiefen unter ≈ 150 Hz · Mitten und Höhen bleiben unverändert.“
* 12 · Karte mit 10 Bändern (31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k), gleich breite Spalten: Wert
  (`decibel` ohne „ dB“, Stil time, textTertiary bei 0, sonst accentText, Schrift 8–12 sp passend) ·
  senkrechter Regler Höhe 188 · Bandname (`labelSmall`, textSecondary, 8–11 sp). Darunter (6) „Bass“ –
  „Mitten“ – „Höhen“ verteilt.
  *Senkrechter Regler*: Innenabstand oben/unten 12; `y(db) = unten − (db + 12)/24·(unten − oben)`;
  α = 1 (aus 0,38): Schiene textPrimary α 0,10·α, 4 pt, runde Enden; 0-dB-Strich textPrimary α 0,25·α,
  ±8 pt, 1 pt; Füllung von 0 dB bis Wert `accent`, 4 pt rund; Knopf: Schatten Schwarz α 0,14·α r 10,5
  (+1 pt y), Weiß (aus α 0,7) r 9,5, Punkt `accent` r 3. Klick = Wert an der Stelle (0,5-dB-Raster),
  Doppelklick = 0 dB, senkrechtes Ziehen ändert (nur bei Wertänderung melden). Nur bei EQ an bedienbar.
* 12 · Karte „Automatische Aussteuerung“ (`bodyLarge`) + Hinweis „Senkt den Pegel bei angehobenen
  Bändern etwas ab, damit nichts verzerrt.“ + Schalter.
* 12 · Zeile: Hinweis „Wirkt nur auf die Musik dieser App · ±12 dB je Band.“ (füllt) + `PillButton`
  „Zurücksetzen“ (Stil PLAIN) → Neutral.
* Jede Änderung wirkt sofort und wird gespeichert.

### 8.3 Tonhöhe

* Kopf rechts: `PillButton` „Original“ (TONAL; aus, wenn bereits 0).
* `SegmentedControl` „Tonhöhe“ (Symbol `music_note`) | „Schallplatte“ (Symbol `vinyl`); darunter (6)
  Beschreibung des Modus („Tonhöhe ändern, Tempo bleibt erhalten“ / „Tonhöhe und Tempo ändern sich
  gemeinsam“).
* 14 · Karte: großer Wert `Formatting.semitones` (`displaySmall`, accentText wenn ≠ 0, zentriert);
  darunter `bodyMedium` textSecondary: KEY → „Tonhöhe ‹Faktor› · Tempo unverändert“, VARISPEED →
  „Tonhöhe und Tempo ‹Faktor› (‹Prozent›)“ (Faktor = 2^(HT/12), `Formatting.factor`); 10 · Zeile:
  `GlassIconButton arrow_downward` 38/18 (−1 HT, aus bei −12) · `MusicSlider` −12…+12 (Markierung 0,
  bipolar, accent, Innenabstand 10; Ziehen zeigt nur an (0,1-Raster), übernommen wird beim Loslassen) ·
  `GlassIconButton arrow_upward` (+1, aus bei +12). Darunter „−12 · 0 · +12“ (Innenabstand 48).
* Nur Modus „Schallplatte“: 14 · „Plattenspieler-Drehzahl“ (`titleSmall`) · Chips „33⅓ → 45 U/min“
  (+5,2 HT) und „45 → 33⅓ U/min“ (−5,2 HT), gewählt bei |Δ| < 0,06.
* 14 · Hinweistext je Modus (siehe Android-Text in `PlayerSheets.kt`; Inhalt: KEY = Phase-Vocoder mit
  Sinc-Resampling, leichtes Vorecho möglich; VARISPEED = reines Resampling; beide: „Änderungen sind nach
  etwa einer Viertelsekunde hörbar; der Titel startet nicht neu. Die Einstellung gilt bis zum
  Zurücksetzen bzw. bis zum Neustart der App.“).
* Hinweis: Im Modus „Schallplatte“ ändert sich `speed` → Plattenteller, Naben und CD drehen schneller.

### 8.4 Sleep-Timer

* Läuft „Ende des Titels“: Karte „Am Ende des Titels“ (`titleLarge`, accentText) + Hinweis „Die
  Wiedergabe hält nach dem laufenden Titel an.“ + `PillButton` „Beenden“ (`clear`) → 16 · „Stattdessen“
  (`titleSmall`).
* Läuft mit Zeit: Karte mit Restzeit `Formatting.countdown` (`displayMedium`, gleich breite Ziffern,
  accentText, zentriert, sekündlich) + Hinweis „Danach wird die Musik sanft ausgeblendet und angehalten.“
  + Zeile (Abstand 10) `PillButton` „+15 Minuten“ (`add`; neue Dauer = aufgerundete Restminuten + 15,
  max. 720) und „Beenden“ → 16 · „Neu stellen“.
* Sonst: Hinweis „Die Wiedergabe stoppt nach der gewählten Zeit – auch bei ausgeschaltetem Display.“
* 10 · Chips (Umbruch, Abstand 8): „15 Min.“, „30 Min.“, „45 Min.“, „60 Min.“, „90 Min.“, „Ende des
  Titels“ (gewählt wenn aktiv).
* 14 · Zeile: Textfeld „Eigene Dauer (Minuten)“ (nur Ziffern, max. 3; Hilfe „1 bis 720 Minuten“; Fehler
  bei ungültig; Radius 12) + `PillButton` „Starten“ (FILLED, nur gültig 1…720).

### 8.5 Wiedergabeliste

Höhe 86 % des Fensters. „Wiedergabeliste“ (`headlineSmall`); Info `bodySmall` textSecondary (max. 2
Zeilen): Quelle · „n Titel“ · „Zufall“ · „Quelle wiederholen“/„Titel wiederholen“, mit „ · “ verbunden;
12. Leer: „Keine Titel in der Warteschlange.“ Liste in tatsächlicher Abspielreihenfolge ab dem aktuellen
Titel: Zeile (Radius 12, Innenabstand 8/7): Cover 42 (Radius 7; beim aktuellen darüber
`NowPlayingBars` 18 pt in `onAccent`) · 12 · Titel (`bodyLarge`, aktuell SemiBold accentText, sonst
Medium textPrimary) / Interpret (`bodySmall`, textSecondary) · Dauer (Stil duration, textTertiary) ·
`IconTap clear` (16/40) „Aus der Wiedergabeliste nehmen“ (beim aktuellen 40 Platzhalter). Aktuelle
Zeile Grund accentSoft, nicht klickbar; vor dem zweiten Eintrag Überschrift „ALS NÄCHSTES“
(`sectionLabel`, textSecondary, oben 14, unten 6). Klick = zu diesem Titel springen.

### 8.6 Songinformationen

Kopf (Innenabstand 20): Cover 64 (Radius 10, Schatten 10 dp) · 14 · Titel `titleMedium` (2 Zeilen) /
Interpret `bodyMedium` accentText. 14 · `SegmentedControl` „Details“ | „Songtext“; beim Laden schmaler
Ladebalken (accent). *Details*: Gruppen „MUSIK“, „WIEDERGABE“, „DATEI“ (Überschrift `sectionLabel`,
Abstand oben 16 / unten 6) als Karten (surface, Radius 18, Innenabstand horizontal 14), Zeilen
(vertikal 10): Bezeichnung `bodyMedium` textSecondary Breite 124 · 12 · Wert `bodyMedium` (auswählbar);
Trenner hairline 0,7 außer nach der letzten Zeile; nur vorhandene Angaben (Liste wie Android
`SongInfoSheet.buildGroups`). *Songtext*: eingebetteter Text (`bodyLarge`, Zeilenhöhe 1,5×,
auswählbar), sonst Erklärung „In dieser Datei ist kein Songtext gespeichert …“. Max. Höhe 620.

### 8.7 Player-Design

Titel „Player-Design“ (`headlineSmall`) · 4 · „Gleiche Bedienung in allen Designs – der Wechsel unterbricht
die Wiedergabe nicht.“ (`bodySmall`) · 14 · **Auswahl** · 14 · Karte „Klangvisualisierung“ (`bodyLarge`) +
Hinweis „Dezente Frequenzbalken bzw. Pegelanzeigen. Nur aktiv, solange der Player sichtbar ist; aus bei
„Animationen entfernen“.“ + Schalter.

**Auswahl** (`PlayerThemePicker`, auch in den Einstellungen): 2 Spalten, Abstand 10 (Zeilen und
Spalten), Reihenfolge Vinyl Studio, Classic Music, Cassette Studio, Portable CD. Kachel (Radius 18
beim Klicken, Innenabstand 4): Vorschau (volle Breite, Seitenverhältnis 0,8, Radius 16, Rand 2,5 pt
accent wenn gewählt, sonst 1 pt hairline) · 8 · Zeile: bei Auswahl `check` 15 accentText + 3 · Name
(`labelLarge`, SemiBold + accentText wenn gewählt, sonst Medium textPrimary, 1 Zeile). Unter dem Raster
die Beschreibung des gewählten Designs (`bodySmall`, textSecondary):
* Vinyl Studio – „Realistischer Plattenspieler mit Cover-Label und Tonarm – die charakteristische Hauptansicht.“
* Classic Music – „Großes Albumcover, ruhiger Hintergrund in den Farben des Covers, klare Typografie.“
* Cassette Studio – „Getöntes Kassettengehäuse mit sichtbaren Wickeln, Bandzählwerk und Statusanzeigen.“
* Portable CD – „Tragbarer CD-Player im Stil der 2000er: drehende CD mit Cover-Label unter getöntem Deckel, Anzeige mit Titelnummer und Laufzeit.“

**Vorschau** (`PlayerThemePreview`, ruhend, mit aktuellem Titel bzw. Beispiel „Musikbibliothek“ /
„Vorschau“; Farben des jeweiligen Designs): Grund Vinyl = dunkel: Verlauf 0xFF2B2427 → 0xFF141112,
hell: `AmbientBackground`; Classic = 3.1; Cassette = 4.1; CD = 5.1. Spalte (Innenabstand 10, zentriert):
quadratisches Mittelstück (so groß wie Platz bleibt) · 8 · angedeuteter Fortschritt (78 % breit, 3 hoch,
Kapsel, textPrimary α 0,18, 35 % `accent`) · 8 · Symbole `fast_rewind` 13, `play` 18, `fast_forward` 13
(Abstand 10, textPrimary). Mittelstück: Vinyl = Plattenspieler `still` (Pause → Arm angehoben, Fortschritt
0,3); Classic = Cover 86 %, Radius 8, Schatten 10 dp; Cassette = Kassettenfach ohne Statusleiste,
`still`, Fortschritt 0,3; CD = CD-Player `still`, Position 1:23, Titel 3, ohne Wiederholen/Zufall.
Vorschauen nutzen denselben Ebenen-Speicher (kleine Größen).

---

## Anhang A – Bausteine (Android-Werte; Mac-Entsprechungen in `Design/Controls.swift`, `Design/Glass.swift`)

**A.1 MusicSlider** – Höhe 30, Spur 5 hoch (beim Ziehen 9, Feder `standardSpring`), runde Enden;
inaktiv textPrimary α 0,14, aktiv textPrimary α 0,85; mit Markierung (nicht bipolar): bis zur Markierung
aktiv, darüber `accent` (überlappend ab Markierung − Spurhöhe), Markierungsstrich textPrimary
α min(3·0,14, 0,6) von 3 pt über bis 3 pt unter der Spur, 1,2 pt; bipolar: Füllung zwischen Markierung und
Wert (wenn > 0,5 px) + Knopf (Schatten Schwarz α 0,12 r 11 (+1 y), Weiß r 10). Kurz klicken springt an
die Stelle (melden + „fertig“), waagerecht ziehen ändert fortlaufend, beim Loslassen „fertig“. Aus: α 0,4.

**A.2 IconTap** – Kreisfläche `touch`, Symbol `iconSize`, beim Drücken Symbol ×0,86 (standardSpring),
aus: Farbe α 0,32. **GlassIconButton** – `GlassSurface` Kreis, Druck ×0,92; aktiv: Tönung accentSoft
über glassTintStrong, Symbol accentText.

**A.3 GlassSurface** – Füllung (eigene Tönung | ohne Glas `surface` | `strong` glassTintStrong |
glassTint); bei Glas zusätzlich senkrechter Verlauf glassSheen (0) → transparent (0,5) und transparent
(0,6) → Schwarz α 0,10 dunkel / 0,025 hell (1); Rand 0,8 pt linearer Verlauf glassEdgeLight →
glassEdgeDark → glassEdgeLight α × 0,45 (ohne Glas 0,6 pt hairline). Hintergrundunschärfe (30 pt,
Sättigung 1,25 dunkel / 1,6 hell) **nur** mit Quelle dahinter (Mini-Player, Kopfleisten) – im
Vollbild-Player nicht.

**A.4 ChoiceChip** – Kapsel, min. Höhe 36, Innenabstand 14/8, `labelMedium`; gewählt accentSoft +
accentText; sonst dunkel Weiß α 0,07 bzw. hell `surface` mit Rand hairline 0,8; aus: textTertiary.
**PillButton** – Radius 12, min. Höhe 44, Innenabstand 18/11, Symbol 20 + 7, `labelLarge`; FILLED
accent/onAccent, TONAL Weiß α 0,09 (dunkel) bzw. surfaceMuted + accentText, PLAIN transparent +
accentText; Druck ×0,96. **SegmentedControl** – Höhe 38, Kapsel, Grund Weiß α 0,08 (dunkel) bzw.
textPrimary α 0,06, Innenabstand 3, gleitende Markierung (standardSpring; Weiß α 0,16 bzw. surface mit
3-dp-Schatten), Text `labelMedium` textPrimary aktiv / textSecondary.

**A.5 Symbole** – Material Symbols Rounded (gefüllt), in der App über `Icons` (`Design/Icons.swift`):
`play`, `pause`, `fast_rewind` (= vorheriger), `fast_forward` (= nächster), `replay_10`, `forward_10`,
`shuffle`, `repeat`, `repeat_one`, `tune`, `pitch`, `bedtime`, `bedtime_fill`, `queue_music`, `info`,
`expand_more`, `more_vert`, `volume_down`, `volume_off`, `favorite`, `favorite_border`, `playlist_add`,
`album`, `vinyl`, `graphic_eq`, `clear`, `add`, `arrow_upward`, `arrow_downward`, `music_note`, `check`.

---

## Anhang B – MLRender-API (Swift)

```swift
// Bild
public struct RasterImage: Equatable, Sendable {
    public let width: Int; public let height: Int; public var pixels: [UInt32]   // 0xAARRGGBB, nicht vormultipliziert
    public init(width: Int, height: Int)
    public init(width: Int, height: Int, pixels: [UInt32])
    public subscript(x: Int, y: Int) -> UInt32 { get set }
    public func alpha(x: Int, y: Int) -> Int
    public func premultipliedPixels() -> [UInt32]
}
public struct ArmRaster: Sendable { public let arm, shadow: RasterImage; public let pivotX, pivotY: Float }

// Plattenspieler
public enum TurntableGeometry {          // Konstanten wie Kotlin: CENTER_X, CENTER_Y, RECORD_RADIUS, PLATTER_FACTOR,
                                         // LABEL_FACTOR, GROOVE_OUTER/INNER, STYLUS_START/END, PIVOT_X/Y, TUBE_LENGTH,
                                         // HEAD_LENGTH, HEADSHELL_BEND_DEG, REST_ANGLE_DEG, REST_POST_DISTANCE,
                                         // ARM_BACK, ARM_FRONT, ARM_HALF_HEIGHT, SPEED_BUTTONS, SPEED_BUTTON_RADIUS
    public static var bendRad: Float; public static var stylusX: Float; public static var stylusY: Float
    public static var effectiveLength: Float
    public static func armAngleForRadius(_ radiusFactor: Float) -> Float
    public static func armAngleForProgress(_ progress: Float) -> Float
}
public enum VinylRenderer {
    public static func record(_ size: Int) -> RasterImage        // size = recordSizePx(S)
    public static func sheen(_ size: Int) -> RasterImage         // size = recordSizePx(S)
    public static func plinth(_ size: Int) -> RasterImage        // size = S
    public static func tonearm(_ s: Int) -> ArmRaster            // s = S
    public static func fallbackLabel(_ size: Int) -> RasterImage // size = labelSizePx(S)
    public static func recordSizePx(_ size: Int) -> Int
    public static func labelSizePx(_ size: Int) -> Int
}

// Kassette
public enum CassetteGeometry {           // WIDTH_MM, HEIGHT_MM, ASPECT, HUB_LEFT_X, HUB_RIGHT_X, HUB_Y, CORE_RADIUS,
                                         // FULL_RADIUS, HUB_RADIUS, LABEL_LEFT/TOP/RIGHT/BOTTOM, ROLLER_LEFT_X,
                                         // ROLLER_RIGHT_X, ROLLER_Y, ROLLER_RADIUS, TAPE_Y, TAPE_SPEED_MM_S
    public static func packRadii(_ progress: Float) -> (left: Float, right: Float)
    public static func degreesPerSecond(_ radiusMm: Float, speedFactor: Float = 1) -> Float
    public static func tangentPoint(cx: Float, cy: Float, r: Float, fromX: Float, fromY: Float, left: Bool) -> (x: Float, y: Float)
}
public enum CassetteRenderer {
    public static let MARGIN_MM: Float                           // 4
    public static func pxPerMm(_ widthPx: Int) -> Float
    public static func heightFor(_ widthPx: Int) -> Int
    public static func hubSizePx(_ widthPx: Int) -> Int
    public static func packSizePx(_ widthPx: Int) -> Int
    public static func back(_ widthPx: Int) -> RasterImage
    public static func pack(_ widthPx: Int) -> RasterImage
    public static func hub(_ widthPx: Int) -> RasterImage
    public static func front(_ widthPx: Int) -> RasterImage
}

// CD-Player
public enum CdGeometry {                 // DISC_RADIUS, HOLE_RADIUS, CLEAR_RADIUS, STACK_RING_RADIUS, LABEL_INNER,
                                         // LABEL_OUTER, DATA_END, MIRROR_END, SPINDLE_CAP, TURNTABLE_RADIUS, BODY_W,
                                         // BODY_H, BODY_RADIUS, DISC_CX, DISC_CY, WINDOW_RADIUS, RING_OUTER, LCD_CX,
                                         // LCD_CY, LCD_W, LCD_H, LED_X, LED_Y, MARGIN, TOTAL_W, TOTAL_H, ASPECT,
                                         // LIGHT_ANGLE, DEGREES_PER_SECOND, LABEL_HOLE_FRACTION
    public static func pxPerMm(_ widthPx: Int) -> Float
    public static func heightFor(_ widthPx: Int) -> Int
    public static func widthToFit(_ maxWidthPx: Int, _ maxHeightPx: Int) -> Int
    public static func discSizePx(_ widthPx: Int) -> Int
    public static func overlaySizePx(_ widthPx: Int) -> Int
    public static func labelSizePx(_ widthPx: Int) -> Int
    public static func discCenterPx(_ widthPx: Int) -> (x: Float, y: Float)
}
public enum CdSpin {
    public static let TAU_UP: Float, TAU_DOWN: Float             // 0.14, 0.32
    public static func targetSpeed(playing: Bool, speedFactor: Float) -> Float
    public static func velocity(current: Float, target: Float, dt: Float) -> Float
    public static func angle(current: Float, velocity: Float, dt: Float) -> Float
}
public enum CdRenderer {
    public static func body(_ widthPx: Int) -> RasterImage
    public static func disc(_ widthPx: Int) -> RasterImage
    public static func overlay(_ widthPx: Int) -> RasterImage
    public static func fallbackLabel(_ sizePx: Int) -> RasterImage
}
public enum CdDisplay {
    public static let A, B, C, D, E, F, G, ALL: Int
    public static func segments(_ ch: Character) -> Int
    public static func trackText(_ number: Int) -> String
    public static func timeText(_ positionMs: Int64) -> (minutes: String, seconds: String)
    public static func segmentRects(_ w: Float, _ h: Float, _ t: Float) -> [Float]   // 7 × (x, y, w, h)
}

// Cover → Label
public enum CoverLabel {
    public static func circular(_ cover: RasterImage, size: Int) -> RasterImage   // Plattenlabel
    public static func cdRing(_ cover: RasterImage, size: Int) -> RasterImage     // CD-Druck (Mitte frei)
    public static func squareCrop(_ cover: RasterImage, size: Int) -> RasterImage
    public static func scaled(_ image: RasterImage, width: Int, height: Int) -> RasterImage  // für CoverPalette (32×32)
}

// Bewegung
public struct CubicBezierEasing { public static let fastOutSlowIn; public func transform(_ x: Float) -> Float }
public struct TweenAnimation { init(from:to:duration:easing:); var value: Float; var isFinished: Bool; mutating func step(_ dt: Float) }
public struct SpringAnimation { init(from:to:stiffness:dampingRatio:visibilityThreshold:); var value; var isFinished; mutating func step(_:) }
public struct TurntableSpin {            // DEGREES_PER_SECOND_33 = 200, TAU_UP 0.18, TAU_DOWN 0.28
    public var angle: Float { get }; public var velocity: Float { get }
    public static func targetSpeed(playing: Bool, speed: Float) -> Float
    public mutating func step(target: Float, dt: Float) -> Bool    // false = steht, Schleife darf enden
    public mutating func stop()
}
public final class TonearmMotion {
    public init(target: Float, playing: Bool)
    public var progress: Float { get }; public var pauseLift: Float { get }; public var jumpLift: Float { get }
    public var lift: Float { get }; public var angleDegrees: Float { get }; public var isAnimating: Bool { get }
    public func setTarget(_ target: Float); public func setPlaying(_ playing: Bool)
    public func snap(to target: Float, playing: Bool); public func step(_ dt: Float)
}
public struct TonearmPose {              // angleDegrees, armOriginX/Y, shadowOriginX/Y, shadowAlpha, armScale
    public init(size: Float, arm: ArmRaster, progress: Float, lift: Float)
}
public struct CassetteReels {            // motor, angleLeft (Start 0), angleRight (Start 37)
    public static func targetMotor(playing: Bool, speed: Float) -> Float
    public mutating func step(target: Float, radiusLeftMm: Float, radiusRightMm: Float, dt: Float) -> Bool
    public mutating func stop()
}
public struct VisualizerSmoothing {      // bands[16], left, right
    public mutating func step(raw: [Float]?) -> Float               // raw = 16 Bänder + L + R; nil = keine frischen Daten
}
```

Alle Renderer sind reine, threadsichere Funktionen (intern parallel über
`DispatchQueue.concurrentPerform`); im Hintergrund aufrufen, Ergebnis zwischenspeichern (0.2).
