package de.privateapp.aether.files

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.FileAlreadyExistsException as NioFileAlreadyExistsException

/*
 * Umbenennen und Ordner erstellen.
 *
 *  - Namen werden vorher nach den Regeln aller Speicher geprüft (FileNames.validate); der Grund steht im Bericht.
 *  - Umbenennen ist ein atomares `rename()` im selben Ordner. Nur die Schreibweise ändern („foto.jpg“ → „Foto.jpg“)
 *    geht auf Speichern ohne Groß-/Kleinschreibung nur über einen Zwischennamen – das erledigt Fs.renameCaseOnly.
 *  - Ist der neue Name belegt, entscheidet der ConflictResolver: Dateien ersetzen, beide behalten oder überspringen;
 *    ein Ordner wird nie ersetzt und nie zusammengeführt (wird zu „überspringen“).
 *  - Ein neuer Ordner erhält bei Belegung automatisch einen freien Namen („Neuer Ordner 2“).
 */
internal class NameOperations(private val ctx: OperationRun) {

    private val env = ctx.env

    suspend fun rename(op: FileOperation.Rename) {
        val src = File(Fs.normalize(op.source))
        val attrs = Fs.attrs(src)
        if (attrs == null) {
            ctx.fail(src.path, FailureReason.NOT_FOUND)
            return
        }
        if (Fs.isVolumeRoot(env.layout, src.path)) {
            ctx.fail(src.path, FailureReason.ACCESS_DENIED, "Die oberste Ebene eines Speichers kann nicht umbenannt werden")
            return
        }
        FileNames.validate(op.newName)?.let { problem ->
            ctx.fail(src.path, FailureReason.INVALID_NAME, problem.message)
            return
        }
        val parent = src.parentFile
        if (parent == null) {
            ctx.fail(src.path, FailureReason.IO_ERROR, "Kein übergeordneter Ordner")
            return
        }
        ctx.totalItems = 1
        ctx.currentName = src.name
        ctx.enterPhase(OperationPhase.RUNNING)
        if (op.newName == src.name) {
            ctx.succeeded++
            return
        }
        val caseOnly = op.newName.equals(src.name, ignoreCase = true)
        val existing = existingOther(src, parent, op.newName, caseOnly)
        var finalName = op.newName
        var replaceTarget: File? = null
        if (existing != null) {
            val sourceEntry = DirectoryReader.entryOf(src)
            val existingEntry = DirectoryReader.entryOf(existing)
            if (sourceEntry != null && existingEntry != null) {
                when (ctx.decide(sourceEntry, existingEntry, ConflictRules.RENAME)) {
                    ConflictChoice.SKIP, ConflictChoice.MERGE -> {
                        ctx.skipped++
                        return
                    }
                    ConflictChoice.KEEP_BOTH -> finalName = FileNames.uniqueName(op.newName, attrs.isDirectory) { candidate ->
                        ctx.names.lookup(parent, candidate) != null || candidate.equals(src.name, ignoreCase = true)
                    }
                    ConflictChoice.REPLACE -> replaceTarget = existing
                }
            }
        }
        try {
            val result = when {
                replaceTarget != null -> {
                    Fs.atomicMove(src, replaceTarget)
                    Fs.fixCaseBestEffort(replaceTarget, finalName)
                }
                caseOnly && finalName == op.newName -> Fs.renameCaseOnly(src, finalName)
                else -> File(parent, finalName).also { Fs.renameNoReplace(src, it) }
            }
            ctx.names.remove(parent, src.name)
            ctx.names.add(parent, result.name)
            ctx.succeeded++
            ctx.created(result.path)
            ctx.removed(src.path)
        } catch (e: IOException) {
            ctx.fail(src.path, e)
        }
        ctx.addItems(1, force = true)
    }

    /** Ein ANDERER Eintrag, der den neuen Namen schon trägt (ohne Groß-/Kleinschreibung), oder `null`. */
    private fun existingOther(src: File, parent: File, newName: String, caseOnly: Boolean): File? {
        if (caseOnly) {
            // Auf Speichern mit Groß-/Kleinschreibung kann „Foto.jpg“ neben „foto.jpg“ existieren.
            val exact = File(parent, newName)
            return if (Fs.exists(exact) && !Fs.isSameFile(src, exact)) exact else null
        }
        val name = ctx.names.lookup(parent, newName) ?: return null
        val other = File(parent, name)
        return if (Fs.isSameFile(src, other)) null else other
    }

    fun createFolder(op: FileOperation.CreateFolder) {
        val parent = File(Fs.normalize(op.parentDir))
        val attrs = Fs.displayAttrs(parent)
        if (attrs == null || !attrs.isDirectory) {
            ctx.fail(parent.path, if (attrs == null) FailureReason.NOT_FOUND else FailureReason.IO_ERROR,
                if (attrs == null) null else OperationRun.DETAIL_NOT_A_FOLDER)
            return
        }
        FileNames.validate(op.name)?.let { problem ->
            ctx.fail(File(parent, op.name).path, FailureReason.INVALID_NAME, problem.message)
            return
        }
        ctx.totalItems = 1
        ctx.enterPhase(OperationPhase.RUNNING)
        repeat(2) { attempt ->
            val name = ctx.uniqueIn(parent, op.name, isDirectory = true)
            val dir = File(parent, name)
            try {
                Files.createDirectory(dir.toPath())
                ctx.names.add(parent, name)
                ctx.succeeded++
                ctx.created(dir.path)
                ctx.addItems(1, force = true)
                return
            } catch (e: NioFileAlreadyExistsException) {
                // Inzwischen von außen angelegt: einmal mit frisch gelesenem Ordner neu versuchen.
                ctx.names.forget(parent)
                if (attempt == 1) ctx.fail(dir.path, e)
            } catch (e: IOException) {
                ctx.fail(dir.path, e)
                return
            }
        }
    }
}
