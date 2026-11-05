import Foundation

/// Ein Zeichenbefehl mit absoluten Koordinaten (Ergebnis von `SVGPath.parse`).
public enum PathCommand: Equatable, Sendable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

/// Parser für SVG-/Android-`pathData` (M, L, H, V, C, S, Q, T, A, Z – absolut und relativ).
///
/// Die Android-App zeichnet alle Symbole als Vektorpfade (Material Symbols Rounded und eigene Zeichnungen);
/// die Mac-App übernimmt genau diese Pfade, damit die Symbolsprache identisch bleibt.
/// Bögen (A) werden in kubische Bézierkurven umgerechnet.
public enum SVGPath {
    public static func parse(_ data: String) -> [PathCommand] {
        var tokens = Tokenizer(Array(data.utf8))
        var result: [PathCommand] = []
        var cx = 0.0, cy = 0.0          // aktueller Punkt
        var sx = 0.0, sy = 0.0          // Startpunkt des Teilpfads
        var lastCtrlX = 0.0, lastCtrlY = 0.0
        var lastKind: UInt8 = 0          // letzter Befehl (für S/T-Spiegelung)
        var command: UInt8 = 0

        while let next = tokens.peekCommand() ?? (command != 0 ? command : nil) {
            if tokens.peekCommand() != nil { tokens.advanceCommand() }
            command = next
            let rel = command >= 97 // Kleinbuchstabe
            let upper = rel ? command - 32 : command
            switch upper {
            case UInt8(ascii: "M"):
                guard let x = tokens.number(), let y = tokens.number() else { return result }
                cx = rel ? cx + x : x
                cy = rel ? cy + y : y
                sx = cx; sy = cy
                result.append(.move(x: cx, y: cy))
                // weitere Koordinatenpaare nach M gelten als L
                command = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")
                lastKind = upper
            case UInt8(ascii: "L"):
                guard let x = tokens.number(), let y = tokens.number() else { return result }
                cx = rel ? cx + x : x
                cy = rel ? cy + y : y
                result.append(.line(x: cx, y: cy))
                lastKind = upper
            case UInt8(ascii: "H"):
                guard let x = tokens.number() else { return result }
                cx = rel ? cx + x : x
                result.append(.line(x: cx, y: cy))
                lastKind = upper
            case UInt8(ascii: "V"):
                guard let y = tokens.number() else { return result }
                cy = rel ? cy + y : y
                result.append(.line(x: cx, y: cy))
                lastKind = upper
            case UInt8(ascii: "C"):
                guard let x1 = tokens.number(), let y1 = tokens.number(), let x2 = tokens.number(),
                      let y2 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return result }
                let c1x = rel ? cx + x1 : x1, c1y = rel ? cy + y1 : y1
                let c2x = rel ? cx + x2 : x2, c2y = rel ? cy + y2 : y2
                cx = rel ? cx + x : x
                cy = rel ? cy + y : y
                result.append(.cubic(c1x: c1x, c1y: c1y, c2x: c2x, c2y: c2y, x: cx, y: cy))
                lastCtrlX = c2x; lastCtrlY = c2y
                lastKind = upper
            case UInt8(ascii: "S"):
                guard let x2 = tokens.number(), let y2 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return result }
                let reflect = lastKind == UInt8(ascii: "C") || lastKind == UInt8(ascii: "S")
                let c1x = reflect ? 2 * cx - lastCtrlX : cx
                let c1y = reflect ? 2 * cy - lastCtrlY : cy
                let c2x = rel ? cx + x2 : x2, c2y = rel ? cy + y2 : y2
                cx = rel ? cx + x : x
                cy = rel ? cy + y : y
                result.append(.cubic(c1x: c1x, c1y: c1y, c2x: c2x, c2y: c2y, x: cx, y: cy))
                lastCtrlX = c2x; lastCtrlY = c2y
                lastKind = upper
            case UInt8(ascii: "Q"):
                guard let x1 = tokens.number(), let y1 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return result }
                let qx = rel ? cx + x1 : x1, qy = rel ? cy + y1 : y1
                cx = rel ? cx + x : x
                cy = rel ? cy + y : y
                result.append(.quad(cx: qx, cy: qy, x: cx, y: cy))
                lastCtrlX = qx; lastCtrlY = qy
                lastKind = upper
            case UInt8(ascii: "T"):
                guard let x = tokens.number(), let y = tokens.number() else { return result }
                let reflect = lastKind == UInt8(ascii: "Q") || lastKind == UInt8(ascii: "T")
                let qx = reflect ? 2 * cx - lastCtrlX : cx
                let qy = reflect ? 2 * cy - lastCtrlY : cy
                cx = rel ? cx + x : x
                cy = rel ? cy + y : y
                result.append(.quad(cx: qx, cy: qy, x: cx, y: cy))
                lastCtrlX = qx; lastCtrlY = qy
                lastKind = upper
            case UInt8(ascii: "A"):
                guard let rx = tokens.number(), let ry = tokens.number(), let rot = tokens.number(),
                      let large = tokens.flag(), let sweep = tokens.flag(),
                      let x = tokens.number(), let y = tokens.number() else { return result }
                let ex = rel ? cx + x : x
                let ey = rel ? cy + y : y
                result.append(contentsOf: arcToCubics(x0: cx, y0: cy, rx: rx, ry: ry, angle: rot, largeArc: large, sweep: sweep, x: ex, y: ey))
                cx = ex; cy = ey
                lastKind = upper
            case UInt8(ascii: "Z"):
                result.append(.close)
                cx = sx; cy = sy
                lastKind = upper
                command = 0
            default:
                return result
            }
        }
        return result
    }

    /// Bogen (SVG-Endpunktdarstellung) als Folge kubischer Kurven (je höchstens 90°).
    static func arcToCubics(x0: Double, y0: Double, rx rx0: Double, ry ry0: Double, angle: Double, largeArc: Bool, sweep: Bool, x: Double, y: Double) -> [PathCommand] {
        if x0 == x && y0 == y { return [] }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { return [.line(x: x, y: y)] }
        let phi = angle * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (x0 - x) / 2, dy = (y0 - y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : (max(0, num) / den).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let centerX = cosPhi * cxp - sinPhi * cyp + (x0 + x) / 2
        let centerY = sinPhi * cxp + cosPhi * cyp + (y0 + y) / 2

        func angleBetween(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angleBetween(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angleBetween((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-9)))
        let step = delta / Double(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        var result: [PathCommand] = []
        var a = theta1
        for i in 0..<segments {
            let cosA = cos(a), sinA = sin(a)
            let b = a + step
            let cosB = cos(b), sinB = sin(b)
            // Punkte auf dem Einheitskreis, skaliert, gedreht, verschoben
            func map(_ px: Double, _ py: Double) -> (Double, Double) {
                let sx = px * rx, sy = py * ry
                return (cosPhi * sx - sinPhi * sy + centerX, sinPhi * sx + cosPhi * sy + centerY)
            }
            let c1 = map(cosA - t * sinA, sinA + t * cosA)
            let c2 = map(cosB + t * sinB, sinB - t * cosB)
            let end = i == segments - 1 ? (x, y) : map(cosB, sinB)
            result.append(.cubic(c1x: c1.0, c1y: c1.1, c2x: c2.0, c2y: c2.1, x: end.0, y: end.1))
            a = b
        }
        return result
    }
}

/// Zerlegt `pathData` in Befehle und Zahlen (Zahlen dürfen ohne Trennzeichen aufeinander folgen, z. B. „1.5.5“ oder „2-3“).
private struct Tokenizer {
    let bytes: [UInt8]
    var i = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    private static func isSeparator(_ c: UInt8) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 || c == 44 }

    private mutating func skipSeparators() {
        while i < bytes.count && Tokenizer.isSeparator(bytes[i]) { i += 1 }
    }

    mutating func peekCommand() -> UInt8? {
        skipSeparators()
        guard i < bytes.count else { return nil }
        let c = bytes[i]
        // Buchstaben außer e/E (Exponent) sind Befehle
        if (c >= 65 && c <= 90) || (c >= 97 && c <= 122), c != 101, c != 69 { return c }
        return nil
    }

    mutating func advanceCommand() { i += 1 }

    /// Bogen-Flag: einzelne Ziffer 0/1 (darf direkt an die nächste Zahl grenzen).
    mutating func flag() -> Bool? {
        skipSeparators()
        guard i < bytes.count else { return nil }
        let c = bytes[i]
        if c == 48 || c == 49 {
            i += 1
            return c == 49
        }
        return nil
    }

    mutating func number() -> Double? {
        skipSeparators()
        guard i < bytes.count else { return nil }
        let start = i
        if bytes[i] == 43 || bytes[i] == 45 { i += 1 } // +/-
        var sawDigit = false
        var sawDot = false
        while i < bytes.count {
            let c = bytes[i]
            if c >= 48 && c <= 57 {
                sawDigit = true
                i += 1
            } else if c == 46 && !sawDot { // .
                sawDot = true
                i += 1
            } else {
                break
            }
        }
        if i < bytes.count && (bytes[i] == 101 || bytes[i] == 69) && sawDigit { // Exponent
            var j = i + 1
            if j < bytes.count && (bytes[j] == 43 || bytes[j] == 45) { j += 1 }
            if j < bytes.count && bytes[j] >= 48 && bytes[j] <= 57 {
                i = j
                while i < bytes.count && bytes[i] >= 48 && bytes[i] <= 57 { i += 1 }
            }
        }
        guard sawDigit, let s = String(bytes: bytes[start..<i], encoding: .ascii) else {
            i = start
            return nil
        }
        return Double(s)
    }
}
