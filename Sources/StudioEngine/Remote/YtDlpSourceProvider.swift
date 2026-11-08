import Foundation
import MLStudio

/// Internet-Quellen über yt-dlp (YouTube, SoundCloud, …); Spotify nur Metadaten. (Platzhalter – Web-Teil.)
public struct YtDlpSourceProvider: RemoteSourceProviding {
    public let tools: StudioToolManager

    public init(tools: StudioToolManager) {
        self.tools = tools
    }

    public func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo {
        throw StudioError.toolMissing("yt-dlp")
    }

    public func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        throw StudioError.toolMissing("yt-dlp")
    }

    public func thumbnail(for source: SourceInfo) async -> Data? { nil }
}
