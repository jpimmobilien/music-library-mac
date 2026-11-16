import Foundation
import AppKit
import PanoraCore

// =============================================================================================
// Unterhaltungen und Projekte – lokal gespeichert unter ~/Library/Application Support/Panora.
// =============================================================================================

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    private let folder: URL
    private let persist: Bool
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(persist: Bool = true) {
        self.persist = persist
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folder = base.appendingPathComponent("Panora/Chats")
        if persist { load() }
    }

    private func load() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var list: [Conversation] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let c = try? decoder.decode(Conversation.self, from: data) {
                list.append(c)
            }
        }
        conversations = list.sorted { $0.updated > $1.updated }
    }

    func conversation(_ id: UUID) -> Conversation? { conversations.first { $0.id == id } }

    func upsert(_ conversation: Conversation, save: Bool = true) {
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        conversations.sort { $0.updated > $1.updated }
        if save { write(conversation) }
    }

    private func write(_ conversation: Conversation) {
        guard persist, !conversation.messages.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? encoder.encode(conversation) {
            try? data.write(to: folder.appendingPathComponent("\(conversation.id.uuidString).json"), options: .atomic)
        }
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        guard persist else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id.uuidString).json"))
    }

    func toggleFavorite(_ id: UUID) {
        guard var c = conversation(id) else { return }
        c.favorite.toggle()
        upsert(c)
    }

    /// Export als Markdown (Modell an jeder Antwort sichtbar).
    func markdown(_ c: Conversation) -> String {
        var out = "# \(c.title)\n\n"
        for m in c.messages {
            switch m.role {
            case .user: out += "**Du:**\n\n\(m.text)\n\n"
            case .assistant: out += "**\(m.modelName ?? "Panora")** (lokal):\n\n\(m.text)\n\n"
            case .expert: out += "**Zweitmeinung – \(m.expertProvider ?? "extern")**:\n\n\(m.text)\n\n"
            case .event: out += "> \(m.text)\n\n"
            }
        }
        return out
    }

    func replaceAll(_ list: [Conversation]) {
        conversations = list
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var scanning: String?
    private let fileURL: URL
    private let persist: Bool

    init(persist: Bool = true) {
        self.persist = persist
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        fileURL = base.appendingPathComponent("Panora/projekte.json")
        if persist, let data = try? Data(contentsOf: fileURL) {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            projects = (try? d.decode([ProjectSummary].self, from: data)) ?? []
        }
    }

    func project(_ path: String?) -> ProjectSummary? {
        guard let path else { return nil }
        return projects.first { $0.path == path }
    }

    func chooseAndAdd() async -> ProjectSummary? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Projekt hinzufügen"
        panel.message = "Ordner wählen – Panora liest ihn nur (Analyse und Kontext), ändert nichts."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return await add(url)
    }

    func add(_ url: URL) async -> ProjectSummary {
        scanning = url.path
        let summary = await Task.detached(priority: .userInitiated) { ProjectScanner.scan(at: url) }.value
        projects.removeAll { $0.path == summary.path }
        projects.insert(summary, at: 0)
        scanning = nil
        save()
        return summary
    }

    func rescan(_ path: String) async {
        _ = await add(URL(fileURLWithPath: path))
    }

    func remove(_ path: String) {
        projects.removeAll { $0.path == path }
        save()
    }

    /// Kontext für das Modell – neu eingelesen, wenn älter als 10 Minuten.
    func contextText(for path: String?, focus: [String], budgetTokens: Int) async -> String? {
        guard let path, var summary = project(path) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return "Projekt \(summary.name): Ordner nicht erreichbar." }
        if Date().timeIntervalSince(summary.scannedAt) > 600 {
            summary = await add(URL(fileURLWithPath: path))
        }
        let s = summary
        return await Task.detached(priority: .userInitiated) {
            ProjectScanner.contextText(s, focus: focus, budgetTokens: budgetTokens)
        }.value
    }

    private func save() {
        guard persist else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(projects) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func setDemo(_ list: [ProjectSummary]) { projects = list }
}
