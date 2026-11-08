import Foundation
import MLCore
import MLStudio
import MLTags

/// Schreibt Metadaten und Cover in eine fertige Datei (über MLTags/TagLib).
enum StudioTagWriter {
    /// Baut die Bearbeitung: ohne `copyFrom` nur die nicht leeren Felder aus `metadata`; mit `copyFrom`
    /// alle Tags des Originals (inkl. Liedtext, Sortierfelder, Bilder) und darüber die nicht leeren Felder
    /// aus `metadata`. Cover, die kein JPEG/PNG sind, werden in JPEG umgewandelt.
    static func edit(metadata: StudioMetadata, copyFrom: URL?) -> TagEdit? {
        let newCover = metadata.cover.flatMap(CoverImage.embeddable)
        var overlayMeta = metadata
        overlayMeta.cover = newCover?.data
        let overlay = overlayMeta.tagEdit(coverMimeType: newCover?.mimeType)

        guard let copyFrom, let original = try? TagFile.read(url: copyFrom).values else {
            return overlay.isEmpty ? nil : overlay
        }
        var values = original
        values.merge(overlay.values, fields: overlay.fields)
        var pictures: [EmbeddedPicture] = original.pictures.compactMap { p in
            guard let converted = CoverImage.embeddable(p.data) else { return nil }
            return EmbeddedPicture(kind: p.kind, mimeType: converted.mimeType, description: p.description, data: converted.data)
        }
        if let newCover {
            let cover = EmbeddedPicture(kind: .frontCover, mimeType: newCover.mimeType, data: newCover.data)
            if let i = pictures.firstIndex(where: { $0.kind == .frontCover }) {
                pictures[i] = cover
            } else {
                pictures.insert(cover, at: 0)
            }
        }
        values.pictures = pictures
        guard hasContent(values) else { return nil }
        return TagEdit(values: values, fields: Set(TagField.allCases), pictures: .replaceAll(pictures))
    }

    /// Enthält mindestens ein Feld oder ein Bild?
    static func hasContent(_ v: TagValues) -> Bool {
        if !v.pictures.isEmpty || v.compilation { return true }
        return TagField.allCases.contains { $0 != .compilation && !v.text(for: $0).isEmpty }
    }

    /// Schreibt die Tags. Rückgabe: true, wenn Felder oder Bilder geschrieben wurden.
    static func write(to url: URL, format: StudioFormat, metadata: StudioMetadata, copyFrom: URL?) throws -> Bool {
        guard format.supportsTags, let edit = edit(metadata: metadata, copyFrom: copyFrom) else { return false }
        do {
            let report = try TagFile.write(url: url, edit: edit)
            return !report.writtenFields.isEmpty || report.picturesWritten
        } catch {
            throw StudioError.encodeFailed("Tags konnten nicht geschrieben werden: \(error.localizedDescription)")
        }
    }
}
