package de.privateapp.aether.operations

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import de.privateapp.aether.files.Conflict
import de.privateapp.aether.files.FileOperation
import de.privateapp.aether.files.FileOperationEngine
import de.privateapp.aether.files.OperationProgress
import de.privateapp.aether.files.OperationReport
import de.privateapp.aether.files.OperationTexts
import de.privateapp.aether.files.Resolution
import de.privateapp.aether.files.TrashStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

enum class JobStatus { QUEUED, RUNNING, WAITING_FOR_DECISION }

/** Ein laufender oder wartender Dateivorgang – so, wie ihn Oberfläche und Benachrichtigung anzeigen. */
data class OperationJob(
    val id: Long,
    val operation: FileOperation,
    /** „12 Objekte kopieren“, „„Urlaub“ verschieben“ … */
    val title: String,
    val status: JobStatus,
    val progress: OperationProgress?,
    /** Wartet auf die Entscheidung des Nutzers (Ersetzen, Beide behalten …). */
    val conflict: Conflict?,
)

/**
 * Führt Dateivorgänge nacheinander aus (nie zwei gleichzeitig – so können sich zwei Vorgänge nicht gegenseitig die
 * Dateien wegnehmen, und der Speicher wird nicht doppelt belastet) und hält ihren Stand für die Oberfläche bereit.
 *
 * Lange Vorgänge laufen zusätzlich in einem Vordergrunddienst ([FileOperationService]), damit Android die App nicht
 * beendet, wenn man sie währenddessen verlässt. Nach jedem Vorgang wird der Medienindex von Android abgeglichen.
 */
class OperationManager(
    context: Context,
    private val engine: FileOperationEngine,
    private val afterFinished: suspend (OperationReport) -> Unit,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext
    private val ids = AtomicLong(0)

    private val _jobs = MutableStateFlow<List<OperationJob>>(emptyList())

    /** Alle laufenden und wartenden Vorgänge (älteste zuerst). */
    val jobs: StateFlow<List<OperationJob>> = _jobs.asStateFlow()

    private val _finished = MutableSharedFlow<OperationReport>(extraBufferCapacity = 32)

    /** Jeder abgeschlossene Vorgang (auch abgebrochene) – Bildschirme laden daraufhin neu. */
    val finished: SharedFlow<OperationReport> = _finished.asSharedFlow()

    private val queue = Channel<Long>(Channel.UNLIMITED)
    private val decisions = ConcurrentHashMap<Long, CompletableDeferred<Resolution>>()
    private val running = ConcurrentHashMap<Long, Job>()
    private val autoResolutions = ConcurrentHashMap<Long, Resolution>()

    init {
        scope.launch {
            for (id in queue) {
                val job = _jobs.value.firstOrNull { it.id == id } ?: continue
                if (job.status != JobStatus.QUEUED) continue
                val worker = scope.launch(Dispatchers.IO) { execute(job) }
                running[id] = worker
                worker.join()
                running.remove(id)
            }
        }
    }

    /**
     * Reiht [operation] ein und gibt ihre Kennung zurück. [autoResolution] beantwortet Namenskonflikte ohne
     * Rückfrage (z. B. „Duplizieren“ = immer „Beide behalten“).
     */
    fun submit(operation: FileOperation, autoResolution: Resolution? = null, title: String? = null): Long {
        val id = ids.incrementAndGet()
        if (autoResolution != null) autoResolutions[id] = autoResolution
        val job = OperationJob(id, operation, title ?: OperationTexts.title(operation), JobStatus.QUEUED, null, null)
        _jobs.update { it + job }
        queue.trySend(id)
        if (OperationTexts.mayTakeLong(operation)) startService()
        return id
    }

    fun cancel(id: Long) {
        decisions.remove(id)?.cancel()
        val worker = running[id]
        if (worker != null) {
            worker.cancel()
            return
        }
        // Noch nicht begonnen: ohne jede Änderung beenden.
        val job = _jobs.value.firstOrNull { it.id == id && it.status == JobStatus.QUEUED } ?: return
        val report = OperationReport(job.operation, 0, 0, emptyList(), cancelled = true, bytesProcessed = 0, createdPaths = emptyList(), removedPaths = emptyList())
        finish(id)
        scope.launch { _finished.emit(report) }
    }

    fun decide(id: Long, resolution: Resolution) {
        decisions.remove(id)?.complete(resolution)
    }

    val hasActive: Boolean get() = _jobs.value.isNotEmpty()

    private suspend fun execute(job: OperationJob) {
        val id = job.id
        update(id) { it.copy(status = JobStatus.RUNNING) }
        var lastEmit = 0L
        val report = engine.run(
            job.operation,
            resolver = { conflict ->
                autoResolutions[id]?.let { return@run it }
                val decision = CompletableDeferred<Resolution>()
                decisions[id] = decision
                update(id) { it.copy(status = JobStatus.WAITING_FOR_DECISION, conflict = conflict) }
                try {
                    decision.await()
                } finally {
                    decisions.remove(id)
                    update(id) { it.copy(status = JobStatus.RUNNING, conflict = null) }
                }
            },
            onProgress = { progress ->
                // Höchstens zehnmal je Sekunde neu zeichnen; Phasenwechsel und Abschluss immer.
                val now = System.nanoTime()
                val phaseChanged = _jobs.value.firstOrNull { it.id == id }?.progress?.phase != progress.phase
                if (phaseChanged || now - lastEmit > 100_000_000L || progress.completedItems == progress.totalItems) {
                    lastEmit = now
                    update(id) { it.copy(progress = progress) }
                }
            },
        )
        autoResolutions.remove(id)
        withContext(NonCancellable) {
            // Erst abschließen und melden (Fortschritt verschwindet, Ordner laden neu, „Widerrufen“ erscheint), dann im
            // Hintergrund nachziehen – der Abgleich des Medienindex kann bei großen Ordnern Sekunden dauern und soll
            // weder die Anzeige noch den nächsten Vorgang aufhalten.
            finish(id)
            _finished.emit(report)
        }
        scope.launch(Dispatchers.IO) {
            try {
                afterFinished(report)
            } catch (e: Exception) {
                // Medienindex/Einstellungen nachziehen ist Komfort – der Vorgang selbst ist abgeschlossen.
            }
        }
    }

    /**
     * Fertige Vorgänge verlassen die Liste sofort – ihr Ergebnis geht über [finished] an die Oberfläche (Rückmeldung).
     * So wächst die Liste nicht mit jedem Vorgang einer langen Sitzung (Berichte können Tausende Pfade enthalten).
     */
    private fun finish(id: Long) {
        _jobs.update { list -> list.filterNot { it.id == id } }
    }

    private inline fun update(id: Long, crossinline transform: (OperationJob) -> OperationJob) {
        _jobs.update { list -> list.map { if (it.id == id) transform(it) else it } }
    }

    private fun startService() {
        try {
            ContextCompat.startForegroundService(appContext, Intent(appContext, FileOperationService::class.java))
        } catch (e: IllegalStateException) {
            // Android erlaubt den Dienst gerade nicht (App im Hintergrund) – der Vorgang läuft trotzdem in der App.
        } catch (e: SecurityException) {
            // dito
        }
    }

    companion object {
        /** Pfade im Papierkorb von ORBIT gehören nicht in den Medienindex. */
        fun indexable(paths: Collection<String>): List<String> = paths.filterNot { "/${TrashStore.DIR_NAME}/" in it || it.endsWith("/${TrashStore.DIR_NAME}") }
    }
}
