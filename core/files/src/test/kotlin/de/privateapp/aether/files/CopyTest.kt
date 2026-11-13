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
import java.io.IOException
import java.nio.file.Files

class CopyTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    @Test
    fun copiesAFileWithContentAndModificationTime() = blocking {
        val data = pseudoRandomBytes(50_000)
        val src = box.vol1.writeBytesFile("DCIM/IMG_1.jpg", data)
        src.setLastModified(1_650_000_000_000L)
        val target = box.vol2.dir("Backup")
        val progress = ArrayList<OperationProgress>()
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), NoConflictExpected) { progress += it }
        assertComplete(report)
        assertEquals(1, report.succeeded)
        val copy = File(target, "IMG_1.jpg")
        assertArrayEquals(data, copy.readBytes())
        assertEquals(1_650_000_000_000L, copy.lastModified())
        assertTrue("Original bleibt", src.exists())
        assertEquals(listOf(copy.path), report.createdPaths)
        assertEquals(emptyList<String>(), report.removedPaths)
        assertEquals(50_000L, report.bytesProcessed)
        val phases = progress.map { it.phase }.distinct()
        assertEquals(listOf(OperationPhase.PREPARING, OperationPhase.RUNNING, OperationPhase.CLEANING_UP), phases)
        assertEquals(1f, progress.last().fraction!!, 0.0001f)
        box.assertNoLeftovers()
    }

    @Test
    fun copiesFoldersRecursivelyIncludingHiddenFiles() = blocking {
        val src = box.vol1.dir("Projekt")
        src.writeTextFile("a.txt", "a")
        src.writeTextFile("Unter/b.txt", "bb")
        src.writeTextFile("Unter/Tiefer/.hidden", "h")
        src.dir("Leer")
        val target = box.vol2.dir("Ziel")
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), NoConflictExpected)
        assertComplete(report)
        assertEquals(src.snapshot(), File(target, "Projekt").snapshot())
        assertEquals(listOf(File(target, "Projekt").path), report.createdPaths)
        box.assertNoLeftovers()
    }

    @Test
    fun copyIntoTheSameFolderCreatesADuplicateWithoutAsking() = blocking {
        val src = box.vol1.writeTextFile("Foto.jpg", "x")
        val folder = box.vol1.writeTextFile("Album/a.txt", "a").parentFile
        val report = box.engine().run(FileOperation.Copy(listOf(src.path, folder.path), box.vol1.path), NoConflictExpected)
        assertComplete(report)
        assertEquals("x", File(box.vol1, "Foto 2.jpg").readText())
        assertEquals("a", File(box.vol1, "Album 2/a.txt").readText())
        assertEquals(listOf(File(box.vol1, "Foto 2.jpg").path, File(box.vol1, "Album 2").path), report.createdPaths)
    }

    @Test
    fun replaceKeepBothAndSkip() = blocking {
        val target = box.vol2.dir("Ziel")
        target.writeTextFile("a.txt", "alt")
        val src = box.vol1.writeTextFile("a.txt", "neu")

        val replace = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(replace)
        assertEquals("neu", File(target, "a.txt").readText())

        src.writeText("dritte")
        val keepBoth = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), FixedResolver(ConflictChoice.KEEP_BOTH))
        assertEquals("neu", File(target, "a.txt").readText())
        assertEquals("dritte", File(target, "a 2.txt").readText())
        assertEquals(listOf(File(target, "a 2.txt").path), keepBoth.createdPaths)

        val skip = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), FixedResolver(ConflictChoice.SKIP))
        assertEquals(1, skip.skipped)
        assertEquals(0, skip.succeeded)
        assertEquals(emptyList<String>(), skip.createdPaths)
        assertEquals(setOf("a.txt", "a 2.txt"), target.list()!!.toSet())
        box.assertNoLeftovers()
    }

    @Test
    fun conflictsIgnoreCase() = blocking {
        val target = box.vol2.dir("Ziel")
        target.writeTextFile("Foto.JPG", "alt")
        val src = box.vol1.writeTextFile("foto.jpg", "neu")
        val resolver = FixedResolver(ConflictChoice.REPLACE)
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), resolver)
        assertComplete(report)
        assertEquals(1, resolver.calls.get())
        assertEquals("Foto.JPG", resolver.conflicts.single().existing.name)
        assertEquals("ersetzt und Schreibweise der neuen Datei übernommen", listOf("foto.jpg"), target.list()!!.toList())
        assertEquals("neu", File(target, "foto.jpg").readText())
    }

    @Test
    fun mergeFoldersAndAskForEachFileInside() = blocking {
        val target = box.vol2.dir("Ziel")
        target.writeTextFile("Fotos/alt.jpg", "alt")
        target.writeTextFile("Fotos/gleich.jpg", "vorher")
        val src = box.vol1.dir("Fotos")
        src.writeTextFile("neu.jpg", "neu")
        src.writeTextFile("gleich.jpg", "nachher")
        val resolver = ConflictResolver { conflict ->
            if (conflict.source.isDirectory) Resolution(ConflictChoice.MERGE) else Resolution(ConflictChoice.KEEP_BOTH)
        }
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), resolver)
        assertComplete(report)
        assertEquals(
            mapOf("alt.jpg" to "alt", "gleich.jpg" to "vorher", "gleich 2.jpg" to "nachher", "neu.jpg" to "neu"),
            File(target, "Fotos").snapshot(),
        )
        assertEquals(listOf(File(target, "Fotos").path), report.createdPaths)
    }

    @Test
    fun replaceOnFoldersMeansMerge() = blocking {
        val target = box.vol2.dir("Ziel")
        target.writeTextFile("Ordner/bleibt.txt", "1")
        val src = box.vol1.writeTextFile("Ordner/dazu.txt", "2").parentFile
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(report)
        assertEquals(setOf("bleibt.txt", "dazu.txt"), File(target, "Ordner").list()!!.toSet())
    }

    @Test
    fun applyToAllIsRememberedSeparatelyForFilesAndFolders() = blocking {
        val target = box.vol2.dir("Ziel")
        for (name in listOf("1.txt", "2.txt", "3.txt")) target.writeTextFile(name, "alt")
        target.dir("A")
        target.dir("B")
        val sources = listOf("1.txt", "2.txt", "3.txt").map { box.vol1.writeTextFile(it, "neu").path } +
            listOf("A", "B").map { box.vol1.dir(it).path }
        val fileCalls = java.util.concurrent.atomic.AtomicInteger()
        val folderCalls = java.util.concurrent.atomic.AtomicInteger()
        val resolver = ConflictResolver { conflict ->
            if (conflict.source.isDirectory) {
                folderCalls.incrementAndGet()
                Resolution(ConflictChoice.SKIP, applyToAll = true)
            } else {
                fileCalls.incrementAndGet()
                Resolution(ConflictChoice.REPLACE, applyToAll = true)
            }
        }
        val report = box.engine().run(FileOperation.Copy(sources, target.path), resolver)
        assertEquals(1, fileCalls.get())
        assertEquals(1, folderCalls.get())
        assertEquals(3, report.succeeded)
        assertEquals(2, report.skipped)
        assertEquals("neu", File(target, "3.txt").readText())
    }

    @Test
    fun replaceNeverDestroysTheOriginalWhenWritingFails() = blocking {
        val target = box.vol2.dir("Ziel")
        target.writeTextFile("gross.bin", "ALT")
        val src = box.vol1.writeBytesFile("gross.bin", pseudoRandomBytes(40_000))
        val engine = box.engine()
        engine.hooks.onChunkWritten = { _, written ->
            if (written > 10_000) throw IOException("write failed: ENOSPC (No space left on device)")
        }
        val report = engine.run(FileOperation.Copy(listOf(src.path), target.path), FixedResolver(ConflictChoice.REPLACE))
        assertEquals(FailureReason.NO_SPACE, report.failures.single().reason)
        assertEquals(0, report.succeeded)
        assertEquals("ALT", File(target, "gross.bin").readText())
        box.assertNoLeftovers()
    }

    @Test
    fun noSpaceStopsTheRemainingItems() = blocking {
        val target = box.vol2.dir("Ziel")
        val sources = (1..3).map { box.vol1.writeBytesFile("$it.bin", ByteArray(5_000)).path }
        val engine = box.engine()
        engine.hooks.onChunkWritten = { file, _ ->
            if (file.name.startsWith("2.bin")) throw IOException("write failed: ENOSPC (No space left on device)")
        }
        val report = engine.run(FileOperation.Copy(sources, target.path), NoConflictExpected)
        assertEquals(1, report.succeeded)
        assertEquals(listOf(sources[1], sources[2]), report.failures.map { it.path })
        assertTrue(report.failures.all { it.reason == FailureReason.NO_SPACE })
        assertEquals(listOf("1.bin"), target.list()!!.toList())
        box.assertNoLeftovers()
    }

    @Test
    fun spaceIsCheckedBeforeAnythingHappens() = blocking {
        val src = box.vol1.writeBytesFile("video.mp4", ByteArray(10_000))
        val target = box.vol2.dir("Ziel")
        val engine = box.engine()
        engine.hooks.usableSpace = { 500_000L } // weniger als Datei + 1 MB Reserve
        val report = engine.run(FileOperation.Copy(listOf(src.path), target.path), NoConflictExpected)
        assertEquals(FailureReason.NO_SPACE, report.failures.single().reason)
        assertEquals(target.path, report.failures.single().path)
        assertEquals(0, report.succeeded)
        assertEquals(0, target.list()!!.size)
    }

    @Test
    fun folderIntoItselfIsRefused() = blocking {
        val src = box.vol1.dir("Eltern")
        val inside = src.dir("Kind")
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), inside.path), NoConflictExpected)
        assertEquals(FailureReason.TARGET_INSIDE_SOURCE, report.failures.single().reason)
        assertEquals(0, inside.list()!!.size)
        val same = box.engine().run(FileOperation.Copy(listOf(src.path), src.path), NoConflictExpected)
        assertEquals(FailureReason.TARGET_INSIDE_SOURCE, same.failures.single().reason)
    }

    @Test
    fun missingSourcesAndTargetsAreReported() = blocking {
        val ok = box.vol1.writeTextFile("ok.txt", "ok")
        val target = box.vol2.dir("Ziel")
        val report = box.engine().run(FileOperation.Copy(listOf(File(box.vol1, "fehlt").path, ok.path), target.path), NoConflictExpected)
        assertEquals(FailureReason.NOT_FOUND, report.failures.single().reason)
        assertEquals(1, report.succeeded)
        assertTrue(File(target, "ok.txt").exists())

        val noTarget = box.engine().run(FileOperation.Copy(listOf(ok.path), File(box.vol2, "nirgends").path), NoConflictExpected)
        assertEquals(FailureReason.NOT_FOUND, noTarget.failures.single().reason)
        val fileTarget = box.engine().run(FileOperation.Copy(listOf(ok.path), ok.path), NoConflictExpected)
        assertEquals(FailureReason.IO_ERROR, fileTarget.failures.single().reason)
    }

    @Test
    fun symlinksAreReportedNotFollowed() = blocking {
        val src = box.vol1.dir("MitLink")
        src.writeTextFile("echt.txt", "echt")
        Files.createSymbolicLink(File(src, "link").toPath(), tmp.newFolder("geheim").toPath())
        val target = box.vol2.dir("Ziel")
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), target.path), NoConflictExpected)
        val failure = report.failures.single()
        assertEquals(FailureReason.SPECIAL_FILE_SKIPPED, failure.reason)
        assertFalse(failure.reason.isProblem)
        assertTrue(failure.detail!!.contains("Verknüpfung"))
        assertEquals(listOf("echt.txt"), File(target, "MitLink").list()!!.toList())
        assertEquals("bewusst übergangen ist kein Fehlschlag", 1, report.succeeded)
        assertEquals(listOf(File(target, "MitLink").path), report.createdPaths)
        val summary = OperationTexts.summary(report)
        assertEquals("1 Objekt kopiert", summary.headline)
        assertEquals("1 Verknüpfung oder Gerätedatei wurde bewusst nicht kopiert.", summary.detail)
        assertFalse(summary.isProblem)
    }

    @Test
    fun internalFilesAreNeverCopied() = blocking {
        val src = box.vol1.dir("Quelle")
        src.writeTextFile("a.txt", "a")
        src.writeTextFile("rest.aether-part", "intern")
        val target = box.vol2.dir("Ziel")
        assertComplete(box.engine().run(FileOperation.Copy(listOf(src.path), target.path), NoConflictExpected))
        assertEquals(listOf("a.txt"), File(target, "Quelle").list()!!.toList())
        assertFalse(File(target, "Quelle/rest.aether-part").exists())
    }
}
