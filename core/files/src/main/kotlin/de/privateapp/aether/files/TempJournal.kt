package de.privateapp.aether.files

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/*
 * Journal der Zwischendateien („*.aether-part“), damit nach einem Absturz oder einem beendeten Prozess nichts Halbes
 * auf dem Speicher liegen bleibt.
 *
 * Ablauf: Die FileOperationEngine trägt jede Zwischendatei ein, bevor sie sie anlegt, und trägt sie wieder aus, sobald
 * sie umbenannt oder entfernt ist. Beim nächsten Start ruft die App [TempJournal.recoverLeftovers] auf.
 *
 * Sicherheitsregeln beim Aufräumen:
 *  - Gelöscht wird nur, was im Journal steht, noch existiert UND auf „.aether-part“ endet – niemals sonst etwas.
 *  - Sonderfall „Bestätigt“ (nur im seltenen Ausweichweg beim Ersetzen, wenn atomares Ersetzen scheitert): Dann ist die
 *    Zwischendatei bereits vollständig und das Original wird gerade ersetzt. Fehlt das Ziel nach einem Absturz, wird
 *    die Zwischendatei an seinen Platz gesetzt (vorwärts vollendet) statt gelöscht – so geht nie die einzige
 *    vollständige Fassung verloren. Dieser Eintrag wird sofort auf das Medium geschrieben (fsync).
 *
 * Format: eine Zeile je Ereignis („+Pfad“, „-Pfad“, „=Zwischendatei<TAB>Ziel“), UTF-8, Steuerzeichen maskiert.
 * Beschädigte Zeilen oder eine unlesbare Datei werden übergangen. Eine Instanz je Datei; threadsicher.
 */

/** Journal der Zwischendateien in [file] (z. B. im privaten App-Speicher). */
class TempJournal(private val file: File) {

    private val lock = Any()

    /** Zwischendatei → Ziel (nur bei „bestätigt“, sonst `null`). Erst beim ersten Zugriff gelesen. */
    private var state: LinkedHashMap<String, String?>? = null
    private var lines = 0

    /** Zwischendatei [path] wird gleich angelegt. Fehler beim Schreiben des Journals werden ignoriert. */
    fun add(path: String) {
        synchronized(lock) {
            loaded()[path] = null
            appendQuietly("+" + escape(path))
        }
    }

    /** Zwischendatei [path] existiert nicht mehr (umbenannt oder gelöscht). */
    fun remove(path: String) {
        synchronized(lock) {
            val current = loaded()
            if (!current.containsKey(path)) return
            current.remove(path)
            if (current.isEmpty()) {
                clearFile()
            } else {
                appendQuietly("-" + escape(path))
            }
        }
    }

    /**
     * [tempPath] ist vollständig und ersetzt gleich [targetPath]. Wird sofort auf das Medium geschrieben; scheitert
     * das, wird eine [IOException] geworfen und das Original darf NICHT angetastet werden.
     */
    internal fun commit(tempPath: String, targetPath: String) {
        synchronized(lock) {
            append("=" + escape(tempPath) + "\t" + escape(targetPath), sync = true)
            loaded()[tempPath] = targetPath
        }
    }

    /**
     * Räumt Reste früherer Läufe auf und leert das Journal. Liefert die Pfade der aufgeräumten Zwischendateien
     * (gelöscht oder – bei „bestätigt“ – an ihr Ziel gesetzt). Einträge, die sich nicht aufräumen ließen, bleiben für
     * den nächsten Versuch im Journal.
     */
    fun recoverLeftovers(): List<String> {
        synchronized(lock) {
            val handled = ArrayList<String>()
            val keep = LinkedHashMap<String, String?>()
            for ((tempPath, targetPath) in loaded()) {
                if (!tempPath.endsWith(FileNames.TEMP_SUFFIX)) continue
                val temp = File(tempPath)
                if (!Fs.exists(temp)) continue
                if (targetPath != null && !Fs.exists(File(targetPath))) {
                    try {
                        Fs.atomicMove(temp, File(targetPath))
                        handled += tempPath
                    } catch (e: IOException) {
                        keep[tempPath] = targetPath // einzige vollständige Fassung – nie löschen
                    }
                    continue
                }
                if (Fs.deleteRecursively(temp)) handled += tempPath else keep[tempPath] = targetPath
            }
            state = keep
            if (keep.isEmpty()) clearFile() else rewriteQuietly()
            return handled
        }
    }

    private fun loaded(): LinkedHashMap<String, String?> {
        state?.let { return it }
        val parsed = LinkedHashMap<String, String?>()
        var count = 0
        val text = try {
            if (file.isFile) String(Files.readAllBytes(file.toPath()), Charsets.UTF_8) else ""
        } catch (e: IOException) {
            ""
        } catch (e: SecurityException) {
            ""
        }
        for (line in text.split('\n')) {
            if (line.isEmpty()) continue
            count++
            val body = line.substring(1)
            when (line[0]) {
                '+' -> unescape(body)?.let { parsed[it] = null }
                '-' -> unescape(body)?.let { parsed.remove(it) }
                '=' -> {
                    val tab = body.indexOf('\t')
                    if (tab < 0) continue
                    val temp = unescape(body.substring(0, tab)) ?: continue
                    val target = unescape(body.substring(tab + 1)) ?: continue
                    parsed[temp] = target
                }
                else -> Unit // beschädigte Zeile
            }
        }
        lines = count
        state = parsed
        return parsed
    }

    private fun appendQuietly(line: String) {
        try {
            append(line, sync = false)
        } catch (e: IOException) {
            // Das Journal ist eine Absicherung; ohne Eintrag wird ein Rest nur nicht automatisch entfernt.
        } catch (e: SecurityException) {
            // dito
        }
    }

    private fun append(line: String, sync: Boolean) {
        file.parentFile?.mkdirs()
        FileOutputStream(file, true).use { out ->
            out.write((line + "\n").toByteArray(Charsets.UTF_8))
            if (sync) out.syncToDisk()
        }
        lines++
        if (lines > COMPACT_AFTER_LINES) rewriteQuietly()
    }

    /** Schreibt nur die aktuellen Einträge neu (atomar über eine Zwischendatei). */
    private fun rewriteQuietly() {
        val current = state ?: return
        val content = buildString {
            for ((temp, target) in current) {
                if (target == null) append('+').append(escape(temp)) else
                    append('=').append(escape(temp)).append('\t').append(escape(target))
                append('\n')
            }
        }
        val tmp = File(file.path + ".tmp")
        try {
            file.parentFile?.mkdirs()
            FileOutputStream(tmp).use { out ->
                out.write(content.toByteArray(Charsets.UTF_8))
                out.syncToDisk()
            }
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            lines = current.size
        } catch (e: IOException) {
            tmp.delete()
        } catch (e: SecurityException) {
            tmp.delete()
        }
    }

    private fun clearFile() {
        try {
            file.delete()
        } catch (e: SecurityException) {
            // nichts zu tun
        }
        lines = 0
    }

    private companion object {
        const val COMPACT_AFTER_LINES = 512

        fun escape(s: String): String = buildString(s.length) {
            for (c in s) {
                when (c) {
                    '\\' -> append("\\\\")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> append(c)
                }
            }
        }

        fun unescape(s: String): String? {
            if (s.isEmpty()) return null
            val out = StringBuilder(s.length)
            var i = 0
            while (i < s.length) {
                val c = s[i]
                if (c != '\\') {
                    out.append(c)
                    i++
                    continue
                }
                if (i + 1 >= s.length) return null
                when (s[i + 1]) {
                    '\\' -> out.append('\\')
                    'n' -> out.append('\n')
                    'r' -> out.append('\r')
                    't' -> out.append('\t')
                    else -> return null
                }
                i += 2
            }
            return out.toString()
        }
    }
}
