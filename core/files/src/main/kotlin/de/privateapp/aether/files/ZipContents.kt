package de.privateapp.aether.files

import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipFile

/*
 * Inhaltsverzeichnis eines ZIP-Archivs für die Schnellansicht – ohne etwas zu entpacken.
 *
 * Es gelten dieselben Regeln wie beim Entpacken ([FileOperationEngine]):
 *  - Namen in UTF-8, ersatzweise IBM-437 (ältere Windows-Archive).
 *  - Einträge mit absolutem Pfad, Laufwerksbuchstaben oder „..“ (Zip-Slip) sind „unsicher“: Sie werden angezeigt und
 *    gekennzeichnet, aber nie entpackt.
 *  - „__MACOSX“ (Zusatzdaten von macOS) wird übergangen und nur gezählt.
 *
 * Zusätzlich liest ORBIT das zentrale Verzeichnis des Archivs selbst ([CentralDirectory]): Verschlüsselung (Bit 0 der
 * Kennzeichen bzw. Verfahren 99 = AES) und Packverfahren, die Android nicht beherrscht (BZip2, LZMA, Deflate64 …),
 * melden die Java-Bibliotheken je nach Android-Version unterschiedlich – oft nur als „ungültiges Archiv“. Lässt sich
 * ein Archiv deshalb nicht mit `ZipFile` öffnen, zeigt ORBIT den Inhalt aus dem eigenen Lesevorgang und sagt ehrlich,
 * warum Entpacken hier nicht geht. Archive mit vorangestelltem Programm (selbstentpackende Archive) werden erkannt.
 *
 * Größenangaben stammen aus dem Archiv und können gefälscht sein: Summen laufen nie über (sie bleiben beim größten
 * Wert stehen und gelten dann als „unbekannt“), negative Angaben gelten als unbekannt.
 */

/** Ein Eintrag des Archivs. Größen sind `-1`, wenn das Archiv sie nicht (glaubhaft) angibt. */
data class ZipEntryInfo(
    /** Pfad im Archiv mit „/“ als Trenner, ohne abschließenden „/“. */
    val path: String,
    val isDirectory: Boolean,
    val sizeBytes: Long,
    val compressedBytes: Long,
    val modifiedMillis: Long,
    /** Würde beim Entpacken übergangen (absoluter Pfad oder „..“). */
    val unsafe: Boolean,
) {
    val name: String get() = path.substringAfterLast('/')
    val parent: String get() = path.substringBeforeLast('/', "")
}

sealed interface ZipContents {
    data class Listed(
        /** Höchstens `maxEntries` Einträge (Archiv-Reihenfolge). */
        val entries: List<ZipEntryInfo>,
        /** Alle Einträge (ohne „__MACOSX“). */
        val totalEntries: Int,
        val files: Int,
        val folders: Int,
        /** Summe der angegebenen Größen (entpackt); [sizeUnknown], wenn Einträge keine glaubhafte Größe angeben. */
        val totalBytes: Long,
        val compressedBytes: Long,
        val sizeUnknown: Boolean,
        val unsafeEntries: Int,
        val macosEntries: Int,
        /** Einträge mit einem Verfahren, das Android nicht entpacken kann. */
        val unsupportedEntries: Int,
        /** Mindestens ein Eintrag ist verschlüsselt – ORBIT kann das Archiv dann nicht entpacken. */
        val encrypted: Boolean,
        val charsetName: String,
        /**
         * Android kann das Archiv öffnen (Voraussetzung fürs Entpacken). `false` = Inhalt stammt aus ORBITs eigenem
         * Lesen des Verzeichnisses, weil Android das Archiv ablehnt (Verschlüsselung, unbekanntes Verfahren).
         */
        val readableByAndroid: Boolean,
    ) : ZipContents {
        val truncated: Boolean get() = entries.size < totalEntries

        /** Entpacken kann überhaupt etwas ergeben. */
        val extractable: Boolean get() = readableByAndroid && !encrypted && totalEntries > unsafeEntries
    }

    /** Archiv ist verschlüsselt, und auch das Verzeichnis ist nicht lesbar. */
    data object Encrypted : ZipContents

    /** Kein lesbares ZIP-Archiv (beschädigt, anderes Format). [detail] = technische Meldung (nur für Protokolle). */
    data class Unsupported(val detail: String?) : ZipContents

    data object NotFound : ZipContents

    data class Failed(val reason: FailureReason, val detail: String?) : ZipContents
}

object ZipContentsReader {

    private val DRIVE_LETTER = Regex("^[A-Za-z]:")
    internal val IBM_437: Charset = runCatching { Charset.forName("IBM437") }.getOrDefault(Charsets.ISO_8859_1)

    /** Liest das Inhaltsverzeichnis von [path]. Blockiert (Datei wird geöffnet) – nicht auf dem Hauptthread aufrufen. */
    fun read(path: String, maxEntries: Int = 2_000): ZipContents {
        val file = File(Fs.normalize(path))
        val attrs = Fs.attrs(file) ?: return ZipContents.NotFound
        if (attrs.isDirectory) return ZipContents.Unsupported("Ist ein Ordner")
        val directory = try {
            CentralDirectory.scan(file, maxEntries)
        } catch (e: IOException) {
            null
        } catch (e: OutOfMemoryError) {
            null
        } catch (e: SecurityException) {
            return ZipContents.Failed(FailureReason.ACCESS_DENIED, e.message)
        }
        var firstProblem: Exception? = null
        for (charset in listOf(Charsets.UTF_8, IBM_437)) {
            var zip: ZipFile? = null
            try {
                zip = ZipFile(file, charset)
                zip.use { return list(it, charset, directory, maxEntries) }
            } catch (e: ZipException) {
                zip?.close()
                if (firstProblem == null) firstProblem = e
            } catch (e: IllegalArgumentException) {
                // Ungültig kodierte Namen („MALFORMED“) – mit der nächsten Kodierung versuchen.
                zip?.close()
                if (firstProblem == null) firstProblem = e
            } catch (e: IOException) {
                zip?.close()
                return ZipContents.Failed(IoErrors.classify(e), e.message)
            } catch (e: SecurityException) {
                zip?.close()
                return ZipContents.Failed(FailureReason.ACCESS_DENIED, e.message)
            } catch (e: OutOfMemoryError) {
                zip?.close()
                return ZipContents.Failed(FailureReason.IO_ERROR, "Inhaltsverzeichnis zu groß")
            }
        }
        // Android lehnt das Archiv ab. Hat ORBIT das Verzeichnis selbst lesen können und erklärt es die Ablehnung
        // (Verschlüsselung, fremdes Verfahren), wird der Inhalt trotzdem gezeigt.
        if (directory != null && directory.records > 0 && (directory.encrypted > 0 || directory.unsupportedMethods > 0)) {
            return fromDirectory(directory)
        }
        val message = firstProblem?.message
        if ((directory?.encrypted ?: 0) > 0 || message?.contains("encrypt", ignoreCase = true) == true) return ZipContents.Encrypted
        return ZipContents.Unsupported(message)
    }

    private class Tally {
        var total = 0
        var files = 0
        var folders = 0
        var bytes = 0L
        var compressed = 0L
        var sizeUnknown = false
        var unsafe = 0
        var macos = 0
        var unsupported = 0
        val shown = ArrayList<ZipEntryInfo>()

        /** Nimmt einen Eintrag auf („__MACOSX“ und leere Namen werden übergangen). */
        fun add(rawName: String, isDirectory: Boolean, size: Long, compressedSize: Long, time: Long, method: Int, maxEntries: Int) {
            val raw = rawName.replace('\\', '/')
            val segments = raw.split('/').filter { it.isNotEmpty() && it != "." }
            if (segments.firstOrNull()?.equals("__MACOSX", ignoreCase = true) == true) {
                macos++
                return
            }
            val isUnsafe = raw.startsWith("/") || DRIVE_LETTER.containsMatchIn(raw) ||
                segments.any { it == ".." || '\u0000' in it || FileNames.isReserved(it) }
            if (segments.isEmpty() && !isUnsafe) return
            total++
            if (isUnsafe) unsafe++
            if (method != ZipEntry.STORED && method != ZipEntry.DEFLATED && method != -1) unsupported++
            val s = if (size >= 0) size else -1L
            val c = if (compressedSize >= 0) compressedSize else -1L
            if (isDirectory) {
                folders++
            } else {
                files++
                if (s < 0) sizeUnknown = true else bytes = saturatingAdd(bytes, s) { sizeUnknown = true }
                if (c >= 0) compressed = saturatingAdd(compressed, c) {}
            }
            if (shown.size < maxEntries) {
                shown += ZipEntryInfo(
                    path = if (isUnsafe) raw.trimEnd('/') else segments.joinToString("/"),
                    isDirectory = isDirectory,
                    sizeBytes = if (isDirectory) 0 else s,
                    compressedBytes = if (isDirectory) 0 else c,
                    modifiedMillis = time,
                    unsafe = isUnsafe,
                )
            }
        }

        fun result(encrypted: Boolean, unsupportedFromDirectory: Int, charsetName: String, readable: Boolean) = ZipContents.Listed(
            entries = shown,
            totalEntries = total,
            files = files,
            folders = folders,
            totalBytes = bytes,
            compressedBytes = compressed,
            sizeUnknown = sizeUnknown,
            unsafeEntries = unsafe,
            macosEntries = macos,
            unsupportedEntries = maxOf(unsupported, unsupportedFromDirectory),
            encrypted = encrypted,
            charsetName = charsetName,
            readableByAndroid = readable,
        )
    }

    /** Summe, die beim größten Wert stehen bleibt (gefälschte Größenangaben dürfen nie ins Negative kippen). */
    internal inline fun saturatingAdd(sum: Long, value: Long, onOverflow: () -> Unit): Long =
        if (value > Long.MAX_VALUE - sum) {
            onOverflow()
            Long.MAX_VALUE
        } else {
            sum + value
        }

    private fun list(zip: ZipFile, charset: Charset, directory: CentralDirectory?, maxEntries: Int): ZipContents.Listed {
        val tally = Tally()
        val entries = zip.entries()
        while (entries.hasMoreElements()) {
            val e = entries.nextElement()
            tally.add(e.name, e.isDirectory, e.size, e.compressedSize, e.time, e.method, maxEntries)
        }
        return tally.result(
            encrypted = (directory?.encrypted ?: 0) > 0,
            unsupportedFromDirectory = directory?.unsupportedMethods ?: 0,
            charsetName = if (charset == Charsets.UTF_8) "UTF-8" else "IBM-437",
            readable = true,
        )
    }

    private fun fromDirectory(d: CentralDirectory): ZipContents.Listed {
        val tally = Tally()
        for (r in d.kept) tally.add(r.name, r.name.endsWith('/'), r.size, r.compressedSize, r.timeMillis, r.method, Int.MAX_VALUE)
        // Über die behaltenen hinaus nur zählen (Größen und Arten sind dann nicht bekannt).
        val missing = d.records - d.kept.size
        if (missing > 0) {
            tally.total += missing
            tally.files += missing
            tally.sizeUnknown = true
        }
        return tally.result(d.encrypted > 0, d.unsupportedMethods, d.charsetName, readable = false)
    }
}

/**
 * Zentrales Verzeichnis eines ZIP-Archivs, selbst gelesen (ZIP64 und vorangestellte Programme werden unterstützt).
 * Behält höchstens `maxEntries` Einträge mit Namen und Größen, zählt aber alle.
 */
internal class CentralDirectory(
    val records: Int,
    val encrypted: Int,
    val unsupportedMethods: Int,
    val kept: List<Record>,
    val charsetName: String,
) {
    class Record(val name: String, val method: Int, val size: Long, val compressedSize: Long, val timeMillis: Long)

    companion object {
        private const val EOCD = 0x06054b50
        private const val ZIP64_LOCATOR = 0x07064b50
        private const val ZIP64_EOCD = 0x06064b50
        private const val CEN = 0x02014b50
        private const val MAX_COMMENT = 0xFFFF
        private const val MAX_DIRECTORY_BYTES = 64L * 1024 * 1024
        private const val U32_MAX = 0xFFFFFFFFL

        fun scan(file: File, maxEntries: Int = Int.MAX_VALUE): CentralDirectory = RandomAccessFile(file, "r").use { raf ->
            val length = raf.length()
            if (length < 22) throw IOException("zu kurz für ein ZIP-Archiv")
            val tailSize = minOf(length, 22L + MAX_COMMENT).toInt()
            val tail = ByteArray(tailSize)
            val tailStart = length - tailSize
            raf.seek(tailStart)
            raf.readFully(tail)
            var eocd = -1
            for (i in tailSize - 22 downTo 0) {
                if (le32(tail, i) == EOCD) {
                    eocd = i
                    break
                }
            }
            if (eocd < 0) throw IOException("Ende des Inhaltsverzeichnisses nicht gefunden")
            val eocdAbs = tailStart + eocd
            var size = le32(tail, eocd + 12).toLong() and U32_MAX
            val offset32 = le32(tail, eocd + 16).toLong() and U32_MAX
            val count16 = le16(tail, eocd + 10)
            // Wo das Verzeichnis tatsächlich beginnt: unmittelbar vor seinem Ende. So stimmt es auch, wenn dem Archiv
            // ein Programm vorangestellt ist (Angaben im Archiv sind dann relativ zum Archivbeginn).
            var start = eocdAbs - size
            if (count16 == 0xFFFF || size == U32_MAX || offset32 == U32_MAX) {
                val loc = eocd - 20
                if (loc >= 0 && le32(tail, loc) == ZIP64_LOCATOR) {
                    val stated = le64(tail, loc + 8)
                    val header = ByteArray(56)
                    // Meist direkt vor dem Locator; sonst die Angabe im Locator.
                    val candidates = listOf(tailStart + loc - 56, stated).filter { it >= 0 && it + 56 <= length }
                    var found = -1L
                    for (c in candidates) {
                        raf.seek(c)
                        raf.readFully(header)
                        if (le32(header, 0) == ZIP64_EOCD) {
                            found = c
                            break
                        }
                    }
                    if (found < 0) throw IOException("ZIP64-Verzeichnis ungültig")
                    size = le64(header, 40)
                    start = found - size
                }
            }
            if (size < 0 || size > MAX_DIRECTORY_BYTES || start < 0 || start + size > length) throw IOException("Inhaltsverzeichnis ungültig")
            val dir = ByteArray(size.toInt())
            raf.seek(start)
            raf.readFully(dir)
            parse(dir, maxEntries)
        }

        private fun parse(dir: ByteArray, maxEntries: Int): CentralDirectory {
            var pos = 0
            var n = 0
            var encrypted = 0
            var unsupported = 0
            var allUtf8 = true
            val kept = ArrayList<Record>()
            val rawNames = ArrayList<Pair<ByteArray, Boolean>>()
            val meta = ArrayList<LongArray>()
            while (pos + 46 <= dir.size && le32(dir, pos) == CEN) {
                val flag = le16(dir, pos + 8)
                val method = le16(dir, pos + 10)
                val dosTime = le16(dir, pos + 12)
                val dosDate = le16(dir, pos + 14)
                var compressed = le32(dir, pos + 20).toLong() and U32_MAX
                var size = le32(dir, pos + 24).toLong() and U32_MAX
                val nameLen = le16(dir, pos + 28)
                val extraLen = le16(dir, pos + 30)
                val commentLen = le16(dir, pos + 32)
                val record = 46 + nameLen + extraLen + commentLen
                if (pos + record > dir.size) break
                if (flag and 1 != 0 || method == 99) encrypted++
                if (method != 0 && method != 8 && method != 99) unsupported++
                if (rawNames.size < maxEntries) {
                    // ZIP64-Zusatzfeld: echte Größen, wenn die 32-Bit-Felder voll sind.
                    if (size == U32_MAX || compressed == U32_MAX) {
                        var e = pos + 46 + nameLen
                        val end = e + extraLen
                        while (e + 4 <= end) {
                            val id = le16(dir, e)
                            val len = le16(dir, e + 2)
                            if (id == 0x0001) {
                                var p = e + 4
                                if (size == U32_MAX && p + 8 <= e + 4 + len) {
                                    size = le64(dir, p)
                                    p += 8
                                }
                                if (compressed == U32_MAX && p + 8 <= e + 4 + len) compressed = le64(dir, p)
                                break
                            }
                            e += 4 + len
                        }
                    }
                    val name = dir.copyOfRange(pos + 46, pos + 46 + nameLen)
                    val utf8Flag = flag and 0x800 != 0
                    if (!utf8Flag && !isValidUtf8(name)) allUtf8 = false
                    rawNames += name to utf8Flag
                    meta += longArrayOf(method.toLong(), size, compressed, dosToMillis(dosDate, dosTime))
                }
                pos += record
                n++
            }
            // Wie beim Entpacken: alle Namen in UTF-8, wenn das für alle geht – sonst IBM-437 (alte Windows-Archive).
            val fallback = if (allUtf8) Charsets.UTF_8 else ZipContentsReader.IBM_437
            for (i in rawNames.indices) {
                val (bytes, utf8Flag) = rawNames[i]
                val m = meta[i]
                kept += Record(String(bytes, if (utf8Flag) Charsets.UTF_8 else fallback), m[0].toInt(), m[1], m[2], m[3])
            }
            return CentralDirectory(n, encrypted, unsupported, kept, if (allUtf8) "UTF-8" else "IBM-437")
        }

        private fun isValidUtf8(bytes: ByteArray): Boolean = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
            true
        } catch (e: CharacterCodingException) {
            false
        }

        /** DOS-Zeitstempel (Ortszeit, 2-s-Raster) in Millisekunden; 0 bei ungültigen Angaben. */
        private fun dosToMillis(date: Int, time: Int): Long = try {
            LocalDateTime.of(1980 + (date shr 9 and 0x7F), date shr 5 and 0x0F, date and 0x1F, time shr 11 and 0x1F, time shr 5 and 0x3F, (time and 0x1F) * 2)
                .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        } catch (e: java.time.DateTimeException) {
            0L
        }

        private fun le16(b: ByteArray, i: Int): Int = (b[i].toInt() and 0xFF) or ((b[i + 1].toInt() and 0xFF) shl 8)

        private fun le32(b: ByteArray, i: Int): Int = le16(b, i) or (le16(b, i + 2) shl 16)

        private fun le64(b: ByteArray, i: Int): Long = (le32(b, i).toLong() and U32_MAX) or ((le32(b, i + 4).toLong() and U32_MAX) shl 32)
    }
}
