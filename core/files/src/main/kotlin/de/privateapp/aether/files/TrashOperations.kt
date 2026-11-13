package de.privateapp.aether.files

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.attribute.BasicFileAttributes
import java.nio.file.NoSuchFileException as NioNoSuchFileException

/*
 * Papierkorb und endgültiges Löschen.
 *
 *  - In den Papierkorb: nur atomares Umbenennen auf demselben Speicher (siehe TrashStore). Geht das nicht, bleibt die
 *    Datei, wo sie ist, und der Grund wird gemeldet – es wird nie ersatzweise kopiert oder gelöscht.
 *  - Endgültig löschen: von unten nach oben; jeder Eintrag, der sich nicht löschen lässt, wird einzeln gemeldet, und
 *    sein Ordner bleibt stehen.
 *  - Wiederherstellen: an den ursprünglichen Ort (fehlende Ordner werden neu angelegt); ist der Name dort inzwischen
 *    belegt, bleiben beide erhalten („Foto 2.jpg“) – ohne nachzufragen, weil nichts überschrieben wird.
 *  - Die oberste Ebene eines Speichers kann weder gelöscht noch in den Papierkorb gelegt werden.
 */
internal class TrashOperations(private val ctx: OperationRun) {

    private val env = ctx.env

    private class Item(val file: File, val attrs: BasicFileAttributes, val totals: Totals)

    suspend fun trash(op: FileOperation.Trash) {
        val items = ArrayList<Item>()
        val seen = HashSet<String>()
        for (raw in op.sources) {
            currentCoroutineContext().ensureActive()
            val file = File(Fs.normalize(raw))
            if (!seen.add(file.path)) continue
            val attrs = Fs.attrs(file)
            if (attrs == null) {
                ctx.fail(file.path, FailureReason.NOT_FOUND)
                continue
            }
            val root = env.layout.volumeRootOf(file.path)?.let(Fs::normalize)
            when {
                root == null -> ctx.fail(file.path, FailureReason.TRASH_UNAVAILABLE, "Speicher unbekannt")
                root == file.path -> ctx.fail(file.path, FailureReason.TRASH_UNAVAILABLE, DETAIL_VOLUME_ROOT)
                Fs.isInsideTrash(file.path) -> ctx.fail(file.path, FailureReason.TRASH_UNAVAILABLE, "Liegt bereits im Papierkorb")
                else -> {
                    // Größe vorab, damit der Papierkorb sie ohne erneutes Zählen anzeigen kann.
                    items += Item(file, attrs, ctx.scan(file, attrs))
                    ctx.totalItems++
                }
            }
        }
        ctx.enterPhase(OperationPhase.RUNNING)
        for (item in items) {
            currentCoroutineContext().ensureActive()
            ctx.currentName = item.file.name
            try {
                val trashed = env.trash.moveIn(item.file, item.attrs.isDirectory, item.totals.bytes)
                ctx.trashed(trashed)
                ctx.succeeded++
                ctx.removed(item.file.path)
                ctx.bytesProcessed += item.totals.bytes
            } catch (e: IOException) {
                ctx.fail(item.file.path, trashFailure(e), e.message)
            }
            ctx.addItems(1, force = true)
        }
    }

    suspend fun deletePermanently(op: FileOperation.DeletePermanently) {
        val items = ArrayList<Item>()
        val seen = HashSet<String>()
        for (raw in op.sources) {
            currentCoroutineContext().ensureActive()
            val file = File(Fs.normalize(raw))
            if (!seen.add(file.path)) continue
            val attrs = Fs.attrs(file)
            when {
                attrs == null -> ctx.fail(file.path, FailureReason.NOT_FOUND)
                Fs.isVolumeRoot(env.layout, file.path) ->
                    ctx.fail(file.path, FailureReason.ACCESS_DENIED, DETAIL_VOLUME_ROOT)
                else -> {
                    val totals = ctx.scan(file, attrs)
                    ctx.totalItems += totals.items
                    ctx.totalBytes += totals.bytes
                    items += Item(file, attrs, totals)
                }
            }
        }
        ctx.enterPhase(OperationPhase.RUNNING)
        for (item in items) {
            if (ctx.skipBecauseAborted(item.file.path)) continue
            val before = ctx.completedItems
            val beforeBytes = ctx.completedBytes
            ctx.currentName = item.file.name
            ctx.beginItem()
            val complete = deleteTree(item.file)
            if (complete) {
                ctx.succeeded++
                ctx.removed(item.file.path)
            }
            ctx.endItem(complete)
            ctx.snapTo(before + item.totals.items, beforeBytes + item.totals.bytes)
        }
    }

    suspend fun restore(op: FileOperation.Restore) {
        val located = locateAll(op.items)
        ctx.totalItems = located.size
        ctx.enterPhase(OperationPhase.RUNNING)
        for ((item, place) in located) {
            currentCoroutineContext().ensureActive()
            ctx.currentName = item.name
            restoreOne(item, place)
            ctx.addItems(1, force = true)
        }
    }

    private fun restoreOne(item: TrashedItem, place: TrashStore.Located) {
        val attrs = Fs.attrs(place.stored)
        if (attrs == null) {
            ctx.fail(item.originalPath, FailureReason.NOT_FOUND)
            return
        }
        val original = File(Fs.normalize(item.originalPath))
        val parent = original.parentFile
        if (parent == null) {
            ctx.fail(item.originalPath, FailureReason.IO_ERROR, "Ursprünglicher Ort ungültig")
            return
        }
        try {
            Files.createDirectories(parent.toPath())
        } catch (e: IOException) {
            ctx.fail(item.originalPath, e)
            return
        }
        val finalName = ctx.uniqueIn(parent, original.name, attrs.isDirectory)
        val dest = File(parent, finalName)
        try {
            Fs.renameNoReplace(place.stored, dest)
        } catch (e: IOException) {
            ctx.fail(item.originalPath, if (Fs.isCrossDevice(e)) FailureReason.TRASH_UNAVAILABLE else IoErrors.classify(e), e.message)
            return
        }
        ctx.names.add(parent, finalName)
        env.trash.removeShell(place.itemDir)
        ctx.succeeded++
        ctx.bytesProcessed += item.sizeBytes
        ctx.created(dest.path)
        ctx.removed(place.stored.path)
    }

    suspend fun deleteFromTrash(op: FileOperation.DeleteFromTrash) {
        val located = locateAll(op.items)
        val totals = HashMap<String, Totals>()
        for ((item, place) in located) {
            val attrs = Fs.attrs(place.stored) ?: continue
            val t = ctx.scan(place.stored, attrs)
            totals[item.id] = t
            ctx.totalItems += t.items
            ctx.totalBytes += t.bytes
        }
        ctx.enterPhase(OperationPhase.RUNNING)
        for ((item, place) in located) {
            if (ctx.skipBecauseAborted(item.storedPath)) continue
            val before = ctx.completedItems
            val beforeBytes = ctx.completedBytes
            ctx.currentName = item.name
            // Erst das Objekt, dann die Hülle – bleibt etwas übrig, bleibt der Eintrag im Papierkorb sichtbar.
            ctx.beginItem()
            var complete = false
            if (deleteTree(place.stored)) {
                if (Fs.deleteRecursively(place.itemDir)) {
                    ctx.succeeded++
                    ctx.removed(item.storedPath)
                    complete = true
                } else {
                    ctx.fail(place.itemDir.path, FailureReason.IO_ERROR, "Papierkorb-Eintrag ließ sich nicht entfernen")
                }
            }
            ctx.endItem(complete)
            val t = totals[item.id] ?: Totals(0, 0)
            ctx.snapTo(before + t.items, beforeBytes + t.bytes)
        }
    }

    private fun locateAll(items: List<TrashedItem>): List<Pair<TrashedItem, TrashStore.Located>> {
        val result = ArrayList<Pair<TrashedItem, TrashStore.Located>>()
        val seen = HashSet<String>()
        for (item in items) {
            if (!seen.add(item.volumeRoot + "\u0000" + item.id)) continue
            val place = env.trash.locate(item)
            if (place == null) ctx.fail(item.storedPath, FailureReason.NOT_FOUND) else result += item to place
        }
        return result
    }

    /** Löscht von unten nach oben, ohne Verknüpfungen zu folgen. `true` = vollständig entfernt. */
    private suspend fun deleteTree(file: File): Boolean {
        currentCoroutineContext().ensureActive()
        val attrs = Fs.attrs(file) ?: return true
        if (attrs.isDirectory) {
            val children = try {
                file.listFiles()
            } catch (e: SecurityException) {
                null
            }
            if (children == null) {
                ctx.fail(file.path, FailureReason.ACCESS_DENIED)
                return false
            }
            var all = true
            for (child in children) {
                if (!deleteTree(child)) all = false
            }
            if (!all) return false
        }
        return try {
            Files.delete(file.toPath())
            val size = if (attrs.isRegularFile) attrs.size() else 0L
            ctx.bytesProcessed += size
            ctx.addBytes(size)
            ctx.addItems(1)
            ctx.childRemoved(file.path)
            if (!attrs.isDirectory) ctx.childFileDone()
            true
        } catch (e: NioNoSuchFileException) {
            true
        } catch (e: IOException) {
            ctx.fail(file.path, e)
            false
        }
    }

    private fun trashFailure(e: IOException): FailureReason {
        if (e is TrashUnavailableException || Fs.isCrossDevice(e)) return FailureReason.TRASH_UNAVAILABLE
        val reason = IoErrors.classify(e)
        return if (reason == FailureReason.IO_ERROR) FailureReason.TRASH_UNAVAILABLE else reason
    }

    private companion object {
        const val DETAIL_VOLUME_ROOT = "Die oberste Ebene eines Speichers kann nicht gelöscht werden"
    }
}
