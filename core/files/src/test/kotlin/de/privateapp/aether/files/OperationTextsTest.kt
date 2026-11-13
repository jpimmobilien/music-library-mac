package de.privateapp.aether.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OperationTextsTest {

    private fun report(
        op: FileOperation,
        succeeded: Int = 0,
        skipped: Int = 0,
        failures: List<Failure> = emptyList(),
        cancelled: Boolean = false,
    ) = OperationReport(op, succeeded, skipped, failures, cancelled, 0, emptyList(), emptyList())

    @Test
    fun titlesNameSingleItemsAndCountMany() {
        assertEquals("„Foto.jpg“ kopieren", OperationTexts.title(FileOperation.Copy(listOf("/s/a/Foto.jpg"), "/s/b")))
        assertEquals("3 Objekte verschieben", OperationTexts.title(FileOperation.Move(listOf("/a", "/b", "/c"), "/t")))
        assertEquals("„Urlaub“ in den Papierkorb legen", OperationTexts.title(FileOperation.Trash(listOf("/s/Urlaub/"))))
        assertEquals("„urlaub.zip“ erstellen", OperationTexts.title(FileOperation.Compress(listOf("/a"), "/t", "urlaub")))
        assertEquals("„x.ZIP“ erstellen", OperationTexts.title(FileOperation.Compress(listOf("/a"), "/t", "x.ZIP")))
        assertEquals("1.234 Objekte", OperationTexts.items(1234))
        assertEquals("1 Objekt", OperationTexts.items(1))
    }

    @Test
    fun onlyPotentiallyLongOperationsUseTheForegroundService() {
        assertTrue(OperationTexts.mayTakeLong(FileOperation.Copy(listOf("/a"), "/t")))
        assertTrue(OperationTexts.mayTakeLong(FileOperation.Extract("/a.zip", "/t")))
        assertFalse(OperationTexts.mayTakeLong(FileOperation.Rename("/a", "b")))
        assertFalse(OperationTexts.mayTakeLong(FileOperation.Trash(listOf("/a"))))
        assertTrue(OperationTexts.mayTakeLong(FileOperation.Trash((1..21).map { "/f$it" })))
    }

    @Test
    fun successSummaryCountsWhatActuallyHappened() {
        val s = OperationTexts.summary(report(FileOperation.Copy(listOf("/a", "/b", "/c"), "/t"), succeeded = 2, skipped = 1))
        assertEquals("2 Objekte kopiert", s.headline)
        assertEquals("1 übersprungen.", s.detail)
        assertFalse(s.isProblem)
        val none = OperationTexts.summary(report(FileOperation.Copy(listOf("/a"), "/t"), succeeded = 0, skipped = 1))
        assertEquals("Nichts kopiert", none.headline)
    }

    @Test
    fun cancelledSummarySaysWhatRemains() {
        val s = OperationTexts.summary(report(FileOperation.Move(listOf("/a", "/b", "/c", "/d"), "/t"), succeeded = 1, cancelled = true))
        assertEquals("Verschieben abgebrochen", s.headline)
        assertEquals("1 von 4 Objekten bereits verschoben – das bleibt so. Unfertige Dateien wurden entfernt.", s.detail)
        val nothing = OperationTexts.summary(report(FileOperation.Trash(listOf("/a")), cancelled = true))
        assertEquals("Es wurde nichts geändert.", nothing.detail)
    }

    @Test
    fun failuresAreProblemsWithTheReasonInWords() {
        val f = Failure("/s/a.mkv", FailureReason.FILE_TOO_LARGE)
        val all = OperationTexts.summary(report(FileOperation.Copy(listOf("/s/a.mkv"), "/sd"), failures = listOf(f)))
        assertTrue(all.isProblem)
        assertEquals("Kopieren nicht möglich", all.headline)
        assertTrue(all.detail!!.startsWith(FailureReason.FILE_TOO_LARGE.message))
        val partial = OperationTexts.summary(report(FileOperation.Copy(listOf("/a", "/b"), "/t"), succeeded = 1, failures = listOf(Failure("/b", FailureReason.NO_SPACE))))
        assertEquals("Kopieren unvollständig", partial.headline)
        assertTrue(partial.detail!!.contains("1 von 2 Objekten kopiert"))
    }

    @Test
    fun quietOperationsHaveShortHeadlines() {
        assertEquals("Umbenannt", OperationTexts.summary(report(FileOperation.Rename("/a", "b"), succeeded = 1)).headline)
        assertEquals("Ordner „Neu“ erstellt", OperationTexts.summary(report(FileOperation.CreateFolder("/t", "Neu"), succeeded = 1)).headline)
        assertNull(OperationTexts.summary(report(FileOperation.WriteText("/a.txt", "x", null), succeeded = 1)).detail)
    }

    @Test
    fun progressItemsUsesTheDative() {
        assertEquals("3 von 12 Objekten", OperationTexts.progressItems(3, 12))
        assertEquals("0 von 1 Objekt", OperationTexts.progressItems(0, 1))
        assertEquals("1 von 1 Objekt", OperationTexts.progressItems(1, 1))
        assertEquals("1.234 von 5.000 Objekten", OperationTexts.progressItems(1234, 5000))
        assertEquals("1 Datei", OperationTexts.files(1))
        assertEquals("2 Dateien", OperationTexts.files(2))
    }

    private fun changedReport(
        op: FileOperation,
        cancelled: Boolean,
        partialDone: Int,
        partialLeft: Int = 0,
        failures: List<Failure> = emptyList(),
    ) = OperationReport(
        op, 0, 0, failures, cancelled, 0, listOf("/t/x"), listOf("/s/x"),
        partialFilesDone = partialDone, partialFilesLeft = partialLeft,
    )

    @Test
    fun cancelledSplitMoveSaysWhereEverythingIs() {
        val s = OperationTexts.summary(changedReport(FileOperation.Move(listOf("/s/Album"), "/t"), cancelled = true, partialDone = 2, partialLeft = 2))
        assertEquals("Verschieben abgebrochen", s.headline)
        assertEquals(
            "2 Dateien liegen bereits im Ziel, 2 Dateien noch am Ursprungsort. " +
                "Gelöscht wurde nur, was vollständig und geprüft im Ziel angekommen ist. Unfertige Dateien wurden entfernt.",
            s.detail,
        )
        assertTrue(s.isProblem)
    }

    @Test
    fun neverNothingChangedWhenPathsChanged() {
        val delete = OperationTexts.summary(changedReport(FileOperation.DeletePermanently(listOf("/s/Gross")), cancelled = true, partialDone = 101))
        assertEquals("101 Dateien wurden bereits endgültig gelöscht.", delete.detail)
        val onlyPaths = OperationTexts.summary(changedReport(FileOperation.Copy(listOf("/s/a"), "/t"), cancelled = true, partialDone = 0))
        assertFalse(onlyPaths.detail!!.contains("nichts geändert"))
        val failed = OperationTexts.summary(
            changedReport(FileOperation.Move(listOf("/s/Mix"), "/t"), cancelled = false, partialDone = 2, partialLeft = 1, failures = listOf(Failure("/s/Mix/b", FailureReason.VERIFICATION_FAILED))),
        )
        assertEquals("Verschieben unvollständig", failed.headline)
        assertTrue(failed.detail!!.contains("2 Dateien liegen bereits im Ziel, 1 Datei noch am Ursprungsort."))
    }

    @Test
    fun deliberatelySkippedLinksAreNotProblems() {
        val r = OperationReport(
            FileOperation.Copy(listOf("/s/a"), "/t"), 1, 0, listOf(Failure("/s/a/link", FailureReason.SPECIAL_FILE_SKIPPED)),
            false, 0, listOf("/t/a"), emptyList(),
        )
        val s = OperationTexts.summary(r)
        assertFalse(s.isProblem)
        assertEquals("1 Objekt kopiert", s.headline)
        assertEquals("1 Verknüpfung oder Gerätedatei wurde bewusst nicht kopiert.", s.detail)
        val mixed = OperationTexts.summary(r.copy(failures = r.failures + Failure("/s/b", FailureReason.ACCESS_DENIED)))
        assertTrue(mixed.isProblem)
        assertTrue(mixed.detail!!.startsWith(FailureReason.ACCESS_DENIED.message))
    }
}
