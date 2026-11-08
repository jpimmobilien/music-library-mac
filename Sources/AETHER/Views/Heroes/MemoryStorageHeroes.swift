import SwiftUI
import AetherCore

// =============================================================================================
// Hero-Visualisierungen „Arbeitsspeicher“ und „Speicher“ (Designsprache Studio).
//
// Ehrlichkeit: Die Höhen der Speicherschichten sind die gemessenen Anteile (host_statistics64), die Kapazitätsbänder
// die gemessenen Volume-Angaben. Das SSD-Modul selbst ist eine Illustration und so beschriftet; Datenströme laufen
// nur bei gemessener Datenträgeraktivität.
// =============================================================================================

// MARK: - Arbeitsspeicher

/// Kopf der Seite „Arbeitsspeicher“: Größe als Aussage, Speicherdruck (von macOS) als Erklärung, darunter die
/// Speicherschichten.
struct MemoryHeroHeader: View {
    @ObservedObject var memory: MemoryStore
    @ObservedObject var system: SystemStore
    let telemetry: Telemetry

    var body: some View {
        StudioHero(section: .memory, eyebrow: tr("Memory"), headline: headline, lead: lead, height: 340) {
            MemoryStrataHero(store: memory, telemetry: telemetry)
        }
    }

    private var headline: String {
        let hw = system.hardware
        guard let physical = hw.physicalMemory else { return tr("Memory") }
        let size = fmt.bytes(physical, style: .memory)
        return hw.isAppleSilicon ? tr("%@ unified memory", size) : tr("%@ memory", size)
    }

    private var lead: String {
        var parts: [String] = []
        if let pressure = memory.snapshot?.pressure {
            if let level = pressure.value {
                parts.append(tr("Memory pressure: %@ – as reported by macOS.", pressureName(level)))
            } else {
                parts.append(tr("Memory pressure: not available – %@", (pressure.reason ?? .queryFailed).explanation))
            }
        } else {
            parts.append(tr("Measuring…"))
        }
        if system.hardware.isAppleSilicon {
            parts.append(tr("Shared by CPU, GPU and Neural Engine – there is no separate graphics memory."))
        }
        return parts.joined(separator: " ")
    }
}

/// Speicherschichten: eine Glassäule, deren Schichten die gemessenen Anteile zeigen, daneben die Zahlen und der
/// Verlauf.
private struct MemoryStrataHero: View {
    @ObservedObject var store: MemoryStore
    @Environment(\.aether) private var theme
    let telemetry: Telemetry
    @AppStorage("aether.memory.range") private var range: ChartRange = .fiveMinutes

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 780
            HStack(alignment: .top, spacing: 28) {
                if let b = store.snapshot?.breakdown.value {
                    StrataColumn(strata: strata(b))
                        .frame(width: wide ? 132 : 108)
                    if wide {
                        StrataLegend(strata: strata(b))
                            .frame(width: 186, alignment: .leading)
                    }
                } else {
                    emptyColumn
                        .frame(width: 120)
                }
                figures
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    // MARK: Zahlen und Verlauf

    private var figures: some View {
        let snapshot = store.snapshot
        let breakdown = snapshot?.breakdown.value
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                LiveFigure(metric: telemetry.value(.memoryUsed, unit: .bytes), label: tr("Memory used"),
                           format: FigureFormat.bytes, size: .giant, source: .vmStatistics,
                           unavailable: snapshot?.breakdown.reason ?? .awaitingSecondSample)
                HStack(spacing: 10) {
                    if let b = breakdown {
                        Text(tr("of %@", fmt.bytes(b.physical, style: .memory)))
                            .font(StudioType.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                    RawReadout(series: telemetry.series(.memoryUsed, unit: .bytes), format: { fmt.bytes($0, style: .memory) })
                }
            }
            HStack(alignment: .top, spacing: 20) {
                if let b = breakdown {
                    // Verfügbar = physisch − belegt = frei + Dateizwischenspeicher
                    let available = fmt.byteParts(Double(b.free &+ b.cached), style: .memory)
                    BigFigure(label: tr("Available"), value: available.value, unit: available.unit,
                              detail: tr("Free + cached files"), size: .small, source: .vmStatistics)
                } else {
                    BigFigure(label: tr("Available"), value: "–", size: .small)
                }
                FigureDivider()
                LiveFigure(metric: telemetry.value(.memoryCompressed, unit: .bytes), label: tr("Compressed"),
                           format: FigureFormat.bytes, size: .small, source: .vmStatistics,
                           unavailable: snapshot?.breakdown.reason ?? .awaitingSecondSample)
                FigureDivider()
                swapFigure(snapshot?.swap)
                FigureDivider()
                pressureFigure(snapshot?.pressure)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("History"))
                        .font(StudioType.label)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    RangePicker(range: $range)
                }
                if let physical = breakdown?.physical {
                    LiveChart(series: telemetry.series(.memoryUsed, unit: .bytes), range: range, color: theme.memory,
                              scale: .fixed(Double(physical)), height: 78, label: { fmt.bytes($0, style: .memory) })
                } else {
                    LiveChart(series: telemetry.series(.memoryUsed, unit: .bytes), range: range, color: theme.memory,
                              scale: .auto(minimum: 1_000_000_000), height: 78, label: { fmt.bytes($0, style: .memory) })
                }
            }
        }
    }

    @ViewBuilder
    private func swapFigure(_ swap: Reading<SwapUsage>?) -> some View {
        if let swap, let value = swap.value {
            let parts = fmt.byteParts(Double(value.used), style: .memory)
            BigFigure(label: tr("Swap used"), value: parts.value, unit: parts.unit,
                      detail: value.total > 0 ? tr("of %@", fmt.bytes(value.total, style: .memory)) : tr("No swap file in use."),
                      color: value.used > 0 ? theme.statusElevated : nil, size: .small, source: swap.source)
        } else {
            BigFigure(label: tr("Swap used"), value: "–", detail: (swap?.reason ?? .awaitingSecondSample).explanation,
                      size: .small, source: .swapUsage, reason: swap?.reason ?? .awaitingSecondSample)
        }
    }

    @ViewBuilder
    private func pressureFigure(_ pressure: Reading<PressureLevel>?) -> some View {
        if let pressure, let level = pressure.value {
            VStack(alignment: .leading, spacing: 6) {
                BigFigure(label: tr("Memory pressure"), value: pressureName(level), color: theme.color(for: level),
                          size: .small, source: pressure.source)
                HStack(spacing: 3) {
                    ForEach(PressureLevel.allCases, id: \.self) { step in
                        Capsule()
                            .fill(step <= level ? theme.color(for: level) : theme.fieldFill)
                            .frame(width: 20, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
        } else {
            BigFigure(label: tr("Memory pressure"), value: "–", size: .small, source: .memoryPressure,
                      reason: pressure?.reason ?? .awaitingSecondSample)
        }
    }

    private var emptyColumn: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(theme.fieldFill)
            .overlay(
                Text(store.snapshot == nil ? tr("Measuring…") : tr("Not available"))
                    .font(StudioType.caption)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(8)
            )
    }

    // MARK: Schichten

    /// Von oben nach unten: frei, Dateizwischenspeicher, komprimiert, fest zugeordnet, App-Speicher (belegt unten).
    private func strata(_ b: MemoryBreakdown) -> [Stratum] {
        [
            Stratum(id: "free", label: tr("Free"), bytes: b.free, color: theme.fieldFill, isUsed: false),
            Stratum(id: "cached", label: tr("Cached files"), bytes: b.cached, color: theme.memoryCached, isUsed: false),
            Stratum(id: "compressed", label: tr("Compressed"), bytes: b.compressed, color: theme.memoryCompressed, isUsed: true),
            Stratum(id: "wired", label: tr("Wired"), bytes: b.wired, color: theme.memoryWired, isUsed: true),
            Stratum(id: "app", label: tr("App memory"), bytes: b.app, color: theme.memory, isUsed: true),
        ]
    }
}

/// Eine Schicht der Säule.
private struct Stratum: Identifiable, Equatable {
    let id: String
    let label: String
    let bytes: UInt64
    let color: Color
    let isUsed: Bool
}

/// Glassäule mit Schichten; Höhen = gemessene Anteile. Bewegt sich nur bei sichtbarer Änderung (Raster 0,5 %).
private struct StrataColumn: View {
    @Environment(\.aether) private var theme
    let strata: [Stratum]

    var body: some View {
        let total = Double(max(1, strata.reduce(UInt64(0)) { $0 &+ $1.bytes }))
        let shares = strata.map { Double($0.bytes) / total }
        GeometryReader { geo in
            let inset: CGFloat = 6
            let height = max(0, geo.size.height - inset * 2)
            let spacing: CGFloat = 2
            let usable = max(0, height - spacing * CGFloat(strata.count - 1))
            ZStack {
                // Glaskörper (dekorativ)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [theme.fieldFill.opacity(0.9), theme.fieldFill.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                VStack(spacing: spacing) {
                    ForEach(Array(strata.enumerated()), id: \.element.id) { index, stratum in
                        let share = shares[index]
                        RoundedRectangle(cornerRadius: index == 0 || index == strata.count - 1 ? 16 : 4, style: .continuous)
                            .fill(stratum.id == "free"
                                  ? AnyShapeStyle(theme.fieldFill.opacity(0.6))
                                  : AnyShapeStyle(LinearGradient(colors: [stratum.color, stratum.color.opacity(0.72)],
                                                                 startPoint: .leading, endPoint: .trailing)))
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(Color.white.opacity(stratum.id == "free" ? 0 : (theme.isDark ? 0.22 : 0.4)))
                                    .frame(height: 1)
                            }
                            .frame(height: share > 0 ? max(1.5, usable * CGFloat(share)) : 0)
                    }
                }
                .padding(inset)
                .frame(maxHeight: .infinity, alignment: .bottom)
                // Glanzkante (dekorativ)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: Color.white.opacity(theme.isDark ? 0.10 : 0.35), location: 0),
                                                 .init(color: .clear, location: 0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.edgeLight.opacity(0.8), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .aetherAnimation(Motion.easeOut(0.45), value: shares.map { ($0 * 200).rounded() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strata.map { "\($0.label) \(fmt.bytes($0.bytes, style: .memory))" }.joined(separator: ", "))
    }
}

/// Beschriftung der Schichten in derselben Reihenfolge wie die Säule.
private struct StrataLegend: View {
    @Environment(\.aether) private var theme
    let strata: [Stratum]

    var body: some View {
        let total = Double(max(1, strata.reduce(UInt64(0)) { $0 &+ $1.bytes }))
        VStack(alignment: .leading, spacing: 12) {
            ForEach(strata) { stratum in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(stratum.id == "free" ? theme.fieldFill : stratum.color)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(theme.hairline, lineWidth: 0.5))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stratum.label)
                            .font(StudioType.label)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(fmt.bytes(stratum.bytes, style: .memory))
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                            Text(fmt.percent(Double(stratum.bytes) / total))
                                .font(StudioType.caption)
                                .monospacedDigit()
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
            Rectangle().fill(theme.hairline).frame(height: 1)
            Text(tr("Used = app memory + wired + compressed"))
                .font(StudioType.caption)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Speicher

/// Kopf der Seite „Speicher“: verfügbarer Platz des Startvolumes als Aussage, darunter SSD-Modul und Aktivität.
struct StorageHeroHeader: View {
    @ObservedObject var store: StorageStore
    let telemetry: Telemetry

    var body: some View {
        let startup = store.snapshot?.startup
        StudioHero(section: .storage, eyebrow: tr("Storage"),
                   headline: startup.map { tr("%@ available", fmt.bytes($0.effectiveAvailable)) } ?? tr("Storage"),
                   lead: startup.map(lead) ?? tr("Volumes, disk activity, SSD health and folder analysis"),
                   height: 300) {
            StorageHero(startup: startup, readReason: reason(store.snapshot?.readRate),
                        writeReason: reason(store.snapshot?.writeRate), telemetry: telemetry,
                        measuring: store.snapshot == nil)
        }
    }

    private func lead(_ v: VolumeInfo) -> String {
        var parts = [tr("“%@”", v.name)]
        if let format = v.format { parts.append(format) }
        parts.append(tr("%@ total", fmt.bytes(v.capacity)))
        if v.isEncrypted == true { parts.append(tr("Encrypted")) }
        return parts.joined(separator: "  ·  ")
    }

    /// Grund nur, wenn die Rate dauerhaft fehlt (nicht beim Warten auf die zweite Messung).
    private func reason(_ reading: Reading<Double>?) -> UnavailableReason? {
        guard let reading, reading.value == nil, let reason = reading.reason, reason != .awaitingSecondSample else { return nil }
        return reason
    }
}

private struct StorageHero: View {
    @Environment(\.aether) private var theme
    let startup: VolumeInfo?
    let readReason: UnavailableReason?
    let writeReason: UnavailableReason?
    let telemetry: Telemetry
    let measuring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let startup {
                SSDModuleArt(volume: startup)
                    .equatable()
                    .frame(maxWidth: 720)
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                CapacityLegend(volume: startup)
                    .frame(maxWidth: .infinity)
            } else {
                Text(measuring ? tr("Measuring…") : tr("No startup volume found"))
                    .font(Typo.callout)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
            HStack(alignment: .center, spacing: 32) {
                DiskLane(metric: telemetry.value(.diskRead, unit: .bytesPerSecond), title: tr("Read"),
                         color: theme.networkDown, forward: true, unavailable: readReason)
                DiskLane(metric: telemetry.value(.diskWrite, unit: .bytesPerSecond), title: tr("Write"),
                         color: theme.networkUp, forward: false, unavailable: writeReason)
            }
            Label(tr("Illustration – capacity values and disk activity are measured."), systemImage: "info.circle")
                .font(StudioType.caption)
                .foregroundStyle(theme.textTertiary)
                .help(tr("Disk activity: read and write rate of all disks"))
        }
    }
}

/// Lese- bzw. Schreibrate mit Datenstrom (Dichte und Tempo folgen der gemessenen Rate; 0 B/s → keine Partikel).
private struct DiskLane: View {
    @ObservedObject var metric: MetricValue
    @EnvironmentObject private var settings: AppSettings
    let title: String
    let color: Color
    let forward: Bool
    let unavailable: UnavailableReason?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            LiveFigure(metric: metric, label: title, format: FigureFormat.rate, color: color, size: .small,
                       source: .blockStorage, showPeak: true, unavailable: unavailable ?? .awaitingSecondSample)
                .frame(width: 150, alignment: .leading)
            FlowStream(rate: unavailable == nil && metric.isAvailable ? metric.display(raw: settings.showRawValues) : nil,
                       color: color, forward: forward, thickness: 3)
                .frame(height: 12)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Flaches SSD-Modul (Illustration) mit gemessenem Kapazitätsband: belegt · löschbar · frei.
private struct SSDModuleArt: View, Equatable {
    @Environment(\.aether) private var theme
    let volume: VolumeInfo

    static func == (a: SSDModuleArt, b: SSDModuleArt) -> Bool { a.volume == b.volume }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pinWidth = max(10, w * 0.035)
            ZStack(alignment: .topLeading) {
                // Bodenschatten (dekorativ)
                Ellipse()
                    .fill(RadialGradient(colors: [Color.black.opacity(theme.isDark ? 0.5 : 0.2), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.5))
                    .frame(width: w * 0.96, height: h * 0.22)
                    .offset(x: w * 0.02, y: h * 0.86)
                // Platine
                RoundedRectangle(cornerRadius: h * 0.1, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: h * 0.1, style: .continuous)
                        .strokeBorder(Color.white.opacity(theme.isDark ? 0.14 : 0.3), lineWidth: 1))
                    .frame(width: w, height: h * 0.9)
                // Steckkontakte links (dekorativ)
                VStack(spacing: h * 0.035) {
                    ForEach(0..<9, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.72, blue: 0.40),
                                                          Color(red: 0.62, green: 0.48, blue: 0.22)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: pinWidth, height: max(2, h * 0.045))
                    }
                }
                .frame(height: h * 0.9)
                .offset(x: 3)
                // Befestigungskerbe rechts (dekorativ)
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: h * 0.16, height: h * 0.16)
                    .offset(x: w - h * 0.24, y: h * 0.45 - h * 0.08)
                // Steuerchip und Speicherbausteine (dekorativ)
                HStack(spacing: w * 0.025) {
                    chip(width: w * 0.12, height: h * 0.28)
                    ForEach(0..<3, id: \.self) { _ in
                        chip(width: w * 0.17, height: h * 0.28)
                    }
                }
                .offset(x: pinWidth + w * 0.04, y: h * 0.1)
                // Kapazitätsband (gemessen)
                band
                    .frame(width: w - pinWidth - w * 0.08 - h * 0.3, height: h * 0.24)
                    .offset(x: pinWidth + w * 0.04, y: h * 0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("%@ of %@ used", fmt.bytes(volume.used), fmt.bytes(volume.capacity)))
    }

    private func chip(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
            .frame(width: width, height: height)
    }

    private var band: some View {
        let capacity = Double(max(volume.capacity, 1))
        let used = Double(volume.used) / capacity
        let purgeable = Double(volume.purgeable ?? 0) / capacity
        let critical = volume.usedFraction > 0.9
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient(colors: [critical ? theme.statusElevated : theme.storage,
                                                      (critical ? theme.statusElevated : theme.storage).opacity(0.75)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: w * CGFloat(min(1, used)))
                    Rectangle()
                        .fill(theme.storage.opacity(0.35))
                        .frame(width: w * CGFloat(min(max(0, 1 - used), purgeable)))
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule())
                Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            }
        }
    }
}

/// Zahlen zum Kapazitätsband.
private struct CapacityLegend: View {
    @Environment(\.aether) private var theme
    let volume: VolumeInfo

    var body: some View {
        HStack(spacing: 22) {
            LegendItem(color: volume.usedFraction > 0.9 ? theme.statusElevated : theme.storage, label: tr("Used"),
                       value: fmt.bytes(volume.used))
            if let purgeable = volume.purgeable, purgeable > 0 {
                LegendItem(color: theme.storage.opacity(0.35), label: tr("Purgeable"), value: fmt.bytes(purgeable))
                    .help(tr("Space macOS frees up automatically when needed (e.g. caches, local snapshots)."))
            }
            LegendItem(color: theme.fieldFill, label: tr("Free"), value: fmt.bytes(volume.available))
            ProvenanceBadge(source: .volumes)
        }
        .font(StudioType.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
