package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException

class TrashTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    private fun trashDir(volume: File) = File(box.trash.trashDirFor(volume.path))

    @Test
    fun trashMovesIntoTheTrashOfTheSameVolume() = blocking {
        val file = box.vol2.writeTextFile("DCIM/foto.jpg", "pixel")
        val folder = box.vol2.writeTextFile("Alben/Urlaub/a.jpg", "12345").parentFile
        val report = box.engine().run(FileOperation.Trash(listOf(file.path, folder.path)), NoConflictExpected)
        assertComplete(report)
        assertEquals(2, report.succeeded)
        assertEquals(listOf(file.path, folder.path), report.removedPaths)
        assertFalse(file.exists())
        assertFalse(folder.exists())
        assertTrue("Medien-Apps blenden den Papierkorb aus", File(trashDir(box.vol2), ".nomedia").exists())
        assertFalse("nichts auf dem anderen Speicher", trashDir(box.vol1).exists())

        val items = box.trash.list(listOf(box.vol1.path, box.vol2.path))
        assertEquals(listOf("Urlaub", "foto.jpg"), items.map { it.name }) // neueste zuerst
        val photo = items.single { it.name == "foto.jpg" }
        assertEquals(file.path, photo.originalPath)
        assertEquals(5L, photo.sizeBytes)
        assertFalse(photo.isDirectory)
        assertEquals(box.vol2.path, photo.volumeRoot)
        assertEquals("pixel", File(photo.storedPath).readText())
        val album = items.single { it.name == "Urlaub" }
        assertTrue(album.isDirectory)
        assertEquals(5L, album.sizeBytes)
        box.assertNoLeftovers()
    }

    @Test
    fun trashReportsTheNewEntriesForUndo() = blocking {
        val a = box.vol1.writeTextFile("a.jpg", "a")
        val b = box.vol2.writeTextFile("Ordner/b.txt", "b").parentFile
        val report = box.engine().run(FileOperation.Trash(listOf(a.path, b.path)), NoConflictExpected)
        assertComplete(report)
        val listed = box.trash.list(listOf(box.vol1.path, box.vol2.path))
        assertEquals(listed.map { it.storedPath }.toSet(), report.createdPaths.toSet())
        assertEquals(listed.toSet(), report.trashedItems.toSet())
        // „Widerrufen“ der App: Einträge über ihre neuen Pfade finden und wiederherstellen.
        val undo = listed.filter { it.storedPath in report.createdPaths }
        assertEquals(2, undo.size)
        assertComplete(box.engine().run(FileOperation.Restore(report.trashedItems), NoConflictExpected))
        assertEquals("a", a.readText())
        assertEquals("b", File(b, "b.txt").readText())
    }

    @Test
    fun trashNeverCopiesWhenRenamingIsImpossible() = blocking {
        val file = box.vol2.writeTextFile("doc.pdf", "inhalt")
        box.trash.atomicMove = { from, to -> throw AtomicMoveNotSupportedException(from.path, to.path, "EXDEV") }
        val report = box.engine().run(FileOperation.Trash(listOf(file.path)), NoConflictExpected)
        assertEquals(FailureReason.TRASH_UNAVAILABLE, report.failures.single().reason)
        assertEquals(0, report.succeeded)
        assertEquals("inhalt", file.readText())
        assertEquals("kein halber Eintrag", emptyList<TrashedItem>(), box.trash.list(listOf(box.vol2.path)))
        assertEquals("nur .nomedia", listOf(".nomedia"), trashDir(box.vol2).list()!!.toList())
    }

    @Test
    fun trashOutsideKnownVolumesOrOfTheRootIsRefused() = blocking {
        val outside = tmp.newFolder("anderswo").writeTextFile("x.txt", "x")
        val report = box.engine().run(
            FileOperation.Trash(listOf(outside.path, box.vol1.path, File(box.vol1, "fehlt").path)),
            NoConflictExpected,
        )
        assertEquals(
            listOf(FailureReason.TRASH_UNAVAILABLE, FailureReason.TRASH_UNAVAILABLE, FailureReason.NOT_FOUND),
            report.failures.map { it.reason },
        )
        assertTrue(outside.exists())
        assertTrue(box.vol1.exists())
    }

    @Test
    fun restoreReturnsToOriginalPlaceAndRecreatesFolders() = blocking {
        val file = box.vol1.writeTextFile("Dokumente/Steuer/2025.pdf", "beleg")
        box.engine().run(FileOperation.Trash(listOf(file.path)), NoConflictExpected)
        File(box.vol1, "Dokumente").deleteRecursively()
        val item = box.trash.list(listOf(box.vol1.path)).single()

        val report = box.engine().run(FileOperation.Restore(listOf(item)), NoConflictExpected)
        assertComplete(report)
        assertEquals(listOf(file.path), report.createdPaths)
        assertEquals("beleg", file.readText())
        assertEquals(emptyList<TrashedItem>(), box.trash.list(listOf(box.vol1.path)))
        assertEquals("Eintragsordner entfernt", listOf(".nomedia"), trashDir(box.vol1).list()!!.toList())
    }

    @Test
    fun restoreKeepsBothWhenTheNameIsTakenAgain() = blocking {
        val file = box.vol1.writeTextFile("Notiz.txt", "alt")
        box.engine().run(FileOperation.Trash(listOf(file.path)), NoConflictExpected)
        box.vol1.writeTextFile("notiz.TXT", "neu")
        val item = box.trash.list(listOf(box.vol1.path)).single()
        val report = box.engine().run(FileOperation.Restore(listOf(item)), NoConflictExpected)
        assertComplete(report)
        assertEquals(listOf(File(box.vol1, "Notiz 2.txt").path), report.createdPaths)
        assertEquals("alt", File(box.vol1, "Notiz 2.txt").readText())
        assertEquals("neu", File(box.vol1, "notiz.TXT").readText())
    }

    @Test
    fun deleteFromTrashRemovesTheWholeEntry() = blocking {
        val folder = box.vol1.writeTextFile("Alt/a/b/c.txt", "ccc").parentFile.parentFile.parentFile
        box.engine().run(FileOperation.Trash(listOf(folder.path)), NoConflictExpected)
        val item = box.trash.list(listOf(box.vol1.path)).single()
        val report = box.engine().run(FileOperation.DeleteFromTrash(listOf(item)), NoConflictExpected)
        assertComplete(report)
        assertEquals(1, report.succeeded)
        assertEquals(3L, report.bytesProcessed)
        assertFalse(File(trashDir(box.vol1), item.id).exists())
        assertEquals(emptyList<TrashedItem>(), box.trash.list(listOf(box.vol1.path)))
    }

    @Test
    fun staleOrForgedItemsAreNotFound() = blocking {
        val file = box.vol1.writeTextFile("x.txt", "x")
        box.engine().run(FileOperation.Trash(listOf(file.path)), NoConflictExpected)
        val item = box.trash.list(listOf(box.vol1.path)).single()
        val forged = item.copy(storedPath = file.path) // zeigt aus dem Papierkorb heraus
        val traversal = item.copy(id = "..")
        val report = box.engine().run(FileOperation.DeleteFromTrash(listOf(forged, traversal)), NoConflictExpected)
        assertEquals(listOf(FailureReason.NOT_FOUND, FailureReason.NOT_FOUND), report.failures.map { it.reason })
        assertEquals("Eintrag unverändert", 1, box.trash.list(listOf(box.vol1.path)).size)
    }

    @Test
    fun listIgnoresBrokenEntriesWithoutDeletingThem() {
        val dir = trashDir(box.vol1).apply { mkdirs() }
        File(dir, "ohne-meta/files").mkdirs()
        File(dir, "ohne-meta/files/a.txt").writeText("a")
        File(dir, "ohne-objekt").mkdirs()
        File(dir, "ohne-objekt/meta.properties").writeText("originalPath=/x/a.txt\nname=a.txt\n")
        File(dir, "kaputt/files").mkdirs()
        File(dir, "kaputt/files/b.txt").writeText("b")
        File(dir, "kaputt/meta.properties").writeBytes(byteArrayOf(92, 117, 90, 90)) // „\uZZ“
        File(dir, "gut/files").mkdirs()
        File(dir, "gut/files/c.txt").writeText("c")
        File(dir, "gut/meta.properties").writeText("originalPath=/v/c.txt\nname=c.txt\ndeletedAt=5\n")

        val items = box.trash.list(listOf(box.vol1.path))
        assertEquals(listOf("c.txt"), items.map { it.name })
        assertEquals("fehlende Größe wird gemessen", 1L, items.single().sizeBytes)
        assertEquals(5L, items.single().deletedAtMillis)
        assertTrue(File(dir, "ohne-meta").exists())
        assertTrue(File(dir, "kaputt").exists())
    }

    @Test
    fun deletePermanentlyRemovesTreesAndReportsBytes() = blocking {
        val folder = box.vol1.writeTextFile("Weg/a.txt", "12").parentFile
        folder.writeTextFile("Sub/b.txt", "345")
        val single = box.vol1.writeTextFile("einzeln.txt", "6789")
        val report = box.engine().run(
            FileOperation.DeletePermanently(listOf(folder.path, single.path, File(box.vol1, "fehlt").path)),
            NoConflictExpected,
        )
        assertEquals(2, report.succeeded)
        assertEquals(listOf(FailureReason.NOT_FOUND), report.failures.map { it.reason })
        assertEquals(9L, report.bytesProcessed)
        assertEquals(listOf(folder.path, single.path), report.removedPaths)
        assertFalse(folder.exists())
        assertFalse(single.exists())
    }

    @Test
    fun deletePermanentlyNeverFollowsLinksAndRefusesVolumeRoots() = blocking {
        val precious = box.vol2.writeTextFile("Wichtig/daten.txt", "bleibt").parentFile
        val folder = box.vol1.dir("MitLink")
        java.nio.file.Files.createSymbolicLink(File(folder, "link").toPath(), precious.toPath())
        val report = box.engine().run(FileOperation.DeletePermanently(listOf(folder.path, box.vol2.path)), NoConflictExpected)
        assertEquals(1, report.succeeded)
        assertEquals(FailureReason.ACCESS_DENIED, report.failures.single().reason)
        assertFalse(folder.exists())
        assertEquals("bleibt", File(precious, "daten.txt").readText())
    }
}
