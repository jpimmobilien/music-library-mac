package de.privateapp.aether.files

import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/*
 * Liest den Anfang einer Textdatei für Vorschau und Editor und erkennt dabei die Zeichenkodierung.
 *
 * Erkennung in dieser Reihenfolge:
 *  1. Byte-Order-Mark: UTF-8 (EF BB BF), UTF-16 BE (FE FF), UTF-16 LE (FF FE). Das BOM ist nicht Teil des Textes.
 *  2. Nullbytes in den ersten 8 KB → keine Textdatei ([TextPreview.looksBinary], Text leer).
 *  3. Gültiges UTF-8 → UTF-8 (reines ASCII zählt als UTF-8).
 *  4. Viele ungültige UTF-8-Folgen → windows-1252 (ältere Windows-Dateien, deutsche Umlaute als einzelne Bytes).
 *     Vereinzelte Fehler in sonst gültigem UTF-8 bleiben UTF-8 (mit Ersatzzeichen).
 *
 * Ungültige oder nicht definierte Bytes werden zur Anzeige durch „�“ ersetzt und als [TextPreview.lossy] gemeldet:
 * Sichern würde genau diese Bytes verändern, deshalb bietet die Oberfläche Bearbeiten dann nicht an.
 *
 * Grenzen: UTF-16 ohne BOM wird wegen seiner Nullbytes als „keine Textdatei“ erkannt; andere alte Kodierungen
 * (z. B. kyrillische) erscheinen als windows-1252. Bei abgeschnittener Vorschau wird nie mitten in einem Zeichen
 * getrennt.
 */

/** Textvorschau mit Kodierungserkennung. Wirft nur [IOException]. */
object TextPreviewReader {

    private const val BINARY_PROBE_BYTES = 8 * 1024
    private val WINDOWS_1252: Charset = runCatching { Charset.forName("windows-1252") }.getOrDefault(Charsets.ISO_8859_1)

    /** Erkannte Kodierung eines Dateianfangs. [bom] = die Bytes des Byte-Order-Marks (leer, wenn keines). */
    internal class Detection(val charset: Charset, val bom: ByteArray, val looksBinary: Boolean)

    private class Head(val bytes: ByteArray, val length: Int, val truncated: Boolean)

    /** Liest höchstens [maxBytes] Byte von [path] und dekodiert sie. */
    fun read(path: String, maxBytes: Int = 512 * 1024): TextPreview {
        val head = readHead(File(path), maxBytes.coerceAtLeast(1))
        val detection = detect(head.bytes, head.length, head.truncated)
        if (detection.looksBinary) return TextPreview("", head.truncated, "", looksBinary = true)
        val (text, lossy) = decode(head, detection)
        return TextPreview(text, head.truncated, detection.charset.name(), looksBinary = false, lossy = lossy)
    }

    /** Kodierung einer vorhandenen Datei (für das Zurückschreiben in derselben Kodierung). */
    internal fun detectFile(file: File, maxBytes: Int = 512 * 1024): Detection {
        val head = readHead(file, maxBytes)
        return detect(head.bytes, head.length, head.truncated)
    }

    private fun readHead(file: File, limit: Int): Head {
        try {
            FileInputStream(file).use { input ->
                val buffer = ByteArray(limit + 1)
                var filled = 0
                while (filled < buffer.size) {
                    val n = input.read(buffer, filled, buffer.size - filled)
                    if (n < 0) break
                    filled += n
                }
                val truncated = filled > limit
                return Head(buffer, if (truncated) limit else filled, truncated)
            }
        } catch (e: SecurityException) {
            throw IOException(e.message, e)
        }
    }

    internal fun detect(bytes: ByteArray, length: Int, truncated: Boolean): Detection {
        fun at(i: Int) = bytes[i].toInt() and 0xFF
        if (length >= 3 && at(0) == 0xEF && at(1) == 0xBB && at(2) == 0xBF) {
            return Detection(Charsets.UTF_8, bytes.copyOfRange(0, 3), looksBinary = false)
        }
        if (length >= 2 && at(0) == 0xFE && at(1) == 0xFF) {
            return Detection(Charsets.UTF_16BE, bytes.copyOfRange(0, 2), looksBinary = false)
        }
        if (length >= 2 && at(0) == 0xFF && at(1) == 0xFE) {
            return Detection(Charsets.UTF_16LE, bytes.copyOfRange(0, 2), looksBinary = false)
        }
        val probe = minOf(length, BINARY_PROBE_BYTES)
        for (i in 0 until probe) {
            if (bytes[i].toInt() == 0) return Detection(Charsets.UTF_8, ByteArray(0), looksBinary = true)
        }
        val (validMultibyte, invalid) = scanUtf8(bytes, length, truncated)
        val charset = when {
            invalid == 0 -> Charsets.UTF_8
            validMultibyte == 0 -> WINDOWS_1252
            invalid > validMultibyte -> WINDOWS_1252
            else -> Charsets.UTF_8
        }
        return Detection(charset, ByteArray(0), looksBinary = false)
    }

    /** (gültige Mehrbyte-Folgen, ungültige Folgen). Eine am Ende abgeschnittene Folge zählt nicht als Fehler. */
    private fun scanUtf8(bytes: ByteArray, end: Int, truncated: Boolean): Pair<Int, Int> {
        var valid = 0
        var invalid = 0
        var i = 0
        while (i < end) {
            val lead = bytes[i].toInt() and 0xFF
            if (lead < 0x80) {
                i++
                continue
            }
            val following = when (lead) {
                in 0xC2..0xDF -> 1
                in 0xE0..0xEF -> 2
                in 0xF0..0xF4 -> 3
                else -> -1
            }
            if (following < 0) {
                invalid++
                i++
                continue
            }
            if (i + following >= end) {
                if (!truncated) invalid++
                break
            }
            if (isValidSequence(bytes, i, lead, following)) {
                valid++
                i += following + 1
            } else {
                invalid++
                i++
            }
        }
        return valid to invalid
    }

    private fun isValidSequence(bytes: ByteArray, start: Int, lead: Int, following: Int): Boolean {
        for (k in 1..following) {
            val b = bytes[start + k].toInt() and 0xFF
            if (b !in 0x80..0xBF) return false
        }
        val second = bytes[start + 1].toInt() and 0xFF
        return when (lead) {
            0xE0 -> second >= 0xA0 // keine überlangen Folgen
            0xED -> second <= 0x9F // keine Surrogate
            0xF0 -> second >= 0x90
            0xF4 -> second <= 0x8F // höchstens U+10FFFF
            else -> true
        }
    }

    /**
     * Text und „verlustbehaftet“: Ungültige oder in der Kodierung nicht definierte Bytes werden zur Anzeige durch „�“
     * ersetzt – Sichern würde sie verändern, deshalb wird das gemeldet. Nur das bewusste Abschneiden am Ende einer
     * gekürzten Vorschau zählt nicht dazu.
     */
    private fun decode(head: Head, detection: Detection): Pair<String, Boolean> {
        val start = detection.bom.size
        var end = head.length
        when (detection.charset) {
            Charsets.UTF_8 -> if (head.truncated) end = completeUtf8End(head.bytes, start, end)
            Charsets.UTF_16LE, Charsets.UTF_16BE -> if (head.truncated) {
                if ((end - start) % 2 != 0) end--
                if (end - start >= 2) {
                    // Hohes Surrogat am Ende nicht ohne seinen Partner zeigen.
                    val highByte = if (detection.charset == Charsets.UTF_16LE) head.bytes[end - 1] else head.bytes[end - 2]
                    if ((highByte.toInt() and 0xFC) == 0xD8) end -= 2
                }
            }
            else -> Unit
        }
        return decodeStrict(head.bytes, start, maxOf(start, end), detection.charset)
    }

    /** Dekodiert mit Fehlermeldung statt stillem Ersetzen; liefert (Text mit „�“ an Fehlerstellen, Fehler ja/nein). */
    internal fun decodeStrict(bytes: ByteArray, start: Int, end: Int, charset: Charset): Pair<String, Boolean> {
        val decoder = charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val input = ByteBuffer.wrap(bytes, start, end - start)
        var out = CharBuffer.allocate(end - start + 16)
        var lossy = false
        while (true) {
            val result = decoder.decode(input, out, true)
            when {
                result.isUnderflow -> break
                result.isOverflow -> out = grow(out)
                else -> {
                    lossy = true
                    if (!out.hasRemaining()) out = grow(out)
                    out.put('\uFFFD')
                    input.position(input.position() + result.length())
                }
            }
        }
        while (decoder.flush(out).isOverflow) out = grow(out)
        out.flip()
        return out.toString() to lossy
    }

    private fun grow(buffer: CharBuffer): CharBuffer {
        val bigger = CharBuffer.allocate(buffer.capacity() * 2 + 16)
        buffer.flip()
        bigger.put(buffer)
        return bigger
    }

    /** Ende ohne eine am Schluss angeschnittene UTF-8-Folge. */
    private fun completeUtf8End(bytes: ByteArray, start: Int, end: Int): Int {
        var k = end - 1
        var back = 0
        while (k >= start && back < 4) {
            val b = bytes[k].toInt() and 0xFF
            if ((b and 0xC0) != 0x80) {
                val needed = when {
                    b < 0x80 -> 1
                    b in 0xC2..0xDF -> 2
                    b in 0xE0..0xEF -> 3
                    b in 0xF0..0xF4 -> 4
                    else -> 1
                }
                return if (end - k < needed) k else end
            }
            k--
            back++
        }
        return end
    }
}
