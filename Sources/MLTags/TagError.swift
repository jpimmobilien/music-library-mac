import Foundation

/// Fehler beim Lesen, Schreiben, Sichern und Wiederherstellen von Tags.
///
/// `localizedDescription` liefert deutsche Texte für die Anzeige. Bei jedem Fehler während
/// des Schreibens bleibt die Originaldatei unverändert.
public enum TagError: Error, Equatable, Sendable {
    /// Die Datei existiert nicht.
    case fileNotFound(path: String)
    /// Der Pfad ist keine normale Datei (z. B. ein Ordner).
    case notAFile(path: String)
    /// Die Datei kann nicht geöffnet werden (Berechtigung, E/A-Fehler).
    case cannotOpen(path: String)
    /// Das Dateiformat wird nicht unterstützt.
    case unsupportedFormat(path: String)
    /// Die Datei ist beschädigt oder keine gültige Audiodatei.
    case invalidFile(path: String)
    /// Das Format kann (in dieser Datei) nicht beschrieben werden; `reason` aus TagLib/Bridge.
    case formatNotWritable(path: String, reason: String)
    /// Die Datei ist schreibgeschützt.
    case fileReadOnly(path: String)
    /// Der Ordner der Datei ist schreibgeschützt (temporäre Kopie/Ersetzen nicht möglich).
    case directoryNotWritable(path: String)
    /// Nicht genügend freier Speicherplatz für Sicherung und temporäre Kopie.
    case insufficientDiskSpace(path: String, required: Int64, available: Int64)
    /// Die Sicherungskopie konnte nicht angelegt werden.
    case backupFailed(path: String, reason: String)
    /// Schreiben der Tags (in die temporäre Kopie) ist fehlgeschlagen.
    case writeFailed(path: String, reason: String)
    /// Nach dem Schreiben stimmen Felder, Bilder oder Audiodaten nicht.
    case verificationFailed(path: String, details: [String])
    /// Die Originaldatei wurde während der Bearbeitung von außen verändert.
    case originalModified(path: String)
    /// Das Ersetzen der Originaldatei ist fehlgeschlagen.
    case replaceFailed(path: String, reason: String)
    /// Das Journal konnte nicht geschrieben/gelesen werden.
    case journalFailed(reason: String)
    /// Die Bearbeitung enthält keine Änderungen.
    case nothingToWrite(path: String)
    /// Für diese Stapel-ID gibt es kein Journal (mehr).
    case batchNotFound(batchID: UUID)
    /// Die Sicherungskopie fehlt.
    case backupMissing(path: String)
    /// Die Sicherungskopie ist beschädigt (Prüfsumme stimmt nicht).
    case backupCorrupted(path: String)
    /// Die Datei wurde nach der Bearbeitung erneut verändert (Rückgängig nicht sicher möglich).
    case modifiedSinceWrite(path: String)
    /// Nach dem Wiederherstellen ist die Datei nicht bytegleich mit der Sicherung.
    case restoreVerificationFailed(path: String)
    /// Unerwarteter interner Fehler.
    case internalError(message: String)

    /// Pfad der betroffenen Datei (falls vorhanden).
    public var path: String? {
        switch self {
        case .fileNotFound(let p), .notAFile(let p), .cannotOpen(let p), .unsupportedFormat(let p),
             .invalidFile(let p), .fileReadOnly(let p), .directoryNotWritable(let p),
             .originalModified(let p), .nothingToWrite(let p), .backupMissing(let p),
             .backupCorrupted(let p), .modifiedSinceWrite(let p), .restoreVerificationFailed(let p):
            return p
        case .formatNotWritable(let p, _), .backupFailed(let p, _), .writeFailed(let p, _),
             .replaceFailed(let p, _):
            return p
        case .insufficientDiskSpace(let p, _, _), .verificationFailed(let p, _):
            return p
        case .journalFailed, .batchNotFound, .internalError:
            return nil
        }
    }
}

extension TagError: LocalizedError {
    public var errorDescription: String? {
        func name(_ path: String) -> String { (path as NSString).lastPathComponent }
        func size(_ bytes: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        switch self {
        case .fileNotFound(let p):
            return "Die Datei „\(name(p))“ wurde nicht gefunden."
        case .notAFile(let p):
            return "„\(name(p))“ ist keine Datei."
        case .cannotOpen(let p):
            return "Die Datei „\(name(p))“ kann nicht geöffnet werden (fehlende Berechtigung?)."
        case .unsupportedFormat(let p):
            return "Das Dateiformat von „\(name(p))“ wird nicht unterstützt."
        case .invalidFile(let p):
            return "Die Datei „\(name(p))“ ist beschädigt oder keine gültige Audiodatei."
        case .formatNotWritable(let p, let reason):
            return "Die Tags von „\(name(p))“ können nicht geschrieben werden (\(reason))."
        case .fileReadOnly(let p):
            return "Die Datei „\(name(p))“ ist schreibgeschützt."
        case .directoryNotWritable(let p):
            return "Der Ordner von „\(name(p))“ ist schreibgeschützt."
        case .insufficientDiskSpace(let p, let required, let available):
            return "Nicht genügend freier Speicherplatz, um „\(name(p))“ sicher zu bearbeiten "
                + "(benötigt: \(size(required)), frei: \(size(available)))."
        case .backupFailed(let p, let reason):
            return "Die Sicherungskopie von „\(name(p))“ konnte nicht angelegt werden: \(reason)"
        case .writeFailed(let p, let reason):
            return "Die Tags von „\(name(p))“ konnten nicht geschrieben werden: \(reason) "
                + "Die Originaldatei wurde nicht verändert."
        case .verificationFailed(let p, let details):
            return "Die Prüfung nach dem Schreiben von „\(name(p))“ ist fehlgeschlagen ("
                + details.prefix(3).joined(separator: "; ")
                + (details.count > 3 ? " …" : "") + "). Die Originaldatei wurde nicht verändert."
        case .originalModified(let p):
            return "„\(name(p))“ wurde während der Bearbeitung von einem anderen Programm geändert. "
                + "Die Änderung wurde nicht übernommen."
        case .replaceFailed(let p, let reason):
            return "Die Datei „\(name(p))“ konnte nicht ersetzt werden: \(reason) "
                + "Die Originaldatei wurde nicht verändert."
        case .journalFailed(let reason):
            return "Das Änderungsprotokoll konnte nicht gespeichert werden: \(reason)"
        case .nothingToWrite(let p):
            return "Für „\(name(p))“ gibt es keine Änderungen."
        case .batchNotFound:
            return "Für diese Bearbeitung gibt es keine Sicherung mehr."
        case .backupMissing(let p):
            return "Die Sicherungskopie von „\(name(p))“ fehlt."
        case .backupCorrupted(let p):
            return "Die Sicherungskopie von „\(name(p))“ ist beschädigt (Prüfsumme stimmt nicht)."
        case .modifiedSinceWrite(let p):
            return "„\(name(p))“ wurde nach der Bearbeitung erneut verändert. "
                + "Das Rückgängigmachen wurde für diese Datei nicht ausgeführt."
        case .restoreVerificationFailed(let p):
            return "„\(name(p))“ konnte nicht bytegleich wiederhergestellt werden."
        case .internalError(let message):
            return "Interner Fehler: \(message)"
        }
    }
}
