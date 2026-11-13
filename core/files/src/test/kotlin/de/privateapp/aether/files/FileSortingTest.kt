package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Test

class FileSortingTest {

    private fun sortedNames(vararg names: String) = names.sortedWith(FileSorting.naturalNameComparator)

    @Test
    fun numbersCompareAsNumbers() {
        assertEquals(listOf("Datei 1", "Datei 2", "Datei 10", "Datei 100"), sortedNames("Datei 10", "Datei 100", "Datei 2", "Datei 1"))
        assertEquals(listOf("IMG_9.jpg", "IMG_10.jpg"), sortedNames("IMG_10.jpg", "IMG_9.jpg"))
        assertEquals("Ziffern vor Buchstaben", listOf("1 Start", "A Start"), sortedNames("A Start", "1 Start"))
        assertEquals("führende Nullen: Zahlwert gleich, dann stabil", listOf("Foto 01", "Foto 1", "Foto 2"), sortedNames("Foto 2", "Foto 1", "Foto 01"))
    }

    @Test
    fun caseInsensitiveAndGermanUmlauts() {
        assertEquals(listOf("Apfel", "banane", "Birne"), sortedNames("Birne", "banane", "Apfel"))
        val sorted = sortedNames("Zebra", "Äpfel", "Birne", "Apfel", "Ofen", "Öl")
        assertEquals(listOf("Apfel", "Äpfel", "Birne", "Ofen", "Öl", "Zebra"), sorted)
        // macOS speichert Umlaute oft zerlegt (A + Trema) – gleiche Position wie „Ä“.
        val decomposed = "Ärger"
        val withDecomposed = sortedNames("Zebra", decomposed, "Birne")
        assertEquals(listOf(decomposed, "Birne", "Zebra"), withDecomposed)
    }

    @Test
    fun identicalIgnoringCaseIsStillDeterministic() {
        assertEquals(sortedNames("a", "A"), sortedNames("A", "a"))
    }

    private fun entry(name: String, dir: Boolean = false, size: Long = 0, modified: Long = 0) = FileEntry(
        path = "/v/$name", name = name, isDirectory = dir, sizeBytes = size, modifiedMillis = modified,
        isHidden = name.startsWith("."), kind = FileTypes.kindOf(name, dir), extension = FileTypes.extensionOf(name),
        mimeType = null, readable = true, writable = true,
    )

    @Test
    fun foldersFirstInEveryOrder() {
        val list = listOf(entry("b.txt"), entry("Zeta", dir = true), entry("a.txt"), entry("Alpha", dir = true))
        assertEquals(listOf("Alpha", "Zeta", "a.txt", "b.txt"), FileSorting.sorted(list, SortOrder()).map { it.name })
        assertEquals(
            listOf("Zeta", "Alpha", "b.txt", "a.txt"),
            FileSorting.sorted(list, SortOrder(SortKey.NAME, ascending = false)).map { it.name },
        )
        assertEquals(
            "ohne Ordner-zuerst",
            listOf("a.txt", "Alpha", "b.txt", "Zeta"),
            FileSorting.sorted(list, SortOrder(), foldersFirst = false).map { it.name },
        )
    }

    @Test
    fun dateSizeAndKind() {
        val list = listOf(
            entry("alt.txt", modified = 1, size = 300),
            entry("neu.jpg", modified = 3, size = 100),
            entry("auch-neu.pdf", modified = 3, size = 200),
            entry("Ordner B", dir = true, modified = 9),
            entry("Ordner A", dir = true, modified = 1),
        )
        assertEquals(
            "neueste zuerst, Gleichstand nach Name",
            listOf("Ordner B", "Ordner A", "auch-neu.pdf", "neu.jpg", "alt.txt"),
            FileSorting.sorted(list, SortOrder(SortKey.DATE, ascending = false)).map { it.name },
        )
        assertEquals(
            "größte zuerst, Ordner nach Name",
            listOf("Ordner A", "Ordner B", "alt.txt", "auch-neu.pdf", "neu.jpg"),
            FileSorting.sorted(list, SortOrder(SortKey.SIZE, ascending = false)).map { it.name },
        )
        assertEquals(
            "nach Art: Bild, PDF-Dokument, Textdatei",
            listOf("Ordner A", "Ordner B", "neu.jpg", "auch-neu.pdf", "alt.txt"),
            FileSorting.sorted(list, SortOrder(SortKey.KIND)).map { it.name },
        )
    }
}
