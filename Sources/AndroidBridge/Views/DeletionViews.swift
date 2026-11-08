import SwiftUI
import AppKit
import ABCore

/// Bestätigung vor dem Löschen auf dem Telefon: Anzahl, Größe, Speicherorte, Warnung (kein Papierkorb).
struct DeleteConfirmationSheet: View {
    let request: DeletionRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var understood = false

    private var total: Int { request.entries.count }
    private var needsAcknowledgement: Bool { request.folderCount > 0 }

    private var title: String {
        if request.folderCount == 0 {
            return request.fileCount == 1 ? "1 Datei endgültig löschen?" : "\(request.fileCount) Dateien endgültig löschen?"
        }
        if request.fileCount == 0 {
            return request.folderCount == 1 ? "1 Ordner endgültig löschen?" : "\(request.folderCount) Ordner endgültig löschen?"
        }
        return "\(total) Objekte endgültig löschen?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(symbol: "trash", tint: Palette.danger, title: title, subtitle: "Auf „\(request.deviceName)“")

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                if request.fileCount > 0 {
                    GridRow {
                        Text("Dateien").foregroundStyle(Palette.textSecondary)
                        Text("\(request.fileCount) · \(ByteFormat.string(request.knownBytes))").monospacedDigit()
                    }
                }
                if request.folderCount > 0 {
                    GridRow {
                        Text("Ordner").foregroundStyle(Palette.textSecondary)
                        Text("\(request.folderCount) – samt gesamtem Inhalt")
                    }
                }
                ForEach(Array(request.summaryRows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label).foregroundStyle(Palette.textSecondary)
                        Text(row.value)
                    }
                }
                GridRow(alignment: .top) {
                    Text(request.locations.count == 1 ? "Speicherort" : "Speicherorte").foregroundStyle(Palette.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(request.locations.prefix(4), id: \.self) { Text($0).lineLimit(1).truncationMode(.middle) }
                        if request.locations.count > 4 {
                            Text("und \(request.locations.count - 4) weitere").foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
            .font(Typo.body)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(request.entries.prefix(6).enumerated()), id: \.offset) { index, e in
                    HStack(spacing: 10) {
                        TypeIcon(name: e.name, isFolder: e.isFolder, size: 20)
                        Text(e.name).font(Typo.body).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(e.isFolder ? "Ordner" : ByteFormat.string(e.size))
                            .font(Typo.caption).foregroundStyle(Palette.textSecondary).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    if index < min(request.entries.count, 6) - 1 { Divider().opacity(0.5).padding(.leading, 40) }
                }
                if request.entries.count > 6 {
                    Text("… und \(request.entries.count - 6) weitere")
                        .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
            }
            .glassCard(cornerRadius: Radius.tile, strong: true)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Das Telefon hat über USB keinen Papierkorb.").font(Typo.headline)
                    Text(needsAcknowledgement
                         ? "Ordner werden mit allen Unterordnern und Dateien gelöscht – auch mit Inhalten, die hier nicht angezeigt werden. Gelöschtes lässt sich nicht wiederherstellen."
                         : "Gelöschte Dateien lassen sich nicht wiederherstellen. Kopien in Cloud-Diensten oder auf dem Mac sind davon nicht betroffen.")
                        .font(Typo.callout).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Palette.dangerSoft))

            if needsAcknowledgement {
                Toggle(isOn: $understood) {
                    Text("Ich verstehe, dass die Ordner mit ihrem gesamten Inhalt endgültig gelöscht werden.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .font(Typo.callout)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Abbrechen", action: onCancel)
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    onConfirm()
                } label: {
                    Label("Endgültig löschen", systemImage: "trash")
                }
                .buttonStyle(GlassButtonStyle(prominent: true, destructive: true))
                .disabled(needsAcknowledgement && !understood)
                .accessibilityIdentifier("confirm-delete")
            }
        }
        .sheetChrome(width: 520)
    }
}

/// Bericht nach einer Löschung mit Fehlern.
struct DeletionResultSheet: View {
    let outcome: DeletionOutcome
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: outcome.deleted.isEmpty ? "xmark.octagon" : "exclamationmark.triangle",
                        tint: outcome.deleted.isEmpty ? Palette.danger : Palette.warning,
                        title: outcome.deleted.isEmpty ? "Nichts gelöscht" : "Teilweise gelöscht",
                        subtitle: summary)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(outcome.failed.enumerated()), id: \.offset) { index, f in
                        HStack(alignment: .top, spacing: 10) {
                            TypeIcon(name: f.entry.name, isFolder: f.entry.isFolder, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.entry.name).font(Typo.bodyMedium).lineLimit(1).truncationMode(.middle)
                                Text(f.reason).font(Typo.caption).foregroundStyle(Palette.danger)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if index < outcome.failed.count - 1 { Divider().opacity(0.5) }
                    }
                }
            }
            .frame(maxHeight: 260)
            .glassCard(cornerRadius: Radius.tile, strong: true)
            Text("Nicht gelöschte Objekte bleiben unverändert auf dem Telefon. Geschützte Ordner (z. B. Android/data) und Dateien anderer Apps kann Android über USB verweigern.")
                .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("OK", action: dismiss)
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheetChrome(width: 500)
    }

    private var summary: String {
        var parts = ["\(outcome.deleted.count) gelöscht", "\(outcome.failed.count) nicht gelöscht"]
        if let freed = outcome.freedBytes { parts.append("\(ByteFormat.string(freed)) frei geworden") }
        return parts.joined(separator: " · ")
    }
}

/// Fortschritt einer laufenden Löschung.
struct DeletionProgressBadge: View {
    let progress: DeletionService.Progress

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .progressViewStyle(.circular)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lösche \(min(progress.done + 1, progress.total)) von \(progress.total)")
                    .font(Typo.headline).monospacedDigit()
                Text(progress.current).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassSurface(Capsule(), strong: true, elevated: true)
    }
}

/// Bestätigung und Bericht – je Fenster (Hauptfenster bzw. Gerätefenster).
struct DeletionSheets: ViewModifier {
    @ObservedObject var model: AppModel
    let origin: String
    var glass = true

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { model.pendingDeletion?.origin == origin ? model.pendingDeletion : nil },
                                 set: { if $0 == nil, model.pendingDeletion?.origin == origin { model.pendingDeletion = nil } })) { request in
                DeleteConfirmationSheet(request: request,
                                        onConfirm: { model.confirmDeletion(request) },
                                        onCancel: { model.pendingDeletion = nil })
                    .environment(\.glassEnabled, glass)
            }
            .sheet(item: Binding(get: { model.deletionReport?.origin == origin ? model.deletionReport : nil },
                                 set: { if $0 == nil, model.deletionReport?.origin == origin { model.deletionReport = nil } })) { box in
                DeletionResultSheet(outcome: box.outcome) { model.deletionReport = nil }
                    .environment(\.glassEnabled, glass)
            }
    }
}

extension View {
    func deletionSheets(model: AppModel, origin: String, glass: Bool) -> some View {
        modifier(DeletionSheets(model: model, origin: origin, glass: glass))
    }
}
