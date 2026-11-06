import Foundation
import os

/// Strukturiertes Protokoll mit Datenschutz: Dateinamen und Inhalte werden nie protokolliert,
/// nur Vorgänge, Größen, Fehlercodes. Die letzten Einträge stehen im Diagnosebereich zur Verfügung.
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()

    enum Category: String, CaseIterable {
        case app = "App"
        case usb = "USB"
        case mtp = "MTP"
        case transfer = "Übertragung"
        case ui = "Oberfläche"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: Category
        let message: String
        let isError: Bool
    }

    @Published private(set) var entries: [Entry] = []
    private let lock = NSLock()
    private var buffer: [Entry] = []
    private let maxEntries = 600
    private let logger = Logger(subsystem: "de.androidbridge.app", category: "general")
    private var flushScheduled = false

    func log(_ category: Category, _ message: String, error: Bool = false) {
        let entry = Entry(date: Date(), category: category, message: message, isError: error)
        if error {
            logger.error("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
        } else {
            logger.info("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
        }
        lock.lock()
        buffer.append(entry)
        if buffer.count > maxEntries { buffer.removeFirst(buffer.count - maxEntries) }
        let needsFlush = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if needsFlush {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.flush() }
        }
    }

    private func flush() {
        lock.lock()
        let snapshot = buffer
        flushScheduled = false
        lock.unlock()
        entries = snapshot
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        entries = []
    }

    func exportText() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        lock.lock()
        let snapshot = buffer
        lock.unlock()
        return snapshot.map { "\(f.string(from: $0.date)) [\($0.category.rawValue)]\($0.isError ? " FEHLER" : "") \($0.message)" }
            .joined(separator: "\n")
    }
}
