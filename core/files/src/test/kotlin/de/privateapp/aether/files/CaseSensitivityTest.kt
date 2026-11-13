package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.FileAlreadyExistsException

/*
 * Speicher, die Groß-/Kleinschreibung unterscheiden (manche USB-Sticks, ext4 ohne Casefolding): Dort können „A.txt“
 * und „a.txt“ nebeneinander liegen. Das Linux-Dateisystem der Tests unterscheidet sie – genau dieser Fall.
 * Regel: Ersetzen trifft nur den gemeinten Eintrag, eine Korrektur der Schreibweise überschreibt nie etwas.
 */
class CaseSensitivityTest {

    @get:Rule
    val tmp = TemporaryFolder()
    private lateinit var box: Sandbox

    @Before
    fun setUp() {
        box = Sandbox(tmp.root)
    }

    private fun bothSpellings(dir: File): File {
        dir.mkdirs()
        File(dir, "A.txt").writeText("A-alt")
        File(dir, "a.txt").writeText("a-alt")
        return dir
    }

    private fun contents(dir: File): Map<String, String> = dir.snapshot()

    @Test
    fun copyReplaceHitsOnlyTheExactName() = blocking {
        val dest = bothSpellings(File(box.vol2, "Ziel"))
        val src = box.vol1.writeTextFile("a.txt", "neu")
        val resolver = FixedResolver(ConflictChoice.REPLACE)
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), dest.path), resolver)
        assertComplete(report)
        assertEquals("gefragt wird nach dem exakt gleichen Namen", listOf("a.txt"), resolver.conflicts.map { it.existing.name })
        assertEquals(mapOf("A.txt" to "A-alt", "a.txt" to "neu"), contents(dest))
        box.assertNoLeftovers()
    }

    @Test
    fun copyReplaceOfAnotherSpellingNeverDestroysTheThirdFile() = blocking {
        val dest = File(box.vol2, "Ziel").apply { mkdirs() }
        File(dest, "A.txt").writeText("A-alt")
        File(dest, "a.TXT").writeText("aTXT-alt")
        val src = box.vol1.writeTextFile("a.txt", "neu")
        val report = box.engine().run(FileOperation.Copy(listOf(src.path), dest.path), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(report)
        val after = contents(dest)
        assertEquals("genau eine Datei ersetzt, keine verloren", 2, after.size)
        assertEquals("neu", after["a.txt"])
        assertTrue("die andere Schreibweise bleibt unangetastet", after.values.any { it == "A-alt" || it == "aTXT-alt" })
    }

    @Test
    fun moveReplaceSameVolumeHitsOnlyTheExactName() = blocking {
        val dest = bothSpellings(File(box.vol1, "Ziel"))
        val src = box.vol1.writeTextFile("Quelle/a.txt", "neu")
        val report = box.engine().run(FileOperation.Move(listOf(src.path), dest.path), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(report)
        assertEquals(mapOf("A.txt" to "A-alt", "a.txt" to "neu"), contents(dest))
        assertTrue(!src.exists())
    }

    @Test
    fun moveReplaceAcrossVolumesHitsOnlyTheExactName() = blocking {
        val dest = bothSpellings(File(box.vol2, "Ziel"))
        val src = box.vol1.writeTextFile("a.txt", "neu")
        val report = box.engine().run(FileOperation.Move(listOf(src.path), dest.path), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(report)
        assertEquals(mapOf("A.txt" to "A-alt", "a.txt" to "neu"), contents(dest))
        assertTrue(!src.exists())
        box.assertNoLeftovers()
    }

    @Test
    fun renameReplaceHitsOnlyTheExactName() = blocking {
        val dir = bothSpellings(File(box.vol1, "Ordner"))
        val x = File(dir, "x.txt").apply { writeText("X") }
        val report = box.engine().run(FileOperation.Rename(x.path, "a.txt"), FixedResolver(ConflictChoice.REPLACE))
        assertComplete(report)
        assertEquals(mapOf("A.txt" to "A-alt", "a.txt" to "X"), contents(dir))
    }

    @Test
    fun caseOnlyRenameOntoAnotherExistingSpellingAsks() = blocking {
        val dir = bothSpellings(File(box.vol1, "Ordner"))
        val resolver = FixedResolver(ConflictChoice.SKIP)
        val report = box.engine().run(FileOperation.Rename(File(dir, "A.txt").path, "a.txt"), resolver)
        assertEquals(1, report.skipped)
        assertEquals(1, resolver.calls.get())
        assertEquals(mapOf("A.txt" to "A-alt", "a.txt" to "a-alt"), contents(dir))
    }

    @Test
    fun renameCaseOnlyNeverOverwritesAnotherFile() {
        val dir = tmp.newFolder("cs")
        File(dir, "Foto.jpg").writeText("eigene Datei")
        val lower = File(dir, "foto.jpg").apply { writeText("klein") }
        try {
            Fs.renameCaseOnly(lower, "Foto.jpg")
            throw AssertionError("FileAlreadyExistsException erwartet")
        } catch (e: FileAlreadyExistsException) {
            // erwartet
        }
        assertEquals(mapOf("Foto.jpg" to "eigene Datei", "foto.jpg" to "klein"), contents(dir))
        assertEquals("kein Zwischenname übrig", 2, dir.list()!!.size)
    }

    @Test
    fun fixCaseBestEffortLeavesTheNameWhenTheSpellingIsTaken() {
        val dir = tmp.newFolder("cs2")
        val replaced = File(dir, "A.txt").apply { writeText("neu") }
        File(dir, "a.txt").writeText("fremd")
        assertEquals(replaced, Fs.fixCaseBestEffort(replaced, "a.txt"))
        assertEquals(mapOf("A.txt" to "neu", "a.txt" to "fremd"), contents(dir))
        // ohne Konkurrenz wird die Schreibweise übernommen
        File(dir, "a.txt").delete()
        assertEquals("a.txt", Fs.fixCaseBestEffort(replaced, "a.txt").name)
        assertEquals(mapOf("a.txt" to "neu"), contents(dir))
    }

    @Test
    fun nameIndexPrefersTheExactSpelling() {
        val dir = bothSpellings(tmp.newFolder("idx"))
        val index = NameIndex()
        assertEquals("a.txt", index.lookup(dir, "a.txt"))
        assertEquals("A.txt", index.lookup(dir, "A.txt"))
        assertTrue(index.lookup(dir, "A.TXT") in setOf("A.txt", "a.txt"))
        index.remove(dir, "a.txt")
        assertEquals("A.txt", index.lookup(dir, "a.txt"))
        index.remove(dir, "A.txt")
        assertEquals(null, index.lookup(dir, "a.txt"))
    }
}
