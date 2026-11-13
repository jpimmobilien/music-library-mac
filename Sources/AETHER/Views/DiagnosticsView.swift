import SwiftUI
import AetherCore

// =============================================================================================
// Entwickler-Diagnose (Einstellungen → Messung): Eigenverbrauch und Zeiten der Messmaschine.
// Nur sichtbar und nur aktualisiert, wenn eingeschaltet – sonst kostet sie nichts.
// =============================================================================================

/// Ausführliche Tafel in den Einstellungen.
struct DiagnosticsPanel: View {
    @ObservedObject var diagnostics: EngineDiagnostics
    @Environment(\.aether) private var theme

    var body: some View {
        let s = diagnostics.snapshot
        VStack(alignment: .leading, spacing: Spacing.m) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                row(tr("ORBIT CPU"), s.ownCPU.map { fmt.percent($0, fractionDigits: 1) } ?? "–",
                    help: tr("Share of one CPU core used by ORBIT itself (all threads)."))
                row(tr("ORBIT memory"), s.ownMemory.map { fmt.bytes($0, style: .memory) } ?? "–",
                    help: tr("Physical memory footprint of ORBIT, as Activity Monitor shows it."))
                row(tr("Base interval"), tr("%@ s", fmt.number(s.interval, fractionDigits: s.interval < 1 ? 1 : 0)))
                row(tr("Measurement time per tick"), milliseconds(s.tickMs),
                    help: tr("Time the background measurement needs per tick (all sources due in this tick)."))
                row(tr("Publishing time per tick"), milliseconds(s.applyMs),
                    help: tr("Time on the main thread to hand the results to the views."))
                row(tr("Timer delay"), milliseconds(s.lateMs),
                    help: tr("How late the tick started compared with the schedule."))
                row(tr("Measurements per second"), fmt.number(s.ticksPerSecond, fractionDigits: 1),
                    help: tr("Regular ticks plus immediate measurements (e.g. after macOS reports a power change)."))
                row(tr("Sources per tick (max.)"), fmt.integer(s.activeSources))
                row(tr("Display updates per second"), fmt.number(s.publishesPerSecond, fractionDigits: 1),
                    help: tr("Large numbers are only redrawn when their rounded value changes."))
                row(tr("Process list"), s.processesActive ? tr("being measured") : tr("paused (not visible)"))
            }
            if !s.sources.isEmpty {
                Divider().overlay(theme.hairline)
                Text(tr("Measurement time per source (smoothed)"))
                    .font(Typo.captionMedium)
                    .foregroundStyle(theme.textSecondary)
                let sorted = s.sources.sorted { $0.value > $1.value }
                let top = max(0.001, sorted.first?.value ?? 1)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(sorted, id: \.key) { entry in
                        HStack(spacing: 10) {
                            Text(entry.key).font(Typo.mono).foregroundStyle(theme.textSecondary).frame(width: 110, alignment: .leading)
                            FillBar(fraction: entry.value / top, color: theme.accent, height: 5)
                            Text(milliseconds(entry.value)).font(Typo.caption).monospacedDigit().frame(width: 70, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, help: String? = nil) -> some View {
        GridRow {
            Text(label).font(Typo.callout).foregroundStyle(theme.textSecondary).help(help ?? "")
            Text(value).font(Typo.callout.weight(.medium)).monospacedDigit()
        }
    }
}

/// Kleine schwebende Anzeige unten rechts im Fenster (wenn die Diagnose an ist).
struct DiagnosticsHUD: View {
    @ObservedObject var diagnostics: EngineDiagnostics
    @Environment(\.aether) private var theme

    var body: some View {
        let s = diagnostics.snapshot
        HStack(spacing: 12) {
            Image(systemName: "stethoscope").foregroundStyle(theme.accent)
            item("CPU", s.ownCPU.map { fmt.percent($0, fractionDigits: 1) } ?? "–")
            item("RAM", s.ownMemory.map { fmt.bytes($0, style: .memory) } ?? "–")
            item(tr("Tick"), milliseconds(s.tickMs))
            item(tr("Main"), milliseconds(s.applyMs))
            item(tr("Late"), milliseconds(s.lateMs))
            item(tr("Upd./s"), fmt.number(s.publishesPerSecond, fractionDigits: 0))
        }
        .font(.system(size: 10.5, weight: .medium))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassSurface(Capsule(), strong: true, floating: true)
        .help(tr("Developer diagnostics – turn off in Settings → Monitoring."))
        .accessibilityElement(children: .combine)
    }

    private func item(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(theme.textTertiary)
            Text(value).foregroundStyle(theme.textPrimary)
        }
    }
}

private func milliseconds(_ value: Double) -> String {
    tr("%@ ms", fmt.number(value, fractionDigits: value < 10 ? 2 : 1))
}
