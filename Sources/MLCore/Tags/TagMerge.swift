import Foundation

/// Hilfen für die Bearbeitung mehrerer Titel gleichzeitig (ergänzt `TagValues`, `TagEdit`, `MixedValue`).
public enum TagMerge {

    /// Je Feld: gemeinsamer Wert aller ausgewählten Titel oder „Gemischt“ (Textdarstellung wie
    /// `TagValues.text(for:)`). Leere Auswahl → leeres Ergebnis.
    public static func mixedValues(_ selection: [TagValues], fields: [TagField] = TagField.allCases) -> [TagField: MixedValue<String>] {
        var result: [TagField: MixedValue<String>] = [:]
        for field in fields {
            if let mixed = MixedValue<String>.combine(selection.lazy.map { $0.text(for: field) }) {
                result[field] = mixed
            }
        }
        return result
    }

    /// Bilder der Auswahl: gleich bei allen (auch „keine Bilder“) oder gemischt.
    public static func mixedPictures(_ selection: [TagValues]) -> MixedValue<[EmbeddedPicture]>? {
        MixedValue<[EmbeddedPicture]>.combine(selection.lazy.map(\.pictures))
    }

    /// Werte, die bei allen ausgewählten Titeln gleich sind; gemischte Felder bleiben leer.
    /// Dient als Ausgangszustand des Formulars für die Mehrfachbearbeitung.
    public static func commonValues(_ selection: [TagValues]) -> TagValues {
        var values = TagValues()
        for (field, mixed) in mixedValues(selection) {
            if case .same(let text) = mixed { values.setText(text, for: field) }
        }
        if case .same(let pictures)? = mixedPictures(selection) { values.pictures = pictures }
        return values
    }

    /// Erzeugt die Bearbeitung aus dem Formular der Mehrfachbearbeitung: Nur Felder, deren Text sich
    /// gegenüber dem Ausgangszustand geändert hat, werden geschrieben. Ein gemischtes Feld, das der
    /// Nutzer nicht angefasst hat (Text `nil`), bleibt bei jedem Titel unverändert.
    /// - Parameters:
    ///   - original: Ergebnis von `mixedValues` der Auswahl.
    ///   - edited: Text je Feld aus dem Formular (`nil` = nicht angefasst).
    ///   - multipleTracks: Bei mehreren Titeln werden Felder, die je Titel verschieden sein müssen
    ///     (`TagField.isPerTrackOnly`, z. B. Titel), nie gemeinsam gesetzt.
    public static func edit(
        original: [TagField: MixedValue<String>],
        edited: [TagField: String?],
        multipleTracks: Bool,
        pictures: PictureChange = .keep
    ) -> TagEdit {
        var values = TagValues()
        var fields = Set<TagField>()
        for (field, newText) in edited {
            guard let newText else { continue }
            if multipleTracks && field.isPerTrackOnly { continue }
            var probe = TagValues()
            probe.setText(newText, for: field)
            let normalized = probe.text(for: field)
            if case .same(let old)? = original[field], old == normalized { continue }
            if original[field] == nil && normalized.isEmpty { continue }
            values.setText(newText, for: field)
            fields.insert(field)
        }
        return TagEdit(values: values, fields: fields, pictures: pictures)
    }

    // MARK: - Kopieren und Einfügen

    /// Zwischenablage für Tag-Felder („Tags kopieren“ → „Tags einfügen“).
    public struct Clipboard: Hashable, Codable, Sendable {
        /// Text je Feld (Schlüssel = `TagField.rawValue`).
        public var texts: [String: String]
        public var pictures: [EmbeddedPictureData]?

        public init(texts: [String: String], pictures: [EmbeddedPictureData]? = nil) {
            self.texts = texts
            self.pictures = pictures
        }

        public var fields: Set<TagField> { Set(texts.keys.compactMap(TagField.init(rawValue:))) }
    }

    /// Bild in der Zwischenablage (Codable-Fassung von `EmbeddedPicture`).
    public struct EmbeddedPictureData: Hashable, Codable, Sendable {
        public var kind: Int
        public var mimeType: String
        public var description: String
        public var data: Data

        public init(_ p: EmbeddedPicture) {
            kind = p.kind.rawValue
            mimeType = p.mimeType
            description = p.description
            data = p.data
        }

        public var picture: EmbeddedPicture {
            EmbeddedPicture(kind: PictureKind(rawValue: kind) ?? .other, mimeType: mimeType, description: description, data: data)
        }
    }

    /// Felder eines Titels kopieren (Standard: alle außer den je Titel verschiedenen; optional mit Bildern).
    public static func copy(_ values: TagValues, fields: Set<TagField>? = nil, includePictures: Bool = false) -> Clipboard {
        let chosen = fields ?? Set(TagField.allCases.filter { !$0.isPerTrackOnly })
        var texts: [String: String] = [:]
        for field in TagField.allCases where chosen.contains(field) {
            texts[field.rawValue] = values.text(for: field)
        }
        return Clipboard(texts: texts, pictures: includePictures ? values.pictures.map(EmbeddedPictureData.init) : nil)
    }

    /// Bearbeitung aus der Zwischenablage. Bei mehreren Zieltiteln werden je Titel verschiedene Felder
    /// (Titel, Liedtext, ISRC …) ausgelassen.
    public static func paste(_ clipboard: Clipboard, multipleTracks: Bool) -> TagEdit {
        var values = TagValues()
        var fields = Set<TagField>()
        for field in TagField.allCases {
            guard let text = clipboard.texts[field.rawValue] else { continue }
            if multipleTracks && field.isPerTrackOnly { continue }
            values.setText(text, for: field)
            fields.insert(field)
        }
        let pictures: PictureChange = clipboard.pictures.map { .replaceAll($0.map(\.picture)) } ?? .keep
        return TagEdit(values: values, fields: fields, pictures: pictures)
    }
}
