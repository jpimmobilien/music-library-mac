import Foundation

/**
 * Maße des Plattenspielers – alle Angaben relativ zur Kantenlänge S der quadratischen Fläche
 * (0…1, y nach unten). Gemeinsame Grundlage für den Renderer ([VinylRenderer]) und die Anzeige.
 *
 * Proportionen wie bei einer echten 30-cm-LP: Label ≈ 1/3 des Durchmessers, Rillenbereich von etwa
 * 46 % bis 95 % des Radius, Einlauf- und Auslaufrille glatt.
 */
public enum TurntableGeometry {
    /** Mittelpunkt der Platte. */
    public static let CENTER_X: Float = 0.455
    public static let CENTER_Y: Float = 0.5

    /** Radius der Platte. */
    public static let RECORD_RADIUS: Float = 0.415

    /** Plattenteller (sichtbarer Rand außerhalb der Platte), relativ zum Plattenradius. */
    public static let PLATTER_FACTOR: Float = 1.035

    /** Label (Cover) relativ zum Plattenradius. */
    public static let LABEL_FACTOR: Float = 0.34

    /** Rillenbereich relativ zum Plattenradius. */
    public static let GROOVE_OUTER: Float = 0.955
    public static let GROOVE_INNER: Float = 0.40

    /** Bereich, über den die Nadel während eines Titels wandert (Einlauf → Auslauf). */
    public static let STYLUS_START: Float = 0.945
    public static let STYLUS_END: Float = 0.42

    /** Drehpunkt des Tonarms. */
    public static let PIVOT_X: Float = 0.875
    public static let PIVOT_Y: Float = 0.20

    /** Rohrlänge bis zum Tonkopf, Abstand Rohrende → Nadel, Abwinkelung des Tonkopfs. */
    public static let TUBE_LENGTH: Float = 0.505
    public static let HEAD_LENGTH: Float = 0.07
    public static let HEADSHELL_BEND_DEG: Float = 22

    /** Ruhestellung (Arm liegt auf der Stütze neben der Platte), Winkel in Grad (Bildschirm, y nach unten). */
    public static let REST_ANGLE_DEG: Float = 84

    /** Abstand der Armstütze vom Drehpunkt. */
    public static let REST_POST_DISTANCE: Float = 0.36

    /** Ausdehnung des Tonarm-Bildes (Armkoordinaten, x entlang des Rohrs, Drehpunkt bei 0). */
    public static let ARM_BACK: Float = 0.175
    public static let ARM_FRONT: Float = 0.64
    public static let ARM_HALF_HEIGHT: Float = 0.085

    /** Bedienknöpfe (33/45) unten links: x33, y33, x45, y45. */
    public static let SPEED_BUTTONS: [Float] = [0.072, 0.94, 0.125, 0.94]
    public static let SPEED_BUTTON_RADIUS: Float = 0.0155

    /** Abwinkelung des Tonkopfs im Bogenmaß. */
    public static var bendRad: Float { HEADSHELL_BEND_DEG * PI_F / 180 }

    /** Nadelspitze in Armkoordinaten (Einheiten von S). */
    public static var stylusX: Float { TUBE_LENGTH + HEAD_LENGTH * kcos(bendRad) }
    public static var stylusY: Float { HEAD_LENGTH * ksin(bendRad) }

    /** Wirksame Armlänge (Drehpunkt → Nadel). */
    public static var effectiveLength: Float { khypot(stylusX, stylusY) }

    /**
     * Drehwinkel des Arm-Bildes (Grad, im Uhrzeigersinn, 0 = nach rechts), bei dem die Nadel den Abstand
     * [radiusFactor] · Plattenradius zum Mittelpunkt hat. Von zwei Lösungen wird die über der Platte
     * (links unterhalb des Drehpunkts) gewählt.
     */
    public static func armAngleForRadius(_ radiusFactor: Float) -> Float {
        let r = radiusFactor * RECORD_RADIUS
        let dx = CENTER_X - PIVOT_X
        let dy = CENTER_Y - PIVOT_Y
        let d = khypot(dx, dy)
        let l = effectiveLength
        let toCenter = katan2(dy, dx)
        // Kosinussatz: Winkel zwischen Richtung „Drehpunkt → Mitte“ und „Drehpunkt → Nadel“.
        let k = clampf((d * d + l * l - r * r) / (2 * d * l), -1, 1)
        let delta = kacos(k)
        // Die Lösung, bei der die Nadel auf der dem Drehpunkt abgewandten Seite (unten) liegt.
        let a1 = toCenter + delta
        let a2 = toCenter - delta
        let y1 = PIVOT_Y + l * ksin(a1)
        let y2 = PIVOT_Y + l * ksin(a2)
        let stylusDirection = y1 >= y2 ? a1 : a2
        let tipOffset = katan2(stylusY, stylusX)
        return (stylusDirection - tipOffset) * 180 / PI_F
    }

    /**
     * Winkel (Grad) für einen Fortschritt 0…1 (Einlauf → Auslauf); Werte < 0 schwenken Richtung
     * Ruhestellung (−1 = [REST_ANGLE_DEG]).
     */
    public static func armAngleForProgress(_ progress: Float) -> Float {
        let outer = armAngleForRadius(STYLUS_START)
        let inner = armAngleForRadius(STYLUS_END)
        if progress >= 0 {
            return outer + (inner - outer) * (progress > 1 ? 1 : progress)
        } else {
            return outer + (outer - REST_ANGLE_DEG) * (progress < -1 ? -1 : progress)
        }
    }
}
