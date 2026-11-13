package de.privateapp.aether.files

/*
 * Datenmodell der Dateiverwaltung. Pfade sind absolute Pfade als Text (z. B. „/storage/emulated/0/Download/a.pdf“),
 * damit sie unverändert zwischen Modulen, Navigation und gespeichertem Zustand wandern können.
 */

/** Art einer Datei – bestimmt Symbol, Kategorie und wie sie geöffnet wird. */
enum class FileKind(val label: String) {
    FOLDER("Ordner"),
    IMAGE("Bild"),
    VIDEO("Video"),
    AUDIO("Audio"),
    DOCUMENT("Dokument"),
    PDF("PDF-Dokument"),
    TEXT("Textdatei"),
    ARCHIVE("Archiv"),
    APK("App-Paket"),
    OTHER("Datei"),
}

/** Eine Datei oder ein Ordner, so wie das Dateisystem sie meldet. */
data class FileEntry(
    val path: String,
    val name: String,
    val isDirectory: Boolean,
    /** Größe in Byte; bei Ordnern 0 (die Gesamtgröße liefert [FolderStats]). */
    val sizeBytes: Long,
    val modifiedMillis: Long,
    /** Name beginnt mit „.“ (wie unter Android/Linux üblich). */
    val isHidden: Boolean,
    val kind: FileKind,
    /** Endung in Kleinbuchstaben ohne Punkt, „“ wenn keine. */
    val extension: String,
    val mimeType: String?,
    val readable: Boolean,
    val writable: Boolean,
) {
    val parentPath: String get() = path.substringBeforeLast('/', "").ifEmpty { "/" }
}

/** Sortierkriterien. */
enum class SortKey(val label: String) {
    NAME("Name"),
    DATE("Änderungsdatum"),
    SIZE("Größe"),
    KIND("Art"),
}

data class SortOrder(val key: SortKey = SortKey.NAME, val ascending: Boolean = true)

/** Warum ein Name nicht verwendet werden kann. */
enum class NameProblem(val message: String) {
    EMPTY("Der Name darf nicht leer sein."),
    DOTS_ONLY("„.“ und „..“ sind als Name nicht erlaubt."),
    TOO_LONG("Der Name ist zu lang (höchstens 255 Byte)."),
    SLASH("Der Name darf keinen Schrägstrich „/“ enthalten."),
    FORBIDDEN_CHARACTER("Diese Zeichen sind nicht erlaubt: \" * : < > ? \\ |"),
    CONTROL_CHARACTER("Der Name enthält unsichtbare Steuerzeichen."),
    TRAILING_DOT_OR_SPACE("Der Name darf nicht mit einem Punkt oder Leerzeichen enden."),
    RESERVED("Dieser Name ist für ORBIT reserviert."),
}

/** Ergebnis beim Auflisten eines Ordners. */
sealed interface Listing {
    /** [hiddenCount] = ausgeblendete Einträge (versteckte Dateien), wenn sie nicht angezeigt werden. */
    data class Entries(val directory: FileEntry, val entries: List<FileEntry>, val hiddenCount: Int) : Listing

    data object NotFound : Listing

    data object NotADirectory : Listing

    /** [protectedBySystem] = Android sperrt den Ordner grundsätzlich (z. B. `Android/data`). */
    data class AccessDenied(val protectedBySystem: Boolean) : Listing

    data class Failed(val detail: String) : Listing
}

/** Inhalt eines Ordners (rekursiv). */
data class FolderStats(val files: Int, val folders: Int, val totalBytes: Long, val complete: Boolean)

/** Ein Vorgang, den die [FileOperationEngine] ausführt. */
sealed interface FileOperation {
    /** Kurzbezeichnung für Fortschritt und Ergebnis („Kopieren“). */
    val label: String

    data class Copy(val sources: List<String>, val targetDir: String) : FileOperation {
        override val label get() = "Kopieren"
    }

    data class Move(val sources: List<String>, val targetDir: String) : FileOperation {
        override val label get() = "Verschieben"
    }

    /** In den Papierkorb desselben Speichers legen (wiederherstellbar). */
    data class Trash(val sources: List<String>) : FileOperation {
        override val label get() = "In den Papierkorb legen"
    }

    /** Endgültig löschen – nicht wiederherstellbar. */
    data class DeletePermanently(val sources: List<String>) : FileOperation {
        override val label get() = "Endgültig löschen"
    }

    data class Restore(val items: List<TrashedItem>) : FileOperation {
        override val label get() = "Wiederherstellen"
    }

    /** Einträge aus dem Papierkorb endgültig entfernen. */
    data class DeleteFromTrash(val items: List<TrashedItem>) : FileOperation {
        override val label get() = "Endgültig löschen"
    }

    data class Rename(val source: String, val newName: String) : FileOperation {
        override val label get() = "Umbenennen"
    }

    data class CreateFolder(val parentDir: String, val name: String) : FileOperation {
        override val label get() = "Ordner erstellen"
    }

    /** ZIP-Archiv [archiveName] (mit oder ohne „.zip“) in [targetDir] aus [sources] erstellen. */
    data class Compress(val sources: List<String>, val targetDir: String, val archiveName: String) : FileOperation {
        override val label get() = "Komprimieren"
    }

    data class Extract(val archive: String, val targetDir: String) : FileOperation {
        override val label get() = "Entpacken"
    }

    /**
     * Textdatei sicher überschreiben (erst vollständig schreiben, dann ersetzen). [expectedModifiedMillis] =
     * Änderungszeit beim Öffnen; wurde die Datei inzwischen geändert, wird nicht überschrieben.
     */
    data class WriteText(val path: String, val text: String, val expectedModifiedMillis: Long?) : FileOperation {
        override val label get() = "Sichern"
    }
}

/** Entscheidung bei einem Namenskonflikt im Ziel. */
enum class ConflictChoice(val label: String) {
    /** Vorhandene Datei ersetzen (erst nachdem die neue vollständig geschrieben ist). */
    REPLACE("Ersetzen"),

    /** Beide behalten – die neue erhält einen freien Namen („Foto 2.jpg“). */
    KEEP_BOTH("Beide behalten"),
    SKIP("Überspringen"),

    /** Nur für Ordner: Inhalte zusammenführen (Konflikte darin werden einzeln entschieden). */
    MERGE("Zusammenführen"),
}

data class Conflict(val source: FileEntry, val existing: FileEntry)

data class Resolution(val choice: ConflictChoice, val applyToAll: Boolean = false)

/** Wird bei jedem Konflikt gefragt (z. B. Dialog in der Oberfläche). Darf aussetzen, bis der Nutzer entscheidet. */
fun interface ConflictResolver {
    suspend fun resolve(conflict: Conflict): Resolution
}

enum class OperationPhase(val label: String) {
    PREPARING("Wird vorbereitet …"),
    RUNNING("Läuft"),
    VERIFYING("Wird geprüft …"),
    CLEANING_UP("Wird abgeschlossen …"),
}

data class OperationProgress(
    val phase: OperationPhase,
    val totalItems: Int,
    val completedItems: Int,
    val totalBytes: Long,
    val completedBytes: Long,
    val currentName: String?,
) {
    /** Anteil 0…1 (nach Bytes, sonst nach Einträgen), `null` solange unbekannt. */
    val fraction: Float?
        get() = when {
            totalBytes > 0 -> (completedBytes.toDouble() / totalBytes).toFloat().coerceIn(0f, 1f)
            totalItems > 0 -> (completedItems.toFloat() / totalItems).coerceIn(0f, 1f)
            else -> null
        }
}

enum class FailureReason(val message: String) {
    NOT_FOUND("Nicht mehr vorhanden"),
    ACCESS_DENIED("Keine Berechtigung"),
    READ_ONLY("Ziel ist schreibgeschützt"),
    NO_SPACE("Nicht genug freier Speicherplatz"),
    FILE_TOO_LARGE("Zu groß für das Dateisystem des Ziels (FAT32 erlaubt höchstens 4 GB je Datei)"),
    INVALID_NAME("Name auf diesem Speicher nicht erlaubt"),
    TARGET_INSIDE_SOURCE("Ein Ordner kann nicht in sich selbst kopiert oder verschoben werden"),
    VERIFICATION_FAILED("Kopie stimmt nicht mit dem Original überein – Original bleibt erhalten"),
    ARCHIVE_UNSUPPORTED("Archiv wird nicht unterstützt (verschlüsselt oder unbekanntes Format)"),
    ARCHIVE_UNSAFE_ENTRY("Eintrag mit unsicherem Pfad übersprungen"),
    TRASH_UNAVAILABLE("Papierkorb auf diesem Speicher nicht verfügbar"),
    CHANGED_MEANWHILE("Die Datei wurde inzwischen geändert"),
    IO_ERROR("Lese- oder Schreibfehler"),

    /**
     * Kein Fehler im eigentlichen Sinn: Verknüpfungen und Gerätedateien werden bewusst nie kopiert, verschoben oder
     * gepackt (sie könnten auf andere Ordner zeigen oder beim Lesen hängen). Steht trotzdem in [OperationReport.failures],
     * damit der Nutzer sieht, was am Ursprungsort geblieben ist.
     */
    SPECIAL_FILE_SKIPPED("Verknüpfung oder Gerätedatei – wird bewusst nicht übertragen"),
    ;

    /** Ein echtes Problem (nicht nur ein bewusst übergangener Sonderfall). */
    val isProblem: Boolean get() = this != SPECIAL_FILE_SKIPPED
}

data class Failure(val path: String, val reason: FailureReason, val detail: String? = null)

/** Ergebnis eines Vorgangs – genau das, was tatsächlich passiert ist. */
data class OperationReport(
    val operation: FileOperation,
    /** Vollständig erledigte Einträge der obersten Ebene. */
    val succeeded: Int,
    val skipped: Int,
    val failures: List<Failure>,
    val cancelled: Boolean,
    val bytesProcessed: Long,
    /** Neu entstandene Pfade (Ziele) – für den Medienindex und um sie anzuzeigen. */
    val createdPaths: List<String>,
    /** Nicht mehr vorhandene Pfade (verschobene Quellen, Gelöschtes) – für den Medienindex. */
    val removedPaths: List<String>,
    /**
     * Fertig bearbeitete Dateien in Einträgen, die NICHT vollständig erledigt wurden (abgebrochen oder teilweise) –
     * z. B. die schon verschobenen Dateien eines halb verschobenen Ordners. Ihre Pfade stehen einzeln in
     * [createdPaths]/[removedPaths]; bei vollständig erledigten Einträgen steht dort nur der oberste Pfad.
     */
    val partialFilesDone: Int = 0,
    /** Nur Verschieben: Dateien dieser nicht vollständig verschobenen Einträge, die noch am Ursprungsort liegen. */
    val partialFilesLeft: Int = 0,
    /** Nur Papierkorb: die neuen Einträge (für „Widerrufen“, ohne den Papierkorb neu zu lesen). */
    val trashedItems: List<TrashedItem> = emptyList(),
) {
    val isComplete: Boolean get() = !cancelled && failures.isEmpty()
}

/** Ein Eintrag im Papierkorb von ORBIT. */
data class TrashedItem(
    val id: String,
    val name: String,
    val originalPath: String,
    val deletedAtMillis: Long,
    val sizeBytes: Long,
    val isDirectory: Boolean,
    /** Wo das Objekt jetzt liegt (im Papierkorb-Ordner des Speichers). */
    val storedPath: String,
    val volumeRoot: String,
)

/** Wie Speicher im Dateisystem gegliedert sind – liefert die Plattform (StorageManager). */
fun interface VolumeLayout {
    /** Wurzel des Speichers, auf dem [path] liegt (z. B. „/storage/emulated/0“, „/storage/1234-ABCD“), oder `null`. */
    fun volumeRootOf(path: String): String?
}

/** Vorschau einer Textdatei. */
data class TextPreview(
    val text: String,
    /** Datei war länger als gelesen. */
    val truncated: Boolean,
    val charsetName: String,
    /** Datei ist offensichtlich keine Textdatei (enthält Nullbytes). */
    val looksBinary: Boolean,
    /**
     * Beim Lesen mussten ungültige Bytes ersetzt werden (z. B. kaputtes UTF-8). Dann würde Sichern Bytes verändern,
     * die der Nutzer nie angefasst hat – die Oberfläche bietet Bearbeiten deshalb nicht an.
     */
    val lossy: Boolean = false,
)
