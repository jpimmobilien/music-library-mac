package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.nio.charset.Charset

class TextPreviewReaderTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun file(bytes: ByteArray): String = tmp.root.writeBytesFile("t-${bytes.contentHashCode()}.txt", bytes).path

    @Test
    fun utf8() {
        val preview = TextPreviewReader.read(file("Grüße aus Köln – 😀".toByteArray()))
        assertEquals("Grüße aus Köln – 😀", preview.text)
        assertEquals("UTF-8", preview.charsetName)
        assertFalse(preview.truncated)
        assertFalse(preview.looksBinary)
    }

    @Test
    fun boms() {
        val utf8Bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "Äpfel".toByteArray()
        assertEquals("Äpfel", TextPreviewReader.read(file(utf8Bom)).text)
        assertEquals("UTF-8", TextPreviewReader.read(file(utf8Bom)).charsetName)

        val le = byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + "Straße".toByteArray(Charsets.UTF_16LE)
        assertEquals("Straße", TextPreviewReader.read(file(le)).text)
        assertEquals("UTF-16LE", TextPreviewReader.read(file(le)).charsetName)

        val be = byteArrayOf(0xFE.toByte(), 0xFF.toByte()) + "Straße".toByteArray(Charsets.UTF_16BE)
        assertEquals("Straße", TextPreviewReader.read(file(be)).text)
        assertEquals("UTF-16BE", TextPreviewReader.read(file(be)).charsetName)
    }

    @Test
    fun windows1252Fallback() {
        val bytes = "Grüße, schöne Straße – 5 €".toByteArray(Charset.forName("windows-1252"))
        val preview = TextPreviewReader.read(file(bytes))
        assertEquals("Grüße, schöne Straße – 5 €", preview.text)
        assertEquals("windows-1252", preview.charsetName)
    }

    @Test
    fun singleBrokenByteInUtf8StaysUtf8() {
        val bytes = "Ärger über Öl: äöü ÄÖÜ ß".toByteArray() + byteArrayOf(0xFF.toByte()) + "ok".toByteArray()
        val preview = TextPreviewReader.read(file(bytes))
        assertEquals("UTF-8", preview.charsetName)
        assertTrue(preview.text.startsWith("Ärger über Öl"))
    }

    @Test
    fun strayBytesMakeThePreviewLossy() {
        val utf8 = TextPreviewReader.read(file("Grüße aus München ".toByteArray() + byteArrayOf(0xFF.toByte()) + " Ende".toByteArray()))
        assertEquals("UTF-8", utf8.charsetName)
        assertTrue("Bearbeiten würde das Byte verändern", utf8.lossy)
        assertEquals("Grüße aus München \uFFFD Ende", utf8.text)

        val undefined = TextPreviewReader.read(file("Gr".toByteArray() + byteArrayOf(0xFC.toByte(), 0x81.toByte()) + "e".toByteArray()))
        assertEquals("windows-1252", undefined.charsetName)
        assertTrue("0x81 ist in windows-1252 nicht belegt", undefined.lossy)

        val oddUtf16 = TextPreviewReader.read(file(byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + "ab".toByteArray(Charsets.UTF_16LE) + byteArrayOf(0x41)))
        assertTrue("überzähliges Byte in UTF-16", oddUtf16.lossy)
    }

    @Test
    fun cleanFilesAreNotLossy() {
        assertFalse(TextPreviewReader.read(file("Grüße 😀".toByteArray())).lossy)
        assertFalse(TextPreviewReader.read(file("Grüße".toByteArray(Charset.forName("windows-1252")))).lossy)
        assertFalse(TextPreviewReader.read(file(byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + "Straße".toByteArray(Charsets.UTF_16LE))).lossy)
        val cut = TextPreviewReader.read(file("ä".repeat(100).toByteArray()), maxBytes = 51)
        assertTrue(cut.truncated)
        assertFalse("Abschneiden der Vorschau ist kein Datenfehler", cut.lossy)
        val cut16 = TextPreviewReader.read(file(byteArrayOf(0xFE.toByte(), 0xFF.toByte()) + "😀😀😀".toByteArray(Charsets.UTF_16BE)), maxBytes = 9)
        assertTrue(cut16.truncated)
        assertFalse(cut16.lossy)
        assertEquals("😀", cut16.text)
    }

    @Test
    fun binaryIsDetected() {
        val preview = TextPreviewReader.read(file(byteArrayOf(0x50, 0x4B, 3, 4, 0, 0, 1, 2)))
        assertTrue(preview.looksBinary)
        assertEquals("", preview.text)
    }

    @Test
    fun truncationNeverSplitsACharacter() {
        val text = "ä".repeat(100) // 200 Byte
        val preview = TextPreviewReader.read(file(text.toByteArray()), maxBytes = 51)
        assertTrue(preview.truncated)
        assertEquals("ä".repeat(25), preview.text)
        assertEquals("UTF-8", preview.charsetName)
        val exact = TextPreviewReader.read(file(text.toByteArray()), maxBytes = 200)
        assertFalse("genau so lang wie erlaubt", exact.truncated)
        assertEquals(text, exact.text)
    }

    @Test
    fun emptyAndMissing() {
        val empty = TextPreviewReader.read(file(ByteArray(0)))
        assertEquals("", empty.text)
        assertFalse(empty.looksBinary)
        try {
            TextPreviewReader.read(File(tmp.root, "fehlt.txt").path)
            throw AssertionError("IOException erwartet")
        } catch (e: IOException) {
            // erwartet
        }
    }
}
