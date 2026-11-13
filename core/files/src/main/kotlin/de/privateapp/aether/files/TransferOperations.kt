package de.privateapp.aether.files

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.attribute.BasicFileAttributes
import java.security.MessageDigest
import java.nio.file.FileAlreadyExistsException as NioFileAlreadyExistsException

/*
 * Kopieren und Verschieben.
 *
 * Kopieren einer Datei:  <Name>.aether-part anlegen (im Journal) → blockweise schreiben → fsync → Größe prüfen →
 *                        Änderungszeit übernehmen → atomar in den endgültigen Namen umbenennen.
 *                        Beim Ersetzen wird das Vorhandene erst angetastet, wenn die neue Fassung vollständig ist.
 * Verschieben, gleicher Speicher:      atomares Umbenennen – sofort, ohne Kopie, ohne zusätzlichen Platz.
 * Verschieben, anderer Speicher:       Kopie mit SHA-256 beim Schreiben → fsync → Kopie erneut lesen und vergleichen
 *                                      → Original prüfen (unverändert?) → erst dann das Original löschen.
 *                                      Ordner werden von unten nach oben entfernt – nur, wenn alles darin angekommen ist.
 * Verknüpfungen und Sonderdateien werden nie übertragen (gemeldet), versteckte Dateien schon, Dateien von ORBIT nie.
 */
internal class TransferOperations(private val ctx: OperationRun) {

    private val env = ctx.env

    private class Source(val file: File, val attrs: BasicFileAttributes, var totals: Totals, var crossVolume: Boolean = false)

    // ---- Kopieren ----------------------------------------------------------------------------------------------

    suspend fun copy(op: FileOperation.Copy) {
        val target = ctx.targetDirectory(op.targetDir) ?: return
        val sources = prepare(op.sources, target, scan = true, refuseVolumeRoot = false)
        if (!ctx.hasSpace(target, sources.sumOf { it.totals.bytes })) return
        ctx.enterPhase(OperationPhase.RUNNING)
        for (source in sources) {
            if (ctx.skipBecauseAborted(source.file.path)) continue
            val items = ctx.completedItems
            val bytes = ctx.completedBytes
            val problemsBefore = ctx.problems
            ctx.beginItem()
            val outcome = copyEntry(source.file, source.attrs, target, topLevel = true)
            account(source, outcome, problemsBefore, isMove = false)
            ctx.snapTo(items + source.totals.items, bytes + source.totals.bytes)
        }
    }

    private suspend fun copyEntry(src: File, attrs: BasicFileAttributes, destDir: File, topLevel: Boolean): Outcome {
        if (ctx.abortReason != null) return Outcome.Failed
        currentCoroutineContext().ensureActive()
        ctx.currentName = src.name
        if (!transferable(src, attrs)) return Outcome.Failed
        var finalName = src.name
        var replaceTarget: File? = null
        var mergeInto: File? = null
        val conflict = if (topLevel && Fs.sameDirectory(src.parentFile, destDir)) {
            // Kopie im selben Ordner = Duplikat („Foto 2.jpg“), ohne nachzufragen.
            ctx.names.lookup(destDir, src.name)?.let { ConflictChoice.KEEP_BOTH to File(destDir, it) }
        } else {
            ctx.conflictChoice(src, destDir, ConflictRules.TRANSFER)
        }
        if (conflict != null) {
            val (choice, existing) = conflict
            when (choice) {
                ConflictChoice.SKIP -> return Outcome.Skipped
                ConflictChoice.KEEP_BOTH -> finalName = ctx.uniqueIn(destDir, src.name, attrs.isDirectory)
                ConflictChoice.REPLACE -> replaceTarget = existing
                ConflictChoice.MERGE -> mergeInto = existing
            }
        }
        return if (attrs.isDirectory) {
            copyDirectory(src, attrs, destDir, finalName, mergeInto)
        } else {
            copyFile(src, attrs, destDir, finalName, replaceTarget)
        }
    }

    private suspend fun copyDirectory(
        src: File,
        attrs: BasicFileAttributes,
        destDir: File,
        finalName: String,
        mergeInto: File?,
    ): Outcome {
        val dir = mergeInto ?: File(destDir, finalName).also { created ->
            try {
                Files.createDirectory(created.toPath())
            } catch (e: IOException) {
                ctx.fail(src.path, e)
                return Outcome.Failed
            }
            ctx.names.add(destDir, finalName)
            ctx.childCreated(created.path)
        }
        ctx.addItems(1)
        val children = listChildren(src) ?: return Outcome.Placed(dir.path, sourceGone = false)
        for (child in children) {
            if (ctx.abortReason != null) break
            val childAttrs = Fs.attrs(child) ?: continue
            copyEntry(child, childAttrs, dir, topLevel = false)
        }
        if (mergeInto == null) Fs.setModified(dir, Fs.modifiedMillis(attrs))
        return Outcome.Placed(dir.path, sourceGone = false)
    }

    private suspend fun copyFile(
        src: File,
        attrs: BasicFileAttributes,
        destDir: File,
        finalName: String,
        replaceTarget: File?,
    ): Outcome {
        val temp = Fs.tempFileIn(destDir, finalName)
        ctx.registerTemp(temp)
        try {
            val written = FileInputStream(src).use { input ->
                FileOutputStream(temp).use { out ->
                    ctx.pump(input, out, temp).also { out.syncToDisk() }
                }
            }
            if (Fs.attrs(temp)?.size() != written) {
                ctx.discardTemp(temp)
                ctx.fail(src.path, FailureReason.VERIFICATION_FAILED, "Größe der Kopie stimmt nicht")
                return Outcome.Failed
            }
            env.hooks.afterTempWritten?.invoke(temp)
            Fs.setModified(temp, Fs.modifiedMillis(attrs))
            val placed = place(temp, destDir, finalName, replaceTarget)
            ctx.bytesProcessed += written
            ctx.addItems(1)
            ctx.childCreated(placed.path)
            ctx.childFileDone()
            return Outcome.Placed(placed.path, sourceGone = false)
        } catch (e: IOException) {
            ctx.discardTemp(temp)
            ctx.fail(src.path, e)
            return Outcome.Failed
        }
    }

    // ---- Verschieben -------------------------------------------------------------------------------------------

    suspend fun move(op: FileOperation.Move) {
        val target = ctx.targetDirectory(op.targetDir) ?: return
        val sources = prepare(op.sources, target, scan = false, refuseVolumeRoot = true)
        var needed = 0L
        for (source in sources) {
            if (Fs.sameDirectory(source.file.parentFile, target)) continue
            if (env.canRename(source.file, target)) continue
            // Anderer Speicher: wie eine Kopie vorab zählen und Platz prüfen.
            val totals = ctx.scan(source.file, source.attrs)
            ctx.totalItems += totals.items - source.totals.items
            ctx.totalBytes += totals.bytes
            source.totals = totals
            source.crossVolume = true
            needed += totals.bytes
        }
        if (!ctx.hasSpace(target, needed)) return
        ctx.enterPhase(OperationPhase.RUNNING)
        for (source in sources) {
            if (ctx.skipBecauseAborted(source.file.path)) continue
            val items = ctx.completedItems
            val bytes = ctx.completedBytes
            if (Fs.sameDirectory(source.file.parentFile, target)) {
                ctx.succeeded++ // liegt schon dort – nichts zu tun
            } else {
                val problemsBefore = ctx.problems
                ctx.beginItem(sourceLeft = source.file)
                val outcome = moveEntry(source.file, source.attrs, target, forceCopy = source.crossVolume)
                account(source, outcome, problemsBefore, isMove = true)
            }
            ctx.snapTo(items + source.totals.items, bytes + source.totals.bytes)
        }
    }

    private suspend fun moveEntry(src: File, attrs: BasicFileAttributes, destDir: File, forceCopy: Boolean): Outcome {
        if (ctx.abortReason != null) return Outcome.Failed
        currentCoroutineContext().ensureActive()
        ctx.currentName = src.name
        if (attrs.isOther) {
            ctx.fail(src.path, FailureReason.SPECIAL_FILE_SKIPPED, OperationRun.DETAIL_SPECIAL)
            return Outcome.Failed
        }
        var finalName = src.name
        var replaceTarget: File? = null
        val conflict = ctx.conflictChoice(src, destDir, ConflictRules.TRANSFER)
        if (conflict != null) {
            val (choice, existing) = conflict
            when (choice) {
                ConflictChoice.SKIP -> return Outcome.Skipped
                ConflictChoice.KEEP_BOTH -> finalName = ctx.uniqueIn(destDir, src.name, attrs.isDirectory)
                ConflictChoice.REPLACE -> replaceTarget = existing
                ConflictChoice.MERGE -> return mergeMove(src, existing)
            }
        }
        if (!forceCopy && env.canRename(src, destDir)) {
            try {
                env.hooks.beforeMoveRename?.invoke(src, replaceTarget ?: File(destDir, finalName))
                val placed = if (replaceTarget != null) {
                    replaceByRename(src, replaceTarget)
                    fixCase(replaceTarget, finalName)
                } else {
                    File(destDir, finalName).also { Fs.renameNoReplace(src, it) }
                }
                ctx.names.remove(src.parentFile, src.name)
                ctx.names.add(destDir, placed.name)
                ctx.addItems(1)
                ctx.childCreated(placed.path)
                ctx.childRemoved(src.path)
                if (attrs.isDirectory) ctx.childDirectoryMovedWhole(placed) else ctx.childFileDone()
                return Outcome.Placed(placed.path, sourceGone = true)
            } catch (e: IOException) {
                if (!Fs.isCrossDevice(e)) {
                    ctx.fail(src.path, e)
                    return Outcome.Failed
                }
                // Gleicher Speicher laut System, aber verschiedene Dateisysteme: geprüfte Kopie statt Umbenennen.
                if (!hasSpaceFor(src, attrs, destDir)) return Outcome.Failed
            }
        }
        if (attrs.isSymbolicLink) {
            ctx.fail(src.path, FailureReason.SPECIAL_FILE_SKIPPED, OperationRun.DETAIL_LINK)
            return Outcome.Failed
        }
        return if (attrs.isDirectory) {
            moveDirectoryByCopy(src, attrs, destDir, finalName)
        } else {
            moveFileByCopy(src, attrs, destDir, finalName, replaceTarget)
        }
    }

    /** Inhalt von [src] in den vorhandenen Ordner [into] verschieben; [src] wird entfernt, wenn er danach leer ist. */
    private suspend fun mergeMove(src: File, into: File): Outcome {
        val children = listChildren(src, includeReserved = true) ?: return Outcome.Failed
        var everythingMoved = true
        for (child in children) {
            if (FileNames.isReserved(child.name) || ctx.abortReason != null) {
                everythingMoved = false
                continue
            }
            val childAttrs = Fs.attrs(child) ?: continue
            val outcome = moveEntry(child, childAttrs, into, forceCopy = !env.canRename(child, into))
            if (outcome !is Outcome.Placed || !outcome.sourceGone) everythingMoved = false
        }
        ctx.addItems(1)
        // Bleibt die Quelle (teilweise) bestehen, stehen die verschobenen Einträge einzeln im Bericht (siehe endItem).
        if (everythingMoved) {
            try {
                Files.delete(src.toPath())
                ctx.names.remove(src.parentFile, src.name)
                ctx.childRemoved(src.path)
                return Outcome.Placed(into.path, sourceGone = true)
            } catch (e: IOException) {
                ctx.fail(src.path, e)
            }
        }
        return Outcome.Placed(into.path, sourceGone = false)
    }

    private suspend fun moveFileByCopy(
        src: File,
        attrs: BasicFileAttributes,
        destDir: File,
        finalName: String,
        replaceTarget: File?,
    ): Outcome {
        val sizeBefore = attrs.size()
        val modifiedBefore = Fs.modifiedMillis(attrs)
        val temp = Fs.tempFileIn(destDir, finalName)
        ctx.registerTemp(temp)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            val written = FileInputStream(src).use { input ->
                FileOutputStream(temp).use { out ->
                    ctx.pump(input, out, temp, digest).also { out.syncToDisk() }
                }
            }
            if (Fs.attrs(temp)?.size() != written) {
                ctx.discardTemp(temp)
                ctx.fail(src.path, FailureReason.VERIFICATION_FAILED, "Größe der Kopie stimmt nicht")
                return Outcome.Failed
            }
            env.hooks.afterTempWritten?.invoke(temp)
            ctx.enterPhase(OperationPhase.VERIFYING, force = false)
            val copyDigest = ctx.sha256(temp)
            ctx.enterPhase(OperationPhase.RUNNING, force = false)
            if (!MessageDigest.isEqual(digest.digest(), copyDigest)) {
                ctx.discardTemp(temp)
                ctx.fail(src.path, FailureReason.VERIFICATION_FAILED)
                return Outcome.Failed
            }
            val now = Fs.attrs(src)
            if (now == null || written != sizeBefore || now.size() != sizeBefore || Fs.modifiedMillis(now) != modifiedBefore) {
                ctx.discardTemp(temp)
                ctx.fail(src.path, FailureReason.CHANGED_MEANWHILE, "Während des Verschiebens geändert – Original bleibt")
                return Outcome.Failed
            }
            Fs.setModified(temp, modifiedBefore)
            val placed = place(temp, destDir, finalName, replaceTarget)
            ctx.bytesProcessed += written
            ctx.addItems(1)
            ctx.childCreated(placed.path)
            ctx.childFileDone()
            return try {
                Files.delete(src.toPath())
                ctx.names.remove(src.parentFile, src.name)
                ctx.childRemoved(src.path)
                Outcome.Placed(placed.path, sourceGone = true)
            } catch (e: IOException) {
                ctx.fail(src.path, IoErrors.classify(e), "Kopie ist vollständig und geprüft, das Original ließ sich nicht entfernen")
                Outcome.Placed(placed.path, sourceGone = false)
            }
        } catch (e: IOException) {
            ctx.discardTemp(temp)
            ctx.fail(src.path, e)
            return Outcome.Failed
        }
    }

    private suspend fun moveDirectoryByCopy(src: File, attrs: BasicFileAttributes, destDir: File, finalName: String): Outcome {
        val dir = File(destDir, finalName)
        try {
            Files.createDirectory(dir.toPath())
        } catch (e: IOException) {
            ctx.fail(src.path, e)
            return Outcome.Failed
        }
        ctx.names.add(destDir, finalName)
        ctx.childCreated(dir.path)
        ctx.addItems(1)
        val children = listChildren(src, includeReserved = true) ?: return Outcome.Placed(dir.path, sourceGone = false)
        var everythingMoved = true
        for (child in children) {
            if (FileNames.isReserved(child.name) || ctx.abortReason != null) {
                everythingMoved = false
                continue
            }
            val childAttrs = Fs.attrs(child) ?: continue
            val outcome = moveEntry(child, childAttrs, dir, forceCopy = true)
            if (outcome !is Outcome.Placed || !outcome.sourceGone) everythingMoved = false
        }
        Fs.setModified(dir, Fs.modifiedMillis(attrs))
        if (!everythingMoved) return Outcome.Placed(dir.path, sourceGone = false)
        return try {
            Files.delete(src.toPath())
            ctx.names.remove(src.parentFile, src.name)
            ctx.childRemoved(src.path)
            Outcome.Placed(dir.path, sourceGone = true)
        } catch (e: IOException) {
            ctx.fail(src.path, IoErrors.classify(e), "Inhalt wurde übertragen, der Quellordner ließ sich nicht entfernen")
            Outcome.Placed(dir.path, sourceGone = false)
        }
    }

    // ---- Gemeinsam ---------------------------------------------------------------------------------------------

    private suspend fun prepare(paths: List<String>, target: File, scan: Boolean, refuseVolumeRoot: Boolean): List<Source> {
        val seen = HashSet<String>()
        val sources = ArrayList<Source>()
        for (raw in paths) {
            currentCoroutineContext().ensureActive()
            val file = File(Fs.normalize(raw))
            if (!seen.add(file.path)) continue
            val attrs = Fs.attrs(file)
            if (attrs == null) {
                ctx.fail(file.path, FailureReason.NOT_FOUND)
                continue
            }
            if (attrs.isDirectory && Fs.isSameOrInside(target.path, file.path)) {
                ctx.fail(file.path, FailureReason.TARGET_INSIDE_SOURCE)
                continue
            }
            if (refuseVolumeRoot && Fs.isVolumeRoot(env.layout, file.path)) {
                ctx.fail(file.path, FailureReason.ACCESS_DENIED, DETAIL_VOLUME_ROOT)
                continue
            }
            val totals = if (scan) ctx.scan(file, attrs) else Totals(1, 0)
            ctx.totalItems += totals.items
            ctx.totalBytes += totals.bytes
            sources += Source(file, attrs, totals)
        }
        ctx.emit(force = true)
        return sources
    }

    /**
     * Ergebnis eines Eintrags der obersten Ebene. Vollständig = keine echten Probleme und (beim Verschieben) die Quelle
     * ist weg: Dann genügt der oberste Pfad. Sonst stehen alle Einzeländerungen im Bericht ([OperationRun.endItem]).
     * Als erledigt zählt ein Eintrag, wenn kein echtes Problem auftrat – bewusst übergangene Verknüpfungen und vom
     * Nutzer übersprungene Teile machen ihn nicht zum Fehlschlag.
     */
    private fun account(source: Source, outcome: Outcome, problemsBefore: Int, isMove: Boolean) {
        val clean = ctx.problems == problemsBefore
        when (outcome) {
            is Outcome.Placed -> {
                val complete = clean && (!isMove || outcome.sourceGone)
                ctx.created(outcome.path)
                if (complete && outcome.sourceGone) ctx.removed(source.file.path)
                if (clean) ctx.succeeded++
                ctx.endItem(complete)
            }
            Outcome.Skipped -> {
                ctx.skipped++
                ctx.endItem(complete = true)
            }
            Outcome.Failed -> ctx.endItem(complete = false)
        }
    }

    /** Verknüpfungen und Gerätedateien werden bewusst nicht übertragen – gemeldet statt still übergangen. */
    private fun transferable(src: File, attrs: BasicFileAttributes): Boolean {
        val detail = when {
            attrs.isSymbolicLink -> OperationRun.DETAIL_LINK
            attrs.isOther -> OperationRun.DETAIL_SPECIAL
            else -> return true
        }
        ctx.fail(src.path, FailureReason.SPECIAL_FILE_SKIPPED, detail)
        return false
    }

    private fun listChildren(dir: File, includeReserved: Boolean = false): List<File>? {
        val children = try {
            dir.listFiles()
        } catch (e: SecurityException) {
            null
        }
        if (children == null) {
            ctx.fail(dir.path, FailureReason.ACCESS_DENIED)
            return null
        }
        return children.filter { includeReserved || !FileNames.isReserved(it.name) }.sortedBy { it.name }
    }

    /** Fertige Zwischendatei an ihren Platz bringen: neu (nie überschreibend) oder als Ersatz für [replaceTarget]. */
    private fun place(temp: File, destDir: File, finalName: String, replaceTarget: File?): File {
        if (replaceTarget != null) {
            replaceWithTemp(temp, replaceTarget)
            return fixCase(replaceTarget, finalName)
        }
        var name = finalName
        var dest = File(destDir, name)
        try {
            Fs.renameNoReplace(temp, dest)
        } catch (e: NioFileAlreadyExistsException) {
            // Inzwischen von außen angelegt: nichts überschreiben, freien Namen wählen.
            ctx.names.forget(destDir)
            name = ctx.uniqueIn(destDir, finalName, isDirectory = false)
            dest = File(destDir, name)
            Fs.renameNoReplace(temp, dest)
        }
        ctx.releaseTemp(temp)
        ctx.names.add(destDir, name)
        return dest
    }

    /**
     * Ersetzt [target] durch die vollständige Zwischendatei [temp] – atomar (ein `rename()`). Nur wenn das Dateisystem
     * das ablehnt: Austausch im Journal bestätigen, dann Vorhandenes löschen und umbenennen. Die Quelle existiert in
     * beiden Fällen noch, es geht also nie die einzige Fassung verloren.
     */
    private fun replaceWithTemp(temp: File, target: File) {
        try {
            Fs.atomicMove(temp, target)
            ctx.releaseTemp(temp)
            return
        } catch (e: IOException) {
            if (Fs.isCrossDevice(e)) throw e
        }
        ctx.commitTemp(temp, target)
        Files.deleteIfExists(target.toPath())
        Fs.atomicMove(temp, target)
        env.journal?.remove(temp.path)
    }

    /** Verschieben mit Ersetzen auf demselben Speicher: atomares Umbenennen über das Vorhandene. */
    private fun replaceByRename(src: File, target: File) {
        try {
            Fs.atomicMove(src, target)
            return
        } catch (e: IOException) {
            if (Fs.isCrossDevice(e)) throw e
        }
        // Ausweichweg: Die Quelle bleibt bis zum Umbenennen an ihrem Ort – bei einem Absturz geht nichts verloren.
        Files.deleteIfExists(target.toPath())
        Fs.atomicMove(src, target)
    }

    /** Nach dem Ersetzen den Namen der neuen Fassung übernehmen, falls er sich nur in der Schreibweise unterscheidet. */
    private fun fixCase(file: File, desiredName: String): File {
        val result = Fs.fixCaseBestEffort(file, desiredName)
        if (result.name != file.name) {
            file.parentFile?.let { parent ->
                ctx.names.remove(parent, file.name)
                ctx.names.add(parent, result.name)
            }
        }
        return result
    }

    private suspend fun hasSpaceFor(src: File, attrs: BasicFileAttributes, destDir: File): Boolean {
        val totals = ctx.scan(src, attrs)
        return ctx.hasSpace(destDir, totals.bytes)
    }

    private companion object {
        const val DETAIL_VOLUME_ROOT = "Die oberste Ebene eines Speichers kann nicht verschoben werden"
    }
}
