package de.privateapp.aether.platform.device.motion

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.Display
import android.view.Surface
import de.privateapp.aether.model.motion.Angles
import de.privateapp.aether.model.motion.CompassAccuracy
import de.privateapp.aether.model.motion.CompassSample
import de.privateapp.aether.model.motion.CompassSensor
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate

/** Luftdruck in Hektopascal mit dem Zeitpunkt auf der monotonen Uhr. */
data class PressureSample(val hPa: Float, val elapsedRealtimeMillis: Long)

/**
 * Kompass (Lage aus dem Rotationsvektor) und Barometer über den `SensorManager`. Beides braucht keine Berechtigung.
 * Sensoren laufen nur, solange der jeweilige Flow gesammelt wird.
 */
class SensorSource(context: Context) {
    private val appContext = context.applicationContext
    private val manager: SensorManager? = appContext.getSystemService(SensorManager::class.java)
    private val displays: DisplayManager? = appContext.getSystemService(DisplayManager::class.java)

    private val barometer: Sensor? = manager?.getDefaultSensor(Sensor.TYPE_PRESSURE)

    val hasBarometer: Boolean get() = barometer != null

    /** Bezeichnung des Barometers laut Hersteller (z. B. „BMP390 Pressure Sensor · Bosch“). */
    val barometerName: String? get() = barometer?.let { listOf(it.name, it.vendor).filter { s -> s.isNotBlank() }.joinToString(" · ") }

    /** Beste verfügbare Quelle für die Richtung oder `null`, wenn das Gerät keinen Kompass hat. */
    val compassSensor: CompassSensor? = when {
        manager == null -> null
        manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null -> CompassSensor.ROTATION_VECTOR
        manager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) != null -> CompassSensor.GEOMAGNETIC_ROTATION_VECTOR
        manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null && manager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null ->
            CompassSensor.ACCELEROMETER_MAGNETOMETER
        else -> null
    }

    /**
     * Luftdruck etwa einmal pro Sekunde (genügt für Höhenänderungen und spart Strom; Android darf schneller melden).
     * Ohne Barometer endet der Flow sofort.
     */
    fun pressure(): Flow<PressureSample> = callbackFlow {
        val sm = manager
        val sensor = barometer
        if (sm == null || sensor == null) {
            close()
            return@callbackFlow
        }
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                trySend(PressureSample(event.values[0], SystemClock.elapsedRealtime()))
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) = Unit
        }
        sm.registerListener(listener, sensor, PRESSURE_PERIOD_MICROS)
        awaitClose { sm.unregisterListener(listener) }
    }.conflate()

    /**
     * Richtung der Oberkante des Bildschirms gegenüber magnetisch Nord, an die aktuelle Displaydrehung angepasst und
     * leicht geglättet (Zeitkonstante [SMOOTHING_MILLIS]). Läuft auf einem eigenen Thread, nicht auf dem Hauptthread.
     */
    fun compass(): Flow<CompassSample> = callbackFlow {
        val sm = manager
        val kind = compassSensor
        if (sm == null || kind == null) {
            close()
            return@callbackFlow
        }
        val thread = HandlerThread("OrbitKompass").apply { start() }
        val handler = Handler(thread.looper)
        val rotation = FloatArray(9)
        val remapped = FloatArray(9)
        val orientation = FloatArray(3)
        val gravity = FloatArray(3)
        val geomagnetic = FloatArray(3)
        var hasGravity = false
        var headingAccuracy: Float? = null
        var magneticAccuracy: CompassAccuracy? = null
        var smoothed: Double? = null
        var lastAt = 0L

        fun publish() {
            val (axisX, axisY) = axesFor(displays?.getDisplay(Display.DEFAULT_DISPLAY)?.rotation ?: Surface.ROTATION_0)
            if (!SensorManager.remapCoordinateSystem(rotation, axisX, axisY, remapped)) return
            SensorManager.getOrientation(remapped, orientation)
            val azimuth = Math.toDegrees(orientation[0].toDouble())
            if (!azimuth.isFinite()) return
            val now = SystemClock.elapsedRealtime()
            val heading = Angles.smooth(smoothed, azimuth, now - lastAt, SMOOTHING_MILLIS)
            smoothed = heading
            lastAt = now
            trySend(
                CompassSample(
                    magneticAzimuthDegrees = heading,
                    pitchDegrees = Math.toDegrees(orientation[1].toDouble()),
                    rollDegrees = Math.toDegrees(orientation[2].toDouble()),
                    headingAccuracyDegrees = headingAccuracy,
                    accuracy = magneticAccuracy,
                    sensor = kind,
                ),
            )
        }

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                when (event.sensor.type) {
                    Sensor.TYPE_ROTATION_VECTOR, Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR -> {
                        SensorManager.getRotationMatrixFromVector(rotation, event.values)
                        // values[4]: geschätzte Genauigkeit der Richtung in Bogenmaß, −1 = unbekannt
                        headingAccuracy = event.values.getOrNull(4)?.takeIf { it >= 0f }?.let { Math.toDegrees(it.toDouble()).toFloat() }
                        publish()
                    }
                    Sensor.TYPE_ACCELEROMETER -> {
                        // Tiefpass: Schwerkraft von kurzen Bewegungen trennen
                        for (i in 0..2) gravity[i] = if (hasGravity) gravity[i] + 0.2f * (event.values[i] - gravity[i]) else event.values[i]
                        hasGravity = true
                    }
                    Sensor.TYPE_MAGNETIC_FIELD -> {
                        System.arraycopy(event.values, 0, geomagnetic, 0, 3)
                        if (kind == CompassSensor.ACCELEROMETER_MAGNETOMETER && hasGravity &&
                            SensorManager.getRotationMatrix(rotation, null, gravity, geomagnetic)
                        ) {
                            publish()
                        }
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
                // Kalibrierzustand des Magnetfeldsensors – Grundlage für den Hinweis „Kompass kalibrieren“.
                if (sensor.type == Sensor.TYPE_MAGNETIC_FIELD) magneticAccuracy = CompassAccuracy.fromAndroid(accuracy)
            }
        }

        val delay = SensorManager.SENSOR_DELAY_UI
        when (kind) {
            CompassSensor.ROTATION_VECTOR -> sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let { sm.registerListener(listener, it, delay, handler) }
            CompassSensor.GEOMAGNETIC_ROTATION_VECTOR -> sm.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)?.let { sm.registerListener(listener, it, delay, handler) }
            CompassSensor.ACCELEROMETER_MAGNETOMETER -> sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sm.registerListener(listener, it, delay, handler) }
        }
        // Magnetfeld immer: für die Kalibrierung (und bei der einfachen Variante für die Richtung selbst).
        sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let { sm.registerListener(listener, it, delay, handler) }
        awaitClose {
            sm.unregisterListener(listener)
            thread.quitSafely()
        }
    }.conflate()

    private fun axesFor(rotation: Int): Pair<Int, Int> = when (rotation) {
        Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
        Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
        Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
        else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
    }

    private companion object {
        const val SMOOTHING_MILLIS = 90.0
        const val PRESSURE_PERIOD_MICROS = 1_000_000
    }
}
