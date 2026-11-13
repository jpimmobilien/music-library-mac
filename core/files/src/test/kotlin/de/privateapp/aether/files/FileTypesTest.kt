package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FileTypesTest {

    @Test
    fun extensionRules() {
        assertEquals("jpg", FileTypes.extensionOf("IMG_0001.JPG"))
        assertEquals("gz", FileTypes.extensionOf("a.tar.gz"))
        assertEquals("Punkt am Anfang ist keine Endung", "", FileTypes.extensionOf(".nomedia"))
        assertEquals("", FileTypes.extensionOf("README"))
        assertEquals("", FileTypes.extensionOf("datei."))
        assertEquals("json", FileTypes.extensionOf(".config.json"))
    }

    @Test
    fun mimeTypes() {
        assertEquals("image/jpeg", FileTypes.mimeTypeOf("jpg"))
        assertEquals("image/jpeg", FileTypes.mimeTypeOf(".JPEG"))
        assertEquals("application/pdf", FileTypes.mimeTypeOf("pdf"))
        assertEquals("application/vnd.android.package-archive", FileTypes.mimeTypeOf("apk"))
        assertEquals("text/x-vcard", FileTypes.mimeTypeOf("vcf"))
        assertNull("kein registrierter Typ", FileTypes.mimeTypeOf("xapk"))
        assertNull(FileTypes.mimeTypeOf("unbekannt"))
    }

    @Test
    fun kindByExtensionAndMime() {
        assertEquals(FileKind.FOLDER, FileTypes.kindOf("Bilder.jpg", isDirectory = true))
        assertEquals(FileKind.IMAGE, FileTypes.kindOf("a.HEIC", false))
        assertEquals(FileKind.VIDEO, FileTypes.kindOf("clip.mkv", false))
        assertEquals(FileKind.AUDIO, FileTypes.kindOf("song.opus", false))
        assertEquals(FileKind.PDF, FileTypes.kindOf("r.pdf", false))
        assertEquals(FileKind.TEXT, FileTypes.kindOf("notes.md", false))
        assertEquals(FileKind.DOCUMENT, FileTypes.kindOf("brief.docx", false))
        assertEquals(FileKind.ARCHIVE, FileTypes.kindOf("x.7z", false))
        assertEquals(FileKind.APK, FileTypes.kindOf("app.apks", false))
        assertEquals(FileKind.OTHER, FileTypes.kindOf("daten.bin", false))
        assertEquals("MIME hat Vorrang", FileKind.IMAGE, FileTypes.kindOf("daten.bin", false, "image/png"))
        assertEquals("MIME mit Parametern", FileKind.TEXT, FileTypes.kindOf("x", false, "text/plain; charset=utf-8"))
        assertEquals("exakter MIME-Typ", FileKind.DOCUMENT, FileTypes.kindOf("x", false, "application/msword"))
        assertEquals("unbrauchbarer MIME → Endung", FileKind.PDF, FileTypes.kindOf("a.pdf", false, "application/octet-stream"))
    }

    @Test
    fun extensionsOfKind() {
        val images = FileTypes.extensionsOf(FileKind.IMAGE)
        assertTrue(images.containsAll(listOf("jpg", "jpeg", "png", "heic", "webp", "svg")))
        assertTrue("nur Kleinbuchstaben ohne Punkt", images.all { it == it.lowercase() && !it.startsWith(".") })
        assertTrue(FileTypes.extensionsOf(FileKind.APK).containsAll(listOf("apk", "apks", "xapk", "aab")))
        assertEquals(setOf("pdf"), FileTypes.extensionsOf(FileKind.PDF))
        assertTrue(FileTypes.extensionsOf(FileKind.FOLDER).isEmpty())
        assertTrue(FileTypes.extensionsOf(FileKind.OTHER).isEmpty())
        // Jede Endung gehört genau zu der Art, die kindOf liefert.
        for (kind in FileKind.entries) {
            for (extension in FileTypes.extensionsOf(kind)) assertEquals(extension, kind, FileTypes.kindOf("a.$extension", false))
        }
    }
}
