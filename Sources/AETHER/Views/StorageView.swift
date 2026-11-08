import SwiftUI
import AppKit
import AetherCore

/// Speicher: Volumes (mit löschbarem Platz), Datenträgeraktivität, SSD-Gesundheit, Ordneranalyse, Bereinigungsvorschläge.
struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        let engine = model.engine
        let isSnapshot = model.launchMode.isSnapshot
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                StorageHeroHeader(store: engine.storage, telemetry: engine.telemetry)
                VolumesPanel(store: engine.storage, actions: VolumeActionsModel.shared) { url in
                    model.openInFiles(url)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: theme.density.cardSpacing, alignment: .top)],
                          alignment: .leading, spacing: theme.density.cardSpacing) {
                    DiskActivityPanel(store: engine.storage, interval: settings.effectiveInterval.seconds)
                    DriveHealthPanel(health: DriveHealthModel.shared, isVirtualMachine: engine.system.hardware.isVirtualMachine)
                }
                FolderAnalysisPanel(analysis: StorageAnalysisModel.shared, isSnapshot: isSnapshot) { url in
                    model.openInFiles(url)
                }
                CleanupPanel(cleanup: CleanupModel.shared, isSnapshot: isSnapshot)
                NoticeBar(text: tr("Analyses run only on this Mac and only when you start them. Nothing is deleted automatically – items only go to the Trash after you confirm, and you can put them back right away."),
                          symbol: "lock.shield")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
    }
}

// MARK: - Volumes

private struct VolumesPanel: View {
    @ObservedObject var store: StorageStore
    @ObservedObject var actions: VolumeActionsModel
    let openInFiles: (URL) -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        let volumes = store.snapshot?.volumes ?? []
        Panel {
            PanelTitle(title: tr("Volumes"), symbol: SymbolName.ssd,
                       trailing: volumes.isEmpty ? nil : tr("%ld volumes", volumes.count))
            if let message = actions.message {
                NoticeBar(text: message.text, symbol: message.isError ? "exclamationmark.triangle" : "checkmark.circle")
            }
            if volumes.isEmpty {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
            ForEach(volumes) { volume in
                VolumeRow(volume: volume, ejecting: actions.ejecting.contains(volume.path), openInFiles: openInFiles) {
                    actions.eject(volume)
                }
                if volume.id != volumes.last?.id {
                    Divider().overlay(theme.hairline)
                }
            }
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo
    let ejecting: Bool
    let openInFiles: (URL) -> Void
    let eject: () -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        let v = volume
        let url = URL(fileURLWithPath: v.path)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: v.isNetwork ? "server.rack" : (v.isRemovable || v.isInternal == false ? "externaldrive" : "internaldrive"))
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(theme.storage)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(v.name).font(Typo.bodyMedium).lineLimit(1)
                        ForEach(badges(v), id: \.self) { badge in
                            StorageTag(text: badge)
                        }
                    }
                    Text(v.path).font(Typo.mono).foregroundStyle(theme.textTertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tr("%@ available", fmt.bytes(v.effectiveAvailable)))
                        .font(Typo.callout.weight(.medium)).monospacedDigit().lineLimit(1)
                    Text(tr("of %@", fmt.bytes(v.capacity)))
                        .font(Typo.caption).foregroundStyle(theme.textSecondary).monospacedDigit().lineLimit(1)
                }
            }
            CapacityBar(volume: v)
            HStack(spacing: Spacing.m) {
                legend(theme.storage, tr("Used"), fmt.bytes(v.used))
                if let purgeable = v.purgeable, purgeable > 0 {
                    legend(theme.storage.opacity(0.38), tr("Purgeable"), fmt.bytes(purgeable))
                        .help(tr("Space macOS frees up automatically when needed (e.g. caches, local snapshots)."))
                    ProvenanceBadge(source: .purgeableSpace)
                }
                legend(theme.fieldFill, tr("Free"), fmt.bytes(v.available))
                ProvenanceBadge(source: .volumes)
                Spacer(minLength: 8)
                Button(tr("Open in Files")) { openInFiles(url) }
                    .buttonStyle(CapsuleButtonStyle())
                Button(tr("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(CapsuleButtonStyle())
                if canEject(v) {
                    Button(ejecting ? tr("Ejecting…") : tr("Eject")) { eject() }
                        .buttonStyle(CapsuleButtonStyle())
                        .disabled(ejecting)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func canEject(_ v: VolumeInfo) -> Bool {
        !v.isRoot && (v.isRemovable || v.isNetwork || v.isInternal == false)
    }

    private func badges(_ v: VolumeInfo) -> [String] {
        var result: [String] = []
        if v.isRoot { result.append(tr("Startup disk")) }
        if v.isNetwork {
            result.append(tr("Network"))
        } else if v.isInternal == false || v.isRemovable {
            result.append(tr("External"))
        } else if v.isInternal == true {
            result.append(tr("Internal"))
        }
        if let format = v.format { result.append(format) }
        if v.isEncrypted == true { result.append(tr("Encrypted")) }
        if v.isReadOnly { result.append(tr("Read-only")) }
        return result
    }

    private func legend(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
                .overlay(Circle().stroke(theme.hairline, lineWidth: 0.5))
            Text(label).foregroundStyle(theme.textSecondary)
            Text(value).monospacedDigit()
        }
        .font(Typo.caption)
        .lineLimit(1)
    }
}

/// Belegt · löschbar · frei als ein Balken.
private struct CapacityBar: View {
    let volume: VolumeInfo
    @Environment(\.aether) private var theme

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(volume.capacity), 1)
            let usedWidth = geo.size.width * CGFloat(min(1, Double(volume.used) / total))
            let purgeableWidth = geo.size.width * CGFloat(min(1, Double(volume.purgeable ?? 0) / total))
            HStack(spacing: 0) {
                Rectangle()
                    .fill(volume.usedFraction > 0.9 ? theme.statusElevated : theme.storage)
                    .frame(width: max(0, usedWidth))
                Rectangle()
                    .fill(theme.storage.opacity(0.38))
                    .frame(width: max(0, min(purgeableWidth, geo.size.width - usedWidth)))
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .background(theme.fieldFill)
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel(tr("%@ used of %@", fmt.bytes(volume.used), fmt.bytes(volume.capacity)))
    }
}

/// Kleines Etikett (Format, intern/extern, verschlüsselt …).
struct StorageTag: View {
    let text: String
    @Environment(\.aether) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.fieldFill))
    }
}

// MARK: - Datenträgeraktivität

private struct DiskActivityPanel: View {
    @ObservedObject var store: StorageStore
    let interval: Double
    @Environment(\.aether) private var theme

    var body: some View {
        let snapshot = store.snapshot
        Panel {
            PanelTitle(title: tr("Disk activity"), symbol: "arrow.up.arrow.down")
            HStack(alignment: .top, spacing: Spacing.xxl) {
                rate(tr("Read"), snapshot?.readRate, theme.networkDown)
                rate(tr("Write"), snapshot?.writeRate, theme.networkUp)
                Spacer(minLength: 0)
            }
            if !store.longRead.isEmpty {
                HistoryChart(series: [.init(values: store.longRead.elements, color: theme.networkDown),
                                      .init(values: store.longWrite.elements, color: theme.networkUp, fill: false)],
                             capacity: detailCapacity, maxValue: nil, height: 120, label: { fmt.rate($0) },
                             spanLabel: historySpanLabel(samples: detailCapacity, interval: interval))
            }
            if let peakRead = store.peakRead, let peakWrite = store.peakWrite {
                Text(tr("Peak since start: read %@ · write %@", fmt.rate(peakRead), fmt.rate(peakWrite)))
                    .font(Typo.caption).foregroundStyle(theme.textSecondary).monospacedDigit()
            }
            Text(tr("All disks combined, including external drives and disk images. macOS doesn’t assign this activity to individual volumes."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func rate(_ label: String, _ reading: Reading<Double>?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
            if let reading, let value = reading.value {
                let parts = fmt.rateParts(value)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ValueText(value: parts.value, unit: parts.unit, font: Typo.metric, color: color)
                    ProvenanceBadge(source: reading.source, timestamp: reading.timestamp)
                }
            } else if let reading {
                UnavailableValue(reason: reading.reason ?? .queryFailed, source: reading.source, compact: true)
            } else {
                Text("–").font(Typo.metric).foregroundStyle(theme.textTertiary)
            }
        }
    }
}

// MARK: - SSD-Gesundheit

private struct DriveHealthPanel: View {
    @ObservedObject var health: DriveHealthModel
    let isVirtualMachine: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        Panel {
            PanelTitle(title: tr("SSD health"), symbol: "stethoscope")
            if let reading = health.drives {
                if let drives = reading.value {
                    ForEach(drives) { drive in
                        DriveHealthRow(drive: drive)
                        if drive.id != drives.last?.id {
                            Divider().overlay(theme.hairline)
                        }
                    }
                } else {
                    HStack {
                        Text(tr("No health data")).font(Typo.bodyMedium)
                        Spacer()
                        UnavailableValue(reason: reading.reason ?? .notProvidedByMacOS, source: reading.source, compact: true)
                    }
                    Text(reading.reason?.explanation ?? "").font(Typo.caption).foregroundStyle(theme.textSecondary)
                }
            } else {
                Text(tr("Reading…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
            Text(tr("Values the drive reports about itself (NVMe SMART). External USB drives and SATA SSDs don’t provide them to apps."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { health.pageAppeared(isVirtualMachine: isVirtualMachine) }
        .onDisappear { health.pageDisappeared() }
    }
}

private struct DriveHealthRow: View {
    let drive: NVMeDrive
    @Environment(\.aether) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: SymbolName.ssd).foregroundStyle(theme.storage)
                Text(drive.model ?? tr("NVMe drive")).font(Typo.bodyMedium).lineLimit(1)
                if let firmware = drive.firmware {
                    StorageTag(text: tr("Firmware %@", firmware))
                }
                Spacer(minLength: 0)
            }
            if let h = drive.health.value {
                if h.warnings.isEmpty {
                    Label(tr("The drive reports no critical warnings"), systemImage: "checkmark.seal")
                        .font(Typo.callout).foregroundStyle(theme.statusNormal)
                } else {
                    ForEach(h.warnings, id: \.self) { warning in
                        Label(warningText(warning), systemImage: "exclamationmark.triangle.fill")
                            .font(Typo.callout).foregroundStyle(theme.statusCritical)
                    }
                }
                HStack(alignment: .top, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Wear (percentage used)")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ValueText(value: fmt.integer(h.percentageUsed), unit: "%", font: Typo.metricSmall,
                                      color: h.percentageUsed >= 90 ? theme.statusElevated : nil)
                            ProvenanceBadge(source: drive.health.source, timestamp: drive.health.timestamp)
                        }
                        FillBar(fraction: Double(h.percentageUsed) / 100,
                                color: h.percentageUsed >= 90 ? theme.statusElevated : theme.storage, height: 5)
                            .frame(width: 120)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Available spare")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                        ValueText(value: fmt.integer(h.availableSpare), unit: "%", font: Typo.metricSmall,
                                  color: h.availableSpare <= h.availableSpareThreshold ? theme.statusCritical : nil)
                        Text(tr("Warning below %@", fmt.integer(h.availableSpareThreshold) + " %"))
                            .font(Typo.caption).foregroundStyle(theme.textTertiary)
                    }
                    if let celsius = h.temperatureCelsius {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Temperature")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                            ValueText(value: fmt.number(celsius, fractionDigits: 0), unit: "°C", font: Typo.metricSmall)
                        }
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 5) {
                    InfoRow(label: tr("Data written"), value: fmt.bytes(h.bytesWritten), source: drive.health.source,
                            timestamp: drive.health.timestamp)
                    InfoRow(label: tr("Data read"), value: fmt.bytes(h.bytesRead))
                    InfoRow(label: tr("Power-on hours"), value: count(h.powerOnHours))
                    InfoRow(label: tr("Power cycles"), value: count(h.powerCycles))
                    InfoRow(label: tr("Unsafe shutdowns"), value: count(h.unsafeShutdowns))
                    InfoRow(label: tr("Media and data integrity errors"), value: count(h.mediaErrors),
                            valueColor: h.mediaErrors > 0 ? theme.statusElevated : nil)
                }
            } else {
                HStack {
                    Text(tr("Health data")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    UnavailableValue(reason: drive.health.reason ?? .queryFailed, source: drive.health.source, compact: true)
                }
            }
        }
    }

    private func count(_ value: Double) -> String {
        fmt.integer(Int(min(value, 9_000_000_000_000)))
    }

    private func warningText(_ warning: NVMeCriticalWarning) -> String {
        switch warning {
        case .spareBelowThreshold: return tr("Spare capacity below the threshold")
        case .temperature: return tr("Temperature outside the permitted range")
        case .reliabilityDegraded: return tr("Reliability degraded (media or internal errors)")
        case .readOnly: return tr("Drive switched to read-only mode")
        case .volatileBackupFailed: return tr("Volatile memory backup failed")
        case .persistentMemoryReadOnly: return tr("Persistent memory region is read-only")
        }
    }
}
