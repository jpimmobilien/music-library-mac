import Foundation
import SwiftUI
import ServiceManagement
import ABCore

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable, Codable {
    case bridge, blue, teal, purple, orange, graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bridge: return "Android Bridge"
        case .blue: return "Blau"
        case .teal: return "Türkis"
        case .purple: return "Violett"
        case .orange: return "Orange"
        case .graphite: return "Graphit"
        }
    }
    var color: Color {
        switch self {
        case .bridge: return Color(red: 0.04, green: 0.42, blue: 0.96)
        case .blue: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .teal: return Color(red: 0.19, green: 0.69, blue: 0.78)
        case .purple: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .orange: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .graphite: return Color(red: 0.45, green: 0.47, blue: 0.5)
        }
    }
}

enum FileManagerLayout: String, CaseIterable, Identifiable, Codable {
    case dual, single, gallery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dual: return "Zwei Spalten"
        case .single: return "Eine Spalte"
        case .gallery: return "Galerie"
        }
    }
    var symbolName: String {
        switch self {
        case .dual: return "rectangle.split.2x1"
        case .single: return "rectangle"
        case .gallery: return "square.grid.3x3"
        }
    }
}

enum VerificationLevel: String, CaseIterable, Identifiable, Codable {
    case size, checksum
    var id: String { rawValue }
    var title: String {
        switch self {
        case .size: return "Dateigröße prüfen"
        case .checksum: return "Größe + Prüfsumme (SHA-256, langsamer)"
        }
    }
}

enum UploadTarget: String, CaseIterable, Identifiable, Codable {
    case currentFolder, download, documents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .currentFolder: return "Geöffneter Ordner auf dem Telefon"
        case .download: return "Ordner „Download“"
        case .documents: return "Ordner „Documents“"
        }
    }
    var folderName: String? {
        switch self {
        case .currentFolder: return nil
        case .download: return "Download"
        case .documents: return "Documents"
        }
    }
}

/// Einstellungen je Gerät (über die Seriennummer zugeordnet).
struct DevicePreferences: Codable, Equatable {
    var customName: String?
    var lastStorageID: UInt32?
    var lastPath: [String] = []
    var autoConnect: Bool = true
}

/// Alle Einstellungen; dauerhaft in den Benutzervoreinstellungen (UserDefaults).
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var appearance: AppearanceMode { didSet { save("appearance", appearance.rawValue) } }
    @Published var accent: AccentChoice { didSet { save("accent", accent.rawValue) } }
    @Published var animations: Bool { didSet { save("animations", animations) } }
    @Published var glassEffects: Bool { didSet { save("glassEffects", glassEffects) } }

    @Published var launchAtLogin: Bool { didSet { if launchAtLogin != oldValue { applyLaunchAtLogin() } } }
    @Published var bringToFrontOnConnect: Bool { didSet { save("bringToFrontOnConnect", bringToFrontOnConnect) } }
    @Published var defaultLayout: FileManagerLayout { didSet { save("defaultLayout", defaultLayout.rawValue) } }
    @Published var downloadFolderPath: String { didSet { save("downloadFolderPath", downloadFolderPath) } }
    @Published var uploadTarget: UploadTarget { didSet { save("uploadTarget", uploadTarget.rawValue) } }

    @Published var smartDestinations: Bool { didSet { save("smartDestinations", smartDestinations) } }
    @Published var photoDestination: String { didSet { save("photoDestination", photoDestination) } }
    @Published var videoDestination: String { didSet { save("videoDestination", videoDestination) } }
    @Published var documentDestination: String { didSet { save("documentDestination", documentDestination) } }

    @Published var conflictResolution: ConflictResolution { didSet { save("conflictResolution", conflictResolution.rawValue) } }
    @Published var notifications: Bool { didSet { save("notifications", notifications) } }
    @Published var keepHistory: Bool { didSet { save("keepHistory", keepHistory) } }
    @Published var verification: VerificationLevel { didSet { save("verification", verification.rawValue) } }
    @Published var skipMacMetadata: Bool { didSet { save("skipMacMetadata", skipMacMetadata) } }
    @Published var showHiddenAndroidFiles: Bool { didSet { save("showHiddenAndroidFiles", showHiddenAndroidFiles) } }
    @Published var preserveDates: Bool { didSet { save("preserveDates", preserveDates) } }

    @Published var autoConnect: Bool { didSet { save("autoConnect", autoConnect) } }
    @Published var rememberDevicePreferences: Bool { didSet { save("rememberDevicePreferences", rememberDevicePreferences) } }
    @Published var connectionTimeout: Double { didSet { save("connectionTimeout", connectionTimeout) } }
    @Published var releasePhotoServiceAutomatically: Bool { didSet { save("releasePhotoServiceAutomatically", releasePhotoServiceAutomatically) } }
    @Published var devicePreferences: [String: DevicePreferences] { didSet { saveCodable("devicePreferences", devicePreferences) } }

    @Published var recentFilesEnabled: Bool { didSet { save("recentFilesEnabled", recentFilesEnabled) } }

    @Published var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func string(_ key: String, _ fallback: String) -> String { defaults.string(forKey: key) ?? fallback }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        appearance = AppearanceMode(rawValue: string("appearance", "")) ?? .system
        accent = AccentChoice(rawValue: string("accent", "")) ?? .bridge
        animations = bool("animations", true)
        glassEffects = bool("glassEffects", true)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        bringToFrontOnConnect = bool("bringToFrontOnConnect", true)
        defaultLayout = FileManagerLayout(rawValue: string("defaultLayout", "")) ?? .dual
        downloadFolderPath = string("downloadFolderPath", home + "/Downloads/Android Imports")
        uploadTarget = UploadTarget(rawValue: string("uploadTarget", "")) ?? .currentFolder
        smartDestinations = bool("smartDestinations", true)
        photoDestination = string("photoDestination", home + "/Pictures/Android Imports")
        videoDestination = string("videoDestination", home + "/Movies/Android Imports")
        documentDestination = string("documentDestination", home + "/Documents/Android Imports")
        conflictResolution = ConflictResolution(rawValue: string("conflictResolution", "")) ?? .ask
        notifications = bool("notifications", true)
        keepHistory = bool("keepHistory", true)
        verification = VerificationLevel(rawValue: string("verification", "")) ?? .size
        skipMacMetadata = bool("skipMacMetadata", true)
        showHiddenAndroidFiles = bool("showHiddenAndroidFiles", false)
        preserveDates = bool("preserveDates", true)
        autoConnect = bool("autoConnect", true)
        rememberDevicePreferences = bool("rememberDevicePreferences", true)
        let timeout = defaults.double(forKey: "connectionTimeout")
        connectionTimeout = timeout > 0 ? timeout : 30
        releasePhotoServiceAutomatically = bool("releasePhotoServiceAutomatically", false)
        if let data = defaults.data(forKey: "devicePreferences"),
           let prefs = try? JSONDecoder().decode([String: DevicePreferences].self, from: data) {
            devicePreferences = prefs
        } else {
            devicePreferences = [:]
        }
        recentFilesEnabled = bool("recentFilesEnabled", true)
    }

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }

    private func saveCodable<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Anmeldeobjekt konnte nicht geändert werden: \(error.localizedDescription). Liegt die App im Programme-Ordner?"
        }
    }

    /// Zielordner für eine Dateiart (intelligente Ziele) oder der Standard-Downloadordner.
    func destination(for kind: FileKind) -> URL {
        guard smartDestinations else { return URL(fileURLWithPath: downloadFolderPath, isDirectory: true) }
        switch kind {
        case .photo: return URL(fileURLWithPath: photoDestination, isDirectory: true)
        case .video: return URL(fileURLWithPath: videoDestination, isDirectory: true)
        case .document: return URL(fileURLWithPath: documentDestination, isDirectory: true)
        default: return URL(fileURLWithPath: downloadFolderPath, isDirectory: true)
        }
    }

    func preferences(forSerial serial: String) -> DevicePreferences {
        devicePreferences[serial] ?? DevicePreferences()
    }

    func updatePreferences(forSerial serial: String, _ change: (inout DevicePreferences) -> Void) {
        guard rememberDevicePreferences, !serial.isEmpty else { return }
        var p = devicePreferences[serial] ?? DevicePreferences()
        change(&p)
        if devicePreferences[serial] != p { devicePreferences[serial] = p }
    }

    func resetAll() {
        let keys = ["appearance", "accent", "animations", "glassEffects", "bringToFrontOnConnect", "defaultLayout",
                    "downloadFolderPath", "uploadTarget", "smartDestinations", "photoDestination", "videoDestination",
                    "documentDestination", "conflictResolution", "notifications", "keepHistory", "verification",
                    "skipMacMetadata", "showHiddenAndroidFiles", "preserveDates", "autoConnect", "rememberDevicePreferences",
                    "connectionTimeout", "releasePhotoServiceAutomatically", "devicePreferences", "recentFilesEnabled"]
        keys.forEach { defaults.removeObject(forKey: $0) }
        let fresh = SettingsStore(defaults: defaults)
        appearance = fresh.appearance; accent = fresh.accent; animations = fresh.animations; glassEffects = fresh.glassEffects
        bringToFrontOnConnect = fresh.bringToFrontOnConnect; defaultLayout = fresh.defaultLayout
        downloadFolderPath = fresh.downloadFolderPath; uploadTarget = fresh.uploadTarget
        smartDestinations = fresh.smartDestinations; photoDestination = fresh.photoDestination
        videoDestination = fresh.videoDestination; documentDestination = fresh.documentDestination
        conflictResolution = fresh.conflictResolution; notifications = fresh.notifications; keepHistory = fresh.keepHistory
        verification = fresh.verification; skipMacMetadata = fresh.skipMacMetadata
        showHiddenAndroidFiles = fresh.showHiddenAndroidFiles; preserveDates = fresh.preserveDates
        autoConnect = fresh.autoConnect; rememberDevicePreferences = fresh.rememberDevicePreferences
        connectionTimeout = fresh.connectionTimeout; releasePhotoServiceAutomatically = fresh.releasePhotoServiceAutomatically
        devicePreferences = fresh.devicePreferences; recentFilesEnabled = fresh.recentFilesEnabled
    }
}
