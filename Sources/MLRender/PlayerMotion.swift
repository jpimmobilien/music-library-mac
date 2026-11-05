import Foundation

// Bewegungslogik der Player-Designs – in der Android-App Teil der Compose-Oberfläche (Turntable.kt,
// Cassette.kt, Visualizer.kt), hier als reine, testbare Rechnung. Die Oberfläche ruft je Bild
// `step(dt)` bzw. die Funktionen mit der vergangenen Zeit auf (dt in Sekunden, wie im Original auf
// höchstens 0,1 s begrenzt) und zeichnet mit den Ergebnissen. Formeln und Zeiten: docs/PLAYER_SPEC.md.

// ---------------------------------------------------------------------------------------------
// Easing und Feder wie in Jetpack Compose
// ---------------------------------------------------------------------------------------------

/** Kubische Bézier-Kurve (0,0)–(x1,y1)–(x2,y2)–(1,1) wie `CubicBezierEasing` in Compose. */
public struct CubicBezierEasing: Sendable {
    public let x1: Float, y1: Float, x2: Float, y2: Float

    public init(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    /** Compose-Standard für `tween()`: `FastOutSlowInEasing` = (0.4, 0, 0.2, 1). */
    public static let fastOutSlowIn = CubicBezierEasing(0.4, 0, 0.2, 1)

    @inline(__always)
    private func bez(_ t: Float, _ p1: Float, _ p2: Float) -> Float {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    /** y zu einem Zeitanteil x (0…1). */
    public func transform(_ x: Float) -> Float {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo: Float = 0, hi: Float = 1
        var t = x
        for _ in 0..<40 {
            let v = bez(t, x1, x2)
            if abs(v - x) < 1e-6 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(t, y1, y2)
    }
}

/** Zeitbasierte Animation von [from] nach [to] (wie `tween(durationMillis, easing)` in Compose). */
public struct TweenAnimation: Sendable {
    public let from: Float
    public let to: Float
    public let duration: Float
    public let easing: CubicBezierEasing?
    public private(set) var elapsed: Float = 0

    /** [easing] = nil → linear (`LinearEasing`). */
    public init(from: Float, to: Float, duration: Float, easing: CubicBezierEasing? = .fastOutSlowIn) {
        self.from = from; self.to = to; self.duration = duration; self.easing = easing
    }

    public var isFinished: Bool { elapsed >= duration }

    public var value: Float {
        if duration <= 0 || elapsed >= duration { return to }
        let f = elapsed / duration
        let e = easing?.transform(f) ?? f
        return from + (to - from) * e
    }

    public mutating func step(_ dt: Float) { elapsed = Swift.min(duration, elapsed + Swift.max(0, dt)) }
}

/**
 * Feder ohne Anfangsgeschwindigkeit (wie `spring(stiffness, dampingRatio)` in Compose, Masse 1). Endet
 * nach der Dauer, die Compose schätzt (Auslenkung unter der Sichtbarkeitsschwelle 0,01), und springt
 * dann genau auf das Ziel.
 */
public struct SpringAnimation: Sendable {
    public let from: Float
    public let to: Float
    public let stiffness: Float
    public let dampingRatio: Float
    public private(set) var elapsed: Float = 0
    public let duration: Float

    public init(from: Float, to: Float, stiffness: Float, dampingRatio: Float, visibilityThreshold: Float = 0.01) {
        self.from = from; self.to = to; self.stiffness = stiffness; self.dampingRatio = dampingRatio
        let p0 = Double(abs(from - to))
        if p0 == 0 {
            duration = 0
        } else {
            let w0 = Double(stiffness).squareRoot(), z = Double(dampingRatio)
            if z < 1 {
                let r = -z * w0, wd = w0 * (1 - z * z).squareRoot()
                let c2 = (0 - r * p0) / wd
                let c = (p0 * p0 + c2 * c2).squareRoot()
                duration = Float(Swift.max(0, log(Double(visibilityThreshold) / c) / r))
            } else {
                // kritisch/überdämpft: einfache Schätzung über die langsamere Abklingrate
                let r = -w0 * (z - (z * z - 1).squareRoot())
                duration = Float(Swift.max(0, log(Double(visibilityThreshold) / (p0 * 2)) / r))
            }
        }
    }

    public var isFinished: Bool { elapsed >= duration }

    public var value: Float {
        if elapsed >= duration { return to }
        let t = Double(elapsed)
        let x0 = Double(from - to)
        let w0 = Double(stiffness).squareRoot(), z = Double(dampingRatio)
        let x: Double
        if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            x = exp(-z * w0 * t) * (x0 * cos(wd * t) + (z * w0 * x0) / wd * sin(wd * t))
        } else if z == 1 {
            x = exp(-w0 * t) * (x0 + w0 * x0 * t)
        } else {
            let s = (z * z - 1).squareRoot()
            let r1 = -w0 * (z - s), r2 = -w0 * (z + s)
            let c2 = (r1 * x0) / (r1 - r2), c1 = x0 - c2
            x = c1 * exp(r1 * t) + c2 * exp(r2 * t)
        }
        return to + Float(x)
    }

    public mutating func step(_ dt: Float) { elapsed = Swift.min(duration, elapsed + Swift.max(0, dt)) }
}

// ---------------------------------------------------------------------------------------------
// Plattenteller
// ---------------------------------------------------------------------------------------------

/**
 * Drehung von Platte und Label (Turntable.kt): 33⅓ U/min = 200°/s · Tempo; Anlaufen τ = 0,18 s
 * (≈ 0,5 s), Auslaufen τ = 0,28 s (≈ 0,8 s). Gedreht wird im Uhrzeigersinn (Winkel wächst).
 */
public struct TurntableSpin: Sendable {
    public static let DEGREES_PER_SECOND_33: Float = 200
    public static let TAU_UP: Float = 0.18
    public static let TAU_DOWN: Float = 0.28

    /** Drehwinkel 0…360 (Grad, im Uhrzeigersinn) und Winkelgeschwindigkeit (°/s). */
    public private(set) var angle: Float = 0
    public private(set) var velocity: Float = 0

    public init() {}

    /** Ziel: 200°/s · [speed] bei Wiedergabe (ohne Begrenzung, wie im Original), sonst 0. */
    public static func targetSpeed(playing: Bool, speed: Float) -> Float { playing ? DEGREES_PER_SECOND_33 * speed : 0 }

    /** Ein Bild weiter. Gibt `false` zurück, sobald Ziel und Geschwindigkeit 0 sind (Schleife darf enden). */
    @discardableResult
    public mutating func step(target: Float, dt rawDt: Float) -> Bool {
        let dt = Swift.min(rawDt, 0.1)
        let tau = target > velocity ? Self.TAU_UP : Self.TAU_DOWN
        velocity += (target - velocity) * (1 - kexp(-dt / tau))
        if abs(target - velocity) < 0.5 { velocity = target }
        angle = (angle + velocity * dt).truncatingRemainder(dividingBy: 360)
        return !(target == 0 && velocity == 0)
    }

    /** Sofort anhalten (Ansicht unsichtbar, statische Vorschau) – der Winkel bleibt. */
    public mutating func stop() { velocity = 0 }
}

/**
 * Tonarm (Turntable.kt): Fortschritt −1 (Ruhestellung) … 0 (Einlauf) … 1 (Auslauf) und Anheben.
 *
 *  - Ziel = `hasMedia ? clamp(position / dauer, 0, 1) : −1`; neue Ziele werden der Reihe nach
 *    abgearbeitet, wobei während einer laufenden Bewegung nur das jeweils neueste wartet.
 *  - Abstand > 0,03 (Titelwechsel, Spulen): Arm hebt sich (`jumpLift` → 1 in 160 ms), schwenkt per Feder
 *    (Steifigkeit 110, Dämpfung 0,92) und senkt sich danach (`jumpLift` → 0 in 260 ms).
 *  - sonst: lineares Nachführen in 260 ms.
 *  - Pause hebt den Arm (`pauseLift` → 1 in 480 ms), Wiedergabe senkt ihn (→ 0).
 *  - `lift = max(pauseLift, jumpLift)` steuert Schatten und Größe (siehe [TonearmPose]).
 */
public final class TonearmMotion {
    public static let JUMP_THRESHOLD: Float = 0.03

    public private(set) var progress: Float
    public private(set) var pauseLift: Float
    public private(set) var jumpLift: Float = 0

    private var pauseTween: TweenAnimation?
    private var pauseTarget: Float
    private var pending: Float?

    private enum Phase {
        case idle
        case follow(TweenAnimation)
        case jump(SpringAnimation, TweenAnimation)
        case lower(TweenAnimation)
    }
    private var phase: Phase = .idle

    /** Startzustand ohne Animation (wie beim ersten Anzeigen). */
    public init(target: Float, playing: Bool) {
        progress = target
        pauseTarget = playing ? 0 : 1
        pauseLift = pauseTarget
        pending = target
    }

    /** Gemeinsames Anheben: steuert Schattenabstand, Schattendeckkraft und Größe. */
    public var lift: Float { Swift.max(pauseLift, jumpLift) }

    /** Drehwinkel des Arm-Bildes in Grad (siehe `TurntableGeometry.armAngleForProgress`). */
    public var angleDegrees: Float { TurntableGeometry.armAngleForProgress(progress) }

    /** Läuft noch eine Bewegung (sonst darf die Bildschleife pausieren)? */
    public var isAnimating: Bool {
        if pending != nil || pauseTween != nil { return true }
        if case .idle = phase { return false }
        return true
    }

    /** Neues Ziel (−1…1); wartet, bis die laufende Bewegung fertig ist (nur das neueste zählt). */
    public func setTarget(_ target: Float) { pending = target }

    /** Wiedergabe-Zustand (hebt/senkt den Arm mit 480 ms). */
    public func setPlaying(_ playing: Bool) {
        let t: Float = playing ? 0 : 1
        if t == pauseTarget { return }
        pauseTarget = t
        pauseTween = TweenAnimation(from: pauseLift, to: t, duration: 0.48)
    }

    /** Statische Vorschau: sofort auf das Ziel, ohne Bewegung. */
    public func snap(to target: Float, playing: Bool) {
        progress = target; pending = nil; phase = .idle
        jumpLift = 0
        pauseTarget = playing ? 0 : 1; pauseLift = pauseTarget; pauseTween = nil
    }

    /** Ein Bild weiter ([dt] in Sekunden). */
    public func step(_ dt: Float) {
        if var p = pauseTween {
            p.step(dt); pauseLift = p.value
            pauseTween = p.isFinished ? nil : p
        }
        switch phase {
        case .idle:
            break
        case .follow(var tw):
            tw.step(dt); progress = tw.value
            phase = tw.isFinished ? .idle : .follow(tw)
        case .jump(var sp, var up):
            sp.step(dt); up.step(dt)
            progress = sp.value; jumpLift = up.value
            if sp.isFinished && up.isFinished {
                phase = .lower(TweenAnimation(from: jumpLift, to: 0, duration: 0.26))
            } else {
                phase = .jump(sp, up)
            }
        case .lower(var tw):
            tw.step(dt); jumpLift = tw.value
            phase = tw.isFinished ? .idle : .lower(tw)
        }
        if case .idle = phase, let t = pending {
            pending = nil
            if abs(t - progress) > Self.JUMP_THRESHOLD {
                phase = .jump(SpringAnimation(from: progress, to: t, stiffness: 110, dampingRatio: 0.92),
                              TweenAnimation(from: jumpLift, to: 1, duration: 0.16))
            } else {
                phase = .follow(TweenAnimation(from: progress, to: t, duration: 0.26, easing: nil))
            }
        }
    }
}

/**
 * Lage von Tonarm und Arm-Schatten in der Plattenspieler-Fläche (Kantenlänge [size] px), wie sie
 * Turntable.kt zeichnet. Beide Bilder werden mit der linken oberen Ecke an `origin` gelegt und dann um
 * `angleDegrees` (im Uhrzeigersinn) um den Punkt `origin + (arm.pivotX, arm.pivotY)` gedreht; der Arm
 * wird zusätzlich um denselben Punkt mit `armScale` skaliert; der Schatten mit `shadowAlpha` gezeichnet.
 */
public struct TonearmPose: Sendable {
    public let angleDegrees: Float
    public let armOriginX: Float, armOriginY: Float
    public let shadowOriginX: Float, shadowOriginY: Float
    public let shadowAlpha: Float
    public let armScale: Float

    public init(size: Float, arm: ArmRaster, progress: Float, lift: Float) {
        angleDegrees = TurntableGeometry.armAngleForProgress(progress)
        let pivotX = TurntableGeometry.PIVOT_X * size, pivotY = TurntableGeometry.PIVOT_Y * size
        let shadowOffset = size * (0.006 + 0.020 * lift)
        armOriginX = pivotX - arm.pivotX
        armOriginY = pivotY - arm.pivotY
        shadowOriginX = armOriginX + shadowOffset
        shadowOriginY = armOriginY + shadowOffset * 1.3
        shadowAlpha = 1 - 0.4 * lift
        armScale = 1 + 0.03 * lift
    }
}

// ---------------------------------------------------------------------------------------------
// Kassette
// ---------------------------------------------------------------------------------------------

/**
 * Antrieb der Kassettennaben (Cassette.kt): Motorfaktor folgt dem Ziel (`clamp(tempo, 0,25, 4)` bei
 * Wiedergabe, sonst 0) mit τ = 0,15 s (Anlauf) bzw. 0,22 s (Auslauf). Jede Nabe dreht sich mit der
 * Winkelgeschwindigkeit ihres Wickels (`CassetteGeometry.degreesPerSecond(radius, motor)`) **gegen** den
 * Uhrzeigersinn (Winkel nimmt ab; Band läuft unten von links nach rechts). Startwinkel links 0°, rechts 37°.
 */
public struct CassetteReels: Sendable {
    public static let TAU_UP: Float = 0.15
    public static let TAU_DOWN: Float = 0.22

    public private(set) var motor: Float = 0
    /** Drehwinkel der Naben in Grad (−360…0, im Uhrzeigersinn positiv). */
    public private(set) var angleLeft: Float = 0
    public private(set) var angleRight: Float = 37

    public init() {}

    public static func targetMotor(playing: Bool, speed: Float) -> Float { playing ? clampf(speed, 0.25, 4) : 0 }

    /**
     * Ein Bild weiter; [radiusLeftMm]/[radiusRightMm] = aktuelle Wickelradien (`packRadii(progress)`).
     * Gibt `false` zurück, sobald alles steht.
     */
    @discardableResult
    public mutating func step(target: Float, radiusLeftMm: Float, radiusRightMm: Float, dt rawDt: Float) -> Bool {
        let dt = Swift.min(rawDt, 0.1)
        let tau = target > motor ? Self.TAU_UP : Self.TAU_DOWN
        motor += (target - motor) * (1 - kexp(-dt / tau))
        if abs(target - motor) < 0.01 { motor = target }
        angleLeft = (angleLeft - CassetteGeometry.degreesPerSecond(radiusLeftMm, speedFactor: motor) * dt).truncatingRemainder(dividingBy: 360)
        angleRight = (angleRight - CassetteGeometry.degreesPerSecond(radiusRightMm, speedFactor: motor) * dt).truncatingRemainder(dividingBy: 360)
        return !(target == 0 && motor == 0)
    }

    public mutating func stop() { motor = 0 }
}

extension CassetteGeometry {
    /**
     * Berührpunkt der Tangente von Punkt ([fromX], [fromY]) an den Kreis (Mitte [cx], [cy], Radius [r]) –
     * außen liegende Seite (`left` = linker Wickel). Für den Bandweg Wickel → Umlenkrolle.
     */
    public static func tangentPoint(cx: Float, cy: Float, r: Float, fromX: Float, fromY: Float, left: Bool) -> (x: Float, y: Float) {
        let dx = fromX - cx, dy = fromY - cy
        let d = (dx * dx + dy * dy).squareRoot()
        if d <= r { return (cx + (left ? -r : r), cy) }
        let base = katan2(dy, dx)
        let off = kacos(r / d)
        let a = left ? base + off : base - off
        return (cx + r * kcos(a), cy + r * ksin(a))
    }
}

// ---------------------------------------------------------------------------------------------
// Klangvisualisierung
// ---------------------------------------------------------------------------------------------

/**
 * Geglättete Anzeigewerte der Visualisierung (Visualizer.kt): 16 Bänder + Pegel links/rechts, je 0…1.
 * Höchstens 30 Aktualisierungen pro Sekunde (≥ 33 ms Abstand); Bänder steigen mit 0,55 und fallen mit
 * 0,14 je Schritt, Pegel mit 0,5 bzw. 0,12. Ohne frische Analysewerte (Pause) klingen alle gegen 0 ab.
 */
public struct VisualizerSmoothing: Sendable {
    public static let BANDS = 16
    public private(set) var bands = [Float](repeating: 0, count: 16)
    public private(set) var left: Float = 0
    public private(set) var right: Float = 0

    public init() {}

    /**
     * Ein Schritt mit den Rohwerten des Analysators ([raw]: 16 Bänder, links, rechts; `nil` = keine
     * frischen Daten). Rückgabe: Summe aller Werte („Energie“) – in Pause endet die Schleife bei < 0,01.
     */
    @discardableResult
    public mutating func step(raw: [Float]?) -> Float {
        var energy: Float = 0
        for i in 0..<Self.BANDS {
            let target = raw?[i] ?? 0
            let cur = bands[i]
            bands[i] = target > cur ? cur + (target - cur) * 0.55 : cur + (target - cur) * 0.14
            energy += bands[i]
        }
        let tl = raw?[Self.BANDS] ?? 0
        let tr = raw?[Self.BANDS + 1] ?? 0
        left += (tl - left) * (tl > left ? 0.5 : 0.12)
        right += (tr - right) * (tr > right ? 0.5 : 0.12)
        energy += left + right
        return energy
    }
}
