package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class TempJournalTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val journalFile get() = File(tmp.root, "app/journal")

    @Test
    fun recoversOnlyListedPartFiles() {
        val dir = tmp.newFolder("Ziel")
        val listedPart = dir.writeTextFile("a.jpg.aether-part", "halb")
        val listedButNotPart = dir.writeTextFile("wichtig.txt", "Nutzerdaten")
        val unlistedPart = dir.writeTextFile("fremd.aether-part", "nicht unseres")
        val removedPart = dir.writeTextFile("fertig.aether-part", "schon ausgetragen")
        val partDir = dir.dir("Entpackt.aether-part")
        partDir.writeTextFile("tief/x.txt", "x")

        val journal = TempJournal(journalFile)
        journal.add(listedPart.path)
        journal.add(listedButNotPart.path)
        journal.add(removedPart.path)
        journal.remove(removedPart.path)
        journal.add(partDir.path)
        journal.add(File(dir, "gibt-es-nicht.aether-part").path)

        // Neuer Prozess: liest das Journal von der Platte.
        val recovered = TempJournal(journalFile).recoverLeftovers()
        assertEquals(listOf(listedPart.path, partDir.path), recovered)
        assertFalse(listedPart.exists())
        assertFalse(partDir.exists())
        assertTrue("nur „.aether-part“ wird je gelöscht", listedButNotPart.exists())
        assertTrue("nicht eingetragen → bleibt", unlistedPart.exists())
        assertTrue("ausgetragen → bleibt", removedPart.exists())
        assertEquals("Journal ist leer", emptyList<String>(), TempJournal(journalFile).recoverLeftovers())
    }

    @Test
    fun committedReplacementIsCompletedNotDeleted() {
        val dir = tmp.newFolder("Text")
        val target = File(dir, "notiz.txt")
        val temp = dir.writeTextFile("notiz.txt.aether-part", "neue Fassung")
        TempJournal(journalFile).apply {
            add(temp.path)
            commit(temp.path, target.path)
        }
        // Absturz nach dem Löschen des Originals: Ziel fehlt → Zwischendatei wird an seinen Platz gesetzt.
        assertEquals(listOf(temp.path), TempJournal(journalFile).recoverLeftovers())
        assertEquals("neue Fassung", target.readText())
        assertFalse(temp.exists())
    }

    @Test
    fun committedButOriginalStillThereDeletesTemp() {
        val dir = tmp.newFolder("Text2")
        val target = dir.writeTextFile("notiz.txt", "Original")
        val temp = dir.writeTextFile("notiz.txt.aether-part", "neu")
        TempJournal(journalFile).commit(temp.path, target.path)
        TempJournal(journalFile).recoverLeftovers()
        assertEquals("Original", target.readText())
        assertFalse(temp.exists())
    }

    @Test
    fun pathsWithSpecialCharactersSurvive() {
        val dir = tmp.newFolder("Sonder")
        val odd = dir.writeTextFile("Zeile\nUmbruch\tund\\Strich.aether-part", "x")
        TempJournal(journalFile).add(odd.path)
        assertEquals(listOf(odd.path), TempJournal(journalFile).recoverLeftovers())
        assertFalse(odd.exists())
    }

    @Test
    fun corruptJournalIsTolerated() {
        journalFile.parentFile.mkdirs()
        journalFile.writeBytes(byteArrayOf(0, -1, 10, 43, 92, 10, 61, 120, 10, 43) + "/kein/pfad\\q\n".toByteArray())
        assertEquals(emptyList<String>(), TempJournal(journalFile).recoverLeftovers())
        val journal = TempJournal(journalFile)
        val part = tmp.root.writeTextFile("neu.aether-part", "x")
        journal.add(part.path)
        assertEquals(listOf(part.path), TempJournal(journalFile).recoverLeftovers())
    }

    @Test
    fun manyEntriesAreCompacted() {
        val journal = TempJournal(journalFile)
        repeat(2000) {
            journal.add("/x/$it.aether-part")
            journal.remove("/x/$it.aether-part")
        }
        journal.add("/x/bleibt.aether-part")
        assertTrue("Journal bleibt klein", journalFile.length() < 64 * 1024)
    }
}
