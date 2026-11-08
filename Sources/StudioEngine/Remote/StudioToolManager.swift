import Foundation
import MLStudio

/// yt-dlp und Deno finden, installieren, aktualisieren. (Platzhalter – wird vom Web-Teil ersetzt.)
public actor StudioToolManager: StudioToolManaging {
    public let supportDirectory: URL

    /// `supportDirectory`: z. B. ~/Library/Application Support/Music Library/Tools
    public init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    public func status() async -> StudioToolStatus { StudioToolStatus() }

    public func installOrUpdate(progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> StudioToolStatus {
        throw StudioError.other("Installation ist noch nicht verfügbar.")
    }

    public func removeManaged() async throws -> StudioToolStatus { StudioToolStatus() }
}
