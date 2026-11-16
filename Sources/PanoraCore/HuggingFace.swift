import Foundation

// =============================================================================================
// Hugging Face Hub: Suche nach MLX-Modellen, Dateilisten, Lizenzen. Nur Adressen und Auswertung –
// die Downloads selbst erledigt die App (URLSession) direkt in den gewählten Modellordner.
// =============================================================================================

public struct HFModelSummary: Sendable, Hashable, Identifiable {
    public var id: String
    public var downloads: Int
    public var likes: Int
    public var tags: [String]
    public var pipelineTag: String?
    public var lastModified: String?

    public var license: LicenseInfo {
        LicenseInfo.fromIdentifier(tags.first { $0.hasPrefix("license:") }.map { String($0.dropFirst("license:".count)) })
    }

    public var parsed: ModelNameParser.Parsed { ModelNameParser.parse(id) }

    public var name: String { id.split(separator: "/").last.map(String.init) ?? id }
    public var author: String { id.split(separator: "/").first.map(String.init) ?? "" }

    public init(id: String, downloads: Int = 0, likes: Int = 0, tags: [String] = [], pipelineTag: String? = nil, lastModified: String? = nil) {
        self.id = id
        self.downloads = downloads
        self.likes = likes
        self.tags = tags
        self.pipelineTag = pipelineTag
        self.lastModified = lastModified
    }
}

public struct HFFile: Sendable, Hashable {
    public var path: String
    public var size: Int64

    public init(path: String, size: Int64) {
        self.path = path
        self.size = size
    }
}

public struct HFModelInfo: Sendable, Equatable {
    public var id: String
    public var files: [HFFile]
    public var license: LicenseInfo
    public var tags: [String]
    public var gated: Bool
    public var pipelineTag: String?

    public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

public enum HuggingFaceAPI {
    public static let base = "https://huggingface.co"

    public static func searchURL(query: String, author: String? = "mlx-community", limit: Int = 40) -> URL {
        var c = URLComponents(string: base + "/api/models")!
        var items = [URLQueryItem(name: "sort", value: "downloads"), URLQueryItem(name: "direction", value: "-1"),
                     URLQueryItem(name: "limit", value: String(limit))]
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items.append(URLQueryItem(name: "search", value: q)) }
        if let author { items.append(URLQueryItem(name: "author", value: author)) }
        items.append(URLQueryItem(name: "filter", value: "mlx"))
        c.queryItems = items
        return c.url!
    }

    public static func infoURL(repo: String) -> URL {
        URL(string: base + "/api/models/" + repo + "?blobs=true")!
    }

    public static func fileURL(repo: String, path: String, revision: String = "main") -> URL {
        let encoded = path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: base + "/" + repo + "/resolve/" + revision + "/" + encoded)!
    }

    public static func modelPageURL(repo: String) -> URL { URL(string: base + "/" + repo)! }

    public static func parseSearch(_ data: Data) throws -> [HFModelSummary] {
        guard let list = (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = (item["id"] as? String) ?? (item["modelId"] as? String) else { return nil }
            return HFModelSummary(id: id, downloads: item["downloads"] as? Int ?? 0, likes: item["likes"] as? Int ?? 0,
                                  tags: item["tags"] as? [String] ?? [], pipelineTag: item["pipeline_tag"] as? String,
                                  lastModified: (item["lastModified"] as? String) ?? (item["createdAt"] as? String))
        }
    }

    public static func parseInfo(_ data: Data) throws -> HFModelInfo {
        guard let root = (try JSONSerialization.jsonObject(with: data)) as? [String: Any], let id = root["id"] as? String else {
            if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let error = root["error"] as? String {
                throw ExpertError.api(error)
            }
            throw ExpertError.badResponse
        }
        let siblings = root["siblings"] as? [[String: Any]] ?? []
        let files: [HFFile] = siblings.compactMap { s in
            guard let path = s["rfilename"] as? String else { return nil }
            let direct = (s["size"] as? Int).map { Int64($0) }
            let lfs = ((s["lfs"] as? [String: Any])?["size"] as? Int).map { Int64($0) }
            let size = direct ?? lfs ?? 0
            return HFFile(path: path, size: size)
        }
        let tags = root["tags"] as? [String] ?? []
        let cardLicense = (root["cardData"] as? [String: Any])?["license"] as? String
        let tagLicense = tags.first { $0.hasPrefix("license:") }.map { String($0.dropFirst("license:".count)) }
        let gatedValue = root["gated"]
        let gated: Bool
        if let b = gatedValue as? Bool { gated = b } else if let s = gatedValue as? String { gated = !s.isEmpty && s != "false" } else { gated = false }
        return HFModelInfo(id: id, files: files, license: LicenseInfo.fromIdentifier(cardLicense ?? tagLicense), tags: tags,
                           gated: gated, pipelineTag: root["pipeline_tag"] as? String)
    }

    /// Nur, was MLX zum Laden braucht (Gewichte, Konfiguration, Tokenizer, Vorlagen, Lizenz).
    public static func filesToDownload(_ files: [HFFile]) -> [HFFile] {
        files.filter { f in
            let lower = f.path.lowercased()
            if lower.hasPrefix(".") || lower.contains("/.") { return false }
            if lower.hasSuffix(".gguf") || lower.hasSuffix(".onnx") || lower.hasSuffix(".bin") || lower.hasSuffix(".pt")
                || lower.hasSuffix(".pth") || lower.hasSuffix(".h5") || lower.hasSuffix(".msgpack") { return false }
            if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".gif") { return false }
            return lower.hasSuffix(".safetensors") || lower.hasSuffix(".json") || lower.hasSuffix(".model")
                || lower.hasSuffix(".txt") || lower.hasSuffix(".jinja") || lower.hasSuffix(".tiktoken")
                || lower == "license" || lower.hasPrefix("license") || lower == "readme.md"
        }
    }

    /// Ordnername für ein Repository („mlx-community__Qwen3-8B-4bit“).
    public static func folderName(for repo: String) -> String {
        repo.replacingOccurrences(of: "/", with: "__")
    }

    public static func repo(fromFolderName name: String) -> String? {
        guard name.contains("__") else { return nil }
        return name.replacingOccurrences(of: "__", with: "/")
    }
}
