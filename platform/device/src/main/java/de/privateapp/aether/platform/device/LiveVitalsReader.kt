package de.privateapp.aether.platform.device

import android.app.ActivityManager
import android.content.Context
import android.net.TrafficStats

/**
 * Schnell wiederholbare Messungen für den ORBIT Core (jede Sekunde, nur solange die Übersicht sichtbar ist):
 *  - Arbeitsspeicher: ActivityManager.MemoryInfo (gesamt / verfügbar) – ohne Berechtigung.
 *  - Netzwerk: TrafficStats, Summe empfangen + gesendet seit dem Gerätestart über alle Schnittstellen – ohne
 *    Berechtigung (ORBIT hat keine Internet-Berechtigung und baut selbst keine Verbindung auf). Meldet ein Gerät
 *    UNSUPPORTED, gibt es keinen Wert.
 * CPU- und GPU-Auslastung des Systems stellt Android normalen Apps seit Android 8 nicht mehr bereit.
 */
class LiveVitalsReader(context: Context) {
    private val activityManager = context.applicationContext.getSystemService(ActivityManager::class.java)

    data class Memory(val totalBytes: Long, val availableBytes: Long, val thresholdBytes: Long, val low: Boolean)

    fun memory(): Memory? = try {
        val am = activityManager ?: return null
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        if (info.totalMem <= 0L) null else Memory(info.totalMem, info.availMem.coerceIn(0L, info.totalMem), info.threshold, info.lowMemory)
    } catch (e: RuntimeException) {
        null
    }

    /** Gesamtzahl übertragener Bytes (empfangen + gesendet) oder `null`, wenn das Gerät sie nicht meldet. */
    fun trafficTotalBytes(): Long? {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        if (rx == TrafficStats.UNSUPPORTED.toLong() || tx == TrafficStats.UNSUPPORTED.toLong() || rx < 0 || tx < 0) return null
        return rx + tx
    }
}
