import Foundation

/// Erkennt schwarze Balken in Vorschaubildern (Android liefert über MTP oft 160×120-Bilder mit
/// Balken bei Hochformat-Fotos). Nur symmetrische, gleichmäßig schwarze Ränder gelten als Balken –
/// dunkle Bildinhalte (Nachthimmel) werden so nicht abgeschnitten.
public enum Letterbox {
    public struct Rect: Equatable, Sendable {
        public var x: Int, y: Int, width: Int, height: Int
        public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
    }

    /// Inhaltsbereich eines Graustufenbilds (Zeilen von oben). `nil` = nichts abzuschneiden.
    public static func contentRect(gray: [UInt8], width: Int, height: Int, threshold: UInt8 = 22) -> Rect? {
        guard width > 4, height > 4, gray.count >= width * height else { return nil }
        func rowIsBar(_ y: Int) -> Bool {
            let base = y * width
            for x in 0..<width where gray[base + x] > threshold { return false }
            return true
        }
        func colIsBar(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            for y in y0..<y1 where gray[y * width + x] > threshold { return false }
            return true
        }
        var top = 0
        while top < height && rowIsBar(top) { top += 1 }
        if top == height { return nil } // ganz dunkles Bild
        var bottom = 0
        while bottom < height - top && rowIsBar(height - 1 - bottom) { bottom += 1 }
        var cropV = symmetric(top, bottom)
        if !cropV { top = 0; bottom = 0 }
        let y0 = top, y1 = height - bottom
        var left = 0
        while left < width && colIsBar(left, y0, y1) { left += 1 }
        var right = 0
        while right < width - left && colIsBar(width - 1 - right, y0, y1) { right += 1 }
        let cropH = symmetric(left, right)
        if !cropH { left = 0; right = 0 }
        let w = width - left - right, h = height - top - bottom
        // Nie mehr als 70 % abschneiden.
        if w < width * 3 / 10 || h < height * 3 / 10 { return nil }
        cropV = cropV && (top + bottom) > 0
        guard cropV || (cropH && (left + right) > 0) else { return nil }
        return Rect(x: left, y: top, width: w, height: h)
    }

    private static func symmetric(_ a: Int, _ b: Int) -> Bool {
        guard a >= 2, b >= 2 else { return false }
        return abs(a - b) <= max(2, max(a, b) * 15 / 100)
    }
}
