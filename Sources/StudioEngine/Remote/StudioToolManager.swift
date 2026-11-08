import Foundation
import MLCore
import MLStudio
#if canImport(Darwin)
import Darwin
#endif

/// Eine Veröffentlichung eines Werkzeugs (Adresse des Programms und der Prüfsummenliste).
public struct ToolRelease: Hashable, Sendable {
    /// Version ohne führendes „v“ (nil, wenn unbekannt – dann wird immer geladen).
    public var version: String?
    public var binaryURL: URL
    public var checksumURL: URL
    /// Dateiname in der Prüfsummenliste.
    public var assetName: String
    /// SHA-256 aus der GitHub-API (zusätzliche Gegenprüfung), falls angegeben.
    public var digest: String?

    public init(version: String?, binaryURL: URL, checksumURL: URL, assetName: String, digest: String? = nil) {
        self.version = version
        self.binaryURL = binaryURL
        self.checksumURL = checksumURL
        self.assetName = assetName
        self.digest = digest
    }
}

/// Woher neue Versionen kommen (GitHub; für Tests austauschbar).
public protocol ToolReleaseSource: Sendable {
    func ytDlp() async throws -> ToolRelease
    /// `arch`: „aarch64“ oder „x86_64“.
    func deno(arch: String) async throws -> ToolRelease
}

/// Offizielle GitHub-Veröffentlichungen von yt-dlp und Deno.
public struct GitHubToolReleases: ToolReleaseSource {
    public init() {}

    static let ytDlpAPI = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    static let denoAPI = URL(string: "https://api.github.com/repos/denoland/deno/releases/latest")!

    public func ytDlp() async throws -> ToolRelease {
        let asset = "yt-dlp_macos"
        if let r = try? await fromAPI(Self.ytDlpAPI, asset: asset, checksumAsset: "SHA2-256SUMS") { return r }
        // Rückfall (z. B. Ratenbegrenzung der API): feste Adressen der neuesten Veröffentlichung
        let base = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/"
        return ToolRelease(version: nil, binaryURL: URL(string: base + asset)!, checksumURL: URL(string: base + "SHA2-256SUMS")!, assetName: asset)
    }

    public func deno(arch: String) async throws -> ToolRelease {
        let asset = "deno-\(arch)-apple-darwin.zip"
        if let r = try? await fromAPI(Self.denoAPI, asset: asset, checksumAsset: asset + ".sha256sum") { return r }
        let base = "https://github.com/denoland/deno/releases/latest/download/"
        return ToolRelease(version: nil, binaryURL: URL(string: base + asset)!, checksumURL: URL(string: base + asset + ".sha256sum")!, assetName: asset)
    }

    private struct Release: Decodable {
        var tag_name: String
        var assets: [Asset]
        struct Asset: Decodable {
            var name: String
            var browser_download_url: String
            var digest: String?
        }
    }

    private func fromAPI(_ api: URL, asset: String, checksumAsset: String) async throws -> ToolRelease {
        let data = try await StudioHTTP.data(from: api, maxBytes: 8 * 1024 * 1024, timeout: 20, accept: "application/vnd.github+json")
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let a = release.assets.first(where: { $0.name == asset }), let c = release.assets.first(where: { $0.name == checksumAsset }),
              let binaryURL = URL(string: a.browser_download_url), let checksumURL = URL(string: c.browser_download_url),
              binaryURL.host == "github.com", checksumURL.host == "github.com" else {
            throw StudioError.other("Die Veröffentlichung enthält „\(asset)“ nicht.")
        }
        var digest: String?
        if let d = a.digest?.lowercased(), d.hasPrefix("sha256:") { digest = String(d.dropFirst(7)) }
        let tag = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return ToolRelease(version: tag, binaryURL: binaryURL, checksumURL: checksumURL, assetName: asset, digest: digest)
    }
}

/// yt-dlp und Deno finden, installieren, aktualisieren und entfernen.
///
/// Reihenfolge der Suche: von der App installierte Werkzeuge in `supportDirectory`, sonst das System
/// (Homebrew, `~/.local/bin` …). FFmpeg wird nur erkannt, nie installiert. Installiert wird nur auf
/// ausdrücklichen Aufruf; jede Datei wird per SHA-256 geprüft, erst in einem temporären Ordner vorbereitet
/// und am Ende ausgetauscht – bei einem Fehler bleibt der vorige Zustand erhalten.
public actor StudioToolManager: StudioToolManaging {
    public let supportDirectory: URL
    /// Suchorte für Systeminstallationen (Apps aus dem Finder haben keinen sinnvollen PATH).
    public let systemSearchPaths: [String]
    private let releases: ToolReleaseSource
    private var versionCache: [String: (stamp: String, version: String?)] = [:]
    private var installing = false

    /// `supportDirectory`: z. B. ~/Library/Application Support/Music Library/Audio Studio/Tools
    public init(supportDirectory: URL, systemSearchPaths: [String]? = nil, releases: ToolReleaseSource = GitHubToolReleases()) {
        self.supportDirectory = supportDirectory
        self.systemSearchPaths = systemSearchPaths ?? Self.defaultSystemSearchPaths
        self.releases = releases
    }

    public static var defaultSystemSearchPaths: [String] {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.deno/bin", "/opt/local/bin"]
    }

    public nonisolated var managedYtDlp: URL { supportDirectory.appendingPathComponent("yt-dlp") }
    public nonisolated var managedDeno: URL { supportDirectory.appendingPathComponent("deno") }
    /// Eigener Zwischenspeicher von yt-dlp (statt ~/.cache).
    public nonisolated var cacheDirectory: URL { supportDirectory.appendingPathComponent("yt-dlp-cache", isDirectory: true) }

    /// Gefundene Programme für Aufrufe.
    public struct Paths: Sendable {
        public var ytDlp: String?
        public var deno: String?
        public var ffmpeg: String?
        public var cacheDirectory: URL
    }

    public func paths() -> Paths {
        Paths(ytDlp: locate("yt-dlp", managed: managedYtDlp)?.path, deno: locate("deno", managed: managedDeno)?.path,
              ffmpeg: locate("ffmpeg", managed: nil)?.path, cacheDirectory: cacheDirectory)
    }

    /// Programm suchen: zuerst die von der App installierte Datei, dann die Systemorte.
    func locate(_ name: String, managed: URL?) -> (path: String, origin: StudioToolStatus.Origin)? {
        let fm = FileManager.default
        if let managed, fm.isExecutableFile(atPath: managed.path) { return (managed.path, .managed) }
        for dir in systemSearchPaths {
            let path = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue, fm.isExecutableFile(atPath: path) {
                return (path, .system)
            }
        }
        return nil
    }

    public func status() async -> StudioToolStatus {
        var s = StudioToolStatus()
        if let yt = locate("yt-dlp", managed: managedYtDlp) {
            s.ytDlpPath = yt.path
            s.ytDlpOrigin = yt.origin
            s.ytDlpVersion = await version(of: yt.path, tool: .ytDlp)
        }
        if let deno = locate("deno", managed: managedDeno) {
            s.denoPath = deno.path
            s.denoOrigin = deno.origin
            s.denoVersion = await version(of: deno.path, tool: .deno)
        }
        s.ffmpegPath = locate("ffmpeg", managed: nil)?.path
        return s
    }

    enum Tool { case ytDlp, deno }

    /// Version über `--version` (mit Zeitlimit; zwischengespeichert, solange sich die Datei nicht ändert).
    func version(of path: String, tool: Tool) async -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let stamp = "\((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)-\((attrs?[.size] as? NSNumber)?.int64Value ?? 0)"
        if let cached = versionCache[path], cached.stamp == stamp { return cached.version }
        let result = try? await StudioProcess.run(path, ["--version"], environment: StudioProcess.environment(), timeout: 30)
        var v: String?
        if let result, result.status == 0, !result.timedOut {
            v = Self.parseVersion(result.stdout, tool: tool)
        }
        versionCache[path] = (stamp, v)
        return v
    }

    /// „2026.10.21“ (yt-dlp) bzw. „deno 2.9.8 (stable, release, aarch64-apple-darwin)“ → „2.9.8“.
    static func parseVersion(_ output: String, tool: Tool) -> String? {
        guard let first = output.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return nil }
        switch tool {
        case .ytDlp:
            return first
        case .deno:
            let parts = first.split(separator: " ")
            if parts.count >= 2, parts[0].lowercased() == "deno" { return String(parts[1]) }
            return first
        }
    }

    static var denoArch: String {
        #if arch(arm64)
        return "aarch64"
        #else
        return "x86_64"
        #endif
    }

    // MARK: Installieren

    public func installOrUpdate(progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> StudioToolStatus {
        guard !installing else { throw StudioError.other("Die Werkzeuge werden bereits installiert.") }
        installing = true
        defer { installing = false }
        let fm = FileManager.default
        try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        removeStaleStaging()
        let staging = supportDirectory.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // yt-dlp
        progress(ToolInstallProgress(step: "yt-dlp: neueste Version wird gesucht …", fraction: 0.01))
        let yt = try await releases.ytDlp()
        try Task.checkCancellation()
        var stagedYt: URL?
        let currentYt = fm.isExecutableFile(atPath: managedYtDlp.path) ? await version(of: managedYtDlp.path, tool: .ytDlp) : nil
        if let v = yt.version, let current = currentYt, current == v {
            progress(ToolInstallProgress(step: "yt-dlp \(v) ist aktuell", fraction: 0.45))
        } else {
            stagedYt = try await stage(yt, name: "yt-dlp", binaryName: "yt-dlp", unzip: false, staging: staging, range: 0.02...0.45, progress: progress)
        }

        // Deno (JavaScript-Laufzeit für YouTube)
        progress(ToolInstallProgress(step: "Deno: neueste Version wird gesucht …", fraction: 0.46))
        let deno = try await releases.deno(arch: Self.denoArch)
        try Task.checkCancellation()
        var stagedDeno: URL?
        let currentDeno = fm.isExecutableFile(atPath: managedDeno.path) ? await version(of: managedDeno.path, tool: .deno) : nil
        if let v = deno.version, let current = currentDeno, current == v {
            progress(ToolInstallProgress(step: "Deno \(v) ist aktuell", fraction: 0.95))
        } else {
            stagedDeno = try await stage(deno, name: "Deno", binaryName: "deno", unzip: true, staging: staging, range: 0.47...0.95, progress: progress)
        }

        // Erst jetzt austauschen – vorher bleibt alles, wie es war.
        try Task.checkCancellation()
        progress(ToolInstallProgress(step: "Werkzeuge werden installiert …", fraction: 0.97))
        if let s = stagedYt { try Self.replace(managedYtDlp, with: s) }
        if let s = stagedDeno { try Self.replace(managedDeno, with: s) }
        versionCache.removeAll()
        progress(ToolInstallProgress(step: "Fertig", fraction: 1))
        return await status()
    }

    /// Laden, Prüfsumme prüfen, ggf. entpacken, ausführbar machen und einmal starten (`--version`).
    private func stage(_ release: ToolRelease, name: String, binaryName: String, unzip: Bool, staging: URL,
                       range: ClosedRange<Double>, progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> URL {
        let fm = FileManager.default
        let dir = staging.appendingPathComponent(binaryName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let label = release.version.map { "\(name) \($0)" } ?? name
        let span = range.upperBound - range.lowerBound

        progress(ToolInstallProgress(step: "\(label): Prüfsumme wird geladen …", fraction: range.lowerBound))
        let sums = try await StudioHTTP.data(from: release.checksumURL, maxBytes: 1024 * 1024, timeout: 20)
        guard let expected = ToolChecksum.expected(in: String(decoding: sums, as: UTF8.self), for: release.assetName) else {
            throw StudioError.other("Für \(name) wurde keine Prüfsumme gefunden. Aus Sicherheitsgründen wurde nichts installiert.")
        }
        if let digest = release.digest, ToolChecksum.isHex64(digest), digest != expected {
            throw StudioError.other("Die Prüfsummen von \(name) widersprechen sich. Aus Sicherheitsgründen wurde nichts installiert.")
        }

        let download = dir.appendingPathComponent(release.assetName)
        try await StudioHTTP.download(from: release.binaryURL, to: download) { done, total in
            let f = total.map { Double(done) / Double(max($0, 1)) } ?? 0
            let amount = total.map { "\(Formatting.fileSize(done)) von \(Formatting.fileSize($0))" } ?? Formatting.fileSize(done)
            progress(ToolInstallProgress(step: "\(label) wird geladen … \(amount)", fraction: range.lowerBound + span * 0.85 * min(1, f)))
        }
        try Task.checkCancellation()

        progress(ToolInstallProgress(step: "\(label): Prüfsumme wird geprüft …", fraction: range.lowerBound + span * 0.88))
        try ToolChecksum.verify(file: download, expected: expected, name: name)

        var binary = download
        if unzip {
            let out = dir.appendingPathComponent("unpacked", isDirectory: true)
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            let r = try await StudioProcess.run("/usr/bin/ditto", ["-x", "-k", download.path, out.path], timeout: 300)
            guard r.status == 0 else { throw StudioError.other("\(name) konnte nicht entpackt werden. \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))") }
            guard let found = Self.findFile(named: binaryName, in: out) else {
                throw StudioError.other("Im Archiv von \(name) wurde das Programm nicht gefunden.")
            }
            binary = found
        }
        try Self.makeExecutable(binary)

        progress(ToolInstallProgress(step: "\(label) wird geprüft …", fraction: range.lowerBound + span * 0.94))
        let check = try await StudioProcess.run(binary.path, ["--version"], environment: StudioProcess.environment(), timeout: 120)
        guard check.status == 0, !check.timedOut, !check.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudioError.other("\(name) ließ sich nach dem Laden nicht starten. Es wurde nichts installiert.")
        }
        let ready = staging.appendingPathComponent(binaryName + ".ready")
        try? fm.removeItem(at: ready)
        try fm.moveItem(at: binary, to: ready)
        return ready
    }

    static func findFile(named name: String, in dir: URL) -> URL? {
        let direct = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == name {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return url }
        }
        return nil
    }

    static func makeExecutable(_ file: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: file.path)
        // Die Datei wurde auf Wunsch des Nutzers von der offiziellen Veröffentlichung geladen und geprüft.
        _ = file.path.withCString { removexattr($0, "com.apple.quarantine", 0) }
    }

    /// Vorhandene Datei atomar ersetzen bzw. neu anlegen.
    static func replace(_ destination: URL, with staged: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
        try makeExecutable(destination)
    }

    private func removeStaleStaging() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: supportDirectory, includingPropertiesForKeys: nil, options: []) else { return }
        for item in items where item.lastPathComponent.hasPrefix(".install-") { try? fm.removeItem(at: item) }
    }

    // MARK: Entfernen

    /// Entfernt nur die von der App installierten Dateien (Werkzeuge im Systemordner bleiben unberührt).
    public func removeManaged() async throws -> StudioToolStatus {
        guard !installing else { throw StudioError.other("Die Werkzeuge werden gerade installiert.") }
        let fm = FileManager.default
        for url in [managedYtDlp, managedDeno, cacheDirectory] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        removeStaleStaging()
        versionCache.removeAll()
        return await status()
    }
}
