package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FileNamesTest {

    @Test
    fun validNamesPass() {
        for (name in listOf("Foto.jpg", ".nomedia", "Ordner 2", "Grüße ✓.txt", "a", "x".repeat(255), "ä".repeat(127) + "a")) {
            assertNull(name, FileNames.validate(name))
        }
    }

    @Test
    fun everyProblemIsDetected() {
        assertEquals(NameProblem.EMPTY, FileNames.validate(""))
        assertEquals(NameProblem.DOTS_ONLY, FileNames.validate("."))
        assertEquals(NameProblem.DOTS_ONLY, FileNames.validate(".."))
        assertEquals(NameProblem.SLASH, FileNames.validate("a/b"))
        for (c in listOf('"', '*', ':', '<', '>', '?', '\\', '|')) {
            assertEquals("Zeichen $c", NameProblem.FORBIDDEN_CHARACTER, FileNames.validate("a${c}b"))
        }
        assertEquals(NameProblem.CONTROL_CHARACTER, FileNames.validate("a\u0001b"))
        assertEquals(NameProblem.CONTROL_CHARACTER, FileNames.validate("a\nb"))
        assertEquals(NameProblem.CONTROL_CHARACTER, FileNames.validate("a\u007Fb"))
        assertEquals(NameProblem.TOO_LONG, FileNames.validate("x".repeat(256)))
        assertEquals("Umlaut = 2 Byte", NameProblem.TOO_LONG, FileNames.validate("ä".repeat(128)))
        assertEquals(NameProblem.TOO_LONG, FileNames.validate("😀".repeat(64)))
        assertEquals(NameProblem.TRAILING_DOT_OR_SPACE, FileNames.validate("Name."))
        assertEquals(NameProblem.TRAILING_DOT_OR_SPACE, FileNames.validate("Name "))
        assertEquals(NameProblem.TRAILING_DOT_OR_SPACE, FileNames.validate("..."))
        assertEquals(NameProblem.RESERVED, FileNames.validate("bild.jpg.aether-part"))
        assertEquals(NameProblem.RESERVED, FileNames.validate("BILD.AETHER-PART"))
        assertEquals(NameProblem.RESERVED, FileNames.validate(".AetherTrash"))
        assertEquals(NameProblem.RESERVED, FileNames.validate(".aethertrash"))
    }

    @Test
    fun uniqueNameCountsUpLikeTheFinder() {
        val taken = mutableSetOf("foto.jpg")
        val isTaken: (String) -> Boolean = { it.lowercase() in taken }
        assertEquals("Frei bleibt frei", "Neu.jpg", FileNames.uniqueName("Neu.jpg", false, isTaken))
        assertEquals("Foto 2.jpg", FileNames.uniqueName("Foto.jpg", false, isTaken))
        taken += "foto 2.jpg"
        assertEquals("Groß-/Kleinschreibung zählt nicht", "FOTO 3.JPG", FileNames.uniqueName("FOTO.JPG", false, isTaken))
        assertEquals("vorhandene Nummer wird hochgezählt", "Foto 3.jpg", FileNames.uniqueName("Foto 2.jpg", false, isTaken))
    }

    @Test
    fun uniqueNameForFoldersDotfilesAndSpecialCases() {
        val all: (String) -> Boolean = { it in setOf("Ordner", "Ordner 2", ".nomedia", "Projekt.v1", "a.tar.gz", "Urlaub 2024.jpg") }
        assertEquals("Ordner 3", FileNames.uniqueName("Ordner", true, all))
        assertEquals("Ordner ohne Endung", "Projekt.v1 2", FileNames.uniqueName("Projekt.v1", true, all))
        assertEquals(".nomedia 2", FileNames.uniqueName(".nomedia", false, all))
        assertEquals("a 2.tar.gz", FileNames.uniqueName("a.tar.gz", false, all))
        assertEquals("Jahreszahl bleibt", "Urlaub 2024 2.jpg", FileNames.uniqueName("Urlaub 2024.jpg", false, all))
    }

    @Test
    fun uniqueNameNeverExceedsTheLimit() {
        val long = "ü".repeat(124) + ".jpg" // 248 + 4 = 252 Byte
        val result = FileNames.uniqueName(long, false) { it == long }
        assertTrue(FileNames.utf8Length(result) <= FileNames.MAX_BYTES)
        assertTrue(result.endsWith(" 2.jpg"))
        assertNull(FileNames.validate(result))
    }

    @Test
    fun fitToBytesNeverSplitsACharacter() {
        assertEquals("ää", FileNames.fitToBytes("äää", 5))
        assertEquals("", FileNames.fitToBytes("😀", 3))
        assertEquals(4, FileNames.utf8Length("😀"))
        assertEquals(6, FileNames.utf8Length("äöü"))
    }
}
