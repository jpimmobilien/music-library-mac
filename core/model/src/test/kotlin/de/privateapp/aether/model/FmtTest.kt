package de.privateapp.aether.model

import org.junit.Assert.assertEquals
import org.junit.Test

class FmtTest {
    private val n = Fmt.NBSP

    @Test
    fun decimalUsesGermanSeparatorsAndAvoidsNegativeZero() {
        assertEquals("4,21", Fmt.decimal(4.2149, 2))
        assertEquals("12.480,5", Fmt.decimal(12480.46, 1))
        assertEquals("0,0", Fmt.decimal(-0.04, 1))
        assertEquals("-0,1", Fmt.decimal(-0.06, 1))
    }

    @Test
    fun percentNeverRoundsToMisleadingExtremes() {
        assertEquals("0$n%", Fmt.percent(0.0))
        assertEquals("<${n}1$n%", Fmt.percent(0.004))
        assertEquals("1$n%", Fmt.percent(0.005))
        assertEquals("63$n%", Fmt.percent(0.626))
        assertEquals(">${n}99$n%", Fmt.percent(0.996))
        assertEquals("100$n%", Fmt.percent(1.0))
        // außerhalb 0…1 wird begrenzt
        assertEquals("100$n%", Fmt.percent(1.3))
        assertEquals("0$n%", Fmt.percent(-0.2))
    }

    @Test
    fun unitsUseNonBreakingSpace() {
        assertEquals("31,4$n°C", Fmt.celsius(31.43))
        assertEquals("4,21${n}V", Fmt.volts(4.2071))
        assertEquals("82$n%", Fmt.percentInt(82))
    }

    @Test
    fun hertzShowsDecimalsOnlyWhenNeeded() {
        assertEquals("120${n}Hz", Fmt.hertz(120.0f))
        assertEquals("60${n}Hz", Fmt.hertz(60.00001f))
        assertEquals("59,9${n}Hz", Fmt.hertz(59.94f))
        assertEquals("90${n}Hz", Fmt.hertz(89.99f))
    }

    @Test
    fun durationIsCoarseAndReadable() {
        assertEquals("unter 1${n}Min.", Fmt.duration(59_000))
        assertEquals("42${n}Min.", Fmt.duration(42 * 60_000L))
        assertEquals("5${n}Std., 12${n}Min.", Fmt.duration((5 * 60 + 12) * 60_000L))
        assertEquals("1${n}Tag, 0${n}Std.", Fmt.duration(24 * 60 * 60_000L + 59_000))
        assertEquals("3${n}Tage, 4${n}Std.", Fmt.duration(((3 * 24 + 4) * 60 + 30) * 60_000L))
    }

    @Test
    fun isoDateIsFormattedInGermanOrLeftAlone() {
        assertEquals("5. Oktober 2026", Fmt.isoDate("2026-10-05"))
        assertEquals("1. März 2025", Fmt.isoDate(" 2025-03-01 "))
        assertEquals("unbekannt", Fmt.isoDate("unbekannt"))
    }

    @Test
    fun clockTimeUsesGivenZone() {
        // 2026-10-26 17:06:07 UTC = 18:06:07 in Berlin (Winterzeit)
        val t = java.time.ZonedDateTime.of(2026, 10, 26, 17, 6, 7, 0, java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
        assertEquals("18:06:07", Fmt.clockTime(t, java.time.ZoneId.of("Europe/Berlin")))
    }

    @Test
    fun countUsesThousandsSeparator() {
        assertEquals("12.480", Fmt.count(12480))
        assertEquals("7", Fmt.count(7))
    }
}

class ByteFormatTest {
    private val n = Fmt.NBSP

    @Test
    fun formatsLikeAndroidSettingsInDecimalUnits() {
        assertEquals("0${n}B", ByteFormat.format(0))
        assertEquals("812${n}B", ByteFormat.format(812))
        assertEquals("999${n}B", ByteFormat.format(999))
        assertEquals("1${n}kB", ByteFormat.format(1000))
        assertEquals("4,2${n}kB", ByteFormat.format(4200))
        assertEquals("47,3${n}GB", ByteFormat.format(47_300_000_000))
        assertEquals("128${n}GB", ByteFormat.format(128_000_000_000))
        assertEquals("1${n}TB", ByteFormat.format(1_000_000_000_000))
        assertEquals("64${n}GB", ByteFormat.format(64_000_000_000))
        assertEquals("1,5${n}GB", ByteFormat.format(1_460_000_000))
    }

    @Test
    fun neverShowsThousandOfAUnitOrHundredWithDecimal() {
        assertEquals("999${n}kB", ByteFormat.format(999_499))
        assertEquals("1${n}MB", ByteFormat.format(999_500))
        assertEquals("100${n}kB", ByteFormat.format(99_960))
        assertEquals("99,9${n}kB", ByteFormat.format(99_940))
        assertEquals("1${n}GB", ByteFormat.format(999_999_999))
    }

    @Test(expected = IllegalArgumentException::class)
    fun negativeSizeIsAProgrammingError() {
        ByteFormat.format(-1)
    }

    @Test
    fun fileDateIsRelativeForRecentDays() {
        val zone = java.time.ZoneId.of("Europe/Berlin")
        val now = java.time.ZonedDateTime.of(2026, 10, 27, 15, 0, 0, 0, zone).toInstant().toEpochMilli()
        fun at(y: Int, m: Int, d: Int, h: Int, min: Int) = java.time.ZonedDateTime.of(y, m, d, h, min, 0, 0, zone).toInstant().toEpochMilli()
        assertEquals("Heute, 14:32", Fmt.fileDate(at(2026, 10, 27, 14, 32), now, zone))
        assertEquals("Gestern, 09:05", Fmt.fileDate(at(2026, 10, 26, 9, 5), now, zone))
        assertEquals("12. März", Fmt.fileDate(at(2026, 3, 12, 8, 0), now, zone))
        assertEquals("12.03.24", Fmt.fileDate(at(2024, 3, 12, 8, 0), now, zone))
        // Zukunft (falsch gestellte Uhr) nie als „Heute“ oder Monatsname, sondern als Datum
        assertEquals("05.11.26", Fmt.fileDate(at(2026, 11, 5, 8, 0), now, zone))
        assertEquals("12. März 2026, 08:00", Fmt.dateTime(at(2026, 3, 12, 8, 0), zone))
    }
}
