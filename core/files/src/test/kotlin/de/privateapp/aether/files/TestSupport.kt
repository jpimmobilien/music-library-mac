package de.privateapp.aether.files

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

/*
 * Testumgebung: echte Dateien in einem temporären Ordner, zwei simulierte Speicher („vol1“ = intern, „vol2“ =
 * SD-Karte) und eine VolumeLayout, die Pfade diesen Speichern zuordnet. Da beide auf demselben Dateisystem liegen,
 * entscheidet die Engine allein über die Zuordnung, ob umbenannt oder geprüft kopiert wird – wie auf dem Gerät.
 */

internal class Sandbox(val root: File) {
    val vol1: File = File(root, "vol1").apply { mkdirs() }
    val vol2: File = File(root, "vol2").apply { mkdirs() }
    val journalFile = File(root, "app/temp-journal")
    val journal = TempJournal(journalFile)
    private var now = 1_700_000_000_000L

    val layout = VolumeLayout { path ->
        listOf(vol1, vol2).firstOrNull { path == it.path || path.startsWith(it.path + "/") }?.path
    }

    val trash = TrashStore(layout) { now++ }

    fun engine(bufferSize: Int = 4096) = FileOperationEngine(layout, trash, journal, bufferSize = bufferSize)

    /** Alle Zwischendateien unter dem Testordner (es dürfen nach einem Vorgang keine übrig sein). */
    fun leftovers(): List<File> = root.walkTopDown().filter { it.name.endsWith(FileNames.TEMP_SUFFIX) }.toList()

    fun assertNoLeftovers() {
        assertEquals("Zwischendateien übrig", emptyList<File>(), leftovers())
        assertEquals("Journal nicht leer", emptyList<String>(), TempJournal(journalFile).recoverLeftovers())
    }
}

internal fun File.writeTextFile(relative: String, text: String): File =
    File(this, relative).also {
        it.parentFile.mkdirs()
        it.writeText(text)
    }

internal fun File.writeBytesFile(relative: String, bytes: ByteArray): File =
    File(this, relative).also {
        it.parentFile.mkdirs()
        it.writeBytes(bytes)
    }

internal fun File.dir(relative: String): File = File(this, relative).also { it.mkdirs() }

/** Relativer Pfad → Inhalt (Ordner mit „/“ am Ende) – zum Vergleichen ganzer Bäume. */
internal fun File.snapshot(): Map<String, String> =
    walkTopDown().filter { it != this }.associate { f ->
        val rel = f.relativeTo(this).path
        if (f.isDirectory) "$rel/" to "" else rel to f.readText()
    }

internal fun pseudoRandomBytes(size: Int, seed: Int = 7): ByteArray {
    var x = seed
    return ByteArray(size) {
        x = x * 1103515245 + 12345
        (x ushr 16).toByte()
    }
}

/** Resolver, der immer gleich entscheidet und mitzählt. */
internal class FixedResolver(private val choice: ConflictChoice, private val applyToAll: Boolean = false) : ConflictResolver {
    val calls = AtomicInteger()
    val conflicts = ArrayList<Conflict>()

    override suspend fun resolve(conflict: Conflict): Resolution {
        calls.incrementAndGet()
        synchronized(conflicts) { conflicts += conflict }
        return Resolution(choice, applyToAll)
    }
}

/** Resolver für Fälle ohne Konflikt: jeder Aufruf ist ein Testfehler. */
internal val NoConflictExpected = ConflictResolver { conflict ->
    throw AssertionError("Unerwarteter Konflikt: ${conflict.source.path} ↔ ${conflict.existing.path}")
}

/** Testkörper in runBlocking; liefert immer Unit (JUnit verlangt void-Methoden). */
internal fun blocking(block: suspend CoroutineScope.() -> Unit) {
    runBlocking { block() }
}

internal fun assertComplete(report: OperationReport) {
    assertTrue("Fehler: ${report.failures}", report.failures.isEmpty())
    assertTrue("abgebrochen", !report.cancelled)
}
