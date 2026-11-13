package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class RenameCreateTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    @Test
    fun renameFileAndFolder() = blocking {
        val file = box.vol1.writeTextFile("alt.txt", "inhalt")
        val report = box.engine().run(FileOperation.Rename(file.path, "neu.txt"), NoConflictExpected)
        assertComplete(report)
        assertEquals("inhalt", File(box.vol1, "neu.txt").readText())
        assertFalse(file.exists())
        assertEquals(listOf(File(box.vol1, "neu.txt").path), report.createdPaths)
        assertEquals(listOf(file.path), report.removedPaths)

        val folder = box.vol1.writeTextFile("Ordner/x.txt", "x").parentFile
        assertComplete(box.engine().run(FileOperation.Rename(folder.path, "Umbenannt"), NoConflictExpected))
        assertEquals("x", File(box.vol1, "Umbenannt/x.txt").readText())
    }

    @Test
    fun invalidNamesAreRejectedWithTheReason() = blocking {
        val file = box.vol1.writeTextFile("a.txt", "a")
        for ((name, problem) in listOf(
            "b:c.txt" to NameProblem.FORBIDDEN_CHARACTER,
            "" to NameProblem.EMPTY,
            "x/y" to NameProblem.SLASH,
            "ende." to NameProblem.TRAILING_DOT_OR_SPACE,
            "a.aether-part" to NameProblem.RESERVED,
        )) {
            val report = box.engine().run(FileOperation.Rename(file.path, name), NoConflictExpected)
            val failure = report.failures.single()
            assertEquals(FailureReason.INVALID_NAME, failure.reason)
            assertEquals(problem.message, failure.detail)
        }
        assertTrue(file.exists())
    }

    @Test
    fun caseOnlyRenameWorksAndLeavesNoIntermediate() = blocking {
        val file = box.vol1.writeTextFile("foto.jpg", "pixel")
        val report = box.engine().run(FileOperation.Rename(file.path, "Foto.JPG"), NoConflictExpected)
        assertComplete(report)
        assertEquals(listOf("Foto.JPG"), box.vol1.list()!!.toList())
        assertEquals("pixel", File(box.vol1, "Foto.JPG").readText())
    }

    @Test
    fun sameNameIsANoOp() = blocking {
        val file = box.vol1.writeTextFile("gleich.txt", "x")
        val report = box.engine().run(FileOperation.Rename(file.path, "gleich.txt"), NoConflictExpected)
        assertComplete(report)
        assertEquals(1, report.succeeded)
        assertTrue(file.exists())
    }

    @Test
    fun renameConflicts() = blocking {
        val a = box.vol1.writeTextFile("a.txt", "A")
        box.vol1.writeTextFile("B.txt", "B")
        val skip = box.engine().run(FileOperation.Rename(a.path, "b.txt"), FixedResolver(ConflictChoice.SKIP))
        assertEquals(1, skip.skipped)
        assertTrue(a.exists())

        val keepBoth = box.engine().run(FileOperation.Rename(a.path, "b.txt"), FixedResolver(ConflictChoice.KEEP_BOTH))
        assertComplete(keepBoth)
        assertEquals("A", File(box.vol1, "b 2.txt").readText())
        assertEquals("B", File(box.vol1, "B.txt").readText())

        val c = box.vol1.writeTextFile("c.txt", "C")
        val replace = box.engine().run(FileOperation.Rename(c.path, "b.txt"), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(replace)
        assertEquals(setOf("b.txt", "b 2.txt"), box.vol1.list()!!.toSet())
        assertEquals("C", File(box.vol1, "b.txt").readText())
    }

    @Test
    fun foldersAreNeverReplacedOrMergedByRename() = blocking {
        val a = box.vol1.writeTextFile("A/a.txt", "a").parentFile
        box.vol1.writeTextFile("B/b.txt", "b")
        for (choice in listOf(ConflictChoice.REPLACE, ConflictChoice.MERGE)) {
            val report = box.engine().run(FileOperation.Rename(a.path, "B"), FixedResolver(choice))
            assertEquals(1, report.skipped)
        }
        assertTrue(File(a, "a.txt").exists())
        assertEquals(listOf("b.txt"), File(box.vol1, "B").list()!!.toList())
    }

    @Test
    fun renameMissingOrVolumeRoot() = blocking {
        val missing = box.engine().run(FileOperation.Rename(File(box.vol1, "fehlt").path, "x"), NoConflictExpected)
        assertEquals(FailureReason.NOT_FOUND, missing.failures.single().reason)
        val root = box.engine().run(FileOperation.Rename(box.vol1.path, "x"), NoConflictExpected)
        assertEquals(FailureReason.ACCESS_DENIED, root.failures.single().reason)
    }

    @Test
    fun createFolderPicksAFreeName() = blocking {
        box.vol1.dir("neuer ordner")
        val report = box.engine().run(FileOperation.CreateFolder(box.vol1.path, "Neuer Ordner"), NoConflictExpected)
        assertComplete(report)
        val created = File(box.vol1, "Neuer Ordner 2")
        assertEquals(listOf(created.path), report.createdPaths)
        assertTrue(created.isDirectory)
    }

    @Test
    fun createFolderErrors() = blocking {
        val invalid = box.engine().run(FileOperation.CreateFolder(box.vol1.path, "a?b"), NoConflictExpected)
        assertEquals(FailureReason.INVALID_NAME, invalid.failures.single().reason)
        assertEquals(NameProblem.FORBIDDEN_CHARACTER.message, invalid.failures.single().detail)
        val noParent = box.engine().run(FileOperation.CreateFolder(File(box.vol1, "fehlt").path, "x"), NoConflictExpected)
        assertEquals(FailureReason.NOT_FOUND, noParent.failures.single().reason)
        assertEquals(0, box.vol1.list()!!.size)
    }
}
