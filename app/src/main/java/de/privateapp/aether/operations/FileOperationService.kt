package de.privateapp.aether.operations

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import de.privateapp.aether.AetherApp
import de.privateapp.aether.MainActivity
import de.privateapp.aether.R
import de.privateapp.aether.files.OperationTexts
import de.privateapp.aether.model.ByteFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Vordergrunddienst für lange Dateivorgänge: Android beendet die App nicht, solange er läuft, und zeigt den
 * Fortschritt mit „Abbrechen“ in einer Benachrichtigung. Er startet mit dem ersten langen Vorgang und beendet sich,
 * sobald keiner mehr läuft – im Hintergrund tut ORBIT sonst nichts.
 */
class FileOperationService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watcher: Job? = null
    private var lastStartId = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = (application as AetherApp).graph.operations
        lastStartId = startId
        if (intent?.action == ACTION_CANCEL) {
            manager.cancel(intent.getLongExtra(EXTRA_JOB_ID, -1))
        }
        ensureChannel()
        // Android verlangt den Aufruf binnen weniger Sekunden nach dem Start – deshalb sofort, mit dem aktuellen Stand.
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(manager.jobs.value), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } catch (e: RuntimeException) {
            // Z. B. Android 15+: Tageskontingent für „dataSync“ aufgebraucht (ForegroundServiceStartNotAllowedException).
            // Der Vorgang läuft in der App weiter, nur ohne Dienst – also beenden statt abzustürzen.
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (manager.jobs.value.isEmpty()) {
            // Nichts (mehr) zu tun – z. B. „Abbrechen“ aus der Benachrichtigung kam nach dem Ende des Vorgangs.
            stopForegroundAndSelf()
            return START_NOT_STICKY
        }
        if (watcher == null) {
            watcher = scope.launch {
                manager.jobs.collect { jobs ->
                    if (jobs.isEmpty()) {
                        stopForegroundAndSelf()
                    } else {
                        notifyIfAllowed(buildNotification(jobs))
                    }
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+: Zeitlimit für „dataSync“ erreicht (6 Stunden je Tag). Laufende Vorgänge werden sauber abgebrochen.
        val manager = (application as AetherApp).graph.operations
        manager.jobs.value.forEach { manager.cancel(it.id) }
        stopForegroundAndSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    /**
     * Beendet den Dienst nur, wenn seit dem letzten Start kein neuer Startauftrag kam ([stopSelfResult] mit der
     * letzten Start-ID). Sonst könnte ein gerade erst angestoßener Start ins Leere laufen – Android wertet das als
     * „Dienst hat startForeground nicht aufgerufen“.
     */
    private fun stopForegroundAndSelf() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        if (stopSelfResult(lastStartId)) {
            watcher?.cancel()
            watcher = null
        }
    }

    private fun ensureChannel() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Dateivorgänge", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Fortschritt beim Kopieren, Verschieben, Komprimieren und Löschen"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun notifyIfAllowed(notification: android.app.Notification) {
        val nmc = NotificationManagerCompat.from(this)
        if (!nmc.areNotificationsEnabled()) return
        try {
            nmc.notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            // Benachrichtigungen nicht erlaubt – der Vorgang läuft trotzdem weiter.
        }
    }

    private fun buildNotification(jobs: List<OperationJob>): android.app.Notification {
        val active = jobs
        val current = active.firstOrNull { it.status != JobStatus.QUEUED } ?: active.firstOrNull()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_files)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        if (current == null) {
            return builder.setContentTitle("Dateivorgänge").setContentText("Wird abgeschlossen …").build()
        }
        builder.setContentTitle(current.title)
        val p = current.progress
        val text = when {
            current.status == JobStatus.WAITING_FOR_DECISION -> "Entscheidung nötig – in ORBIT öffnen"
            current.status == JobStatus.QUEUED -> "Wartet"
            p == null -> "Wird vorbereitet …"
            p.totalBytes > 0 -> "${ByteFormat.format(p.completedBytes)} von ${ByteFormat.format(p.totalBytes)}"
            p.totalItems > 0 -> OperationTexts.progressItems(p.completedItems, p.totalItems)
            else -> p.phase.label
        }
        val queued = active.size - 1
        builder.setContentText(if (queued > 0) "$text · danach $queued weitere" else text)
        val fraction = p?.fraction
        if (current.status == JobStatus.RUNNING && fraction != null) {
            builder.setProgress(1000, (fraction * 1000).toInt(), false)
        } else if (current.status != JobStatus.WAITING_FOR_DECISION) {
            builder.setProgress(0, 0, true)
        }
        val cancel = PendingIntent.getService(
            this,
            current.id.toInt(),
            Intent(this, FileOperationService::class.java).setAction(ACTION_CANCEL).putExtra(EXTRA_JOB_ID, current.id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        builder.addAction(0, "Abbrechen", cancel)
        return builder.build()
    }

    companion object {
        private const val CHANNEL_ID = "file_operations"
        private const val NOTIFICATION_ID = 41
        private const val ACTION_CANCEL = "de.privateapp.aether.action.CANCEL_OPERATION"
        private const val EXTRA_JOB_ID = "job"
    }
}
