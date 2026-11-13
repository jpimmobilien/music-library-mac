package de.privateapp.aether.files

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.nio.charset.Charset

class WriteTextTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    private fun modified(file: File) = DirectoryReader.entryFor(file.path)!!.modifiedMillis

    @Test
    fun createsANewFileAsUtf8() = blocking {
        val file = File(box.vol1, "neu.txt")
        val report = box.engine().run(FileOperation.WriteText(file.path, "Grüße 😀", expectedModifiedMillis = null), NoConflictExpected)
        assertComplete(report)
        assertArrayEquals("Grüße 😀".toByteArray(), file.readBytes())
        assertEquals(listOf(file.path), report.createdPaths)
        box.assertNoLeftovers()
    }

    @Test
    fun overwritesWhenUnchangedSinceOpening() = blocking {
        val file = box.vol1.writeTextFile("notiz.txt", "alt")
        file.setLastModified(1_600_000_000_000L)
        val report = box.engine().run(FileOperation.WriteText(file.path, "neu", modified(file)), NoConflictExpected)
        assertComplete(report)
        assertEquals("neu", file.readText())
        assertEquals(3L, report.bytesProcessed)
        box.assertNoLeftovers()
    }

    @Test
    fun changedMeanwhileIsNeverOverwritten() = blocking {
        val file = box.vol1.writeTextFile("notiz.txt", "Fassung A")
        file.setLastModified(1_600_000_000_000L)
        val openedAt = modified(file)
        file.writeText("Fassung B von anderer App")
        file.setLastModified(1_600_000_005_000L)
        val report = box.engine().run(FileOperation.WriteText(file.path, "Fassung C", openedAt), NoConflictExpected)
        assertEquals(FailureReason.CHANGED_MEANWHILE, report.failures.single().reason)
        assertEquals("Fassung B von anderer App", file.readText())

        val exists = box.engine().run(FileOperation.WriteText(file.path, "x", expectedModifiedMillis = null), NoConflictExpected)
        assertEquals("„neu“, aber schon vorhanden", FailureReason.CHANGED_MEANWHILE, exists.failures.single().reason)

        file.delete()
        val deleted = box.engine().run(FileOperation.WriteText(file.path, "x", openedAt), NoConflictExpected)
        assertEquals(FailureReason.CHANGED_MEANWHILE, deleted.failures.single().reason)
        assertFalse(file.exists())
        box.assertNoLeftovers()
    }

    @Test
    fun changeDuringSavingIsDetectedBeforeReplacing() = blocking {
        val file = box.vol1.writeTextFile("notiz.txt", "A")
        file.setLastModified(1_600_000_000_000L)
        val engine = box.engine()
        engine.hooks.afterTempWritten = { file.setLastModified(1_600_000_009_000L) }
        val report = engine.run(FileOperation.WriteText(file.path, "B", modified(file)), NoConflictExpected)
        assertEquals(FailureReason.CHANGED_MEANWHILE, report.failures.single().reason)
        assertEquals("A", file.readText())
        box.assertNoLeftovers()
    }

    @Test
    fun writeFailureKeepsTheOriginal() = blocking {
        val file = box.vol1.writeTextFile("gross.txt", "Original")
        val engine = box.engine()
        engine.hooks.onChunkWritten = { _, _ -> throw IOException("write failed: EIO (I/O error)") }
        val report = engine.run(FileOperation.WriteText(file.path, "x".repeat(50_000), modified(file)), NoConflictExpected)
        assertEquals(FailureReason.IO_ERROR, report.failures.single().reason)
        assertEquals("Original", file.readText())
        box.assertNoLeftovers()
    }

    @Test
    fun encodingAndBomArePreserved() = blocking {
        val cp1252 = Charset.forName("windows-1252")
        val legacy = box.vol1.writeBytesFile("alt.txt", "Grüße".toByteArray(cp1252))
        assertComplete(box.engine().run(FileOperation.WriteText(legacy.path, "Grüße, Welt", modified(legacy)), NoConflictExpected))
        assertArrayEquals("Grüße, Welt".toByteArray(cp1252), legacy.readBytes())

        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        val withBom = box.vol1.writeBytesFile("bom.txt", bom + "ä".toByteArray())
        assertComplete(box.engine().run(FileOperation.WriteText(withBom.path, "ö", modified(withBom)), NoConflictExpected))
        assertArrayEquals(bom + "ö".toByteArray(), withBom.readBytes())

        val le = byteArrayOf(0xFF.toByte(), 0xFE.toByte())
        val utf16 = box.vol1.writeBytesFile("utf16.txt", le + "a".toByteArray(Charsets.UTF_16LE))
        assertComplete(box.engine().run(FileOperation.WriteText(utf16.path, "Straße", modified(utf16)), NoConflictExpected))
        assertArrayEquals(le + "Straße".toByteArray(Charsets.UTF_16LE), utf16.readBytes())
    }

    @Test
    fun charactersOutsideTheOldEncodingSwitchToUtf8() = blocking {
        val legacy = box.vol1.writeBytesFile("alt.txt", "Grüße".toByteArray(Charset.forName("windows-1252")))
        assertComplete(box.engine().run(FileOperation.WriteText(legacy.path, "Grüße 😀", modified(legacy)), NoConflictExpected))
        assertArrayEquals("Grüße 😀".toByteArray(Charsets.UTF_8), legacy.readBytes())
    }

    @Test
    fun invalidNewNameOrMissingFolder() = blocking {
        val invalid = box.engine().run(FileOperation.WriteText(File(box.vol1, "a?.txt").path, "x", null), NoConflictExpected)
        assertEquals(FailureReason.INVALID_NAME, invalid.failures.single().reason)
        val noFolder = box.engine().run(FileOperation.WriteText(File(box.vol1, "fehlt/a.txt").path, "x", null), NoConflictExpected)
        assertEquals(FailureReason.NOT_FOUND, noFolder.failures.single().reason)
    }
}
