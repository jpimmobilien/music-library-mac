package de.privateapp.aether.files

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.AtomicMoveNotSupportedException

class MoveTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    @Test
    fun sameVolumeMoveIsARename() = blocking {
        val src = box.vol1.writeTextFile("Download/brief.pdf", "pdf")
        val folder = box.vol1.writeTextFile("Download/Ordner/x.txt", "x").parentFile
        val target = box.vol1.dir("Dokumente")
        val engine = box.engine()
        var bytesCopied = 0L
        engine.hooks.onChunkWritten = { _, written -> bytesCopied += written }
        val report = engine.run(FileOperation.Move(listOf(src.path, folder.path), target.path), NoConflictExpected)
        assertComplete(report)
        assertEquals(2, report.succeeded)
        assertEquals("kein Byte kopiert", 0L, bytesCopied)
        assertFalse(src.exists())
        assertFalse(folder.exists())
        assertEquals("pdf", File(target, "brief.pdf").readText())
        assertEquals("x", File(target, "Ordner/x.txt").readText())
        assertEquals(listOf(src.path, folder.path), report.removedPaths)
        assertEquals(listOf(File(target, "brief.pdf").path, File(target, "Ordner").path), report.createdPaths)
    }

    @Test
    fun moveIntoTheSameFolderDoesNothing() = blocking {
        val src = box.vol1.writeTextFile("a.txt", "a")
        val report = box.engine().run(FileOperation.Move(listOf(src.path), box.vol1.path), NoConflictExpected)
        assertComplete(report)
        assertEquals(1, report.succeeded)
        assertEquals("a", src.readText())
        assertEquals(emptyList<String>(), report.createdPaths)
    }

    @Test
    fun crossVolumeMoveIsAVerifiedCopy() = blocking {
        val data = pseudoRandomBytes(123_457)
        val src = box.vol1.writeBytesFile("Musik/lied.flac", data)
        src.setLastModified(1_640_000_000_000L)
        val folder = box.vol1.dir("Alben")
        folder.writeBytesFile("1/a.mp3", pseudoRandomBytes(10_000, seed = 1))
        folder.writeBytesFile("1/b.mp3", pseudoRandomBytes(20_000, seed = 2))
        folder.dir("leer")
        val folderSnapshot = folder.snapshot()
        val target = box.vol2.dir("Musik")
        val report = box.engine().run(FileOperation.Move(listOf(src.path, folder.path), target.path), NoConflictExpected)
        assertComplete(report)
        assertEquals(2, report.succeeded)
        assertFalse(src.exists())
        assertFalse(folder.exists())
        val moved = File(target, "lied.flac")
        assertArrayEquals(data, moved.readBytes())
        assertEquals(1_640_000_000_000L, moved.lastModified())
        assertEquals(folderSnapshot, File(target, "Alben").snapshot())
        assertEquals(123_457L + 30_000L, report.bytesProcessed)
        assertEquals(listOf(src.path, folder.path), report.removedPaths)
        box.assertNoLeftovers()
    }

    @Test
    fun verificationFailureKeepsTheOriginal() = blocking {
        val data = pseudoRandomBytes(30_000)
        val src = box.vol1.writeBytesFile("wichtig.bin", data)
        val target = box.vol2.dir("Ziel")
        val engine = box.engine()
        engine.hooks.afterTempWritten = { temp ->
            RandomAccessFile(temp, "rw").use { raf ->
                raf.seek(12_345)
                val b = raf.read()
                raf.seek(12_345)
                raf.write(b xor 0xFF)
            }
        }
        val report = engine.run(FileOperation.Move(listOf(src.path), target.path), NoConflictExpected)
        assertEquals(FailureReason.VERIFICATION_FAILED, report.failures.single().reason)
        assertEquals(0, report.succeeded)
        assertArrayEquals("Original unverändert", data, src.readBytes())
        assertEquals("keine Kopie im Ziel", 0, target.list()!!.size)
        assertEquals(emptyList<String>(), report.removedPaths)
        box.assertNoLeftovers()
    }

    @Test
    fun sourceChangedDuringMoveIsKept() = blocking {
        val src = box.vol1.writeBytesFile("log.txt", ByteArray(20_000))
        val target = box.vol2.dir("Ziel")
        val engine = box.engine()
        engine.hooks.afterTempWritten = { src.appendText("neue Zeile") }
        val report = engine.run(FileOperation.Move(listOf(src.path), target.path), NoConflictExpected)
        assertEquals(FailureReason.CHANGED_MEANWHILE, report.failures.single().reason)
        assertTrue(src.exists())
        assertEquals(0, target.list()!!.size)
    }

    @Test
    fun crossVolumeReplaceAndMerge() = blocking {
        val target = box.vol2.dir("Ziel")
        target.writeTextFile("a.txt", "alt")
        target.writeTextFile("Fotos/1.jpg", "eins")
        val file = box.vol1.writeTextFile("a.txt", "neu")
        val folder = box.vol1.writeTextFile("Fotos/2.jpg", "zwei").parentFile
        val report = box.engine().run(FileOperation.Move(listOf(file.path, folder.path), target.path), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(report)
        assertEquals("neu", File(target, "a.txt").readText())
        assertEquals(mapOf("1.jpg" to "eins", "2.jpg" to "zwei"), File(target, "Fotos").snapshot())
        assertFalse(file.exists())
        assertFalse("Quellordner nach dem Zusammenführen leer → entfernt", folder.exists())
        box.assertNoLeftovers()
    }

    @Test
    fun sameVolumeMergeKeepsSkippedItemsInTheSource() = blocking {
        val target = box.vol1.dir("Ziel")
        target.writeTextFile("Ordner/gleich.txt", "ziel")
        val src = box.vol1.dir("Quelle/Ordner")
        src.writeTextFile("gleich.txt", "quelle")
        src.writeTextFile("neu.txt", "neu")
        val resolver = ConflictResolver { c ->
            Resolution(if (c.source.isDirectory) ConflictChoice.MERGE else ConflictChoice.SKIP)
        }
        val report = box.engine().run(FileOperation.Move(listOf(src.path), target.path), resolver)
        assertComplete(report)
        assertEquals("quelle", File(src, "gleich.txt").readText())
        assertFalse(File(src, "neu.txt").exists())
        assertEquals("neu", File(target, "Ordner/neu.txt").readText())
        assertEquals("ziel", File(target, "Ordner/gleich.txt").readText())
        assertEquals("nur der verschobene Eintrag gilt als entfernt", listOf(File(src, "neu.txt").path), report.removedPaths)
    }

    @Test
    fun keepBothOnMove() = blocking {
        val target = box.vol1.dir("Ziel")
        target.writeTextFile("x.txt", "1")
        val src = box.vol1.writeTextFile("x.txt", "2")
        val report = box.engine().run(FileOperation.Move(listOf(src.path), target.path), FixedResolver(ConflictChoice.KEEP_BOTH))
        assertComplete(report)
        assertEquals("1", File(target, "x.txt").readText())
        assertEquals("2", File(target, "x 2.txt").readText())
        assertFalse(src.exists())
    }

    @Test
    fun folderIntoItselfAndVolumeRootAreRefused() = blocking {
        val parent = box.vol1.dir("Eltern")
        val child = parent.dir("Kind")
        val report = box.engine().run(FileOperation.Move(listOf(parent.path), child.path), NoConflictExpected)
        assertEquals(FailureReason.TARGET_INSIDE_SOURCE, report.failures.single().reason)
        assertTrue(parent.exists())
        val root = box.engine().run(FileOperation.Move(listOf(box.vol2.path), box.vol1.path), NoConflictExpected)
        assertEquals(FailureReason.ACCESS_DENIED, root.failures.single().reason)
    }

    @Test
    fun crossVolumeSpaceIsCheckedFirst() = blocking {
        val src = box.vol1.writeBytesFile("film.mkv", ByteArray(5_000))
        val target = box.vol2.dir("Ziel")
        val engine = box.engine()
        engine.hooks.usableSpace = { 1_000L }
        val report = engine.run(FileOperation.Move(listOf(src.path), target.path), NoConflictExpected)
        assertEquals(FailureReason.NO_SPACE, report.failures.single().reason)
        assertTrue(src.exists())
        assertEquals(0, target.list()!!.size)
    }

    @Test
    fun unexpectedCrossDeviceFallsBackToVerifiedCopy() = blocking {
        // Speicher laut System gleich, Umbenennen scheitert trotzdem mit EXDEV (z. B. eingebundene Ordner).
        val src = box.vol1.writeTextFile("Quelle/a.txt", "inhalt").parentFile
        val target = box.vol1.dir("Ziel")
        val engine = box.engine()
        var attempts = 0
        engine.hooks.beforeMoveRename = { from, to ->
            attempts++
            throw AtomicMoveNotSupportedException(from.path, to.path, "Invalid cross-device link")
        }
        val report = engine.run(FileOperation.Move(listOf(src.path), target.path), NoConflictExpected)
        assertComplete(report)
        assertEquals("nur einmal versucht, danach direkt geprüft kopiert", 1, attempts)
        assertEquals("inhalt", File(target, "Quelle/a.txt").readText())
        assertFalse(src.exists())
        assertEquals(6L, report.bytesProcessed)
        box.assertNoLeftovers()
    }
}
