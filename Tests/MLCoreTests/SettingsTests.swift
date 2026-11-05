import XCTest
@testable import MLCore

/// Portierung der Einstellungs-Teile von `data/DataRulesTest.kt` (Speichern als JSON statt SharedPreferences).
final class SettingsTests: XCTestCase {

    private func reload(_ s: AppSettings) -> AppSettings { AppSettings.decode(from: s.encoded()) }

    private func decode(_ json: String) -> AppSettings { AppSettings.decode(from: Data(json.utf8)) }

    func testEinstellungen_werdenDauerhaftUndJeBereichGespeichert() {
        var s = AppSettings()
        s.trackSort = Sort(.year, descending: true)
        s.albumSort = Sort(.duration, descending: false)
        s.themeMode = .dark
        s.deleteMode = .permanent
        s.effects = s.effects.withPreset(EqPresets.rock)
        s.effects.volume = 1.5
        s.favoritesTab = .albums
        s.playerTheme = .cassette
        s.visualizer = true
        let reloaded = reload(s)
        XCTAssertEqual(reloaded.trackSort, Sort(TrackSort.year, descending: true))
        XCTAssertEqual(reloaded.albumSort, Sort(AlbumSort.duration, descending: false))
        XCTAssertEqual(reloaded.themeMode, .dark)
        XCTAssertEqual(reloaded.deleteMode, .permanent)
        XCTAssertEqual(reloaded.effects.bandGains, EqPresets.rock.gains)
        XCTAssertEqual(reloaded.effects.volume, 1.5)
        XCTAssertEqual(reloaded.favoritesTab, .albums)
        XCTAssertEqual(reloaded.playerTheme, .cassette)
        XCTAssertTrue(reloaded.visualizer)
        XCTAssertEqual(reloaded, s)
    }

    func testEinstellungen_bassUndPlayerDesign_undAlteDarstellungUebernommen() {
        // Android 1.1.0 kannte nur „Darstellung“ (VINYL/COVER) → wird als Design übernommen
        XCTAssertEqual(PlayerTheme.fromStored(nil, legacyVisual: "COVER"), .classic)
        XCTAssertEqual(PlayerTheme.fromStored(nil, legacyVisual: "VINYL"), .vinylStudio)
        XCTAssertEqual(PlayerTheme.fromStored("PORTABLE_CD", legacyVisual: "COVER"), .portableCD)
        // ohne gespeicherten Wert: Vinyl Studio, Bass neutral, Visualisierung aus
        let fresh = decode("{}")
        XCTAssertEqual(fresh.playerTheme, .vinylStudio)
        XCTAssertEqual(fresh.effects.bassDb, 0)
        XCTAssertFalse(fresh.visualizer)
        // Bass wird gespeichert und begrenzt geladen
        var s = AppSettings()
        s.effects = s.effects.withBass(7.5)
        XCTAssertEqual(reload(s).effects.bassDb, 7.5)
        XCTAssertEqual(decode(#"{"effects":{"bassDb":99}}"#).effects.bassDb, 12)
    }

    func testPlayerDesign_wechselLaesstAllesAndereUnveraendert() {
        // v2: neue Designs hinten angefügt (gespeicherte Namen bleiben gültig)
        XCTAssertEqual(PlayerTheme.allCases, [.vinylStudio, .classic, .cassette, .portableCD, .modernGlass, .aurora, .reelToReel])
        var s = AppSettings()
        s.effects = s.effects.withPreset(EqPresets.rock).withBass(6)
        s.effects.volume = 1.4
        s.themeMode = .dark
        s.visualizer = true
        let before = reload(s)
        var changed = before
        changed.playerTheme = .portableCD
        let after = reload(changed)
        var expected = before
        expected.playerTheme = .portableCD
        XCTAssertEqual(after, expected)
        // unbekannter Name (z. B. aus einer späteren Version) → Vinyl Studio
        XCTAssertEqual(decode(#"{"playerTheme":"HOLOGRAMM"}"#).playerTheme, .vinylStudio)
    }

    func testEinstellungen_defekteWerteFallenAufStandard() {
        let s = decode(#"""
        {"trackSort":"GIBTESNICHT:desc","effects":{"bandGains":[1,2,3],"volume":99},"themeMode":"LILA",
         "lastSection":42,"glassEffects":"ja","backupRetentionDays":-5,"pitch":{"semitones":99}}
        """#)
        XCTAssertEqual(s.trackSort, AppSettings().trackSort)
        XCTAssertEqual(s.effects.bandGains, EqPresets.flat.gains)
        XCTAssertEqual(s.effects.volume, 3)
        XCTAssertEqual(s.themeMode, .system)
        XCTAssertEqual(s.lastSection, .tracks)
        XCTAssertTrue(s.glassEffects)
        XCTAssertEqual(s.backupRetentionDays, 1)
        XCTAssertEqual(s.pitch.semitones, 12)
    }

    func testKaputteDatei_ergibtStandard() {
        XCTAssertEqual(AppSettings.decode(from: Data("kein json".utf8)), AppSettings())
        XCTAssertEqual(AppSettings.decode(from: nil), AppSettings())
        XCTAssertEqual(AppSettings.decode(from: Data("[1,2]".utf8)), AppSettings())
        XCTAssertEqual(decode(#"{"unbekannterSchluessel":true}"#), AppSettings())
    }

    func testMacEinstellungen_standardwerteUndSpeichern() {
        let d = AppSettings()
        XCTAssertTrue(d.resumeOnLaunch)
        XCTAssertFalse(d.showComposer)
        XCTAssertEqual(d.backupRetentionDays, 30)
        XCTAssertTrue(d.confirmBeforeWritingTags)
        XCTAssertEqual(d.pitch, PitchSettings())
        var s = d
        s.resumeOnLaunch = false
        s.showComposer = true
        s.backupRetentionDays = 7
        s.confirmBeforeWritingTags = false
        s.pitch = PitchSettings(mode: .key, semitones: 2, tempo: 1.1)
        XCTAssertEqual(reload(s), s)
    }

    func testSechsBereiche_inDerRichtigenReihenfolge() {
        XCTAssertEqual(LibrarySection.allCases.map(\.label), ["Titel", "Alben", "Playlists", "Interpreten", "Genres", "Favoriten"])
        XCTAssertEqual(ThemeMode.system.label, "Wie macOS")
        XCTAssertTrue(ThemeMode.system.isDark(systemIsDark: true))
        XCTAssertFalse(ThemeMode.light.isDark(systemIsDark: true))
        XCTAssertEqual(FavoritesTab.albums.label, "Alben")
    }

    func testSpeicherformat_lesbar() throws {
        var s = AppSettings()
        s.trackSort = Sort(.year, descending: true)
        let json = try XCTUnwrap(String(data: s.encoded(), encoding: .utf8))
        XCTAssertTrue(json.contains(#""trackSort" : "YEAR:desc""#))
        XCTAssertTrue(json.contains(#""playerTheme" : "VINYL_STUDIO""#))
        XCTAssertTrue(json.contains(#""lastSection" : "TRACKS""#))
    }
}
