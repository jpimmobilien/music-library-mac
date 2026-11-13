package de.privateapp.aether.platform.storage

import android.content.Context
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import de.privateapp.aether.files.VolumeLayout
import de.privateapp.aether.model.storage.MountState
import de.privateapp.aether.model.storage.VolumeKind

/** Ein Speicher, den man im Dateimanager öffnen kann (interner Speicher, SD-Karte, USB-Speicher). */
data class BrowseRoot(
    /** Wurzelordner, z. B. „/storage/emulated/0“ oder „/storage/1234-ABCD“. */
    val path: String,
    /** Bezeichnung laut Android („Interner gemeinsamer Speicher“, „SanDisk SD-Karte“ …). */
    val label: String,
    val kind: VolumeKind,
    val isPrimary: Boolean,
    val isRemovable: Boolean,
    /** Nur lesbar eingebunden (z. B. schreibgeschützte SD-Karte, NTFS-Stick ohne Schreibtreiber). */
    val readOnly: Boolean,
    /** Name des Speichers im Medienindex (MediaStore), `null` wenn unbekannt. */
    val mediaStoreVolume: String?,
)

/**
 * Eingebundene Speicher laut `StorageManager` – Grundlage für den Dateimanager und für die Frage, auf welchem
 * Speicher ein Pfad liegt (Papierkorb je Speicher, Verschieben über Speichergrenzen = Kopieren + Prüfen).
 *
 * Die Liste wird bei jedem Aufruf frisch gelesen (ein Binder-Aufruf, Mikrosekunden) – so ist eine gerade entnommene
 * SD-Karte sofort nicht mehr dabei.
 */
class VolumeRoots(context: Context) : VolumeLayout {

    private val appContext = context.applicationContext

    fun list(): List<BrowseRoot> {
        val manager = appContext.getSystemService(StorageManager::class.java) ?: return emptyList()
        val volumes = try {
            manager.storageVolumes
        } catch (e: RuntimeException) {
            return emptyList()
        }
        return volumes.mapNotNull { describe(it) }
            .distinctBy { it.path }
            .sortedWith(compareByDescending<BrowseRoot> { it.isPrimary }.thenBy { it.label.lowercase() })
    }

    override fun volumeRootOf(path: String): String? = rootFor(path)?.path

    /** Speicher, auf dem [path] liegt (längste passende Wurzel), oder `null` (z. B. Systempfad, entnommene Karte). */
    fun rootFor(path: String): BrowseRoot? = rootFor(path, list())

    companion object {
        fun rootFor(path: String, roots: List<BrowseRoot>): BrowseRoot? =
            roots.filter { r -> path == r.path || path.startsWith(if (r.path == "/") "/" else "${r.path}/") }
                .maxByOrNull { it.path.length }
    }

    private fun describe(volume: StorageVolume): BrowseRoot? {
        val state = MountState.fromAndroid(volume.state)
        if (!state.isMounted) return null
        val directory = volume.directory ?: return null
        val label = try {
            volume.getDescription(appContext)
        } catch (e: RuntimeException) {
            null
        } ?: if (volume.isPrimary) VolumeKind.INTERNAL.label else VolumeKind.REMOVABLE.label
        return BrowseRoot(
            path = directory.absolutePath.trimEnd('/').ifEmpty { "/" },
            label = label,
            kind = VolumeKind.classify(volume.isPrimary, volume.isRemovable, label),
            isPrimary = volume.isPrimary,
            isRemovable = volume.isRemovable,
            readOnly = state == MountState.MOUNTED_READ_ONLY,
            mediaStoreVolume = try {
                volume.mediaStoreVolumeName
            } catch (e: RuntimeException) {
                null
            },
        )
    }
}
