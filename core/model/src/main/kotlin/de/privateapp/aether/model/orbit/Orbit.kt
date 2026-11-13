package de.privateapp.aether.model.orbit

import de.privateapp.aether.model.appearance.EffectIntensity

/*
 * ORBIT – gemeinsame Grundlagen von „Spatial Liquid Glass“ ohne Android (auf der JVM getestet: OrbitTest).
 * Gleiche Regeln wie in der macOS-App (Sources/AetherCore/Orbit.swift).
 */

/**
 * Aufgelöste Effekt-Schalter. Vorrang: „Animationen entfernen“ (Android) bzw. „Bewegung reduzieren“ (App) >
 * Energiesparmodus > Effektstärke.
 */
data class OrbitEffects(
    /** Kurzer Auftakt beim Start (≈ 0,8 s, blockiert nichts). */
    val ambientIntro: Boolean,
    /** Statt des Auftakts nur eine kurze Überblendung. */
    val introFadeOnly: Boolean,
    /** Lichtfelder der Atmosphäre wandern sehr langsam (nur „Immersiv“, gedrosselt, nur im Vordergrund). */
    val livingBackground: Boolean,
    /** Lichtfelder gleiten beim Bereichswechsel an eine neue Stelle. */
    val spatialBackground: Boolean,
    /** Lichtreflex an der Berührstelle auf Glasflächen. */
    val touchReflection: Boolean,
    /** Karten verwandeln sich in Detailansichten (gleiche Fläche wächst). */
    val morphingCards: Boolean,
    /** Große Zahlen wechseln mit einer kurzen Bewegung (nur „Immersiv“). */
    val numberTransitions: Boolean,
    /** Animierte Flüsse (Laden, Datenfluss, Dateivorgänge) – nur bei echter Aktivität. */
    val dataFlow: Boolean,
) {
    companion object {
        fun resolve(intensity: EffectIntensity, reducedMotion: Boolean, powerSave: Boolean): OrbitEffects {
            val moving = !reducedMotion
            return when (intensity) {
                EffectIntensity.MINIMAL -> OrbitEffects(
                    ambientIntro = false, introFadeOnly = false, livingBackground = false, spatialBackground = false,
                    touchReflection = false, morphingCards = moving, numberTransitions = false, dataFlow = moving,
                )
                EffectIntensity.BALANCED -> OrbitEffects(
                    ambientIntro = true, introFadeOnly = reducedMotion, livingBackground = false, spatialBackground = moving,
                    touchReflection = true, morphingCards = moving, numberTransitions = false, dataFlow = moving,
                )
                EffectIntensity.IMMERSIVE -> OrbitEffects(
                    ambientIntro = true, introFadeOnly = reducedMotion, livingBackground = moving && !powerSave,
                    spatialBackground = moving, touchReflection = true, morphingCards = moving,
                    numberTransitions = moving, dataFlow = moving,
                )
            }
        }
    }
}

/** Höchstwert eines Zeitfensters in Blöcken (konstanter Speicher). */
class RollingPeak(private val windowMillis: Long = 300_000, private val bucketMillis: Long = 15_000) {
    private val starts = ArrayDeque<Long>()
    private val maxima = ArrayDeque<Double>()

    fun add(value: Double, atMillis: Long) {
        if (!value.isFinite()) return
        val start = atMillis - Math.floorMod(atMillis, bucketMillis)
        if (starts.isNotEmpty() && starts.last() == start) {
            maxima[maxima.lastIndex] = maxOf(maxima.last(), value)
        } else {
            starts.addLast(start)
            maxima.addLast(value)
        }
        val limit = atMillis - windowMillis
        while (starts.isNotEmpty() && starts.first() + bucketMillis <= limit) {
            starts.removeFirst()
            maxima.removeFirst()
        }
    }

    fun peak(atMillis: Long): Double? {
        val limit = atMillis - windowMillis
        var best: Double? = null
        for (i in starts.indices) if (starts[i] + bucketMillis > limit) best = maxOf(best ?: maxima[i], maxima[i])
        return best
    }
}

/**
 * Datenrate aus fortlaufenden Zählern (TrafficStats). Liefert erst ab der zweiten Messung einen Wert; ein
 * zurückgesetzter Zähler (Neustart, Schnittstellenwechsel) ergibt keinen negativen, sondern keinen Wert.
 */
class CounterRate {
    private var lastTotal: Long? = null
    private var lastMillis: Long = 0

    fun next(total: Long?, atMillis: Long): Double? {
        if (total == null || total < 0) {
            lastTotal = null
            return null
        }
        val previous = lastTotal
        val previousMillis = lastMillis
        lastTotal = total
        lastMillis = atMillis
        if (previous == null || atMillis <= previousMillis || total < previous) return null
        return (total - previous) * 1000.0 / (atMillis - previousMillis)
    }
}

/** Bahnen des ORBIT Core auf Android (innen → außen). CPU- und GPU-Auslastung gibt Android normalen Apps nicht frei. */
enum class OrbitRing(val label: String) {
    MEMORY("Arbeitsspeicher"),
    STORAGE("Speicher"),
    THERMAL("Thermik"),
    NETWORK("Netzwerk"),
    BATTERY("Akku"),
}

/** Grundlage eines Bogens. */
enum class OrbitBasis { MEASURED, RELATIVE_TO_PEAK, UNAVAILABLE }

data class OrbitRingState(val ring: OrbitRing, val fraction: Float?, val basis: OrbitBasis) {
    /** Bogenlänge, auf 0,5 % gerastert (bewegt sich nur bei sichtbarer Änderung). */
    val arc: Float get() = fraction?.let { Math.round(it.coerceIn(0f, 1f) * 200f) / 200f } ?: 0f

    companion object {
        fun of(ring: OrbitRing, fraction: Float?, basis: OrbitBasis = OrbitBasis.MEASURED): OrbitRingState {
            val clean = fraction?.takeIf { it.isFinite() }?.coerceIn(0f, 1f)
            return OrbitRingState(ring, clean, if (clean == null) OrbitBasis.UNAVAILABLE else basis)
        }
    }
}

object OrbitCore {
    /** Untergrenze der Netzwerk-Skala (64 kB/s): Ohne nennenswerten Verkehr wirkt der Ring nicht „voll“. */
    const val NETWORK_FLOOR = 64_000.0

    fun networkFraction(current: Double?, peak: Double?): Float? {
        if (current == null || !current.isFinite() || current < 0) return null
        val reference = maxOf(peak ?: 0.0, current, NETWORK_FLOOR)
        return (current / reference).toFloat()
    }

    fun memoryFraction(total: Long?, available: Long?): Float? {
        if (total == null || available == null || total <= 0 || available < 0 || available > total) return null
        return ((total - available).toDouble() / total).toFloat()
    }
}
