import Foundation

/// Beschreibung einer USB-Schnittstelle (aus der IORegistry).
public struct USBInterfaceDescriptor: Equatable, Hashable, Codable, Sendable {
    public var number: Int
    public var interfaceClass: Int
    public var subClass: Int
    public var interfaceProtocol: Int
    public var name: String?

    public init(number: Int, interfaceClass: Int, subClass: Int, interfaceProtocol: Int, name: String? = nil) {
        self.number = number
        self.interfaceClass = interfaceClass
        self.subClass = subClass
        self.interfaceProtocol = interfaceProtocol
        self.name = name
    }

    /// Standard-Bildgeräteklasse (PTP), von Android im Modus „PTP“ bzw. teils für MTP verwendet.
    public var isStillImage: Bool { interfaceClass == 0x06 && subClass == 0x01 && interfaceProtocol == 0x01 }
    /// Android-Debug-Bridge.
    public var isADB: Bool { interfaceClass == 0xFF && subClass == 0x42 && interfaceProtocol == 0x01 }
    /// Android Open Accessory / Android Auto u. ä.
    public var isAccessory: Bool { interfaceClass == 0xFF && subClass == 0xFF && (name?.lowercased().contains("accessory") ?? false) }
    /// Herstellerspezifische Schnittstelle mit „MTP“ im Namen (Android-MTP-Funktion).
    public var isNamedMTP: Bool {
        guard let n = name?.uppercased() else { return false }
        return n == "MTP" || n.hasPrefix("MTP") || n.contains(" MTP")
    }
    /// Herstellerspezifisch ohne Unterklasse – Kandidat für MTP, wenn das Gerät von einem Android-Hersteller stammt.
    public var isVendorGeneric: Bool { interfaceClass == 0xFF && subClass == 0xFF && interfaceProtocol == 0x00 }
    /// Mobile Daten-/Netzwerkfreigabe (RNDIS/NCM/ECM).
    public var isTethering: Bool {
        (interfaceClass == 0xE0 && subClass == 0x01 && interfaceProtocol == 0x03) || interfaceClass == 0x02 || interfaceClass == 0x0A
    }
    public var isMIDI: Bool { interfaceClass == 0x01 && subClass == 0x03 }
}

/// Was das angeschlossene Gerät gerade anbietet.
public enum USBDeviceMode: Equatable, Sendable {
    /// MTP/PTP-Schnittstelle vorhanden (Nummer der Schnittstelle).
    case fileTransfer(interface: Int, isPTPOnly: Bool)
    /// Android-Gerät ohne Dateiübertragung (nur Laden, ADB, Tethering, MIDI …).
    case androidWithoutFileTransfer
    /// Kein (erkennbares) Android-Gerät.
    case unrelated
}

public enum USBDeviceClassifier {
    /// Bekannte USB-Hersteller-IDs von Android-Geräten – nur für Anzeige und Erkennung „Telefon ohne
    /// Dateiübertragung“, nie als Voraussetzung für die Unterstützung (die erfolgt über die Schnittstellen).
    public static let androidVendors: [Int: String] = [
        0x18D1: "Google",
        0x04E8: "Samsung",
        0x2717: "Xiaomi",
        0x2A70: "OnePlus",
        0x22D9: "OPPO",
        0x22B8: "Motorola",
        0x0FCE: "Sony",
        0x12D1: "Huawei",
        0x339B: "Honor",
        0x1004: "LG",
        0x0BB4: "HTC",
        0x17EF: "Lenovo",
        0x19D2: "ZTE",
        0x0B05: "ASUS",
        0x2D95: "vivo",
        0x0E8D: "MediaTek",
        0x05C6: "Qualcomm",
    ]

    public static func vendorName(_ vendorID: Int) -> String? { androidVendors[vendorID] }

    public static func isKnownAndroidVendor(_ vendorID: Int) -> Bool { androidVendors[vendorID] != nil }

    /// Bestimmt den Modus anhand der Schnittstellen (protokollbasiert, ohne Modelllisten).
    public static func classify(vendorID: Int, interfaces: [USBInterfaceDescriptor]) -> USBDeviceMode {
        // Apple-Geräte (iPhone/iPad bieten ebenfalls PTP an) gehören nicht hierher.
        if vendorID == 0x05AC { return .unrelated }
        // 1. ausdrücklich „MTP“ benannte Schnittstelle
        if let mtp = interfaces.first(where: { $0.isNamedMTP }) {
            return .fileTransfer(interface: mtp.number, isPTPOnly: false)
        }
        // 2. herstellerspezifische Schnittstelle eines Android-Herstellers (MTP ohne Namen),
        //    aber nicht ADB oder Zubehör
        let androidHint = isKnownAndroidVendor(vendorID) || interfaces.contains(where: { $0.isADB })
        if androidHint, let generic = interfaces.first(where: { $0.isVendorGeneric && !$0.isAccessory && !$0.isADB }) {
            return .fileTransfer(interface: generic.number, isPTPOnly: false)
        }
        // 3. PTP (Bildgeräteklasse) – Android im Modus „PTP“ oder MTP mit Standardklasse
        if let ptp = interfaces.first(where: { $0.isStillImage }) {
            let named = ptp.name?.uppercased() ?? ""
            return .fileTransfer(interface: ptp.number, isPTPOnly: named == "PTP" && androidHint)
        }
        if androidHint { return .androidWithoutFileTransfer }
        return .unrelated
    }
}
