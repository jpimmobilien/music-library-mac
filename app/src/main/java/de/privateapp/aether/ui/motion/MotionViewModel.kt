package de.privateapp.aether.ui.motion

import android.content.Context
import android.os.SystemClock
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.derived
import de.privateapp.aether.model.motion.Altitude
import de.privateapp.aether.model.motion.ClimbSource
import de.privateapp.aether.model.motion.CompassInterpreter
import de.privateapp.aether.model.motion.Course
import de.privateapp.aether.model.motion.GnssInterpreter
import de.privateapp.aether.model.motion.GpsFix
import de.privateapp.aether.model.motion.Heading
import de.privateapp.aether.model.motion.LocationAccess
import de.privateapp.aether.model.motion.LocationPermission
import de.privateapp.aether.model.motion.PositionInterpreter
import de.privateapp.aether.model.motion.PressureInterpreter
import de.privateapp.aether.model.motion.SatelliteSummary
import de.privateapp.aether.model.motion.SessionStats
import de.privateapp.aether.model.motion.SessionTracker
import de.privateapp.aether.model.motion.Smoothed
import de.privateapp.aether.model.motion.Speed
import de.privateapp.aether.model.unavailable
import de.privateapp.aether.model.valueOrNull
import de.privateapp.aether.platform.device.motion.GeoPoint
import de.privateapp.aether.platform.device.motion.GnssUpdate
import de.privateapp.aether.platform.device.motion.GpsUpdate
import de.privateapp.aether.platform.device.motion.LocationSource
import de.privateapp.aether.platform.device.motion.PressureSample
import de.privateapp.aether.platform.device.motion.SensorSource
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** GPS-Empfang für die Hauptanzeige. */
enum class GpsPhase {
    /** GPS nicht nutzbar (keine Freigabe, Standort aus oder kein Empfänger) – siehe [MotionState.access]. */
    BLOCKED,

    /** Freigegeben, aber noch keine Position. */
    SEARCHING,
    LIVE,

    /** Letzte Position ist älter als [PositionInterpreter.STALE_AFTER_MILLIS] (z. B. im Tunnel, im Gebäude). */
    STALE,
}

data class SatelliteState(
    /** `null`, solange der Empfänger noch nichts gemeldet hat. */
    val summary: SatelliteSummary?,
    val timeToFirstFixMillis: Long?,
    val hardwareName: String?,
    /** Einzelne Signale (Richtung, Höhe, Stärke) für den Sensor-Globus; leer, solange nichts gemeldet ist. */
    val signals: List<de.privateapp.aether.model.motion.SatelliteSignal> = emptyList(),
)

/** Alles außer dem Kompass (der meldet viel häufiger und hat einen eigenen Zustand). */
data class MotionState(
    val access: LocationAccess,
    val phase: GpsPhase,
    /** Letzte Position (auch veraltet), `null` solange keine vorliegt oder GPS gesperrt ist. */
    val fix: GpsFix?,
    val fixAgeMillis: Long?,
    /** Seit wann gesucht wird (monotone Uhr), für „seit 12 s“. */
    val searchingForMillis: Long?,
    val speed: Reading<Speed>,
    val course: Reading<Course>,
    val msl: Reading<Altitude>,
    val ellipsoid: Reading<Altitude>,
    val horizontalAccuracy: Reading<Float>,
    val satellites: SatelliteState,
    val hasBarometer: Boolean,
    val barometerName: String?,
    val pressureHPa: Reading<Double>,
    /** Geglättete Druckhöhe. */
    val pressureAltitude: Reading<Double>,
    val session: SessionStats,
)

sealed interface CompassState {
    data object Pending : CompassState

    data object NoSensor : CompassState

    data class Live(val heading: Heading) : CompassState
}

/**
 * Live-Werte der Seite „Bewegung“. Alle Sensoren und GPS laufen nur, solange die Seite angezeigt wird
 * (WhileSubscribed): Verlässt man sie, schaltet Android GPS nach 5 Sekunden ab – keine Ortung im Hintergrund.
 */
class MotionViewModel(context: Context) : ViewModel() {
    private val location = LocationSource(context)
    private val sensors = SensorSource(context)
    private val climbSource = if (sensors.hasBarometer) ClimbSource.BAROMETER else ClimbSource.GPS

    // Ändern sich nicht – einmal lesen statt bei jeder Meldung (Systemaufruf).
    private val gnssHardwareName = location.gnssHardwareName
    private val barometerName = sensors.barometerName

    private val access = MutableStateFlow(location.access())
    private val raw = MutableStateFlow(Raw())
    private val session = MutableStateFlow(SessionTracker.start(climbSource))

    private data class Raw(
        val fix: GpsFix? = null,
        val gnss: GnssUpdate? = null,
        val searchingSinceMillis: Long? = null,
        val pressure: PressureSample? = null,
        val altitude: Smoothed? = null,
        val nowMillis: Long = SystemClock.elapsedRealtime(),
    )

    /** Freigaben und Standort-Schalter neu lesen (beim Zurückkehren auf die Seite, nach der Rückfrage). */
    fun refreshAccess() {
        access.value = location.access()
    }

    /** Messung „seit Beginn“ neu starten. */
    fun resetSession() {
        session.value = SessionTracker.start(climbSource).tick(SystemClock.elapsedRealtime())
    }

    val state: StateFlow<MotionState> = channelFlow {
        launch { location.locationSettingChanges().collect { refreshAccess() } }
        launch {
            access.map { it.canUseGps }.distinctUntilChanged().collectLatest { usable ->
                if (!usable) {
                    raw.update { it.copy(fix = null, gnss = null, searchingSinceMillis = null) }
                    return@collectLatest
                }
                val now = SystemClock.elapsedRealtime()
                // Eine alte Position (Seite war nicht sichtbar) nicht als „Signal verloren“ zeigen – es wird neu gesucht.
                // Satellitenstand und Startzeit stammen vom vorigen Lauf des Empfängers – neu abwarten.
                raw.update { r -> r.copy(searchingSinceMillis = now, fix = r.fix?.takeUnless { PositionInterpreter.isStale(it, now) }, gnss = null) }
                coroutineScope {
                    launch {
                        location.gpsUpdates().collect { update ->
                            when (update) {
                                is GpsUpdate.Fix -> onFix(update.fix)
                                is GpsUpdate.ProviderEnabled -> refreshAccess()
                            }
                        }
                    }
                    launch { location.gnssUpdates().collect { g -> raw.update { it.copy(gnss = g) } } }
                }
            }
        }
        launch { sensors.pressure().collect { onPressure(it) } }
        launch {
            while (true) {
                val now = SystemClock.elapsedRealtime()
                raw.update { it.copy(nowMillis = now) }
                session.update { it.tick(now) }
                delay(1_000L)
            }
        }
        combine(access, raw, session) { a, r, s -> build(a, r, s) }.collect { send(it) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), build(access.value, raw.value, session.value))

    /** Missweisung: aus der aktuellen GPS-Position, sonst aus der letzten bekannten Position irgendeines Anbieters. */
    private val declination = combine(
        access,
        raw.map { r -> r.fix?.let { GeoPoint(it.latitude, it.longitude, it.ellipsoidAltitudeMeters ?: 0.0) } }.distinctUntilChanged(),
    ) { a, point ->
        // Auf 0,1° gerundet – die Missweisung ändert sich auf diesen Abständen nicht messbar.
        val p = point ?: if (a.canUseAnyLocation) location.lastKnownPoint() else null
        p?.let { GeoPoint((it.latitude * 10).roundToInt() / 10.0, (it.longitude * 10).roundToInt() / 10.0, it.altitudeMeters.roundToInt().toDouble()) }
    }.distinctUntilChanged().map { p -> p?.let { location.declinationDegrees(it) } }

    val compass: StateFlow<CompassState> =
        if (sensors.compassSensor == null) {
            MutableStateFlow(CompassState.NoSensor)
        } else {
            combine(sensors.compass(), declination) { sample, decl -> CompassState.Live(CompassInterpreter.heading(sample, decl)) }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CompassState.Pending)
        }

    private fun onFix(fix: GpsFix) {
        raw.update { it.copy(fix = fix) }
        session.update { it.withFix(fix, location::distanceMeters) }
    }

    private fun onPressure(sample: PressureSample) {
        val p = PressureInterpreter.pressure(sample.hPa).valueOrNull ?: run {
            raw.update { it.copy(pressure = sample) }
            return
        }
        val altitude = Smoothed.next(raw.value.altitude, PressureInterpreter.pressureAltitudeMeters(p), sample.elapsedRealtimeMillis, PRESSURE_SMOOTHING_MILLIS)
        raw.update { it.copy(pressure = sample, altitude = altitude) }
        session.update { it.withBarometricAltitude(altitude.value) }
    }

    private fun build(a: LocationAccess, r: Raw, s: SessionTracker): MotionState {
        val blocked: Missing? = when {
            !a.hasGps -> Missing.NotReported
            a.permission == LocationPermission.NONE -> Missing.Condition("Standortfreigabe fehlt")
            a.permission == LocationPermission.APPROXIMATE -> Missing.Condition("Braucht „Genauer Standort“")
            !a.servicesEnabled -> Missing.Condition("Standort ist ausgeschaltet")
            else -> null
        }
        val fix = if (blocked == null) r.fix else null
        val now = r.nowMillis.coerceAtLeast(fix?.elapsedRealtimeMillis ?: 0L)
        val phase = when {
            blocked != null -> GpsPhase.BLOCKED
            fix == null -> GpsPhase.SEARCHING
            PositionInterpreter.isStale(fix, now) -> GpsPhase.STALE
            else -> GpsPhase.LIVE
        }
        fun <T> gps(read: (GpsFix) -> Reading<T>): Reading<T> = when {
            blocked != null -> unavailable(blocked)
            fix == null -> unavailable(Missing.Condition("Position wird gesucht …"))
            else -> read(fix)
        }
        val pressure: Reading<Double> = when {
            !sensors.hasBarometer -> unavailable(Missing.NotReported)
            r.pressure == null -> unavailable(Missing.Pending)
            else -> PressureInterpreter.pressure(r.pressure.hPa)
        }
        val pressureAltitude: Reading<Double> = when {
            pressure !is Reading.Value -> pressure
            r.altitude == null -> unavailable(Missing.Pending)
            else -> derived(r.altitude.value, "aus dem Luftdruck (Normatmosphäre, nicht kalibriert)")
        }
        val signals = if (blocked == null) r.gnss?.signals else null
        return MotionState(
            access = a,
            phase = phase,
            fix = fix,
            fixAgeMillis = fix?.let { now - it.elapsedRealtimeMillis },
            searchingForMillis = if (phase == GpsPhase.SEARCHING) r.searchingSinceMillis?.let { (r.nowMillis - it).coerceAtLeast(0L) } else null,
            speed = gps { PositionInterpreter.speed(it, now) },
            course = gps { PositionInterpreter.course(it, now) },
            msl = gps { it.msl },
            ellipsoid = gps { PositionInterpreter.ellipsoidAltitude(it) },
            horizontalAccuracy = gps { PositionInterpreter.horizontalAccuracy(it) },
            satellites = SatelliteState(
                summary = signals?.let { GnssInterpreter.summarize(it) },
                timeToFirstFixMillis = if (blocked == null) r.gnss?.timeToFirstFixMillis else null,
                hardwareName = gnssHardwareName,
                signals = signals.orEmpty(),
            ),
            hasBarometer = sensors.hasBarometer,
            barometerName = barometerName,
            pressureHPa = pressure,
            pressureAltitude = pressureAltitude,
            session = s.stats(),
        )
    }

    private companion object {
        /** Glättung der Druckhöhe: dämpft Sensorrauschen (≈ ±0,5 m), folgt einer Treppe aber in wenigen Sekunden. */
        const val PRESSURE_SMOOTHING_MILLIS = 2_500.0
    }
}
