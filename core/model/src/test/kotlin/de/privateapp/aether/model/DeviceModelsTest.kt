package de.privateapp.aether.model

import de.privateapp.aether.model.device.BatteryHealth
import de.privateapp.aether.model.device.BatteryInterpreter
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.device.DeviceSummary
import de.privateapp.aether.model.device.PowerSource
import de.privateapp.aether.model.device.ThermalInterpreter
import de.privateapp.aether.model.device.ThermalLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryInterpreterTest {

    private fun <T> value(r: Reading<T>): T = (r as Reading.Value).value
    private fun missing(r: Reading<*>): Missing = (r as Reading.Unavailable).missing

    @Test
    fun levelFromLevelAndScale() {
        assertEquals(82, value(BatteryInterpreter.level(82, 100)))
        assertEquals(50, value(BatteryInterpreter.level(128, 256)))
        assertEquals(100, value(BatteryInterpreter.level(100, 100)))
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.level(-1, 100)))
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.level(50, 0)))
        assertTrue(missing(BatteryInterpreter.level(120, 100)) is Missing.Implausible)
    }

    @Test
    fun temperatureIsTenthsOfDegreesCelsius() {
        assertEquals(31.5, value(BatteryInterpreter.temperature(315)), 1e-9)
        assertEquals(-5.0, value(BatteryInterpreter.temperature(-50)), 1e-9)
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.temperature(Int.MIN_VALUE)))
        // 3150 Zehntelgrad = 315 °C: nicht plausibel, wird nicht angezeigt
        assertTrue(missing(BatteryInterpreter.temperature(3150)) is Missing.Implausible)
        assertTrue(missing(BatteryInterpreter.temperature(-500)) is Missing.Implausible)
    }

    @Test
    fun voltageAcceptsMillivoltsAndMicrovoltsOnly() {
        assertEquals(4.21, value(BatteryInterpreter.voltage(4210)), 1e-9)
        assertEquals(3.85, value(BatteryInterpreter.voltage(3_850_000)), 1e-9)
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.voltage(0)))
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.voltage(Int.MIN_VALUE)))
        // Ganze Volt wären zu ungenau
        assertTrue(missing(BatteryInterpreter.voltage(4)) is Missing.Implausible)
        assertTrue(missing(BatteryInterpreter.voltage(12_000)) is Missing.Implausible)
    }

    @Test
    fun cycleCountRequiresAndroid14AndAPlausibleValue() {
        assertEquals(Missing.RequiresAndroid(34, "14"), missing(BatteryInterpreter.cycleCount(null)))
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.cycleCount(-1)))
        assertEquals(0, value(BatteryInterpreter.cycleCount(0)))
        assertEquals(312, value(BatteryInterpreter.cycleCount(312)))
        assertTrue(missing(BatteryInterpreter.cycleCount(1_000_000)) is Missing.Implausible)
    }

    @Test
    fun statusHealthAndSourcesMapAndroidConstants() {
        assertEquals(ChargeStatus.CHARGING, ChargeStatus.fromAndroid(2))
        assertEquals(ChargeStatus.FULL, ChargeStatus.fromAndroid(5))
        assertEquals(ChargeStatus.UNKNOWN, ChargeStatus.fromAndroid(99))
        assertEquals(BatteryHealth.GOOD, value(BatteryInterpreter.health(2)))
        assertEquals(BatteryHealth.OVERHEAT, value(BatteryInterpreter.health(3)))
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.health(1)))
        assertTrue(BatteryHealth.COLD.isProblem && !BatteryHealth.GOOD.isProblem)
        assertEquals(setOf(PowerSource.USB), PowerSource.fromAndroid(2))
        assertEquals(setOf(PowerSource.AC, PowerSource.WIRELESS), PowerSource.fromAndroid(1 or 4))
        assertEquals(emptySet<PowerSource>(), PowerSource.fromAndroid(0))
        assertEquals(emptySet<PowerSource>(), PowerSource.fromAndroid(64))
    }

    @Test
    fun technologyIgnoresBlank() {
        assertEquals("Li-ion", value(BatteryInterpreter.technology(" Li-ion ")))
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.technology("")))
        assertEquals(Missing.NotReported, missing(BatteryInterpreter.technology(null)))
    }
}

class ThermalTest {

    @Test
    fun allSevenAndroidLevelsAreMappedInOrder() {
        assertEquals(7, ThermalLevel.entries.size)
        ThermalLevel.entries.forEachIndexed { i, level ->
            assertEquals(i, level.androidValue)
            assertEquals(level, ThermalLevel.fromAndroid(i))
            assertTrue(level.label.isNotBlank() && level.meaning.isNotBlank())
        }
        assertNull(ThermalLevel.fromAndroid(7))
        assertNull(ThermalLevel.fromAndroid(-1))
    }

    @Test
    fun severityGroups() {
        assertFalse(ThermalLevel.LIGHT.isElevated)
        assertTrue(ThermalLevel.MODERATE.isElevated)
        assertFalse(ThermalLevel.SEVERE.isCritical)
        assertTrue(ThermalLevel.CRITICAL.isCritical && ThermalLevel.SHUTDOWN.isCritical)
    }

    @Test
    fun unknownStatusIsNotGuessed() {
        val r = ThermalInterpreter.level(9)
        assertTrue((r as Reading.Unavailable).missing is Missing.Implausible)
        assertEquals(ThermalLevel.SEVERE, (ThermalInterpreter.level(3) as Reading.Value).value)
    }

    @Test
    fun headroomNaNMeansNotAvailable() {
        assertEquals(Missing.NotReported, (ThermalInterpreter.headroom(Float.NaN, 0) as Reading.Unavailable).missing)
        assertTrue((ThermalInterpreter.headroom(-0.1f, 0) as Reading.Unavailable).missing is Missing.Implausible)
        assertTrue((ThermalInterpreter.headroom(Float.POSITIVE_INFINITY, 0) as Reading.Unavailable).missing is Missing.Implausible)
        val h = (ThermalInterpreter.headroom(0.38f, 0) as Reading.Value).value
        assertFalse(h.overThreshold)
        assertEquals("38${Fmt.NBSP}% genutzt", h.label)
        val over = (ThermalInterpreter.headroom(1.2f, 0) as Reading.Value).value
        assertTrue(over.overThreshold)
        assertEquals("Drosselschwelle erreicht", over.label)
    }
}

class DeviceSummaryTest {
    @Test
    fun modelNameAvoidsDuplicateManufacturer() {
        assertEquals("Google Pixel 6 Pro", DeviceSummary.modelName("Google", "Pixel 6 Pro"))
        assertEquals("Samsung Galaxy S24", DeviceSummary.modelName("samsung", "Samsung Galaxy S24"))
        assertEquals("Xiaomi 2201117TG", DeviceSummary.modelName("Xiaomi", "2201117TG"))
        assertEquals("Pixel", DeviceSummary.modelName("", "Pixel"))
        assertEquals("Google", DeviceSummary.modelName("google", ""))
    }

    @Test
    fun releaseNames() {
        assertEquals("14", DeviceSummary.releaseForApi(34))
        assertEquals("16", DeviceSummary.releaseForApi(36))
        assertEquals("API 40", DeviceSummary.releaseForApi(40))
    }
}
