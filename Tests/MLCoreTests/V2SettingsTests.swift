import XCTest
@testable import MLCore

/// v2: Ansichten, neue Einstellungen (tolerant gelesen), eigene Equalizer-Presets, Tonhöhe, Designs.
final class V2SettingsTests: XCTestCase {

    private func reload(_ s: AppSettings) -> AppSettings { AppSettings.decode(from: s.encoded()) }

    private func decode(_ json: String) -> AppSettings { AppSettings.decode(from: Data(json.utf8)) }

    // MARK: - Ansichten

    func testAnsichten_standardJeBereich() {
        let modes = LibraryViewContext.allCases.map { LibraryViewOptions.defaults(for: $0).mode }
        XCTAssertEqual(modes, [.list, .grid, .list, .list, .grid, .list, .grid])
        XCTAssertEqual(LibraryViewOptions.coverSizeRange, 90...320)
        XCTAssertEqual(LibraryViewOptions.spacingRange, 6...40)
        for context in LibraryViewContext.allCases {
            let d = LibraryViewOptions.defaults(for: context)
            let available = LibraryViewOptions.availableColumns(for: context)
            XCTAssertFalse(d.columns.isEmpty, context.rawValue)
            XCTAssertTrue(Set(d.columns).isSubset(of: Set(available)), context.rawValue)
            XCTAssertEqual(Set(available).count, available.count, context.rawValue)
            XCTAssertTrue(LibraryViewOptions.coverSizeRange.contains(d.coverSize))
            XCTAssertTrue(LibraryViewOptions.spacingRange.contains(d.spacing))
            XCTAssertEqual(d.normalized(for: context), d, context.rawValue)
            XCTAssertFalse(context.label.isEmpty)
        }
        let albums = LibraryViewOptions.availableColumns(for: .albums)
        XCTAssertTrue(Set(albums).isSuperset(of: [.album, .albumArtist, .year, .genre, .trackCount, .duration, .dateAdded]))
        XCTAssertEqual(LibraryViewOptions.availableColumns(for: .favoriteTracks), LibraryViewOptions.availableColumns(for: .tracks))
        XCTAssertTrue(LibraryViewOptions.availableColumns(for: .artists).contains(.albumCount))
    }

    func testAnsichten_namenUndSpalten() {
        XCTAssertEqual(LibraryViewMode.allCases.map(\.label), ["Raster", "Kompaktes Raster", "Liste", "Detailliste", "Cover Flow"])
        XCTAssertEqual(LibraryViewMode.allCases.map(\.rawValue), ["GRID", "COMPACT_GRID", "LIST", "DETAILED_LIST", "COVER_FLOW"])
        XCTAssertEqual(LibraryViewContext.allCases.map(\.rawValue),
                       ["TRACKS", "ALBUMS", "PLAYLISTS", "ARTISTS", "GENRES", "FAVORITE_TRACKS", "FAVORITE_ALBUMS"])
        XCTAssertEqual(DetailColumn.allCases.count, 17)
        XCTAssertEqual(DetailColumn.dateAdded.rawValue, "DATE_ADDED")
        XCTAssertEqual(DetailColumn.albumCount.rawValue, "ALBUM_COUNT")
        for c in DetailColumn.allCases {
            XCTAssertFalse(c.label.isEmpty)
            XCTAssertGreaterThan(c.defaultWidth, 0)
        }
        XCTAssertTrue(DetailColumn.duration.numeric)
        XCTAssertTrue(DetailColumn.trackCount.numeric)
        XCTAssertFalse(DetailColumn.title.numeric)
        XCTAssertEqual(DetailColumn.title.label, "Titel")
        XCTAssertEqual(DetailColumn.title.label(for: .artists), "Name")
        XCTAssertEqual(DetailColumn.title.label(for: .tracks), "Titel")
        XCTAssertEqual(DetailColumn.dateAdded.label(for: .playlists), "Erstellt")
        XCTAssertTrue(LibraryViewContext.favoriteTracks.showsTracks)
        XCTAssertFalse(LibraryViewContext.favoriteAlbums.showsTracks)
    }

    func testAnsichten_begrenztUndBereinigt() {
        let big = LibraryViewOptions(coverSize: 1_000, spacing: -5, columns: [.title, .title, .artist])
        XCTAssertEqual(big.coverSize, 320)
        XCTAssertEqual(big.spacing, 6)
        XCTAssertEqual(big.columns, [.title, .artist])
        XCTAssertEqual(LibraryViewOptions(coverSize: .nan, spacing: .infinity).coverSize, 180)
        XCTAssertEqual(LibraryViewOptions(coverSize: .nan, spacing: .infinity).spacing, 18)
        let artists = LibraryViewOptions(mode: .detailedList, columns: [.bpm, .trackCount, .title, .trackCount]).normalized(for: .artists)
        XCTAssertEqual(artists.columns, [.trackCount, .title]) // BPM gibt es bei Interpreten nicht
        XCTAssertEqual(artists.mode, .detailedList)
        XCTAssertEqual(LibraryViewOptions(columns: [.bpm]).normalized(for: .genres).columns, LibraryViewOptions.defaults(for: .genres).columns)
    }

    func testAnsichten_codable() throws {
        let o = LibraryViewOptions(mode: .coverFlow, coverSize: 222, spacing: 12, showSecondaryText: false, showDetails: true,
                                   columns: [.album, .year])
        XCTAssertEqual(try JSONDecoder().decode(LibraryViewOptions.self, from: JSONEncoder().encode(o)), o)
        let garbage = #"{"mode":"HOLOGRAMM","coverSize":5000,"spacing":"x","showDetails":true,"columns":["TITLE","FOO","TITLE","ARTIST",7]}"#
        let g = try JSONDecoder().decode(LibraryViewOptions.self, from: Data(garbage.utf8))
        let d = LibraryViewOptions.defaults(for: .tracks)
        XCTAssertEqual(g.mode, d.mode)
        XCTAssertEqual(g.coverSize, 320)
        XCTAssertEqual(g.spacing, d.spacing)
        XCTAssertTrue(g.showDetails)
        XCTAssertEqual(g.showSecondaryText, d.showSecondaryText)
        XCTAssertEqual(g.columns, [.title, .artist])
        XCTAssertEqual(try JSONDecoder().decode(LibraryViewOptions.self, from: Data(#"{"columns":[]}"#.utf8)).columns, d.columns)
    }

    func testEinstellungen_ansichtJeBereich() {
        var s = AppSettings()
        XCTAssertEqual(s.viewOptions, [:])
        XCTAssertEqual(s.viewOptions(for: .albums), LibraryViewOptions.defaults(for: .albums))
        var albums = s.viewOptions(for: .albums)
        albums.mode = .compactGrid
        albums.coverSize = 999
        albums.columns = [.album, .bpm, .year]
        s.setViewOptions(albums, for: .albums)
        XCTAssertEqual(s.viewOptions(for: .albums).mode, .compactGrid)
        XCTAssertEqual(s.viewOptions(for: .albums).coverSize, 320)
        XCTAssertEqual(s.viewOptions(for: .albums).columns, [.album, .year])
        XCTAssertEqual(s.viewOptions(for: .favoriteAlbums), LibraryViewOptions.defaults(for: .favoriteAlbums)) // getrennt gespeichert
        XCTAssertEqual(Array(s.viewOptions.keys), ["ALBUMS"])
        XCTAssertEqual(reload(s), s)
        XCTAssertEqual(reload(s).viewOptions(for: .albums).mode, .compactGrid)
    }

    func testEinstellungen_ansichtenTolerantGelesen() {
        let s = decode(#"""
        {"viewOptions":{"ALBUMS":{"mode":"LIST","coverSize":10,"columns":["BPM","YEAR"]},
                        "UNBEKANNT":{"mode":"GRID"},
                        "GENRES":{"mode":"WOLKE","spacing":99},
                        "TRACKS":42}}
        """#)
        XCTAssertEqual(Set(s.viewOptions.keys), ["ALBUMS", "GENRES", "TRACKS"]) // unbekannter Bereich ignoriert
        let albums = s.viewOptions(for: .albums)
        XCTAssertEqual(albums.mode, .list)
        XCTAssertEqual(albums.coverSize, 90)
        XCTAssertEqual(albums.columns, [.year])
        XCTAssertEqual(albums.spacing, LibraryViewOptions.defaults(for: .albums).spacing)
        let genres = s.viewOptions(for: .genres)
        XCTAssertEqual(genres.mode, .grid) // unbekannte Darstellung → Standard des Bereichs
        XCTAssertEqual(genres.spacing, 40)
        XCTAssertEqual(s.viewOptions(for: .tracks), LibraryViewOptions.defaults(for: .tracks))
        XCTAssertEqual(decode(#"{"viewOptions":"kaputt"}"#).viewOptions, [:])
    }

    // MARK: - Neue Einstellungen

    func testNeueEinstellungen_standardwerte() {
        let s = AppSettings()
        XCTAssertNil(s.startSection)
        XCTAssertTrue(s.showMenuBarPlayer)
        XCTAssertTrue(s.dynamicCoverColors)
        XCTAssertFalse(s.reduceTransparency)
        XCTAssertEqual(s.animationLevel, .full)
        XCTAssertEqual(s.cassetteColor, .smoke)
        XCTAssertEqual(s.miniPlayerSize, .standard)
        XCTAssertTrue(s.miniPlayerShowsDesign)
        XCTAssertTrue(s.watchFolders)
        XCTAssertTrue(s.scanOnLaunch)
        XCTAssertEqual(s.skipSeconds, 10)
        XCTAssertTrue(s.rememberLongTrackPosition)
        XCTAssertTrue(s.sleepTimerFadeOut)
        XCTAssertEqual(s.eqUserPresets, [])
        XCTAssertFalse(s.keepPitchOnRelaunch)
        XCTAssertEqual(s.maxVolume, 3.0)
        XCTAssertEqual(s.lyricsFontSize, 17)
        XCTAssertTrue(s.lyricsAutoScroll)
        XCTAssertTrue(s.lyricsUseLrcFiles)
        XCTAssertTrue(s.mediaKeysEnabled)
        XCTAssertEqual(s.coverCacheLimitMB, 500)
        XCTAssertTrue(s.recordHistory)
        XCTAssertTrue(s.recordPlayCounts)
        XCTAssertEqual(AppSettings.skipSecondsOptions, [5, 10, 15, 30])
    }

    func testNeueEinstellungen_werdenGespeichert() {
        var s = AppSettings()
        s.startSection = .albums
        s.showMenuBarPlayer = false
        s.dynamicCoverColors = false
        s.reduceTransparency = true
        s.animationLevel = .reduced
        s.cassetteColor = .cover
        s.miniPlayerSize = .large
        s.miniPlayerShowsDesign = false
        s.setViewOptions(LibraryViewOptions(mode: .detailedList, columns: [.title, .bpm]), for: .tracks)
        s.watchFolders = false
        s.scanOnLaunch = false
        s.skipSeconds = 30
        s.rememberLongTrackPosition = false
        s.sleepTimerFadeOut = false
        s.effects = s.effects.withPreset(EqPresets.jazz).withBass(3)
        s.saveEqPreset(name: "Mein Jazz")
        s.keepPitchOnRelaunch = true
        s.maxVolume = 1.5
        s.lyricsFontSize = 22.5
        s.lyricsAutoScroll = false
        s.lyricsUseLrcFiles = false
        s.mediaKeysEnabled = false
        s.coverCacheLimitMB = 2_000
        s.recordHistory = false
        s.recordPlayCounts = false
        let r = reload(s)
        XCTAssertEqual(r, s)
        XCTAssertEqual(r.startSection, .albums)
        XCTAssertEqual(r.eqUserPresets.map(\.name), ["Mein Jazz"])
        XCTAssertEqual(r.viewOptions(for: .tracks).columns, [.title, .bpm])
        let json = String(decoding: s.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""cassetteColor" : "COVER""#))
        XCTAssertTrue(json.contains(#""animationLevel" : "REDUCED""#))
        XCTAssertTrue(json.contains(#""startSection" : "ALBUMS""#))
        // „zuletzt benutzter Bereich“ (nil) wird nicht geschrieben und bleibt nil
        XCTAssertFalse(String(decoding: AppSettings().encoded(), as: UTF8.self).contains("startSection"))
        XCTAssertNil(reload(AppSettings()).startSection)
        XCTAssertEqual(reload(AppSettings()), AppSettings())
    }

    func testAlteEinstellungsdatei_ohneNeueSchluessel_ergibtStandardwerte() {
        let v1 = #"""
        {"themeMode":"DARK","glassEffects":false,"trackSort":"YEAR:desc","albumSort":"TITLE:asc","playlistSort":"NAME:asc",
         "artistSort":"NAME:asc","genreSort":"NAME:asc","favoriteTrackSort":"ADDED:desc","favoriteAlbumSort":"ADDED:desc",
         "favoritesTab":"ALBUMS","deleteMode":"TRASH","effects":{"eqEnabled":true,"bandGains":[0,0,0,0,0,0,0,0,0,0],
         "volume":1.2,"autoHeadroom":true,"bassDb":2},"lastSection":"GENRES","playerTheme":"CASSETTE","visualizer":true,
         "pitch":{"mode":"KEY","semitones":1.5,"tempo":1},"resumeOnLaunch":true,"showComposer":false,
         "backupRetentionDays":30,"confirmBeforeWritingTags":true}
        """#
        let s = decode(v1)
        XCTAssertEqual(s.themeMode, .dark)
        XCTAssertEqual(s.lastSection, .genres)
        XCTAssertEqual(s.playerTheme, .cassette)
        XCTAssertEqual(s.pitch.semitones, 1.5)
        var expected = AppSettings()
        expected.themeMode = s.themeMode
        expected.glassEffects = s.glassEffects
        expected.trackSort = s.trackSort
        expected.favoritesTab = s.favoritesTab
        expected.effects = s.effects
        expected.lastSection = s.lastSection
        expected.playerTheme = s.playerTheme
        expected.visualizer = s.visualizer
        expected.pitch = s.pitch
        XCTAssertEqual(s, expected) // alle neuen Werte = Standard
    }

    func testNeueEinstellungen_ungueltigeWerte_begrenztOderStandard() {
        let s = decode(#"""
        {"skipSeconds":7,"maxVolume":9,"lyricsFontSize":2,"coverCacheLimitMB":99999,"animationLevel":"WILD",
         "cassetteColor":"PINK","miniPlayerSize":5,"startSection":"NIRGENDWO","eqUserPresets":"x",
         "showMenuBarPlayer":"ja","recordHistory":"nein","keepPitchOnRelaunch":null,"playerTheme":"AURORA"}
        """#)
        XCTAssertEqual(s.skipSeconds, 10)
        XCTAssertEqual(s.maxVolume, 3)
        XCTAssertEqual(s.lyricsFontSize, 12)
        XCTAssertEqual(s.coverCacheLimitMB, 4_000)
        XCTAssertEqual(s.animationLevel, .full)
        XCTAssertEqual(s.cassetteColor, .smoke)
        XCTAssertEqual(s.miniPlayerSize, .standard)
        XCTAssertNil(s.startSection)
        XCTAssertEqual(s.eqUserPresets, [])
        XCTAssertTrue(s.showMenuBarPlayer)
        XCTAssertTrue(s.recordHistory)
        XCTAssertFalse(s.keepPitchOnRelaunch)
        XCTAssertEqual(s.playerTheme, .aurora)

        let t = decode(#"{"skipSeconds":15,"maxVolume":0.5,"lyricsFontSize":99,"coverCacheLimitMB":1,"miniPlayerSize":"COMPACT"}"#)
        XCTAssertEqual(t.skipSeconds, 15)
        XCTAssertEqual(t.maxVolume, 1)
        XCTAssertEqual(t.lyricsFontSize, 30)
        XCTAssertEqual(t.coverCacheLimitMB, 100)
        XCTAssertEqual(t.miniPlayerSize, .compact)
        for allowed in AppSettings.skipSecondsOptions {
            XCTAssertEqual(decode(#"{"skipSeconds":\#(allowed)}"#).skipSeconds, allowed)
        }
        XCTAssertEqual(decode(#"{"skipSeconds":0}"#).skipSeconds, 10)
        XCTAssertEqual(decode(#"{"maxVolume":2.25}"#).maxVolume, 2.25)
    }

    // MARK: - Eigene Equalizer-Presets

    func testEqPreset_speichernAusAktuellenBaendern() {
        var s = AppSettings()
        s.effects = s.effects.withPreset(EqPresets.rock).withBass(4)
        let p = s.saveEqPreset(name: "  Mein   Rock  ")
        XCTAssertEqual(p.name, "Mein Rock")
        XCTAssertEqual(p.gains, EqPresets.rock.gains)
        XCTAssertEqual(p.bassDb, 4)
        XCTAssertTrue(p.id.hasPrefix("user-"))
        XCTAssertEqual(s.eqUserPresets, [p])
        XCTAssertEqual(s.effects.activeUserPreset(in: s.eqUserPresets), p)
        let q = s.saveEqPreset(name: "Anderes")
        XCTAssertNotEqual(p.id, q.id)
    }

    func testEqPreset_namenEindeutigGekuerztUndStandard() {
        var s = AppSettings()
        XCTAssertEqual(s.saveEqPreset(name: "Mein Preset").name, "Mein Preset")
        XCTAssertEqual(s.saveEqPreset(name: "Mein Preset").name, "Mein Preset (2)")
        XCTAssertEqual(s.saveEqPreset(name: "mein preset").name, "mein preset (3)")
        XCTAssertEqual(s.saveEqPreset(name: "   ").name, "Eigenes Preset")
        XCTAssertEqual(s.saveEqPreset(name: "").name, "Eigenes Preset (2)")
        let long = String(repeating: "ä", count: 60)
        let first = s.saveEqPreset(name: long).name
        XCTAssertEqual(first, String(repeating: "ä", count: 40))
        let second = s.saveEqPreset(name: long).name
        XCTAssertEqual(second, String(repeating: "ä", count: 36) + " (2)")
        XCTAssertEqual(second.count, EqUserPreset.maxNameLength)
        XCTAssertEqual(EqUserPreset.cleanName(" a \n b "), "a b")
        XCTAssertEqual(EqUserPreset.uniqueName("X", existing: ["X", "X (2)"]), "X (3)")
    }

    func testEqPreset_umbenennenAktualisierenLoeschen() {
        var s = AppSettings()
        s.effects = s.effects.withPreset(EqPresets.pop)
        let a = s.saveEqPreset(name: "A")
        let b = s.saveEqPreset(name: "B")
        s.renameEqPreset(id: b.id, to: "A")
        XCTAssertEqual(s.eqUserPresets.map(\.name), ["A", "A (2)"])
        s.renameEqPreset(id: a.id, to: "  A ") // eigener Name bleibt ohne Zusatz
        XCTAssertEqual(s.eqUserPresets.map(\.name), ["A", "A (2)"])
        s.renameEqPreset(id: a.id, to: "")
        XCTAssertEqual(s.eqUserPresets[0].name, "Eigenes Preset")
        s.renameEqPreset(id: "user-gibtesnicht", to: "X")
        XCTAssertEqual(s.eqUserPresets.map(\.name), ["Eigenes Preset", "A (2)"])

        s.effects = s.effects.withPreset(EqPresets.vocal).withBass(-2)
        s.updateEqPreset(id: a.id)
        XCTAssertEqual(s.eqUserPresets[0].gains, EqPresets.vocal.gains)
        XCTAssertEqual(s.eqUserPresets[0].bassDb, -2)
        XCTAssertEqual(s.eqUserPresets[1].gains, EqPresets.pop.gains) // anderes unverändert
        XCTAssertEqual(s.eqUserPresets[0].id, a.id)

        s.deleteEqPreset(id: a.id)
        XCTAssertEqual(s.eqUserPresets.map(\.id), [b.id])
        s.deleteEqPreset(id: "gibtesnicht")
        XCTAssertEqual(s.eqUserPresets.count, 1)
        XCTAssertEqual(reload(s), s)
    }

    func testEqPreset_anwendenUndErkennen() {
        let preset = EqUserPreset(id: "user-1", name: "Warm", gains: [3, 2, 1, 0, 0, 0, 0, -1, -2, -3], bassDb: 5)
        let off = AudioEffectsSettings(eqEnabled: false)
        let applied = off.withUserPreset(preset)
        XCTAssertTrue(applied.eqEnabled)
        XCTAssertEqual(applied.bandGains, preset.gains)
        XCTAssertEqual(applied.bassDb, 5)
        XCTAssertEqual(applied.activeUserPreset(in: [preset]), preset)
        XCTAssertNil(applied.withBand(0, 6).activeUserPreset(in: [preset]))
        XCTAssertNil(AudioEffectsSettings().activeUserPreset(in: [preset]))
        XCTAssertEqual(applied.withBass(0).activeUserPreset(in: [preset]), preset) // Bass zählt nicht
        // ohne mitgespeicherten Bass bleibt der Bassregler, wie er ist
        let noBass = EqUserPreset(name: "Ohne Bass", gains: EqPresets.rock.gains)
        XCTAssertEqual(AudioEffectsSettings().withBass(2).withUserPreset(noBass).bassDb, 2)
        // erstes passendes Preset gewinnt
        let twin = EqUserPreset(id: "user-2", name: "Zwilling", gains: preset.gains)
        XCTAssertEqual(applied.activeUserPreset(in: [twin, preset])?.id, "user-2")
    }

    func testEqPreset_baenderImmerZehnUndBegrenzt() {
        let p = EqUserPreset(name: "X", gains: [20, -20, .nan, 1.5], bassDb: 99)
        XCTAssertEqual(p.gains, [12, -12, 0, 1.5, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(p.bassDb, 12)
        XCTAssertEqual(EqUserPreset(name: "X", gains: Array(repeating: 1, count: 12)).gains.count, 10)
        XCTAssertNil(EqUserPreset(name: "X", gains: [], bassDb: .nan).bassDb)
        XCTAssertTrue(EqUserPreset(name: "X", gains: []).id.hasPrefix("user-"))
    }

    func testEqPreset_tolerantGelesen() throws {
        let p = EqUserPreset(id: "user-a", name: "A", gains: EqPresets.jazz.gains, bassDb: 1.5)
        XCTAssertEqual(try JSONDecoder().decode(EqUserPreset.self, from: JSONEncoder().encode(p)), p)
        let partial = try JSONDecoder().decode(EqUserPreset.self, from: Data(#"{"name":"  B ","gains":[1,2]}"#.utf8))
        XCTAssertTrue(partial.id.hasPrefix("user-"))
        XCTAssertEqual(partial.name, "B")
        XCTAssertEqual(partial.gains, [1, 2, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertNil(partial.bassDb)

        let s = decode(#"""
        {"eqUserPresets":[{"id":"user-1","name":"Eins","gains":[1,1,1,1,1,1,1,1,1,1]}, 5, "x",
                          {"id":"user-1","name":"Doppelt","gains":"kaputt","bassDb":"laut"}, {}]}
        """#)
        XCTAssertEqual(s.eqUserPresets.map(\.name), ["Eins", "Doppelt", "Eigenes Preset"])
        XCTAssertEqual(s.eqUserPresets[0].id, "user-1")
        XCTAssertNotEqual(s.eqUserPresets[1].id, "user-1") // doppelte Kennung erhält eine neue
        XCTAssertEqual(s.eqUserPresets[1].gains, EqPresets.flat.gains)
        XCTAssertNil(s.eqUserPresets[1].bassDb)
        XCTAssertEqual(Set(s.eqUserPresets.map(\.id)).count, 3)
    }

    // MARK: - Tonhöhe

    func testTonhoehe_rundetAufHundertstelUndBegrenzt() {
        XCTAssertEqual(PitchSettings.fineStep, 0.1)
        XCTAssertEqual(PitchSettings.coarseStep, 1)
        var p = PitchSettings()
        for _ in 0..<7 { p = p.withSemitones(p.semitones + PitchSettings.fineStep) }
        XCTAssertEqual(p.semitones, 0.7) // keine Rechenreste
        for _ in 0..<10 { p = p.withSemitones(p.semitones - PitchSettings.fineStep) }
        XCTAssertEqual(p.semitones, -0.3)
        XCTAssertEqual(PitchSettings().withSemitones(1.234).semitones, 1.23)
        XCTAssertEqual(PitchSettings().withSemitones(-2.567).semitones, -2.57)
        XCTAssertEqual(PitchSettings().withSemitones(13.7).semitones, 12)
        XCTAssertEqual(PitchSettings().withSemitones(-40).semitones, -12)
        XCTAssertEqual(PitchSettings().withSemitones(.infinity).semitones, 12)
        XCTAssertEqual(PitchSettings().withSemitones(.nan).semitones, 0)
        let tiny = PitchSettings().withSemitones(-0.004).semitones
        XCTAssertEqual(tiny, 0)
        XCTAssertEqual(tiny.sign, .plus) // kein „−0“
        XCTAssertTrue(PitchSettings().withSemitones(0.001).isOriginal)
        // gespeicherte Werte werden ebenso gerundet
        let s = decode(#"{"pitch":{"mode":"KEY","semitones":0.30000001,"tempo":1}}"#)
        XCTAssertEqual(s.pitch.semitones, 0.3)
    }

    func testFormatierung_halbtoeneMitZehntelnUndCent() {
        XCTAssertEqual(Formatting.semitones(1.5), "+1,5 Halbtöne")
        XCTAssertEqual(Formatting.semitones(-0.3), "−0,3 Halbtöne")
        XCTAssertEqual(Formatting.semitones(1), "+1 Halbton")
        XCTAssertEqual(Formatting.semitones(-1), "−1 Halbton")
        XCTAssertEqual(Formatting.semitones(0), "Original")
        XCTAssertEqual(Formatting.semitones(0.04), "Original")
        XCTAssertEqual(Formatting.semitones(12), "+12 Halbtöne")
        XCTAssertEqual(Formatting.semitones(-12), "−12 Halbtöne")
        XCTAssertEqual(Formatting.semitones(0.96), "+1 Halbton")
        XCTAssertEqual(Formatting.semitones(5.2), "+5,2 Halbtöne")
        XCTAssertEqual(Formatting.semitones(-2.26), "−2,3 Halbtöne")
        XCTAssertEqual(Formatting.semitones(0.1), "+0,1 Halbtöne")
        XCTAssertEqual(Formatting.semitones(-11.9), "−11,9 Halbtöne")

        XCTAssertEqual(Formatting.cents(1.5), "+150 Cent")
        XCTAssertEqual(Formatting.cents(-0.3), "−30 Cent")
        XCTAssertEqual(Formatting.cents(0), "0 Cent")
        XCTAssertEqual(Formatting.cents(0.004), "0 Cent")
        XCTAssertEqual(Formatting.cents(12), "+1200 Cent")
        XCTAssertEqual(Formatting.cents(-12), "−1200 Cent")
        XCTAssertEqual(Formatting.cents(5.19), "+519 Cent")
        XCTAssertEqual(Formatting.cents(0.07), "+7 Cent")
        XCTAssertEqual(Formatting.cents(PitchSettings().withSemitones(-0.35).semitones), "−35 Cent")
    }

    // MARK: - Designs, Kassettenfarbe, Mini-Player, Animationen

    func testPlayerDesigns_neuHintenAngefuegt() {
        XCTAssertEqual(PlayerTheme.modernGlass.rawValue, "MODERN_GLASS")
        XCTAssertEqual(PlayerTheme.aurora.rawValue, "AURORA")
        XCTAssertEqual(PlayerTheme.reelToReel.rawValue, "REEL_TO_REEL")
        XCTAssertEqual(PlayerTheme.allCases.suffix(3).map(\.label), ["Modern Glass", "Aurora", "Studio Reel"])
        XCTAssertTrue(PlayerTheme.allCases.allSatisfy { !$0.description.isEmpty })
        XCTAssertEqual(PlayerTheme.fromStored("REEL_TO_REEL", legacyVisual: nil), .reelToReel)
        var s = AppSettings()
        s.playerTheme = .modernGlass
        XCTAssertEqual(reload(s).playerTheme, .modernGlass)
    }

    func testKassettenfarbenMiniPlayerAnimationen() {
        XCTAssertEqual(CassetteColor.allCases.map(\.rawValue), ["SMOKE", "ROSE", "OCEAN", "MINT", "SUNSET", "IVORY", "COVER"])
        XCTAssertNil(CassetteColor.cover.argb)
        for c in CassetteColor.allCases where c != .cover {
            XCTAssertEqual(c.argb.map { $0 >> 24 }, 0xFF, c.rawValue) // deckend
            XCTAssertFalse(c.label.isEmpty)
        }
        XCTAssertEqual(Set(CassetteColor.allCases.compactMap(\.argb)).count, 6)
        XCTAssertEqual(MiniPlayerSize.allCases.map(\.height), [64, 84, 112])
        XCTAssertEqual(MiniPlayerSize.allCases.map(\.rawValue), ["COMPACT", "STANDARD", "LARGE"])
        XCTAssertEqual(MiniPlayerSize.allCases.map(\.label), ["Kompakt", "Standard", "Groß"])
        XCTAssertEqual(AnimationLevel.allCases.map(\.rawValue), ["FULL", "REDUCED", "OFF"])
        XCTAssertTrue(AnimationLevel.allCases.allSatisfy { !$0.label.isEmpty })
    }
}
