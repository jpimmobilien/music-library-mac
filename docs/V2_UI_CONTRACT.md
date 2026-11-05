# v2 – Gestaltung, Regeln und Schnittstellen für den App-Code

Gilt für alle, die in `Sources/MusicLibrary` arbeiten. Ergänzt `docs/V2_MLCORE_CONTRACT.md` (neue Typen in MLCore).

## 1. Gestaltung „Liquid Glass Studio“

- Grundlage bleibt die Android-App (Rosé-Akzent, Inter, eigene Symbole, schwebende Glas-Navigation oben,
  große Titel, schwebender Mini-Player unten). Kein iTunes/Apple-Music-Aufbau: keine Seitenleiste, keine
  grauen Tabellen, keine Rahmenlinien zwischen Bereichen.
- **Glas**: `glassSurface(...)` (Design/Glass.swift) – auf macOS 26 echtes Liquid Glass (`glassEffect`), auf
  macOS 13–15 Unschärfe (NSVisualEffectView) + Tönung + Glanzkante. **Nur für schwebende Elemente** verwenden
  (Navigation, Kopfleisten-Kapseln, Mini-Player, Popover, Seitenleiste, Player-Werkzeugleiste). Inhalte
  (Kacheln, Zeilen, Karten) bekommen **keine** Unschärfe, sondern leichte, halbtransparente Füllungen
  (`colors.surface.opacity(…)`, `colors.textPrimary.opacity(0.04…0.08)`), sonst ruckelt es auf älteren Macs.
- Farben/Schrift/Maße nur aus `MusicColors` (`@Environment(\.musicColors)`), `Typo`, `Spacing`, `Radius`,
  `Metrics`, `Motion` (Design/Theme.swift). Hell und Dunkel müssen beide stimmen (nie feste Weiß/Schwarz-Werte
  für Text oder Flächen, außer bewusst auf Bildern/Covern).
- Symbole: `Icon(Icons.xyz, size:, color:)` – alle Namen in Design/Icons.swift (v2-Ergänzungen u. a.
  `viewGrid, viewCompact, viewList, viewDetailed, viewCoverFlow, coverSize, filterAlt, filterOff, swapVert,
  arrowUp, arrowDown, palette, darkMode, lightMode, autoMode, keyboard, storage, privacy, stats, schedule,
  newReleases, event, category, save, addCircle, remove, waves, blur, animation, cleaning, restart, headphones,
  speaker, volumeMute, leaderboard, visibility, expandLess, unfoldMore, radio, equalizerBars, instantMix,
  dashboard, style, motion, timerOff, playlistCheck, pin, fullscreen, fullscreenExit, tag, manageSearch,
  pageInfo, linearScale, skipNext, skipPrevious`). **Keine SF Symbols** (`Image(systemName:)`).
- Animationen: `Motion.easeOut(…)`, `Motion.playerSpring`; immer auf `reduceMotion` bzw. die Einstellung
  `model.settings.animationLevel` achten (`.off` → keine, `.reduced` → nur Überblendungen).

## 2. Verbindliche Technik-Regeln (macOS 13 Ventura ist Mindestziel, Intel-Mac 2017)

1. **Keine API neuer als macOS 13 ohne `if #available`.** Nicht verwenden: `onChange(of:initial:)` mit 0/2
   Parametern (nur `.onChange(of: x) { neu in … }`), `scrollPosition`, `scrollTargetBehavior`,
   `contentMargins`, `ContentUnavailableView`, `@Observable`, `symbolEffect`, `onKeyPress`, `focusable(interactions:)`,
   `containerBackground`, `inspector`, `Color.mix`, `MainActor.assumeIsolated`, `openSettings`, `SettingsLink`,
   `TextField(axis:)` ist erlaubt (13), `Grid`/`ViewThatFits`/`Layout` sind erlaubt (13).
2. **Höchstens 10 direkte Elemente je ViewBuilder-Block** (unter macOS 13 Pflicht) – sonst `Group { }`.
3. **Kein `Menu` mit eigener Beschriftung** (bleibt unsichtbar). Stattdessen `GlassMenuButton` (Design/GlassMenu.swift):
   ```swift
   GlassMenuButton(icon: Icons.sort, help: "Sortieren") { menu in
       GlassMenuHeader(title: "Sortieren nach")
       GlassMenuItem(title: "Titel", checked: true) { …; menu.close() }
       GlassMenuDivider()
       GlassMenuDisclosure(title: "Mehr") { … }
   }
   GlassMenuButton(help: "…", label: { eigeneBeschriftung }) { menu in … }   // freie Beschriftung
   ```
   Eigene Popover-Inhalte in `GlassMenuPanel(width:) { … }` einbetten. `.contextMenu` (Rechtsklick) bleibt nativ.
4. Swift-5-Sprachmodus, gebaut mit Xcode 26 und Xcode 16.4. Keine Ternäre zwischen Closure und `nil` ohne
   Typangabe, lange arithmetische Ausdrücke in typisierte `let`s aufteilen, `switch` über MLCore-Enums
   vollständig (neue Fälle beachten!), `String(format:)` mit Int64 → `%lld`, Jahreszahlen nie über
   `Text("\(jahr)")` (Tausenderpunkt) – `Text(verbatim:)` bzw. `String(jahr)`.
5. **Performance** (die App muss mit 10.000 Titeln und 1.600 Alben flüssig sein, auch auf einem Intel-Mac 2017):
   - Große Sammlungen nur mit `LazyVStack`/`LazyVGrid`/`LazyHStack` in `ScrollView`; Zeilen/Kacheln als eigene,
     schlanke Views mit **Werte-Parametern** (Track/AlbumInfo + Bools), möglichst `Equatable` + `.equatable()`.
     In Zeilen **kein** `@EnvironmentObject` von `PlayerService`; „läuft gerade“/„spielt“ als Parameter übergeben.
   - Hochfrequente Werte (Position, Restzeit des Sleep-Timers, Pegel) **nur** über `player.clock`
     (`PlaybackClock`: `positionMs`, `durationMs`, `sleepRemainingMs`) in kleinen Unter-Views mit
     `@ObservedObject var clock: PlaybackClock` lesen – nie im Body großer Views.
   - Regler (EQ, Pitch, Lautstärke, Coverröße) während des Ziehens **nicht** bei jedem Schritt in
     `model.settings` schreiben: lokaler `@State`, live hörbar über `model.previewEffects(_:)` /
     `model.previewPitch(_:)` / `player.setLiveVolume(_:)`, gespeichert beim Loslassen
     (`MusicSlider(onEditingChanged:)`).
   - Keine `.blur(radius:)` auf großen, sich bewegenden Ebenen; keine Schatten mit großem Radius auf vielen
     Kacheln gleichzeitig (Schatten nur beim Überfahren/ausgewählt oder als vorberechnetes Bild).
   - Cover nur über `TrackArtwork`/`ArtworkBox`/`ArtworkStore` (Design/Artwork.swift) – lädt im Hintergrund,
     zwischengespeichert. Für Kacheln die passende `ArtworkSize` wählen.
   - `TimelineView(.animation)` nur, solange wirklich etwas läuft (z. B. Wiedergabe), und mit `paused:`.

## 3. Schnittstellen von `AppModel` (App/AppModel.swift) – vorhanden bzw. in v2 ergänzt

```swift
// Listen (gefiltert, gesucht, sortiert – im Hintergrund berechnet)
model.trackList, albumList, artistList, genreList, smartPlaylists, playlistList, favoriteTrackList,
favoriteAlbumList, missingFavoriteAlbums, index (LibraryIndex), stats, favoriteTracks, favoriteAlbums, playlists, history
// Suche
model.query(_ section: LibrarySection) -> String;  model.setQuery(_:_:)
// v2: Ansichten (gespeichert)
func viewOptions(_ context: LibraryViewContext) -> LibraryViewOptions
func setViewOptions(_ options: LibraryViewOptions, for context: LibraryViewContext)
// v2: Filter (je Bereich, nicht gespeichert)
func filter(_ context: LibraryViewContext) -> LibraryFilter
func setFilter(_ filter: LibraryFilter, for context: LibraryViewContext)
var facets: FilterFacets                       // aus allen verfügbaren Titeln
var unfilteredCount: [LibraryViewContext: Int] // Anzahl ohne Filter/Suche (für „12 von 340“)
// v2: Sortierung je Bereich (bestehend, jetzt mit neuen Feldern): model.settings.trackSort usw.
// v2: Audio ohne Speichern (während Reglerbewegung)
func previewEffects(_ effects: AudioEffectsSettings)
func previewPitch(_ pitch: PitchSettings)
// Navigation, Aktionen (bestehend)
select(_:), open(_:), back(), openAlbum(of:), openArtist(named:), showInfo(_:), toggleFavorite(_:), setFavorite(_:_:),
isFavorite(_:), isAlbumFavorite(_:), toggleAlbumFavorite(_:), addToPlaylist(_:trackUids:), toast(_:…),
sidePanel, playerOpen, addToPlaylistUids
WindowRouter.shared.openSettings(), .openEqualizer(), .openMiniPlayer(), .openEditor()
```

`PlayerService` (Audio/PlayerService.swift): `current, isPlaying, queue, shuffleEnabled, repeatMode, clock,
liveVolume, preparing, lastError, sleepTimer` · `play(uids:startIndex:shuffle:source:)`, `togglePlay()`,
`next()`, `previous()`, `seek(to:)`, `skip(by:)`, `skipForward()`, `skipBackward()` (v2: nutzen
`settings.skipSeconds`), `toggleShuffle()`, `cycleRepeat()`, `setLiveVolume(_:)`, `playNext(uids:)`,
`addToQueue(uids:)`, `jump(to:)`, `removeFromQueue(item:)`, `moveUpNext(from:to:)`, `clearUpNext()`,
`startSleepTimer(minutes:)`, `sleepAtEndOfTrack()`, `cancelSleepTimer()`, `setVisualizer(_:)`,
`engine.levels` (LevelMeter, nur bei aktiver Visualisierung).

## 4. Dateizuständigkeit (gleichzeitige Arbeit)

| Bereich | Dateien |
|---|---|
| Bibliothek (Ansichten, Sortierung, Filter, Cover Flow) | `Views/LibraryViews.swift`, `Views/PlaylistViews.swift`, `Views/FavoritesAndTools.swift`, `Views/TrackList.swift`, `Views/Scaffold.swift`, neue Dateien in `Views/Library/` |
| Player, Mini-Player, Player-Designs | alle Dateien in `Player/`, neue Dateien in `Player/` |
| Hauptfenster, Navigation, Einstellungen, AppModel, PlayerService, Artwork, Glas, Snapshots, Performance | `Views/MainWindow.swift`, `App/`, `Audio/`, `Design/`, `Settings/`, `Snapshot/`, `Library/`, `Metadata/` |

Wer eine Änderung in einer fremden Datei braucht, beschreibt sie im Bericht (Datei, was, warum) statt sie
selbst vorzunehmen.
