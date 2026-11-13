package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ZipContentsTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun zip(name: String, vararg entries: Pair<String, ByteArray?>): File {
        val f = File(tmp.root, name)
        ZipOutputStream(FileOutputStream(f)).use { out ->
            for ((path, data) in entries) {
                out.putNextEntry(ZipEntry(path))
                if (data != null) out.write(data)
                out.closeEntry()
            }
        }
        return f
    }

    @Test
    fun listsFilesFoldersAndTotals() {
        val f = zip(
            "a.zip",
            "Fotos/" to null,
            "Fotos/Strand.jpg" to ByteArray(1000) { 1 },
            "Fotos/Berg.jpg" to ByteArray(500) { 2 },
            "liesmich.txt" to "Hallo".toByteArray(),
        )
        val c = ZipContentsReader.read(f.path) as ZipContents.Listed
        assertEquals(4, c.totalEntries)
        assertEquals(3, c.files)
        assertEquals(1, c.folders)
        assertEquals(1505L, c.totalBytes)
        assertFalse(c.sizeUnknown)
        assertFalse(c.encrypted)
        assertFalse(c.truncated)
        assertEquals(0, c.unsafeEntries)
        assertEquals("UTF-8", c.charsetName)
        val strand = c.entries.first { it.path == "Fotos/Strand.jpg" }
        assertEquals("Strand.jpg", strand.name)
        assertEquals("Fotos", strand.parent)
        assertEquals(1000L, strand.sizeBytes)
        assertTrue("komprimiert kleiner", strand.compressedBytes in 1..999)
        assertEquals("Fotos", c.entries.first { it.isDirectory }.path)
    }

    @Test
    fun flagsUnsafeEntriesAndSkipsMacosMetadata() {
        val f = zip(
            "b.zip",
            "../../evil.sh" to "x".toByteArray(),
            "/etc/abs.txt" to "x".toByteArray(),
            "C:/win.txt" to "x".toByteArray(),
            "ok/../../up.txt" to "x".toByteArray(),
            "__MACOSX/._ok.txt" to "x".toByteArray(),
            "ok.txt" to "x".toByteArray(),
        )
        val c = ZipContentsReader.read(f.path) as ZipContents.Listed
        assertEquals(5, c.totalEntries)
        assertEquals(4, c.unsafeEntries)
        assertEquals(1, c.macosEntries)
        assertTrue(c.entries.single { it.path == "ok.txt" }.let { !it.unsafe })
        assertTrue(c.entries.filter { it.path != "ok.txt" }.all { it.unsafe })
    }

    @Test
    fun capsListedEntriesButCountsAll() {
        val entries = (1..50).map { "f$it.txt" to "x".toByteArray() }.toTypedArray()
        val f = zip("c.zip", *entries)
        val c = ZipContentsReader.read(f.path, maxEntries = 10) as ZipContents.Listed
        assertEquals(10, c.entries.size)
        assertEquals(50, c.totalEntries)
        assertEquals(50, c.files)
        assertTrue(c.truncated)
    }

    @Test
    fun storedEntriesReportSizes() {
        val data = ByteArray(300) { it.toByte() }
        val f = File(tmp.root, "s.zip")
        ZipOutputStream(FileOutputStream(f)).use { out ->
            val e = ZipEntry("roh.bin")
            e.method = ZipEntry.STORED
            e.size = data.size.toLong()
            e.compressedSize = data.size.toLong()
            e.crc = CRC32().apply { update(data) }.value
            out.putNextEntry(e)
            out.write(data)
            out.closeEntry()
        }
        val c = ZipContentsReader.read(f.path) as ZipContents.Listed
        assertEquals(300L, c.entries.single().sizeBytes)
        assertEquals(300L, c.entries.single().compressedBytes)
        assertEquals(0, c.unsupportedEntries)
    }

    @Test
    fun detectsEncryptionFlagInCentralDirectory() {
        val f = File(tmp.root, "e.zip").apply { writeBytes(rawZip(listOf(RawEntry("geheim.txt", "vertraulich".toByteArray(), flag = 1)))) }
        assertEquals(1, CentralDirectory.scan(f).encrypted)
        // Die JVM lehnt verschlüsselte Archive beim Öffnen ab, ältere Android-Versionen listen sie: In beiden Fällen
        // zeigt AETHER den Inhalt und sperrt das Entpacken.
        val c = ZipContentsReader.read(f.path) as ZipContents.Listed
        assertTrue(c.encrypted)
        assertFalse(c.extractable)
        assertEquals("geheim.txt", c.entries.single().path)
    }

    @Test
    fun unsupportedMethodIsReportedNotCalledBroken() {
        // Verfahren 12 = BZip2 (Inhalt egal, es wird nie entpackt) neben einem normalen Eintrag.
        val f = File(tmp.root, "bz.zip").apply {
            writeBytes(rawZip(listOf(RawEntry("a.txt", "BZh91AY&SY".toByteArray(), method = 12), RawEntry("b.txt", "Hallo".toByteArray()))))
        }
        val c = ZipContentsReader.read(f.path) as ZipContents.Listed
        assertEquals(2, c.totalEntries)
        assertEquals(1, c.unsupportedEntries)
        assertFalse(c.encrypted)
        assertEquals(listOf("a.txt", "b.txt"), c.entries.map { it.path })
    }

    @Test
    fun forgedZip64SizesNeverOverflow() {
        // Zwei Einträge, die laut ZIP64-Zusatzfeld je 2^62 Byte groß sein wollen: Die Summe darf nicht negativ werden.
        val f = File(tmp.root, "z64.zip").apply {
            writeBytes(rawZip(listOf(RawEntry("big0.bin", "x".toByteArray(), zip64Size = 1L shl 62), RawEntry("big1.bin", "x".toByteArray(), zip64Size = 1L shl 62))))
        }
        when (val c = ZipContentsReader.read(f.path)) {
            is ZipContents.Listed -> {
                assertTrue("Summe ${c.totalBytes}", c.totalBytes >= 0)
                assertTrue("Summe ${c.compressedBytes}", c.compressedBytes >= 0)
                assertTrue(c.entries.all { it.sizeBytes >= -1 })
                if (c.totalBytes == Long.MAX_VALUE) assertTrue(c.sizeUnknown)
            }
            is ZipContents.Unsupported -> Unit // falls die Laufzeit solche Angaben schon beim Öffnen ablehnt
            else -> throw AssertionError("unerwartet: $c")
        }
        var flagged = false
        assertEquals(Long.MAX_VALUE, ZipContentsReader.saturatingAdd(1L shl 62, 1L shl 62) { flagged = true } + (1L shl 62) - (1L shl 62))
        assertTrue(flagged)
    }

    @Test
    fun selfExtractingArchiveWithPrefixIsScannedCorrectly() {
        val prefix = ByteArray(1000) { 'M'.code.toByte() }
        val f = File(tmp.root, "sfx.zip").apply { writeBytes(rawZip(listOf(RawEntry("geheim.txt", "x".toByteArray(), flag = 1)), prefix)) }
        val d = CentralDirectory.scan(f)
        assertEquals(1, d.records)
        assertEquals(1, d.encrypted)
    }

    @Test
    fun notAZipAndMissing() {
        val notZip = tmp.root.writeTextFile("kein.zip", "nur Text, kein Archiv")
        assertTrue(ZipContentsReader.read(notZip.path) is ZipContents.Unsupported)
        assertEquals(ZipContents.NotFound, ZipContentsReader.read(File(tmp.root, "fehlt.zip").path))
        assertTrue(ZipContentsReader.read(tmp.root.path) is ZipContents.Unsupported)
    }

    @Test
    fun ibm437NamesFromOldWindowsArchives() {
        // „Übersicht.txt“ in IBM-437 (Ü = 0x9A), ohne UTF-8-Kennzeichen.
        val f = File(tmp.root, "alt.zip")
        ZipOutputStream(FileOutputStream(f), charset("IBM437")).use { out ->
            out.putNextEntry(ZipEntry("Übersicht.txt"))
            out.write("x".toByteArray())
            out.closeEntry()
        }
        val c = ZipContentsReader.read(f.path) as ZipContents.Listed
        assertEquals("Übersicht.txt", c.entries.single().path)
        assertEquals("IBM-437", c.charsetName)
    }

    @Test
    fun sha256MatchesJdkDigestAndReportsProgress() = blocking {
        val data = pseudoRandomBytes(700_000)
        val f = tmp.root.writeBytesFile("daten.bin", data)
        var last = 0L
        val hex = Checksums.sha256(f.path, bufferSize = 64 * 1024) { last = it }
        val expected = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
        assertEquals(expected, hex)
        assertEquals(700_000L, last)
        // Bekannter Prüfwert der leeren Datei
        val empty = tmp.root.writeBytesFile("leer.bin", ByteArray(0))
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Checksums.sha256(empty.path))
    }

    private class RawEntry(val name: String, val data: ByteArray, val method: Int = 0, val flag: Int = 0, val zip64Size: Long? = null)

    /** Baut ein ZIP Byte für Byte (für Fälle, die java.util.zip nicht erzeugt: fremde Verfahren, Kennzeichen, ZIP64). */
    private fun rawZip(entries: List<RawEntry>, prefix: ByteArray = ByteArray(0)): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        fun u16(v: Int) { out.write(v and 0xFF); out.write(v shr 8 and 0xFF) }
        fun u32(v: Long) { for (i in 0 until 4) out.write((v shr (8 * i) and 0xFF).toInt()) }
        fun u64(v: Long) { for (i in 0 until 8) out.write((v shr (8 * i) and 0xFF).toInt()) }
        out.write(prefix)
        val offsets = ArrayList<Long>()
        for (e in entries) {
            offsets += (out.size() - prefix.size).toLong()
            val crc = CRC32().apply { update(e.data) }.value
            u32(0x04034b50); u16(20); u16(e.flag); u16(e.method); u16(0); u16(0x21)
            u32(crc); u32(e.data.size.toLong()); u32(e.data.size.toLong())
            val name = e.name.toByteArray()
            u16(name.size); u16(0); out.write(name); out.write(e.data)
        }
        val cdStart = out.size()
        entries.forEachIndexed { i, e ->
            val crc = CRC32().apply { update(e.data) }.value
            val name = e.name.toByteArray()
            u32(0x02014b50); u16(45); u16(if (e.zip64Size != null) 45 else 20); u16(e.flag); u16(e.method); u16(0); u16(0x21)
            u32(crc)
            if (e.zip64Size != null) { u32(0xFFFFFFFFL); u32(0xFFFFFFFFL) } else { u32(e.data.size.toLong()); u32(e.data.size.toLong()) }
            u16(name.size); u16(if (e.zip64Size != null) 20 else 0); u16(0); u16(0); u16(0); u32(0); u32(offsets[i])
            out.write(name)
            if (e.zip64Size != null) { u16(0x0001); u16(16); u64(e.zip64Size); u64(e.zip64Size) }
        }
        val cdSize = out.size() - cdStart
        u32(0x06054b50); u16(0); u16(0); u16(entries.size); u16(entries.size); u32(cdSize.toLong()); u32((cdStart - prefix.size).toLong()); u16(0)
        return out.toByteArray()
    }
}
