import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Geräte-Illustrationen je Mac-Modell (seit 2017) – eigene Vektorzeichnungen nach Apples Maßen, ohne Logos und
// Schriftzüge. Vorderansicht (Übersicht, Hardware) mit echtem Bildschirminhalt; Aufsicht für die Wärmekarte.
// Merkmale je Bauform: Displayrand (Aluminium/Glas), Kerbe bzw. Dynamic Island, Keilform, Touch Bar,
// Funktionstasten halb/voll, Lautsprechergitter, Trackpad-Größe, iMac-Kinn, Mac mini/Studio/Pro-Gehäuse.
// Farbe nur bei Modellen, die es in genau einer Farbe gab; sonst neutral (macOS meldet die Gehäusefarbe nicht).
// =============================================================================================

// MARK: - Modell des eigenen Macs

/// Diagonale des eingebauten Displays (Zoll) – nur für die Schätzung unbekannter, neuer Notebook-Modelle.
enum BuiltInDisplay {
    @MainActor static let inches: Double? = {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            guard CGDisplayIsBuiltin(id) != 0 else { continue }
            let size = CGDisplayScreenSize(id)
            guard size.width > 0, size.height > 0 else { continue }
            return (size.width * size.width + size.height * size.height).squareRoot() / 25.4
        }
        return nil
    }()
}

extension HardwareSummary {
    /// Erkanntes Modell (exakt über die Modellkennung, sonst geschätzt); virtuelle Macs: `nil`.
    @MainActor var macModel: MacModelInfo? {
        guard !isVirtualMachine, kind != .virtualMachine else { return nil }
        if let identifier = modelIdentifier, let exact = MacModelCatalog.all[identifier] { return exact }
        return MacModelCatalog.resolve(identifier: modelIdentifier, kind: kind, appleSilicon: isAppleSilicon,
                                       builtInDisplayInches: kind.isPortable ? BuiltInDisplay.inches : nil)
    }
}

extension MacModelInfo {
    /// „MacBook Pro 13″ (2020 · 4× Thunderbolt 3)“ – mit Hinweis, wenn nur geschätzt.
    var displayName: String {
        // Dezimaltrennzeichen der App-Sprache („iMac 21,5″“)
        let separator = fmt.number(1.5, fractionDigits: 1).contains(",") ? "," : "."
        let name = productName.replacingOccurrences(of: ".", with: separator)
        if !exact { return tr("%@ (estimated)", name) }
        return variant.isEmpty ? name : "\(name) (\(variant))"
    }
}

// MARK: - Oberflächen

struct MacFinish {
    var top: Color
    var bottom: Color
    var deck: Color
    var edge: Color
    var key: Color
    var well: Color
    var bezel: Color

    static func make(_ finish: MacModelInfo.Finish?, dark: Bool) -> MacFinish {
        switch finish {
        case .spaceGray:
            return MacFinish(top: Color(white: dark ? 0.36 : 0.46), bottom: Color(white: dark ? 0.17 : 0.27),
                             deck: Color(white: dark ? 0.31 : 0.42), edge: Color.white.opacity(dark ? 0.22 : 0.4),
                             key: Color(white: 0.08), well: Color(white: 0.12), bezel: Color.black)
        case .black:
            return MacFinish(top: Color(white: 0.17), bottom: Color(white: 0.04), deck: Color(white: 0.12),
                             edge: Color.white.opacity(0.25), key: Color(white: 0.05), well: Color(white: 0.06), bezel: Color.black)
        case .silver:
            return MacFinish(top: Color(white: dark ? 0.66 : 0.90), bottom: Color(white: dark ? 0.44 : 0.74),
                             deck: Color(white: dark ? 0.60 : 0.86), edge: Color.white.opacity(dark ? 0.35 : 0.95),
                             key: Color(white: dark ? 0.20 : 0.26), well: Color(white: dark ? 0.50 : 0.78), bezel: Color.black)
        case nil:
            return MacFinish(top: Color(white: dark ? 0.26 : 0.87), bottom: Color(white: dark ? 0.11 : 0.70),
                             deck: Color(white: dark ? 0.22 : 0.82), edge: Color.white.opacity(dark ? 0.22 : 0.9),
                             key: Color(white: dark ? 0.06 : 0.22), well: Color(white: dark ? 0.09 : 0.70), bezel: Color.black)
        }
    }
}

// MARK: - Formen

/// Rechteck mit getrennten Radien oben und unten (UnevenRoundedRectangle erst ab macOS 14).
struct TopBottomRoundedRect: Shape {
    var top: CGFloat
    var bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        let t = min(top, rect.width / 2, rect.height / 2)
        let b = min(bottom, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + t), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - b, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - b), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Trapez (oben schmaler als unten) – Tastaturfläche in leichter Aufsicht, Standfüße.
struct TrapezoidShape: Shape {
    /// Breite oben relativ zur Breite unten
    var topFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * (1 - topFraction) / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Kerbe oben im Display (unten abgerundet).
struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.height * 0.45, rect.width * 0.2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - r * 0.6, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + r * 0.6, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r * 0.6), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r * 0.6))
        path.addQuadCurve(to: CGPoint(x: rect.minX - r * 0.6, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Punktraster in einer Form (Lautsprechergitter, Lochgitter) – ein einziger Pfad statt vieler Ansichten.
struct DotGridShape: Shape {
    var columns: Int
    var rows: Int
    /// Punktgröße relativ zum Raster
    var dot: CGFloat = 0.45
    /// jede zweite Reihe versetzt
    var staggered = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard columns > 0, rows > 0 else { return path }
        let cellW = rect.width / CGFloat(columns)
        let cellH = rect.height / CGFloat(rows)
        let d = min(cellW, cellH) * dot
        for row in 0..<rows {
            let shift = staggered && row % 2 == 1 ? cellW / 2 : 0
            for column in 0..<columns {
                let x = rect.minX + cellW * (CGFloat(column) + 0.5) + shift
                guard x + d / 2 <= rect.maxX + 0.5 else { continue }
                let y = rect.minY + cellH * (CGFloat(row) + 0.5)
                path.addEllipse(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
            }
        }
        return path
    }
}

/// Tastatur in Aufsicht: Funktionsreihe (halb/voll/Touch Bar) und fünf Tastenreihen – ein Pfad.
struct KeyboardShape: Shape {
    enum FunctionRow { case half, full, touchBar, touchBarWithEscape, halfWithTouchID }
    var functionRow: FunctionRow

    private static let rows: [[CGFloat]] = [
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],          // Zahlenreihe
        [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],          // Tab
        [1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.75],         // Feststell / Return
        [2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.25],            // Umschalt
        [1, 1, 1, 1.25, 5, 1.25, 1, 1, 1, 1],                  // fn ctrl alt cmd Leertaste cmd alt ← ↑↓ →
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let units: CGFloat = 14.5
        let unit = rect.width / units
        let gap = unit * 0.1
        let fnHeight: CGFloat
        switch functionRow {
        case .full: fnHeight = 1
        case .half, .halfWithTouchID: fnHeight = 0.55
        case .touchBar, .touchBarWithEscape: fnHeight = 0.62
        }
        let rowUnit = rect.height / (5 + fnHeight)
        let radius = unit * 0.14

        func key(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            let r = CGRect(x: x + gap / 2, y: y + gap / 2, width: max(0, w - gap), height: max(0, h - gap))
            path.addRoundedRect(in: r, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }

        // Funktionsreihe
        let fnH = rowUnit * fnHeight
        switch functionRow {
        case .half, .full, .halfWithTouchID:
            var x = rect.minX
            let widths: [CGFloat] = [1.5] + Array(repeating: 1, count: 12) + [1]
            for w in widths {
                key(x, rect.minY, unit * w, fnH)
                x += unit * w
            }
        case .touchBar:
            // Touch Bar über die ganze Breite, rechts Touch ID
            key(rect.minX, rect.minY, unit * 13.5, fnH)
            key(rect.minX + unit * 13.5, rect.minY, unit, fnH)
        case .touchBarWithEscape:
            key(rect.minX, rect.minY, unit, fnH)
            key(rect.minX + unit, rect.minY, unit * 12.5, fnH)
            key(rect.minX + unit * 13.5, rect.minY, unit, fnH)
        }

        // Tastenreihen
        var y = rect.minY + fnH
        for (index, row) in Self.rows.enumerated() {
            var x = rect.minX
            for (column, w) in row.enumerated() {
                if index == 4 && column >= 7 {
                    // Pfeiltasten: halbe Höhe, ↑/↓ übereinander
                    if column == 8 {
                        key(x, y, unit, rowUnit / 2)
                        key(x, y + rowUnit / 2, unit, rowUnit / 2)
                    } else {
                        key(x, y + rowUnit / 2, unit, rowUnit / 2)
                    }
                } else {
                    key(x, y, unit * w, rowUnit)
                }
                x += unit * w
            }
            y += rowUnit
        }
        return path
    }
}

// MARK: - Vorderansicht

/// Gerät in Vorderansicht mit Bildschirminhalt (Übersicht, Hardware). Ohne erkanntes Modell (z. B. virtueller Mac)
/// zeichnet `DeviceArt` eine neutrale Form.
struct MacFrontArt<Screen: View>: View {
    @Environment(\.aether) private var theme
    let model: MacModelInfo
    @ViewBuilder var screen: () -> Screen

    var body: some View {
        let finish = MacFinish.make(model.finish, dark: theme.isDark)
        Group {
            if model.design.isPortable {
                LaptopFront(model: model, finish: finish, screen: screen)
            } else if model.design.hasBuiltInDisplay {
                IMacFront(model: model, finish: finish, screen: screen)
            } else {
                DesktopFront(model: model, finish: finish, screen: screen)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Maße eines Notebooks in mm (Vorderansicht).
private struct LaptopGeometry {
    let width: CGFloat
    let lidHeight: CGFloat
    let deckBand: CGFloat
    let frontEdge: CGFloat
    let flare: CGFloat = 1.035
    let screen: CGSize
    let topBezel: CGFloat
    let glassInset: CGFloat
    let aluminumBezel: Bool
    let notch: CGSize?
    let island: CGSize?
    let lidRadius: CGFloat
    let screenTopRadius: CGFloat

    init(_ model: MacModelInfo) {
        width = CGFloat(model.width)
        lidHeight = CGFloat(model.depth) * 0.975
        deckBand = CGFloat(model.depth) * 0.085
        let design = model.design
        switch design {
        case .airClassic: frontEdge = 3
        case .airRetina: frontEdge = 4.1
        case .macBook12: frontEdge = 3.5
        default: frontEdge = CGFloat(model.height)
        }
        let diagonal = CGFloat(model.inches ?? 13.3) * 25.4
        let aspect: CGFloat
        switch design {
        case .proNotch, .proIsland: aspect = (model.inches ?? 14) > 15 ? 1.547 : 1.540
        case .airFlat: aspect = (model.inches ?? 13.6) > 14 ? 1.545 : 1.538
        default: aspect = 1.6
        }
        let screenH = diagonal / (1 + aspect * aspect).squareRoot()
        screen = CGSize(width: screenH * aspect, height: screenH)
        switch design {
        case .airClassic: topBezel = 17
        case .airRetina, .proTouchBar, .proFunctionKeys: topBezel = (model.inches ?? 13) >= 16 ? 9.5 : 11
        case .macBook12: topBezel = 12
        case .proNotch, .airFlat: topBezel = 6
        case .proIsland: topBezel = 5
        default: topBezel = 10
        }
        aluminumBezel = design == .airClassic
        glassInset = aluminumBezel ? 0 : 1.6
        switch design {
        case .proNotch, .airFlat: notch = CGSize(width: screen.width * 0.066, height: screen.height * 0.034)
        default: notch = nil
        }
        island = design == .proIsland ? CGSize(width: screen.width * 0.078, height: screen.height * 0.026) : nil
        lidRadius = width * 0.028
        screenTopRadius = (design == .proNotch || design == .proIsland || design == .airFlat) ? width * 0.022 : width * 0.004
    }

    var totalWidth: CGFloat { width * flare }
    var totalHeight: CGFloat { lidHeight + deckBand + frontEdge + 10 }
}

private struct LaptopFront<Screen: View>: View {
    let model: MacModelInfo
    let finish: MacFinish
    let screen: () -> Screen

    var body: some View {
        GeometryReader { geo in
            let g = LaptopGeometry(model)
            let s = max(0.01, min(geo.size.width * 0.96 / g.totalWidth, geo.size.height * 0.94 / g.totalHeight))
            let cx = geo.size.width / 2
            let top = (geo.size.height - g.totalHeight * s) / 2
            ZStack(alignment: .topLeading) {
                shadow(width: g.totalWidth * s * 1.02)
                    .position(x: cx, y: top + (g.lidHeight + g.deckBand + g.frontEdge) * s + 4)
                lid(g, s)
                    .frame(width: g.width * s, height: g.lidHeight * s)
                    .position(x: cx, y: top + g.lidHeight * s / 2)
                deck(g, s)
                    .frame(width: g.totalWidth * s, height: g.deckBand * s)
                    .position(x: cx, y: top + (g.lidHeight + g.deckBand / 2) * s)
                front(g, s)
                    .frame(width: g.totalWidth * s, height: max(2, g.frontEdge * s))
                    .position(x: cx, y: top + (g.lidHeight + g.deckBand) * s + max(2, g.frontEdge * s) / 2)
            }
        }
    }

    private func lid(_ g: LaptopGeometry, _ s: CGFloat) -> some View {
        let screenW = g.screen.width * s
        let screenH = g.screen.height * s
        let screenX = (g.width - g.screen.width) / 2 * s
        let screenY = g.topBezel * s
        return ZStack(alignment: .topLeading) {
            // Deckel (Aluminium)
            TopBottomRoundedRect(top: g.lidRadius * s, bottom: g.width * 0.006 * s)
                .fill(LinearGradient(colors: [finish.top, finish.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(TopBottomRoundedRect(top: g.lidRadius * s, bottom: g.width * 0.006 * s)
                    .stroke(finish.edge, lineWidth: 0.8))
            // Glas mit schwarzem Rand (bzw. beim MacBook Air bis 2017 nur um den Bildschirm)
            if g.aluminumBezel {
                RoundedRectangle(cornerRadius: 2 * s, style: .continuous)
                    .fill(Color.black)
                    .frame(width: screenW + 5 * s, height: screenH + 5 * s)
                    .offset(x: screenX - 2.5 * s, y: screenY - 2.5 * s)
            } else {
                TopBottomRoundedRect(top: (g.lidRadius - g.glassInset) * s, bottom: 1 * s)
                    .fill(finish.bezel)
                    .frame(width: (g.width - g.glassInset * 2) * s, height: (g.lidHeight - g.glassInset - 2.5) * s)
                    .offset(x: g.glassInset * s, y: g.glassInset * s)
            }
            // Bildschirm mit Inhalt
            ZStack(alignment: .top) {
                Color.black
                screen()
                if let notch = g.notch {
                    NotchShape()
                        .fill(finish.bezel)
                        .frame(width: notch.width * s, height: notch.height * s)
                    Circle()
                        .fill(Color(white: 0.16))
                        .frame(width: max(1.5, 2.2 * s), height: max(1.5, 2.2 * s))
                        .offset(y: notch.height * s * 0.38)
                }
                if let island = g.island {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: island.width * s, height: island.height * s)
                        .offset(y: island.height * s * 0.5)
                }
                // Glasreflex (dekorativ)
                LinearGradient(stops: [.init(color: .white.opacity(0.07), location: 0), .init(color: .clear, location: 0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            .frame(width: screenW, height: screenH)
            .clipShape(TopBottomRoundedRect(top: g.screenTopRadius * s, bottom: g.width * 0.003 * s))
            .offset(x: screenX, y: screenY)
            // Kamera im oberen Rand (Modelle ohne Kerbe)
            if g.notch == nil && g.island == nil {
                Circle()
                    .fill(g.aluminumBezel ? Color(white: 0.12) : Color(white: 0.17))
                    .frame(width: max(1.5, 2.2 * s), height: max(1.5, 2.2 * s))
                    .offset(x: g.width * s / 2 - max(1.5, 2.2 * s) / 2, y: screenY / 2 - max(1.5, 2.2 * s) / 2)
            }
            // Scharnierabdeckung
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: g.width * 0.84 * s, height: max(1, 2.2 * s))
                .offset(x: g.width * 0.08 * s, y: (g.lidHeight - 2.2) * s)
        }
    }

    /// Oberseite des Unterteils in leichter Aufsicht: Tastatur und Trackpad angedeutet.
    private func deck(_ g: LaptopGeometry, _ s: CGFloat) -> some View {
        let w = g.totalWidth * s
        let h = g.deckBand * s
        let keyboard = MacTopLayout(model: model)
        return ZStack(alignment: .topLeading) {
            TrapezoidShape(topFraction: 1 / g.flare)
                .fill(LinearGradient(colors: [finish.deck.opacity(0.9), finish.deck], startPoint: .top, endPoint: .bottom))
                .overlay(TrapezoidShape(topFraction: 1 / g.flare).stroke(finish.edge.opacity(0.6), lineWidth: 0.6))
            TrapezoidShape(topFraction: 0.97)
                .fill(finish.key.opacity(0.85))
                .frame(width: w * CGFloat(keyboard.keyboardX.upperBound - keyboard.keyboardX.lowerBound) * 0.99,
                       height: h * 0.42)
                .offset(x: w * CGFloat(keyboard.keyboardX.lowerBound) + w * 0.005, y: h * 0.12)
            TrapezoidShape(topFraction: 0.97)
                .fill(finish.bottom.opacity(0.35))
                .overlay(TrapezoidShape(topFraction: 0.97).stroke(finish.edge.opacity(0.35), lineWidth: 0.5))
                .frame(width: w * CGFloat(keyboard.trackpad.width), height: h * 0.3)
                .offset(x: w * (1 - CGFloat(keyboard.trackpad.width)) / 2, y: h * 0.62)
        }
    }

    /// Vorderkante mit Griffmulde.
    private func front(_ g: LaptopGeometry, _ s: CGFloat) -> some View {
        let w = g.totalWidth * s
        let h = max(2, g.frontEdge * s)
        return ZStack(alignment: .top) {
            TopBottomRoundedRect(top: 0, bottom: min(h * 0.6, w * 0.01))
                .fill(LinearGradient(colors: [finish.bottom.opacity(0.95), finish.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(TopBottomRoundedRect(top: 0, bottom: min(h * 0.6, w * 0.01)).stroke(finish.edge.opacity(0.45), lineWidth: 0.6))
            Ellipse()
                .fill(Color.black.opacity(0.35))
                .frame(width: w * 0.1, height: max(1.5, h * 0.8))
                .offset(y: -max(1.5, h * 0.8) / 2)
                .clipped()
        }
    }

    private func shadow(width: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [Color.black.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: width / 2))
            .frame(width: width, height: width * 0.06)
    }
}

/// iMac in Vorderansicht.
private struct IMacFront<Screen: View>: View {
    @Environment(\.aether) private var theme
    let model: MacModelInfo
    let finish: MacFinish
    let screen: () -> Screen

    var body: some View {
        GeometryReader { geo in
            let g = IMacGeometry(model)
            let s = max(0.01, min(geo.size.width * 0.9 / g.width, geo.size.height * 0.94 / (g.panel + g.stand + 8)))
            let cx = geo.size.width / 2
            let top = (geo.size.height - (g.panel + g.stand) * s) / 2
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(RadialGradient(colors: [Color.black.opacity(0.45), .clear], center: .center, startRadius: 0,
                                         endRadius: g.width * s * 0.3))
                    .frame(width: g.width * s * 0.6, height: g.width * s * 0.04)
                    .position(x: cx, y: top + (g.panel + g.stand) * s)
                stand(g, s)
                    .frame(width: g.width * 0.36 * s, height: g.stand * s)
                    .position(x: cx, y: top + (g.panel + g.stand / 2) * s)
                panel(g, s)
                    .frame(width: g.width * s, height: g.panel * s)
                    .position(x: cx, y: top + g.panel * s / 2)
            }
        }
    }

    private func panel(_ g: IMacGeometry, _ s: CGFloat) -> some View {
        let glassH = g.top + g.display.height + g.bottomBorder
        let chinColor = g.flat ? Color(white: theme.isDark ? 0.62 : 0.86) : finish.top
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: g.width * 0.018 * s, style: .continuous)
                .fill(LinearGradient(colors: [chinColor, g.flat ? chinColor.opacity(0.85) : finish.bottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: g.width * 0.018 * s, style: .continuous).stroke(finish.edge, lineWidth: 0.8))
            // Displayrand: schwarzes Glas (bis 2020) bzw. heller Rand (iMac 24″)
            TopBottomRoundedRect(top: g.width * 0.017 * s, bottom: 0)
                .fill(g.flat ? Color(white: theme.isDark ? 0.82 : 0.95) : Color.black)
                .frame(width: (g.width - 2) * s, height: glassH * s)
                .offset(x: 1 * s, y: 1 * s)
            ZStack {
                Color.black
                screen()
                LinearGradient(stops: [.init(color: .white.opacity(0.06), location: 0), .init(color: .clear, location: 0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(width: g.display.width * s, height: g.display.height * s)
            .clipShape(RoundedRectangle(cornerRadius: max(1, g.width * 0.003 * s), style: .continuous))
            .offset(x: (g.width - g.display.width) / 2 * s, y: g.top * s)
            Circle()
                .fill(Color(white: g.flat ? 0.35 : 0.16))
                .frame(width: max(1.5, 4 * s), height: max(1.5, 4 * s))
                .offset(x: g.width / 2 * s - max(1.5, 4 * s) / 2, y: g.top / 2 * s - max(1.5, 4 * s) / 2)
        }
    }

    private func stand(_ g: IMacGeometry, _ s: CGFloat) -> some View {
        let standColor = model.design == .iMacPro ? Color(white: 0.12) : finish.top
        return VStack(spacing: 0) {
            TrapezoidShape(topFraction: 0.9)
                .fill(LinearGradient(colors: [standColor.opacity(0.75), standColor], startPoint: .top, endPoint: .bottom))
                .frame(width: g.width * (g.flat ? 0.27 : 0.3) * s)
            RoundedRectangle(cornerRadius: 2 * s, style: .continuous)
                .fill(standColor)
                .overlay(RoundedRectangle(cornerRadius: 2 * s, style: .continuous).stroke(finish.edge.opacity(0.6), lineWidth: 0.6))
                .frame(height: max(2, (g.flat ? 4 : 7) * s))
        }
    }
}

private struct IMacGeometry {
    let width: CGFloat
    let display: CGSize
    let top: CGFloat
    let bottomBorder: CGFloat
    let chin: CGFloat
    let stand: CGFloat
    /// iMac 24″ (flach, heller Rand)
    let flat: Bool

    init(_ model: MacModelInfo) {
        width = CGFloat(model.width)
        flat = model.design == .iMac24
        let diagonal = CGFloat(model.inches ?? 27) * 25.4
        let root = CGFloat(337).squareRoot()
        display = CGSize(width: diagonal * 16 / root, height: diagonal * 9 / root)
        let side = (width - display.width) / 2
        top = flat ? 13.4 : side
        bottomBorder = flat ? 4 : side * 0.4
        chin = width * (flat ? 0.12 : 0.105)
        let panelHeight = top + display.height + bottomBorder + chin
        stand = max(width * 0.1, CGFloat(model.height) - panelHeight)
    }

    var panel: CGFloat { top + display.height + bottomBorder + chin }
}

/// Mac mini / Mac Studio / Mac Pro: neutraler Monitor (zeigt den Inhalt) und daneben das Gerät.
private struct DesktopFront<Screen: View>: View {
    @Environment(\.aether) private var theme
    let model: MacModelInfo
    let finish: MacFinish
    let screen: () -> Screen

    var body: some View {
        GeometryReader { geo in
            // Monitor 27″ (Maße mm) und Gerät in echten Proportionen
            let monitorW: CGFloat = 615
            let monitorH: CGFloat = 360
            let monitorStand: CGFloat = 120
            let box = boxSize
            let gap: CGFloat = 50
            let totalW = monitorW + gap + box.width
            let totalH = max(monitorH + monitorStand, box.height + box.topBand) + 12
            let s = max(0.01, min(geo.size.width * 0.96 / totalW, geo.size.height * 0.94 / totalH))
            let left = (geo.size.width - totalW * s) / 2
            let floor = (geo.size.height + totalH * s) / 2 - 8 * s
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(RadialGradient(colors: [Color.black.opacity(0.45), .clear], center: .center, startRadius: 0,
                                         endRadius: totalW * s * 0.5))
                    .frame(width: totalW * s, height: totalW * s * 0.05)
                    .position(x: left + totalW * s / 2, y: floor)
                monitor(width: monitorW * s, height: monitorH * s, stand: monitorStand * s)
                    .frame(width: monitorW * s, height: (monitorH + monitorStand) * s)
                    .position(x: left + monitorW * s / 2, y: floor - (monitorH + monitorStand) * s / 2)
                MacBoxFront(model: model, finish: finish)
                    .frame(width: box.width * s, height: (box.height + box.topBand) * s)
                    .position(x: left + (monitorW + gap + box.width / 2) * s, y: floor - (box.height + box.topBand) * s / 2)
            }
        }
    }

    /// Breite, Höhe der Front, Tiefe der sichtbaren Oberseite (mm)
    private var boxSize: (width: CGFloat, height: CGFloat, topBand: CGFloat) {
        let w = CGFloat(model.width)
        switch model.design {
        case .proTower: return (w, CGFloat(model.height), 22)
        case .proCylinder: return (w, CGFloat(model.height), w * 0.22)
        default: return (w, CGFloat(model.height), CGFloat(model.depth) * 0.2)
        }
    }

    private func monitor(width: CGFloat, height: CGFloat, stand: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.012, style: .continuous)
                    .fill(Color(white: theme.isDark ? 0.08 : 0.12))
                    .overlay(RoundedRectangle(cornerRadius: width * 0.012, style: .continuous).stroke(finish.edge.opacity(0.5), lineWidth: 0.8))
                ZStack {
                    Color.black
                    screen()
                }
                .frame(width: width * 0.965, height: height - width * 0.035)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.004, style: .continuous))
            }
            .frame(width: width, height: height)
            TrapezoidShape(topFraction: 0.8)
                .fill(LinearGradient(colors: [Color(white: theme.isDark ? 0.2 : 0.7), Color(white: theme.isDark ? 0.12 : 0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width * 0.22, height: stand * 0.9)
            Capsule()
                .fill(Color(white: theme.isDark ? 0.2 : 0.68))
                .frame(width: width * 0.32, height: stand * 0.1)
        }
    }
}

/// Mac mini, Mac Studio, Mac Pro in leichter Aufsicht von vorn.
private struct MacBoxFront: View {
    let model: MacModelInfo
    let finish: MacFinish

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            switch model.design {
            case .proTower: tower(w, h)
            case .proCylinder: cylinder(w, h)
            default: box(w, h)
            }
        }
    }

    private func box(_ w: CGFloat, _ h: CGFloat) -> some View {
        let topBand = h * CGFloat(model.depth * 0.2 / (model.height + model.depth * 0.2))
        let frontH = h - topBand
        let radius = w * (model.design == .studio ? 0.09 : 0.14)
        return ZStack(alignment: .topLeading) {
            // Oberseite
            RoundedRectangle(cornerRadius: min(radius, topBand), style: .continuous)
                .fill(LinearGradient(colors: [finish.top.opacity(0.85), finish.top], startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: topBand * 1.6)
            // Front
            RoundedRectangle(cornerRadius: min(radius * 0.5, frontH * 0.3), style: .continuous)
                .fill(LinearGradient(colors: [finish.bottom.opacity(0.95), finish.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: min(radius * 0.5, frontH * 0.3), style: .continuous)
                    .stroke(finish.edge.opacity(0.55), lineWidth: 0.7))
                .frame(width: w, height: frontH)
                .offset(y: topBand)
            details(w, frontH)
                .frame(width: w, height: frontH)
                .offset(y: topBand)
        }
    }

    @ViewBuilder
    private func details(_ w: CGFloat, _ h: CGFloat) -> some View {
        let led = Circle().fill(Color.white.opacity(0.85)).frame(width: max(1.5, w * 0.02), height: max(1.5, w * 0.02))
        switch model.design {
        case .miniCompact:
            // vorn: zwei USB-C-Anschlüsse, Kopfhöreranschluss, Statuslicht
            HStack(spacing: w * 0.05) {
                ForEach(0..<2, id: \.self) { _ in
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: w * 0.07, height: max(1.5, h * 0.12))
                }
                Circle().fill(Color.black.opacity(0.6)).frame(width: max(1.5, h * 0.12), height: max(1.5, h * 0.12))
                Spacer()
                led
            }
            .padding(.horizontal, w * 0.12)
        case .studio:
            ZStack(alignment: .bottom) {
                HStack(spacing: w * 0.04) {
                    Spacer()
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.6)).frame(width: w * 0.06, height: max(1.5, h * 0.06))
                    }
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: w * 0.14, height: max(1, h * 0.025))
                        .padding(.leading, w * 0.04)
                    Spacer().frame(width: w * 0.12)
                }
                .frame(maxHeight: .infinity)
                // Lüftungsöffnungen am unteren Rand
                DotGridShape(columns: 48, rows: 2, dot: 0.5)
                    .fill(Color.black.opacity(0.4))
                    .frame(width: w * 0.9, height: h * 0.08)
                    .padding(.bottom, h * 0.03)
                HStack { Spacer(); led }.padding(.trailing, w * 0.06).frame(maxHeight: .infinity, alignment: .center)
            }
        default:
            HStack { Spacer(); led }.padding(.trailing, w * 0.08).frame(maxHeight: .infinity)
        }
    }

    private func tower(_ w: CGFloat, _ h: CGFloat) -> some View {
        let top = h * 0.05
        return ZStack(alignment: .topLeading) {
            // Griffe
            HStack(spacing: w * 0.36) {
                ForEach(0..<2, id: \.self) { _ in
                    Capsule().stroke(finish.top, lineWidth: max(1.5, w * 0.03))
                        .frame(width: w * 0.2, height: top * 2)
                }
            }
            .frame(width: w)
            RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                .fill(LinearGradient(colors: [finish.top, finish.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.04, style: .continuous).stroke(finish.edge.opacity(0.55), lineWidth: 0.7))
                .frame(width: w, height: h - top * 1.5)
                .offset(y: top)
            DotGridShape(columns: 9, rows: 22, dot: 0.62, staggered: true)
                .fill(Color.black.opacity(0.5))
                .frame(width: w * 0.86, height: (h - top * 1.5) * 0.92)
                .offset(x: w * 0.07, y: top + (h - top * 1.5) * 0.04)
        }
    }

    private func cylinder(_ w: CGFloat, _ h: CGFloat) -> some View {
        let cap = w * 0.22
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: w * 0.5, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.04), Color(white: 0.22), Color(white: 0.05)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: w, height: h - cap / 2)
                .offset(y: cap / 2)
            Ellipse()
                .fill(Color(white: 0.12))
                .overlay(Ellipse().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                .frame(width: w, height: cap)
            Ellipse()
                .fill(Color.black)
                .frame(width: w * 0.62, height: cap * 0.62)
                .offset(y: cap * 0.19)
        }
    }
}

// MARK: - Aufsicht (Wärmekarte)

/// Lage von Tastatur, Funktionsreihe, Lautsprechern und Trackpad auf der Oberseite eines Notebooks (Anteile).
struct MacTopLayout {
    enum Grilles { case none, sides(inset: Double, width: Double), top }
    let keyboardX: ClosedRange<Double>
    let keyboardY: ClosedRange<Double>
    let functionRow: KeyboardShape.FunctionRow
    let grilles: Grilles
    /// Breite, Höhe, oberer Rand (Anteile)
    let trackpad: (width: Double, height: Double, y: Double)
    /// schwarze Tastaturwanne (MacBook Pro ab 2021)
    let darkWell: Bool
    /// Lüftungsschlitze am Scharnier (MacBook Air ab M2)
    let hingeVents: Bool

    init(model: MacModelInfo) {
        let large = (model.inches ?? 13) > 15
        let medium = (model.inches ?? 13) > 14 && !large
        switch model.design {
        case .proTouchBar where large:
            keyboardX = 0.13...0.87; keyboardY = 0.065...0.44; functionRow = .touchBarWithEscape
            grilles = .sides(inset: 0.04, width: 0.075); trackpad = (0.447, 0.407, 0.5)
        case .proTouchBar where medium:
            keyboardX = 0.135...0.865; keyboardY = 0.065...0.44; functionRow = .touchBar
            grilles = .sides(inset: 0.04, width: 0.08); trackpad = (0.458, 0.415, 0.5)
        case .proTouchBar:
            keyboardX = 0.095...0.905; keyboardY = 0.075...0.47; functionRow = .touchBar
            grilles = .sides(inset: 0.035, width: 0.05); trackpad = (0.444, 0.39, 0.53)
        case .proFunctionKeys:
            keyboardX = 0.095...0.905; keyboardY = 0.075...0.47; functionRow = .half
            grilles = .sides(inset: 0.035, width: 0.05); trackpad = (0.444, 0.39, 0.53)
        case .proNotch, .proIsland:
            if large {
                keyboardX = 0.14...0.86; keyboardY = 0.06...0.44
                grilles = .sides(inset: 0.04, width: 0.085); trackpad = (0.382, 0.355, 0.53)
            } else {
                keyboardX = 0.115...0.885; keyboardY = 0.06...0.46
                grilles = .sides(inset: 0.035, width: 0.065); trackpad = (0.384, 0.353, 0.55)
            }
            functionRow = .full
        case .airRetina:
            keyboardX = 0.085...0.915; keyboardY = 0.07...0.47; functionRow = .halfWithTouchID
            grilles = .sides(inset: 0.03, width: 0.04); trackpad = (0.395, 0.377, 0.55)
        case .airFlat:
            keyboardX = large ? 0.115...0.885 : 0.07...0.93; keyboardY = 0.065...0.47; functionRow = .full
            grilles = .none; trackpad = large ? (0.40, 0.362, 0.55) : (0.395, 0.372, 0.55)
        case .airClassic:
            keyboardX = 0.085...0.915; keyboardY = 0.08...0.47; functionRow = .half
            grilles = .none; trackpad = (0.323, 0.335, 0.56)
        case .macBook12:
            keyboardX = 0.04...0.96; keyboardY = 0.09...0.47; functionRow = .half
            grilles = .top; trackpad = (0.40, 0.36, 0.55)
        default:
            keyboardX = 0.1...0.9; keyboardY = 0.07...0.47; functionRow = .half
            grilles = .none; trackpad = (0.4, 0.37, 0.55)
        }
        darkWell = model.design == .proNotch || model.design == .proIsland
        hingeVents = model.design == .airFlat
    }
}

/// Gehäuse in Aufsicht bzw. Frontansicht (Wärmekarte), zurückhaltend gezeichnet, damit die Messpunkte lesbar bleiben.
struct MacTopArt: View {
    @Environment(\.aether) private var theme
    let model: MacModelInfo?

    /// Seitenverhältnis der Zeichnung (Breite/Höhe).
    static func aspect(_ model: MacModelInfo?) -> CGFloat {
        guard let model else { return 1.3 }
        switch model.design {
        case .iMacClassic, .iMacPro, .iMac24:
            let g = IMacGeometry(model)
            return g.width / g.panel
        case .proTower: return CGFloat(model.width / model.height)
        case .proCylinder, .miniClassic, .miniCompact, .studio: return 1
        default: return CGFloat(model.width / model.depth)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Group {
                if let model {
                    switch model.design {
                    case .iMacClassic, .iMacPro, .iMac24: iMacPanel(model, w, h)
                    case .proTower: towerFront(w, h)
                    case .proCylinder: cylinderTop(w, h)
                    case .miniClassic, .miniCompact, .studio: boxTop(model, w, h)
                    default: laptopTop(model, w, h)
                    }
                } else {
                    plain(w, h)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var fill: Color { theme.fieldFill.opacity(1.4) }
    private var line: Color { theme.hairline }
    private var detail: Color { theme.textTertiary.opacity(theme.isDark ? 0.22 : 0.28) }
    private var grille: Color { theme.textTertiary.opacity(theme.isDark ? 0.42 : 0.5) }

    private func laptopTop(_ model: MacModelInfo, _ w: CGFloat, _ h: CGFloat) -> some View {
        let layout = MacTopLayout(model: model)
        let kbX = w * CGFloat(layout.keyboardX.lowerBound)
        let kbW = w * CGFloat(layout.keyboardX.upperBound - layout.keyboardX.lowerBound)
        let kbY = h * CGFloat(layout.keyboardY.lowerBound)
        let kbH = h * CGFloat(layout.keyboardY.upperBound - layout.keyboardY.lowerBound)
        let tp = layout.trackpad
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: w * 0.03, style: .continuous)
                .fill(LinearGradient(colors: [fill, theme.fieldFill.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.03, style: .continuous).strokeBorder(line, lineWidth: 1))
            // Scharnier
            Rectangle()
                .fill(detail.opacity(0.6))
                .frame(width: w * 0.86, height: max(1, h * 0.012))
                .offset(x: w * 0.07, y: h * 0.012)
            if layout.hingeVents {
                // Lüftungsschlitze am Scharnier (MacBook Air ab M2)
                HStack(spacing: w * 0.006) {
                    ForEach(0..<40, id: \.self) { _ in
                        Capsule().fill(grille).frame(height: max(1, h * 0.012))
                    }
                }
                .frame(width: w * 0.8)
                .offset(x: w * 0.1, y: h * 0.032)
            }
            grilles(layout, w, h, kbY: kbY, kbH: kbH)
            if layout.darkWell {
                RoundedRectangle(cornerRadius: w * 0.01, style: .continuous)
                    .fill(Color.black.opacity(theme.isDark ? 0.35 : 0.12))
                    .frame(width: kbW + w * 0.012, height: kbH + h * 0.02)
                    .offset(x: kbX - w * 0.006, y: kbY - h * 0.01)
            }
            KeyboardShape(functionRow: layout.functionRow)
                .fill(detail)
                .frame(width: kbW, height: kbH)
                .offset(x: kbX, y: kbY)
            RoundedRectangle(cornerRadius: w * 0.012, style: .continuous)
                .fill(detail.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: w * 0.012, style: .continuous).strokeBorder(line, lineWidth: 1))
                .frame(width: w * CGFloat(tp.width), height: h * CGFloat(tp.height))
                .offset(x: w * (1 - CGFloat(tp.width)) / 2, y: h * CGFloat(tp.y))
            // Griffmulde an der Vorderkante
            Capsule()
                .fill(line)
                .frame(width: w * 0.1, height: max(1.5, h * 0.012))
                .offset(x: w * 0.45, y: h - max(1.5, h * 0.012) - 1)
        }
    }

    @ViewBuilder
    private func grilles(_ layout: MacTopLayout, _ w: CGFloat, _ h: CGFloat, kbY: CGFloat, kbH: CGFloat) -> some View {
        switch layout.grilles {
        case .none: EmptyView()
        case .top:
            // MacBook 12″: Gitter über der ganzen Tastaturbreite
            DotGridShape(columns: 72, rows: 3, dot: 0.6)
                .fill(grille)
                .frame(width: w * 0.9, height: h * 0.034)
                .offset(x: w * 0.05, y: h * 0.045)
        case .sides(let inset, let width):
            // Lautsprechergitter links und rechts der Tastatur
            let gw = w * CGFloat(width)
            let columns = max(3, Int((gw / max(1, kbH)) * 26))
            ForEach(0..<2, id: \.self) { side in
                DotGridShape(columns: columns, rows: 26, dot: 0.58)
                    .fill(grille)
                    .frame(width: gw, height: kbH)
                    .offset(x: side == 0 ? w * CGFloat(inset) : w - w * CGFloat(inset) - gw, y: kbY)
            }
        }
    }

    private func iMacPanel(_ model: MacModelInfo, _ w: CGFloat, _ h: CGFloat) -> some View {
        let g = IMacGeometry(model)
        let s = w / g.width
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: w * 0.018, style: .continuous)
                .fill(LinearGradient(colors: [fill, theme.fieldFill.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.018, style: .continuous).strokeBorder(line, lineWidth: 1))
            RoundedRectangle(cornerRadius: w * 0.004, style: .continuous)
                .strokeBorder(line, lineWidth: 1)
                .frame(width: g.display.width * s, height: g.display.height * s)
                .offset(x: (g.width - g.display.width) / 2 * s, y: g.top * s)
            Rectangle()
                .fill(line)
                .frame(width: w, height: 1)
                .offset(y: (g.panel - g.chin) * s)
        }
    }

    private func boxTop(_ model: MacModelInfo, _ w: CGFloat, _ h: CGFloat) -> some View {
        let radius = w * (model.design == .studio ? 0.1 : (model.design == .miniCompact ? 0.17 : 0.16))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [fill, theme.fieldFill.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(line, lineWidth: 1))
            // Anschlüsse hinten (oben im Bild), Vorderseite unten
            HStack(spacing: w * 0.025) {
                ForEach(0..<(model.design == .miniCompact ? 5 : 7), id: \.self) { _ in
                    Capsule().fill(detail).frame(width: w * 0.05, height: max(1.5, h * 0.018))
                }
            }
            .frame(width: w)
            .offset(y: h * 0.05)
            Capsule()
                .fill(detail)
                .frame(width: w * 0.3, height: max(1.5, h * 0.012))
                .offset(x: w * 0.35, y: h * 0.94)
        }
    }

    private func towerFront(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                .fill(LinearGradient(colors: [fill, theme.fieldFill.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.05, style: .continuous).strokeBorder(line, lineWidth: 1))
            DotGridShape(columns: 9, rows: 22, dot: 0.55, staggered: true)
                .fill(detail)
                .frame(width: w * 0.86, height: h * 0.9)
                .offset(x: w * 0.07, y: h * 0.05)
        }
    }

    private func cylinderTop(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [fill, theme.fieldFill.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(line, lineWidth: 1))
            Circle()
                .strokeBorder(line, lineWidth: 1)
                .frame(width: w * 0.62, height: h * 0.62)
        }
    }

    private func plain(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(w, h) * 0.07, style: .continuous)
            .fill(LinearGradient(colors: [fill, theme.fieldFill.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: min(w, h) * 0.07, style: .continuous).strokeBorder(line, lineWidth: 1))
    }
}
