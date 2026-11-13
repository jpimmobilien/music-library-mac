package de.privateapp.aether.files

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.charset.Charset
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

class ArchiveTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    private fun zip(file: File, charset: Charset = Charsets.UTF_8, vararg entries: Pair<String, String?>): File {
        ZipOutputStream(file.outputStream(), charset).use { out ->
            for ((name, content) in entries) {
                out.putNextEntry(ZipEntry(name))
                if (content != null) out.write(content.toByteArray())
                out.closeEntry()
            }
        }
        return file
    }

    private fun entryNames(file: File) = ZipFile(file).use { z -> z.entries().toList().map { it.name } }

    @Test
    fun compressCreatesAValidZipWithFoldersAndTimes() = blocking {
        val photos = box.vol1.dir("Fotos")
        photos.writeBytesFile("a.jpg", pseudoRandomBytes(5_000))
        photos.writeTextFile("Unter/notiz.txt", "Grüße")
        val note = box.vol1.writeTextFile("liste.txt", "eins\nzwei")
        note.setLastModified(1_600_000_002_000L)
        val report = box.engine().run(
            FileOperation.Compress(listOf(photos.path, note.path), box.vol1.path, "Paket"),
            NoConflictExpected,
        )
        assertComplete(report)
        val archive = File(box.vol1, "Paket.zip")
        assertEquals(listOf(archive.path), report.createdPaths)
        assertEquals(2, report.succeeded)
        assertEquals(listOf("Fotos/", "Fotos/Unter/", "Fotos/Unter/notiz.txt", "Fotos/a.jpg", "liste.txt"), entryNames(archive))
        ZipFile(archive).use { z ->
            assertEquals(1_600_000_002_000L, z.getEntry("liste.txt").time)
            assertEquals("Grüße", z.getInputStream(z.getEntry("Fotos/Unter/notiz.txt")).readBytes().toString(Charsets.UTF_8))
        }
        box.assertNoLeftovers()
    }

    @Test
    fun compressNeverOverwritesAndValidatesTheName() = blocking {
        val src = box.vol1.writeTextFile("a.txt", "a")
        box.vol1.writeTextFile("Archiv.zip", "vorhanden")
        val report = box.engine().run(FileOperation.Compress(listOf(src.path), box.vol1.path, "Archiv.zip"), NoConflictExpected)
        assertComplete(report)
        assertEquals(listOf(File(box.vol1, "Archiv 2.zip").path), report.createdPaths)
        assertEquals("vorhanden", File(box.vol1, "Archiv.zip").readText())
        val invalid = box.engine().run(FileOperation.Compress(listOf(src.path), box.vol1.path, "a:b"), NoConflictExpected)
        assertEquals(FailureReason.INVALID_NAME, invalid.failures.single().reason)
        val empty = box.engine().run(FileOperation.Compress(listOf(src.path), box.vol1.path, "  "), NoConflictExpected)
        assertEquals(FailureReason.INVALID_NAME, empty.failures.single().reason)
    }

    @Test
    fun roundTripWithSingleTopLevelFolder() = blocking {
        val project = box.vol1.dir("Projekt")
        project.writeTextFile("Übersicht.md", "# Titel")
        project.writeBytesFile("bilder/logo.png", pseudoRandomBytes(20_000))
        project.dir("leer")
        val before = project.snapshot()
        assertComplete(box.engine().run(FileOperation.Compress(listOf(project.path), box.vol1.path, "Projekt"), NoConflictExpected))

        val target = box.vol2.dir("Entpackt")
        target.dir("Projekt") // belegt → „Projekt 2“
        val report = box.engine().run(FileOperation.Extract(File(box.vol1, "Projekt.zip").path, target.path), NoConflictExpected)
        assertComplete(report)
        val extracted = File(target, "Projekt 2")
        assertEquals(listOf(extracted.path), report.createdPaths)
        assertEquals(before, extracted.snapshot())
        assertArrayEquals(File(project, "bilder/logo.png").readBytes(), File(extracted, "bilder/logo.png").readBytes())
        box.assertNoLeftovers()
    }

    @Test
    fun severalTopLevelEntriesGoIntoAFolderNamedAfterTheArchive() = blocking {
        val archive = zip(File(box.vol1, "Sammlung.zip"), Charsets.UTF_8, "a.txt" to "a", "b/c.txt" to "c", "__MACOSX/._a.txt" to "x")
        val report = box.engine().run(FileOperation.Extract(archive.path, box.vol1.path), NoConflictExpected)
        assertComplete(report)
        val folder = File(box.vol1, "Sammlung")
        assertEquals(mapOf("a.txt" to "a", "b/" to "", "b/c.txt" to "c"), folder.snapshot())
        assertFalse(File(folder, "__MACOSX").exists())
    }

    @Test
    fun singleFileGoesIntoAFolderToo() = blocking {
        val archive = zip(File(box.vol1, "Eins.zip"), Charsets.UTF_8, "nur.txt" to "n")
        assertComplete(box.engine().run(FileOperation.Extract(archive.path, box.vol1.path), NoConflictExpected))
        assertEquals("n", File(box.vol1, "Eins/nur.txt").readText())
    }

    @Test
    fun zipSlipEntriesAreNeverWritten() = blocking {
        val target = box.vol2.dir("Ziel")
        val archive = zip(
            File(box.vol1, "boese.zip"), Charsets.UTF_8,
            "../ausserhalb.txt" to "böse",
            "/absolut.txt" to "böse",
            "ok/../../auch.txt" to "böse",
            "C:\\windows.txt" to "böse",
            "ok.txt" to "gut",
        )
        val report = box.engine().run(FileOperation.Extract(archive.path, target.path), NoConflictExpected)
        assertEquals(4, report.failures.size)
        assertTrue(report.failures.all { it.reason == FailureReason.ARCHIVE_UNSAFE_ENTRY })
        assertEquals("gut", File(target, "boese/ok.txt").readText())
        assertFalse(File(box.vol2, "ausserhalb.txt").exists())
        assertFalse(File(box.vol1, "auch.txt").exists())
        assertEquals("teilweise → nicht erledigt", 0, report.succeeded)
        assertEquals(listOf(File(target, "boese").path), report.createdPaths)
        box.assertNoLeftovers()
    }

    @Test
    fun legacyIbm437NamesAreDecoded() = blocking {
        val ibm437 = runCatching { Charset.forName("IBM437") }.getOrNull()
        assumeTrue("IBM437 nicht verfügbar", ibm437 != null)
        // Nicht-ASCII-Dateinamen braucht eine UTF-8-Umgebung (Android immer; JVM: LC_ALL=C.UTF-8).
        assumeTrue("Dateinamen-Kodierung der JVM ist nicht UTF-8", System.getProperty("sun.jnu.encoding").equals("UTF-8", ignoreCase = true))
        val archive = zip(File(box.vol1, "alt.zip"), ibm437!!, "Müller/Bücher.txt" to "x")
        val report = box.engine().run(FileOperation.Extract(archive.path, box.vol1.path), NoConflictExpected)
        assertComplete(report)
        assertEquals("x", File(box.vol1, "Müller/Bücher.txt").readText())
    }

    @Test
    fun notAZipIsUnsupported() = blocking {
        val fake = box.vol1.writeTextFile("kein.zip", "das ist kein Archiv")
        val report = box.engine().run(FileOperation.Extract(fake.path, box.vol1.path), NoConflictExpected)
        assertEquals(FailureReason.ARCHIVE_UNSUPPORTED, report.failures.single().reason)
        assertEquals(listOf("kein.zip"), box.vol1.list()!!.toList())
    }

    @Test
    fun extractChecksSpaceFirst() = blocking {
        val archive = zip(File(box.vol1, "a.zip"), Charsets.UTF_8, "x.bin" to "x".repeat(10_000))
        val engine = box.engine()
        engine.hooks.usableSpace = { 100L }
        val report = engine.run(FileOperation.Extract(archive.path, box.vol2.path), NoConflictExpected)
        assertEquals(FailureReason.NO_SPACE, report.failures.single().reason)
        assertEquals(0, box.vol2.list()!!.size)
        box.assertNoLeftovers()
    }

    @Test
    fun duplicateNamesInsideTheArchiveDoNotOverwriteEachOther() = blocking {
        val archive = zip(File(box.vol1, "doppelt.zip"), Charsets.UTF_8, "d/Datei.txt" to "1", "d/datei.TXT" to "2")
        assertComplete(box.engine().run(FileOperation.Extract(archive.path, box.vol2.path), NoConflictExpected))
        assertEquals(mapOf("Datei.txt" to "1", "datei 2.TXT" to "2"), File(box.vol2, "d").snapshot())
    }
}
