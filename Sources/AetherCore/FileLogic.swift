import Foundation

// =============================================================================================
// Dateilogik ohne Oberfläche (Linux-testbar): eindeutige Namen, Namensprüfung, Stapel-Umbenennung.
// ORBIT überschreibt nie: Bei Namensgleichheit entsteht „Name 2“, „Name 3“ … wie im Finder („Beide behalten“).
// =============================================================================================

public enum FileNaming {
    /// Zerlegt „Bericht.final.pdf“ in („Bericht.final“, „pdf“). Ordner und Namen ohne Punkt: Endung leer.
    /// Führender Punkt (versteckte Datei „.zshrc“) zählt nicht als Endung.
    public static func split(_ name: String, isDirectory: Bool = false) -> (base: String, ext: String) {
        guard !isDirectory, let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    public static func join(_ base: String, _ ext: String) -> String {
        ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// Ein freier Name in einem Ordner: „Name“, sonst „Name 2“, „Name 3“ … (Endung bleibt erhalten).
    /// Vergleich ohne Groß-/Kleinschreibung (APFS und HFS+ sind standardmäßig so).
    public static func uniqueName(for name: String, existing: Set<String>, isDirectory: Bool = false) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var (base, ext) = split(name, isDirectory: isDirectory)
        var start = 2
        // „Bericht 2.pdf“ → weiterzählen statt „Bericht 2 2.pdf“
        if let space = base.lastIndex(of: " "), let number = Int(base[base.index(after: space)...]), number >= 2 {
            base = String(base[..<space])
            start = number + 1
        }
        var counter = start
        while true {
            let candidate = join("\(base) \(counter)", ext)
            if !taken.contains(candidate.lowercased()) { return candidate }
            counter += 1
        }
    }

    public enum Problem: Equatable, Sendable {
        case empty
        case containsSlash
        case containsColon
        case tooLong
        case reserved
        /// Kein Fehler, aber ein Hinweis: Namen mit Punkt am Anfang sind versteckt.
        case hidden
    }

    /// Prüft einen neuen Datei- oder Ordnernamen. `nil` = in Ordnung.
    public static func validate(_ name: String) -> Problem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if name == "." || name == ".." { return .reserved }
        if name.contains("/") { return .containsSlash }
        if name.contains(":") { return .containsColon }
        if name.utf8.count > 255 { return .tooLong }
        if name.hasPrefix(".") { return .hidden }
        return nil
    }

    /// Fehler, die eine Umbenennung verhindern (`hidden` ist nur ein Hinweis).
    public static func isBlocking(_ problem: Problem?) -> Bool {
        guard let problem else { return false }
        return problem != .hidden
    }
}

/// Stapel-Umbenennung wie im Finder: Text ersetzen, Text hinzufügen oder neu nummerieren.
public enum BatchRenameMode: Equatable, Sendable {
    case replace(find: String, with: String, caseSensitive: Bool)
    case add(text: String, atEnd: Bool)
    case format(base: String, start: Int, digits: Int, atEnd: Bool)
}

public struct BatchRenameEntry: Equatable, Sendable {
    public var original: String
    public var proposed: String
    public var problem: BatchRenameProblem?

    public init(original: String, proposed: String, problem: BatchRenameProblem?) {
        self.original = original
        self.proposed = proposed
        self.problem = problem
    }

    public var changes: Bool { original != proposed }
}

public enum BatchRenameProblem: Equatable, Sendable {
    case invalidName(FileNaming.Problem)
    /// Zwei Einträge bekämen denselben Namen.
    case duplicateInBatch
    /// Ein anderes Objekt im Ordner trägt den Namen bereits.
    case existsInFolder
}

public enum BatchRenamePlanner {
    /// Plant neue Namen. `items` = (Name, ist Ordner). `others` = Namen im Ordner, die nicht umbenannt werden.
    /// Endungen bleiben unverändert (wie im Finder).
    public static func plan(_ items: [(name: String, isDirectory: Bool)], mode: BatchRenameMode,
                            others: Set<String>) -> [BatchRenameEntry] {
        var proposals: [String] = []
        for (index, item) in items.enumerated() {
            let (base, ext) = FileNaming.split(item.name, isDirectory: item.isDirectory)
            let newBase: String
            switch mode {
            case let .replace(find, replacement, caseSensitive):
                if find.isEmpty {
                    newBase = base
                } else {
                    newBase = base.replacingOccurrences(of: find, with: replacement,
                                                        options: caseSensitive ? [] : [.caseInsensitive])
                }
            case let .add(text, atEnd):
                newBase = atEnd ? base + text : text + base
            case let .format(name, start, digits, atEnd):
                let number = String(format: "%0\(max(1, min(digits, 9)))ld", start + index)
                newBase = atEnd ? "\(name)\(number)" : "\(number)\(name)"
            }
            proposals.append(FileNaming.join(newBase, ext))
        }

        let othersLower = Set(others.map { $0.lowercased() })
        var counts: [String: Int] = [:]
        for proposal in proposals { counts[proposal.lowercased(), default: 0] += 1 }

        return zip(items, proposals).map { item, proposal in
            var problem: BatchRenameProblem?
            if let issue = FileNaming.validate(proposal), FileNaming.isBlocking(issue) {
                problem = .invalidName(issue)
            } else if (counts[proposal.lowercased()] ?? 0) > 1 {
                problem = .duplicateInBatch
            } else if proposal.lowercased() != item.name.lowercased(), othersLower.contains(proposal.lowercased()) {
                problem = .existsInFolder
            }
            return BatchRenameEntry(original: item.name, proposed: proposal, problem: problem)
        }
    }

    /// Ausführbar, wenn kein Eintrag einen Fehler hat und mindestens einer sich ändert. (Die App benennt in zwei
    /// Schritten über temporäre Namen um, damit Tausch-Umbenennungen A→B, B→A nicht kollidieren.)
    public static func canApply(_ entries: [BatchRenameEntry]) -> Bool {
        entries.allSatisfy { $0.problem == nil } && entries.contains { $0.changes }
    }
}

/// Darstellung der POSIX-Rechte („rwxr-xr-x“).
public enum PosixPermissions {
    public static func string(_ mode: Int) -> String {
        let symbols: [(Int, Character)] = [(0o400, "r"), (0o200, "w"), (0o100, "x"), (0o040, "r"), (0o020, "w"), (0o010, "x"),
                                           (0o004, "r"), (0o002, "w"), (0o001, "x")]
        return String(symbols.map { mode & $0.0 != 0 ? $0.1 : "-" })
    }
}

/// Pfadteile für die Pfadleiste: vom Wurzelordner bis zum aktuellen Ordner.
public enum PathTrail {
    /// „/Users/anna/Documents“ → ["/", "/Users", "/Users/anna", "/Users/anna/Documents"].
    public static func ancestors(of path: String) -> [String] {
        let standardized = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard standardized.hasPrefix("/") else { return [standardized] }
        var result = ["/"]
        var current = ""
        for part in standardized.split(separator: "/") {
            current += "/" + part
            result.append(current)
        }
        return result
    }

    /// Liegt `path` innerhalb von `folder` (oder ist er es)? Verhindert z. B. das Verschieben eines Ordners in sich selbst.
    public static func isInside(_ path: String, folder: String) -> Bool {
        let a = path.hasSuffix("/") ? path : path + "/"
        let b = folder.hasSuffix("/") ? folder : folder + "/"
        return a.hasPrefix(b)
    }
}
