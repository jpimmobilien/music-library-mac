package de.privateapp.aether.files

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.charset.Charset
import java.nio.file.Files
import java.nio.file.attribute.BasicFileAttributes
import java.util.Locale
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import java.nio.file.FileAlreadyExistsException as NioFileAlreadyExistsException

/*
 * ZIP erstellen und entpacken.
 *
 * Komprimieren: Namen in UTF-8 (mit Kennzeichen, das alle heutigen Programme verstehen), Ordner als eigene Einträge,
 * Änderungszeiten bleiben erhalten. Bereits komprimierte Formate (Fotos, Videos, Musik, Archive, Apps) werden nur
 * gespeichert statt erneut komprimiert – das spart viel Zeit und kaum Platz. Geschrieben wird in
 * „<Name>.zip.aether-part“; erst das fertige, auf das Medium geschriebene Archiv erhält seinen Namen.
 *
 * Entpacken:
 *  - Enthält das Archiv genau einen Ordner auf oberster Ebene, entsteht dieser Ordner im Ziel. Sonst entsteht ein
 *    Ordner mit dem Namen des Archivs. Belegte Namen werden nie überschrieben („Fotos 2“).
 *  - Alles wird zuerst in „<Ordner>.aether-part“ entpackt und erst am Ende umbenannt. Bei Abbruch oder schwerem Fehler
 *    (Speicher voll) wird dieser Zwischenordner vollständig entfernt – es bleibt nichts Halbes zurück.
 *  - Einträge mit absolutem Pfad oder „..“ (Zip-Slip) werden nie entpackt, sondern gemeldet.
 *  - Namen ohne UTF-8-Kennzeichen, die kein gültiges UTF-8 sind, werden als IBM-437 gelesen (ältere Windows-Archive).
 *  - „__MACOSX“ (Zusatzdaten von macOS) wird übergangen.
 *  - Verschlüsselte Archive und unbekannte Verfahren werden ehrlich als „nicht unterstützt“ gemeldet.
 */
internal class ArchiveOperations(private val ctx: OperationRun) {

    private class Source(val file: File, val attrs: BasicFileAttributes)

    private class Planned(val entry: ZipEntry, val segments: List<String>)

    // ---- Komprimieren ------------------------------------------------------------------------------------------

    suspend fun compress(op: FileOperation.Compress) {
        val target = ctx.targetDirectory(op.targetDir) ?: return
        val name = OperationTexts.archiveFileName(op.archiveName)
        val problem = if (name.length <= ".zip".length) NameProblem.EMPTY else FileNames.validate(name)
        if (problem != null) {
            ctx.fail(File(target, name).path, FailureReason.INVALID_NAME, problem.message)
            return
        }
        val sources = ArrayList<Source>()
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
            val totals = ctx.scan(file, attrs)
            ctx.totalItems += totals.items
            ctx.totalBytes += totals.bytes
            sources += Source(file, attrs)
        }
        if (sources.isEmpty()) return
        val finalName = ctx.uniqueIn(target, name, isDirectory = false)
        val temp = Fs.tempFileIn(target, finalName)
        ctx.registerTemp(temp)
        ctx.enterPhase(OperationPhase.RUNNING)
        var complete = 0
        var entries = 0
        val bytesBefore = ctx.bytesProcessed
        try {
            FileOutputStream(temp).use { fileOut ->
                ZipOutputStream(BufferedOutputStream(fileOut, ZIP_BUFFER), Charsets.UTF_8).use { zip ->
                    val topNames = HashSet<String>()
                    for (source in sources) {
                        if (ctx.skipBecauseAborted(source.file.path)) continue
                        val problemsBefore = ctx.problems
                        // Gleichnamige Quellen aus verschiedenen Ordnern: zweite als „Name 2“.
                        val entryRoot = FileNames.uniqueName(source.file.name, source.attrs.isDirectory) {
                            it.lowercase(Locale.ROOT) in topNames
                        }
                        topNames += entryRoot.lowercase(Locale.ROOT)
                        entries += addToZip(zip, source.file, source.attrs, entryRoot)
                        if (ctx.problems == problemsBefore) complete++
                    }
                    zip.finish()
                    zip.flush()
                    fileOut.channel.force(true)
                }
            }
        } catch (e: IOException) {
            ctx.discardTemp(temp)
            ctx.fail(File(target, finalName).path, e)
            ctx.bytesProcessed = bytesBefore
            return
        }
        if (entries == 0) {
            ctx.discardTemp(temp)
            ctx.bytesProcessed = bytesBefore
            return
        }
        try {
            val archive = placeNew(temp, target, finalName)
            ctx.created(archive.path)
            ctx.succeeded = complete
        } catch (e: IOException) {
            ctx.discardTemp(temp)
            ctx.fail(File(target, finalName).path, e)
        }
    }

    /** Fügt [file] (rekursiv) unter [entryName] hinzu; liefert die Zahl der geschriebenen Einträge. */
    private suspend fun addToZip(zip: ZipOutputStream, file: File, attrs: BasicFileAttributes, entryName: String): Int {
        if (ctx.abortReason != null) return 0
        currentCoroutineContext().ensureActive()
        ctx.currentName = file.name
        when {
            attrs.isSymbolicLink -> {
                ctx.fail(file.path, FailureReason.SPECIAL_FILE_SKIPPED, OperationRun.DETAIL_LINK)
                return 0
            }
            attrs.isOther -> {
                ctx.fail(file.path, FailureReason.SPECIAL_FILE_SKIPPED, OperationRun.DETAIL_SPECIAL)
                return 0
            }
            attrs.isDirectory -> {
                val entry = ZipEntry("$entryName/")
                entry.setLastModifiedTime(attrs.lastModifiedTime())
                zip.putNextEntry(entry)
                zip.closeEntry()
                ctx.addItems(1)
                var count = 1
                val children = try {
                    file.listFiles()
                } catch (e: SecurityException) {
                    null
                }
                if (children == null) {
                    ctx.fail(file.path, FailureReason.ACCESS_DENIED)
                    return count
                }
                for (child in children.sortedBy { it.name }) {
                    if (FileNames.isReserved(child.name)) continue
                    val childAttrs = Fs.attrs(child) ?: continue
                    count += addToZip(zip, child, childAttrs, "$entryName/${child.name}")
                }
                return count
            }
            else -> {
                // Öffnen VOR dem Eintrag: Eine unlesbare Datei wird gemeldet und fehlt, das Archiv bleibt gültig.
                // Ein Lesefehler MITTEN in der Datei bricht dagegen das ganze Archiv ab (es wäre sonst beschädigt).
                val input = try {
                    FileInputStream(file)
                } catch (e: IOException) {
                    ctx.fail(file.path, e)
                    return 0
                }
                input.use {
                    val entry = ZipEntry(entryName)
                    entry.setLastModifiedTime(attrs.lastModifiedTime())
                    zip.setLevel(if (isAlreadyCompressed(file.name)) Deflater.NO_COMPRESSION else Deflater.DEFAULT_COMPRESSION)
                    zip.putNextEntry(entry)
                    val written = ctx.pump(input, zip, file)
                    zip.closeEntry()
                    ctx.bytesProcessed += written
                }
                ctx.addItems(1)
                return 1
            }
        }
    }

    private fun isAlreadyCompressed(name: String): Boolean = when (FileTypes.kindOf(name, isDirectory = false)) {
        FileKind.IMAGE, FileKind.VIDEO, FileKind.AUDIO, FileKind.ARCHIVE, FileKind.APK ->
            FileTypes.extensionOf(name) !in UNCOMPRESSED_MEDIA
        else -> FileTypes.extensionOf(name) in COMPRESSED_DOCUMENTS
    }

    // ---- Entpacken ---------------------------------------------------------------------------------------------

    suspend fun extract(op: FileOperation.Extract) {
        val archive = File(Fs.normalize(op.archive))
        val archiveAttrs = Fs.attrs(archive)
        if (archiveAttrs == null) {
            ctx.fail(archive.path, FailureReason.NOT_FOUND)
            return
        }
        if (archiveAttrs.isDirectory) {
            ctx.fail(archive.path, FailureReason.ARCHIVE_UNSUPPORTED, "Ist ein Ordner")
            return
        }
        val target = ctx.targetDirectory(op.targetDir) ?: return
        val (zip, entries) = open(archive) ?: return
        zip.use {
            extractFrom(zip, entries, archive, target)
        }
    }

    private suspend fun extractFrom(zip: ZipFile, entries: List<ZipEntry>, archive: File, target: File) {
        val problemsBefore = ctx.problems
        val planned = plan(entries, archive)
        if (planned.isEmpty()) {
            if (ctx.problems == problemsBefore) ctx.succeeded = 1 // leeres Archiv: nichts zu entpacken
            return
        }
        // Ein einziger Ordner oben → diesen Ordner entpacken; sonst Ordner mit dem Namen des Archivs.
        val topLevel = planned.map { it.segments.first().lowercase(Locale.ROOT) }.toSet()
        val singleDir = topLevel.size == 1 && planned.any { it.segments.size > 1 || it.entry.isDirectory }
        val topName = planned.first().segments.first()
        val useTopDir = singleDir && FileNames.validate(topName) == null
        val strip = if (useTopDir) 1 else 0
        val baseName = if (useTopDir) topName else archiveBaseName(archive.name)
        val needed = planned.sumOf { if (it.entry.isDirectory) 0L else it.entry.size.coerceAtLeast(0L) }
        ctx.totalItems = planned.size
        ctx.totalBytes = needed
        if (!ctx.hasSpace(target, needed)) return

        val finalName = ctx.uniqueIn(target, baseName, isDirectory = true)
        val partDir = Fs.tempFileIn(target, finalName)
        ctx.registerTemp(partDir)
        try {
            Files.createDirectory(partDir.toPath())
        } catch (e: IOException) {
            ctx.fail(File(target, finalName).path, e)
            return
        }
        ctx.enterPhase(OperationPhase.RUNNING)
        val directoryTimes = ArrayList<Pair<File, Long>>()
        var topTime = -1L
        for (item in planned) {
            if (ctx.abortReason != null) break
            currentCoroutineContext().ensureActive()
            val segments = item.segments.drop(strip)
            if (segments.isEmpty()) {
                topTime = item.entry.time
                ctx.addItems(1)
                continue
            }
            ctx.currentName = segments.last()
            val dest = File(partDir, segments.joinToString("/"))
            if (item.entry.isDirectory) {
                try {
                    Files.createDirectories(dest.toPath())
                    directoryTimes += dest to item.entry.time
                } catch (e: IOException) {
                    ctx.fail(archive.path, e, "${item.entry.name}: ${e.message}")
                }
                ctx.addItems(1)
                continue
            }
            extractFile(zip, item.entry, dest, archive)
        }
        if (ctx.abortReason != null) return // Zwischenordner wird beim Aufräumen vollständig entfernt
        for ((dir, time) in directoryTimes.asReversed()) Fs.setModified(dir, time)
        Fs.setModified(partDir, topTime)
        try {
            val folder = placeNew(partDir, target, finalName)
            ctx.created(folder.path)
            if (ctx.problems == problemsBefore) ctx.succeeded = 1
        } catch (e: IOException) {
            ctx.fail(File(target, finalName).path, e)
        }
    }

    private suspend fun extractFile(zip: ZipFile, entry: ZipEntry, dest: File, archive: File) {
        val parent = dest.parentFile
        try {
            Files.createDirectories(parent.toPath())
        } catch (e: IOException) {
            ctx.fail(archive.path, e, "${entry.name}: ${e.message}")
            return
        }
        // Doppelte Namen im Archiv (auch nur in der Schreibweise verschieden) überschreiben einander nicht.
        val name = ctx.uniqueIn(parent, dest.name, isDirectory = false)
        val out = File(parent, name)
        val limit = if (entry.size >= 0) entry.size else Long.MAX_VALUE
        try {
            zip.getInputStream(entry).use { input ->
                FileOutputStream(out).use { stream ->
                    ctx.names.add(parent, name)
                    val written = ctx.pump(input, stream, out, limit = limit)
                    stream.syncToDisk()
                    ctx.bytesProcessed += written
                }
            }
            Fs.setModified(out, entry.time)
            ctx.addItems(1)
        } catch (e: SizeLimitExceededException) {
            out.delete()
            ctx.fail(archive.path, FailureReason.ARCHIVE_UNSUPPORTED, "${entry.name}: mehr Daten als angegeben")
        } catch (e: ZipException) {
            out.delete()
            ctx.fail(archive.path, FailureReason.ARCHIVE_UNSUPPORTED, "${entry.name}: ${e.message}")
        } catch (e: IOException) {
            out.delete()
            ctx.fail(archive.path, e, "${entry.name}: ${e.message}")
        }
    }

    /** Öffnet das Archiv (UTF-8, sonst IBM-437) und liest das Inhaltsverzeichnis. `null` = gemeldet. */
    private fun open(archive: File): Pair<ZipFile, List<ZipEntry>>? {
        var firstProblem: Exception? = null
        for (charset in listOf(Charsets.UTF_8, IBM_437)) {
            var zip: ZipFile? = null
            try {
                zip = ZipFile(archive, charset)
                return zip to zip.entries().toList()
            } catch (e: ZipException) {
                zip?.close()
                if (firstProblem == null) firstProblem = e
            } catch (e: IllegalArgumentException) {
                // Android meldet ungültig kodierte Namen als „MALFORMED“.
                zip?.close()
                if (firstProblem == null) firstProblem = e
            } catch (e: IOException) {
                zip?.close()
                ctx.fail(archive.path, e)
                return null
            }
        }
        ctx.fail(archive.path, FailureReason.ARCHIVE_UNSUPPORTED, firstProblem?.message)
        return null
    }

    /** Sichere Einträge mit ihren Pfadteilen; unsichere werden gemeldet, „__MACOSX“ übergangen. */
    private fun plan(entries: List<ZipEntry>, archive: File): List<Planned> {
        val planned = ArrayList<Planned>()
        for (entry in entries) {
            val raw = entry.name
            val path = raw.replace('\\', '/')
            val segments = path.split('/').filter { it.isNotEmpty() && it != "." }
            val unsafe = path.startsWith("/") || DRIVE_LETTER.containsMatchIn(path) ||
                segments.any { it == ".." || '\u0000' in it || FileNames.isReserved(it) }
            if (unsafe) {
                ctx.fail(archive.path, FailureReason.ARCHIVE_UNSAFE_ENTRY, raw)
                continue
            }
            if (segments.isEmpty()) continue
            if (segments.first().equals("__MACOSX", ignoreCase = true)) continue
            planned += Planned(entry, segments)
        }
        return planned
    }

    private fun archiveBaseName(name: String): String {
        val extension = FileTypes.extensionOf(name)
        val stem = if (extension.isEmpty()) name else name.dropLast(extension.length + 1)
        return if (stem.isNotEmpty() && FileNames.validate(stem) == null) stem else "Archiv"
    }

    /** Fertige Zwischendatei bzw. -ordner unter [finalName] ablegen – nie überschreibend. */
    private fun placeNew(temp: File, target: File, finalName: String): File {
        var dest = File(target, finalName)
        try {
            Fs.renameNoReplace(temp, dest)
        } catch (e: NioFileAlreadyExistsException) {
            ctx.names.forget(target)
            dest = File(target, ctx.uniqueIn(target, finalName, isDirectory = temp.isDirectory))
            Fs.renameNoReplace(temp, dest)
        }
        ctx.releaseTemp(temp)
        ctx.names.add(target, dest.name)
        return dest
    }

    private companion object {
        const val ZIP_BUFFER = 64 * 1024
        val DRIVE_LETTER = Regex("^[A-Za-z]:")
        val IBM_437: Charset = runCatching { Charset.forName("IBM437") }.getOrDefault(Charsets.ISO_8859_1)

        /** Medienformate, die unkomprimiert sind und sich gut packen lassen. */
        val UNCOMPRESSED_MEDIA = setOf("bmp", "wav", "svg", "tar")

        /** Bürodateien, die selbst ZIP-Archive sind. */
        val COMPRESSED_DOCUMENTS = setOf("docx", "xlsx", "pptx", "odt", "ods", "odp", "epub")
    }
}
