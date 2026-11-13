import Foundation
import Combine
import MLCore
import MLStore
import MLStudio

/// Was das Audio Studio von der Bibliothek braucht. In der App erfüllt `AppModel` diese Schnittstelle;
/// Tests verwenden eine eigene Umsetzung (ohne Datenbank, Player und Fenster).
@MainActor
protocol StudioLibraryAccess: AnyObject {
    /// Musikordner der Bibliothek.
    var studioFolders: [LibraryFolder] { get }
    /// Alle Titel (für die Doppel-Erkennung und „Abspielen“).
    var studioTracks: [Track] { get }
    func studioTrack(_ uid: Int64) -> Track?
    /// Neue Dateien in den Musikordnern einlesen.
    func studioRescan()
    /// Eine geänderte Datei neu einlesen (Original ersetzt bzw. wiederhergestellt) und die Bibliothek neu laden.
    func studioRefreshTrack(_ uid: Int64)
    /// Kurze Mitteilung (vorhandene Toasts der App).
    func studioToast(_ text: String, action: String?, isError: Bool, perform: (() -> Void)?)
    /// Audio Studio anzeigen.
    func studioShow()
    /// Titel im Hauptplayer abspielen.
    func studioPlay(uid: Int64)
    /// Änderungen beobachten: Bibliothek neu geladen bzw. Studio ein-/ausgeblendet.
    func studioObserve(libraryChanged: @escaping @MainActor @Sendable () -> Void, visibilityChanged: @escaping @MainActor @Sendable (Bool) -> Void) -> [AnyCancellable]
    /// Equalizer und Bass des Players (für „wie im Player“ beim Bearbeiten).
    var studioPlayerEffects: AudioEffectsSettings? { get }
    /// Eigene Equalizer-Voreinstellungen.
    var studioEqUserPresets: [EqUserPreset] { get }
}

extension StudioLibraryAccess {
    var studioPlayerEffects: AudioEffectsSettings? { nil }
    var studioEqUserPresets: [EqUserPreset] { [] }
}

extension AppModel: StudioLibraryAccess {
    var studioFolders: [LibraryFolder] { folders }
    var studioTracks: [Track] { index.tracks }
    func studioTrack(_ uid: Int64) -> Track? { track(uid) }
    func studioRescan() { library.rescan(reason: "Audio Studio") }

    func studioRefreshTrack(_ uid: Int64) {
        library.refreshTrack(uid: uid)
        reloadLibrary()
    }

    func studioToast(_ text: String, action: String?, isError: Bool, perform: (() -> Void)?) {
        toast(text, action: action, isError: isError, perform: perform)
    }

    func studioShow() { openStudio() }
    var studioPlayerEffects: AudioEffectsSettings? { settings.effects }
    var studioEqUserPresets: [EqUserPreset] { settings.eqUserPresets }

    func studioPlay(uid: Int64) {
        player.play(uids: [uid], startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .singleTrack, label: "Audio Studio"))
    }

    func studioObserve(libraryChanged: @escaping @MainActor @Sendable () -> Void, visibilityChanged: @escaping @MainActor @Sendable (Bool) -> Void) -> [AnyCancellable] {
        // @Published meldet vor der Änderung – über einen Task weitergeben, damit beim Aufruf der neue Wert gilt.
        let lib = $index.dropFirst().sink { _ in
            Task { @MainActor in libraryChanged() }
        }
        let vis = $studioOpen.removeDuplicates().sink { open in
            Task { @MainActor in visibilityChanged(open) }
        }
        return [lib, vis]
    }
}
