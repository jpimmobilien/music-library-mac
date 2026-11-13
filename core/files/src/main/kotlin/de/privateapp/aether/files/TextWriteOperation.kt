package de.privateapp.aether.files

import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.FileAlreadyExistsException as NioFileAlreadyExistsException

/*
 * Textdatei sicher sichern (Editor).
 *
 *  1. Wurde die Datei seit dem Öffnen geändert (andere Änderungszeit) oder gelöscht, wird NICHT geschrieben
 *     ([FailureReason.CHANGED_MEANWHILE]) – der Nutzer entscheidet dann. Ohne erwartete Änderungszeit (neue Datei) darf
 *     die Datei noch nicht existieren; sonst ebenfalls CHANGED_MEANWHILE statt still zu überschreiben.
 *  2. Neuer Inhalt vollständig in „<Name>.aether-part“, fsync, Größe prüfen.
 *  3. Unmittelbar vorher nochmals auf Änderungen prüfen, dann atomar ersetzen (ein `rename()`): Es gibt keinen
 *     Moment, in dem die Datei fehlt oder halb geschrieben ist.
 *  4. Nur falls das Dateisystem atomares Ersetzen ablehnt: Austausch im Journal bestätigen (fsync), Original löschen,
 *     Zwischendatei umbenennen. Stürzt die App genau dazwischen ab, setzt das Journal beim nächsten Start die neue
 *     Fassung an ihren Platz – die einzige vollständige Fassung wird nie gelöscht.
 *
 * Die Kodierung bleibt erhalten: Eine windows-1252- oder UTF-16-Datei wird wieder so geschrieben (mit ihrem BOM),
 * solange alle Zeichen darin darstellbar sind; sonst UTF-8. Neue Dateien werden UTF-8 ohne BOM.
 */
internal class TextWriteOperation(private val ctx: OperationRun) {

    private val env = ctx.env

    suspend fun write(op: FileOperation.WriteText) {
        val file = File(Fs.normalize(op.path))
        val parent = file.parentFile
        if (parent == null || !parent.isDirectory) {
            ctx.fail(file.path, FailureReason.NOT_FOUND, "Ordner nicht vorhanden")
            return
        }
        val attrs = Fs.attrs(file)
        if (attrs != null && attrs.isDirectory) {
            ctx.fail(file.path, FailureReason.IO_ERROR, "Ist ein Ordner")
            return
        }
        if (!unchanged(op, file)) {
            ctx.fail(file.path, FailureReason.CHANGED_MEANWHILE)
            return
        }
        if (attrs == null) {
            FileNames.validate(file.name)?.let { problem ->
                ctx.fail(file.path, FailureReason.INVALID_NAME, problem.message)
                return
            }
        }
        val bytes = encode(op.text, file, exists = attrs != null)
        ctx.totalItems = 1
        ctx.totalBytes = bytes.size.toLong()
        ctx.currentName = file.name
        ctx.enterPhase(OperationPhase.RUNNING)
        val temp = Fs.tempFileIn(parent, file.name)
        ctx.registerTemp(temp)
        try {
            val written = FileOutputStream(temp).use { out ->
                ctx.pump(ByteArrayInputStream(bytes), out, temp).also { out.syncToDisk() }
            }
            if (written != bytes.size.toLong() || Fs.attrs(temp)?.size() != written) {
                ctx.discardTemp(temp)
                ctx.fail(file.path, FailureReason.VERIFICATION_FAILED, "Größe der gespeicherten Fassung stimmt nicht")
                return
            }
            env.hooks.afterTempWritten?.invoke(temp)
            if (!unchanged(op, file)) {
                ctx.discardTemp(temp)
                ctx.fail(file.path, FailureReason.CHANGED_MEANWHILE)
                return
            }
            if (attrs == null) {
                Fs.renameNoReplace(temp, file)
                ctx.releaseTemp(temp)
            } else {
                replace(temp, file)
            }
        } catch (e: NioFileAlreadyExistsException) {
            ctx.discardTemp(temp)
            ctx.fail(file.path, FailureReason.CHANGED_MEANWHILE, "Inzwischen von außen angelegt")
            return
        } catch (e: IOException) {
            // discardTemp löscht nur eine Wegwerf-Zwischendatei, nie eine bereits bestätigte (siehe Dateikopf).
            ctx.discardTemp(temp)
            ctx.fail(file.path, e)
            return
        }
        ctx.succeeded = 1
        ctx.bytesProcessed = bytes.size.toLong()
        ctx.created(file.path)
        ctx.addItems(1, force = true)
    }

    private fun unchanged(op: FileOperation.WriteText, file: File): Boolean {
        val current = Fs.attrs(file)
        val expected = op.expectedModifiedMillis ?: return current == null
        return current != null && Fs.modifiedMillis(current) == expected
    }

    private fun replace(temp: File, file: File) {
        try {
            Fs.atomicMove(temp, file)
            ctx.releaseTemp(temp)
            return
        } catch (e: IOException) {
            if (Fs.isCrossDevice(e)) throw e
        }
        ctx.commitTemp(temp, file)
        Files.deleteIfExists(file.toPath())
        Fs.atomicMove(temp, file)
        env.journal?.remove(temp.path)
    }

    /** Text in der Kodierung der vorhandenen Datei (mit ihrem BOM), wenn alle Zeichen passen; sonst UTF-8. */
    private fun encode(text: String, file: File, exists: Boolean): ByteArray {
        if (!exists) return text.toByteArray(Charsets.UTF_8)
        val detection = try {
            TextPreviewReader.detectFile(file)
        } catch (e: IOException) {
            null
        }
        if (detection == null || detection.looksBinary) return text.toByteArray(Charsets.UTF_8)
        val charset = detection.charset
        if (!charset.newEncoder().canEncode(text)) return text.toByteArray(Charsets.UTF_8)
        return detection.bom + text.toByteArray(charset)
    }
}
