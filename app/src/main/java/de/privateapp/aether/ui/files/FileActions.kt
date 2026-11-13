package de.privateapp.aether.ui.files

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.AppGraph
import de.privateapp.aether.files.ConflictChoice
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.files.FileOperation
import de.privateapp.aether.files.OperationReport
import de.privateapp.aether.files.OperationTexts
import de.privateapp.aether.files.Resolution
import de.privateapp.aether.files.TrashedItem
import de.privateapp.aether.navigation.AppNavigator
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.platform.storage.LaunchResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Was die Dateiaktionen gerade anzeigen (höchstens eins zugleich). */
sealed interface FileDialog {
    /** Aktionsblatt zu einem oder mehreren Objekten. */
    data class Actions(val entries: List<FileEntry>) : FileDialog
    data class Rename(val entry: FileEntry) : FileDialog
    /** [suggestedName] = freier Name („Neuer Ordner 2“), vorab außerhalb des Hauptthreads ermittelt. */
    data class NewFolder(val parentDir: String, val suggestedName: String) : FileDialog
    data class ConfirmDelete(val entries: List<FileEntry>) : FileDialog
    data class ConfirmDeleteFromTrash(val items: List<TrashedItem>, val emptiesTrash: Boolean) : FileDialog
    data class Compress(val entries: List<FileEntry>, val targetDir: String, val suggestedName: String) : FileDialog
    data class Pick(val purpose: PickPurpose, val entries: List<FileEntry>, val startDir: String) : FileDialog
    data class Info(val entry: FileEntry) : FileDialog
    data class InstallPermission(val entry: FileEntry) : FileDialog
    data class Failures(val report: OperationReport) : FileDialog
}

enum class PickPurpose(val title: String, val confirm: String) {
    COPY("Kopieren nach", "Hierher kopieren"),
    MOVE("Verschieben nach", "Hierher verschieben"),
    EXTRACT("Entpacken nach", "Hierher entpacken"),
}

/** Kurze Rückmeldung nach einem Vorgang (unten über der Navigation). */
data class Banner(
    val id: Long,
    val headline: String,
    val detail: String?,
    val isProblem: Boolean,
    /** „Widerrufen“ nach dem Löschen in den Papierkorb. */
    val undo: (() -> Unit)? = null,
    /** „Details“ bei Problemen. */
    val report: OperationReport? = null,
)

/**
 * Zustand der Dateiaktionen für die ganze Aktivität (übersteht Drehen): offener Dialog, Rückmeldung. Die Vorgänge
 * selbst führt der [de.privateapp.aether.operations.OperationManager] aus.
 */
class FileActionsViewModel(val graph: AppGraph) : ViewModel() {
    var dialog: FileDialog? by mutableStateOf(null)
        private set
    var banner: Banner? by mutableStateOf(null)
        private set
    private var bannerJob: Job? = null
    private var bannerIds = 0L

    /** Abgeschlossene Vorgänge – Bildschirme laden daraufhin neu und heben die Auswahl auf. */
    val finished: SharedFlow<OperationReport> get() = graph.operations.finished

    init {
        viewModelScope.launch {
            graph.operations.finished.collect { report -> showBanner(report) }
        }
    }

    fun show(d: FileDialog) {
        dialog = d
    }

    fun dismissDialog() {
        dialog = null
    }

    /** Ermittelt im Hintergrund einen freien Namen in [dir] und zeigt dann den Dialog (kein Dateizugriff im Hauptthread). */
    fun showWithFreeName(dir: String, desired: String, isDirectory: Boolean, make: (String) -> FileDialog) {
        viewModelScope.launch {
            val name = withContext(Dispatchers.IO) {
                val taken = java.io.File(dir).list()?.map { it.lowercase() }?.toSet().orEmpty()
                de.privateapp.aether.files.FileNames.uniqueName(desired, isDirectory) { it.lowercase() in taken }
            }
            dialog = make(name)
        }
    }

    fun dismissBanner() {
        bannerJob?.cancel()
        banner = null
    }

    fun submit(op: FileOperation, autoResolution: Resolution? = null, title: String? = null) {
        dialog = null
        graph.operations.submit(op, autoResolution, title)
    }

    fun recordOpened(entry: FileEntry) {
        if (entry.isDirectory) return
        viewModelScope.launch { graph.settings.addRecentFile(entry.path) }
    }

    fun toggleFavorite(path: String) {
        viewModelScope.launch { graph.settings.toggleFavorite(path) }
    }

    fun note(headline: String, detail: String? = null, isProblem: Boolean = true) {
        post(Banner(++bannerIds, headline, detail, isProblem))
    }

    private fun showBanner(report: OperationReport) {
        val summary = OperationTexts.summary(report)
        // Nach einem gelungenen Löschen in den Papierkorb: rückgängig machen wie auf dem Mac.
        val undo: (() -> Unit)? = if (report.operation is FileOperation.Trash && report.succeeded > 0 && !report.cancelled) {
            { undoTrash(report) }
        } else {
            null
        }
        // Schnelle, unauffällige Vorgänge (Umbenennen, Ordner erstellen, Sichern) brauchen nur bei Problemen eine Meldung.
        val quiet = !summary.isProblem && !report.cancelled &&
            report.operation.let { it is FileOperation.Rename || it is FileOperation.CreateFolder || it is FileOperation.WriteText }
        if (quiet) return
        // „Details“ nur, wenn es echte Probleme gibt (bewusst übersprungene Verknüpfungen zählen nicht).
        post(Banner(++bannerIds, summary.headline, summary.detail, summary.isProblem, undo, report.takeIf { r -> r.failures.any { it.reason.isProblem } }))
    }

    private fun post(b: Banner) {
        bannerJob?.cancel()
        banner = b
        if (!b.isProblem) {
            bannerJob = viewModelScope.launch {
                delay(bannerTimeout(withAction = b.undo != null))
                if (banner?.id == b.id) banner = null
            }
        }
    }

    /**
     * Anzeigedauer einer Rückmeldung: 4 s (mit „Widerrufen“ 6 s) – oder länger, wenn in den Bedienungshilfen „Zeit zum
     * Reagieren“ eingestellt ist (Android liefert dafür die empfohlene Dauer).
     */
    private fun bannerTimeout(withAction: Boolean): Long {
        val base = if (withAction) 6_000 else 4_000
        val am = graph.context.getSystemService(android.view.accessibility.AccessibilityManager::class.java) ?: return base.toLong()
        val flags = android.view.accessibility.AccessibilityManager.FLAG_CONTENT_TEXT or
            (if (withAction) android.view.accessibility.AccessibilityManager.FLAG_CONTENT_CONTROLS else 0)
        return am.getRecommendedTimeoutMillis(base, flags).toLong()
    }

    private fun undoTrash(report: OperationReport) {
        dismissBanner()
        viewModelScope.launch {
            // Nur, was noch im Papierkorb liegt (es könnte inzwischen endgültig gelöscht worden sein).
            val stored = report.trashedItems.map { it.storedPath }.toSet()
            val items = withContext(Dispatchers.IO) {
                graph.trash.list(graph.volumeRoots.list().map { it.path })
            }.filter { it.storedPath in stored }
            if (items.isEmpty()) {
                note("Widerrufen nicht möglich", "Die Objekte sind nicht mehr im Papierkorb.")
            } else {
                graph.operations.submit(FileOperation.Restore(items))
            }
        }
    }
}

/**
 * Dateiaktionen für Bildschirme (über [LocalFileActions]): Öffnen, Teilen, Umbenennen, Kopieren, Verschieben, Löschen,
 * Komprimieren, Entpacken, Informationen. Zerstörerisches fragt nach oder ist widerrufbar; alles Weitere erledigt
 * der [FileActionsHost] (Dialoge, Ziel-Auswahl, Fortschritt, Rückmeldung).
 */
@Stable
class FileActions internal constructor(
    val vm: FileActionsViewModel,
    private val navigator: AppNavigator,
    private val activityContext: Context,
) {
    private val graph get() = vm.graph

    /** Öffnen wie in „Dateien“ von Apple: Ordner öffnen, Bilder/Text/PDF/ZIP als Schnellansicht, sonst passende App. */
    fun open(entry: FileEntry) {
        when {
            entry.isDirectory -> navigator.push(Route.Folder(entry.path))
            entry.kind == FileKind.APK -> install(entry)
            previewable(entry) -> {
                vm.recordOpened(entry)
                navigator.push(Route.Preview(entry.path))
            }
            else -> {
                vm.recordOpened(entry)
                when (graph.fileIntents.launch(activityContext, graph.fileIntents.view(entry))) {
                    LaunchResult.STARTED -> Unit
                    // Keine App dafür installiert: Schnellansicht mit Informationen und „Öffnen mit …“.
                    else -> navigator.push(Route.Preview(entry.path))
                }
            }
        }
    }

    /** In einer anderen App öffnen (Auswahl aller passenden Apps). */
    fun openWith(entry: FileEntry) {
        vm.dismissDialog()
        vm.recordOpened(entry)
        report(graph.fileIntents.launch(activityContext, graph.fileIntents.openWith(entry)))
    }

    fun share(entries: List<FileEntry>) {
        vm.dismissDialog()
        val files = entries.filter { !it.isDirectory }
        if (files.isEmpty()) {
            vm.note("Ordner können nicht geteilt werden", "Komprimiere den Ordner zuerst zu einem ZIP-Archiv und teile dieses.")
            return
        }
        report(graph.fileIntents.launch(activityContext, graph.fileIntents.share(files)))
        if (files.size < entries.size) {
            vm.note("Nur Dateien geteilt", "${entries.size - files.size} Ordner wurde(n) ausgelassen – Ordner lassen sich nur als ZIP-Archiv teilen.", isProblem = false)
        }
    }

    fun install(entry: FileEntry) {
        vm.dismissDialog()
        if (!graph.fileIntents.canRequestInstalls()) {
            vm.show(FileDialog.InstallPermission(entry))
            return
        }
        report(graph.fileIntents.launch(activityContext, graph.fileIntents.install(entry)))
    }

    fun openInstallSettings() {
        vm.dismissDialog()
        report(graph.fileIntents.launch(activityContext, graph.fileIntents.unknownSourcesSettings()))
    }

    fun showActions(entries: List<FileEntry>) {
        if (entries.isNotEmpty()) vm.show(FileDialog.Actions(entries))
    }

    fun info(entry: FileEntry) = vm.show(FileDialog.Info(entry))

    fun rename(entry: FileEntry) = vm.show(FileDialog.Rename(entry))

    fun newFolder(parentDir: String) = vm.showWithFreeName(parentDir, "Neuer Ordner", isDirectory = true) { name ->
        FileDialog.NewFolder(parentDir, name)
    }

    fun copy(entries: List<FileEntry>) = pick(PickPurpose.COPY, entries)

    fun move(entries: List<FileEntry>) = pick(PickPurpose.MOVE, entries)

    /** Kopie im selben Ordner („Foto 2.jpg“) – ohne Rückfrage. */
    fun duplicate(entries: List<FileEntry>) {
        val byParent = entries.groupBy { it.parentPath }
        for ((parent, group) in byParent) {
            val op = FileOperation.Copy(group.map { it.path }, parent)
            val title = if (group.size == 1) "„${group.first().name}“ duplizieren" else "${OperationTexts.items(group.size)} duplizieren"
            vm.submit(op, Resolution(ConflictChoice.KEEP_BOTH, applyToAll = true), title)
        }
    }

    /** In den Papierkorb – sofort, mit „Widerrufen“ in der Rückmeldung (wie auf dem Mac, ohne Rückfrage). */
    fun trash(entries: List<FileEntry>) {
        if (entries.isEmpty()) return
        vm.submit(FileOperation.Trash(entries.map { it.path }))
    }

    /** Endgültig löschen – nur nach ausdrücklicher Bestätigung. */
    fun deletePermanently(entries: List<FileEntry>) {
        if (entries.isNotEmpty()) vm.show(FileDialog.ConfirmDelete(entries))
    }

    fun compress(entries: List<FileEntry>) {
        if (entries.isEmpty()) return
        val parent = entries.first().parentPath
        val suggested = if (entries.size == 1) entries.first().name.substringBeforeLast('.').ifEmpty { entries.first().name } else "Archiv"
        vm.showWithFreeName(parent, "$suggested.zip", isDirectory = false) { name ->
            FileDialog.Compress(entries, parent, name.removeSuffix(".zip"))
        }
    }

    /** Entpacken in einen neuen Ordner neben dem Archiv (wie das Archivprogramm von macOS). */
    fun extractHere(archive: FileEntry) {
        vm.submit(FileOperation.Extract(archive.path, archive.parentPath))
    }

    fun extractTo(archive: FileEntry) = pick(PickPurpose.EXTRACT, listOf(archive))

    fun restore(items: List<TrashedItem>) {
        if (items.isNotEmpty()) vm.submit(FileOperation.Restore(items))
    }

    fun deleteFromTrash(items: List<TrashedItem>, emptiesTrash: Boolean = false) {
        if (items.isNotEmpty()) vm.show(FileDialog.ConfirmDeleteFromTrash(items, emptiesTrash))
    }

    fun toggleFavorite(path: String) {
        vm.dismissDialog()
        vm.toggleFavorite(path)
    }

    /** Text sicher speichern (erst vollständig schreiben, dann ersetzen); scheitert, wenn die Datei inzwischen geändert wurde. */
    fun saveText(entry: FileEntry, text: String, expectedModifiedMillis: Long?) {
        vm.submit(FileOperation.WriteText(entry.path, text, expectedModifiedMillis))
    }

    private fun pick(purpose: PickPurpose, entries: List<FileEntry>) {
        if (entries.isEmpty()) return
        vm.show(FileDialog.Pick(purpose, entries, entries.first().parentPath))
    }

    private fun report(result: LaunchResult) {
        result.message?.let { vm.note(it) }
    }

    companion object {
        /** Pfade, auf die ein Vorgang wirkt (für „Auswahl beenden, sobald etwas damit geschieht“). */
        fun sourcesOf(op: FileOperation): List<String> = when (op) {
            is FileOperation.Copy -> op.sources
            is FileOperation.Move -> op.sources
            is FileOperation.Trash -> op.sources
            is FileOperation.DeletePermanently -> op.sources
            is FileOperation.Compress -> op.sources
            is FileOperation.Restore -> op.items.map { it.storedPath }
            is FileOperation.DeleteFromTrash -> op.items.map { it.storedPath }
            is FileOperation.Rename -> listOf(op.source)
            is FileOperation.Extract -> listOf(op.archive)
            is FileOperation.CreateFolder, is FileOperation.WriteText -> emptyList()
        }

        /** Was die Schnellansicht von ORBIT selbst darstellen kann. */
        fun previewable(entry: FileEntry): Boolean = when (entry.kind) {
            FileKind.IMAGE, FileKind.TEXT, FileKind.PDF -> true
            FileKind.ARCHIVE -> entry.extension == "zip"
            else -> false
        }
    }
}

/**
 * Beendet die Auswahl, sobald ein Vorgang mit ausgewählten Objekten beginnt (z. B. nach „Hierher kopieren“) – wie bei
 * Apple. Andere, gleichzeitig laufende Vorgänge lassen die Auswahl in Ruhe.
 */
@Composable
fun EndSelectionOnOperation(graph: AppGraph, selection: Set<String>?, endSelection: () -> Unit) {
    val current by androidx.compose.runtime.rememberUpdatedState(selection)
    androidx.compose.runtime.LaunchedEffect(graph) {
        var known = graph.operations.jobs.value.map { it.id }.toSet()
        graph.operations.jobs.collect { jobs ->
            val fresh = jobs.filter { it.id !in known }
            known = jobs.map { it.id }.toSet()
            val sel = current ?: return@collect
            if (fresh.any { job -> FileActions.sourcesOf(job.operation).any { it in sel } }) endSelection()
        }
    }
}

val LocalFileActions = staticCompositionLocalOf<FileActions> { error("FileActions nicht bereitgestellt") }

/** Kurzform für Bildschirme. */
val fileActions: FileActions
    @Composable get() = LocalFileActions.current
