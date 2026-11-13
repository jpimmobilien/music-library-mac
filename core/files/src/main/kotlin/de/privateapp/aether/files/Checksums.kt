package de.privateapp.aether.files

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.security.MessageDigest

/** Prüfsummen von Dateien – z. B. um eine Kopie oder einen Download mit der Angabe des Anbieters zu vergleichen. */
object Checksums {

    /**
     * SHA-256 von [path] als Kleinbuchstaben-Hex (64 Zeichen). Läuft auf IO, lässt sich abbrechen
     * (CancellationException) und meldet den Fortschritt in Byte. Wirft [IOException], wenn die Datei nicht lesbar ist.
     */
    suspend fun sha256(path: String, bufferSize: Int = 256 * 1024, onProgress: (bytesRead: Long) -> Unit = {}): String =
        withContext(Dispatchers.IO) {
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(bufferSize.coerceAtLeast(4096))
            var total = 0L
            try {
                FileInputStream(File(Fs.normalize(path))).use { input ->
                    while (true) {
                        currentCoroutineContext().ensureActive()
                        val n = input.read(buffer)
                        if (n < 0) break
                        digest.update(buffer, 0, n)
                        total += n
                        onProgress(total)
                    }
                }
            } catch (e: SecurityException) {
                throw IOException(e.message, e)
            }
            toHex(digest.digest())
        }

    internal fun toHex(bytes: ByteArray): String {
        val digits = "0123456789abcdef"
        val out = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            out.append(digits[v ushr 4]).append(digits[v and 0x0F])
        }
        return out.toString()
    }
}
