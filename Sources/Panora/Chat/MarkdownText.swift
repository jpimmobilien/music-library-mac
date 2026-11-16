import SwiftUI
import AppKit

/// Einfache Markdown-Darstellung für Antworten: Überschriften, Aufzählungen, Absätze mit Inline-Formatierung
/// und Codeblöcke (Monospace, mit Kopieren-Knopf).
struct MarkdownText: View {
    @Environment(\.panora) private var colors
    let text: String

    enum Block: Identifiable {
        case heading(Int, String, Int)
        case paragraph(String, Int)
        case bullet(String, String, Int)
        case code(String, String, Int)
        case quote(String, Int)
        case rule(Int)

        var id: Int {
            switch self {
            case .heading(_, _, let i), .paragraph(_, let i), .bullet(_, _, let i), .code(_, _, let i), .quote(_, let i), .rule(let i):
                return i
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.parse(text)) { block in
                switch block {
                case .heading(let level, let t, _):
                    inline(t)
                        .font(.system(size: level == 1 ? 20 : (level == 2 ? 17 : 15), weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                        .padding(.top, 4)
                case .paragraph(let t, _):
                    inline(t)
                        .font(Typo.body(14.5))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(3)
                case .bullet(let marker, let t, _):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).font(Typo.body(14.5, .semibold)).foregroundStyle(colors.accent)
                        inline(t).font(Typo.body(14.5)).foregroundStyle(colors.textPrimary).lineSpacing(3)
                    }
                    .padding(.leading, 4)
                case .code(let lang, let code, _):
                    CodeBlockView(language: lang, code: code)
                case .quote(let t, _):
                    HStack(spacing: 10) {
                        Rectangle().fill(colors.accent.opacity(0.6)).frame(width: 3)
                        inline(t).font(Typo.body(14)).foregroundStyle(colors.textSecondary)
                    }
                case .rule:
                    Rectangle().fill(colors.hairline).frame(height: 1)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> Text {
        if let attributed = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(s)
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var inCode = false
        var codeLang = ""
        var codeLines: [String] = []
        var n = 0
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n"), n)); n += 1
                paragraph.removeAll()
            }
        }
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLang, codeLines.joined(separator: "\n"), n)); n += 1
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flush()
                    inCode = true
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if inCode { codeLines.append(line); continue }
            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level <= 6, trimmed.dropFirst(level).hasPrefix(" ") {
                    flush()
                    blocks.append(.heading(level, String(trimmed.dropFirst(level + 1)), n)); n += 1
                    continue
                }
            }
            if trimmed == "---" || trimmed == "***" { flush(); blocks.append(.rule(n)); n += 1; continue }
            if trimmed.hasPrefix("> ") { flush(); blocks.append(.quote(String(trimmed.dropFirst(2)), n)); n += 1; continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flush()
                var content = String(trimmed.dropFirst(2))
                var marker = "•"
                if content.hasPrefix("[ ] ") { marker = "☐"; content = String(content.dropFirst(4)) }
                else if content.lowercased().hasPrefix("[x] ") { marker = "☑"; content = String(content.dropFirst(4)) }
                blocks.append(.bullet(marker, content, n)); n += 1
                continue
            }
            if let dot = trimmed.firstIndex(of: "."), trimmed[trimmed.startIndex..<dot].allSatisfy(\.isNumber),
               trimmed.distance(from: trimmed.startIndex, to: dot) <= 3, trimmed.distance(from: trimmed.startIndex, to: dot) >= 1,
               trimmed[trimmed.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.bullet(String(trimmed[...dot]), String(trimmed[trimmed.index(dot, offsetBy: 2)...]), n)); n += 1
                continue
            }
            paragraph.append(line)
        }
        if inCode { blocks.append(.code(codeLang, codeLines.joined(separator: "\n"), n)); n += 1 }
        flush()
        return blocks
    }
}

struct CodeBlockView: View {
    @Environment(\.panora) private var colors
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "Code" : language).font(Typo.label(11, .semibold)).foregroundStyle(colors.textTertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Typo.label(11, .semibold))
                        .foregroundStyle(colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Rectangle().fill(colors.hairline).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Typo.mono(12.5))
                    .foregroundStyle(colors.textPrimary)
                    .padding(14)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.hairline, lineWidth: 0.8))
    }
}
