package de.privateapp.aether.files

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/*
 * Führt alle Dateivorgänge aus (Kopieren, Verschieben, Papierkorb, Löschen, Umbenennen, Ordner, ZIP, Text sichern).
 *
 * Verlässlichkeit vor Geschwindigkeit:
 *  - Nichts wird halb geschrieben sichtbar: Neue Dateien entstehen als „<Name>.aether-part“ und werden erst nach
 *    fsync und Prüfung atomar umbenannt. Ersetzt wird erst, wenn die neue Fassung vollständig ist.
 *  - Eine Quelle wird nur gelöscht, wenn ihre Kopie nachweislich gleich ist (SHA-256, erneut gelesen).
 *  - Vor großen Vorgängen wird der freie Platz geprüft; reicht er nicht, passiert gar nichts.
 *  - Abbrechen ist jederzeit möglich (Coroutine abbrechen): Eigene Zwischendateien werden entfernt, Fertiges bleibt,
 *    und der Bericht sagt genau, was passiert ist.
 *
 * Abbruch: [FileOperationEngine.run] gibt auch nach einem Abbruch einen Bericht mit `cancelled = true` zurück, statt
 * die CancellationException weiterzuwerfen. Der Aufrufer kann ihn direkt verwenden (z. B. in einen StateFlow legen);
 * jedes weitere Aussetzen in der abgebrochenen Coroutine wirft dann wie üblich.
 *
 * [onProgress] wird aus einem Hintergrundthread aufgerufen (höchstens etwa alle 100 ms, sofort bei Phasenwechsel und
 * nach jedem Eintrag der obersten Ebene) und muss threadsicher sein, z. B. `MutableStateFlow.value = …`.
 * [ConflictResolver.resolve] darf aussetzen, bis der Nutzer entschieden hat.
 */

/**
 * Dateivorgänge auf echten Pfaden. [layout] ordnet Pfade Speichern zu (Papierkorb, Umbenennen nur innerhalb eines
 * Speichers), [journal] räumt Zwischendateien nach einem Absturz auf, [clock] taktet die Fortschrittsmeldungen,
 * [bufferSize] ist die Blockgröße beim Kopieren.
 */
class FileOperationEngine(
    private val layout: VolumeLayout,
    private val trash: TrashStore,
    private val journal: TempJournal? = null,
    private val clock: () -> Long = System::currentTimeMillis,
    private val bufferSize: Int = 256 * 1024,
) {
    /** Eingriffspunkte für Tests. */
    internal val hooks = EngineHooks()

    private val env = EngineEnv(layout, trash, journal, clock, bufferSize.coerceAtLeast(MIN_BUFFER_SIZE), hooks)

    /** Führt [operation] aus und liefert, was tatsächlich passiert ist. Wirft nicht – auch nicht bei Abbruch. */
    suspend fun run(
        operation: FileOperation,
        resolver: ConflictResolver,
        onProgress: (OperationProgress) -> Unit = {},
    ): OperationReport {
        val ctx = OperationRun(operation, resolver, onProgress, env)
        try {
            withContext(Dispatchers.IO) {
                try {
                    ctx.emit(force = true)
                    execute(ctx)
                    ctx.finished = true
                } catch (e: CancellationException) {
                    ctx.cancelled = true
                } catch (e: Exception) {
                    // Unerwarteter Fehler: melden statt die App zu beenden; Aufräumen folgt.
                    ctx.fail(primaryPath(operation), IoErrors.classify(e), e.toString())
                    ctx.finished = true
                } finally {
                    ctx.cleanup() // blockierend, ohne Aussetzen – läuft also auch nach einem Abbruch vollständig
                }
            }
        } catch (e: CancellationException) {
            // Der Aufrufer wurde abgebrochen, während der Vorgang zurückkehrte.
            if (!ctx.finished) ctx.cancelled = true
        }
        return ctx.report()
    }

    private suspend fun execute(ctx: OperationRun) {
        when (val op = ctx.operation) {
            is FileOperation.Copy -> TransferOperations(ctx).copy(op)
            is FileOperation.Move -> TransferOperations(ctx).move(op)
            is FileOperation.Trash -> TrashOperations(ctx).trash(op)
            is FileOperation.DeletePermanently -> TrashOperations(ctx).deletePermanently(op)
            is FileOperation.Restore -> TrashOperations(ctx).restore(op)
            is FileOperation.DeleteFromTrash -> TrashOperations(ctx).deleteFromTrash(op)
            is FileOperation.Rename -> NameOperations(ctx).rename(op)
            is FileOperation.CreateFolder -> NameOperations(ctx).createFolder(op)
            is FileOperation.Compress -> ArchiveOperations(ctx).compress(op)
            is FileOperation.Extract -> ArchiveOperations(ctx).extract(op)
            is FileOperation.WriteText -> TextWriteOperation(ctx).write(op)
        }
    }

    private fun primaryPath(operation: FileOperation): String = when (operation) {
        is FileOperation.Copy -> operation.targetDir
        is FileOperation.Move -> operation.targetDir
        is FileOperation.Trash -> operation.sources.firstOrNull().orEmpty()
        is FileOperation.DeletePermanently -> operation.sources.firstOrNull().orEmpty()
        is FileOperation.Restore -> operation.items.firstOrNull()?.originalPath.orEmpty()
        is FileOperation.DeleteFromTrash -> operation.items.firstOrNull()?.storedPath.orEmpty()
        is FileOperation.Rename -> operation.source
        is FileOperation.CreateFolder -> operation.parentDir
        is FileOperation.Compress -> operation.targetDir
        is FileOperation.Extract -> operation.archive
        is FileOperation.WriteText -> operation.path
    }

    private companion object {
        const val MIN_BUFFER_SIZE = 1024
    }
}
