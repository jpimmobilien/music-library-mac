import SwiftUI
import AppKit
import MLCore
import MLTags

/// Bereiche des Informationsfensters.
enum EditorTab: String, CaseIterable, Hashable {
    case details, cover, lyrics, sorting, file

    var label: String {
        switch self {
        case .details: return "Details"
        case .cover: return "Cover"
        case .lyrics: return "Liedtext"
        case .sorting: return "Sortierung"
        case .file: return "Datei"
        }
    }

    var icon: String {
        switch self {
        case .details: return Icons.info
        case .cover: return Icons.image
        case .lyrics: return Icons.lyrics
        case .sorting: return Icons.sortByAlpha
        case .file: return Icons.description
        }
    }
}

/// Eine Datei im Bearbeitungsfenster.
struct EditorFile: Identifiable {
    let track: Track
    var result: TagReadResult?
    var error: String?
    var supported: Set<TagField>
    var id: Int64 { track.uid }
    var url: URL { URL(fileURLWithPath: track.path) }
}

/// Zustand einer Bearbeitung (ein oder mehrere Titel). Gemischte Werte werden als „Gemischt“ geführt;
/// geschrieben werden nur ausdrücklich geänderte Felder.
@MainActor
final class EditorSession: ObservableObject {
    let uids: [Int64]
    @Published var loading = true
    @Published var files: [EditorFile] = []
    @Published var tab: EditorTab = .details

    /// Angezeigter Text je Feld.
    @Published var text: [TagField: String] = [:]
    /// Felder mit unterschiedlichen Werten in der Auswahl.
    @Published var mixed: Set<TagField> = []
    /// Vom Benutzer geänderte Felder (werden geschrieben).
    @Published var dirty: Set<TagField> = []

    @Published var pictures: [EmbeddedPicture] = []
    @Published var picturesMixed = false
    @Published var picturesDirty = false
    @Published var selectedPicture = 0
    /// Cover für alle Titel des Albums übernehmen.
    @Published var applyCoverToAlbum = false
    /// Sehr große Bilder vor dem Einbetten verkleinern (längste Seite 3000 px).
    @Published var downscaleLargeImages = true

    private var original: [TagField: String] = [:]

    init(uids: [Int64]) {
        self.uids = uids
    }

    var isMulti: Bool { files.count > 1 }
    var hasChanges: Bool { !dirty.isEmpty || picturesDirty }

    /// Felder, die alle ausgewählten Dateien speichern können.
    var supportedFields: Set<TagField> {
        let sets = files.compactMap { $0.result != nil ? $0.supported : nil }
        guard let first = sets.first else { return [] }
        return sets.dropFirst().reduce(first) { $0.intersection($1) }
    }

    var allWritable: Bool { files.allSatisfy { $0.result?.writable ?? false } }

    /// Nur für Vorschaubilder: Tags aus der Beispielbibliothek statt aus Dateien.
    static var demoResult: ((Track) -> TagReadResult?)?

    func load(tracks: [Track]) async {
        loading = true
        if let demo = Self.demoResult {
            files = tracks.map { EditorFile(track: $0, result: demo($0), error: nil, supported: Set(TagField.allCases)) }
            recomputeCombined()
            loading = false
            return
        }
        let loaded: [EditorFile] = await Task.detached(priority: .userInitiated) {
            tracks.map { t in
                let url = URL(fileURLWithPath: t.path)
                do {
                    let r = try TagFile.read(url: url)
                    let supported = (try? TagFile.supportedFields(url: url)) ?? Set(TagField.allCases)
                    return EditorFile(track: t, result: r, error: nil, supported: supported)
                } catch {
                    return EditorFile(track: t, result: nil, error: error.localizedDescription, supported: [])
                }
            }
        }.value
        files = loaded
        recomputeCombined()
        loading = false
    }

    private func recomputeCombined() {
        let values = files.compactMap { $0.result?.values }
        var t: [TagField: String] = [:]
        var m: Set<TagField> = []
        for field in TagField.allCases {
            switch MixedValue.combine(values.map { $0.text(for: field) }) {
            case .same(let v)?: t[field] = v
            case .mixed?:
                t[field] = ""
                m.insert(field)
            case nil: t[field] = ""
            }
        }
        text = t
        original = t
        mixed = m
        dirty = []
        let pics = values.map(\.pictures)
        if let first = pics.first {
            picturesMixed = pics.dropFirst().contains { $0 != first }
            pictures = picturesMixed ? [] : first
        } else {
            pictures = []
            picturesMixed = false
        }
        picturesDirty = false
        selectedPicture = 0
    }

    // MARK: Felder

    func value(_ field: TagField) -> String { text[field] ?? "" }

    func binding(_ field: TagField) -> Binding<String> {
        Binding(get: { self.value(field) }, set: { self.set(field, $0) })
    }

    func set(_ field: TagField, _ newValue: String) {
        text[field] = newValue
        if !mixed.contains(field) && newValue == (original[field] ?? "") {
            dirty.remove(field)
        } else {
            dirty.insert(field)
        }
    }

    /// Feld auf den ursprünglichen Wert zurücksetzen (auch „Gemischt“ wiederherstellen).
    func revert(_ field: TagField) {
        text[field] = original[field] ?? ""
        dirty.remove(field)
    }

    func revertAll() { recomputeCombined() }

    var compilation: Bool? {
        if mixed.contains(.compilation) && !dirty.contains(.compilation) { return nil }
        return value(.compilation) == "1"
    }

    func setCompilation(_ on: Bool) { set(.compilation, on ? "1" : "0") }

    /// Bewertung 0…5 Sterne (`nil` = gemischt).
    var stars: Int? {
        if mixed.contains(.rating) && !dirty.contains(.rating) { return nil }
        return ((Int(value(.rating)) ?? 0) + 10) / 20
    }

    func setStars(_ n: Int) { set(.rating, n == 0 ? "" : String(n * 20)) }

    // MARK: Bilder

    func setPictures(_ pics: [EmbeddedPicture]) {
        pictures = pics
        picturesDirty = true
        picturesMixed = false
        selectedPicture = min(selectedPicture, max(0, pics.count - 1))
    }

    func addPicture(_ pic: EmbeddedPicture) {
        var p = pictures
        var pic = pic
        if p.isEmpty { pic.kind = .frontCover }
        p.append(pic)
        setPictures(p)
        selectedPicture = p.count - 1
    }

    func replaceSelectedPicture(_ pic: EmbeddedPicture) {
        guard pictures.indices.contains(selectedPicture) else { return addPicture(pic) }
        var p = pictures
        var newPic = pic
        newPic.kind = p[selectedPicture].kind
        p[selectedPicture] = newPic
        setPictures(p)
    }

    func removeSelectedPicture() {
        guard pictures.indices.contains(selectedPicture) else { return }
        var p = pictures
        p.remove(at: selectedPicture)
        setPictures(p)
    }

    func setKind(_ kind: PictureKind, at index: Int) {
        guard pictures.indices.contains(index) else { return }
        var p = pictures
        p[index].kind = kind
        setPictures(p)
    }

    // MARK: Ergebnis

    /// Die Bearbeitung (gleich für alle ausgewählten Dateien).
    func makeEdit() -> TagEdit {
        var values = TagValues()
        for field in dirty { values.setText(value(field), for: field) }
        return TagEdit(values: values, fields: dirty, pictures: picturesDirty ? .replaceAll(pictures) : .keep)
    }

    /// Kurzbeschreibung vor dem Schreiben.
    var summary: String {
        var parts: [String] = []
        let names = dirty.sorted { TagField.allCases.firstIndex(of: $0)! < TagField.allCases.firstIndex(of: $1)! }.map(\.label)
        if !names.isEmpty { parts.append("\(names.count == 1 ? "1 Feld" : "\(names.count) Felder") (\(names.joined(separator: ", ")))") }
        if picturesDirty { parts.append(pictures.isEmpty ? "Bilder entfernen" : "\(pictures.count == 1 ? "1 Bild" : "\(pictures.count) Bilder")") }
        return parts.joined(separator: " · ")
    }

    /// Werte kopieren (für „Metadaten einfügen“ bei anderen Titeln).
    func copyableValues() -> (TagValues, Set<TagField>) {
        var v = TagValues()
        var fields = Set<TagField>()
        for f in TagField.allCases where !f.isPerTrackOnly && !mixed.contains(f) {
            v.setText(value(f), for: f)
            fields.insert(f)
        }
        return (v, fields)
    }

    /// Eingefügte Werte übernehmen (nur gesetzte, nicht titelspezifische Felder).
    func paste(_ values: TagValues, fields: Set<TagField>) {
        for f in fields where !f.isPerTrackOnly {
            let t = values.text(for: f)
            if !t.isEmpty || f == .compilation { set(f, t) }
        }
    }
}
