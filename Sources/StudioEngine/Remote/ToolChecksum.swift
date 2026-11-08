import Foundation
import CryptoKit
import MLStudio

/// SHA-256-Prüfsummen für heruntergeladene Werkzeuge.
public enum ToolChecksum {
    /// SHA-256 einer Datei als Kleinbuchstaben-Hex (in Blöcken gelesen, auch für große Dateien).
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Erwartete Prüfsumme für `fileName` aus einer Prüfsummenliste.
    /// Unterstützt „<hex>  <name>“, „<hex> *<name>“ (sha256sum/shasum) und eine einzelne Prüfsumme ohne Namen
    /// (z. B. Deno-„.sha256sum“ älterer Veröffentlichungen).
    public static func expected(in list: String, for fileName: String) -> String? {
        var single: [String] = []
        for raw in list.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let hash = parts.first.map({ $0.lowercased() }), isHex64(hash) else {
                // „SHA256 (name) = hex“ (BSD-Format)
                if line.hasPrefix("SHA256 ("), let close = line.range(of: ") = ") {
                    let name = String(line[line.index(line.startIndex, offsetBy: 8)..<close.lowerBound])
                    let hash = String(line[close.upperBound...]).trimmingCharacters(in: .whitespaces).lowercased()
                    if isHex64(hash), name == fileName || (name as NSString).lastPathComponent == fileName { return hash }
                }
                // Hex-Zeile ohne Leerzeichen-Trennung (z. B. Windows-CertUtil-Ausgabe)
                let compact = line.replacingOccurrences(of: " ", with: "").lowercased()
                if isHex64(compact) { single.append(compact) }
                continue
            }
            if parts.count == 1 { single.append(hash); continue }
            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            if name == fileName || (name as NSString).lastPathComponent == fileName { return hash }
        }
        return single.count == 1 ? single[0] : nil
    }

    /// Prüft eine Datei; bei Abweichung `StudioError.other` mit verständlicher Meldung.
    public static func verify(file: URL, expected: String, name: String) throws {
        let actual = try sha256(of: file)
        guard actual == expected.lowercased() else {
            throw StudioError.other("Die Prüfsumme von \(name) stimmt nicht mit der Veröffentlichung überein. Aus Sicherheitsgründen wurde nichts installiert.")
        }
    }

    static func isHex64(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { $0.isHexDigit }
    }
}
