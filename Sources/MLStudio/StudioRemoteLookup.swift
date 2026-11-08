import Foundation

// Additive Erweiterung des Vertrags (Audio Studio 2.2): Playlists und Sets erkennen, damit mehrere Titel
// als einzelne Aufträge in die Warteschlange kommen. Dienste ohne eigene Umsetzung (Ersatzdienste für
// Vorschaubilder und Tests) verwenden die Standard-Implementierungen unten.

/// Eintrag einer Playlist bzw. eines Sets (aus `yt-dlp --flat-playlist`, ohne die Titel einzeln abzufragen).
public struct RemotePlaylistEntry: Hashable, Sendable {
    public var url: URL
    public var title: String?
    public var duration: Double?

    public init(url: URL, title: String? = nil, duration: Double? = nil) {
        self.url = url
        self.title = title
        self.duration = duration
    }
}

/// Ergebnis der Abfrage einer Adresse: ein einzelner Titel oder eine Playlist/ein Set.
public enum RemoteLookup: Hashable, Sendable {
    case single(SourceInfo)
    /// Playlist/Set mit Titel und Einträgen (höchstens `RemoteLookup.maxEntries`).
    case playlist(title: String, entries: [RemotePlaylistEntry])

    /// Höchstzahl der Einträge, die aus einer Playlist übernommen werden.
    public static let maxEntries = 200
}

extension RemoteSourceProviding {
    /// Standard: jede Adresse ist ein einzelner Titel.
    public func lookup(url: URL, kind: SourceKind) async throws -> RemoteLookup {
        .single(try await analyze(url: url, kind: kind))
    }

    /// Standard: über `lookup`; ein einzelner Titel ergibt `[url]`.
    public func expandPlaylist(url: URL) async throws -> [URL] {
        let kind = SourceURL.classify(url.absoluteString)?.kind ?? .web
        if case .playlist(_, let entries) = try await lookup(url: url, kind: kind) {
            return Array(entries.prefix(RemoteLookup.maxEntries).map(\.url))
        }
        return [url]
    }
}
