package de.privateapp.aether.model.motion

import kotlin.math.abs

/*
 * Satelliten (GNSS) – reine Deutung dessen, was `GnssStatus` meldet. Android listet jedes empfangene SIGNAL als
 * eigenen Eintrag: Ein Galileo-Satellit, der auf E1 und E5a empfangen wird, erscheint zweimal. Gezählt werden hier
 * deshalb Satelliten (System + Nummer), nicht Einträge.
 */

/** Satellitensystem laut `GnssStatus.getConstellationType`. Reihenfolge = Reihenfolge in der Anzeige. */
enum class GnssConstellation(val label: String, val operator: String) {
    GPS("GPS", "USA"),
    GALILEO("Galileo", "EU"),
    GLONASS("GLONASS", "Russland"),
    BEIDOU("BeiDou", "China"),
    QZSS("QZSS", "Japan"),
    NAVIC("NavIC", "Indien"),
    SBAS("SBAS", "Korrekturdienste wie EGNOS"),
    UNKNOWN("Unbekannt", "nicht zugeordnet"),
    ;

    companion object {
        /**
         * Werte von `GnssStatus.CONSTELLATION_*`: 0 unbekannt, 1 GPS, 2 SBAS, 3 GLONASS, 4 QZSS, 5 BeiDou,
         * 6 Galileo, 7 IRNSS (= NavIC). Unbekannte künftige Werte landen bei [UNKNOWN].
         */
        fun fromAndroid(type: Int): GnssConstellation = when (type) {
            1 -> GPS
            2 -> SBAS
            3 -> GLONASS
            4 -> QZSS
            5 -> BEIDOU
            6 -> GALILEO
            7 -> NAVIC
            else -> UNKNOWN
        }
    }
}

/**
 * Frequenzband eines Signals (aus `GnssStatus.getCarrierFrequencyHz`). [upper] = L1-artiges Band, [lower] = L5-artiges
 * Band; beides zusammen nennt man Zweifrequenz-Empfang – er macht die Position in Städten und unter Bäumen robuster.
 */
enum class FrequencyBand(val label: String, val upper: Boolean, val lower: Boolean) {
    L1("L1 / E1 / B1C", upper = true, lower = false),
    B1I("B1I", upper = true, lower = false),
    G1("G1", upper = true, lower = false),
    L2("L2", upper = false, lower = false),
    G2("G2", upper = false, lower = false),
    E6("E6 / B3 / L6", upper = false, lower = false),
    E5B("E5b / B2I", upper = false, lower = true),
    L5("L5 / E5a / B2a", upper = false, lower = true),
    OTHER("anderes Band", upper = false, lower = false),
    ;

    companion object {
        private const val MHZ = 1_000_000.0

        /** Zuordnung nach Trägerfrequenz (Nennwerte der Systeme, ±2 MHz; GLONASS-FDMA als Bereich). */
        fun of(carrierHz: Double): FrequencyBand {
            val mhz = carrierHz / MHZ
            fun near(nominal: Double) = abs(mhz - nominal) <= 2.0
            return when {
                near(1575.42) -> L1
                near(1561.098) -> B1I
                mhz in 1597.5..1606.0 -> G1
                near(1227.60) -> L2
                mhz in 1242.0..1249.0 -> G2
                near(1278.75) || near(1268.52) -> E6
                near(1207.14) -> E5B
                near(1176.45) -> L5
                else -> OTHER
            }
        }
    }
}

/** Ein empfangenes Signal, so wie `GnssStatus` es meldet. */
data class SatelliteSignal(
    val constellation: GnssConstellation,
    /** Satellitennummer innerhalb des Systems. */
    val svid: Int,
    /** Signalstärke (Träger-Rausch-Verhältnis) in dB-Hz; 0 = erwartet, aber nicht empfangen. */
    val cn0DbHz: Float,
    val usedInFix: Boolean,
    /** Trägerfrequenz in Hz, `null` wenn der Empfänger sie nicht meldet. */
    val carrierFrequencyHz: Double?,
    val elevationDegrees: Float,
    val azimuthDegrees: Float,
)

/** Satelliten eines Systems. */
data class ConstellationCount(val constellation: GnssConstellation, val received: Int, val used: Int)

/** Einordnung der durchschnittlichen Signalstärke der genutzten Satelliten. */
enum class SignalQuality(val label: String, val range: String) {
    STRONG("stark", "ab 40 dB-Hz"),
    MEDIUM("mittel", "30 bis 40 dB-Hz"),
    WEAK("schwach", "unter 30 dB-Hz"),
    ;

    companion object {
        fun of(meanCn0DbHz: Float): SignalQuality = when {
            meanCn0DbHz >= 40f -> STRONG
            meanCn0DbHz >= 30f -> MEDIUM
            else -> WEAK
        }
    }
}

/** Zusammenfassung des Satellitenempfangs. */
data class SatelliteSummary(
    /** Gemeldete Satelliten (auch erwartete ohne Empfang). */
    val listed: Int,
    /** Davon mit Signal (C/N0 > 0). */
    val received: Int,
    /** Davon für die Position genutzt. */
    val used: Int,
    /** Nur Systeme mit mindestens einem gemeldeten Satelliten, in Anzeigereihenfolge. */
    val byConstellation: List<ConstellationCount>,
    val strongestCn0DbHz: Float?,
    /** Mittlere Signalstärke der genutzten Satelliten (je Satellit das stärkste Signal). */
    val meanUsedCn0DbHz: Float?,
    /** Frequenzbänder empfangener Signale; leer, wenn der Empfänger keine Frequenzen meldet. */
    val bands: Set<FrequencyBand>,
    /** Der Empfänger meldet Trägerfrequenzen (sonst lässt sich Zweifrequenz nicht feststellen). */
    val reportsFrequencies: Boolean,
) {
    /** `null` = nicht feststellbar (keine Frequenzangaben). */
    val dualFrequency: Boolean?
        get() = if (!reportsFrequencies) null else bands.any { it.upper } && bands.any { it.lower }

    val quality: SignalQuality? get() = meanUsedCn0DbHz?.let { SignalQuality.of(it) }

    companion object {
        val EMPTY = SatelliteSummary(0, 0, 0, emptyList(), null, null, emptySet(), reportsFrequencies = false)
    }
}

object GnssInterpreter {
    /** Fasst die Signale eines `GnssStatus` zu Satelliten zusammen. */
    fun summarize(signals: List<SatelliteSignal>): SatelliteSummary {
        if (signals.isEmpty()) return SatelliteSummary.EMPTY
        data class Sat(val constellation: GnssConstellation, val bestCn0: Float, val used: Boolean)
        val satellites = signals
            .groupBy { it.constellation to it.svid }
            .map { (key, s) -> Sat(key.first, s.maxOf { it.cn0DbHz.coerceAtLeast(0f) }, s.any { it.usedInFix }) }
        val byConstellation = GnssConstellation.entries.mapNotNull { c ->
            val of = satellites.filter { it.constellation == c }
            if (of.isEmpty()) null else ConstellationCount(c, received = of.count { it.bestCn0 > 0f }, used = of.count { it.used })
        }
        val received = satellites.filter { it.bestCn0 > 0f }
        val used = satellites.filter { it.used }
        val withFrequency = signals.filter { it.carrierFrequencyHz != null && it.carrierFrequencyHz > 0.0 }
        return SatelliteSummary(
            listed = satellites.size,
            received = received.size,
            used = used.size,
            byConstellation = byConstellation,
            strongestCn0DbHz = received.maxOfOrNull { it.bestCn0 },
            meanUsedCn0DbHz = used.filter { it.bestCn0 > 0f }.takeIf { it.isNotEmpty() }?.map { it.bestCn0 }?.average()?.toFloat(),
            bands = withFrequency.filter { it.cn0DbHz > 0f }.mapNotNull { s -> s.carrierFrequencyHz?.let { FrequencyBand.of(it) } }.toSet(),
            reportsFrequencies = withFrequency.isNotEmpty(),
        )
    }
}
