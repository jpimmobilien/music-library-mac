import SwiftUI
import AppKit
import Combine
import CoreGraphics
import UniformTypeIdentifiers
import AetherCore
import AetherSystem

/// Hardware: Modell, Prozessor, Speicher, Grafik, Bildschirme, Laufwerke, Batterie, Software.
/// Die Seriennummer wird nur auf Klick gelesen; der Systembericht wird nur lokal gespeichert.
struct HardwareView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme

    var body: some View {
        let engine = model.engine
        HardwareContent(system: engine.system, gpu: engine.gpu, storage: engine.storage, power: engine.power,
                        isSnapshot: model.launchMode.isSnapshot)
    }
}

private enum SerialState: Equatable {
    case hidden, loading, shown(String), unavailable
}

private struct HardwareContent: View {
    @ObservedObject var system: SystemStore
    @ObservedObject var gpu: GPUStore
    @ObservedObject var storage: StorageStore
    @ObservedObject var power: PowerStore
    let isSnapshot: Bool
    @Environment(\.aether) private var theme
    @State private var serial: SerialState = .hidden
    @State private var displays: [DisplayDescription] = []
    @State private var exporting = false
    @State private var includeSerial = false
    @State private var exportMessage: (text: String, url: URL?)?

    var body: some View {
        let sections = HardwareReport.sections(system: system, gpu: gpu, storage: storage, power: power, displays: displays)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                StudioHero(section: .hardware, eyebrow: tr("This Mac"),
                           headline: system.hardware.machineName ?? system.profiler?.machineName ?? tr("This Mac"),
                           lead: headerSubtitle, height: 320) {
                    Button {
                        exporting = true
                    } label: {
                        Label(tr("Export Report…"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                } hero: {
                    // Seriennummer bewusst nicht in der Bühne – sie bleibt hinter „Anzeigen“ (SerialPanel).
                    HardwareHero(hardware: system.hardware, chip: system.profiler?.chip,
                                 totalCores: system.profiler?.totalCores)
                        .equatable()
                }
                if let message = exportMessage {
                    HStack(spacing: Spacing.m) {
                        NoticeBar(text: message.text, symbol: message.url == nil ? "exclamationmark.triangle" : "checkmark.circle")
                        if let url = message.url {
                            Button(tr("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .buttonStyle(CapsuleButtonStyle())
                        }
                    }
                }
                SerialPanel(state: $serial)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: theme.density.cardSpacing, alignment: .top)],
                          alignment: .leading, spacing: theme.density.cardSpacing) {
                    ForEach(sections) { section in
                        Panel {
                            PanelTitle(title: section.title, symbol: section.symbol)
                            if section.rows.isEmpty {
                                Text(placeholder(for: section)).font(Typo.callout).foregroundStyle(theme.textSecondary)
                            }
                            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                                InfoRow(label: row.label, value: row.value, source: row.source)
                                    .help(row.value)
                            }
                        }
                    }
                }
                NoticeBar(text: tr("All values come from macOS on this Mac. ORBIT doesn’t send anything – the report is only saved where you choose."),
                          symbol: "lock.shield")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
        .onAppear { displays = DisplayCatalog.current() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = DisplayCatalog.current()
        }
        .sheet(isPresented: $exporting) {
            ExportSheet(includeSerial: $includeSerial) {
                exporting = false
            } save: {
                exporting = false
                export(sections: sections)
            }
        }
    }

    private var headerSubtitle: String {
        let hw = system.hardware
        return [hw.modelIdentifier, system.profiler?.modelNumber, hw.osVersion.map { "macOS \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func placeholder(for section: ReportSection) -> String {
        section.title == tr("Graphics") && !gpu.devicesLoaded ? tr("Loading…") : tr("Not available")
    }

    private func export(sections: [ReportSection]) {
        guard !isSnapshot else { return }
        var all = sections
        if includeSerial {
            // Ausdrücklich angefordert: jetzt lesen, nur in diese Datei schreiben.
            let value = SerialNumberSource.read() ?? tr("Not available")
            if let index = all.firstIndex(where: { $0.title == tr("Mac") }) {
                all[index].rows.append(ReportRow(tr("Serial number"), value, source: .serialNumber, isSensitive: true))
            }
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "–"
        let now = Date()
        let dateText = DateFormatter.localizedString(from: now, dateStyle: .long, timeStyle: .short)
        let text = ReportFormatter.markdown(
            title: tr("System report – %@", system.hardware.machineName ?? system.profiler?.machineName ?? "Mac"),
            subtitle: tr("Created with ORBIT %@ on %@. Values as reported by macOS at that moment.", version, dateText),
            columns: (tr("Item"), tr("Value"), tr("Type")),
            sections: all, includeSensitive: includeSerial,
            footer: tr("Measured = read directly · Computed = calculated by ORBIT · Reported by macOS = system information or manufacturer data · Estimate = estimate by macOS."),
            describe: { $0.provenance.title })

        let panel = NSSavePanel()
        panel.title = tr("Export System Report")
        panel.nameFieldStringValue = ReportFormatter.fileName(prefix: tr("ORBIT-System-Report"), date: now)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = (tr("Report saved: %@", url.lastPathComponent), url)
        } catch {
            exportMessage = (tr("The report couldn’t be saved: %@", error.localizedDescription), nil)
        }
    }
}

/// Seriennummer: verborgen, bis der Nutzer sie ausdrücklich anzeigen lässt; wird nirgends gespeichert.
private struct SerialPanel: View {
    @Binding var state: SerialState
    @Environment(\.aether) private var theme

    var body: some View {
        Panel {
            HStack(spacing: Spacing.m) {
                Image(systemName: "number").foregroundStyle(theme.textSecondary)
                Text(tr("Serial number")).font(Typo.bodyMedium)
                Spacer(minLength: Spacing.s)
                switch state {
                case .hidden:
                    Text(tr("Hidden")).font(Typo.callout).foregroundStyle(theme.textTertiary)
                    Button(tr("Show")) { reveal() }.buttonStyle(CapsuleButtonStyle())
                case .loading:
                    ProgressView().controlSize(.small)
                case .shown(let value):
                    Text(value).font(Typo.mono.weight(.medium)).textSelection(.enabled)
                    ProvenanceBadge(source: .serialNumber)
                    Button(tr("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }
                    .buttonStyle(CapsuleButtonStyle())
                    Button(tr("Hide")) { state = .hidden }.buttonStyle(CapsuleButtonStyle())
                case .unavailable:
                    UnavailableValue(reason: .notProvidedByMacOS, source: .serialNumber, compact: true)
                }
            }
            Text(tr("Only read when you click “Show”. ORBIT doesn’t store or transmit it."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary)
        }
    }

    private func reveal() {
        state = .loading
        DispatchQueue.global(qos: .userInitiated).async {
            let value = SerialNumberSource.read()
            DispatchQueue.main.async { state = value.map(SerialState.shown) ?? .unavailable }
        }
    }
}

private struct ExportSheet: View {
    @Binding var includeSerial: Bool
    let cancel: () -> Void
    let save: () -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(tr("Export System Report")).font(.system(size: 17, weight: .semibold))
            Text(tr("The report contains the values shown on this page as a Markdown file. It is only saved on this Mac, in the place you choose – nothing is sent."))
                .font(Typo.body).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Toggle(tr("Include serial number"), isOn: $includeSerial)
            Text(tr("Leave this off if you want to share the report."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary)
            HStack {
                Spacer()
                Button(tr("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(tr("Save…"), action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 440)
    }
}

// MARK: - Inhalt (gemeinsam für Anzeige und Bericht)

enum HardwareReport {
    @MainActor
    static func sections(system: SystemStore, gpu: GPUStore, storage: StorageStore, power: PowerStore,
                         displays: [DisplayDescription]) -> [ReportSection] {
        let hw = system.hardware
        let profiler = system.profiler
        var result: [ReportSection] = []

        // Mac
        var mac: [ReportRow] = []
        if let name = profiler?.machineName ?? hw.machineName { mac.append(ReportRow(tr("Model"), name, source: .systemProfiler)) }
        if let identifier = hw.modelIdentifier { mac.append(ReportRow(tr("Model identifier"), identifier, source: .hardwareSysctl)) }
        if let number = profiler?.modelNumber { mac.append(ReportRow(tr("Model number"), number, source: .systemProfiler)) }
        mac.append(ReportRow(tr("Type"), deviceKindName(hw.kind), source: .systemProfiler))
        if hw.isVirtualMachine && hw.kind != .virtualMachine {
            mac.append(ReportRow(tr("Environment"), tr("Virtual Mac"), source: .hardwareSysctl))
        }
        result.append(ReportSection(title: tr("Mac"), symbol: deviceSymbol(hw.kind), rows: mac))

        // Prozessor
        var cpu: [ReportRow] = []
        if let chip = profiler?.chip ?? hw.processor?.displayName { cpu.append(ReportRow(tr("Chip"), chip, source: .hardwareSysctl)) }
        cpu.append(ReportRow(tr("Architecture"), architectureDescription(hw), source: .hardwareSysctl))
        let cores = coreSummary(hw)
        if !cores.isEmpty { cpu.append(ReportRow(tr("Cores"), cores, source: .cpuTopology)) }
        if let logical = hw.logicalCores { cpu.append(ReportRow(tr("Logical processors"), fmt.integer(logical), source: .cpuTopology)) }
        if let hz = hw.nominalFrequency, hz > 0 {
            cpu.append(ReportRow(tr("Nominal clock"), fmt.number(Double(hz) / 1e9, fractionDigits: 2) + " GHz", source: .hardwareSysctl))
        } else if let speed = profiler?.processorSpeed {
            cpu.append(ReportRow(tr("Nominal clock"), speed, source: .systemProfiler))
        }
        let caches: [(String, Int?)] = [(tr("L1 cache (instructions)"), hw.cacheL1Instruction), (tr("L1 cache (data)"), hw.cacheL1Data),
                                        (tr("L2 cache"), hw.cacheL2), (tr("L3 cache"), hw.cacheL3)]
        for (label, bytes) in caches {
            if let bytes, bytes > 0 { cpu.append(ReportRow(label, fmt.bytes(UInt64(bytes), style: .memory), source: .hardwareSysctl)) }
        }
        result.append(ReportSection(title: tr("Processor"), symbol: "cpu", rows: cpu))

        // Arbeitsspeicher
        var memory: [ReportRow] = []
        if let bytes = hw.physicalMemory { memory.append(ReportRow(tr("Installed"), fmt.bytes(bytes, style: .memory), source: .hardwareSysctl)) }
        if let text = profiler?.memory { memory.append(ReportRow(tr("System Information"), text, source: .systemProfiler)) }
        if hw.isAppleSilicon { memory.append(ReportRow(tr("Design"), tr("Unified memory (shared by CPU and GPU)"), source: .hardwareSysctl)) }
        result.append(ReportSection(title: tr("Memory"), symbol: "memorychip", rows: memory))

        // Grafik
        let graphics = gpu.devices.map { device in
            ReportRow(device.name, gpuDetails(device), source: .gpuDevices)
        }
        result.append(ReportSection(title: tr("Graphics"), symbol: SymbolName.gpu, rows: graphics))

        // Bildschirme
        let screens = displays.map { display in
            ReportRow(display.name, display.summary, source: .displays)
        }
        result.append(ReportSection(title: tr("Displays"), symbol: SymbolName.display, rows: screens))

        // Laufwerke
        let volumes = (storage.snapshot?.volumes ?? []).filter { !$0.isNetwork }.map { volume in
            ReportRow(volume.name, volumeSummary(volume), source: .volumes)
        }
        result.append(ReportSection(title: tr("Storage"), symbol: SymbolName.ssd, rows: volumes))

        // Batterie
        if let b = power.battery, b.isPresent {
            var battery: [ReportRow] = []
            if let condition = power.profiler?.condition ?? b.systemCondition {
                battery.append(ReportRow(tr("Condition (macOS)"), condition, source: power.profiler?.condition != nil ? .powerProfiler : .powerSources))
            }
            if let maximum = power.profiler?.maximumCapacity { battery.append(ReportRow(tr("Maximum capacity (Apple)"), maximum, source: .powerProfiler)) }
            if let health = b.computedHealth.value {
                battery.append(ReportRow(tr("Capacity (computed)"), fmt.percent(health, fractionDigits: 1), source: .batteryHealth))
            }
            if let cycles = b.cycleCount.value { battery.append(ReportRow(tr("Charge cycles"), fmt.integer(cycles), source: .smartBattery)) }
            if let design = b.designCapacity.value { battery.append(ReportRow(tr("Design capacity"), "\(fmt.integer(design)) mAh", source: .smartBattery)) }
            result.append(ReportSection(title: tr("Battery"), symbol: SymbolName.battery, rows: battery))
        }

        // Software
        var software: [ReportRow] = []
        if let os = hw.osVersion { software.append(ReportRow("macOS", hw.osBuild.map { "\(os) (\($0))" } ?? os, source: .osVersion)) }
        if let kernel = hw.kernelVersion { software.append(ReportRow(tr("Kernel"), kernel, source: .osVersion)) }
        if let boot = hw.bootTime {
            software.append(ReportRow(tr("Uptime"), fmt.duration(seconds: Uptime.seconds(bootTime: boot)), source: .uptime))
            software.append(ReportRow(tr("Last startup"), DateFormatter.localizedString(from: boot, dateStyle: .medium, timeStyle: .short),
                                      source: .uptime))
        }
        let info = Bundle.main.infoDictionary ?? [:]
        software.append(ReportRow("ORBIT", "\(info["CFBundleShortVersionString"] as? String ?? "–") (\(info["CFBundleVersion"] as? String ?? "–"))"))
        software.append(ReportRow(tr("ORBIT runs as"), hw.isTranslated ? tr("Intel code via Rosetta") : (hw.isAppleSilicon ? "arm64" : "x86_64"),
                                  source: .hardwareSysctl))
        result.append(ReportSection(title: tr("Software"), symbol: "apple.logo", rows: software))
        return result
    }

    private static func volumeSummary(_ v: VolumeInfo) -> String {
        var parts = [tr("%@ of %@ free", fmt.bytes(v.availableForImportantUsage ?? v.available), fmt.bytes(v.capacity))]
        if let format = v.format { parts.append(format) }
        if v.isRoot { parts.append(tr("Startup disk")) } else if v.isInternal == false || v.isRemovable { parts.append(tr("External")) }
        if v.isEncrypted == true { parts.append(tr("Encrypted")) }
        if v.isReadOnly { parts.append(tr("Read-only")) }
        return parts.joined(separator: " · ")
    }
}

func architectureDescription(_ hw: HardwareSummary) -> String {
    let base = hw.isAppleSilicon ? tr("Apple Silicon (arm64)") : tr("Intel (x86_64)")
    return hw.isTranslated ? base + " · " + tr("running via Rosetta") : base
}

func deviceKindName(_ kind: DeviceKind) -> String {
    switch kind {
    case .macBookPro: return "MacBook Pro"
    case .macBookAir: return "MacBook Air"
    case .macBook: return "MacBook"
    case .iMac: return "iMac"
    case .macMini: return "Mac mini"
    case .macStudio: return "Mac Studio"
    case .macPro: return "Mac Pro"
    case .virtualMachine: return tr("Virtual Mac")
    case .unknown: return tr("Mac (type not reported)")
    }
}

func gpuDetails(_ d: GPUDevice) -> String {
    var parts: [String] = []
    if let vendor = d.vendor { parts.append(vendor) }
    if let cores = d.coreCount { parts.append(tr("%ld cores", cores)) }
    if d.hasUnifiedMemory {
        parts.append(tr("Unified memory"))
    } else {
        switch d.kind {
        case .integrated: parts.append(tr("Integrated"))
        case .discrete: parts.append(tr("Dedicated"))
        case .external: parts.append(tr("External"))
        case .unknown: break
        }
        if let vram = d.vram { parts.append(vram) }
    }
    if let metal = d.metalSupport { parts.append(metal) }
    return parts.joined(separator: " · ")
}

// MARK: - Bildschirme (AppKit/CoreGraphics, öffentlich)

struct DisplayDescription: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let pointWidth: Int
    let pointHeight: Int
    let refreshRate: Double?
    let diagonalInches: Double?

    var summary: String {
        var parts = ["\(pixelWidth) × \(pixelHeight) px"]
        if pointWidth != pixelWidth { parts.append(tr("looks like %@", "\(pointWidth) × \(pointHeight)")) }
        if let refreshRate { parts.append(fmt.number(refreshRate, fractionDigits: 0) + " Hz") }
        if let diagonalInches { parts.append("≈ " + fmt.number(diagonalInches, fractionDigits: 1) + "″") }
        parts.append(isBuiltIn ? tr("Built-in") : tr("External"))
        if isMain { parts.append(tr("Main display")) }
        return parts.joined(separator: " · ")
    }
}

enum DisplayCatalog {
    @MainActor
    static func current() -> [DisplayDescription] {
        let main = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let mode = CGDisplayCopyDisplayMode(id)
            let scale = screen.backingScaleFactor
            let pixelWidth = mode?.pixelWidth ?? Int(screen.frame.width * scale)
            let pixelHeight = mode?.pixelHeight ?? Int(screen.frame.height * scale)
            var refresh = mode?.refreshRate ?? 0
            if refresh <= 0 { refresh = Double(screen.maximumFramesPerSecond) }
            let size = CGDisplayScreenSize(id)
            var diagonal: Double?
            if size.width > 0, size.height > 0 {
                let inches = (Double(size.width * size.width + size.height * size.height)).squareRoot() / 25.4
                diagonal = (8...60).contains(inches) ? inches : nil
            }
            return DisplayDescription(id: id, name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(id) != 0, isMain: id == main,
                                      pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                                      pointWidth: Int(screen.frame.width), pointHeight: Int(screen.frame.height),
                                      refreshRate: (1...500).contains(refresh) ? refresh : nil, diagonalInches: diagonal)
        }
    }
}
