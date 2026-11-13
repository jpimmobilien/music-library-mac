package de.privateapp.aether.files

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files

/**
 * Abgebrochene oder teilweise erledigte Einträge: Der Bericht nennt jede einzelne Änderung darin (für Medienindex und
 * Anzeige), zählt die fertigen und die am Ursprungsort verbliebenen Dateien – und die Zusammenfassung sagt nie
 * „nichts geändert“, wenn sich etwas geändert hat.
 */
class PartialReportTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    private fun runWithCancel(engine: FileOperationEngine, operation: FileOperation, arm: (cancel: () -> Unit) -> Unit): OperationReport {
        var report: OperationReport? = null
        blocking {
            val job = launch(Dispatchers.Default, start = CoroutineStart.LAZY) { report = engine.run(operation, NoConflictExpected) }
            arm { job.cancel() }
            job.start()
            job.join()
        }
        return report!!
    }

    @Test
    fun cancelledCrossVolumeFolderMoveReportsEveryMovedFile() {
        val album = box.vol1.dir("Album")
        for (i in 1..4) album.writeBytesFile("$i.bin", pseudoRandomBytes(40_000, seed = i))
        val target = box.vol2.dir("Ziel")
        val engine = box.engine(bufferSize = 1024)
        val report = runWithCancel(engine, FileOperation.Move(listOf(album.path), target.path)) { cancel ->
            engine.hooks.onChunkWritten = { file, written -> if (file.name.startsWith("3.bin") && written >= 10_000) cancel() }
        }
        assertTrue(report.cancelled)
        assertEquals(0, report.succeeded)
        assertEquals(listOf("3.bin", "4.bin"), album.list()!!.sorted())
        val movedAlbum = File(target, "Album")
        assertEquals(listOf("1.bin", "2.bin"), movedAlbum.list()!!.sorted())
        assertEquals(
            setOf(movedAlbum.path, File(movedAlbum, "1.bin").path, File(movedAlbum, "2.bin").path),
            report.createdPaths.toSet(),
        )
        assertEquals(setOf(File(album, "1.bin").path, File(album, "2.bin").path), report.removedPaths.toSet())
        assertEquals(2, report.partialFilesDone)
        assertEquals(2, report.partialFilesLeft)

        val summary = OperationTexts.summary(report)
        assertEquals("Verschieben abgebrochen", summary.headline)
        assertTrue(summary.detail!!, summary.detail.orEmpty().contains("2 Dateien liegen bereits im Ziel, 2 Dateien noch am Ursprungsort."))
        assertFalse(summary.detail.orEmpty().contains("nichts geändert"))
        assertTrue("geteilter Ordner verlangt Aufmerksamkeit", summary.isProblem)
        box.assertNoLeftovers()
    }

    @Test
    fun cancelledPermanentDeleteReportsWhatIsGone() {
        val big = box.vol1.dir("Gross")
        for (i in 1..60) big.writeTextFile("sub$i/f.txt", "x")
        var clock = 0L
        val engine = FileOperationEngine(box.layout, box.trash, box.journal, clock = { clock += 1_000; clock })
        var report: OperationReport? = null
        blocking {
            lateinit var cancel: () -> Unit
            val job = launch(Dispatchers.Default, start = CoroutineStart.LAZY) {
                report = engine.run(FileOperation.DeletePermanently(listOf(big.path)), NoConflictExpected) { progress ->
                    if (progress.phase == OperationPhase.RUNNING && progress.completedItems >= 20) cancel()
                }
            }
            cancel = { job.cancel() }
            job.start()
            job.join()
        }
        val r = report!!
        assertTrue(r.cancelled)
        assertTrue(big.exists())
        val gone = r.removedPaths
        assertTrue("gelöschte Einträge stehen im Bericht", gone.size >= 20)
        assertTrue(gone.all { !File(it).exists() })
        assertTrue(r.partialFilesDone >= 10)
        val summary = OperationTexts.summary(r)
        assertTrue(summary.detail!!, summary.detail.orEmpty().contains("bereits endgültig gelöscht"))
        assertFalse(summary.detail.orEmpty().contains("nichts geändert"))
    }

    @Test
    fun cancelledFolderCopyReportsFinishedFiles() {
        val folder = box.vol1.dir("Fotos")
        for (i in 1..3) folder.writeBytesFile("$i.jpg", pseudoRandomBytes(30_000, seed = i))
        val target = box.vol2.dir("Ziel")
        val engine = box.engine(bufferSize = 1024)
        val report = runWithCancel(engine, FileOperation.Copy(listOf(folder.path), target.path)) { cancel ->
            engine.hooks.onChunkWritten = { file, written -> if (file.name.startsWith("2.jpg") && written >= 5_000) cancel() }
        }
        assertTrue(report.cancelled)
        val copy = File(target, "Fotos")
        assertEquals(setOf(copy.path, File(copy, "1.jpg").path), report.createdPaths.toSet())
        assertEquals(1, report.partialFilesDone)
        assertEquals(0, report.partialFilesLeft)
        val summary = OperationTexts.summary(report)
        assertEquals("Kopieren abgebrochen", summary.headline)
        assertEquals("1 Datei wurde bereits vollständig kopiert. Unfertige Dateien wurden entfernt.", summary.detail)
        box.assertNoLeftovers()
    }

    @Test
    fun partialMoveAfterAFailedFileListsTheMovedOnes() = blocking {
        val folder = box.vol1.dir("Mix")
        for (name in listOf("a.bin", "b.bin", "c.bin")) folder.writeBytesFile(name, pseudoRandomBytes(5_000, seed = name.hashCode()))
        val target = box.vol2.dir("Ziel")
        val engine = box.engine()
        engine.hooks.afterTempWritten = { temp ->
            if (temp.name.startsWith("b.bin")) {
                RandomAccessFile(temp, "rw").use { raf ->
                    raf.seek(10)
                    val original = raf.read()
                    raf.seek(10)
                    raf.write(original xor 0xFF)
                }
            }
        }
        val report = engine.run(FileOperation.Move(listOf(folder.path), target.path), NoConflictExpected)
        assertEquals(listOf(FailureReason.VERIFICATION_FAILED), report.failures.map { it.reason })
        assertEquals(0, report.succeeded)
        assertEquals(listOf("b.bin"), folder.list()!!.toList())
        assertEquals(setOf(File(folder, "a.bin").path, File(folder, "c.bin").path), report.removedPaths.toSet())
        assertTrue(report.createdPaths.containsAll(listOf(File(target, "Mix/a.bin").path, File(target, "Mix/c.bin").path)))
        assertEquals(2, report.partialFilesDone)
        assertEquals(1, report.partialFilesLeft)
        val summary = OperationTexts.summary(report)
        assertEquals("Verschieben unvollständig", summary.headline)
        assertTrue(summary.detail!!, summary.detail.orEmpty().contains("2 Dateien liegen bereits im Ziel, 1 Datei noch am Ursprungsort."))
        box.assertNoLeftovers()
    }

    @Test
    fun moveWithALinkInsideIsTruthful() = blocking {
        val folder = box.vol1.dir("Mix")
        folder.writeTextFile("a.txt", "a")
        folder.writeTextFile("b.txt", "b")
        Files.createSymbolicLink(File(folder, "link").toPath(), File(folder, "a.txt").toPath())
        val target = box.vol2.dir("Ziel")
        val report = box.engine().run(FileOperation.Move(listOf(folder.path), target.path), NoConflictExpected)
        assertEquals(listOf(FailureReason.SPECIAL_FILE_SKIPPED), report.failures.map { it.reason })
        assertEquals(1, report.succeeded)
        assertEquals(listOf("link"), folder.list()!!.toList())
        assertEquals("verschobene Dateien gelten als entfernt", setOf(File(folder, "a.txt").path, File(folder, "b.txt").path), report.removedPaths.toSet())
        assertFalse("der Ordner selbst existiert noch", folder.path in report.removedPaths)
        val summary = OperationTexts.summary(report)
        assertEquals("1 Objekt verschoben", summary.headline)
        assertEquals("1 Verknüpfung oder Gerätedatei wurde bewusst nicht verschoben und bleibt am Ursprungsort.", summary.detail)
        assertFalse(summary.isProblem)
    }

    @Test
    fun completedItemsReportOnlyTheTopLevelPath() = blocking {
        val folder = box.vol1.dir("Ganz")
        for (i in 1..5) folder.writeTextFile("$i.txt", "$i")
        val target = box.vol2.dir("Ziel")
        val report = box.engine().run(FileOperation.Move(listOf(folder.path), target.path), NoConflictExpected)
        assertComplete(report)
        assertEquals(listOf(File(target, "Ganz").path), report.createdPaths)
        assertEquals(listOf(folder.path), report.removedPaths)
        assertEquals(0, report.partialFilesDone)
    }

    @Test
    fun skippedChildrenInAMergeKeepTheSourceAndSaySo() = blocking {
        val target = box.vol1.dir("Ziel")
        target.writeTextFile("Ordner/gleich.txt", "ziel")
        val src = box.vol1.dir("Quelle/Ordner")
        src.writeTextFile("gleich.txt", "quelle")
        src.writeTextFile("neu.txt", "neu")
        val resolver = ConflictResolver { c -> Resolution(if (c.source.isDirectory) ConflictChoice.MERGE else ConflictChoice.SKIP) }
        val report = box.engine().run(FileOperation.Move(listOf(src.path), target.path), resolver)
        assertComplete(report)
        assertEquals(1, report.partialFilesDone)
        assertEquals(1, report.partialFilesLeft)
        val summary = OperationTexts.summary(report)
        assertFalse(summary.isProblem)
        assertTrue(summary.detail!!, summary.detail.orEmpty().contains("1 Datei liegt bereits im Ziel, 1 Datei noch am Ursprungsort."))
    }
}
