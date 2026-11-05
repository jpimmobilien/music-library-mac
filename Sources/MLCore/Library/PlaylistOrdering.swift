import Foundation

/// Reine Logik für manuelle Playlists: Reihenfolge ändern, Namen prüfen (Portierung von `library/PlaylistOrdering.kt`).
public enum PlaylistOrdering {

    /// Verschiebt das Element an `from` nach `to` (beide Indizes in der ursprünglichen Liste).
    public static func move<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return items }
        var list = items
        let item = list.remove(at: from)
        list.insert(item, at: to)
        return list
    }

    /// Neue Positionen 0..n-1 in der gegebenen Reihenfolge (lückenlos).
    public static func renumber<T>(_ items: [T]) -> [(T, Int)] {
        items.enumerated().map { ($0.element, $0.offset) }
    }

    public static let maxNameLength = 200

    /// Bereinigter Playlistname oder `nil`, wenn er leer ist.
    ///
    /// Gekürzt wird auf 200 Zeichen (Graphem-Cluster), nicht wie in Kotlin auf 200 UTF-16-Einheiten –
    /// so wird nie ein Emoji oder Umlaut mittendurch geschnitten.
    public static func cleanName(_ raw: String) -> String? {
        let name = raw.collapsingRegexWhitespace().kotlinTrimmed()
        if name.isEmpty { return nil }
        return String(name.prefix(maxNameLength))
    }

    /// Freier Name: „Neue Playlist“, „Neue Playlist 2“ … (Vergleich ohne Groß-/Kleinschreibung).
    public static func uniqueName<C: Collection>(_ base: String, existing: C) -> String where C.Element == String {
        let taken = Set(existing.map { $0.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
