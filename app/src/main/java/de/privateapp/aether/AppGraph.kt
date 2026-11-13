package de.privateapp.aether

import android.content.Context
import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.ThermalSnapshot
import de.privateapp.aether.model.storage.StorageOverview
import de.privateapp.aether.platform.device.BatteryMonitor
import de.privateapp.aether.platform.device.DeviceInfoReader
import de.privateapp.aether.platform.device.ThermalMonitor
import de.privateapp.aether.platform.storage.AndroidStorageVolumeSource
import de.privateapp.aether.platform.storage.StorageVolumeSource
import de.privateapp.aether.settings.SettingsStore
import de.privateapp.aether.files.FileOperation
import de.privateapp.aether.files.FileOperationEngine
import de.privateapp.aether.files.OperationReport
import de.privateapp.aether.files.TempJournal
import de.privateapp.aether.files.TrashStore
import de.privateapp.aether.operations.OperationManager
import de.privateapp.aether.platform.storage.ApkInspector
import de.privateapp.aether.platform.storage.FileIntents
import de.privateapp.aether.platform.storage.MediaIndex
import de.privateapp.aether.platform.storage.MediaIndexUpdater
import de.privateapp.aether.platform.storage.ThumbnailLoader
import de.privateapp.aether.platform.storage.VolumeRoots
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import de.privateapp.aether.model.appearance.AppearanceSettings
import de.privateapp.aether.settings.FilesPrefs
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Zentrale Verdrahtung (ohne DI-Bibliothek – für diese Projektgröße genügt eine Klasse).
 *
 * Laufende Werte (Speicher, Akku, Thermalstatus) werden geteilt: Mehrere Bildschirme hören dieselbe Quelle,
 * und 5 s nachdem der letzte Bildschirm verschwunden ist, meldet sich die Quelle bei Android ab. Im Hintergrund
 * überwacht ORBIT nichts. Als `StateFlow` behalten sie den letzten Wert – kehrt man zurück, erscheint nicht
 * kurz wieder „Wird gelesen …“, sondern der letzte Stand, bis Android den neuen meldet (beim Akku sofort).
 * `null` = seit dem Start noch nie gelesen.
 */
class AppGraph(context: Context) {
    private val appContext = context.applicationContext

    /** Anwendungskontext für Funktionen, die eigene Systemdienste anmelden (z. B. Bewegung, Dateien). */
    val context: Context get() = appContext

    /** Hauptthread: Systemmeldungen (Akku, Thermalstatus) kommen dort an; Dateisystemzugriffe wechseln selbst auf IO. */
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val stopDelayMillis = 5_000L

    val settings = SettingsStore(appContext)

    /**
     * Darstellung – sofort beim App-Start geladen und danach immer vorhanden, damit beim Drehen oder Neuaufbau
     * der Aktivität kein falsches Theme aufblitzt. `null` nur in den ersten Millisekunden nach dem Start.
     */
    val appearance: StateFlow<AppearanceSettings?> = settings.appearance.stateIn(appScope, SharingStarted.Eagerly, null)

    val storageSource: StorageVolumeSource = AndroidStorageVolumeSource(appContext)
    val deviceInfo = DeviceInfoReader(appContext)

    /** Arbeitsspeicher und Netzwerk-Zähler für den ORBIT Core (nur gelesen, solange er sichtbar ist). */
    val vitals = de.privateapp.aether.platform.device.LiveVitalsReader(appContext)

    val storage: StateFlow<StorageOverview?> =
        storageSource.overview().stateIn(appScope, SharingStarted.WhileSubscribed(stopDelayMillis), null)

    val battery: StateFlow<BatterySnapshot?> =
        BatteryMonitor(appContext).snapshots().stateIn(appScope, SharingStarted.WhileSubscribed(stopDelayMillis), null)

    val thermal: StateFlow<ThermalSnapshot?> =
        ThermalMonitor(appContext).snapshots().stateIn(appScope, SharingStarted.WhileSubscribed(stopDelayMillis), null)

    // --- Dateien ------------------------------------------------------------------------------------------------

    /** Einstellungen der Dateiverwaltung – wie die Darstellung sofort geladen, damit Ordner ohne Flackern erscheinen. */
    val filesPrefs: StateFlow<FilesPrefs?> = settings.files.stateIn(appScope, SharingStarted.Eagerly, null)

    val volumeRoots = VolumeRoots(appContext)
    val trash = TrashStore(volumeRoots)
    val mediaIndex = MediaIndex(appContext)
    val thumbnails = ThumbnailLoader(appContext)
    val apkInspector = ApkInspector(appContext)
    val fileIntents = FileIntents(appContext, authority = "${appContext.packageName}.files")
    private val indexUpdater = MediaIndexUpdater(appContext)

    /**
     * Merkt sich unfertige Kopien (Endung „.aether-part“), solange sie entstehen. Wird die App mitten im Kopieren
     * beendet (z. B. Akku leer), räumt der nächste Start sie auf – das Original war zu keinem Zeitpunkt in Gefahr.
     */
    private val journal = TempJournal(File(appContext.noBackupFilesDir, "unfertige-dateien.txt"))

    val engine = FileOperationEngine(volumeRoots, trash, journal)

    val operations = OperationManager(appContext, engine, afterFinished = ::afterOperation, scope = appScope)

    init {
        appScope.launch {
            withContext(Dispatchers.IO) {
                try {
                    journal.recoverLeftovers()
                } catch (e: Exception) {
                    // Aufräumen ist Komfort; ein Fehler darf den Start nicht verhindern.
                }
            }
        }
    }

    /** Nach jedem Vorgang: Medienindex abgleichen, Favoriten und „Zuletzt geöffnet“ nachziehen. */
    private suspend fun afterOperation(report: OperationReport) {
        val op = report.operation
        when (op) {
            is FileOperation.Rename -> report.createdPaths.firstOrNull()?.let { settings.movePaths(op.source, it) }
            is FileOperation.Move -> for (source in op.sources) {
                val target = op.targetDir.trimEnd('/') + "/" + source.trimEnd('/').substringAfterLast('/')
                if (source in report.removedPaths && target in report.createdPaths) settings.movePaths(source, target)
            }
            is FileOperation.Trash, is FileOperation.DeletePermanently -> settings.removeRecentFiles(report.removedPaths)
            else -> Unit
        }
        if (op is FileOperation.Trash || op is FileOperation.DeletePermanently) {
            settings.removeFavoritesUnder(report.removedPaths)
        }
        indexUpdater.update(OperationManager.indexable(report.createdPaths + report.removedPaths))
    }
}
