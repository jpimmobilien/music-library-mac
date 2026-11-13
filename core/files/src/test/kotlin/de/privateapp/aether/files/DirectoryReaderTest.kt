package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files

class DirectoryReaderTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun fixture(): File {
        val dir = tmp.newFolder("Liste")
        dir.writeTextFile("b.txt", "bb")
        dir.writeTextFile("A.jpg", "a")
        dir.dir("Ordner")
        dir.writeTextFile(".versteckt", "x")
        dir.dir(".Thumbnails")
        dir.writeTextFile("halb.jpg.aether-part", "intern")
        dir.dir(TrashStore.DIR_NAME)
        return dir
    }

    @Test
    fun listsVisibleEntriesFoldersFirstAndCountsHidden() {
        val dir = fixture()
        val listing = DirectoryReader.list(dir.path, includeHidden = false) as Listing.Entries
        assertEquals(listOf("Ordner", "A.jpg", "b.txt"), listing.entries.map { it.name })
        assertEquals("versteckte Einträge (ohne AETHER-eigene)", 2, listing.hiddenCount)
        assertEquals(dir.path, listing.directory.path)
        assertTrue(listing.directory.isDirectory)
    }

    @Test
    fun includeHiddenShowsDotFilesButNeverInternals() {
        val dir = fixture()
        val listing = DirectoryReader.list(dir.path + "/", includeHidden = true) as Listing.Entries
        assertEquals(listOf(".Thumbnails", "Ordner", ".versteckt", "A.jpg", "b.txt"), listing.entries.map { it.name })
        assertEquals(0, listing.hiddenCount)
        assertTrue(listing.entries.none { DirectoryReader.isInternal(it.name) })
    }

    @Test
    fun entryFieldsComeFromTheFileSystem() {
        val dir = fixture()
        val file = File(dir, "b.txt")
        file.setLastModified(1_600_000_000_000L)
        val entry = DirectoryReader.entryFor(file.path)!!
        assertEquals("b.txt", entry.name)
        assertEquals(2L, entry.sizeBytes)
        assertEquals(1_600_000_000_000L, entry.modifiedMillis)
        assertEquals(FileKind.TEXT, entry.kind)
        assertEquals("txt", entry.extension)
        assertEquals("text/plain", entry.mimeType)
        assertFalse(entry.isHidden)
        assertTrue(entry.readable)
        assertEquals(dir.path, entry.parentPath)
        val folder = DirectoryReader.entryFor(File(dir, "Ordner").path)!!
        assertEquals(FileKind.FOLDER, folder.kind)
        assertEquals(0L, folder.sizeBytes)
        assertNull(folder.mimeType)
        assertNull(DirectoryReader.entryFor(File(dir, "fehlt").path))
    }

    @Test
    fun symlinkToFolderIsShownAsFolder() {
        val dir = fixture()
        val link = File(dir, "Verknuepfung")
        Files.createSymbolicLink(link.toPath(), File(dir, "Ordner").toPath())
        val entry = DirectoryReader.entryFor(link.path)!!
        assertTrue(entry.isDirectory)
    }

    @Test
    fun notFoundAndNotADirectory() {
        val dir = fixture()
        assertEquals(Listing.NotFound, DirectoryReader.list(File(dir, "fehlt").path, includeHidden = false))
        assertEquals(Listing.NotADirectory, DirectoryReader.list(File(dir, "b.txt").path, includeHidden = false))
    }

    @Test
    fun androidDataAndObbAreReportedAsSystemProtected() {
        for (path in listOf(
            "/storage/emulated/0/Android/data",
            "/storage/emulated/0/Android/obb/",
            "/storage/emulated/10/android/DATA/com.example",
            "/storage/1234-ABCD/Android/data",
            "/sdcard/Android/data",
            "/storage/self/primary/Android/obb",
        )) {
            assertEquals(path, Listing.AccessDenied(protectedBySystem = true), DirectoryReader.list(path, includeHidden = false))
            assertNull(DirectoryReader.childCount(path, includeHidden = true))
        }
        assertFalse(DirectoryReader.isSystemProtected("/storage/emulated/0/Android/media"))
        assertFalse(DirectoryReader.isSystemProtected("/storage/emulated/0/Download/Android/data"))
        assertFalse(DirectoryReader.isSystemProtected("/storage/emulated/0/Android"))
    }

    @Test
    fun childCountMatchesListing() {
        val dir = fixture()
        assertEquals(3, DirectoryReader.childCount(dir.path, includeHidden = false))
        assertEquals(5, DirectoryReader.childCount(dir.path, includeHidden = true))
        assertNull(DirectoryReader.childCount(File(dir, "fehlt").path, includeHidden = true))
        assertNotNull(DirectoryReader.childCount(File(dir, "Ordner").path, includeHidden = true))
    }
}
