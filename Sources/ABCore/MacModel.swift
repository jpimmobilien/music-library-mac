import Foundation

/// Bauform eines Macs, abgeleitet aus Modellkennung („MacBookPro14,1“) und Verkaufsname.
/// Reine Logik – die App liest Kennung und Namen aus dem System und zeichnet danach den passenden Mac.
public enum MacForm: String, CaseIterable, Sendable {
    /// MacBook Pro / MacBook 2016–2020 (und M1/M2 13"): schwarzer Glasrahmen mit Kinn.
    case retinaChin
    /// MacBook Pro seit 2021: schmale Ränder mit Notch, kantiges Unterteil.
    case notchPro
    /// MacBook Air seit M2: Notch, sehr flaches Unterteil.
    case notchAir
    /// MacBook Air 2018–2020 (Intel/M1): schwarzer Rahmen mit Kinn, Keilform.
    case retinaAir
    /// MacBook Air bis 2017: breiter Aluminiumrahmen.
    case classicAir
    /// MacBook Pro bis 2015: Glasrahmen mit breitem Kinn.
    case classicPro
    /// iMac mit Aluminiumkinn (Intel).
    case iMacClassic
    /// iMac 24" (Apple Silicon): farbiges Kinn, heller Rahmen.
    case iMacColor
    /// Mac mini, Mac Studio, Mac Pro: Bildschirm und Gehäuse.
    case desktop

    public var isLaptop: Bool {
        switch self {
        case .retinaChin, .notchPro, .notchAir, .retinaAir, .classicAir, .classicPro: return true
        default: return false
        }
    }
}

/// Gehäusefarben (die Farbe lässt sich nicht aus der Hardware lesen – Vorschlag + Auswahl).
public enum MacFinish: String, CaseIterable, Identifiable, Sendable {
    case silver, spaceGray, spaceBlack, midnight, starlight, gold, skyBlue, blue, green, purple
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .silver: return "Silber"
        case .spaceGray: return "Space Grau"
        case .spaceBlack: return "Space Schwarz"
        case .midnight: return "Mitternacht"
        case .starlight: return "Polarstern"
        case .gold: return "Gold"
        case .skyBlue: return "Himmelblau"
        case .blue: return "Blau"
        case .green: return "Grün"
        case .purple: return "Violett"
        }
    }

    /// Farben, in denen es die Bauform gab.
    public static func options(for form: MacForm) -> [MacFinish] {
        switch form {
        case .notchPro: return [.silver, .spaceGray, .spaceBlack]
        case .notchAir: return [.silver, .spaceGray, .midnight, .starlight, .skyBlue]
        case .retinaAir, .retinaChin: return [.silver, .spaceGray, .gold]
        case .classicAir, .classicPro: return [.silver]
        case .iMacColor: return [.blue, .green, .purple, .silver]
        case .iMacClassic, .desktop: return [.silver, .spaceGray]
        }
    }
}

public struct MacModel: Equatable, Sendable {
    public let identifier: String
    /// Deutscher Verkaufsname, z. B. „MacBook Pro (13 Zoll, 2017, 2 × Thunderbolt 3)“.
    public let marketingName: String
    public let form: MacForm
    public let suggestedFinish: MacFinish

    public init(identifier: String, rawName: String?, chip: String = "") {
        let name = MacModel.germanize(rawName ?? MacModel.fallbackName(identifier))
        let form = MacModel.form(identifier: identifier, name: name)
        self.identifier = identifier
        self.marketingName = name
        self.form = form
        self.suggestedFinish = MacModel.suggestedFinish(form: form, chip: chip)
    }

    /// „MacBook Pro“ (ohne Klammerzusatz).
    public var familyName: String {
        if let r = marketingName.range(of: " (") { return String(marketingName[..<r.lowerBound]) }
        return marketingName
    }

    /// „13 Zoll, 2017“ – der Klammerzusatz.
    public var detailName: String? {
        guard let open = marketingName.firstIndex(of: "("), let close = marketingName.lastIndex(of: ")"), open < close else { return nil }
        return String(marketingName[marketingName.index(after: open)..<close])
    }

    public static func suggestedFinish(form: MacForm, chip: String) -> MacFinish {
        switch form {
        case .notchPro:
            if let gen = chipGeneration(chip), gen >= 3, chip.contains("Pro") || chip.contains("Max") { return .spaceBlack }
            return .spaceGray
        case .notchAir: return .midnight
        case .retinaChin, .retinaAir: return .silver
        case .iMacColor: return .blue
        default: return .silver
        }
    }

    public static func form(identifier id: String, name: String) -> MacForm {
        func major(_ prefix: String) -> Int? {
            guard id.hasPrefix(prefix) else { return nil }
            let rest = id.dropFirst(prefix.count)
            guard let comma = rest.firstIndex(of: ",") else { return nil }
            return Int(rest[..<comma])
        }
        if let m = major("MacBookPro") { return m >= 18 ? .notchPro : (m >= 13 ? .retinaChin : .classicPro) }
        if let m = major("MacBookAir") { return m >= 8 ? .retinaAir : .classicAir }
        if major("MacBook") != nil { return .retinaChin }
        if major("iMacPro") != nil { return .iMacClassic }
        if let m = major("iMac") { return m >= 21 ? .iMacColor : .iMacClassic }
        if id.hasPrefix("Macmini") || id.hasPrefix("MacPro") { return .desktop }
        // Neues Schema „MacNN,x“ (seit 2022): erst der Name, dann bekannte Kennungen
        if id == "Mac14,7" { return .retinaChin }   // MacBook Pro 13" M2 – noch mit Kinn
        let lower = name.lowercased()
        if lower.contains("macbook pro") { return .notchPro }
        if lower.contains("macbook") { return .notchAir }
        if lower.contains("imac") { return .iMacColor }
        if lower.contains("mac mini") || lower.contains("mac studio") || lower.contains("mac pro") { return .desktop }
        let airs: Set<String> = ["Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13", "Mac16,12", "Mac16,13"]
        let pros: Set<String> = ["Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10", "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8",
                                 "Mac15,9", "Mac15,10", "Mac15,11", "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8"]
        let iMacs: Set<String> = ["Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3"]
        if airs.contains(id) { return .notchAir }
        if pros.contains(id) { return .notchPro }
        if iMacs.contains(id) { return .iMacColor }
        if id.hasPrefix("Mac"), id.contains(",") { return .desktop }
        // Unbekannt (z. B. virtuelle Maschine): aktuelles MacBook Pro
        return .notchPro
    }

    /// „Apple M3 Pro“ → 3.
    public static func chipGeneration(_ chip: String) -> Int? {
        guard let r = chip.range(of: " M") ?? (chip.hasPrefix("M") ? chip.range(of: "M") : nil) else { return nil }
        return Int(chip[r.upperBound...].prefix { $0.isNumber })
    }

    /// Englische Apple-Bezeichnungen ins Deutsche: „13-inch“ → „13 Zoll“ usw.
    public static func germanize(_ s: String) -> String {
        var out = s
        let pairs: [(String, String)] = [
            ("-inch", " Zoll"), ("-Inch", " Zoll"), ("-Zoll", " Zoll"),
            ("Four Thunderbolt 3 ports", "4 × Thunderbolt 3"), ("Four Thunderbolt 3 Ports", "4 × Thunderbolt 3"),
            ("Two Thunderbolt 3 ports", "2 × Thunderbolt 3"), ("Two Thunderbolt 3 Ports", "2 × Thunderbolt 3"),
            ("Four Thunderbolt ports", "4 × Thunderbolt"), ("Two Thunderbolt ports", "2 × Thunderbolt"),
            ("Early ", "Anfang "), ("Mid ", "Mitte "), ("Late ", "Ende "),
        ]
        for (a, b) in pairs { out = out.replacingOccurrences(of: a, with: b) }
        return out
    }

    public static func fallbackName(_ id: String) -> String {
        if id.hasPrefix("MacBookPro") { return "MacBook Pro" }
        if id.hasPrefix("MacBookAir") { return "MacBook Air" }
        if id.hasPrefix("MacBook") { return "MacBook" }
        if id.hasPrefix("iMacPro") { return "iMac Pro" }
        if id.hasPrefix("iMac") { return "iMac" }
        if id.hasPrefix("Macmini") { return "Mac mini" }
        if id.hasPrefix("MacPro") { return "Mac Pro" }
        switch form(identifier: id, name: "") {
        case .notchAir: return "MacBook Air"
        case .notchPro, .retinaChin: return id.hasPrefix("Mac") ? "MacBook Pro" : "Mac"
        case .iMacColor: return "iMac"
        default: return "Mac"
        }
    }
}
