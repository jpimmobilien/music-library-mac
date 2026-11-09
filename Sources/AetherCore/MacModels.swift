import Foundation

// =============================================================================================
// Mac-Modelle seit 2017 – für die Geräte-Illustrationen (Vorderansicht in Übersicht/Hardware, Aufsicht der
// Wärmekarte). Zuordnung über die Modellkennung (`hw.model`), Quelle: Apple-Support-Artikel „Modell bestimmen“
// (MacBook Pro 108052, MacBook Air 102869, MacBook 103257, iMac 108054, Mac mini 102852, Mac Studio HT213073,
// Mac Pro 102887), Stand November 2026. Maße in Millimetern aus Apples technischen Daten (gerundet).
//
// Die Illustrationen sind eigene, vereinfachte Zeichnungen (keine Apple-Bilder, keine Logos/Schriftzüge). Sie zeigen
// Bauform, Proportionen und Merkmale der Modellreihe (Kerbe, Touch Bar, Lautsprecher, Keilform …) – nicht die Farbe
// des eigenen Geräts, die macOS Apps nicht mitteilt.
// =============================================================================================

public struct MacModelInfo: Sendable, Equatable {
    public enum Family: String, Sendable {
        case macBookPro, macBookAir, macBook, iMac, iMacPro, macMini, macStudio, macPro
    }

    /// Bauform (bestimmt die Zeichnung).
    public enum Design: String, Sendable, CaseIterable {
        /// MacBook Air 13″ bis 2017: breiter Aluminiumrahmen ums Display, Keilform
        case airClassic
        /// MacBook Air Retina 2018–2020 (Intel und M1): schwarzer Glasrand, Keilform, Lautsprecher neben der Tastatur
        case airRetina
        /// MacBook Air ab M2 (13″/15″): flaches Gehäuse, Kerbe, Lautsprecher im Scharnier
        case airFlat
        /// MacBook 12″ (2017): sehr flach, Keilform, Lautsprechergitter über der Tastatur
        case macBook12
        /// MacBook Pro 13″ 2017 mit zwei Anschlüssen: Funktionstasten statt Touch Bar
        case proFunctionKeys
        /// MacBook Pro 13″/15″/16″ mit Touch Bar (2016–2022)
        case proTouchBar
        /// MacBook Pro 14″/16″ ab 2021: Kerbe, Funktionstasten in voller Höhe
        case proNotch
        /// MacBook Pro mit PROLED-XDR-Display (2026): Dynamic Island statt Kerbe
        case proIsland
        /// iMac 21,5″/27″ (2017–2020): schwarzer Glasrand, Aluminium-Kinn
        case iMacClassic
        /// iMac Pro (2017): wie iMac 27″, Space Grau
        case iMacPro
        /// iMac 24″ ab 2021: sehr flach, helles Display-Rand, farbiges Kinn
        case iMac24
        /// Mac mini 19,7 cm (2014–2023)
        case miniClassic
        /// Mac mini 12,7 cm (ab 2024)
        case miniCompact
        /// Mac Studio
        case studio
        /// Mac Pro (Ende 2013): Zylinder
        case proCylinder
        /// Mac Pro 2019/2023: Turm mit Lochgitter
        case proTower

        public var isPortable: Bool {
            switch self {
            case .airClassic, .airRetina, .airFlat, .macBook12, .proFunctionKeys, .proTouchBar, .proNotch, .proIsland: return true
            default: return false
            }
        }

        public var hasBuiltInDisplay: Bool { isPortable || self == .iMacClassic || self == .iMacPro || self == .iMac24 }
    }

    /// Modellkennung (z. B. „MacBookPro15,2“); bei geschätzter Zuordnung die gemeldete Kennung oder leer.
    public let identifier: String
    public let family: Family
    public let design: Design
    /// Bildschirmdiagonale in Zoll (Apples Angabe), sonst `nil`
    public let inches: Double?
    /// Unterscheidung innerhalb der Reihe – sprachneutral (z. B. „2018–2019 · 4× Thunderbolt 3“, „M3, 2024“)
    public let variant: String
    /// Gehäusemaße (mm): Breite, Tiefe, Höhe
    public let width: Double
    public let depth: Double
    public let height: Double
    /// true = über die Modellkennung sicher erkannt; false = aus Gerätefamilie/Bildschirmgröße geschätzt
    public let exact: Bool

    /// Gehäusefarbe – nur bei Modellen, die es in genau einer Farbe gab (sonst `nil`: macOS teilt Apps die Farbe nicht
    /// mit, die Illustration bleibt neutral).
    public enum Finish: String, Sendable { case silver, spaceGray, black }
    public var finish: Finish? {
        switch design {
        case .airClassic, .iMacClassic, .studio, .proTower, .miniCompact: return .silver
        case .iMacPro: return .spaceGray
        case .proCylinder: return .black
        case .miniClassic: return identifier == "Macmini8,1" ? .spaceGray : .silver
        default: return nil
        }
    }

    public init(identifier: String, family: Family, design: Design, inches: Double?, variant: String,
                width: Double, depth: Double, height: Double, exact: Bool = true) {
        self.identifier = identifier
        self.family = family
        self.design = design
        self.inches = inches
        self.variant = variant
        self.width = width
        self.depth = depth
        self.height = height
        self.exact = exact
    }

    /// Produktname ohne Variante, z. B. „MacBook Pro 13″“, „iMac 24″“, „Mac Studio“.
    public var productName: String {
        let base: String
        switch family {
        case .macBookPro: base = "MacBook Pro"
        case .macBookAir: base = "MacBook Air"
        case .macBook: base = "MacBook"
        case .iMac: base = "iMac"
        case .iMacPro: base = "iMac Pro"
        case .macMini: base = "Mac mini"
        case .macStudio: base = "Mac Studio"
        case .macPro: base = "Mac Pro"
        }
        guard let inches, family != .iMacPro else { return base }
        return base + " " + MacModelInfo.inchLabel(inches) + "″"
    }

    /// „13“, „15“, „21,5“ bzw. „21.5“ – Apples Größenbezeichnung (13,3″ heißt „13″“, 14,2″ „14″“ usw.).
    public static func inchLabel(_ inches: Double, decimalSeparator: String = ".") -> String {
        let nominal: Double
        switch inches {
        case 21.4...21.6: nominal = 21.5
        default: nominal = inches.rounded(.down)
        }
        if nominal == nominal.rounded() { return String(Int(nominal)) }
        return String(format: "%.1f", nominal).replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

public enum MacModelCatalog {
    // Gehäusemaße je Bauform/Größe (mm: Breite, Tiefe, Höhe)
    private typealias Size = (w: Double, d: Double, h: Double)
    private static let pro13: Size = (304.1, 212.4, 14.9)
    private static let pro15: Size = (349.3, 240.7, 15.5)
    private static let pro16_2019: Size = (357.9, 245.9, 16.2)
    private static let pro14: Size = (312.6, 221.2, 15.5)
    private static let pro16: Size = (355.7, 248.1, 16.8)
    private static let proOLED14: Size = (310.8, 216.3, 15.0)
    private static let proOLED16: Size = (355.5, 244.2, 16.0)
    private static let air2017: Size = (325.0, 227.0, 17.0)
    private static let airRetina: Size = (304.1, 212.4, 15.6)
    private static let air13: Size = (304.1, 215.0, 11.3)
    private static let air15: Size = (340.4, 237.6, 11.5)
    private static let macBook12: Size = (280.5, 196.5, 13.1)
    private static let iMac215: Size = (528.0, 175.0, 450.0)
    private static let iMac27: Size = (650.0, 203.0, 516.0)
    private static let iMac24: Size = (547.0, 147.0, 461.0)
    private static let miniClassic: Size = (197.0, 197.0, 36.0)
    private static let miniCompact: Size = (127.0, 127.0, 50.0)
    private static let studio: Size = (197.0, 197.0, 95.0)
    private static let proTower: Size = (218.0, 450.0, 529.0)
    private static let proCylinder: Size = (167.0, 167.0, 251.0)

    private static func m(_ ids: [String], _ family: MacModelInfo.Family, _ design: MacModelInfo.Design, _ inches: Double?,
                          _ variant: String, _ size: Size) -> [(String, MacModelInfo)] {
        ids.map { ($0, MacModelInfo(identifier: $0, family: family, design: design, inches: inches, variant: variant,
                                    width: size.w, depth: size.d, height: size.h)) }
    }

    /// Alle bekannten Modelle seit 2017 (und die 2017 noch verkauften Mac mini 2014 / Mac Pro 2013).
    public static let all: [String: MacModelInfo] = {
        var list: [(String, MacModelInfo)] = []
        // MacBook Pro
        list += m(["MacBookPro14,1"], .macBookPro, .proFunctionKeys, 13.3, "2017 · 2× Thunderbolt 3", pro13)
        list += m(["MacBookPro14,2"], .macBookPro, .proTouchBar, 13.3, "2017 · 4× Thunderbolt 3", pro13)
        list += m(["MacBookPro14,3"], .macBookPro, .proTouchBar, 15.4, "2017", pro15)
        list += m(["MacBookPro15,1"], .macBookPro, .proTouchBar, 15.4, "2018–2019", pro15)
        list += m(["MacBookPro15,2"], .macBookPro, .proTouchBar, 13.3, "2018–2019 · 4× Thunderbolt 3", pro13)
        list += m(["MacBookPro15,3"], .macBookPro, .proTouchBar, 15.4, "2019", pro15)
        list += m(["MacBookPro15,4"], .macBookPro, .proTouchBar, 13.3, "2019 · 2× Thunderbolt 3", pro13)
        list += m(["MacBookPro16,1", "MacBookPro16,4"], .macBookPro, .proTouchBar, 16.0, "2019", pro16_2019)
        list += m(["MacBookPro16,2"], .macBookPro, .proTouchBar, 13.3, "2020 · 4× Thunderbolt 3", pro13)
        list += m(["MacBookPro16,3"], .macBookPro, .proTouchBar, 13.3, "2020 · 2× Thunderbolt 3", pro13)
        list += m(["MacBookPro17,1"], .macBookPro, .proTouchBar, 13.3, "M1, 2020", (304.1, 212.4, 15.6))
        list += m(["Mac14,7"], .macBookPro, .proTouchBar, 13.3, "M2, 2022", (304.1, 212.4, 15.6))
        list += m(["MacBookPro18,3", "MacBookPro18,4"], .macBookPro, .proNotch, 14.2, "2021", pro14)
        list += m(["MacBookPro18,1", "MacBookPro18,2"], .macBookPro, .proNotch, 16.2, "2021", pro16)
        list += m(["Mac14,5", "Mac14,9"], .macBookPro, .proNotch, 14.2, "2023", pro14)
        list += m(["Mac14,6", "Mac14,10"], .macBookPro, .proNotch, 16.2, "2023", pro16)
        list += m(["Mac15,3"], .macBookPro, .proNotch, 14.2, "M3, 2023", pro14)
        list += m(["Mac15,6", "Mac15,8", "Mac15,10"], .macBookPro, .proNotch, 14.2, "M3 Pro/Max, 2023", pro14)
        list += m(["Mac15,7", "Mac15,9", "Mac15,11"], .macBookPro, .proNotch, 16.2, "M3 Pro/Max, 2023", pro16)
        list += m(["Mac16,1"], .macBookPro, .proNotch, 14.2, "M4, 2024", pro14)
        list += m(["Mac16,6", "Mac16,8"], .macBookPro, .proNotch, 14.2, "M4 Pro/Max, 2024", pro14)
        list += m(["Mac16,5", "Mac16,7"], .macBookPro, .proNotch, 16.2, "M4 Pro/Max, 2024", pro16)
        list += m(["Mac17,2"], .macBookPro, .proNotch, 14.2, "M5, 2025", pro14)
        list += m(["Mac17,7", "Mac17,9"], .macBookPro, .proNotch, 14.2, "M5 Pro/Max, 2026", pro14)
        list += m(["Mac17,6", "Mac17,8"], .macBookPro, .proNotch, 16.2, "M5 Pro/Max, 2026", pro16)
        list += m(["Mac17,11", "Mac17,13"], .macBookPro, .proIsland, 14.2, "PROLED XDR, 2026", proOLED14)
        list += m(["Mac17,10", "Mac17,12"], .macBookPro, .proIsland, 16.2, "PROLED XDR, 2026", proOLED16)
        list += m(["Mac18,1"], .macBookPro, .proNotch, 14.2, "M6", pro14)
        // MacBook Air
        list += m(["MacBookAir7,2"], .macBookAir, .airClassic, 13.3, "2017", air2017)
        list += m(["MacBookAir8,1"], .macBookAir, .airRetina, 13.3, "Retina, 2018", airRetina)
        list += m(["MacBookAir8,2"], .macBookAir, .airRetina, 13.3, "Retina, 2019", airRetina)
        list += m(["MacBookAir9,1"], .macBookAir, .airRetina, 13.3, "Retina, 2020", airRetina)
        list += m(["MacBookAir10,1"], .macBookAir, .airRetina, 13.3, "M1, 2020", airRetina)
        list += m(["Mac14,2"], .macBookAir, .airFlat, 13.6, "M2, 2022", air13)
        list += m(["Mac14,15"], .macBookAir, .airFlat, 15.3, "M2, 2023", air15)
        list += m(["Mac15,12"], .macBookAir, .airFlat, 13.6, "M3, 2024", air13)
        list += m(["Mac15,13"], .macBookAir, .airFlat, 15.3, "M3, 2024", air15)
        list += m(["Mac16,12"], .macBookAir, .airFlat, 13.6, "M4, 2025", air13)
        list += m(["Mac16,13"], .macBookAir, .airFlat, 15.3, "M4, 2025", air15)
        list += m(["Mac17,3"], .macBookAir, .airFlat, 13.6, "M5", air13)
        list += m(["Mac17,4"], .macBookAir, .airFlat, 15.3, "M5", air15)
        // MacBook
        list += m(["MacBook10,1"], .macBook, .macBook12, 12.0, "2017", macBook12)
        // iMac
        list += m(["iMac18,1"], .iMac, .iMacClassic, 21.5, "2017", iMac215)
        list += m(["iMac18,2"], .iMac, .iMacClassic, 21.5, "Retina 4K, 2017", iMac215)
        list += m(["iMac18,3"], .iMac, .iMacClassic, 27.0, "Retina 5K, 2017", iMac27)
        list += m(["iMac19,1"], .iMac, .iMacClassic, 27.0, "Retina 5K, 2019", iMac27)
        list += m(["iMac19,2"], .iMac, .iMacClassic, 21.5, "Retina 4K, 2019", iMac215)
        list += m(["iMac20,1", "iMac20,2"], .iMac, .iMacClassic, 27.0, "Retina 5K, 2020", iMac27)
        list += m(["iMacPro1,1"], .iMacPro, .iMacPro, 27.0, "2017", iMac27)
        list += m(["iMac21,1", "iMac21,2"], .iMac, .iMac24, 24.0, "M1, 2021", iMac24)
        list += m(["Mac15,4", "Mac15,5"], .iMac, .iMac24, 24.0, "M3, 2023", iMac24)
        list += m(["Mac16,2", "Mac16,3"], .iMac, .iMac24, 24.0, "M4, 2024", iMac24)
        list += m(["Mac18,2"], .iMac, .iMac24, 24.0, "M6", iMac24)
        // Mac mini
        list += m(["Macmini7,1"], .macMini, .miniClassic, nil, "Late 2014", miniClassic)
        list += m(["Macmini8,1"], .macMini, .miniClassic, nil, "2018", miniClassic)
        list += m(["Macmini9,1"], .macMini, .miniClassic, nil, "M1, 2020", miniClassic)
        list += m(["Mac14,3"], .macMini, .miniClassic, nil, "M2, 2023", miniClassic)
        list += m(["Mac14,12"], .macMini, .miniClassic, nil, "M2 Pro, 2023", miniClassic)
        list += m(["Mac16,10", "Mac16,11"], .macMini, .miniCompact, nil, "2024", miniCompact)
        list += m(["Mac17,16"], .macMini, .miniCompact, nil, "M5 Pro, 2026", miniCompact)
        list += m(["Mac18,5"], .macMini, .miniCompact, nil, "M6, 2026", miniCompact)
        // Mac Studio
        list += m(["Mac13,1"], .macStudio, .studio, nil, "M1 Max, 2022", studio)
        list += m(["Mac13,2"], .macStudio, .studio, nil, "M1 Ultra, 2022", studio)
        list += m(["Mac14,13"], .macStudio, .studio, nil, "M2 Max, 2023", studio)
        list += m(["Mac14,14"], .macStudio, .studio, nil, "M2 Ultra, 2023", studio)
        list += m(["Mac15,14"], .macStudio, .studio, nil, "M3 Ultra, 2025", studio)
        list += m(["Mac16,9"], .macStudio, .studio, nil, "M4 Max, 2025", studio)
        list += m(["Mac17,14"], .macStudio, .studio, nil, "M5 Max, 2026", studio)
        list += m(["Mac17,15"], .macStudio, .studio, nil, "M5 Ultra, 2026", studio)
        // Mac Pro
        list += m(["MacPro6,1"], .macPro, .proCylinder, nil, "Late 2013", proCylinder)
        list += m(["MacPro7,1"], .macPro, .proTower, nil, "2019", proTower)
        list += m(["Mac14,8"], .macPro, .proTower, nil, "2023", proTower)
        return Dictionary(list, uniquingKeysWith: { first, _ in first })
    }()

    /// Modell zur Kennung – exakt, wenn bekannt; sonst eine Schätzung aus Gerätefamilie, Chip und (bei Notebooks)
    /// der gemessenen Diagonale des eingebauten Displays. Für virtuelle Macs und Unbekanntes `nil`.
    public static func resolve(identifier: String?, kind: DeviceKind, appleSilicon: Bool,
                               builtInDisplayInches: Double? = nil) -> MacModelInfo? {
        if let identifier {
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = all[trimmed] { return exact }
        }
        let id = identifier ?? ""
        func estimate(_ family: MacModelInfo.Family, _ design: MacModelInfo.Design, _ inches: Double?,
                      _ size: Size) -> MacModelInfo {
            MacModelInfo(identifier: id, family: family, design: design, inches: inches, variant: "",
                         width: size.w, depth: size.d, height: size.h, exact: false)
        }
        let display = builtInDisplayInches
        switch kind {
        case .macBookPro:
            guard appleSilicon else {
                if let display, display > 15.7 { return estimate(.macBookPro, .proTouchBar, 16.0, pro16_2019) }
                if let display, display > 14 { return estimate(.macBookPro, .proTouchBar, 15.4, pro15) }
                return estimate(.macBookPro, .proTouchBar, 13.3, pro13)
            }
            if let display, display < 13.8 { return estimate(.macBookPro, .proTouchBar, 13.3, pro13) }
            if let display, display > 15 { return estimate(.macBookPro, .proNotch, 16.2, pro16) }
            return estimate(.macBookPro, .proNotch, 14.2, pro14)
        case .macBookAir:
            guard appleSilicon else { return estimate(.macBookAir, .airRetina, 13.3, airRetina) }
            if let display, display > 14.5 { return estimate(.macBookAir, .airFlat, 15.3, air15) }
            if let display, display < 13.45 { return estimate(.macBookAir, .airRetina, 13.3, airRetina) }
            return estimate(.macBookAir, .airFlat, 13.6, air13)
        case .macBook:
            return estimate(.macBook, .macBook12, 12.0, macBook12)
        case .iMac:
            if appleSilicon { return estimate(.iMac, .iMac24, 24.0, iMac24) }
            return estimate(.iMac, .iMacClassic, 27.0, iMac27)
        case .macMini:
            return appleSilicon ? estimate(.macMini, .miniCompact, nil, miniCompact)
                                : estimate(.macMini, .miniClassic, nil, miniClassic)
        case .macStudio:
            return estimate(.macStudio, .studio, nil, studio)
        case .macPro:
            return estimate(.macPro, .proTower, nil, proTower)
        case .virtualMachine, .unknown:
            return nil
        }
    }
}
