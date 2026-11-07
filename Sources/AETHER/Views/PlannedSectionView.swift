import SwiftUI
import AetherCore

/// Zwischenstand für Bereiche, die in einer späteren Phase vollständig umgesetzt werden. Ehrlich beschriftet:
/// was kommt, aus welchen Quellen – und was davon schon jetzt in der Übersicht zu sehen ist.
struct PlannedSectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    let section: AppSection

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: section.title, subtitle: subtitle)
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack(spacing: Spacing.l) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 34, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.accent)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(theme.accent.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 4) {
                            if let phase = section.plannedPhase {
                                Chip(text: tr("In development · Phase %ld", phase), symbol: "hammer")
                            }
                            Text(summary)
                                .font(.system(size: 15, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider().overlay(theme.hairline)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(plannedItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "circle.dotted").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                                Text(item).font(Typo.body).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let available = availableNow {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle").foregroundStyle(theme.statusNormal)
                            Text(available).font(Typo.callout).foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button(tr("Open Overview")) { model.select(.overview) }
                                .buttonStyle(CapsuleButtonStyle(prominent: true))
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
                .glassCard()
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
    }

    private var subtitle: String {
        tr("Planned for phase %ld – see the concept for details", section.plannedPhase ?? 0)
    }

    private var summary: String {
        switch section {
        case .activity: return tr("A process manager that goes beyond Activity Monitor – with app families, details and safe actions.")
        case .cpuGPU: return tr("Every core, both core types, load history and the graphics processors in detail.")
        case .memory: return tr("Where your memory goes: apps, wired, compressed, cache, swap and pressure over time.")
        case .thermal: return tr("As many real sensor values as this Mac provides – never invented ones.")
        case .battery: return tr("Charge cycles, capacity, voltage, current, temperature and a local history.")
        case .hardware: return tr("Everything about this Mac in one place – exportable as a system report.")
        case .storage: return tr("Volumes, SSD health, the largest files and real duplicates.")
        case .files: return tr("Finder Plus: a fast file manager with Quick Look, search and safe operations.")
        case .network: return tr("Interfaces, live rates, connections and Wi‑Fi details.")
        case .overview, .settings: return ""
        }
    }

    private var plannedItems: [String] {
        switch section {
        case .activity:
            return [tr("All processes with PID, user, state, CPU, memory, threads, path, start time and architecture"),
                    tr("App families: helper processes grouped under their app"),
                    tr("Quit and force quit with confirmation; system processes are protected"),
                    tr("Values of other users’ processes only where macOS provides them without administrator rights")]
        case .cpuGPU:
            return [tr("Usage per core, grouped by performance and efficiency cores (Apple Silicon) or cores and threads (Intel)"),
                    tr("History and peaks"),
                    tr("GPU model, cores, Metal family and utilization as reported by the driver")]
        case .memory:
            return [tr("App memory, wired, compressed, cached files, free"),
                    tr("Swap, page-ins and page-outs, compression rate"),
                    tr("Memory pressure over time")]
        case .thermal:
            return [tr("CPU, GPU and SoC temperatures from the System Management Controller, read-only"),
                    tr("Each sensor with source, time stamp and history; averages clearly marked as computed"),
                    tr("Fans: count, speed, minimum, maximum – or “This Mac has no fan”")]
        case .battery:
            return [tr("Cycle count, design and full charge capacity, computed health next to macOS’s own condition"),
                    tr("Voltage, current, power, temperature, power adapter"),
                    tr("Local history from the moment you turn it on – nothing invented before that")]
        case .hardware:
            return [tr("Model, chip, cores, caches, memory, graphics, displays, storage, network hardware"),
                    tr("macOS version, build, kernel, uptime"),
                    tr("System report as a file; the serial number only on explicit request")]
        case .storage:
            return [tr("Internal and external volumes, APFS containers, purgeable space"),
                    tr("SSD health via NVMe SMART: wear, temperature, data written"),
                    tr("Largest files and folders, real duplicates by content (SHA-256), never deleted automatically")]
        case .files:
            return [tr("Sidebar with home folders, applications, volumes and favorites"),
                    tr("Copy, move, rename, new folder, Trash with undo, drag and drop"),
                    tr("Quick Look, Spotlight search, Show in Finder, Copy path")]
        case .network:
            return [tr("Wi‑Fi, Ethernet, VPN and other interfaces with addresses"),
                    tr("Download and upload rates with history"),
                    tr("Active connections; passwords are never shown")]
        case .overview, .settings:
            return []
        }
    }

    private var availableNow: String? {
        switch section {
        case .cpuGPU: return tr("Already live in the Overview: total CPU usage, user and system share, GPU.")
        case .memory: return tr("Already live in the Overview: memory breakdown, swap and memory pressure.")
        case .thermal: return tr("Already live in the Overview: thermal state and battery temperature.")
        case .battery: return tr("Already live in the Overview: charge, cycles, computed capacity and condition.")
        case .hardware: return tr("Already live in the Overview: model, chip, memory, macOS and uptime.")
        case .storage: return tr("Already live in the Overview: volumes, free space and disk activity.")
        case .network: return tr("Already live in the Overview: download and upload rates.")
        case .activity, .files, .overview, .settings: return nil
        }
    }
}
