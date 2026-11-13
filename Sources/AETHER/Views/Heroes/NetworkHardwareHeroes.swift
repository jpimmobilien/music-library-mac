import SwiftUI
import AetherCore

// =============================================================================================
// Hero-Visualisierungen „Netzwerk“ und „Dieser Mac“ (Designsprache Studio).
//
// Netzwerk: zwei ruhige Datenströme zwischen „Dieser Mac“ und der Schnittstelle. Partikel gibt es nur bei
// gemessenem Durchsatz; Dichte und Tempo folgen ihm (logarithmisch). Die Zahlen kommen aus den Bytezählern
// (Differenzen je Messung, in der Messmaschine berechnet).
// Dieser Mac: Produktbühne mit Gerätesilhouette (als Illustration beschriftet) und den Kenndaten von macOS.
// =============================================================================================

// MARK: - Netzwerk

struct NetworkHero: View {
    @Environment(\.aether) private var theme
    let telemetry: Telemetry
    let network: NetworkStore
    let deviceKind: DeviceKind
    /// Name der Hauptschnittstelle (nil = keine aktive Verbindung bzw. noch nicht geladen)
    let interfaceName: String?
    let interfaceSymbol: String
    let address: String?

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    LiveFigure(metric: telemetry.value(.networkDown, unit: .bytesPerSecond), label: "↓ " + tr("Download"),
                               format: FigureFormat.rate, color: theme.networkDown, source: .interfaceCounters, showPeak: true)
                    RawReadout(series: telemetry.series(.networkDown, unit: .bytesPerSecond), format: { fmt.rate($0) })
                }
                VStack(alignment: .leading, spacing: 3) {
                    LiveFigure(metric: telemetry.value(.networkUp, unit: .bytesPerSecond), label: "↑ " + tr("Upload"),
                               format: FigureFormat.rate, color: theme.networkUp, source: .interfaceCounters, showPeak: true)
                    RawReadout(series: telemetry.series(.networkUp, unit: .bytesPerSecond), format: { fmt.rate($0) })
                }
                SessionTotals(store: network)
            }
            .frame(width: 230, alignment: .leading)
            VStack(spacing: 14) {
                NetworkFlowStage(down: telemetry.value(.networkDown, unit: .bytesPerSecond),
                                 up: telemetry.value(.networkUp, unit: .bytesPerSecond),
                                 deviceKind: deviceKind, interfaceName: interfaceName, interfaceSymbol: interfaceSymbol,
                                 address: address)
                    .frame(height: 170)
                Label(tr("Data streams: density and speed follow the measured network throughput. No traffic, no particles."),
                      systemImage: "info.circle")
                    .font(StudioType.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Seit dem Start von ORBIT empfangen und gesendet (Bytezähler).
private struct SessionTotals: View {
    @ObservedObject var store: NetworkStore
    @Environment(\.aether) private var theme

    var body: some View {
        if let snapshot = store.snapshot {
            Text(tr("Since start: ↓ %@ · ↑ %@", fmt.bytes(snapshot.sessionDownloaded), fmt.bytes(snapshot.sessionUploaded)))
                .font(StudioType.caption)
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// „Dieser Mac“ ⇄ Schnittstelle: ↓ fließt zum Mac, ↑ fließt von ihm weg.
private struct NetworkFlowStage: View {
    @ObservedObject var down: MetricValue
    @ObservedObject var up: MetricValue
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    let deviceKind: DeviceKind
    let interfaceName: String?
    let interfaceSymbol: String
    let address: String?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            node(symbol: deviceSymbol(deviceKind), title: tr("This Mac"), detail: address, color: theme.accent, active: true)
            VStack(alignment: .leading, spacing: 30) {
                lane(title: tr("Download"), symbol: "arrow.left", rate: rate(down), color: theme.networkDown, forward: false)
                lane(title: tr("Upload"), symbol: "arrow.right", rate: rate(up), color: theme.networkUp, forward: true)
            }
            .frame(maxWidth: .infinity)
            node(symbol: interfaceName == nil ? "network.slash" : interfaceSymbol,
                 title: interfaceName ?? tr("No active connection"), detail: nil, color: theme.networkDown,
                 active: interfaceName != nil)
        }
        .help(tr("Short spikes stay visible: the large numbers show the peak of the last 10 seconds, the history band the lowest and highest value of each time slice."))
    }

    private func rate(_ metric: MetricValue) -> Double? {
        metric.isAvailable ? metric.display(raw: settings.showRawValues) : nil
    }

    private func lane(title: String, symbol: String, rate: Double?, color: Color, forward: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title)
                Spacer(minLength: 0)
                Text(rate.map { fmt.rate($0) } ?? "–").monospacedDigit()
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color.opacity(0.9))
            FlowStream(rate: rate, color: color, forward: forward, thickness: 4)
                .frame(height: 16)
        }
    }

    private func node(symbol: String, title: String, detail: String?, color: Color, active: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(active ? (theme.isDark ? 0.32 : 0.22) : 0.08), color.opacity(0.02)],
                                         center: .center, startRadius: 0, endRadius: 46))
                Circle()
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(theme.isDark ? 0.28 : 0.85),
                                                          color.opacity(active ? 0.45 : 0.15)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(active ? theme.textPrimary : theme.textTertiary)
            }
            .frame(width: 84, height: 84)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(Typo.mono)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 130)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dieser Mac

/// Produktbühne: Gerät (Illustration der Modellfamilie) mit den Kenndaten von macOS ringsum.
/// Vergleichbar – zeichnet sich nur neu, wenn sich die Angaben ändern (die Seite wird sonst jede Sekunde neu
/// berechnet, weil sie auch Laufwerke und Batterie beobachtet).
struct HardwareHero: View, Equatable {
    @Environment(\.aether) private var theme
    let hardware: HardwareSummary
    let chip: String?
    let totalCores: Int?

    static func == (a: HardwareHero, b: HardwareHero) -> Bool {
        a.hardware == b.hardware && a.chip == b.chip && a.totalCores == b.totalCores
    }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 24) {
                BigFigure(label: tr("Chip"), value: chipName, size: .small, source: .hardwareSysctl)
                coresFigure
            }
            .frame(width: 210, alignment: .leading)
            VStack(spacing: 10) {
                DeviceArt(model: hardware.macModel, kind: hardware.kind) {
                    ProductScreen(title: chipName, subtitle: hardware.osVersion.map { "macOS \($0)" })
                }
                .frame(height: 250)
                Label(hardware.macModel.map { tr("Illustration of %@ – not a photo of this Mac.", $0.displayName) }
                          ?? tr("Illustration of the model family – not a photo of this Mac."), systemImage: "info.circle")
                    .font(StudioType.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 24) {
                memoryFigure
                if let os = hardware.osVersion {
                    BigFigure(label: "macOS", value: os, detail: hardware.osBuild.map { tr("Build %@", $0) }, size: .small,
                              source: .osVersion)
                } else {
                    BigFigure(label: "macOS", value: "–", size: .small, source: .osVersion, reason: .queryFailed)
                }
                uptimeFigure
            }
            .frame(width: 200, alignment: .leading)
        }
    }

    private var chipName: String {
        chip ?? hardware.processor?.displayName ?? "–"
    }

    @ViewBuilder
    private var coresFigure: some View {
        let summary = coreSummary(hardware)
        if let cores = totalCores ?? hardware.physicalCores {
            BigFigure(label: tr("CPU cores"), value: fmt.integer(cores), detail: summary.isEmpty ? nil : summary, size: .small,
                      source: .cpuTopology)
        } else {
            BigFigure(label: tr("CPU cores"), value: "–", size: .small, source: .cpuTopology, reason: .queryFailed)
        }
    }

    @ViewBuilder
    private var memoryFigure: some View {
        if let memory = hardware.physicalMemory {
            let parts = fmt.byteParts(Double(memory), style: .memory)
            BigFigure(label: hardware.isAppleSilicon ? tr("Unified memory") : tr("Memory"), value: parts.value, unit: parts.unit,
                      size: .small, source: .hardwareSysctl)
        } else {
            BigFigure(label: tr("Memory"), value: "–", size: .small, source: .hardwareSysctl, reason: .queryFailed)
        }
    }

    /// Betriebszeit: zählt selbst weiter (alle 30 s), damit die vergleichbare Bühne nicht neu gezeichnet werden muss.
    @ViewBuilder
    private var uptimeFigure: some View {
        if let boot = hardware.bootTime {
            TimelineView(.periodic(from: Date(), by: 30)) { _ in
                BigFigure(label: tr("Uptime"), value: fmt.duration(seconds: Uptime.seconds(bootTime: boot)), size: .small,
                          source: .uptime)
            }
        } else {
            BigFigure(label: tr("Uptime"), value: "–", size: .small, source: .uptime, reason: .queryFailed)
        }
    }
}

/// Bildschirm der Illustration: ruhiger Verlauf mit Chip und macOS-Version – dekorativ.
private struct ProductScreen: View {
    @Environment(\.aether) private var theme
    let title: String
    let subtitle: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.03, green: 0.03, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [theme.accent.opacity(0.38), .clear], center: UnitPoint(x: 0.5, y: 1.05),
                           startRadius: 0, endRadius: 170)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
