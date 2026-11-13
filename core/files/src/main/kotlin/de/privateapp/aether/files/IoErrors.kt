package de.privateapp.aether.files

import java.io.FileNotFoundException
import java.nio.file.FileSystemException as NioFileSystemException
import java.nio.file.NoSuchFileException as NioNoSuchFileException
import java.nio.file.AccessDeniedException as NioAccessDeniedException
import java.nio.file.ReadOnlyFileSystemException

/*
 * Übersetzt technische Ein-/Ausgabefehler in verständliche Gründe ([FailureReason]).
 *
 * Android meldet viele Fehler nur als Text mit dem Fehlercode des Linux-Kernels, etwa
 * „/storage/1234-ABCD/a.txt: open failed: EACCES (Permission denied)“. Deshalb werden neben den Ausnahmetypen die
 * bekannten Fehlercodes (errno) und ihre englischen Standardtexte erkannt – aber nur im Teil der Meldung, der den
 * Grund nennt, nicht im Pfad: Eine Datei „No space left.txt“ darf keinen falschen Grund auslösen.
 */

/** Ordnet Ausnahmen einem [FailureReason] zu. */
object IoErrors {

    fun classify(e: Throwable): FailureReason {
        var current: Throwable? = e
        var depth = 0
        while (current != null && depth < 8) {
            classifyOne(current)?.let { return it }
            current = current.cause
            depth++
        }
        return FailureReason.IO_ERROR
    }

    private fun classifyOne(t: Throwable): FailureReason? = when (t) {
        is NioAccessDeniedException -> FailureReason.ACCESS_DENIED
        is NioNoSuchFileException -> FailureReason.NOT_FOUND
        is NioFileSystemException -> byText(t.reason)
        is kotlin.io.AccessDeniedException -> FailureReason.ACCESS_DENIED
        is kotlin.io.NoSuchFileException -> FailureReason.NOT_FOUND
        is kotlin.io.FileSystemException -> byText(t.reason)
        is ReadOnlyFileSystemException -> FailureReason.READ_ONLY
        is FileNotFoundException -> byText(reasonPart(t.message)) ?: FailureReason.NOT_FOUND
        else -> byText(reasonPart(t.message))
    }

    /** Der Teil einer Meldung, der den Grund nennt: nach „failed:“ (Android) bzw. in der letzten Klammer (JVM). */
    private fun reasonPart(message: String?): String? {
        if (message == null) return null
        val failed = message.lastIndexOf("failed:")
        if (failed >= 0) return message.substring(failed + "failed:".length)
        val paren = message.lastIndexOf(" (")
        if (paren >= 0 && message.endsWith(")")) return message.substring(paren + 2)
        return message
    }

    private fun byText(text: String?): FailureReason? {
        if (text.isNullOrBlank()) return null
        // Fehlercodes exakt (Großbuchstaben), Standardtexte ohne Rücksicht auf Groß-/Kleinschreibung.
        fun has(codes: List<String>, texts: List<String>) =
            codes.any { text.contains(it) } || texts.any { text.contains(it, ignoreCase = true) }
        return when {
            has(listOf("ENOSPC", "EDQUOT"), listOf("No space left", "Disk quota exceeded")) -> FailureReason.NO_SPACE
            has(listOf("EFBIG"), listOf("File too large")) -> FailureReason.FILE_TOO_LARGE
            has(listOf("EROFS"), listOf("Read-only file system")) -> FailureReason.READ_ONLY
            has(listOf("ENAMETOOLONG", "EINVAL"), listOf("File name too long", "Invalid argument")) ->
                FailureReason.INVALID_NAME
            has(listOf("EACCES", "EPERM"), listOf("Permission denied", "Operation not permitted")) ->
                FailureReason.ACCESS_DENIED
            has(listOf("ENOENT"), listOf("No such file or directory")) -> FailureReason.NOT_FOUND
            else -> null
        }
    }
}
