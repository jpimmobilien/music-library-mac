package de.privateapp.aether.files

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.attribute.BasicFileAttributes
import java.security.MessageDigest
import java.util.Locale

/*
 * Zustand eines einzelnen Vorgangs der FileOperationEngine: Ergebnis (wird zum OperationReport), Fortschritt,
 * eigene Zwischendateien, Konfliktentscheidungen „für alle übernehmen“ und ein Namensverzeichnis der Zielordner.
 *
 * Ein Vorgang läuft nacheinander in einer Coroutine; dieser Zustand wird nie gleichzeitig verändert.
 */

/** Gemeinsame Einstellungen aller Vorgänge einer Engine. */
internal class EngineEnv(
    val layout: VolumeLayout,
    val trash: TrashStore,
    val journal: TempJournal?,
    val clock: () -> Long,
    val bufferSize: Int,
    val hooks: EngineHooks,
) {
    fun usableSpace(dir: File): Long = hooks.usableSpace?.invoke(dir) ?: dir.usableSpace

    /**
     * Darf zwischen den Speichern umbenannt werden? Nein, wenn die Speicher verschieden sind. Ist ein Speicher
     * unbekannt, wird es versucht – das System meldet dann gegebenenfalls „anderes Dateisystem“.
     */
    fun canRename(from: File, toDir: File): Boolean {
        hooks.canRename?.let { return it(from.path, toDir.path) }
        val a = layout.volumeRootOf(from.path) ?: return true
        val b = layout.volumeRootOf(toDir.path) ?: return true
        return Fs.normalize(a) == Fs.normalize(b)
    }
}

/** Eingriffspunkte für Tests (Fehler, Abbruch, Speicherplatz, Datenträgerwechsel simulieren). */
internal class EngineHooks {
    /** Ersetzt [EngineEnv.canRename]. */
    var canRename: ((from: String, toDir: String) -> Boolean)? = null

    /** Ersetzt `File.usableSpace`. */
    var usableSpace: ((File) -> Long)? = null

    /** Vor dem Umbenennen beim Verschieben; darf eine IOException werfen (z. B. „anderes Dateisystem“). */
    var beforeMoveRename: ((from: File, to: File) -> Unit)? = null

    /** Nach jedem geschriebenen Block; darf eine IOException werfen (Schreibfehler) oder abbrechen. */
    var onChunkWritten: ((target: File, writtenBytes: Long) -> Unit)? = null

    /** Nachdem eine Zwischendatei vollständig geschrieben ist, vor Prüfung und Umbenennen (z. B. „beschädigen“). */
    var afterTempWritten: ((File) -> Unit)? = null
}

/** Einträge und Bytes eines Baums. */
internal data class Totals(val items: Int, val bytes: Long)

/** Ergebnis für einen Eintrag. */
internal sealed interface Outcome {
    /** Am Ziel liegt jetzt [path]. [sourceGone] = die Quelle existiert nicht mehr (verschoben). */
    data class Placed(val path: String, val sourceGone: Boolean) : Outcome

    data object Skipped : Outcome

    data object Failed : Outcome
}

/** Welche Entscheidungen bei einem Konflikt möglich sind. */
internal enum class ConflictRules {
    /** Kopieren/Verschieben: Dateien Ersetzen/Beide/Überspringen, Ordner Zusammenführen/Beide/Überspringen. */
    TRANSFER {
        override fun normalize(choice: ConflictChoice, sourceIsDir: Boolean, existingIsDir: Boolean): ConflictChoice =
            when {
                sourceIsDir && existingIsDir -> if (choice == ConflictChoice.REPLACE) ConflictChoice.MERGE else choice
                !sourceIsDir && !existingIsDir -> if (choice == ConflictChoice.MERGE) ConflictChoice.KEEP_BOTH else choice
                // Datei gegen Ordner: weder ersetzen (würde einen ganzen Ordner löschen) noch zusammenführen.
                else -> if (choice == ConflictChoice.SKIP) ConflictChoice.SKIP else ConflictChoice.KEEP_BOTH
            }
    },

    /** Umbenennen: nur Dateien dürfen ersetzt werden; Zusammenführen gibt es nicht. */
    RENAME {
        override fun normalize(choice: ConflictChoice, sourceIsDir: Boolean, existingIsDir: Boolean): ConflictChoice =
            when (choice) {
                ConflictChoice.KEEP_BOTH -> ConflictChoice.KEEP_BOTH
                ConflictChoice.REPLACE -> if (!sourceIsDir && !existingIsDir) ConflictChoice.REPLACE else ConflictChoice.SKIP
                ConflictChoice.SKIP, ConflictChoice.MERGE -> ConflictChoice.SKIP
            }
    };

    abstract fun normalize(choice: ConflictChoice, sourceIsDir: Boolean, existingIsDir: Boolean): ConflictChoice
}

/**
 * Namen je Zielordner ohne Rücksicht auf Groß-/Kleinschreibung (wie der gemeinsame Speicher von Android). Jeder Ordner
 * wird höchstens einmal gelesen – auch beim Kopieren tausender Dateien in einen vollen Ordner.
 *
 * Auf Speichern, die Groß-/Kleinschreibung unterscheiden (manche USB-Sticks), können „A.txt“ und „a.txt“ nebeneinander
 * liegen. Deshalb gewinnt immer der exakt gleiche Name; nur wenn es ihn nicht gibt, zählt ein anders geschriebener.
 */
internal class NameIndex {
    private val dirs = HashMap<String, HashMap<String, MutableList<String>>>()

    /** Vorhandener Name in [dir]: exakt [name], sonst einer, der sich nur in der Schreibweise unterscheidet, sonst `null`. */
    fun lookup(dir: File, name: String): String? {
        val candidates = namesOf(dir)[key(name)] ?: return null
        return if (name in candidates) name else candidates.firstOrNull()
    }

    fun add(dir: File, name: String) {
        val candidates = namesOf(dir).getOrPut(key(name)) { ArrayList(1) }
        if (name !in candidates) candidates += name
    }

    fun remove(dir: File?, name: String) {
        if (dir == null) return
        val map = dirs[dir.path] ?: return
        val candidates = map[key(name)] ?: return
        candidates.remove(name)
        if (candidates.isEmpty()) map.remove(key(name))
    }

    /** Nach Überraschungen (Name erschien unerwartet) neu einlesen. */
    fun forget(dir: File) {
        dirs.remove(dir.path)
    }

    private fun namesOf(dir: File): HashMap<String, MutableList<String>> = dirs.getOrPut(dir.path) {
        val map = HashMap<String, MutableList<String>>()
        try {
            dir.list()?.forEach { name -> map.getOrPut(key(name)) { ArrayList(1) }.add(name) }
        } catch (e: SecurityException) {
            // leer – Fehler zeigt sich beim Schreiben
        }
        map
    }

    private fun key(name: String) = name.lowercase(Locale.ROOT)
}

internal class OperationRun(
    val operation: FileOperation,
    private val resolver: ConflictResolver,
    private val onProgress: (OperationProgress) -> Unit,
    val env: EngineEnv,
) {
    var succeeded = 0
    var skipped = 0
    val failures = ArrayList<Failure>()
    var cancelled = false
    var finished = false
    var bytesProcessed = 0L
    private val created = LinkedHashSet<String>()
    private val removed = LinkedHashSet<String>()

    var phase = OperationPhase.PREPARING
        private set
    var totalItems = 0
    var totalBytes = 0L
    var completedItems = 0
        private set
    var completedBytes = 0L
        private set
    var currentName: String? = null
    private var lastEmit: Long? = null

    /** Gesetzt, wenn das Ziel voll oder schreibgeschützt ist: Weitere Einträge werden dann nicht mehr versucht. */
    var abortReason: FailureReason? = null
        private set

    private val temps = LinkedHashSet<File>()
    private var fileChoiceForAll: ConflictChoice? = null
    private var folderChoiceForAll: ConflictChoice? = null
    val names = NameIndex()

    // ---- Ergebnis ----------------------------------------------------------------------------------------------

    fun fail(path: String, reason: FailureReason, detail: String? = null) {
        failures += Failure(path, reason, detail)
        if (reason.isProblem) problems++
    }

    /** Anzahl echter Probleme bisher (ohne bewusst übergangene Verknüpfungen/Gerätedateien). */
    var problems = 0
        private set

    /** Neuer Papierkorb-Eintrag (für „Widerrufen“). */
    fun trashed(item: TrashedItem) {
        trashedItems += item
        created(item.storedPath)
    }

    private val trashedItems = ArrayList<TrashedItem>()

    /** Fehler aus einer Ausnahme. „Kein Platz“ und „schreibgeschützt“ beenden den Vorgang (betrifft alles Weitere). */
    fun fail(path: String, error: Throwable, detail: String? = error.message) {
        val reason = IoErrors.classify(error)
        fail(path, reason, detail)
        if (reason == FailureReason.NO_SPACE || reason == FailureReason.READ_ONLY) abortReason = reason
    }

    /** Wenn der Vorgang beendet wurde: [path] als „nicht ausgeführt“ melden und `true` liefern. */
    fun skipBecauseAborted(path: String): Boolean {
        val reason = abortReason ?: return false
        fail(path, reason, DETAIL_NOT_ATTEMPTED)
        return true
    }

    fun created(path: String) {
        created += path
    }

    fun removed(path: String) {
        removed += path
    }

    fun report() = OperationReport(
        operation = operation,
        succeeded = succeeded,
        skipped = skipped,
        failures = failures.toList(),
        cancelled = cancelled,
        bytesProcessed = bytesProcessed,
        createdPaths = created.toList(),
        removedPaths = removed.toList(),
        partialFilesDone = partialFilesDone,
        partialFilesLeft = partialFilesLeft,
        trashedItems = trashedItems.toList(),
    )

    // ---- Einträge der obersten Ebene -----------------------------------------------------------------------------
    //
    // Während ein Eintrag (z. B. ein Ordner) bearbeitet wird, merkt sich der Lauf jede einzelne Änderung darin. Wird
    // der Eintrag vollständig erledigt, genügt dem Medienindex sein oberster Pfad – die Einzelpfade werden verworfen.
    // Bleibt er unvollständig (Abbruch, Fehler, übersprungene Teile), kommen alle Einzelpfade in den Bericht, damit
    // nichts Verschobenes, Kopiertes oder Gelöschtes verschwiegen wird.

    private class ItemScope(val sourceLeft: File?) {
        val created = ArrayList<String>()
        val removed = ArrayList<String>()
        val wholeDirectories = ArrayList<File>()
        var files = 0
    }

    private var item: ItemScope? = null
    private var partialFilesDone = 0
    private var partialFilesLeft = 0

    /** Beginn eines Eintrags der obersten Ebene. [sourceLeft] = Quelle, deren Rest gezählt wird (nur Verschieben). */
    fun beginItem(sourceLeft: File? = null) {
        endItem(complete = false)
        item = ItemScope(sourceLeft)
    }

    fun childCreated(path: String) {
        item?.created?.add(path) ?: created(path)
    }

    fun childRemoved(path: String) {
        item?.removed?.add(path) ?: removed(path)
    }

    /** Eine Datei wurde fertig bearbeitet (kopiert, verschoben, gelöscht). */
    fun childFileDone() {
        item?.let { it.files++ }
    }

    /** Ein ganzer Ordner wurde in einem Schritt umbenannt (seine Dateien werden nur bei Bedarf gezählt). */
    fun childDirectoryMovedWhole(dir: File) {
        item?.wholeDirectories?.add(dir)
    }

    /**
     * Ende eines Eintrags. [complete] = vollständig erledigt: Der Aufrufer meldet nur den obersten Pfad. Sonst kommen
     * alle Einzeländerungen in den Bericht, und es wird gezählt, wie viele Dateien schon fertig sind bzw. (beim
     * Verschieben) noch am Ursprungsort liegen. Blockierend – nur auf dem IO-Thread aufrufen.
     */
    fun endItem(complete: Boolean) {
        val scope = item ?: return
        item = null
        if (complete) return
        scope.created.forEach { created(it) }
        scope.removed.forEach { removed(it) }
        val done = scope.files + scope.wholeDirectories.sumOf { Fs.countFilesBlocking(it) }
        if (done == 0) return // nichts angefangen: der Eintrag liegt unverändert am Ursprungsort
        partialFilesDone += done
        scope.sourceLeft?.let { partialFilesLeft += Fs.countFilesBlocking(it) }
    }

    // ---- Fortschritt -------------------------------------------------------------------------------------------

    /** Phasenwechsel werden sofort gemeldet ([force]); Wechsel innerhalb eines Eintrags (Prüfen) gedrosselt. */
    fun enterPhase(next: OperationPhase, force: Boolean = true) {
        if (phase == next) return
        phase = next
        emit(force)
    }

    fun addBytes(n: Long) {
        completedBytes += n
        emit(force = false)
    }

    fun addItems(n: Int, force: Boolean = false) {
        completedItems += n
        emit(force)
    }

    /** Nach einem Eintrag der obersten Ebene: Stand genau auf „erledigt“ setzen (nie rückwärts). */
    fun snapTo(items: Int, bytes: Long) {
        completedItems = maxOf(completedItems, items)
        completedBytes = maxOf(completedBytes, bytes)
        emit(force = true)
    }

    fun emit(force: Boolean) {
        val now = env.clock()
        val last = lastEmit
        if (!force && last != null && now - last < PROGRESS_INTERVAL_MS) return
        lastEmit = now
        if (progressBroken) return
        try {
            onProgress(OperationProgress(phase, totalItems, completedItems, totalBytes, completedBytes, currentName))
        } catch (e: RuntimeException) {
            // Ein Fehler in der Anzeige darf keinen Dateivorgang mittendrin abbrechen – keine weiteren Meldungen.
            progressBroken = true
        }
    }

    private var progressBroken = false

    // ---- Zwischendateien ---------------------------------------------------------------------------------------

    /** Vor dem Anlegen eintragen – so wird sie auch bei Abbruch oder Absturz wieder entfernt. */
    fun registerTemp(file: File) {
        temps += file
        env.journal?.add(file.path)
    }

    /** Zwischendatei existiert nicht mehr (umbenannt oder gelöscht). */
    fun releaseTemp(file: File) {
        temps -= file
        env.journal?.remove(file.path)
    }

    fun isTemp(file: File): Boolean = file in temps

    /** Zwischendatei löschen und austragen. Lässt sie sich nicht löschen, bleibt sie im Journal (nächster Start). */
    fun discardTemp(file: File) {
        if (file in temps) {
            temps -= file
            if (Fs.deleteRecursively(file)) env.journal?.remove(file.path)
        }
    }

    /**
     * [temp] ist vollständig und ersetzt gleich [target] auf dem Ausweichweg (löschen + umbenennen). Ab jetzt ist sie
     * keine Wegwerfdatei mehr: Das Aufräumen löscht sie nicht, das Journal vollendet den Austausch nach einem Absturz.
     */
    fun commitTemp(temp: File, target: File) {
        env.journal?.commit(temp.path, target.path)
        temps -= temp
    }

    /** Abschluss – auch nach Abbruch: offenen Eintrag als unvollständig abrechnen, eigene Zwischendateien entfernen. */
    fun cleanup() {
        enterPhase(OperationPhase.CLEANING_UP)
        endItem(complete = false)
        for (temp in temps.toList()) {
            // Lässt sich eine Zwischendatei nicht löschen (z. B. SD-Karte entnommen), bleibt sie im Journal.
            if (Fs.deleteRecursively(temp)) env.journal?.remove(temp.path)
        }
        temps.clear()
    }

    // ---- Konflikte ---------------------------------------------------------------------------------------------

    /** Entscheidung für einen Konflikt; „für alle“ gilt getrennt für Dateien und für Ordner. */
    suspend fun decide(source: FileEntry, existing: FileEntry, rules: ConflictRules): ConflictChoice {
        val forFolders = source.isDirectory
        val remembered = if (forFolders) folderChoiceForAll else fileChoiceForAll
        val raw = remembered ?: resolver.resolve(Conflict(source, existing)).let { resolution ->
            if (resolution.applyToAll) {
                if (forFolders) folderChoiceForAll = resolution.choice else fileChoiceForAll = resolution.choice
            }
            resolution.choice
        }
        return rules.normalize(raw, source.isDirectory, existing.isDirectory)
    }

    /** Konflikt für [src] in [destDir] (ohne Groß-/Kleinschreibung) entscheiden; `null` = kein Konflikt. */
    suspend fun conflictChoice(src: File, destDir: File, rules: ConflictRules): Pair<ConflictChoice, File>? {
        val existingName = names.lookup(destDir, src.name) ?: return null
        val existing = File(destDir, existingName)
        val existingEntry = DirectoryReader.entryOf(existing)
        if (existingEntry == null) {
            names.forget(destDir)
            return null
        }
        val sourceEntry = DirectoryReader.entryOf(src) ?: return null
        return decide(sourceEntry, existingEntry, rules) to existing
    }

    fun uniqueIn(dir: File, desired: String, isDirectory: Boolean): String =
        FileNames.uniqueName(desired, isDirectory) { names.lookup(dir, it) != null }

    // ---- Gemeinsame Bausteine ----------------------------------------------------------------------------------

    /** Zielordner prüfen: muss existieren und ein Ordner sein. */
    fun targetDirectory(path: String): File? {
        val dir = File(Fs.normalize(path))
        if (dir.isDirectory) return dir
        if (Fs.exists(dir)) fail(dir.path, FailureReason.IO_ERROR, DETAIL_NOT_A_FOLDER) else fail(dir.path, FailureReason.NOT_FOUND)
        return null
    }

    /** Freien Platz für [needed] Byte (plus Reserve) prüfen; bei Mangel einmal melden und `false`. */
    fun hasSpace(target: File, needed: Long): Boolean {
        if (needed <= 0) return true
        val free = env.usableSpace(target)
        if (needed + Fs.SPACE_RESERVE_BYTES <= free) return true
        fail(target.path, FailureReason.NO_SPACE, "Benötigt: $needed Byte, verfügbar: $free Byte")
        abortReason = FailureReason.NO_SPACE
        return false
    }

    /** Einträge und Bytes unter [file] (ohne Verknüpfungen zu folgen, ohne Dateien von ORBIT). Abbrechbar. */
    suspend fun scan(file: File, attrs: BasicFileAttributes): Totals {
        if (!attrs.isDirectory) return Totals(1, if (attrs.isRegularFile) attrs.size() else 0L)
        var items = 1
        var bytes = 0L
        val pending = ArrayDeque<File>()
        pending.addLast(file)
        while (pending.isNotEmpty()) {
            currentCoroutineContext().ensureActive()
            val dir = pending.removeLast()
            val children = try {
                dir.listFiles()
            } catch (e: SecurityException) {
                null
            } ?: continue
            for (child in children) {
                if (FileNames.isReserved(child.name)) continue
                val childAttrs = Fs.attrs(child) ?: continue
                items++
                if (childAttrs.isDirectory) pending.addLast(child) else if (childAttrs.isRegularFile) bytes += childAttrs.size()
            }
        }
        return Totals(items, bytes)
    }

    /**
     * Kopiert [input] nach [out] in Blöcken: prüft vor jedem Block auf Abbruch, meldet Fortschritt, rechnet optional
     * die Prüfsumme mit. Mehr als [limit] Byte → [SizeLimitExceededException]. Liefert die geschriebenen Bytes.
     */
    suspend fun pump(
        input: InputStream,
        out: OutputStream,
        target: File,
        digest: MessageDigest? = null,
        limit: Long = Long.MAX_VALUE,
    ): Long {
        val buffer = ByteArray(env.bufferSize)
        var written = 0L
        while (true) {
            currentCoroutineContext().ensureActive()
            val n = input.read(buffer)
            if (n < 0) break
            if (n == 0) continue
            if (written + n > limit) throw SizeLimitExceededException()
            out.write(buffer, 0, n)
            digest?.update(buffer, 0, n)
            written += n
            addBytes(n.toLong())
            env.hooks.onChunkWritten?.invoke(target, written)
        }
        return written
    }

    /** SHA-256 einer Datei, abbrechbar. */
    suspend fun sha256(file: File): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(env.bufferSize)
        java.io.FileInputStream(file).use { input ->
            while (true) {
                currentCoroutineContext().ensureActive()
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest()
    }

    companion object {
        const val PROGRESS_INTERVAL_MS = 100L
        const val DETAIL_LINK = "Verknüpfung (symbolischer Link)"
        const val DETAIL_SPECIAL = "Gerätedatei, Pipe oder Socket"
        const val DETAIL_NOT_ATTEMPTED = "Nicht ausgeführt, weil der Vorgang wegen eines früheren Fehlers endete"
        const val DETAIL_NOT_A_FOLDER = "Ziel ist kein Ordner"
    }
}

/** Ein Eintrag ist größer als angegeben (beschädigtes oder manipuliertes Archiv). */
internal class SizeLimitExceededException : IOException("Mehr Daten als angegeben")
