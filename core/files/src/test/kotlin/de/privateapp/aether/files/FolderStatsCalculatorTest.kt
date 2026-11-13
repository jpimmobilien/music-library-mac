package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files

class FolderStatsCalculatorTest {

    @get:Rule
    val tmp = TemporaryFolder()

    @Test
    fun countsRecursivelyWithoutFollowingLinks() = blocking {
        val root = tmp.newFolder("Statistik")
        root.writeBytesFile("a.bin", ByteArray(100))
        root.writeBytesFile("Sub/b.bin", ByteArray(50))
        root.writeBytesFile("Sub/Tief/.versteckt", ByteArray(7))
        root.dir("Leer")
        root.writeBytesFile("x.jpg.aether-part", ByteArray(999)) // gehört AETHER, zählt nicht
        val outside = tmp.newFolder("Draussen")
        outside.writeBytesFile("gross.bin", ByteArray(10_000))
        Files.createSymbolicLink(File(root, "Link").toPath(), outside.toPath())

        val stats = FolderStatsCalculator.compute(root.path)
        assertEquals(FolderStats(files = 4, folders = 3, totalBytes = 157, complete = true), stats)
    }

    @Test
    fun fileAndMissingPath() = blocking {
        val file = tmp.root.writeBytesFile("einzeln.bin", ByteArray(42))
        assertEquals(FolderStats(1, 0, 42, complete = true), FolderStatsCalculator.compute(file.path))
        assertEquals(FolderStats(0, 0, 0, complete = false), FolderStatsCalculator.compute(File(tmp.root, "fehlt").path))
    }
}
