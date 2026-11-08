import SwiftUI
import AppKit
import ABCore

/// Informationen zu einer Datei auf dem Telefon.
struct EntryInfoBox: Identifiable {
    let id = UUID()
    let deviceID: UInt64
    let entry: DeviceEntry
    let path: [String]
}

struct EntryInfoSheet: View {
    @EnvironmentObject private var model: AppModel
    let box: EntryInfoBox
    let dismiss: () -> Void

    private var device: DeviceConnection? { model.devices.device(id: box.deviceID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                Group {
                    if let device {
                        DeviceThumb(entry: box.entry, device: device, size: 120, corner: 0)
                    } else {
                        TypeIcon(name: box.entry.name, isFolder: box.entry.isFolder, size: 64)
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Palette.hairline))
                VStack(alignment: .leading, spacing: 6) {
                    Text(box.entry.name)
                        .font(Typo.title2)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text(kindName(box.entry.kind, name: box.entry.name))
                        .font(Typo.callout).foregroundStyle(Palette.textSecondary)
                    if !box.entry.isFolder {
                        Text(ByteFormat.string(box.entry.size)).font(.display(20, .bold)).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                if let device { row("Gerät", device.displayName) }
                if let storage = device?.storages.first(where: { $0.id == box.entry.storageID }) { row("Speicher", storage.displayName) }
                row("Ordner", box.path.isEmpty ? "–" : box.path.joined(separator: " › "))
                if !box.entry.isFolder { row("Größe", "\(ByteFormat.string(box.entry.size)) (\(box.entry.size.formatted()) Byte)") }
                if box.entry.imageWidth > 0 { row("Abmessungen", "\(box.entry.imageWidth) × \(box.entry.imageHeight)") }
                if let d = box.entry.modified { row("Geändert", d.formatted(date: .long, time: .shortened)) }
                if let d = box.entry.created { row("Erstellt", d.formatted(date: .long, time: .shortened)) }
            }
            .font(Typo.body)
            HStack {
                Spacer()
                Button("Fertig", action: dismiss)
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheetChrome(width: 480)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(label).foregroundStyle(Palette.textSecondary)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
