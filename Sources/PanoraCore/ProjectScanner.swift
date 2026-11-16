import Foundation

// =============================================================================================
// Projektanalyse (nur lesend): Ordner durchsuchen, Projektart und Sprachen erkennen, Struktur und
// wichtige Dateien als Kontext für das Modell aufbereiten. Läuft komplett offline.
// =============================================================================================

public struct LanguageStat: Codable, Equatable, Sendable, Hashable {
    public var name: String
    public var files: Int
    public var bytes: Int64

    public init(name: String, files: Int, bytes: Int64) {
        self.name = name
        self.files = files
        self.bytes = bytes
    }
}

public struct ProjectSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var kind: String
    public var fileCount: Int
    public var totalBytes: Int64
    public var languages: [LanguageStat]
    public var keyFiles: [String]
    public var tree: [String]
    public var files: [String]
    public var readme: String?
    public var scannedAt: Date
    public var truncated: Bool

    public init(path: String, name: String, kind: String, fileCount: Int, totalBytes: Int64, languages: [LanguageStat],
                keyFiles: [String], tree: [String], files: [String], readme: String?, scannedAt: Date, truncated: Bool) {
        self.path = path
        self.name = name
        self.kind = kind
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.languages = languages
        self.keyFiles = keyFiles
        self.tree = tree
        self.files = files
        self.readme = readme
        self.scannedAt = scannedAt
        self.truncated = truncated
    }
}

public enum ProjectScanner {
    public static let skipDirectories: Set<String> = [".git", ".build", "build", "DerivedData", "node_modules", ".gradle", "Pods",
                                                       ".idea", ".swiftpm", "dist", "out", ".venv", "venv", "__pycache__",
                                                       "Carthage", ".next", "target", ".cxx", ".externalNativeBuild", "xcuserdata"]

    static let languages: [String: String] = [
        "swift": "Swift", "kt": "Kotlin", "kts": "Kotlin Script", "java": "Java", "xml": "XML", "gradle": "Gradle",
        "m": "Objective-C", "mm": "Objective-C++", "h": "C-Header", "c": "C", "cpp": "C++", "cc": "C++", "rs": "Rust",
        "go": "Go", "py": "Python", "js": "JavaScript", "jsx": "JavaScript", "ts": "TypeScript", "tsx": "TypeScript",
        "json": "JSON", "yml": "YAML", "yaml": "YAML", "md": "Markdown", "html": "HTML", "css": "CSS", "scss": "SCSS",
        "sql": "SQL", "sh": "Shell", "plist": "Property List", "toml": "TOML", "dart": "Dart", "rb": "Ruby", "php": "PHP",
        "cs": "C#", "vue": "Vue", "svelte": "Svelte", "txt": "Text", "strings": "Strings", "xcstrings": "String Catalog",
    ]

    static let keyFileNames: [String] = ["settings.gradle.kts", "settings.gradle", "build.gradle.kts", "build.gradle",
                                         "app/build.gradle.kts", "app/build.gradle", "gradle/libs.versions.toml",
                                         "AndroidManifest.xml", "Package.swift", "project.yml", "Podfile", "package.json",
                                         "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod", "pubspec.yaml",
                                         "Makefile", "Dockerfile"]

    public static func scan(at root: URL, maxFiles: Int = 20_000) -> ProjectSummary {
        let fm = FileManager.default
        var files: [String] = []
        var stats: [String: LanguageStat] = [:]
        var total: Int64 = 0
        var count = 0
        var truncated = false
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isRegularFileKey],
                                          options: [.skipsPackageDescendants]) {
            while let item = enumerator.nextObject() as? URL {
                let name = item.lastPathComponent
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isRegularFileKey])
                if values?.isDirectory == true {
                    if skipDirectories.contains(name) || name.hasSuffix(".xcassets") {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values?.isRegularFile ?? true else { continue }
                if name == ".DS_Store" { continue }
                count += 1
                if count > maxFiles { truncated = true; break }
                let size = Int64(values?.fileSize ?? 0)
                total += size
                var rel = item.resolvingSymlinksInPath().standardizedFileURL.path
                if rel.hasPrefix(rootPath) { rel = String(rel.dropFirst(rootPath.count)) }
                if rel.hasPrefix("/") { rel.removeFirst() }
                if files.count < 5_000 { files.append(rel) }
                let ext = (name as NSString).pathExtension.lowercased()
                if let lang = languages[ext] {
                    var s = stats[lang] ?? LanguageStat(name: lang, files: 0, bytes: 0)
                    s.files += 1
                    s.bytes += size
                    stats[lang] = s
                }
            }
        }
        files.sort()
        let keyFiles: [String] = keyFileNames.compactMap { key in
            if let exact = files.first(where: { $0 == key }) { return exact }
            guard !key.contains("/") else { return nil }
            return files.first { $0.hasSuffix("/" + key) && $0.split(separator: "/").count <= 4 }
        }
        let kind = detectKind(files: files, root: root)
        let tree = makeTree(files: files, limit: 140)
        var readme: String?
        if let readmePath = files.first(where: { $0.lowercased() == "readme.md" || $0.lowercased() == "readme" }) {
            readme = (try? String(contentsOf: root.appendingPathComponent(readmePath), encoding: .utf8)).map { String($0.prefix(6_000)) }
        }
        let langList = stats.values.sorted { $0.files == $1.files ? $0.name < $1.name : $0.files > $1.files }
        var unique: [String] = []
        for k in keyFiles where !unique.contains(k) { unique.append(k) }
        return ProjectSummary(path: root.path, name: root.lastPathComponent, kind: kind, fileCount: min(count, maxFiles),
                              totalBytes: total, languages: langList, keyFiles: unique, tree: tree, files: files, readme: readme,
                              scannedAt: Date(), truncated: truncated)
    }

    static func detectKind(files: [String], root: URL) -> String {
        let set = Set(files.map { ($0 as NSString).lastPathComponent })
        let hasAndroid = files.contains { $0.hasSuffix("AndroidManifest.xml") }
        if (set.contains("settings.gradle.kts") || set.contains("settings.gradle")) && hasAndroid { return "Android-App (Gradle)" }
        if set.contains("settings.gradle.kts") || set.contains("build.gradle.kts") || set.contains("build.gradle") { return "Gradle-Projekt" }
        if files.contains(where: { $0.contains(".xcodeproj/") }) || set.contains("project.yml") { return "Xcode-Projekt (Swift)" }
        if set.contains("Package.swift") { return "Swift-Paket" }
        if set.contains("pubspec.yaml") { return "Flutter/Dart" }
        if set.contains("package.json") { return "Node.js/Web" }
        if set.contains("pyproject.toml") || set.contains("requirements.txt") { return "Python" }
        if set.contains("Cargo.toml") { return "Rust" }
        if set.contains("go.mod") { return "Go" }
        return "Ordner"
    }

    static func makeTree(files: [String], limit: Int) -> [String] {
        var lines: [String] = []
        var seenDirs: Set<String> = []
        for path in files {
            let parts = path.split(separator: "/").map(String.init)
            // Ordner bis Tiefe 3 und Dateien bis Tiefe 2
            for depth in 0..<min(parts.count - 1, 3) {
                let dir = parts[0...depth].joined(separator: "/")
                if !seenDirs.contains(dir) {
                    seenDirs.insert(dir)
                    lines.append(String(repeating: "  ", count: depth) + parts[depth] + "/")
                }
            }
            if parts.count <= 2 {
                lines.append(String(repeating: "  ", count: parts.count - 1) + parts[parts.count - 1])
            }
            if lines.count >= limit { lines.append("…"); break }
        }
        return lines
    }

    /// Kontext für das Modell: Überblick, Struktur, README, Build-Dateien und gezielt angefragte Dateien.
    public static func contextText(_ summary: ProjectSummary, focus: [String] = [], budgetTokens: Int) -> String {
        let root = URL(fileURLWithPath: summary.path)
        var parts: [String] = []
        let langs = summary.languages.prefix(6).map { "\($0.name) \($0.files)" }.joined(separator: ", ")
        parts.append("Projekt „\(summary.name)“ – \(summary.kind), \(summary.fileCount) Dateien (\(Formatting.bytes(summary.totalBytes))). Sprachen: \(langs).")
        parts.append("Struktur:\n" + summary.tree.joined(separator: "\n"))
        var used = TaskAnalyzer.estimateTokens(parts.joined(separator: "\n\n"))
        func add(_ title: String, _ text: String, share: Double) {
            let remaining = budgetTokens - used
            guard remaining > 200 else { return }
            let limited = ContextEngine.truncateToTokens(text, tokens: min(remaining, Int(Double(budgetTokens) * share)))
            let block = "--- \(title) ---\n" + limited
            parts.append(block)
            used += TaskAnalyzer.estimateTokens(block)
        }
        // Angefragte Dateien zuerst
        for wanted in focus {
            guard let match = summary.files.first(where: { $0 == wanted || $0.hasSuffix("/" + wanted) }) else { continue }
            if let text = try? String(contentsOf: root.appendingPathComponent(match), encoding: .utf8) {
                add(match, text, share: 0.35)
            }
        }
        if let readme = summary.readme { add("README", readme, share: 0.15) }
        for key in summary.keyFiles.prefix(6) {
            if let text = try? String(contentsOf: root.appendingPathComponent(key), encoding: .utf8) {
                add(key, text, share: 0.1)
            }
        }
        return ContextEngine.truncateToTokens(parts.joined(separator: "\n\n"), tokens: budgetTokens)
    }
}
