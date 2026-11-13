package de.privateapp.aether.platform.device

import android.content.Context
import android.os.PowerManager
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.device.ThermalHeadroom
import de.privateapp.aether.model.device.ThermalInterpreter
import de.privateapp.aether.model.device.ThermalSnapshot
import de.privateapp.aether.model.unavailable
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Thermalstatus (`PowerManager.addThermalStatusListener`) und thermische Reserve
 * (`PowerManager.getThermalHeadroom`). Der Status kommt als Meldung von Android; die Reserve wird nur
 * abgefragt, solange jemand zuhört – alle [headroomPeriodMillis] (Android erlaubt höchstens eine Abfrage
 * pro Sekunde). Beides läuft auf dem Hauptthread (kurze Systemaufrufe), damit kein Wettlauf entsteht.
 *
 * Das ist keine Temperatur: Android stellt gewöhnlichen Apps keine CPU- oder GPU-Temperatur bereit.
 */
class ThermalMonitor(
    context: Context,
    private val headroomPeriodMillis: Long = 5_000L,
) {
    private val appContext = context.applicationContext

    fun snapshots(): Flow<ThermalSnapshot> = callbackFlow {
        val power = appContext.getSystemService(PowerManager::class.java)
        if (power == null) {
            trySend(ThermalSnapshot(unavailable(Missing.NotReported), unavailable(Missing.NotReported), System.currentTimeMillis()))
            awaitClose { }
            return@callbackFlow
        }
        var level = ThermalInterpreter.level(power.currentThermalStatus)
        var headroom: Reading<ThermalHeadroom> = unavailable(Missing.Pending)
        var lastValidHeadroom: Reading.Value<ThermalHeadroom>? = null
        var lastValidAt = 0L
        var reads = 0

        fun push() {
            trySend(ThermalSnapshot(level, headroom, System.currentTimeMillis()))
        }

        fun readHeadroom() {
            val raw = try {
                power.getThermalHeadroom(0)
            } catch (e: RuntimeException) {
                Float.NaN
            }
            val now = System.currentTimeMillis()
            val r = ThermalInterpreter.headroom(raw, 0)
            reads++
            headroom = when {
                r is Reading.Value -> {
                    lastValidHeadroom = r
                    lastValidAt = now
                    r
                }
                // Einzelne NaN-Antworten (z. B. Abfragegrenze) nicht als Ausfall zeigen, solange der letzte
                // gültige Wert jünger als 20 s ist.
                lastValidHeadroom != null && now - lastValidAt < 20_000L -> lastValidHeadroom
                // Die erste Antwort nach dem Anmelden kann wegen der Abfragegrenze NaN sein – erst nach der zweiten
                // erfolglosen Abfrage (5 s später) heißt es „Nicht verfügbar auf diesem Gerät“.
                lastValidHeadroom == null && reads < 2 -> unavailable(Missing.Pending)
                else -> r
            }
        }

        val listener = PowerManager.OnThermalStatusChangedListener { status ->
            level = ThermalInterpreter.level(status)
            push()
        }
        power.addThermalStatusListener(appContext.mainExecutor, listener)
        readHeadroom()
        push()
        val poller = launch {
            while (isActive) {
                delay(headroomPeriodMillis)
                readHeadroom()
                push()
            }
        }
        awaitClose {
            poller.cancel()
            power.removeThermalStatusListener(listener)
        }
    }.conflate()
}
