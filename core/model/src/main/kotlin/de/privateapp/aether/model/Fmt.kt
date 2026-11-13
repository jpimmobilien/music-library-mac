package de.privateapp.aether.model

import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Zahlenformate der Oberfläche (deutsch: Dezimalkomma, Tausenderpunkt, geschütztes Leerzeichen vor
 * Einheiten, damit „63 %“ oder „31,4 °C“ nie umbrochen werden).
 */
object Fmt {
    private val locale: Locale = Locale.GERMANY

    /** Geschütztes Leerzeichen zwischen Zahl und Einheit. */
    const val NBSP = ' '

    /** Dezimalzahl mit genau [fractionDigits] Nachkommastellen, z. B. „4,21“. */
    fun decimal(value: Double, fractionDigits: Int): String {
        require(fractionDigits in 0..6) { "fractionDigits" }
        // -0,0 vermeiden
        val v = if (abs(value) < 0.5 * Math.pow(10.0, -fractionDigits.toDouble())) 0.0 else value
        return String.format(locale, "%,.${fractionDigits}f", v)
    }

    /** Ganze Zahl mit Tausenderpunkt, z. B. „12.480“. */
    fun count(value: Long): String = String.format(locale, "%,d", value)

    fun count(value: Int): String = count(value.toLong())

    /**
     * Anteil 0…1 als Prozent ohne Nachkommastellen. Nie irreführend gerundet: Ein kleiner, aber vorhandener
     * Anteil wird „< 1 %“, ein fast voller „> 99 %“ – „0 %“ und „100 %“ erscheinen nur, wenn es stimmt.
     */
    fun percent(fraction: Double): String {
        val f = fraction.coerceIn(0.0, 1.0)
        val pct = (f * 100.0).roundToInt()
        return when {
            pct == 0 && f > 0.0 -> "<${NBSP}1${NBSP}%"
            pct == 100 && f < 1.0 -> ">${NBSP}99${NBSP}%"
            else -> "$pct${NBSP}%"
        }
    }

    /** Ganze Prozentzahl, z. B. Akkustand „82 %“. */
    fun percentInt(value: Int): String = "$value${NBSP}%"

    /** Temperatur in Grad Celsius mit einer Nachkommastelle, z. B. „31,4 °C“. */
    fun celsius(value: Double): String = decimal(value, 1) + "${NBSP}°C"

    /** Spannung in Volt mit zwei Nachkommastellen, z. B. „4,21 V“. */
    fun volts(value: Double): String = decimal(value, 2) + "${NBSP}V"

    /** Bildwiederholrate, z. B. „120 Hz“ bzw. „59,9 Hz“. */
    fun hertz(value: Float): String {
        val rounded = (value * 10f).roundToInt() / 10.0
        return if (abs(rounded - rounded.roundToLong()) < 0.05) "${rounded.roundToLong()}${NBSP}Hz" else decimal(rounded, 1) + "${NBSP}Hz"
    }

    private val longDate = java.time.format.DateTimeFormatter.ofPattern("d. MMMM yyyy", locale)
    private val clock = java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss", locale)

    /** ISO-Datum („2026-10-05“) als „5. Oktober 2026“; unbekannte Schreibweisen bleiben unverändert. */
    fun isoDate(text: String): String = try {
        java.time.LocalDate.parse(text.trim()).format(longDate)
    } catch (e: java.time.format.DateTimeParseException) {
        text
    }

    /** Uhrzeit eines Zeitpunkts in der Zeitzone des Geräts, z. B. „18:42:10“. */
    fun clockTime(epochMillis: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String =
        java.time.Instant.ofEpochMilli(epochMillis).atZone(zone).format(clock)

    private val hm = java.time.format.DateTimeFormatter.ofPattern("HH:mm", locale)
    private val dayMonth = java.time.format.DateTimeFormatter.ofPattern("d. MMM", locale)
    private val numericDate = java.time.format.DateTimeFormatter.ofPattern("dd.MM.yy", locale)
    private val longDateTime = java.time.format.DateTimeFormatter.ofPattern("d. MMMM yyyy, HH:mm", locale)

    /**
     * Kurzes Datum für Dateilisten wie in „Dateien“ von Apple: „Heute, 14:32“, „Gestern, 09:10“, im selben Jahr
     * „12. März“, sonst „12.03.24“. Zeitpunkte in der Zukunft (falsche Uhr der Kamera …) erscheinen als Datum.
     */
    fun fileDate(epochMillis: Long, nowMillis: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String {
        val t = java.time.Instant.ofEpochMilli(epochMillis).atZone(zone)
        val today = java.time.Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        val day = t.toLocalDate()
        return when {
            day == today -> "Heute, ${t.format(hm)}"
            day == today.minusDays(1) -> "Gestern, ${t.format(hm)}"
            day.year == today.year && !day.isAfter(today) -> t.format(dayMonth)
            else -> t.format(numericDate)
        }
    }

    /** Vollständiges Datum mit Uhrzeit, z. B. „12. März 2026, 14:32“ (Informationen zu einer Datei). */
    fun dateTime(epochMillis: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String =
        java.time.Instant.ofEpochMilli(epochMillis).atZone(zone).format(longDateTime)

    /** Dauer seit einem Ereignis, grob: „3 Tage, 4 Std.“, „5 Std., 12 Min.“, „42 Min.“, „unter 1 Min.“ */
    fun duration(millis: Long): String {
        if (millis < 60_000L) return "unter 1${NBSP}Min."
        val totalMinutes = millis / 60_000L
        val days = totalMinutes / (24 * 60)
        val hours = (totalMinutes / 60) % 24
        val minutes = totalMinutes % 60
        return when {
            days > 0 -> "${count(days)}${NBSP}${if (days == 1L) "Tag" else "Tage"}, $hours${NBSP}Std."
            hours > 0 -> "$hours${NBSP}Std., $minutes${NBSP}Min."
            else -> "$minutes${NBSP}Min."
        }
    }
}

/**
 * Speichergrößen wie in den Android-Einstellungen: Dezimal-Einheiten (1 GB = 1 000 000 000 Byte).
 * Android zeigt Speicher seit Version 8 so an; dieselbe Rechnung verhindert, dass ORBIT und die
 * Systemeinstellungen für denselben Datenträger unterschiedliche Zahlen zeigen.
 */
object ByteFormat {
    private val units = arrayOf("B", "kB", "MB", "GB", "TB", "PB")

    /**
     * „0 B“, „812 B“, „4,2 kB“, „47,3 GB“, „64 GB“, „128 GB“. Unter 100 höchstens eine Nachkommastelle, ab 100 keine.
     * Negative Werte sind ein Programmierfehler.
     */
    fun format(bytes: Long): String {
        require(bytes >= 0) { "Negative Größe: $bytes" }
        if (bytes < 1000) return "$bytes${Fmt.NBSP}B"
        var value = bytes.toDouble()
        var unit = 0
        // Ab 999,5 würde gerundet „1000“ erscheinen – stattdessen die nächste Einheit („1,0 MB“).
        while (value >= 999.5 && unit < units.lastIndex) {
            value /= 1000.0
            unit++
        }
        // Ab 99,95 würde mit Nachkommastelle „100,0“ erscheinen – dann ganzzahlig („100 GB“).
        // Eine Null nach dem Komma entfällt („64 GB“ statt „64,0 GB“).
        val text = if (value >= 99.95) value.roundToLong().toString() else Fmt.decimal(value, 1).removeSuffix(",0")
        return "$text${Fmt.NBSP}${units[unit]}"
    }
}
