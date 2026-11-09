import SwiftUI
import AppKit
import IOKit
import ABCore

// =============================================================================================
// „Ihr Mac“: Android Bridge erkennt das Modell dieses Macs (Modellkennung, z. B. „MacBookPro14,1“)
// und zeichnet dessen Bauform nach – Rahmen mit Kinn (2016–2020), Notch (seit 2021), MacBook Air,
// iMac oder Desktop-Mac mit Bildschirm. Alles selbst gezeichnet: keine Produktfotos, kein Logo.
// Die Gehäusefarbe lässt sich nicht aus der Hardware auslesen – sie hat einen Vorschlag und ist in
// den Einstellungen wählbar.
// =============================================================================================

/// Dieser Mac: Modell aus dem System gelesen (Logik in ABCore/MacModel).
struct MacHardware: Equatable {
    typealias Form = MacForm
    typealias Finish = MacFinish

    let model: MacModel
    let isAppleSilicon: Bool

    var identifier: String { model.identifier }
    var marketingName: String { model.marketingName }
    var form: MacForm { model.form }
    var suggestedFinish: MacFinish { model.suggestedFinish }
    var familyName: String { model.familyName }
    var detailName: String? { model.detailName }

    static let current: MacHardware = detect()

    static func preview(_ id: String, _ name: String, chip: String = "") -> MacHardware {
        MacHardware(model: MacModel(identifier: id, rawName: name, chip: chip), isAppleSilicon: chip.hasPrefix("Apple"))
    }

    static func detect() -> MacHardware {
        let id = sysctlString("hw.model") ?? "Mac"
        let brand = sysctlString("machdep.cpu.brand_string") ?? ""
        let arm = brand.hasPrefix("Apple") || sysctlInt("hw.optional.arm64") == 1
        let raw = appleSiliconProductName() ?? intelMarketingName(id)
        return MacHardware(model: MacModel(identifier: id, rawName: raw, chip: brand), isAppleSilicon: arm)
    }

    // MARK: Systemquellen

    private static func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        let s = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func sysctlInt(_ key: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// Apple Silicon: der Verkaufsname steht im Gerätebaum („MacBook Pro (14-inch, Nov 2023)“).
    private static func appleSiliconProductName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let cf = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let data = cf as? Data else { return nil }
        let s = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Intel: macOS führt eine Liste der Verkaufsnamen (dieselbe wie „Über diesen Mac“).
    private static func intelMarketingName(_ id: String) -> String? {
        let base = "/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/"
        for lproj in ["de.lproj", "German.lproj", "en.lproj", "English.lproj"] {
            guard let dict = NSDictionary(contentsOfFile: base + lproj + "/SIMachineAttributes.plist") as? [String: Any],
                  let entry = dict[id] as? [String: Any],
                  let loc = entry["_LOCALIZABLE_"] as? [String: Any],
                  let name = loc["marketingModel"] as? String, !name.isEmpty else { continue }
            return name
        }
        return nil
    }
}

extension MacFinish {
    /// Helle und dunkle Stufe des Metalls (für Verläufe).
    var metal: (Color, Color) {
        switch self {
        case .silver: return (Color(hex: 0xE6E7E9), Color(hex: 0xA9ADB3))
        case .spaceGray: return (Color(hex: 0x8E9196), Color(hex: 0x4E5156))
        case .spaceBlack: return (Color(hex: 0x46484B), Color(hex: 0x1B1C1E))
        case .midnight: return (Color(hex: 0x4A5363), Color(hex: 0x232933))
        case .starlight: return (Color(hex: 0xF1EADF), Color(hex: 0xC4B9A7))
        case .gold: return (Color(hex: 0xF3E1CF), Color(hex: 0xC9AF96))
        case .skyBlue: return (Color(hex: 0xDCE6EE), Color(hex: 0xA6B6C3))
        case .blue: return (Color(hex: 0xA9C4EA), Color(hex: 0x5D82BD))
        case .green: return (Color(hex: 0xB7D9C2), Color(hex: 0x6E9F82))
        case .purple: return (Color(hex: 0xCDBFEA), Color(hex: 0x8A76C2))
        }
    }
}

/// Gewählte Gehäusefarbe (Einstellungen) – „auto“ = Vorschlag zur Bauform.
enum MacAppearance {
    static let storageKey = "macFinish"

    static func finish(for hardware: MacHardware, stored: String) -> MacFinish {
        if let f = MacFinish(rawValue: stored), MacFinish.options(for: hardware.form).contains(f) { return f }
        return hardware.suggestedFinish
    }
}

// MARK: - Darstellung

/// Der Mac in Vorderansicht, dessen Bildschirm echte Inhalte zeigt.
struct MacRender<Screen: View>: View {
    var width: CGFloat = 320
    var hardware: MacHardware = .current
    var finish: MacHardware.Finish? = nil
    @ViewBuilder var screen: () -> Screen
    @AppStorage(MacAppearance.storageKey) private var storedFinish = "auto"

    private var metal: (Color, Color) { (finish ?? MacAppearance.finish(for: hardware, stored: storedFinish)).metal }

    var body: some View {
        Group {
            if hardware.form.isLaptop {
                laptop
            } else if hardware.form == .desktop {
                desktop
            } else {
                iMac
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: width * 0.06, y: width * 0.04)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hardware.marketingName)
    }

    /// Maße der Notebook-Bauformen (Anteile der Deckelbreite).
    private struct LaptopSpec {
        var side: CGFloat, top: CGFloat, chin: CGFloat
        var screenRatio: CGFloat
        var notch: Bool
        var bezelIsMetal = false
        var baseHeight: CGFloat
        var baseOverhang: CGFloat
        var flatBase: Bool
        var lidCorner: CGFloat
    }

    private var spec: LaptopSpec {
        switch hardware.form {
        case .notchPro: return LaptopSpec(side: 0.021, top: 0.026, chin: 0.03, screenRatio: 1.54, notch: true, baseHeight: 0.042, baseOverhang: 0.012, flatBase: true, lidCorner: 0.03)
        case .notchAir: return LaptopSpec(side: 0.021, top: 0.026, chin: 0.03, screenRatio: 1.56, notch: true, baseHeight: 0.026, baseOverhang: 0.01, flatBase: true, lidCorner: 0.028)
        case .retinaAir: return LaptopSpec(side: 0.03, top: 0.038, chin: 0.06, screenRatio: 1.6, notch: false, baseHeight: 0.026, baseOverhang: 0.02, flatBase: false, lidCorner: 0.026)
        case .classicAir: return LaptopSpec(side: 0.062, top: 0.06, chin: 0.075, screenRatio: 1.6, notch: false, bezelIsMetal: true, baseHeight: 0.026, baseOverhang: 0.02, flatBase: false, lidCorner: 0.03)
        case .classicPro: return LaptopSpec(side: 0.04, top: 0.05, chin: 0.08, screenRatio: 1.6, notch: false, baseHeight: 0.04, baseOverhang: 0.015, flatBase: false, lidCorner: 0.03)
        default: return LaptopSpec(side: 0.028, top: 0.036, chin: 0.066, screenRatio: 1.6, notch: false, baseHeight: 0.034, baseOverhang: 0.015, flatBase: false, lidCorner: 0.026)
        }
    }

    private var laptop: some View {
        let s = spec
        let w = width
        let screenW = w * (1 - 2 * s.side)
        let screenH = screenW / s.screenRatio
        let lidH = screenH + w * (s.top + s.chin)
        let (light, dark) = metal
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Deckel: Metallkante, darin Glas (bzw. Metallrahmen beim alten Air)
                RoundedRectangle(cornerRadius: w * s.lidCorner, style: .continuous)
                    .fill(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: w * (s.lidCorner - 0.004), style: .continuous)
                    .fill(s.bezelIsMetal ? AnyShapeStyle(LinearGradient(colors: [light.opacity(0.95), dark.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(Color(hex: 0x050506)))
                    .padding(w * 0.005)
                // Bildschirm
                screenArea(width: screenW, height: screenH, notch: s.notch)
                    .padding(.top, w * s.top)
                // Kamera (ohne Notch)
                if !s.notch {
                    Circle()
                        .fill(Color(hex: 0x16202B))
                        .overlay(Circle().fill(Color(hex: 0x2B4A6A).opacity(0.6)).padding(w * 0.002))
                        .frame(width: w * 0.011, height: w * 0.011)
                        .padding(.top, w * s.top * 0.42)
                }
                // Glanz über dem Deckel
                RoundedRectangle(cornerRadius: w * s.lidCorner, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: .white.opacity(0.10), location: 0), .init(color: .clear, location: 0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: w * s.lidCorner, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            }
            .frame(width: w, height: lidH)
            // Scharnier
            Rectangle()
                .fill(LinearGradient(colors: [Color(hex: 0x111214), dark.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.82, height: max(1.5, w * 0.008))
            // Unterteil
            MacBase(flat: s.flatBase)
                .fill(LinearGradient(colors: [light, dark, dark.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    // Griffmulde
                    Capsule().fill(LinearGradient(colors: [dark.opacity(0.9), dark.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.13, height: w * s.baseHeight * 0.32)
                        .offset(y: -w * s.baseHeight * 0.18),
                    alignment: .center
                )
                .overlay(MacBase(flat: s.flatBase).stroke(Color.white.opacity(0.35), lineWidth: 0.6).mask(
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
                .frame(width: w * (1 + 2 * s.baseOverhang), height: w * s.baseHeight)
        }
    }

    private func screenArea(width: CGFloat, height: CGFloat, notch: Bool) -> some View {
        let corner = notch ? width * 0.018 : width * 0.004
        return ZStack(alignment: .top) {
            screen()
                .frame(width: width, height: height)
                .clipShape(UnevenScreenShape(topRadius: corner, bottomRadius: notch ? width * 0.006 : width * 0.003))
            if notch {
                NotchShape()
                    .fill(Color(hex: 0x050506))
                    .frame(width: width * 0.105, height: width * 0.022)
                    .overlay(Circle().fill(Color(hex: 0x1B2C3D)).frame(width: width * 0.008, height: width * 0.008).offset(y: -width * 0.002))
            }
        }
        .frame(width: width, height: height)
    }

    private var iMac: some View {
        let w = width
        let classic = hardware.form == .iMacClassic
        let border = w * (classic ? 0.03 : 0.024)
        let screenW = w - 2 * border
        let screenH = screenW / 1.78
        let chin = w * (classic ? 0.14 : 0.09)
        let (light, dark) = metal
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(classic ? Color(hex: 0x050506) : Color(hex: 0xF4F4F2))
                    screen().frame(width: screenW, height: screenH).clipShape(RoundedRectangle(cornerRadius: w * 0.004))
                }
                .frame(width: w, height: screenH + 2 * border)
                Rectangle()
                    .fill(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: chin)
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.022, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: w * 0.022, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
            // Standfuß
            Trapezoid(inset: 0.08)
                .fill(LinearGradient(colors: [dark, light.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.22, height: w * 0.14)
            Capsule().fill(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.3, height: w * 0.012)
        }
    }

    private var desktop: some View {
        let w = width
        let border = w * 0.016
        let screenW = w - 2 * border
        let screenH = screenW / 1.78
        let (light, dark) = metal
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: w * 0.016, style: .continuous).fill(Color(hex: 0x050506))
                    screen().frame(width: screenW, height: screenH).clipShape(RoundedRectangle(cornerRadius: w * 0.006))
                }
                .frame(width: w, height: screenH + 2 * border)
                .overlay(RoundedRectangle(cornerRadius: w * 0.016, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom), lineWidth: w * 0.004))
                Rectangle().fill(LinearGradient(colors: [dark, light], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.12, height: w * 0.12)
                Capsule().fill(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.32, height: w * 0.014)
            }
            // Das Gehäuse (Mac mini / Studio) neben dem Fuß
            RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
                .fill(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.02, style: .continuous).strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6))
                .frame(width: w * 0.2, height: w * 0.065)
                .offset(x: w * 0.02)
        }
    }
}

/// Unterteil: vorne leicht abgerundet (Notch-Modelle kantiger).
private struct MacBase: Shape {
    var flat: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        let curve = r.width * (flat ? 0.012 : 0.03)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - curve, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + curve, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Notch: unten abgerundete Aussparung.
private struct NotchShape: Shape {
    func path(in r: CGRect) -> Path {
        let rad = min(r.height * 0.5, r.width * 0.12)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Bildschirmform: oben stärker gerundet als unten.
private struct UnevenScreenShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    func path(in r: CGRect) -> Path {
        let t = min(topRadius, r.width / 2), b = min(bottomRadius, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + t), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.maxX - b, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - b), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

private struct Trapezoid: Shape {
    var inset: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Beschriftung unter dem Mac: „MacBook Pro · 13 Zoll, 2017“.
struct MacCaption: View {
    var hardware: MacHardware = .current
    var color: Color = .white.opacity(0.7)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hardware.form.isLaptop ? "laptopcomputer" : (hardware.form == .desktop ? "macmini" : "desktopcomputer"))
            Text(hardware.familyName).fontWeight(.semibold)
            if let detail = hardware.detailName {
                Text(detail).foregroundStyle(color.opacity(0.75))
            }
        }
        .font(.ui(11.5))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
