package de.privateapp.aether.platform.device.motion

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.GeomagneticField
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.LocationRequest
import android.location.altitude.AltitudeConverter
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.motion.Altitude
import de.privateapp.aether.model.motion.GnssConstellation
import de.privateapp.aether.model.motion.GpsFix
import de.privateapp.aether.model.motion.LocationAccess
import de.privateapp.aether.model.motion.LocationPermission
import de.privateapp.aether.model.motion.MslSource
import de.privateapp.aether.model.motion.PositionInterpreter
import de.privateapp.aether.model.motion.SatelliteSignal
import de.privateapp.aether.model.unavailable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.io.IOException

/** Meldung des GPS-Anbieters. */
sealed interface GpsUpdate {
    data class Fix(val fix: GpsFix) : GpsUpdate

    /** Standort wurde in den Einstellungen bzw. im Schnellzugriff ein- oder ausgeschaltet. */
    data class ProviderEnabled(val enabled: Boolean) : GpsUpdate
}

/** Zustand des GNSS-Empfängers laut `GnssStatus.Callback`. */
data class GnssUpdate(
    /** Zuletzt gemeldete Signale; `null`, solange noch keine Meldung kam. */
    val signals: List<SatelliteSignal>?,
    /** Zeit bis zur ersten Position seit dem Einschalten des Empfängers (`onFirstFix`). */
    val timeToFirstFixMillis: Long?,
    val engineRunning: Boolean,
)

/** Punkt für die Berechnung der Missweisung. */
data class GeoPoint(val latitude: Double, val longitude: Double, val altitudeMeters: Double)

/**
 * Standort über den Android-eigenen `LocationManager` (Anbieter „gps“) – ohne Google-Play-Dienste und ohne
 * Netzwerk. Alles läuft nur, solange jemand den jeweiligen Flow sammelt (Seite sichtbar); es gibt keine
 * Hintergrundortung. Die Höhe über dem Meeresspiegel rechnet ab Android 14 `AltitudeConverter` mit dem auf dem
 * Gerät gespeicherten Geoid-Modell um – ohne Internet.
 */
class LocationSource(context: Context) {
    private val appContext = context.applicationContext
    private val manager: LocationManager? = appContext.getSystemService(LocationManager::class.java)

    /** Gerät hat einen GNSS-Empfänger, den Android als Anbieter „gps“ bereitstellt. */
    val hasGps: Boolean =
        appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS) &&
            manager?.hasProvider(LocationManager.GPS_PROVIDER) == true

    /** Hersteller-Bezeichnung des GNSS-Chips, falls Android sie kennt (z. B. „Broadcom BCM4775x …“). */
    val gnssHardwareName: String? get() = manager?.gnssHardwareModelName?.trim()?.takeIf { it.isNotEmpty() }

    /** Altitude-Konverter wird erst beim ersten Bedarf geladen (er liest das Geoid-Modell vom Gerät). */
    private var converter: Any? = null

    fun access(): LocationAccess {
        val fine = granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        val permission = when {
            fine -> LocationPermission.PRECISE
            coarse -> LocationPermission.APPROXIMATE
            else -> LocationPermission.NONE
        }
        return LocationAccess(permission, servicesEnabled = manager?.isLocationEnabled == true, hasGps = hasGps)
    }

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(appContext, permission) == PackageManager.PERMISSION_GRANTED

    /** Meldet, wenn der Standort im System ein- oder ausgeschaltet wird (auch über den Schnellzugriff). */
    @SuppressLint("UnspecifiedRegisterReceiverFlag") // vor Android 13 gibt es die Kennzeichnung nicht; nur Systemmeldungen
    fun locationSettingChanges(): Flow<Unit> = callbackFlow {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                trySend(Unit)
            }
        }
        val filter = IntentFilter().apply {
            addAction(LocationManager.MODE_CHANGED_ACTION)
            addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
        }
        // Beide Meldungen sendet nur das System (geschützte Systemmeldungen). Ab Android 13 zusätzlich ausdrücklich
        // „nicht exportiert“ – Meldungen des Systems kommen trotzdem an, die anderer Apps nicht.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            appContext.registerReceiver(receiver, filter)
        }
        awaitClose { appContext.unregisterReceiver(receiver) }
    }.conflate()

    /**
     * GPS-Positionen etwa jede Sekunde. Endet sofort, wenn die Freigabe „Genauer Standort“ fehlt oder es keinen
     * GPS-Empfänger gibt.
     */
    @SuppressLint("MissingPermission") // geprüft in access(); SecurityException wird zusätzlich abgefangen
    fun gpsUpdates(): Flow<GpsUpdate> = callbackFlow<Location?> {
        val lm = manager
        if (lm == null || !hasGps || access().permission != LocationPermission.PRECISE) {
            close()
            return@callbackFlow
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                trySend(location)
            }

            override fun onProviderEnabled(provider: String) {
                trySend(null)
            }

            override fun onProviderDisabled(provider: String) {
                trySend(null)
            }
        }
        val request = LocationRequest.Builder(UPDATE_INTERVAL_MILLIS)
            .setQuality(LocationRequest.QUALITY_HIGH_ACCURACY)
            .setMinUpdateIntervalMillis(UPDATE_INTERVAL_MILLIS / 2)
            .build()
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, request, appContext.mainExecutor, listener)
        } catch (e: SecurityException) {
            close()
            return@callbackFlow
        } catch (e: IllegalArgumentException) {
            close()
            return@callbackFlow
        }
        awaitClose { lm.removeUpdates(listener) }
    }
        .buffer(capacity = 8, onBufferOverflow = BufferOverflow.DROP_OLDEST)
        .map { location ->
            if (location == null) GpsUpdate.ProviderEnabled(manager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true) else GpsUpdate.Fix(toFix(location))
        }

    /** Satelliten (verlangt „Genauer Standort“). Der Empfänger meldet nur, solange GPS-Positionen angefordert sind. */
    @SuppressLint("MissingPermission") // geprüft in access(); SecurityException wird zusätzlich abgefangen
    fun gnssUpdates(): Flow<GnssUpdate> = callbackFlow {
        val lm = manager
        if (lm == null || !hasGps || access().permission != LocationPermission.PRECISE) {
            close()
            return@callbackFlow
        }
        // Wird nur auf dem Hauptthread verändert (Executor) – kein Wettlauf.
        var state = GnssUpdate(signals = null, timeToFirstFixMillis = null, engineRunning = false)
        val callback = object : GnssStatus.Callback() {
            override fun onStarted() {
                state = state.copy(engineRunning = true)
                trySend(state)
            }

            override fun onStopped() {
                state = state.copy(engineRunning = false)
                trySend(state)
            }

            override fun onFirstFix(ttffMillis: Int) {
                state = state.copy(timeToFirstFixMillis = ttffMillis.toLong())
                trySend(state)
            }

            override fun onSatelliteStatusChanged(status: GnssStatus) {
                state = state.copy(signals = status.toSignals(), engineRunning = true)
                trySend(state)
            }
        }
        val registered = try {
            lm.registerGnssStatusCallback(appContext.mainExecutor, callback)
        } catch (e: SecurityException) {
            false
        }
        if (!registered) {
            close()
            return@callbackFlow
        }
        awaitClose { lm.unregisterGnssStatusCallback(callback) }
    }.conflate()

    /**
     * Jüngste bekannte Position irgendeines Anbieters – nur für die Missweisung (sie ändert sich über Hunderte
     * Kilometer kaum; auch eine ungefähre oder ältere Position genügt). `null` ohne Freigabe.
     */
    @SuppressLint("MissingPermission") // geprüft in access(); SecurityException wird zusätzlich abgefangen
    fun lastKnownPoint(): GeoPoint? {
        val lm = manager ?: return null
        if (!access().canUseAnyLocation) return null
        return try {
            lm.getProviders(true)
                .mapNotNull { lm.getLastKnownLocation(it) }
                .maxByOrNull { it.elapsedRealtimeNanos }
                ?.let { GeoPoint(it.latitude, it.longitude, if (it.hasAltitude()) it.altitude else 0.0) }
        } catch (e: SecurityException) {
            null
        }
    }

    /** Missweisung (Ost positiv) laut Erdmagnetfeld-Modell von Android (World Magnetic Model). */
    fun declinationDegrees(point: GeoPoint, timeMillis: Long = System.currentTimeMillis()): Double =
        GeomagneticField(point.latitude.toFloat(), point.longitude.toFloat(), point.altitudeMeters.toFloat(), timeMillis).declination.toDouble()

    /** Abstand auf dem WGS-84-Ellipsoid (wie Android ihn rechnet). */
    fun distanceMeters(a: GpsFix, b: GpsFix): Double {
        val out = FloatArray(1)
        Location.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude, out)
        return out[0].toDouble()
    }

    private suspend fun toFix(l: Location): GpsFix = GpsFix(
        elapsedRealtimeMillis = l.elapsedRealtimeNanos / 1_000_000L, // getElapsedRealtimeMillis() erst ab Android 13
        latitude = l.latitude,
        longitude = l.longitude,
        horizontalAccuracyMeters = if (l.hasAccuracy()) l.accuracy else null,
        speedMetersPerSecond = if (l.hasSpeed()) l.speed else null,
        speedAccuracyMetersPerSecond = if (l.hasSpeedAccuracy()) l.speedAccuracyMetersPerSecond else null,
        bearingDegrees = if (l.hasBearing()) l.bearing else null,
        bearingAccuracyDegrees = if (l.hasBearingAccuracy()) l.bearingAccuracyDegrees else null,
        ellipsoidAltitudeMeters = if (l.hasAltitude()) l.altitude else null,
        verticalAccuracyMeters = if (l.hasVerticalAccuracy()) l.verticalAccuracyMeters else null,
        msl = msl(l),
        isMock = l.isMock,
    )

    private suspend fun msl(l: Location): Reading<Altitude> = when {
        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> unavailable(Missing.RequiresAndroid(34, "14"))
        else -> mslApi34(l)
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private suspend fun mslApi34(l: Location): Reading<Altitude> {
        if (l.hasMslAltitude()) {
            return PositionInterpreter.msl(l.mslAltitudeMeters, if (l.hasMslAltitudeAccuracy()) l.mslAltitudeAccuracyMeters else null, MslSource.RECEIVER)
        }
        if (!l.hasAltitude()) return unavailable(Missing.Condition("Vom GPS gerade nicht gemeldet"))
        return withContext(Dispatchers.IO) {
            val copy = Location(l)
            try {
                val c = (converter as? AltitudeConverter) ?: AltitudeConverter().also { converter = it }
                c.addMslAltitudeToLocation(appContext, copy)
                if (copy.hasMslAltitude()) {
                    PositionInterpreter.msl(copy.mslAltitudeMeters, if (copy.hasMslAltitudeAccuracy()) copy.mslAltitudeAccuracyMeters else null, MslSource.CONVERTED)
                } else {
                    unavailable(Missing.NotReported)
                }
            } catch (e: IOException) {
                unavailable(Missing.Failed("Höhenmodell von Android nicht lesbar"))
            } catch (e: IllegalArgumentException) {
                unavailable(Missing.Implausible("Position außerhalb des Höhenmodells"))
            }
        }
    }

    private fun GnssStatus.toSignals(): List<SatelliteSignal> = List(satelliteCount) { i ->
        SatelliteSignal(
            constellation = GnssConstellation.fromAndroid(getConstellationType(i)),
            svid = getSvid(i),
            cn0DbHz = getCn0DbHz(i),
            usedInFix = usedInFix(i),
            carrierFrequencyHz = if (hasCarrierFrequencyHz(i)) getCarrierFrequencyHz(i).toDouble() else null,
            elevationDegrees = getElevationDegrees(i),
            azimuthDegrees = getAzimuthDegrees(i),
        )
    }

    private companion object {
        const val UPDATE_INTERVAL_MILLIS = 1_000L
    }
}
