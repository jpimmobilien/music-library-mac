import Foundation
import MLCore
import TagBridge

/// Kapitelmarken für Hörbücher und Hörspiele: MP3 (ID3v2 CHAP + CTOC) und M4A/M4B (Nero-Kapitel und
/// QuickTime-Kapitelspur, wie sie Apple Bücher/Musik lesen). Vorhandene Kapitel werden ersetzt, alle anderen Tags
/// bleiben unverändert.
public enum ChapterWriter {
    public struct Chapter: Hashable, Sendable {
        public var title: String
        /// Beginn in Sekunden.
        public var start: Double
        public init(title: String, start: Double) {
            self.title = title
            self.start = start
        }
    }

    /// Dateiendungen, in die Kapitel geschrieben werden können.
    public static let supportedExtensions: Set<String> = ["mp3", "m4a", "m4b", "mp4"]

    public static func write(_ chapters: [Chapter], total: Double, to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw TagError.unsupportedFormat(path: url.path) }
        let sorted = chapters.sorted { $0.start < $1.start }
        let titles = sorted.map { strdup($0.title) }
        defer { titles.forEach { free($0) } }
        let starts = sorted.map { UInt32(max(0, min(Double(UInt32.max - 1), ($0.start * 1000).rounded()))) }
        let totalMs = UInt32(max(Double(starts.last ?? 0) + 1, min(Double(UInt32.max - 1), (total * 1000).rounded())))
        let status: TBStatus = sorted.isEmpty
            ? url.path.withCString { tb_write_chapters($0, 0, nil, nil, totalMs) }
            : titles.withUnsafeBufferPointer { tp in
            tp.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: titles.count) { titlePtr in
                starts.withUnsafeBufferPointer { sp in
                    url.path.withCString { tb_write_chapters($0, sorted.count, titlePtr, sp.baseAddress, totalMs) }
                }
            }
        }
        guard status == TB_OK else {
            throw BridgeFile.error(for: status, path: url.path, message: String(cString: tb_status_message(status)))
        }
    }
}
