import Foundation
import MLCore

/// Ziel innerhalb eines Bereichs (Android `Destination`), auf dem Mac ergänzt um Verlauf und Duplikate.
enum Destination: Hashable {
    case album(String)
    case artist(String)
    case genre(String)
    case playlist(Int64)
    case smartPlaylist(String)
    case history
    case duplicates
}

/// Seitenleiste rechts (Desktop-Ergänzung): Warteschlange, Liedtext oder Titelinformationen.
enum SidePanel: String, Hashable {
    case queue
    case lyrics
}

/// Kurze Mitteilung unten im Fenster (Android: Snackbar), optional mit Aktion („Rückgängig“).
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var actionLabel: String? = nil
    var isError: Bool = false
    var action: (() -> Void)? = nil

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Zustand des Einlesens der Musikordner.
enum ScanState: Equatable {
    case idle
    /// Läuft: verarbeitete und gefundene Dateien, aktueller Ordner.
    case running(done: Int, total: Int, folder: String)
    case finished(added: Int, updated: Int, missing: Int)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

extension LibrarySection {
    /// Symbol in der schwebenden Navigation (Android `navIcon`).
    func icon(selected: Bool) -> String {
        switch self {
        case .tracks: return selected ? "music_note_fill" : "music_note"
        case .albums: return selected ? "album_fill" : "album"
        case .playlists: return selected ? "queue_music_fill" : "queue_music"
        case .artists: return selected ? "mic_fill" : "mic"
        case .genres: return selected ? "genres_nav_fill" : "genres_nav"
        case .favorites: return selected ? "favorite" : "favorite_border"
        }
    }

    var shortcutDigit: Character {
        switch self {
        case .tracks: return "1"
        case .albums: return "2"
        case .playlists: return "3"
        case .artists: return "4"
        case .genres: return "5"
        case .favorites: return "6"
        }
    }
}
