package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.file.AccessDeniedException
import java.nio.file.FileSystemException
import java.nio.file.NoSuchFileException

class IoErrorsTest {

    private fun reason(e: Throwable) = IoErrors.classify(e)

    @Test
    fun exceptionTypes() {
        assertEquals(FailureReason.ACCESS_DENIED, reason(AccessDeniedException("/x")))
        assertEquals(FailureReason.NOT_FOUND, reason(NoSuchFileException("/x")))
        assertEquals(FailureReason.ACCESS_DENIED, reason(kotlin.io.AccessDeniedException(java.io.File("/x"))))
        assertEquals(FailureReason.IO_ERROR, reason(IOException("etwas anderes")))
        assertEquals(FailureReason.IO_ERROR, reason(RuntimeException()))
    }

    @Test
    fun androidMessages() {
        assertEquals(FailureReason.ACCESS_DENIED, reason(FileNotFoundException("/storage/1234-ABCD/a.txt: open failed: EACCES (Permission denied)")))
        assertEquals(FailureReason.ACCESS_DENIED, reason(IOException("rename failed: EPERM (Operation not permitted)")))
        assertEquals(FailureReason.NOT_FOUND, reason(FileNotFoundException("/x: open failed: ENOENT (No such file or directory)")))
        assertEquals(FailureReason.NO_SPACE, reason(IOException("write failed: ENOSPC (No space left on device)")))
        assertEquals(FailureReason.FILE_TOO_LARGE, reason(IOException("write failed: EFBIG (File too large)")))
        assertEquals(FailureReason.READ_ONLY, reason(IOException("open failed: EROFS (Read-only file system)")))
        assertEquals(FailureReason.INVALID_NAME, reason(IOException("open failed: EINVAL (Invalid argument)")))
        assertEquals(FailureReason.INVALID_NAME, reason(IOException("open failed: ENAMETOOLONG (File name too long)")))
    }

    @Test
    fun jvmMessages() {
        assertEquals(FailureReason.ACCESS_DENIED, reason(FileNotFoundException("/tmp/x (Permission denied)")))
        assertEquals(FailureReason.NOT_FOUND, reason(FileNotFoundException("/tmp/x (No such file or directory)")))
        assertEquals(FailureReason.READ_ONLY, reason(FileSystemException("/x", null, "Read-only file system")))
        assertEquals(FailureReason.INVALID_NAME, reason(FileSystemException("/x", null, "Invalid argument")))
        assertEquals(FailureReason.NO_SPACE, reason(IOException("No space left on device")))
    }

    @Test
    fun pathsDoNotTriggerFalseReasons() {
        assertEquals(FailureReason.ACCESS_DENIED, reason(FileNotFoundException("/x/No space left (2).txt (Permission denied)")))
        assertEquals(FailureReason.IO_ERROR, reason(FileSystemException("/x/Read-only file system.txt")))
    }

    @Test
    fun causesAreFollowed() {
        assertEquals(FailureReason.NO_SPACE, reason(RuntimeException("Hülle", IOException("ENOSPC"))))
    }
}
