package de.privateapp.aether.files

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Abbruch mitten im Vorgang: keine Zwischendateien, ehrlicher Teilbericht, Fertiges bleibt. */
class CancellationTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    /** Startet [operation], bricht ab, sobald [cancelWhen] zutrifft, und liefert den Bericht. */
    private fun runAndCancel(
        operation: FileOperation,
        resolver: ConflictResolver = NoConflictExpected,
        cancelWhen: (File, Long) -> Boolean,
    ): OperationReport {
        var report: OperationReport? = null
        blocking {
            val engine = box.engine(bufferSize = 1024)
            val job = launch(Dispatchers.Default, start = CoroutineStart.LAZY) { report = engine.run(operation, resolver) }
            engine.hooks.onChunkWritten = { target, written -> if (cancelWhen(target, written)) job.cancel() }
            job.start()
            job.join()
        }
        assertNotNull("run() muss auch nach Abbruch einen Bericht liefern", report)
        return report!!
    }

    @Test
    fun cancelMidCopyLeavesNoTempFilesAndAPartialReport() {
        val small = box.vol1.writeBytesFile("1-klein.bin", pseudoRandomBytes(3_000))
        val large = box.vol1.writeBytesFile("2-gross.bin", pseudoRandomBytes(200_000))
        val never = box.vol1.writeBytesFile("3-nie.bin", pseudoRandomBytes(3_000))
        val target = box.vol2.dir("Ziel")
        val report = runAndCancel(FileOperation.Copy(listOf(small.path, large.path, never.path), target.path)) { file, written ->
            file.name.startsWith("2-gross") && written >= 50_000
        }
        assertTrue(report.cancelled)
        assertEquals(1, report.succeeded)
        assertEquals(listOf(File(target, "1-klein.bin").path), report.createdPaths)
        assertEquals(listOf("1-klein.bin"), target.list()!!.toList())
        assertArrayEquals(small.readBytes(), File(target, "1-klein.bin").readBytes())
        assertTrue(large.exists())
        assertTrue(never.exists())
        box.assertNoLeftovers()
    }

    @Test
    fun cancelDuringCrossVolumeMoveKeepsTheSource() {
        val data = pseudoRandomBytes(100_000)
        val src = box.vol1.writeBytesFile("video.mp4", data)
        val target = box.vol2.dir("Ziel")
        val report = runAndCancel(FileOperation.Move(listOf(src.path), target.path)) { _, written -> written >= 30_000 }
        assertTrue(report.cancelled)
        assertEquals(0, report.succeeded)
        assertArrayEquals(data, src.readBytes())
        assertEquals(0, target.list()!!.size)
        assertEquals(emptyList<String>(), report.removedPaths)
        box.assertNoLeftovers()
    }

    @Test
    fun cancelDuringExtractRemovesThePartFolder() {
        val archive = File(box.vol1, "gross.zip")
        ZipOutputStream(archive.outputStream()).use { zip ->
            for (i in 1..5) {
                zip.putNextEntry(ZipEntry("Inhalt/$i.bin"))
                zip.write(pseudoRandomBytes(40_000, seed = i))
                zip.closeEntry()
            }
        }
        val target = box.vol2.dir("Ziel")
        val report = runAndCancel(FileOperation.Extract(archive.path, target.path)) { file, _ -> file.name == "3.bin" }
        assertTrue(report.cancelled)
        assertEquals(0, target.list()!!.size)
        assertEquals(emptyList<String>(), report.createdPaths)
        box.assertNoLeftovers()
    }

    @Test
    fun cancelWhileWaitingForTheUserWritesNothing() = blocking {
        val target = box.vol2.dir("Ziel")
        target.writeTextFile("a.txt", "alt")
        val src = box.vol1.writeTextFile("a.txt", "neu")
        val asked = CompletableDeferred<Unit>()
        val resolver = ConflictResolver {
            asked.complete(Unit)
            CompletableDeferred<Resolution>().await() // Nutzer antwortet nie
        }
        var report: OperationReport? = null
        val job = launch(Dispatchers.Default) {
            report = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), resolver)
        }
        asked.await()
        delay(20)
        job.cancel()
        job.join()
        val result = report!!
        assertTrue(result.cancelled)
        assertEquals(0, result.succeeded)
        assertEquals("alt", File(target, "a.txt").readText())
        box.assertNoLeftovers()
    }

    @Test
    fun alreadyCancelledCallerGetsAnEmptyCancelledReport() = blocking {
        val src = box.vol1.writeTextFile("a.txt", "a")
        var report: OperationReport? = null
        val job = launch {
            kotlinx.coroutines.currentCoroutineContext()[Job]!!.cancel()
            report = box.engine().run(FileOperation.Copy(listOf(src.path), box.vol2.path), NoConflictExpected)
        }
        job.join()
        assertTrue(report!!.cancelled)
        assertFalse(File(box.vol2, "a.txt").exists())
    }
}
