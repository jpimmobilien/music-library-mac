import SwiftUI
import AppKit
import ABCore

// =============================================================================================
// Produktbühne der Übersicht (5.0): dieser Mac als aufgeklapptes Notebook in echter Perspektive –
// berechnet aus einem 3D-Modell seiner Bauform – mit der laufenden App auf dem Bildschirm, davor das
// verbundene Telefon mit dem neuesten Foto. Alles selbst gezeichnet: keine Produktfotos, keine Logos.
// =============================================================================================

/// Punkt im Raum (Einheit: Breite des Notebooks = 1).
private struct P3 {
    var x: CGFloat, y: CGFloat, z: CGFloat
}

/// Maße einer Notebook-Bauform (Anteile der Breite).
struct LaptopDims {
    var side: CGFloat, top: CGFloat, chin: CGFloat
    var screenRatio: CGFloat
    var notch: Bool
    var baseThickness: CGFloat
    var lidCorner: CGFloat
    var bezelIsMetal = false
    /// Touch Bar statt Funktionstasten (MacBook Pro 2016–2022 mit Kinn).
    var touchBar = false
    /// Lautsprechergitter links und rechts der Tastatur (15"/16" und Notch-Pro).
    var sideSpeakers = false
    /// Funktionstasten in voller Höhe (Notch-Modelle).
    var fullFunctionRow = false

    static func of(_ hardware: MacHardware) -> LaptopDims {
        let name = hardware.marketingName
        let big = name.contains("15") || name.contains("16")
        switch hardware.form {
        case .notchPro:
            return LaptopDims(side: 0.021, top: 0.026, chin: 0.03, screenRatio: 1.54, notch: true, baseThickness: 0.044,
                              lidCorner: 0.03, sideSpeakers: true, fullFunctionRow: true)
        case .notchAir:
            return LaptopDims(side: 0.021, top: 0.026, chin: 0.03, screenRatio: 1.56, notch: true, baseThickness: 0.03,
                              lidCorner: 0.028, fullFunctionRow: true)
        case .retinaAir:
            return LaptopDims(side: 0.03, top: 0.038, chin: 0.06, screenRatio: 1.6, notch: false, baseThickness: 0.034, lidCorner: 0.026)
        case .classicAir:
            return LaptopDims(side: 0.062, top: 0.06, chin: 0.075, screenRatio: 1.6, notch: false, baseThickness: 0.036,
                              lidCorner: 0.03, bezelIsMetal: true)
        case .classicPro:
            return LaptopDims(side: 0.04, top: 0.05, chin: 0.08, screenRatio: 1.6, notch: false, baseThickness: 0.046,
                              lidCorner: 0.03, sideSpeakers: big)
        default:
            // MacBook Pro / MacBook 2016–2022 mit Kinn
            let pro = hardware.familyName.contains("Pro")
            let touchBar = pro && (name.contains("Touch") || !name.contains("2 × Thunderbolt"))
            return LaptopDims(side: 0.028, top: 0.036, chin: 0.066, screenRatio: 1.6, notch: false, baseThickness: 0.04,
                              lidCorner: 0.026, touchBar: touchBar, sideSpeakers: pro && big)
        }
    }

    var lidHeight: CGFloat { (1 - 2 * side) / screenRatio + top + chin }
    var depth: CGFloat { lidHeight * 1.03 }
}

/// Kamera: Drehung um die Hochachse (yaw), Blick von oben (pitch), Öffnungswinkel des Deckels.
struct LaptopCamera {
    var yaw: Double = -24
    var pitch: Double = 19
    var lidTilt: Double = 17
    var distance: CGFloat = 3.4
}

/// Berechnet die Perspektive und liefert Polygone in Bildkoordinaten.
private struct LaptopProjector {
    let dims: LaptopDims
    let camera: LaptopCamera
    var scale: CGFloat = 1
    var offset: CGPoint = .zero

    private var cy: CGFloat { CGFloat(cos(camera.yaw * .pi / 180)) }
    private var sy: CGFloat { CGFloat(sin(camera.yaw * .pi / 180)) }
    private var cp: CGFloat { CGFloat(cos(camera.pitch * .pi / 180)) }
    private var sp: CGFloat { CGFloat(sin(camera.pitch * .pi / 180)) }
    private var ct: CGFloat { CGFloat(cos(camera.lidTilt * .pi / 180)) }
    private var st: CGFloat { CGFloat(sin(camera.lidTilt * .pi / 180)) }

    func raw(_ p: P3) -> CGPoint {
        let x = p.x, y = p.y - dims.lidHeight * 0.35, z = p.z - dims.depth * 0.35
        let x1 = x * cy + z * sy
        let z1 = -x * sy + z * cy
        let y2 = y * cp - z1 * sp
        let z2 = y * sp + z1 * cp
        let k = camera.distance / (camera.distance - z2)
        return CGPoint(x: x1 * k, y: -y2 * k)
    }

    func point(_ p: P3) -> CGPoint {
        let r = raw(p)
        return CGPoint(x: r.x * scale + offset.x, y: r.y * scale + offset.y)
    }

    /// Deckel: u quer (−0,5…0,5), v vom Scharnier nach oben; `w` = Tiefe (Rückseite negativ).
    func lid(_ u: CGFloat, _ v: CGFloat, _ w: CGFloat = 0) -> P3 {
        P3(x: u, y: dims.baseThickness + v * ct - w * st, z: 0.012 - v * st - w * ct)
    }

    /// Unterteil: x quer, z von hinten (0) nach vorn (Tiefe), y Höhe.
    func base(_ x: CGFloat, _ z: CGFloat, _ y: CGFloat) -> P3 { P3(x: x, y: y, z: z) }

    /// Abgerundetes Rechteck in einer Ebene → Polygon.
    static func roundedRect(x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, r: CGFloat, steps: Int = 6) -> [CGPoint] {
        let r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
        var pts: [CGPoint] = []
        let corners: [(CGFloat, CGFloat, Double)] = [(x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180), (x1 - r, y0 + r, 270)]
        for (cx, cyy, start) in corners {
            for i in 0...steps {
                let a = (start + Double(i) * 90 / Double(steps)) * .pi / 180
                pts.append(CGPoint(x: cx + r * CGFloat(cos(a)), y: cyy + r * CGFloat(sin(a))))
            }
        }
        return pts
    }

    func lidPolygon(x0: CGFloat, x1: CGFloat, v0: CGFloat, v1: CGFloat, r: CGFloat, w: CGFloat = 0) -> [CGPoint] {
        LaptopProjector.roundedRect(x0: x0, x1: x1, y0: v0, y1: v1, r: r).map { point(lid($0.x, $0.y, w)) }
    }

    func basePolygon(x0: CGFloat, x1: CGFloat, z0: CGFloat, z1: CGFloat, r: CGFloat, y: CGFloat) -> [CGPoint] {
        LaptopProjector.roundedRect(x0: x0, x1: x1, y0: z0, y1: z1, r: r).map { point(base($0.x, $0.y, y)) }
    }

    func baseQuad(x0: CGFloat, x1: CGFloat, z0: CGFloat, z1: CGFloat, y: CGFloat) -> [CGPoint] {
        [point(base(x0, z0, y)), point(base(x1, z0, y)), point(base(x1, z1, y)), point(base(x0, z1, y))]
    }

    /// Umriss aller sichtbaren Teile (für das Einpassen in den Rahmen).
    func outline() -> [CGPoint] {
        let d = dims
        var pts: [CGPoint] = []
        for (u, v) in [(-0.5, 0.0), (0.5, 0.0), (-0.5, d.lidHeight), (0.5, d.lidHeight)] as [(CGFloat, CGFloat)] {
            pts.append(raw(lid(u, v)))
        }
        for (x, z) in [(-0.5, 0.0), (0.5, 0.0), (-0.5, d.depth), (0.5, d.depth)] as [(CGFloat, CGFloat)] {
            pts.append(raw(base(x, z, 0)))
            pts.append(raw(base(x, z, d.baseThickness)))
        }
        return pts
    }
}

/// Polygon in festen Bildkoordinaten.
private struct Polygon: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for q in points.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }
}

/// Mehrere Polygone als ein Pfad (z. B. alle Tasten).
private struct PolygonSet: Shape {
    var polygons: [[CGPoint]]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for poly in polygons {
            guard let first = poly.first else { continue }
            p.move(to: first)
            for q in poly.dropFirst() { p.addLine(to: q) }
            p.closeSubpath()
        }
        return p
    }
}

private func bounds(_ pts: [CGPoint]) -> CGRect {
    guard let f = pts.first else { return .zero }
    var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
    for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// Projektive Abbildung: Rechteck (0,0)–(w,h) auf das Viereck tl, tr, br, bl.
private func homography(width w: CGFloat, height h: CGFloat, tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) -> ProjectionTransform {
    let x0 = tl.x, y0 = tl.y, x1 = tr.x, y1 = tr.y, x2 = br.x, y2 = br.y, x3 = bl.x, y3 = bl.y
    let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
    let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
    let den = dx1 * dy2 - dx2 * dy1
    let g: CGFloat = abs(den) < 1e-9 ? 0 : (dx3 * dy2 - dx2 * dy3) / den
    let hh: CGFloat = abs(den) < 1e-9 ? 0 : (dx1 * dy3 - dx3 * dy1) / den
    let a = x1 - x0 + g * x1, b = x3 - x0 + hh * x3, c = x0
    let d = y1 - y0 + g * y1, e = y3 - y0 + hh * y3, f = y0
    var t = ProjectionTransform()
    t.m11 = a / w; t.m12 = d / w; t.m13 = g / w
    t.m21 = b / h; t.m22 = e / h; t.m23 = hh / h
    t.m31 = c; t.m32 = f; t.m33 = 1
    return t
}

// MARK: - Notebook in Perspektive

/// Dieser Mac als aufgeklapptes Notebook in Dreiviertelansicht. `screen` wird perspektivisch auf das Display gelegt.
struct PerspectiveLaptop<Screen: View>: View {
    var hardware: MacHardware = .current
    var camera = LaptopCamera()
    /// Gestaltungsgröße des Bildschirminhalts (wird perspektivisch verkleinert).
    var screenSize = CGSize(width: 960, height: 600)
    @ViewBuilder var screen: () -> Screen
    @AppStorage(MacAppearance.storageKey) private var storedFinish = "auto"
    @Environment(\.colorScheme) private var scheme

    private var finish: MacFinish { MacAppearance.finish(for: hardware, stored: storedFinish) }

    var body: some View {
        GeometryReader { geo in
            let proj = fitted(in: geo.size)
            ZStack(alignment: .topLeading) {
                groundShadow(proj)
                lid(proj)
                base(proj)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hardware.marketingName)
    }

    private func fitted(in size: CGSize) -> LaptopProjector {
        var p = LaptopProjector(dims: LaptopDims.of(hardware), camera: camera)
        let b = bounds(p.outline())
        let s = min(size.width / max(b.width, 0.001), size.height * 0.94 / max(b.height, 0.001))
        p.scale = s
        p.offset = CGPoint(x: (size.width - b.width * s) / 2 - b.minX * s, y: (size.height * 0.97 - b.height * s) - b.minY * s)
        return p
    }

    // MARK: Teile

    private func groundShadow(_ p: LaptopProjector) -> some View {
        let d = p.dims
        let pts = p.basePolygon(x0: -0.52, x1: 0.52, z0: -0.02, z1: d.depth + 0.03, r: 0.05, y: 0)
        let b = bounds(pts)
        let contact = p.basePolygon(x0: -0.49, x1: 0.49, z0: 0.01, z1: d.depth, r: 0.04, y: 0)
        return ZStack(alignment: .topLeading) {
            // weicher Umgebungsschatten
            Polygon(points: pts)
                .fill(Color.black.opacity(scheme == .dark ? 0.7 : 0.22))
                .blur(radius: max(8, b.height * 0.12))
                .offset(y: b.height * 0.07)
            // Kontaktschatten direkt unter dem Gehäuse
            Polygon(points: contact)
                .fill(Color.black.opacity(scheme == .dark ? 0.85 : 0.45))
                .blur(radius: max(1.5, b.height * 0.012))
                .offset(y: b.height * 0.012)
        }
        .allowsHitTesting(false)
    }

    private func lid(_ p: LaptopProjector) -> some View {
        let d = p.dims
        let (light, dark) = finish.metal
        let half: CGFloat = 0.5
        let rim = p.lidPolygon(x0: -half, x1: half, v0: 0, v1: d.lidHeight, r: d.lidCorner, w: -0.006)
        let face = p.lidPolygon(x0: -half, x1: half, v0: 0, v1: d.lidHeight, r: d.lidCorner)
        let glass = p.lidPolygon(x0: -half + 0.004, x1: half - 0.004, v0: 0.004, v1: d.lidHeight - 0.004, r: d.lidCorner - 0.003)
        let sx0 = -half + d.side, sx1 = half - d.side, sv0 = d.chin, sv1 = d.lidHeight - d.top
        let tl = p.point(p.lid(sx0, sv1)), tr = p.point(p.lid(sx1, sv1)), br = p.point(p.lid(sx1, sv0)), bl = p.point(p.lid(sx0, sv0))
        let screenPoly = p.lidPolygon(x0: sx0, x1: sx1, v0: sv0, v1: sv1, r: d.notch ? 0.012 : 0.003)
        let fb = bounds(face)
        return ZStack(alignment: .topLeading) {
            // Rückseite/Kante des Deckels
            Polygon(points: rim).fill(LinearGradient(colors: [dark, light], startPoint: .top, endPoint: .bottom))
            Polygon(points: face).fill(LinearGradient(colors: [light, dark], startPoint: .leading, endPoint: .trailing))
            // Glasrahmen (beim alten MacBook Air: Metall)
            Polygon(points: glass).fill(d.bezelIsMetal ? AnyShapeStyle(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom))
                                                       : AnyShapeStyle(Color(hex: 0x0B0B0C)))
            // Bildschirm mit echtem Inhalt
            screen()
                .frame(width: screenSize.width, height: screenSize.height)
                .clipped()
                .projectionEffect(homography(width: screenSize.width, height: screenSize.height, tl: tl, tr: tr, br: br, bl: bl))
                .mask(Polygon(points: screenPoly))
            if d.notch {
                let n = p.lidPolygon(x0: -0.055, x1: 0.055, v0: sv1 - 0.024, v1: sv1 + 0.004, r: 0.008)
                Polygon(points: n).fill(Color(hex: 0x0B0B0C))
            } else {
                let c = p.point(p.lid(0, d.lidHeight - d.top * 0.5))
                Circle().fill(Color(hex: 0x1A2430))
                    .frame(width: max(2, fb.width * 0.008), height: max(2, fb.width * 0.008))
                    .position(c)
            }
            // Tiefe: der Bildschirm liegt unter dem Glas (leichte Abdunklung zu den Rändern)
            Polygon(points: screenPoly)
                .stroke(Color.black.opacity(0.35), lineWidth: max(1, fb.width * 0.006))
                .blur(radius: max(0.6, fb.width * 0.004))
                .mask(Polygon(points: screenPoly))
                .allowsHitTesting(false)
            // Spiegelung auf dem Glas: breite, weiche Bahn wie im Studiolicht
            Polygon(points: glass)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.13), location: 0), .init(color: .white.opacity(0.05), location: 0.32),
                                             .init(color: .white.opacity(0.0), location: 0.5), .init(color: .white.opacity(0.03), location: 0.78),
                                             .init(color: .clear, location: 1)],
                                     startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1)))
                .allowsHitTesting(false)
            // Lichtkante am Deckelrand (Fase)
            Polygon(points: face).stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.18), .white.opacity(0.45)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
    }

    private func base(_ p: LaptopProjector) -> some View {
        let d = p.dims
        let (light, dark) = finish.metal
        let t = d.baseThickness
        let r: CGFloat = 0.03
        // Seitenwände: Umriss in mehreren Höhen übereinander (ergibt die abgerundete Kante in jeder Drehung)
        let layers: [[CGPoint]] = stride(from: 0.0, to: 1.0, by: 0.2).map { k in
            p.basePolygon(x0: -0.5, x1: 0.5, z0: 0, z1: d.depth, r: r, y: t * CGFloat(k))
        }
        let top = p.basePolygon(x0: -0.5, x1: 0.5, z0: 0, z1: d.depth, r: r, y: t)
        return ZStack(alignment: .topLeading) {
            // Seitenwände: unten dunkler, zur Oberkante hin heller (gerundete Aluminiumkante)
            ForEach(layers.indices, id: \.self) { i in
                let k = Double(i) / Double(max(layers.count - 1, 1))
                Polygon(points: layers[i]).fill(dark.opacity(0.75 + 0.2 * (1 - k)))
                Polygon(points: layers[i]).fill(light.opacity(0.18 * k))
            }
            Polygon(points: layers[0]).fill(Color.black.opacity(0.22))
            Polygon(points: top)
                .fill(LinearGradient(colors: [light.opacity(0.9), light, dark.opacity(0.7)],
                                     startPoint: UnitPoint(x: 0.5, y: 0), endPoint: UnitPoint(x: 0.5, y: 1)))
            // Glanzlicht des Studiolichts auf dem Aluminium
            Polygon(points: top)
                .fill(RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.16 : 0.42), .clear],
                                     center: UnitPoint(x: 0.3, y: 0.75), startRadius: 0, endRadius: bounds(top).width * 0.45))
                .allowsHitTesting(false)
            // Scharnier: schmale dunkle Fuge hinten
            Polygon(points: p.basePolygon(x0: -0.4, x1: 0.4, z0: -0.003, z1: 0.012, r: 0.005, y: t + 0.0003))
                .fill(LinearGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0.15)], startPoint: .top, endPoint: .bottom))
            keyboard(p)
            trackpad(p)
            // Griffmulde vorn (Modelle mit Kinn)
            if !d.notch {
                Polygon(points: p.basePolygon(x0: -0.055, x1: 0.055, z0: d.depth - 0.012, z1: d.depth + 0.002, r: 0.006, y: t + 0.0005))
                    .fill(dark.opacity(0.85))
            }
            // Lichtkante vorne oben
            Polygon(points: top).stroke(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.85)],
                                                       startPoint: UnitPoint(x: 0.5, y: 0), endPoint: UnitPoint(x: 0.5, y: 1)), lineWidth: 0.7)
        }
    }

    private func keyboard(_ p: LaptopProjector) -> some View {
        let d = p.dims
        let y = d.baseThickness + 0.0004
        let kx0: CGFloat = d.sideSpeakers ? -0.41 : -0.445
        let kx1: CGFloat = -kx0
        let kz0: CGFloat = d.depth * 0.065
        let kz1: CGFloat = d.depth * 0.47
        let (_, dark) = finish.metal
        let keyColor = finish == .silver || finish == .starlight || finish == .gold || finish == .skyBlue
            ? Color(hex: 0x1C1C1E) : Color(hex: 0x111113)
        let keys = keyPolygons(p, x0: kx0, x1: kx1, z0: kz0, z1: kz1, y: y)
        let well = p.basePolygon(x0: kx0 - 0.006, x1: kx1 + 0.006, z0: kz0 - 0.006, z1: kz1 + 0.006, r: 0.008, y: y)
        return ZStack(alignment: .topLeading) {
            Polygon(points: well).fill(dark.opacity(0.22))
            PolygonSet(polygons: keys.keys).fill(keyColor)
            PolygonSet(polygons: keys.keys).stroke(Color.white.opacity(0.08), lineWidth: 0.4)
            if let bar = keys.touchBar {
                Polygon(points: bar).fill(LinearGradient(colors: [Color(hex: 0x14161C), Color(hex: 0x050506)], startPoint: .leading, endPoint: .trailing))
                Polygon(points: bar).stroke(Color.white.opacity(0.12), lineWidth: 0.4)
            }
            if d.sideSpeakers {
                Polygon(points: p.basePolygon(x0: -0.485, x1: kx0 - 0.018, z0: kz0, z1: kz1, r: 0.004, y: y)).fill(dark.opacity(0.28))
                Polygon(points: p.basePolygon(x0: kx1 + 0.018, x1: 0.485, z0: kz0, z1: kz1, r: 0.004, y: y)).fill(dark.opacity(0.28))
            }
        }
    }

    private func trackpad(_ p: LaptopProjector) -> some View {
        let d = p.dims
        let (light, dark) = finish.metal
        let w: CGFloat = d.sideSpeakers ? 0.46 : 0.38
        let pad = p.basePolygon(x0: -w / 2, x1: w / 2, z0: d.depth * 0.53, z1: d.depth * 0.94, r: 0.014, y: d.baseThickness + 0.0004)
        return ZStack(alignment: .topLeading) {
            Polygon(points: pad).fill(LinearGradient(colors: [light.opacity(0.85), dark.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            Polygon(points: pad).stroke(dark.opacity(0.6), lineWidth: 0.5)
        }
    }

    /// Tastenfelder als Polygone (Reihen mit Einheitsbreiten wie bei einer Mac-Tastatur).
    private func keyPolygons(_ p: LaptopProjector, x0: CGFloat, x1: CGFloat, z0: CGFloat, z1: CGFloat, y: CGFloat)
        -> (keys: [[CGPoint]], touchBar: [CGPoint]?) {
        let d = p.dims
        let rows: [[CGFloat]] = [
            [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],
            [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            [1.8, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.7],
            [2.3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.2],
            [1, 1, 1, 1.25, 5, 1.25, 1, 3],
        ]
        let fnHeight: CGFloat = d.fullFunctionRow ? 1 : 0.55
        let total: CGFloat = 5 + fnHeight
        let unitZ = (z1 - z0) / total
        let gap: CGFloat = 0.12
        var polys: [[CGPoint]] = []
        var bar: [CGPoint]?
        func zAt(_ rowTop: CGFloat) -> CGFloat { z0 + rowTop * unitZ }
        func xAt(_ u: CGFloat) -> CGFloat { x0 + (x1 - x0) * u / 14.5 }
        // Funktionsreihe
        let fz0 = zAt(gap / 2), fz1 = zAt(fnHeight - gap / 2)
        if d.touchBar {
            bar = p.baseQuad(x0: xAt(1.5 + gap / 2), x1: xAt(13.5 - gap / 2), z0: fz0, z1: fz1, y: y)
            polys.append(p.baseQuad(x0: xAt(gap / 2), x1: xAt(1.5 - gap / 2), z0: fz0, z1: fz1, y: y))
            polys.append(p.baseQuad(x0: xAt(13.5 + gap / 2), x1: xAt(14.5 - gap / 2), z0: fz0, z1: fz1, y: y))
        } else {
            var u: CGFloat = 0
            for w in [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1] as [CGFloat] {
                polys.append(p.baseQuad(x0: xAt(u + gap / 2), x1: xAt(u + w - gap / 2), z0: fz0, z1: fz1, y: y))
                u += w
            }
        }
        for (i, row) in rows.enumerated() {
            let top = fnHeight + CGFloat(i)
            let rz0 = zAt(top + gap / 2), rz1 = zAt(top + 1 - gap / 2)
            var u: CGFloat = 0
            for (j, w) in row.enumerated() {
                if i == 4 && j == row.count - 1 {
                    // Pfeiltasten: links/rechts volle Höhe unten, hoch/runter halbe Höhe
                    let mid = zAt(top + 0.5)
                    polys.append(p.baseQuad(x0: xAt(u + gap / 2), x1: xAt(u + 1 - gap / 2), z0: mid + unitZ * gap / 4, z1: rz1, y: y))
                    polys.append(p.baseQuad(x0: xAt(u + 1 + gap / 2), x1: xAt(u + 2 - gap / 2), z0: rz0, z1: mid - unitZ * gap / 4, y: y))
                    polys.append(p.baseQuad(x0: xAt(u + 1 + gap / 2), x1: xAt(u + 2 - gap / 2), z0: mid + unitZ * gap / 4, z1: rz1, y: y))
                    polys.append(p.baseQuad(x0: xAt(u + 2 + gap / 2), x1: xAt(u + 3 - gap / 2), z0: mid + unitZ * gap / 4, z1: rz1, y: y))
                } else {
                    polys.append(p.baseQuad(x0: xAt(u + gap / 2), x1: xAt(u + w - gap / 2), z0: rz0, z1: rz1, y: y))
                }
                u += w
            }
        }
        return (polys, bar)
    }
}

// MARK: - Telefon

/// Bauart des Telefons nach Hersteller/Modell – Rahmen, Ecken und Kameraloch unterscheiden sich.
enum PhoneStyle {
    case pixel, galaxyUltra, galaxy, generic

    init(manufacturer: String, model: String) {
        let m = (manufacturer + " " + model).lowercased()
        if m.contains("pixel") || m.contains("google") { self = .pixel }
        else if m.contains("samsung") || m.contains("galaxy") || m.contains("sm-") {
            self = (m.contains("ultra") || m.contains("s918") || m.contains("s928") || m.contains("s938")) ? .galaxyUltra : .galaxy
        } else { self = .generic }
    }

    var cornerRatio: CGFloat {
        switch self {
        case .pixel: return 0.15
        case .galaxyUltra: return 0.07
        case .galaxy: return 0.13
        case .generic: return 0.14
        }
    }
    var bezel: CGFloat {
        switch self {
        case .pixel: return 0.042
        case .galaxyUltra, .galaxy: return 0.032
        case .generic: return 0.04
        }
    }
    var frame: (Color, Color) {
        switch self {
        case .pixel: return (Color(hex: 0x5A5C61), Color(hex: 0x1D1E21))
        case .galaxyUltra: return (Color(hex: 0x9A9894), Color(hex: 0x4C4B48))
        case .galaxy: return (Color(hex: 0x7E8389), Color(hex: 0x32363B))
        case .generic: return (Color(hex: 0x62666C), Color(hex: 0x24272B))
        }
    }
}

/// Ein Telefon von vorn, leicht gedreht; Bildschirm mit echtem Inhalt.
struct RealisticPhone<Screen: View>: View {
    var height: CGFloat
    var style: PhoneStyle = .generic
    var yaw: Double = 14
    /// Flach auf dem Tisch liegend, von oben gesehen (keine Kante, Schatten rundum).
    var lying = false
    /// Echtes Produktfoto des Telefons (falls vorhanden) statt der Zeichnung.
    var photo: PhonePhoto? = nil
    @ViewBuilder var screen: () -> Screen
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let photo, photo.image != nil {
            photoBody(photo)
        } else if lying {
            phoneBody(depth: 0)
                .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.22), radius: height * 0.03, y: height * 0.018)
                .accessibilityHidden(true)
        } else {
            standing
        }
    }

    private var standing: some View {
        let width = height / 2.12
        return phoneBody(depth: width * 0.075)
            .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .background(alignment: .bottom) {
                ZStack {
                    Ellipse()
                        .fill(Color.black.opacity(scheme == .dark ? 0.7 : 0.25))
                        .frame(width: width * 1.25, height: height * 0.07)
                        .blur(radius: height * 0.03)
                        .offset(y: height * 0.025)
                    Ellipse()
                        .fill(Color.black.opacity(scheme == .dark ? 0.85 : 0.45))
                        .frame(width: width * 0.95, height: height * 0.018)
                        .blur(radius: height * 0.006)
                        .offset(y: height * 0.006)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func photoBody(_ photo: PhonePhoto) -> some View {
        let px = photo.pixelSize
        let h = height
        let w = h * px.width / px.height
        let k = h / px.height
        let r = photo.screen
        let view = ZStack(alignment: .topLeading) {
            if let img = photo.image {
                Image(nsImage: img).resizable().interpolation(.high).frame(width: w, height: h)
            }
            screen()
                .frame(width: r.width * k, height: r.height * k)
                .clipShape(RoundedRectangle(cornerRadius: photo.screenCorner * k, style: .continuous))
                .offset(x: r.minX * k, y: r.minY * k)
            // Kamera-Loch wie im Foto
            Circle()
                .fill(Color.black)
                .overlay(Circle().fill(Color(white: 0.18)).padding(photo.punchRadius * k * 0.45))
                .frame(width: photo.punchRadius * 2 * k, height: photo.punchRadius * 2 * k)
                .offset(x: (photo.punch.x - photo.punchRadius) * k, y: (photo.punch.y - photo.punchRadius) * k)
            // Glas: weiche Spiegelung
            RoundedRectangle(cornerRadius: photo.screenCorner * k, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.12), location: 0), .init(color: .white.opacity(0.03), location: 0.35),
                                             .init(color: .clear, location: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: r.width * k, height: r.height * k)
                .offset(x: r.minX * k, y: r.minY * k)
                .allowsHitTesting(false)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        if lying {
            view.shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.22), radius: h * 0.03, y: h * 0.018)
                .accessibilityHidden(true)
        } else {
            view
                .background(alignment: .bottom) {
                    Ellipse()
                        .fill(Color.black.opacity(scheme == .dark ? 0.75 : 0.3))
                        .frame(width: w * 1.1, height: h * 0.04)
                        .blur(radius: h * 0.02)
                        .offset(y: h * 0.015)
                }
                .accessibilityHidden(true)
        }
    }

    private func phoneBody(depth: CGFloat) -> some View {
        let width = height / 2.12
        let corner = width * style.cornerRatio
        let bezel = width * style.bezel
        let (light, dark) = style.frame
        return ZStack {
            // Gehäusekante (Tiefe des Telefons) – rechts hinter der Front sichtbar
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [dark, light, dark.opacity(0.9), Color.black], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.35), .white.opacity(0.0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .blendMode(.screen)
                )
                .offset(x: depth)
                .opacity(depth > 0 ? 1 : 0)
            // Seitentasten (auf der Kante)
            VStack(spacing: height * 0.02) {
                Capsule().frame(width: width * 0.03, height: height * 0.05)
                Capsule().frame(width: width * 0.03, height: height * 0.1)
            }
            .foregroundStyle(LinearGradient(colors: [light, dark], startPoint: .leading, endPoint: .trailing))
            .offset(x: width * 0.5 + depth * 0.95, y: -height * 0.14)
            .opacity(depth > 0 ? 1 : 0)
            // Rahmen (poliertes Metall mit Glanzlichtern)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(AngularGradient(colors: [light, dark, light.opacity(0.95), dark, light.opacity(0.8), dark, light],
                                      center: .center))
            RoundedRectangle(cornerRadius: corner * 0.92, style: .continuous)
                .fill(Color.black)
                .padding(width * 0.012)
            // Bildschirm
            screen()
                .frame(width: width - 2 * bezel, height: height - 2 * bezel)
                .clipShape(RoundedRectangle(cornerRadius: max(2, corner - bezel * 0.8), style: .continuous))
            // Kameraloch
            Circle()
                .fill(Color.black)
                .overlay(Circle().fill(RadialGradient(colors: [Color(hex: 0x1E3248), .black], center: .center, startRadius: 0, endRadius: width * 0.016)))
                .frame(width: width * (style == .pixel ? 0.05 : 0.04), height: width * (style == .pixel ? 0.05 : 0.04))
                .offset(y: -height / 2 + bezel + width * 0.045)
            // Tiefe: Bildschirm unter dem Glas
            RoundedRectangle(cornerRadius: max(2, corner - bezel * 0.8), style: .continuous)
                .strokeBorder(Color.black.opacity(0.4), lineWidth: width * 0.012)
                .blur(radius: width * 0.008)
                .frame(width: width - 2 * bezel, height: height - 2 * bezel)
                .clipShape(RoundedRectangle(cornerRadius: max(2, corner - bezel * 0.8), style: .continuous))
                .allowsHitTesting(false)
            // Glas: weiche Spiegelung des Studiolichts
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .white.opacity(0.06), location: 0.3),
                                             .init(color: .clear, location: 0.48), .init(color: .white.opacity(0.04), location: 0.8),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .white.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Bildschirminhalt: die App selbst

/// Was auf dem Mac-Bildschirm der Bühne zu sehen ist: Android Bridge mit den Fotos des Telefons.
struct MiniAppScreen: View {
    var photos: [NSImage] = []
    var connected: Bool
    var deviceName: String
    @Environment(\.colorScheme) private var scheme

    private let navItems: [(String, String)] = [
        ("square.grid.2x2.fill", "Übersicht"), ("folder", "Dateien"), ("photo.on.rectangle", "Fotos"),
        ("arrow.up.arrow.down.circle", "Übertragen"), ("star", "Favoriten"), ("clock", "Zuletzt"),
        ("doc.on.doc", "Duplikate"), ("gearshape", "Einstellungen"),
    ]

    var body: some View {
        let dark = scheme == .dark
        let bg = dark ? Color(hex: 0x0E0F12) : Color(hex: 0xF5F5F7)
        let fg = dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x1D1D1F)
        let card = dark ? Color(hex: 0x1C1C20) : Color.white
        VStack(spacing: 0) {
            // Menüleiste
            HStack(spacing: 18) {
                Text("Android Bridge").fontWeight(.bold)
                Text("Ablage")
                Text("Bearbeiten")
                Text("Darstellung")
                Text("Fenster")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
            }
            .font(.system(size: 13))
            .foregroundStyle(fg.opacity(0.9))
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(dark ? Color.black.opacity(0.5) : Color.white.opacity(0.7))
            ZStack(alignment: .top) {
                bg
                VStack(alignment: .leading, spacing: 18) {
                    nav(fg: fg, card: card)
                        .frame(maxWidth: .infinity)
                    if connected {
                        Text("Fotos & Videos").font(.system(size: 34, weight: .bold)).foregroundStyle(fg)
                        Text(deviceName).font(.system(size: 15)).foregroundStyle(fg.opacity(0.55)).padding(.top, -12)
                        grid
                    } else {
                        Spacer(minLength: 30)
                        VStack(spacing: 10) {
                            Text("Ihr Android.").font(.system(size: 46, weight: .bold)).foregroundStyle(fg)
                            Text("Direkt auf Ihrem Mac.").font(.system(size: 46, weight: .bold)).foregroundStyle(fg.opacity(0.45))
                            Text("Telefon per USB anschließen").font(.system(size: 16)).foregroundStyle(fg.opacity(0.5)).padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 14)
            }
        }
        .background(bg)
    }

    private func nav(fg: Color, card: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(navItems.indices, id: \.self) { i in
                let active = connected ? i == 2 : i == 0
                VStack(spacing: 3) {
                    Image(systemName: navItems[i].0).font(.system(size: 15))
                    Text(navItems[i].1).font(.system(size: 9.5, weight: .medium))
                }
                .foregroundStyle(active ? Color.accentColor : fg.opacity(0.75))
                .frame(width: 62, height: 42)
                .background(Capsule().fill(active ? Color.accentColor.opacity(0.14) : .clear))
            }
        }
        .padding(4)
        .background(Capsule().fill(card.opacity(0.92)).shadow(color: .black.opacity(0.12), radius: 8, y: 2))
    }

    private var grid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(0..<10, id: \.self) { i in
                Group {
                    if !photos.isEmpty {
                        Color.clear.overlay(Image(nsImage: photos[i % photos.count]).resizable().aspectRatio(contentMode: .fill))
                    } else {
                        Color.gray.opacity(0.18)
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - Bühne

/// Die Produktbühne der Übersicht: Mac (Perspektive) und Telefon davor.
struct ProductStage: View {
    var connected: Bool
    var photos: [NSImage] = []
    var deviceName: String = "Ihr Android-Telefon"
    var phoneStyle: PhoneStyle = .generic
    var stateSymbol: String?
    var stateText: String?
    var hardware: MacHardware = .current
    /// Zeitpunkt der Verbindung – startet die Auftrittsanimation (Telefon wird neben den Mac gelegt).
    var connectedAt: Date?
    /// Echtes Foto des angeschlossenen Telefons (falls vorhanden).
    var phonePhoto: PhonePhoto? = nil

    /// Seitenverhältnis der Bühne: mit Produktfoto so hoch wie das Foto, sonst breit (Mac + Telefon).
    static func aspect(for hardware: MacHardware = .current, connected: Bool) -> CGFloat {
        if let p = connected ? MacPhoto.front(for: hardware) : MacPhoto.side(for: hardware) {
            // verbunden: rechts neben dem Mac liegt das Telefon
            return p.pixelSize.width / p.pixelSize.height + (connected ? PhotoDeskStage.phoneArea(p) : 0)
        }
        return 2.05
    }
    static func maxWidth(for hardware: MacHardware = .current, connected: Bool) -> CGFloat {
        if connected, let p = MacPhoto.front(for: hardware) { return p.isTopDown ? 860 : 940 }
        if connected { return 940 }
        if let p = MacPhoto.side(for: hardware) { return p == .notchFront ? 820 : 720 }
        return 940
    }

    var body: some View {
        if connected, let photo = MacPhoto.front(for: hardware) {
            // Echtes Produktfoto von oben, daneben liegt das verbundene Telefon
            PhotoDeskStage(photo: photo, photos: photos, deviceName: deviceName, phoneStyle: phoneStyle,
                           phonePhoto: phonePhoto, stateSymbol: stateSymbol, stateText: stateText, connectedAt: connectedAt)
        } else if !connected, let photo = MacPhoto.side(for: hardware) {
            // Ohne Telefon: der Mac allein in der Seitenansicht, wie auf einer Produktseite
            PhotoLaptop(photo: photo) { MiniAppScreen(photos: photos, connected: connected, deviceName: deviceName) }
        } else {
            drawnStage
        }
    }

    private var drawnStage: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let phoneH = h * 0.66
            ZStack(alignment: .topLeading) {
                mac
                    .frame(width: w * 0.8, height: h)
                    .offset(x: w * 0.2)
                RealisticPhone(height: phoneH, style: phoneStyle, photo: phonePhoto) {
                    PhoneScreenContent(wallpaper: connected ? photos.first : nil, stateSymbol: stateSymbol, stateText: stateText, dimmed: !connected)
                }
                .position(x: w * 0.19, y: h - phoneH / 2 - h * 0.02)
            }
            .frame(width: w, height: h)
        }
    }

    @ViewBuilder private var mac: some View {
        let content = MiniAppScreen(photos: photos, connected: connected, deviceName: deviceName)
        if hardware.form.isLaptop {
            PerspectiveLaptop(hardware: hardware) { content }
        } else {
            GeometryReader { geo in
                MacRender(width: min(geo.size.width * 0.82, geo.size.height * 1.2), hardware: hardware) {
                    ScaledScreen { content }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
        }
    }
}

/// Zeigt einen Inhalt in seiner Gestaltungsgröße (960 × 600) verkleinert – für Bildschirme in der Vorderansicht.
struct ScaledScreen<Content: View>: View {
    var design = CGSize(width: 960, height: 600)
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { g in
            // Höhe bleibt fest, die Breite folgt dem Seitenverhältnis des Bildschirms –
            // so füllt die App auch 16:9-Displays (iMac, Studio Display) ohne schwarzen Rand.
            let scale = g.size.height > 0 ? g.size.height / design.height : 1
            let width = scale > 0 ? max(design.width * 0.8, g.size.width / scale) : design.width
            content()
                .frame(width: width, height: design.height)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .clipped()
    }
}

// MARK: - Produktfotos (5.2)

/// Echte Produktfotos aus dem App-Bundle (Resources/Photos). Für Modelle ohne Foto bleibt die gezeichnete Ansicht.
enum MacPhoto: String {
    /// MacBook Pro mit Touch Bar, von oben – Bildschirm wird durch die laufende App ersetzt.
    case touchBarFront = "macbook-pro-touchbar-front"
    /// MacBook Pro mit Touch Bar, Seitenansicht (Titelbild ohne Telefon).
    case touchBarSide = "macbook-pro-touchbar-side"
    /// MacBook Pro mit Kerbe (ab 2021, 14"/16"), Silber, frontal.
    case notchFront = "macbook-pro-notch-front"

    /// Pixelgröße des Fotos.
    var pixelSize: CGSize {
        switch self {
        case .touchBarFront: return CGSize(width: 965, height: 895)
        case .touchBarSide: return CGSize(width: 923, height: 768)
        case .notchFront: return CGSize(width: 1100, height: 667)
        }
    }

    /// Von oben fotografiert (Telefon liegt daneben) oder frontal (Telefon steht daneben).
    var isTopDown: Bool { self == .touchBarFront }

    /// Gestaltungsgröße des Bildschirminhalts – passend zum Seitenverhältnis des Displays im Foto.
    var screenDesign: CGSize {
        switch self {
        case .notchFront: return CGSize(width: 920, height: 600)
        default: return CGSize(width: 960, height: 600)
        }
    }

    /// Rundung der Displayecken im Foto (Pixel).
    var screenCorner: CGFloat { self == .notchFront ? 10 : 0 }

    /// Kerbe (Kamera) oben im Display, in Pixeln des Fotos.
    var notch: CGRect? {
        switch self {
        case .notchFront: return CGRect(x: 511, y: 11, width: 78, height: 21)
        default: return nil
        }
    }

    /// Bildschirmfläche im Foto (oben links, oben rechts, unten rechts, unten links) in Pixeln – etwas
    /// größer als gemessen, damit kein Rest des Originalbildschirms durchscheint.
    var screenQuad: [CGPoint]? {
        switch self {
        case .touchBarFront:
            return [CGPoint(x: 24.5, y: 26.5), CGPoint(x: 939.5, y: 26.5), CGPoint(x: 873.5, y: 305.5), CGPoint(x: 90.5, y: 305.5)]
        case .touchBarSide:
            return nil
        case .notchFront:
            return [CGPoint(x: 93.5, y: 11.5), CGPoint(x: 1006.5, y: 11.5), CGPoint(x: 1006.5, y: 607.5), CGPoint(x: 93.5, y: 607.5)]
        }
    }

    var image: NSImage? { MacPhoto.cache(self) }

    private static var store: [MacPhoto: NSImage] = [:]
    private static func cache(_ p: MacPhoto) -> NSImage? {
        if let i = store[p] { return i }
        guard let url = Bundle.main.url(forResource: p.rawValue, withExtension: "png", subdirectory: "Photos")
                ?? Bundle.main.url(forResource: p.rawValue, withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        store[p] = img
        return img
    }

    /// Passendes Foto für diesen Mac (nur Modelle, für die es ein echtes Foto gibt).
    static func front(for hw: MacHardware) -> MacPhoto? {
        if hw.form == .notchPro, MacPhoto.notchFront.image != nil { return .notchFront }
        guard hw.form.isLaptop, LaptopDims.of(hw).touchBar, MacPhoto.touchBarFront.image != nil else { return nil }
        return .touchBarFront
    }
    static func side(for hw: MacHardware) -> MacPhoto? {
        if hw.form == .notchPro, MacPhoto.notchFront.image != nil { return .notchFront }
        guard hw.form.isLaptop, LaptopDims.of(hw).touchBar, MacPhoto.touchBarSide.image != nil else { return nil }
        return .touchBarSide
    }
}

/// Produktfoto mit der laufenden App auf dem Bildschirm (perspektivisch eingepasst).
struct PhotoLaptop<Screen: View>: View {
    let photo: MacPhoto
    @ViewBuilder var screen: () -> Screen
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let px = photo.pixelSize
            let s = min(geo.size.width / px.width, geo.size.height / px.height)
            let w = px.width * s, h = px.height * s
            let screenSize = photo.screenDesign
            ZStack(alignment: .topLeading) {
                if let img = photo.image {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: w, height: h)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.16), radius: max(6, h * 0.035), y: h * 0.025)
                }
                if let q = photo.screenQuad?.map({ CGPoint(x: $0.x * s, y: $0.y * s) }) {
                    screen()
                        .frame(width: screenSize.width, height: screenSize.height)
                        .clipped()
                        .projectionEffect(homography(width: screenSize.width, height: screenSize.height,
                                                     tl: q[0], tr: q[1], br: q[2], bl: q[3]))
                        .mask(ScreenMask(points: q, corner: photo.screenCorner * s))
                    if let n = photo.notch {
                        // Kerbe mit Kamera, wie beim echten Gerät
                        PhotoNotchShape(radius: n.height * 0.38 * s)
                            .fill(Color.black)
                            .overlay(Circle().fill(Color(white: 0.16)).frame(width: n.height * 0.3 * s, height: n.height * 0.3 * s))
                            .frame(width: n.width * s, height: n.height * s)
                            .offset(x: n.minX * s, y: n.minY * s)
                    }
                    // Glas über dem Bildschirm: weiche Spiegelung wie im Foto
                    Polygon(points: q)
                        .fill(LinearGradient(stops: [.init(color: .white.opacity(0.10), location: 0),
                                                     .init(color: .white.opacity(0.03), location: 0.35),
                                                     .init(color: .clear, location: 0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .allowsHitTesting(false)
                }
            }
            // oben links verankern: der Bildschirminhalt ist größer als das Foto gelayoutet
            // (danach perspektivisch verkleinert) und darf das Foto nicht verschieben
            .frame(width: w, height: h, alignment: .topLeading)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}


/// Verbunden mit Produktfoto: Mac von oben, das Telefon liegt rechts daneben auf dem Tisch.
/// Beim Verbinden wird das Telefon hereingelegt, der Mac-Bildschirm geht an, ein Lichtimpuls läuft vom Telefon aus.
struct PhotoDeskStage: View {
    /// Zusätzliche Breite (in Höhen der Bühne) für das Telefon.
    static func phoneArea(_ photo: MacPhoto) -> CGFloat { photo.isTopDown ? 0.3 : 0.24 }

    let photo: MacPhoto
    var photos: [NSImage]
    var deviceName: String
    var phoneStyle: PhoneStyle
    var phonePhoto: PhonePhoto? = nil
    var stateSymbol: String?
    var stateText: String?
    var connectedAt: Date?
    @Environment(\.animationsEnabled) private var animations
    @State private var placed = true
    @State private var screenOn = true
    @State private var pulse: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let lw = H * photo.pixelSize.width / photo.pixelSize.height
            let topDown = photo.isTopDown
            let phoneH = H * (topDown ? 0.5 : 0.6)
            let phoneW = phoneH / 2.12
            // von oben: Telefon liegt rechts neben der Handballenauflage, leicht schräg;
            // frontal: Telefon steht rechts vorne, leicht vor dem Mac
            let cx = min(geo.size.width - phoneW * 0.55, lw + phoneW * (topDown ? 0.32 : 0.1))
            let cy = topDown ? H * 0.68 : H - phoneH / 2 - H * 0.01
            let finalAngle: Double = topDown ? -8 : 0
            let glow = phoneH * 1.8
            ZStack(alignment: .topLeading) {
                PhotoLaptop(photo: photo) {
                    MiniAppScreen(photos: photos, connected: true, deviceName: deviceName)
                        .overlay(Color.black.opacity(screenOn ? 0 : 0.92))
                }
                .frame(width: lw, height: H)
                // Lichtimpuls vom Telefon aus
                Circle()
                    .fill(RadialGradient(colors: [Palette.accent.opacity(0.35), Palette.accent.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: glow / 2))
                    .frame(width: glow, height: glow)
                    .scaleEffect(0.3 + pulse * 1.1)
                    .opacity(Double(1 - pulse))
                    .offset(x: cx - glow / 2, y: cy - glow / 2)
                    .allowsHitTesting(false)
                RealisticPhone(height: phoneH, style: phoneStyle, lying: topDown, photo: phonePhoto) {
                    PhoneScreenContent(wallpaper: photos.first, stateSymbol: stateSymbol, stateText: stateText, dimmed: false)
                }
                .frame(width: phoneW, height: phoneH)
                .rotationEffect(.degrees(placed ? finalAngle : finalAngle + 22))
                .scaleEffect(placed ? 1 : 1.08)
                .opacity(placed ? 1 : 0)
                .offset(x: cx - phoneW / 2 + (placed ? 0 : phoneW * 1.6), y: cy - phoneH / 2 + (placed ? 0 : -H * 0.06))
            }
            .frame(width: geo.size.width, height: H, alignment: .topLeading)
        }
        .onAppear {
            if let t = connectedAt, Date().timeIntervalSince(t) < 10 { play() }
        }
        .onChange(of: connectedAt) { _ in play() }
    }

    private func play() {
        guard MotionPolicy.allowed(animations) else { return }
        // Ausgangslage ohne Animation setzen, im nächsten Durchlauf weich in die Endlage
        placed = false
        screenOn = false
        pulse = 0
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.78)) { placed = true }
            withAnimation(.easeInOut(duration: 0.7).delay(0.4)) { screenOn = true }
            withAnimation(.easeOut(duration: 1.3).delay(0.5)) { pulse = 1 }
        }
    }
}


/// Displayfläche im Foto: Viereck, bei rechteckigen Displays mit gerundeten Ecken.
private struct ScreenMask: Shape {
    var points: [CGPoint]
    var corner: CGFloat
    func path(in rect: CGRect) -> Path {
        guard points.count == 4 else { return Path() }
        if corner > 0 {
            let r = CGRect(x: points[0].x, y: points[0].y, width: points[1].x - points[0].x, height: points[3].y - points[0].y)
            return Path(roundedRect: r, cornerRadius: corner, style: .continuous)
        }
        var p = Path()
        p.move(to: points[0]); points.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
        return p
    }
}

/// Kerbe oben im Display: oben gerade, unten gerundet.
private struct PhotoNotchShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Echte Produktfotos von Telefonen (Vorderseite). Der Bildschirm wird durch Inhalte vom Gerät ersetzt.
enum PhonePhoto: String {
    case pixel6Pro = "phone-pixel-6-pro"
    case xiaomi11Lite = "phone-xiaomi-11-lite"

    var pixelSize: CGSize {
        switch self {
        case .pixel6Pro: return CGSize(width: 467, height: 997)
        case .xiaomi11Lite: return CGSize(width: 233, height: 490)
        }
    }
    /// Displayfläche im Foto (Pixel).
    var screen: CGRect {
        switch self {
        case .pixel6Pro: return CGRect(x: 10, y: 11, width: 443, height: 973)
        case .xiaomi11Lite: return CGRect(x: 9, y: 8, width: 213, height: 468)
        }
    }
    var screenCorner: CGFloat {
        switch self {
        case .pixel6Pro: return 34
        case .xiaomi11Lite: return 18
        }
    }
    /// Kameraloch (Mittelpunkt, Radius) in Pixeln.
    var punch: CGPoint {
        switch self {
        case .pixel6Pro: return CGPoint(x: 232, y: 22)
        case .xiaomi11Lite: return CGPoint(x: 29, y: 26)
        }
    }
    var punchRadius: CGFloat {
        switch self {
        case .pixel6Pro: return 6
        case .xiaomi11Lite: return 5
        }
    }

    var image: NSImage? { PhonePhoto.cache(self) }
    private static var store: [PhonePhoto: NSImage] = [:]
    private static func cache(_ p: PhonePhoto) -> NSImage? {
        if let i = store[p] { return i }
        guard let url = Bundle.main.url(forResource: p.rawValue, withExtension: "png", subdirectory: "Photos")
                ?? Bundle.main.url(forResource: p.rawValue, withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        store[p] = img
        return img
    }

    /// Passendes Foto für das angeschlossene Telefon (nur Modelle, für die es ein Foto gibt).
    static func match(manufacturer: String, model: String) -> PhonePhoto? {
        let m = (manufacturer + " " + model).lowercased()
        if m.contains("pixel 6 pro") { return .pixel6Pro }
        if m.contains("11 lite"), m.contains("xiaomi") || m.contains("mi 11") { return .xiaomi11Lite }
        return nil
    }
}
