import SwiftUI
import AppKit
import AetherCore

/// Die elf Bereiche der App.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, activity, cpuGPU, memory, thermal, battery, hardware, storage, files, network, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return tr("Overview")
        case .activity: return tr("Activity")
        case .cpuGPU: return tr("CPU & GPU")
        case .memory: return tr("Memory")
        case .thermal: return tr("Temperature & Fans")
        case .battery: return tr("Battery")
        case .hardware: return tr("Hardware")
        case .storage: return tr("Storage")
        case .files: return tr("Files")
        case .network: return tr("Network")
        case .settings: return tr("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "circle.hexagongrid"
        case .activity: return "list.bullet.rectangle"
        case .cpuGPU: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .battery: return SymbolName.battery
        case .hardware: return "laptopcomputer"
        case .storage: return "internaldrive"
        case .files: return "folder"
        case .network: return "network"
        case .settings: return "gearshape"
        }
    }

    /// Gruppen der Seitenleiste.
    enum SidebarGroup: CaseIterable {
        case main, performance, hardware, data

        var title: String? {
            switch self {
            case .main: return nil
            case .performance: return tr("Performance")
            case .hardware: return tr("Hardware & Energy")
            case .data: return tr("Data")
            }
        }

        var sections: [AppSection] {
            switch self {
            case .main: return [.overview]
            case .performance: return [.activity, .cpuGPU, .memory]
            case .hardware: return [.thermal, .battery, .hardware]
            case .data: return [.storage, .files, .network]
            }
        }
    }

    /// Kurzbefehl ⌘1 … ⌘0.
    var shortcut: KeyEquivalent? {
        switch self {
        case .overview: return "1"
        case .activity: return "2"
        case .cpuGPU: return "3"
        case .memory: return "4"
        case .thermal: return "5"
        case .battery: return "6"
        case .hardware: return "7"
        case .storage: return "8"
        case .files: return "9"
        case .network: return "0"
        case .settings: return nil
        }
    }

    /// Entwicklungsphase, in der der Bereich vollständig umgesetzt wird (siehe docs/KONZEPT.md).
    var plannedPhase: Int? {
        switch self {
        case .overview, .settings: return nil
        case .activity, .cpuGPU, .memory, .thermal, .battery, .hardware: return nil
        case .storage, .files: return 6
        case .network: return 7
        }
    }
}

/// Startart: normal, Selbsttest oder Bildschirmfotos (nur in der Build-Pipeline).
enum LaunchMode {
    case normal
    case selfTest(URL)
    case snapshot(URL)

    static func fromArguments(_ arguments: [String] = CommandLine.arguments) -> LaunchMode {
        if let index = arguments.firstIndex(of: "--selftest"), index + 1 < arguments.count {
            return .selfTest(URL(fileURLWithPath: arguments[index + 1]))
        }
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            return .snapshot(URL(fileURLWithPath: arguments[index + 1]))
        }
        return .normal
    }

    var isAutomated: Bool {
        if case .normal = self { return false }
        return true
    }

    /// Fotomodus: zeigt das Design auch dann mit Glas, wenn am Build-Rechner „Transparenz reduzieren“ an ist.
    var isSnapshot: Bool {
        if case .snapshot = self { return true }
        return false
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: AppSection = .overview {
        didSet {
            if selection != oldValue { updateDemand() }
        }
    }
    @Published var sidebarVisible = true
    @Published var editingDashboard = false

    let settings: AppSettings
    let engine: MonitorEngine
    let launchMode: LaunchMode
    private var started = false
    private var windowVisible = true
    private var appActive = true

    init(launchMode: LaunchMode = .fromArguments()) {
        self.launchMode = launchMode
        settings = AppSettings(persist: !launchMode.isAutomated)
        engine = MonitorEngine()
    }

    func start() {
        guard !started else { return }
        started = true
        engine.loadStaticInfo()
        engine.start(interval: settings.effectiveInterval)
        updateDemand()
    }

    /// Teure Messungen nur, solange ein Bereich sie zeigt.
    func updateDemand() {
        engine.setProcessDemand([.activity, .cpuGPU, .memory].contains(selection))
    }

    func intervalChanged() {
        engine.setInterval(settings.effectiveInterval)
    }

    /// Messungen ruhen, solange das Fenster nicht zu sehen ist.
    func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
        updateRunning()
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        updateRunning()
    }

    private func updateRunning() {
        guard started, !launchMode.isAutomated else { return }
        if windowVisible {
            engine.start(interval: settings.effectiveInterval)
        } else {
            engine.stop()
        }
    }

    func select(_ section: AppSection) {
        selection = section
    }

    /// Prozess, der in der Aktivität ausgewählt werden soll (z. B. aus „Größte Verbraucher“).
    @Published var focusedPID: Int32?

    func focusProcess(_ pid: Int32) {
        focusedPID = pid
        selection = .activity
    }
}
