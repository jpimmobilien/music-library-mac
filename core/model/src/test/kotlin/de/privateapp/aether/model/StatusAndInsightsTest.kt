package de.privateapp.aether.model

import de.privateapp.aether.model.appearance.AccentChoice
import de.privateapp.aether.model.appearance.AppearanceCodec
import de.privateapp.aether.model.appearance.AppearanceSettings
import de.privateapp.aether.model.appearance.EffectIntensity
import de.privateapp.aether.model.appearance.ThemeStyle
import de.privateapp.aether.model.device.BatteryHealth
import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.device.PowerSource
import de.privateapp.aether.model.device.ThermalLevel
import de.privateapp.aether.model.device.ThermalSnapshot
import de.privateapp.aether.model.storage.Capacity
import de.privateapp.aether.model.storage.CapacityMethod
import de.privateapp.aether.model.storage.MountState
import de.privateapp.aether.model.storage.StorageOverview
import de.privateapp.aether.model.storage.StorageVolumeInfo
import de.privateapp.aether.model.storage.VolumeKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private val n = Fmt.NBSP

internal fun battery(level: Int?, status: ChargeStatus = ChargeStatus.DISCHARGING, health: BatteryHealth = BatteryHealth.GOOD, present: Boolean = true) =
    BatterySnapshot(
        present = present,
        level = if (level != null) reported(level, "t") else unavailable(Missing.NotReported),
        status = status,
        sources = if (status == ChargeStatus.CHARGING) setOf(PowerSource.USB) else emptySet(),
        health = reported(health, "t"),
        temperatureCelsius = reported(30.0, "t"),
        voltage = reported(4.0, "t"),
        technology = reported("Li-ion", "t"),
        cycleCount = unavailable(Missing.NotReported),
        observedAtMillis = 0,
    )

internal fun volume(
    id: String,
    kind: VolumeKind,
    state: MountState = MountState.MOUNTED,
    total: Long = 64_000_000_000,
    free: Long = 60_000_000_000,
    description: String = kind.label,
) = StorageVolumeInfo(
    id = id, kind = kind, description = description, isPrimary = kind == VolumeKind.INTERNAL, isRemovable = kind != VolumeKind.INTERNAL,
    isEmulated = kind == VolumeKind.INTERNAL, state = state, path = null,
    capacity = if (state.isMounted) Capacity.of(total, free, CapacityMethod.FILE_SYSTEM) else unavailable(Missing.NotMounted),
    partition = null,
)

class StatusLineTest {
    @Test
    fun combinesOnlyAvailableParts() {
        val cap = Capacity.of(100, 37, CapacityMethod.SYSTEM_STATS)
        val thermal = reported(ThermalLevel.NONE, "t")
        assertEquals(
            "Speicher zu 63$n% belegt · Akku 82$n% · thermisch normal",
            StatusLine.build(cap, battery(82), thermal),
        )
        assertEquals("Akku 100$n%, voll", StatusLine.build(null, battery(100, ChargeStatus.FULL), null))
        assertEquals("Akku 40$n%, lädt · Wärme: erhöht", StatusLine.build(null, battery(40, ChargeStatus.CHARGING), reported(ThermalLevel.MODERATE, "t")))
    }

    @Test
    fun saysWhenNothingIsKnownYetOrAtAll() {
        assertEquals("Gerätedaten werden gelesen …", StatusLine.build(null, null, null))
        assertEquals(
            "Keine Gerätedaten verfügbar",
            StatusLine.build(unavailable(Missing.NotReported), battery(null, present = false), unavailable(Missing.NotReported)),
        )
    }

    @Test
    fun missingBatteryIsNotShownAsZero() {
        val line = StatusLine.build(Capacity.of(100, 50, CapacityMethod.SYSTEM_STATS), battery(null), null)
        assertEquals("Speicher zu 50$n% belegt", line)
    }
}

class InsightsTest {
    private fun overview(vararg v: StorageVolumeInfo) = StorageOverview(v.toList(), 0)

    @Test
    fun nothingToSayMeansNoInsights() {
        val o = overview(volume("primary", VolumeKind.INTERNAL, total = 128_000_000_000, free = 60_000_000_000))
        val t = ThermalSnapshot(reported(ThermalLevel.LIGHT, "t"), unavailable(Missing.NotReported), 0)
        assertTrue(Insights.from(o, battery(80), t).isEmpty())
        assertTrue(Insights.from(null, null, null).isEmpty())
    }

    @Test
    fun externalMediaAreReportedFactually() {
        val o = overview(
            volume("primary", VolumeKind.INTERNAL, total = 128_000_000_000, free = 60_000_000_000),
            volume("sd", VolumeKind.SD_CARD, description = "SD-Karte von SanDisk"),
            volume("usb", VolumeKind.USB, state = MountState.MOUNTED_READ_ONLY, description = "USB-Speicher"),
            volume("bad", VolumeKind.REMOVABLE, state = MountState.UNMOUNTABLE, description = "Datenträger"),
            volume("gone", VolumeKind.SD_CARD, state = MountState.REMOVED),
        )
        val list = Insights.from(o, null, null)
        assertEquals(listOf("ro-usb", "bad-bad", "ext-sd"), list.map { it.id })
        val sd = list.first { it.id == "ext-sd" }
        assertEquals("SD-Karte erkannt", sd.title)
        assertEquals("„SD-Karte von SanDisk“ · 60${n}GB frei von 64${n}GB", sd.message)
        assertEquals(Severity.INFO, sd.severity)
    }

    @Test
    fun nearlyFullInternalStorageIsMentionedWithoutPressure() {
        val o = overview(volume("primary", VolumeKind.INTERNAL, total = 100_000_000_000, free = 8_000_000_000))
        val i = Insights.from(o, null, null).single()
        assertEquals(Severity.ATTENTION, i.severity)
        assertEquals("Interner Speicher zu 92$n% belegt", i.title)
        assertTrue(!i.message.contains("!"))
        val full = Insights.from(overview(volume("primary", VolumeKind.INTERNAL, total = 100_000_000_000, free = 2_000_000_000)), null, null).single()
        assertEquals(Severity.CRITICAL, full.severity)
    }

    @Test
    fun thermalAndBatteryProblemsComeFirst() {
        val o = overview(
            volume("primary", VolumeKind.INTERNAL, total = 128_000_000_000, free = 60_000_000_000),
            volume("sd", VolumeKind.SD_CARD),
        )
        val t = ThermalSnapshot(reported(ThermalLevel.CRITICAL, "t"), unavailable(Missing.NotReported), 0)
        val list = Insights.from(o, battery(50, health = BatteryHealth.OVERHEAT), t)
        assertEquals(listOf("thermal", "battery-health", "ext-sd"), list.map { it.id })
        assertEquals(Severity.CRITICAL, list.first().severity)
        assertEquals(InsightTarget.DEVICE, list.first().target)
    }
}

class AppearanceCodecTest {
    @Test
    fun roundTripsAndFallsBackOnUnknownValues() {
        ThemeStyle.entries.forEach { assertEquals(it, AppearanceCodec.theme(it.name)) }
        AccentChoice.entries.forEach { assertEquals(it, AppearanceCodec.accent(it.name)) }
        EffectIntensity.entries.forEach { assertEquals(it, AppearanceCodec.intensity(it.name)) }
        assertEquals(AppearanceSettings.Default.theme, AppearanceCodec.theme(null))
        assertEquals(AppearanceSettings.Default.theme, AppearanceCodec.theme("NEON"))
        assertEquals(AppearanceSettings.Default.accent, AppearanceCodec.accent("purple"))
        assertEquals(AppearanceSettings.Default.intensity, AppearanceCodec.intensity(""))
    }

    @Test
    fun defaultsMatchTheBrief() {
        assertEquals(5, ThemeStyle.entries.size)
        assertEquals(3, EffectIntensity.entries.size)
        // sieben feste Akzente + Systemfarbe
        assertEquals(8, AccentChoice.entries.size)
        assertEquals(ThemeStyle.ADAPTIVE, AppearanceSettings.Default.theme)
    }
}
