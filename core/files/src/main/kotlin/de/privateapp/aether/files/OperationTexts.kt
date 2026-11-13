package de.privateapp.aether.files

/** Wie Vorgänge und ihre Ergebnisse in Oberfläche und Benachrichtigung heißen – an einer Stelle, getestet. */
object OperationTexts {

    /** „1 Objekt“, „12 Objekte“. */
    fun items(count: Int): String = if (count == 1) "1 Objekt" else "${formatCount(count)} Objekte"

    private fun quoted(path: String): String = "„${path.trimEnd('/').substringAfterLast('/')}“"

    private fun subject(paths: List<String>): String = if (paths.size == 1) quoted(paths.first()) else items(paths.size)

    private fun subjectOfTrash(items: List<TrashedItem>): String =
        if (items.size == 1) "„${items.first().name}“" else items(items.size)

    /** Titel eines laufenden Vorgangs. */
    fun title(op: FileOperation): String = when (op) {
        is FileOperation.Copy -> "${subject(op.sources)} kopieren"
        is FileOperation.Move -> "${subject(op.sources)} verschieben"
        is FileOperation.Trash -> "${subject(op.sources)} in den Papierkorb legen"
        is FileOperation.DeletePermanently -> "${subject(op.sources)} endgültig löschen"
        is FileOperation.Restore -> "${subjectOfTrash(op.items)} wiederherstellen"
        is FileOperation.DeleteFromTrash -> "${subjectOfTrash(op.items)} endgültig löschen"
        is FileOperation.Rename -> "${quoted(op.source)} umbenennen"
        is FileOperation.CreateFolder -> "Ordner „${op.name}“ erstellen"
        is FileOperation.Compress -> "„${archiveFileName(op.archiveName)}“ erstellen"
        is FileOperation.Extract -> "${quoted(op.archive)} entpacken"
        is FileOperation.WriteText -> "${quoted(op.path)} sichern"
    }

    /** Anzahl der Objekte, auf die sich ein Vorgang bezieht (oberste Ebene). */
    fun itemCount(op: FileOperation): Int = when (op) {
        is FileOperation.Copy -> op.sources.size
        is FileOperation.Move -> op.sources.size
        is FileOperation.Trash -> op.sources.size
        is FileOperation.DeletePermanently -> op.sources.size
        is FileOperation.Restore -> op.items.size
        is FileOperation.DeleteFromTrash -> op.items.size
        is FileOperation.Compress -> op.sources.size
        is FileOperation.Rename, is FileOperation.CreateFolder, is FileOperation.Extract, is FileOperation.WriteText -> 1
    }

    /** Kann der Vorgang länger dauern (dann läuft er als Vordergrunddienst mit Benachrichtigung)? */
    fun mayTakeLong(op: FileOperation): Boolean = when (op) {
        is FileOperation.Copy, is FileOperation.Move, is FileOperation.Compress, is FileOperation.Extract,
        is FileOperation.DeletePermanently, is FileOperation.DeleteFromTrash, is FileOperation.Restore -> true
        is FileOperation.Trash -> op.sources.size > 20
        is FileOperation.Rename, is FileOperation.CreateFolder, is FileOperation.WriteText -> false
    }

    /** „urlaub“ → „urlaub.zip“; vorhandene Endung bleibt. */
    fun archiveFileName(name: String): String = name.trim().let { if (it.endsWith(".zip", ignoreCase = true)) it else "$it.zip" }

    private fun pastTense(op: FileOperation): String = when (op) {
        is FileOperation.Copy -> "kopiert"
        is FileOperation.Move -> "verschoben"
        is FileOperation.Trash -> "in den Papierkorb gelegt"
        is FileOperation.DeletePermanently, is FileOperation.DeleteFromTrash -> "endgültig gelöscht"
        is FileOperation.Restore -> "wiederhergestellt"
        is FileOperation.Rename -> "umbenannt"
        is FileOperation.CreateFolder -> "erstellt"
        is FileOperation.Compress -> "komprimiert"
        is FileOperation.Extract -> "entpackt"
        is FileOperation.WriteText -> "gesichert"
    }

    /** Kurze Zusammenfassung: Überschrift und – wenn nötig – eine erklärende Zeile. */
    data class Summary(val headline: String, val detail: String?, val isProblem: Boolean)

    /**
     * Was tatsächlich passiert ist – nie „nichts geändert“, wenn sich ein Pfad geändert hat. Wurde ein Ordner nur
     * teilweise verschoben, steht ausdrücklich da, wie viel schon im Ziel und wie viel noch am Ursprungsort liegt.
     */
    fun summary(report: OperationReport): Summary {
        val op = report.operation
        val total = itemCount(op)
        val done = report.succeeded
        val problems = report.failures.filter { it.reason.isProblem }
        val specials = report.failures.size - problems.size
        val changed = done > 0 || report.partialFilesDone > 0 || report.createdPaths.isNotEmpty() || report.removedPaths.isNotEmpty()
        val splitMove = op is FileOperation.Move && report.partialFilesDone > 0
        val skipped = if (report.skipped > 0) "${formatCount(report.skipped)} übersprungen." else null
        val special = if (specials > 0) specialSentence(op, specials) else null

        if (report.cancelled) {
            val parts = ArrayList<String>()
            if (done > 0) parts += "${progressItems(done, total)} bereits ${pastTense(op)} – das bleibt so."
            partialSentence(op, report)?.let(parts::add)
            if (!changed) parts += "Es wurde nichts geändert."
            if (op is FileOperation.Copy || op is FileOperation.Move || op is FileOperation.Compress || op is FileOperation.Extract) {
                parts += "Unfertige Dateien wurden entfernt."
            }
            return Summary("${op.label} abgebrochen", parts.joinToString(" "), isProblem = splitMove)
        }
        if (problems.isNotEmpty()) {
            val first = problems.first()
            val reasons = problems.map { it.reason }.distinct()
            val detail = buildString {
                if (reasons.size == 1) append(first.reason.message) else append("${formatCount(problems.size)} Probleme, u. a.: ${first.reason.message}")
                append('.')
                if (done > 0) append(" ${progressItems(done, total)} ${pastTense(op)}.")
                partialSentence(op, report)?.let { append(' ').append(it) }
                special?.let { append(' ').append(it) }
                skipped?.let { append(' ').append(it) }
            }
            val headline = if (!changed && report.skipped == 0) "${op.label} nicht möglich" else "${op.label} unvollständig"
            return Summary(headline, detail, isProblem = true)
        }
        val headline = when (op) {
            is FileOperation.Rename -> "Umbenannt"
            is FileOperation.CreateFolder -> "Ordner „${op.name}“ erstellt"
            is FileOperation.Compress -> "„${archiveFileName(op.archiveName)}“ erstellt"
            is FileOperation.Extract -> "${quoted(op.archive)} entpackt"
            is FileOperation.WriteText -> "Gesichert"
            else -> if (done == 0) "Nichts ${pastTense(op)}" else "${items(done)} ${pastTense(op)}"
        }
        // Ohne Probleme bleibt nur dann etwas am Ursprungsort, wenn Teile übersprungen oder bewusst übergangen wurden.
        val split = if (report.partialFilesLeft > 0) partialSentence(op, report) else null
        val detail = listOfNotNull(split, special, skipped).joinToString(" ").ifEmpty { null }
        return Summary(headline, detail, isProblem = false)
    }

    /** „3 von 12 Objekten“, „0 von 1 Objekt“ (Fortschritt in Anzeige und Benachrichtigung). */
    fun progressItems(done: Int, total: Int): String =
        "${formatCount(done)} von ${formatCount(total)} ${if (total == 1) "Objekt" else "Objekten"}"

    /** „1 Datei“, „2 Dateien“. */
    fun files(count: Int): String = if (count == 1) "1 Datei" else "${formatCount(count)} Dateien"

    /** Satz über angefangene, nicht vollständig erledigte Einträge – oder `null`, wenn darin nichts fertig wurde. */
    private fun partialSentence(op: FileOperation, report: OperationReport): String? {
        val doneFiles = report.partialFilesDone
        if (doneFiles == 0) return null
        val verb = if (doneFiles == 1) "wurde" else "wurden"
        return when (op) {
            is FileOperation.Move -> {
                val lies = if (doneFiles == 1) "liegt" else "liegen"
                val left = report.partialFilesLeft
                val where = if (left > 0) "${files(doneFiles)} $lies bereits im Ziel, ${files(left)} noch am Ursprungsort." else "${files(doneFiles)} $lies bereits im Ziel."
                "$where Gelöscht wurde nur, was vollständig und geprüft im Ziel angekommen ist."
            }
            is FileOperation.Copy -> "${files(doneFiles)} $verb bereits vollständig kopiert."
            is FileOperation.DeletePermanently, is FileOperation.DeleteFromTrash -> "${files(doneFiles)} $verb bereits endgültig gelöscht."
            else -> "${files(doneFiles)} $verb bereits ${pastTense(op)}."
        }
    }

    private fun specialSentence(op: FileOperation, count: Int): String {
        val subject = if (count == 1) "1 Verknüpfung oder Gerätedatei wurde" else "${formatCount(count)} Verknüpfungen oder Gerätedateien wurden"
        val stays = if (op is FileOperation.Move) (if (count == 1) " und bleibt am Ursprungsort" else " und bleiben am Ursprungsort") else ""
        return "$subject bewusst nicht ${pastTense(op)}$stays."
    }

    private fun formatCount(n: Int): String = String.format(java.util.Locale.GERMANY, "%,d", n)
}
