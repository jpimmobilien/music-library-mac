package de.privateapp.aether.model

import de.privateapp.aether.model.appearance.EffectIntensity
import de.privateapp.aether.model.orbit.CounterRate
import de.privateapp.aether.model.orbit.OrbitBasis
import de.privateapp.aether.model.orbit.OrbitCore
import de.privateapp.aether.model.orbit.OrbitEffects
import de.privateapp.aether.model.orbit.OrbitRing
import de.privateapp.aether.model.orbit.OrbitRingState
import de.privateapp.aether.model.orbit.RollingPeak
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OrbitTest {
    @Test
    fun reducedMotionWinsOverEveryProfile() {
        for (intensity in EffectIntensity.entries) {
            val e = OrbitEffects.resolve(intensity, reducedMotion = true, powerSave = false)
            assertFalse(e.livingBackground)
            assertFalse(e.spatialBackground)
            assertFalse(e.numberTransitions)
            assertFalse(e.dataFlow)
        }
        assertTrue(OrbitEffects.resolve(EffectIntensity.BALANCED, reducedMotion = true, powerSave = false).introFadeOnly)
    }

    @Test
    fun onlyImmersiveLivesAndNeverInPowerSave() {
        assertFalse(OrbitEffects.resolve(EffectIntensity.BALANCED, false, false).livingBackground)
        assertTrue(OrbitEffects.resolve(EffectIntensity.IMMERSIVE, false, false).livingBackground)
        assertFalse(OrbitEffects.resolve(EffectIntensity.IMMERSIVE, false, powerSave = true).livingBackground)
        val minimal = OrbitEffects.resolve(EffectIntensity.MINIMAL, false, false)
        assertFalse(minimal.ambientIntro)
        assertFalse(minimal.touchReflection)
        assertTrue("Echte Aktivität bleibt sichtbar", minimal.dataFlow)
    }

    @Test
    fun rollingPeakForgetsOldValues() {
        val peak = RollingPeak(windowMillis = 60_000, bucketMillis = 10_000)
        assertNull(peak.peak(0))
        peak.add(5_000_000.0, 0)
        peak.add(1_000.0, 30_000)
        assertEquals(5_000_000.0, peak.peak(30_000)!!, 0.0)
        peak.add(2_000.0, 75_000)
        assertEquals(2_000.0, peak.peak(75_000)!!, 0.0)
        peak.add(Double.NaN, 76_000)
        assertEquals(2_000.0, peak.peak(76_000)!!, 0.0)
    }

    @Test
    fun counterRateNeedsTwoSamplesAndIgnoresResets() {
        val rate = CounterRate()
        assertNull(rate.next(1_000, 0))
        assertEquals(2_000.0, rate.next(3_000, 1_000)!!, 1e-9)
        assertNull("Zähler zurückgesetzt", rate.next(500, 2_000))
        assertEquals(500.0, rate.next(1_000, 3_000)!!, 1e-9)
        assertNull("TrafficStats.UNSUPPORTED", rate.next(-1, 4_000))
        assertNull(rate.next(2_000, 5_000))
    }

    @Test
    fun networkIsRelativeWithFloor() {
        assertNull(OrbitCore.networkFraction(null, 1e6))
        assertEquals(0.5f, OrbitCore.networkFraction(500_000.0, 1_000_000.0)!!, 1e-6f)
        assertEquals((2_000 / OrbitCore.NETWORK_FLOOR).toFloat(), OrbitCore.networkFraction(2_000.0, 2_000.0)!!, 1e-6f)
        assertEquals(1f, OrbitCore.networkFraction(9e6, 1e6)!!, 0f)
    }

    @Test
    fun ringStatesNeverInventValues() {
        assertEquals(OrbitBasis.UNAVAILABLE, OrbitRingState.of(OrbitRing.MEMORY, null).basis)
        assertEquals(OrbitBasis.UNAVAILABLE, OrbitRingState.of(OrbitRing.MEMORY, Float.NaN).basis)
        assertEquals(1f, OrbitRingState.of(OrbitRing.THERMAL, 1.7f).fraction!!, 0f)
        assertEquals(0.43f, OrbitRingState.of(OrbitRing.STORAGE, 0.4321f).arc, 1e-6f)
        assertEquals(0.435f, OrbitRingState.of(OrbitRing.STORAGE, 0.4337f).arc, 1e-6f)
        assertEquals(0.75f, OrbitCore.memoryFraction(8_000, 2_000)!!, 1e-6f)
        assertNull(OrbitCore.memoryFraction(0, 0))
    }
}
