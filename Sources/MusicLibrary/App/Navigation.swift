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

/// Was das Hauptfenster zeigt: die Bibliothek (sechs Bereiche) oder einen Arbeitsbereich mit eigenem Eintrag
/// in der Navigation (2.4: „Hinzufügen“ und „Studio“).
enum MainWorkspace: String, Hashable, CaseIterable {
    case library
    case add
    case studio

    /// Einträge rechts in der Navigation, in dieser Reihenfolge.
    static let navigationEntries: [MainWorkspace] = [.add, .studio]

    var label: String {
        switch self {
        case .library: return "Bibliothek"
        case .add: return "Hinzufügen"
        case .studio: return "Studio"
        }
    }

    /// Tastenkürzel (⌘7, ⌘8) – direkt nach den sechs Bereichen.
    var shortcutDigit: Int? {
        guard let i = Self.navigationEntries.firstIndex(of: self) else { return nil }
        return 7 + i
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .library: return Icons.libraryMusic
        case .add: return selected ? Icons.addMusicFill : Icons.addMusic
        case .studio: return selected ? Icons.studioFill : Icons.studio
        }
    }

    var help: String {
        switch self {
        case .library: return "Bibliothek"
        case .add: return "Hinzufügen – Musik aus dem Netz oder von deinem Mac (⌘7)"
        case .studio: return "Studio – Titel der Bibliothek schneiden und bearbeiten (⌘8)"
        }
    }
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
