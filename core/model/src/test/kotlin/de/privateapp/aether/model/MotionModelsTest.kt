package de.privateapp.aether.model

import de.privateapp.aether.model.motion.Altitude
import de.privateapp.aether.model.motion.Angles
import de.privateapp.aether.model.motion.Cardinal
import de.privateapp.aether.model.motion.ClimbCounter
import de.privateapp.aether.model.motion.ClimbSource
import de.privateapp.aether.model.motion.CompassAccuracy
import de.privateapp.aether.model.motion.CompassInterpreter
import de.privateapp.aether.model.motion.CompassSample
import de.privateapp.aether.model.motion.CompassSensor
import de.privateapp.aether.model.motion.FrequencyBand
import de.privateapp.aether.model.motion.GnssConstellation
import de.privateapp.aether.model.motion.GnssInterpreter
import de.privateapp.aether.model.motion.GpsFix
import de.privateapp.aether.model.motion.LocationAccess
import de.privateapp.aether.model.motion.LocationPermission
import de.privateapp.aether.model.motion.MotionFormat
import de.privateapp.aether.model.motion.MslSource
import de.privateapp.aether.model.motion.NorthReference
import de.privateapp.aether.model.motion.PositionInterpreter
import de.privateapp.aether.model.motion.PressureInterpreter
import de.privateapp.aether.model.motion.SatelliteSignal
import de.privateapp.aether.model.motion.SessionTracker
import de.privateapp.aether.model.motion.SignalQuality
import de.privateapp.aether.model.motion.Smoothed
import de.privateapp.aether.model.motion.greatCircleMeters
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

class MotionModelsTest {
    private val n = Fmt.NBSP

    // ---------------------------------------------------------------- Satelliten

    private fun sig(c: GnssConstellation, svid: Int, cn0: Float, used: Boolean, mhz: Double? = null) =
        SatelliteSignal(c, svid, cn0, used, mhz?.let { it * 1_000_000.0 }, 30f, 120f)

    @Test
    fun constellationMappingFollowsAndroidConstants() {
        assertEquals(GnssConstellation.UNKNOWN, GnssConstellation.fromAndroid(0))
        assertEquals(GnssConstellation.GPS, GnssConstellation.fromAndroid(1))
        assertEquals(GnssConstellation.SBAS, GnssConstellation.fromAndroid(2))
        assertEquals(GnssConstellation.GLONASS, GnssConstellation.fromAndroid(3))
        assertEquals(GnssConstellation.QZSS, GnssConstellation.fromAndroid(4))
        assertEquals(GnssConstellation.BEIDOU, GnssConstellation.fromAndroid(5))
        assertEquals(GnssConstellation.GALILEO, GnssConstellation.fromAndroid(6))
        assertEquals(GnssConstellation.NAVIC, GnssConstellation.fromAndroid(7))
        assertEquals(GnssConstellation.UNKNOWN, GnssConstellation.fromAndroid(42))
    }

    @Test
    fun frequencyBandsByCarrier() {
        assertEquals(FrequencyBand.L1, FrequencyBand.of(1575.42e6))
        assertEquals(FrequencyBand.L5, FrequencyBand.of(1176.45e6))
        assertEquals(FrequencyBand.G1, FrequencyBand.of(1602.5625e6))
        assertEquals(FrequencyBand.B1I, FrequencyBand.of(1561.098e6))
        assertEquals(FrequencyBand.E5B, FrequencyBand.of(1207.14e6))
        assertEquals(FrequencyBand.OTHER, FrequencyBand.of(1000e6))
    }

    @Test
    fun dualFrequencySignalsCountAsOneSatellite() {
        val s = GnssInterpreter.summarize(
            listOf(
                sig(GnssConstellation.GALILEO, 5, 41f, used = true, mhz = 1575.42),
                sig(GnssConstellation.GALILEO, 5, 37f, used = true, mhz = 1176.45),
                sig(GnssConstellation.GPS, 12, 35f, used = true, mhz = 1575.42),
                sig(GnssConstellation.GPS, 30, 0f, used = false, mhz = 1575.42),
                sig(GnssConstellation.GLONASS, 3, 22f, used = false, mhz = 1602.0),
            ),
        )
        assertEquals(4, s.listed)
        assertEquals(3, s.received)
        assertEquals(2, s.used)
        // GPS vor Galileo vor GLONASS
        assertEquals(listOf(GnssConstellation.GPS, GnssConstellation.GALILEO, GnssConstellation.GLONASS), s.byConstellation.map { it.constellation })
        assertEquals(1, s.byConstellation.first { it.constellation == GnssConstellation.GPS }.received)
        assertEquals(41f, s.strongestCn0DbHz!!, 0.001f)
        assertEquals(38f, s.meanUsedCn0DbHz!!, 0.001f) // (41 + 35) / 2 – je Satellit das stärkste Signal
        assertEquals(SignalQuality.MEDIUM, s.quality)
        assertEquals(true, s.dualFrequency)
        assertTrue(FrequencyBand.L5 in s.bands)
    }

    @Test
    fun withoutFrequenciesDualFrequencyIsUnknownNotFalse() {
        val s = GnssInterpreter.summarize(listOf(sig(GnssConstellation.GPS, 1, 30f, used = true)))
        assertNull(s.dualFrequency)
        val single = GnssInterpreter.summarize(listOf(sig(GnssConstellation.GPS, 1, 30f, used = true, mhz = 1575.42)))
        assertEquals(false, single.dualFrequency)
        assertEquals(0, GnssInterpreter.summarize(emptyList()).listed)
        assertNull(GnssInterpreter.summarize(listOf(sig(GnssConstellation.GPS, 1, 0f, used = false))).strongestCn0DbHz)
    }

    @Test
    fun signalQualityThresholds() {
        assertEquals(SignalQuality.STRONG, SignalQuality.of(40f))
        assertEquals(SignalQuality.MEDIUM, SignalQuality.of(39.9f))
        assertEquals(SignalQuality.MEDIUM, SignalQuality.of(30f))
        assertEquals(SignalQuality.WEAK, SignalQuality.of(29.9f))
    }

    // ---------------------------------------------------------------- Position

    private fun fix(
        t: Long = 1_000L,
        lat: Double = 52.5,
        lon: Double = 13.4,
        acc: Float? = 4f,
        speed: Float? = null,
        speedAcc: Float? = 0.5f,
        bearing: Float? = null,
        alt: Double? = null,
        vAcc: Float? = 3f,
        msl: Reading<Altitude> = unavailable(Missing.RequiresAndroid(34, "14")),
    ) = GpsFix(t, lat, lon, acc, speed, speedAcc, bearing, 3f, alt, vAcc, msl, isMock = false)

    @Test
    fun speedWithinItsOwnAccuracyIsMarkedNotReplaced() {
        val still = (PositionInterpreter.speed(fix(speed = 0.3f, speedAcc = 0.5f), 1_000L) as Reading.Value).value
        assertTrue(still.withinNoise)
        assertFalse(still.moving)
        assertEquals(1.08, still.kmh, 1e-6) // der Messwert bleibt erhalten
        val driving = (PositionInterpreter.speed(fix(speed = 10f, speedAcc = 0.5f), 1_000L) as Reading.Value).value
        assertTrue(driving.moving)
        assertEquals(36.0, driving.kmh, 1e-6)
        assertEquals(1.8, driving.accuracyKmh!!, 1e-6)
        // ohne Genauigkeitsangabe keine Kennzeichnung
        assertFalse((PositionInterpreter.speed(fix(speed = 0.1f, speedAcc = null), 1_000L) as Reading.Value).value.withinNoise)
    }

    @Test
    fun speedMissingImplausibleOrStaleIsNotShown() {
        val missing = PositionInterpreter.speed(fix(speed = null), 1_000L) as Reading.Unavailable
        assertTrue(missing.missing is Missing.Condition)
        assertTrue((PositionInterpreter.speed(fix(speed = 600f), 1_000L) as Reading.Unavailable).missing is Missing.Implausible)
        val stale = PositionInterpreter.speed(fix(t = 1_000L, speed = 5f), 1_000L + PositionInterpreter.STALE_AFTER_MILLIS + 1) as Reading.Unavailable
        assertEquals("Kein aktuelles GPS-Signal", stale.missing.text)
    }

    @Test
    fun courseOnlyWhileMoving() {
        val moving = PositionInterpreter.course(fix(speed = 3f, bearing = 361f), 1_000L) as Reading.Value
        assertEquals(1f, moving.value.degrees, 1e-4f)
        assertEquals(Cardinal.N, moving.value.cardinal)
        assertEquals("Im Stillstand nicht bestimmbar", (PositionInterpreter.course(fix(speed = 0.2f, bearing = 90f), 1_000L) as Reading.Unavailable).missing.text)
        assertEquals("Erst in Bewegung bestimmbar", (PositionInterpreter.course(fix(speed = 3f, bearing = null), 1_000L) as Reading.Unavailable).missing.text)
    }

    @Test
    fun altitudesKeepTheirOrigin() {
        val converted = PositionInterpreter.msl(34.2, 5f, MslSource.CONVERTED) as Reading.Value
        assertEquals(ValueKind.DERIVED, converted.kind)
        assertEquals(ValueKind.REPORTED, (PositionInterpreter.msl(34.2, null, MslSource.RECEIVER) as Reading.Value).kind)
        assertTrue((PositionInterpreter.msl(Double.NaN, null, MslSource.RECEIVER) as Reading.Unavailable).missing is Missing.Implausible)
        assertEquals(81.0, (PositionInterpreter.ellipsoidAltitude(fix(alt = 81.0)) as Reading.Value).value.meters, 1e-9)
        assertTrue(PositionInterpreter.ellipsoidAltitude(fix(alt = null)) is Reading.Unavailable)
    }

    @Test
    fun gpsNeedsPreciseLocationButDeclinationNeedsAnyLocation() {
        assertTrue(LocationAccess(LocationPermission.PRECISE, servicesEnabled = true, hasGps = true).canUseGps)
        assertFalse(LocationAccess(LocationPermission.APPROXIMATE, servicesEnabled = true, hasGps = true).canUseGps)
        assertTrue(LocationAccess(LocationPermission.APPROXIMATE, servicesEnabled = true, hasGps = true).canUseAnyLocation)
        assertFalse(LocationAccess(LocationPermission.PRECISE, servicesEnabled = false, hasGps = true).canUseGps)
        assertFalse(LocationAccess(LocationPermission.PRECISE, servicesEnabled = true, hasGps = false).canUseGps)
        assertFalse(LocationAccess(LocationPermission.NONE, servicesEnabled = true, hasGps = true).canUseAnyLocation)
    }

    // ---------------------------------------------------------------- Kompass

    @Test
    fun anglesWrapAroundNorth() {
        assertEquals(350.0, Angles.normalize(-10.0), 1e-9)
        assertEquals(0.0, Angles.normalize(720.0), 1e-9)
        assertEquals(20.0, Angles.shortestDelta(350.0, 10.0), 1e-9)
        assertEquals(-20.0, Angles.shortestDelta(10.0, 350.0), 1e-9)
        assertEquals(180.0, Angles.shortestDelta(0.0, 180.0), 1e-9)
        // Glättung über 359° → 0° läuft vorwärts (kein Umweg über 180°)
        val smoothed = Angles.smooth(350.0, 10.0, dtMillis = 100, timeConstantMillis = 100.0)
        assertEquals(Angles.normalize(350.0 + 20.0 * (1 - Math.exp(-1.0))), smoothed, 1e-9)
        assertEquals(10.0, Angles.smooth(null, 10.0, 100, 100.0), 1e-9)
    }

    @Test
    fun cardinalSectorsAreCentred() {
        assertEquals(Cardinal.N, Cardinal.of(0.0))
        assertEquals(Cardinal.N, Cardinal.of(22.4))
        assertEquals(Cardinal.NE, Cardinal.of(22.5))
        assertEquals(Cardinal.N, Cardinal.of(337.5))
        assertEquals(Cardinal.NW, Cardinal.of(337.4))
        assertEquals(Cardinal.S, Cardinal.of(180.0))
        assertEquals(Cardinal.SW, Cardinal.of(225.0))
        assertEquals(Cardinal.NW, Cardinal.of(-45.0))
        assertEquals("SW", Cardinal.of(245.0).short)
        assertEquals("Südwesten", Cardinal.of(245.0).long)
    }

    @Test
    fun headingUsesTrueNorthOnlyWithDeclination() {
        val sample = CompassSample(350.0, pitchDegrees = 5.0, rollDegrees = -3.0, headingAccuracyDegrees = 4f, accuracy = CompassAccuracy.HIGH, sensor = CompassSensor.ROTATION_VECTOR)
        val trueNorth = CompassInterpreter.heading(sample, declinationDegrees = 15.0)
        assertEquals(5.0, trueNorth.degrees, 1e-9)
        assertEquals(NorthReference.TRUE, trueNorth.reference)
        assertFalse(trueNorth.tilted)
        val magnetic = CompassInterpreter.heading(sample, declinationDegrees = null)
        assertEquals(350.0, magnetic.degrees, 1e-9)
        assertEquals(NorthReference.MAGNETIC, magnetic.reference)
        assertTrue(CompassInterpreter.heading(sample.copy(pitchDegrees = -80.0), null).tilted)
        assertTrue(CompassAccuracy.fromAndroid(-1).needsCalibration)
        assertTrue(CompassAccuracy.fromAndroid(1).needsCalibration)
        assertFalse(CompassAccuracy.fromAndroid(2).needsCalibration)
        assertEquals(CompassAccuracy.HIGH, CompassAccuracy.fromAndroid(3))
    }

    // ---------------------------------------------------------------- Barometer

    @Test
    fun pressureAltitudeMatchesSensorManagerFormula() {
        assertEquals(0.0, PressureInterpreter.pressureAltitudeMeters(1013.25), 1e-9)
        for (p in listOf(1030f, 1000f, 950f, 900f, 800f, 700f, 500f, 337f)) {
            // SensorManager.getAltitude rechnet in float: 44330 * (1 - (p / p0)^(1 / 5.255))
            val android = 44330.0f * (1.0f - (p / 1013.25f).toDouble().pow((1.0f / 5.255f).toDouble()).toFloat())
            assertEquals("p=$p", android.toDouble(), PressureInterpreter.pressureAltitudeMeters(p.toDouble()), 0.5)
        }
        assertEquals(988.0, PressureInterpreter.pressureAltitudeMeters(900.0), 1.0)
        assertTrue((PressureInterpreter.pressure(50f) as Reading.Unavailable).missing is Missing.Implausible)
        val alt = PressureInterpreter.pressureAltitude(PressureInterpreter.pressure(1013.25f)) as Reading.Value
        assertEquals(ValueKind.DERIVED, alt.kind)
    }

    @Test
    fun smoothingIsTimeBased() {
        val a = Smoothed.next(null, 10.0, 0L, 1000.0)
        assertEquals(10.0, a.value, 1e-9)
        val b = a.next(20.0, 1000L, 1000.0)
        assertEquals(10.0 + 10.0 * (1 - Math.exp(-1.0)), b.value, 1e-9)
        assertEquals(b, b.next(99.0, 1000L, 1000.0)) // gleiche Zeit: keine Änderung
    }

    // ---------------------------------------------------------------- Messung seit dem Start

    /** Breitengrad-Versatz für [meters] nach Norden. */
    private fun north(meters: Double) = meters / 111_195.0

    @Test
    fun standingStillCollectsNoDistance() {
        var s = SessionTracker.start(ClimbSource.GPS)
        val jitter = listOf(0.0, 3.0, -2.5, 1.0, -3.0, 2.0, 0.5, -1.5)
        jitter.forEachIndexed { i, m -> s = s.withFix(fix(t = 1_000L * i, lat = 52.5 + north(m), acc = 8f, speed = 0.2f, speedAcc = 0.6f)) }
        assertEquals(0.0, (s.stats().distanceMeters as Reading.Value).value, 1e-9)
        assertTrue(s.stats().maxSpeed is Reading.Unavailable)
        assertEquals(0L, s.movingMillis)
    }

    @Test
    fun walkingNorthMeasuresDistanceWithoutOvercounting() {
        var s = SessionTracker.start(ClimbSource.GPS)
        for (i in 0..100) s = s.withFix(fix(t = 1_000L * i, lat = 52.5 + north(i.toDouble()), acc = 4f, speed = 1.0f, speedAcc = 0.3f))
        val d = (s.stats().distanceMeters as Reading.Value).value
        assertTrue("d=$d", d in 95.0..100.5)
        assertEquals(100_000L, s.movingMillis)
        val avg = (s.stats().averageMovingSpeedMetersPerSecond as Reading.Value).value
        assertTrue("avg=$avg", avg in 0.95..1.01)
        assertEquals(1.0f, (s.stats().maxSpeed as Reading.Value).value.metersPerSecond, 1e-6f)
    }

    @Test
    fun inaccurateFixesAndJumpsAreIgnored() {
        var s = SessionTracker.start(ClimbSource.GPS)
        s = s.withFix(fix(t = 0, acc = 60f, speed = 30f))
        assertTrue(s.stats().distanceMeters is Reading.Unavailable) // keine genaue Position
        assertTrue(s.stats().maxSpeed is Reading.Unavailable)
        s = s.withFix(fix(t = 1_000, acc = 4f))
        s = s.withFix(fix(t = 2_000, lat = 52.5 + north(5_000.0), acc = 4f)) // 5 km in 1 s
        assertEquals(0.0, (s.stats().distanceMeters as Reading.Value).value, 1e-9)
        // unsichere Geschwindigkeit zählt nicht als Höchstwert
        s = s.withFix(fix(t = 3_000, speed = 20f, speedAcc = 9f))
        assertTrue(s.stats().maxSpeed is Reading.Unavailable)
    }

    @Test
    fun climbCounterIgnoresNoiseBelowThreshold() {
        var c = ClimbCounter(2.0)
        for (h in listOf(100.0, 101.0, 99.5, 101.5, 100.2)) c = c.add(h)
        assertEquals(0.0, c.ascentMeters, 1e-9)
        assertEquals(0.0, c.descentMeters, 1e-9)
        for (h in listOf(102.0, 104.0, 106.0, 110.0, 104.0)) c = c.add(h)
        assertEquals(10.0, c.ascentMeters, 1e-9)
        assertEquals(6.0, c.descentMeters, 1e-9)
    }

    @Test
    fun barometricClimbAndAltitudeChange() {
        var s = SessionTracker.start(ClimbSource.BAROMETER)
        assertTrue(s.stats().ascentMeters is Reading.Unavailable)
        for (h in listOf(50.0, 50.5, 53.0, 56.0, 55.5)) s = s.withBarometricAltitude(h)
        val st = s.stats()
        assertEquals(6.0, (st.ascentMeters as Reading.Value).value, 1e-9)
        assertEquals(5.5, (st.altitudeChangeMeters as Reading.Value).value, 1e-9)
        // GPS-Höhe wird bei Barometer-Messung nicht zusätzlich gezählt
        s = s.withFix(fix(alt = 500.0, vAcc = 2f))
        assertEquals(6.0, (s.stats().ascentMeters as Reading.Value).value, 1e-9)
        // GPS-Sitzung: nur Höhen mit ausreichender vertikaler Genauigkeit
        var g = SessionTracker.start(ClimbSource.GPS)
        g = g.withFix(fix(t = 0, alt = 100.0, vAcc = 30f)).withFix(fix(t = 1000, alt = 140.0, vAcc = 30f))
        assertTrue(g.stats().ascentMeters is Reading.Unavailable)
        g = g.withFix(fix(t = 2000, alt = 100.0, vAcc = 4f)).withFix(fix(t = 3000, alt = 107.0, vAcc = 4f))
        assertEquals(7.0, (g.stats().ascentMeters as Reading.Value).value, 1e-9)
    }

    @Test
    fun gpsClimbNeverMixesHeightReferences() {
        val msl = { m: Double -> PositionInterpreter.msl(m, 3f, MslSource.CONVERTED) }
        var g = SessionTracker.start(ClimbSource.GPS)
        // Meereshöhe kommt und geht – gezählt wird durchgehend die Ellipsoid-Höhe
        g = g.withFix(fix(t = 0, alt = 140.0, vAcc = 4f, msl = msl(95.0)))
        g = g.withFix(fix(t = 1_000, alt = 141.0, vAcc = 4f))
        g = g.withFix(fix(t = 2_000, alt = 148.0, vAcc = 4f, msl = msl(103.0)))
        assertEquals(8.0, (g.stats().ascentMeters as Reading.Value).value, 1e-9)
        assertEquals(0.0, (g.stats().descentMeters as Reading.Value).value, 1e-9)
        // Fehlt die Ellipsoid-Höhe, wird auf Meereshöhe gewechselt – ohne 45-m-Sprung als Abstieg
        g = g.withFix(fix(t = 3_000, alt = null, vAcc = 4f, msl = msl(103.0)))
        assertEquals(0.0, (g.stats().descentMeters as Reading.Value).value, 1e-9)
        g = g.withFix(fix(t = 4_000, alt = null, vAcc = 4f, msl = msl(110.0)))
        assertEquals(15.0, (g.stats().ascentMeters as Reading.Value).value, 1e-9)
        // Änderung seit Beginn: 8 m (Ellipsoid) + 7 m (Meereshöhe), der Bezugswechsel selbst zählt nicht
        assertEquals(15.0, (g.stats().altitudeChangeMeters as Reading.Value).value, 1e-9)
        // und zurück zur Ellipsoid-Höhe: wieder kein Sprung
        g = g.withFix(fix(t = 5_000, alt = 155.0, vAcc = 4f, msl = msl(110.0)))
        assertEquals(15.0, (g.stats().ascentMeters as Reading.Value).value, 1e-9)
        assertEquals(0.0, (g.stats().descentMeters as Reading.Value).value, 1e-9)
        assertEquals(15.0, (g.stats().altitudeChangeMeters as Reading.Value).value, 1e-9)
    }

    @Test
    fun averageMovingSpeedUsesOnlyMovingIntervals() {
        var s = SessionTracker.start(ClimbSource.GPS)
        var t = 0L
        var meters = 0.0
        // 100 s Schleichen mit 0,4 m/s (unter der Bewegungsgrenze): Strecke wächst, Zeit in Bewegung nicht
        repeat(101) {
            s = s.withFix(fix(t = t, lat = 52.5 + north(meters), acc = 4f, speed = 0.4f, speedAcc = 0.2f))
            t += 1_000L
            meters += 0.4
        }
        assertTrue((s.stats().distanceMeters as Reading.Value).value > 30.0)
        assertEquals(0L, s.movingMillis)
        assertTrue(s.stats().averageMovingSpeedMetersPerSecond is Reading.Unavailable)
        // danach 20 s mit 2 m/s
        repeat(21) {
            s = s.withFix(fix(t = t, lat = 52.5 + north(meters), acc = 4f, speed = 2f, speedAcc = 0.3f))
            t += 1_000L
            meters += 2.0
        }
        assertEquals(20_000L, s.movingMillis)
        // früher: (≈ 40 m + 40 m) / 20 s ≈ 4 m/s – jetzt genau die Geschwindigkeit während der Bewegung
        assertEquals(2.0, (s.stats().averageMovingSpeedMetersPerSecond as Reading.Value).value, 1e-9)
    }

    @Test
    fun pausesDoNotCountAsMeasuringTimeOrDistance() {
        var s = SessionTracker.start(ClimbSource.BAROMETER)
        s = s.tick(0).tick(1_000).tick(2_000)
        s = s.withFix(fix(t = 2_000, acc = 4f)).withBarometricAltitude(100.0)
        // Seite 10 Minuten nicht sichtbar: 3 km weiter, 30 m höher
        s = s.tick(602_000).tick(603_000)
        s = s.withFix(fix(t = 603_000, lat = 52.5 + north(3_000.0), acc = 4f)).withBarometricAltitude(130.0)
        assertEquals(3_000L, s.activeMillis)
        assertEquals(0.0, (s.stats().distanceMeters as Reading.Value).value, 1e-9)
        assertEquals(0.0, (s.stats().ascentMeters as Reading.Value).value, 1e-9)
        // „Änderung seit Beginn“ bleibt die echte Differenz zwischen zwei Messungen
        assertEquals(30.0, (s.stats().altitudeChangeMeters as Reading.Value).value, 1e-9)
        // danach wird normal weitergezählt
        s = s.tick(604_000).withFix(fix(t = 604_000, lat = 52.5 + north(3_010.0), acc = 4f)).withBarometricAltitude(133.0)
        assertEquals(10.0, (s.stats().distanceMeters as Reading.Value).value, 0.1)
        assertEquals(3.0, (s.stats().ascentMeters as Reading.Value).value, 1e-9)
    }

    @Test
    fun greatCircleDistance() {
        // 1° Breite ≈ 111,2 km
        assertEquals(111_195.0, greatCircleMeters(fix(lat = 0.0, lon = 0.0), fix(lat = 1.0, lon = 0.0)), 5.0)
    }

    // ---------------------------------------------------------------- Formate

    @Test
    fun motionFormats() {
        assertEquals("4,3", MotionFormat.kmhNumber(4.34))
        assertEquals("52", MotionFormat.kmhNumber(52.4))
        assertEquals("10", MotionFormat.kmhNumber(9.96))
        assertEquals("1.204", MotionFormat.kmhNumber(1204.0))
        assertEquals("±${n}1,2${n}km/h", MotionFormat.kmhAccuracy(1.24))
        assertEquals("820${n}m", MotionFormat.distance(820.0))
        assertEquals("1,00${n}km", MotionFormat.distance(999.6))
        assertEquals("1,24${n}km", MotionFormat.distance(1_240.0))
        assertEquals("12,4${n}km", MotionFormat.distance(12_400.0))
        assertEquals("124${n}km", MotionFormat.distance(124_000.0))
        assertEquals("0°", MotionFormat.degrees(359.6))
        assertEquals("245°", MotionFormat.degrees(245.2))
        assertEquals("−3${n}m", MotionFormat.metersChange(-3.2))
        assertEquals("+12${n}m", MotionFormat.metersChange(12.0))
        assertEquals("±0${n}m", MotionFormat.metersChange(0.3))
        assertEquals("−12", MotionFormat.metersNumber(-12.4))
        assertEquals("±${n}4${n}m", MotionFormat.metersAccuracy(3.8f))
        assertEquals("<${n}1${n}m", MotionFormat.metersAccuracy(0.2f))
        assertEquals("2,9°${n}Ost", MotionFormat.declination(2.94))
        assertEquals("1,4°${n}West", MotionFormat.declination(-1.4))
        assertEquals("1.013,2${n}hPa", MotionFormat.hectopascal(1013.24))
        assertEquals("52,51630°${n}N, 13,37770°${n}O", MotionFormat.coordinates(52.5163, 13.3777))
        assertEquals("33,86880°${n}S, 151,20930°${n}O", MotionFormat.coordinates(-33.8688, 151.2093))
        assertEquals("0:42", MotionFormat.stopwatch(42_000))
        assertEquals("1:03:09", MotionFormat.stopwatch(3_789_000))
        assertEquals("gerade eben", MotionFormat.age(900))
        assertEquals("vor 4${n}s", MotionFormat.age(4_200))
        assertEquals("vor 3${n}Min.", MotionFormat.age(185_000))
        assertEquals("4,2${n}s", MotionFormat.seconds(4_200))
        assertEquals("1${n}Min. 12${n}s", MotionFormat.seconds(72_000))
        assertEquals("38${n}dB-Hz", MotionFormat.dbHz(38.4f))
    }
}
