package de.privateapp.aether.platform.device

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import androidx.core.content.ContextCompat
import de.privateapp.aether.model.device.BatteryInterpreter
import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.device.PowerSource
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * Akku über die systemweite Meldung `ACTION_BATTERY_CHANGED` (ohne Berechtigung). Android sendet sie bei jeder
 * Änderung; die zuletzt gesendete Meldung liegt beim Anmelden sofort vor. Abgemeldet wird, sobald niemand mehr
 * zuhört – im Hintergrund wird nichts überwacht.
 */
class BatteryMonitor(context: Context) {

    private val appContext = context.applicationContext

    fun snapshots(): Flow<BatterySnapshot> = callbackFlow {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                trySend(parse(intent, System.currentTimeMillis()))
            }
        }
        val sticky = ContextCompat.registerReceiver(
            appContext,
            receiver,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        if (sticky != null) trySend(parse(sticky, System.currentTimeMillis()))
        awaitClose { appContext.unregisterReceiver(receiver) }
    }
        .conflate()
        // Android sendet die Meldung auch, wenn sich nur Werte ändern, die ORBIT nicht zeigt.
        .distinctUntilChanged { a, b -> a.copy(observedAtMillis = 0L) == b.copy(observedAtMillis = 0L) }

    companion object {
        /** Deutet die Extras der Akku-Meldung (Regeln in core/model: BatteryInterpreter). */
        fun parse(intent: Intent, now: Long): BatterySnapshot {
            val cycles = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                BatteryInterpreter.cycleCount(intent.getIntExtra(BatteryManager.EXTRA_CYCLE_COUNT, -1))
            } else {
                BatteryInterpreter.cycleCount(null)
            }
            return BatterySnapshot(
                present = intent.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true),
                level = BatteryInterpreter.level(
                    intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1),
                    intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1),
                ),
                status = ChargeStatus.fromAndroid(intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)),
                sources = PowerSource.fromAndroid(intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)),
                health = BatteryInterpreter.health(intent.getIntExtra(BatteryManager.EXTRA_HEALTH, BatteryManager.BATTERY_HEALTH_UNKNOWN)),
                temperatureCelsius = BatteryInterpreter.temperature(intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)),
                voltage = BatteryInterpreter.voltage(intent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, Int.MIN_VALUE)),
                technology = BatteryInterpreter.technology(intent.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY)),
                cycleCount = cycles,
                observedAtMillis = now,
            )
        }
    }
}
