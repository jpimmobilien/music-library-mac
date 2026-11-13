package de.privateapp.aether.files

import kotlinx.coroutines.flow.last
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files

class FileSearchTest {
    private lateinit var root: File

    @Before
    fun setUp() {
        root = Files.createTempDirectory("aether-search").toFile()
        File(root, "Urlaub/München").mkdirs()
        File(root, "Urlaub/München/Strand.JPG").writeText("x")
        File(root, "Urlaub/notizen.txt").writeText("x")
        File(root, ".versteckt").mkdirs()
        File(root, ".versteckt/strandkorb.png").writeText("x")
        File(root, "${TrashStore.DIR_NAME}/1/files").mkdirs()
        File(root, "${TrashStore.DIR_NAME}/1/files/strand-alt.jpg").writeText("x")
        File(root, "halb-strand.jpg${FileNames.TEMP_SUFFIX}").writeText("x")
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    private fun names(query: String, hidden: Boolean) = runBlocking {
        FileSearch.search(listOf(root.path), query, includeHidden = hidden).last().matches.map { it.name }.sorted()
    }

    @Test
    fun findsCaseInsensitivelyAndSkipsTrashAndTempFiles() {
        assertEquals(listOf("Strand.JPG"), names("strand", hidden = false))
        assertEquals(listOf("Strand.JPG", "strandkorb.png"), names("STRAND", hidden = true))
    }

    @Test
    fun matchesUmlautsInBothUnicodeForms() {
        // „München“ zerlegt (u + Trema) wie von macOS geschrieben
        val decomposed = "münchen"
        assertEquals(listOf("München"), names(decomposed, hidden = false))
        assertEquals(listOf("München"), names("MÜNCHEN", hidden = false))
    }

    @Test
    fun emptyQueryFindsNothingAndFinishes() = runBlocking {
        val all = FileSearch.search(listOf(root.path), "  ", includeHidden = true).toList()
        assertEquals(1, all.size)
        assertTrue(all.single().done)
        assertTrue(all.single().matches.isEmpty())
    }

    @Test
    fun stopsAtTheLimit() = runBlocking {
        repeat(5) { File(root, "treffer-$it.txt").writeText("x") }
        val last = FileSearch.search(listOf(root.path), "treffer", includeHidden = false, limit = 3).last()
        assertEquals(3, last.matches.size)
        assertTrue(last.limitReached)
    }

    @Test
    fun skipsProtectedAndroidDataFolders() {
        assertTrue(DirectoryReader.isSystemProtected("/storage/emulated/0/Android/data/com.x"))
    }
}
