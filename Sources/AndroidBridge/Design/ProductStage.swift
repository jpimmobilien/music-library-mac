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
        return Polygon(points: pts)
            .fill(Color.black.opacity(scheme == .dark ? 0.75 : 0.32))
            .blur(radius: max(6, b.height * 0.09))
            .offset(y: b.height * 0.05)
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
            // Spiegelung auf dem Glas
            Polygon(points: glass)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.10), location: 0), .init(color: .white.opacity(0.02), location: 0.45),
                                             .init(color: .clear, location: 0.46)],
                                     startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1)))
                .allowsHitTesting(false)
            Polygon(points: face).stroke(Color.white.opacity(0.35), lineWidth: 0.6)
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
            ForEach(layers.indices, id: \.self) { i in
                Polygon(points: layers[i]).fill(dark.opacity(0.92))
            }
            Polygon(points: layers[0]).fill(Color.black.opacity(0.18))
            Polygon(points: top)
                .fill(LinearGradient(colors: [light.opacity(0.92), light, dark.opacity(0.75)],
                                     startPoint: UnitPoint(x: 0.5, y: 0), endPoint: UnitPoint(x: 0.5, y: 1)))
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
    @ViewBuilder var screen: () -> Screen
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let width = height / 2.12
        let corner = width * style.cornerRatio
        let bezel = width * style.bezel
        let (light, dark) = style.frame
        ZStack {
            // Seitentasten (rechts)
            VStack(spacing: height * 0.02) {
                Capsule().frame(width: width * 0.022, height: height * 0.05)
                Capsule().frame(width: width * 0.022, height: height * 0.1)
            }
            .foregroundStyle(LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom))
            .offset(x: width * 0.505, y: -height * 0.14)
            // Rahmen
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [light, dark, light.opacity(0.9), dark], startPoint: .topLeading, endPoint: .bottomTrailing))
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
            // Glas
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0.03), location: 0.42),
                                             .init(color: .clear, location: 0.43)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .white.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .background(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(scheme == .dark ? 0.8 : 0.35))
                .frame(width: width * 1.1, height: height * 0.05)
                .blur(radius: height * 0.025)
                .offset(y: height * 0.02)
        }
        .accessibilityHidden(true)
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

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let phoneH = h * 0.74
            ZStack(alignment: .topLeading) {
                mac
                    .frame(width: w * 0.8, height: h)
                    .offset(x: w * 0.2)
                RealisticPhone(height: phoneH, style: phoneStyle) {
                    PhoneScreenContent(wallpaper: connected ? photos.first : nil, stateSymbol: stateSymbol, stateText: stateText, dimmed: !connected)
                }
                .position(x: w * 0.17, y: h - phoneH / 2 - h * 0.015)
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
