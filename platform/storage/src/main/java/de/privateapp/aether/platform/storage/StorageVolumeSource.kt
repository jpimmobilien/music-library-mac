package de.privateapp.aether.platform.storage

import android.app.usage.StorageStatsManager
import android.content.Context
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.reported
import de.privateapp.aether.model.storage.Capacity
import de.privateapp.aether.model.storage.CapacityMethod
import de.privateapp.aether.model.storage.DataPartition
import de.privateapp.aether.model.storage.MountState
import de.privateapp.aether.model.storage.StorageOverview
import de.privateapp.aether.model.storage.StorageVolumeInfo
import de.privateapp.aether.model.storage.VolumeKind
import de.privateapp.aether.model.unavailable
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/** Speicherorte und ihre Kapazität. */
interface StorageVolumeSource {
    /** Momentaufnahme aller Speicherorte. Fragt das Dateisystem ab – läuft nie auf dem Hauptthread. */
    suspend fun read(): StorageOverview

    /**
     * Laufende Übersicht: sofort, bei jeder Zustandsänderung eines Datenträgers (eingelegt, entfernt,
     * eingebunden …) und zusätzlich alle [refreshMillis], weil sich der freie Platz ohne Meldung ändert.
     */
    fun overview(refreshMillis: Long = 15_000L): Flow<StorageOverview>
}

/**
 * Umsetzung mit den offiziellen Schnittstellen – nur lesend und ohne Berechtigung:
 * - `StorageManager.getStorageVolumes()` für die Liste (interner Speicher, SD-Karte, USB-Speicher),
 * - `StorageStatsManager` für Kapazität und freien Platz des internen Speichers (wie in den Einstellungen),
 * - `StatFs` für Wechseldatenträger und die Datenpartition.
 * Liefert Android keinen stimmigen Wert, bleibt er leer – es wird nichts geschätzt.
 */
class AndroidStorageVolumeSource(
    context: Context,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : StorageVolumeSource {

    private val appContext = context.applicationContext

    override suspend fun read(): StorageOverview = withContext(io) {
        val manager = appContext.getSystemService(StorageManager::class.java)
        val volumes = try {
            manager?.storageVolumes.orEmpty()
        } catch (e: RuntimeException) {
            emptyList()
        }
        val infos = volumes.mapIndexed { index, v -> describe(v, index) }
            .sortedWith(compareByDescending<StorageVolumeInfo> { it.isPrimary }.thenBy { it.description.lowercase() })
        StorageOverview(infos, System.currentTimeMillis())
    }

    override fun overview(refreshMillis: Long): Flow<StorageOverview> =
        merge(flowOf(Unit), volumeChanges(), ticker(refreshMillis))
            .conflate()
            .map { read() }
            .distinctUntilChanged { a, b -> a.volumes == b.volumes }

    /** Meldet Zustandsänderungen von Datenträgern (Android 11+: StorageVolumeCallback). */
    private fun volumeChanges(): Flow<Unit> = callbackFlow {
        val manager = appContext.getSystemService(StorageManager::class.java)
        if (manager == null) {
            awaitClose { }
            return@callbackFlow
        }
        val callback = object : StorageManager.StorageVolumeCallback() {
            override fun onStateChanged(volume: StorageVolume) {
                trySend(Unit)
            }
        }
        manager.registerStorageVolumeCallback(appContext.mainExecutor, callback)
        awaitClose { manager.unregisterStorageVolumeCallback(callback) }
    }

    private fun ticker(periodMillis: Long): Flow<Unit> = flow {
        while (true) {
            delay(periodMillis)
            emit(Unit)
        }
    }

    private fun describe(volume: StorageVolume, index: Int): StorageVolumeInfo {
        val state = MountState.fromAndroid(volume.state)
        val description = try {
            volume.getDescription(appContext)
        } catch (e: RuntimeException) {
            null
        } ?: if (volume.isPrimary) VolumeKind.INTERNAL.label else VolumeKind.REMOVABLE.label
        val kind = VolumeKind.classify(volume.isPrimary, volume.isRemovable, description)
        val directory: File? = if (state.isMounted) volume.directory else null
        // Eindeutig, auch wenn zwei Datenträger ohne UUID (z. B. unformatiert) dieselbe Bezeichnung tragen.
        val id = if (volume.isPrimary) "primary" else (volume.uuid ?: "ohne-uuid-$index")
        val capacity: Reading<Capacity> = when {
            !state.isMounted -> unavailable(Missing.NotMounted)
            volume.isPrimary -> internalCapacity()
            directory != null -> fileSystemCapacity(directory)
            else -> unavailable(Missing.NotReported)
        }
        val partition = if (volume.isPrimary && state.isMounted) dataPartition() else null
        return StorageVolumeInfo(
            id = id,
            kind = kind,
            description = description,
            isPrimary = volume.isPrimary,
            isRemovable = volume.isRemovable,
            isEmulated = volume.isEmulated,
            state = state,
            path = directory?.path,
            capacity = capacity,
            partition = partition,
        )
    }

    /**
     * Interner Speicher wie in den Android-Einstellungen: Kapazität des Datenträgers (so, wie sie im Handel
     * angegeben ist) und freier Platz einschließlich Zwischenspeicher, den Android selbst freigibt.
     * Ersatzweise die Datenpartition laut Dateisystem.
     */
    private fun internalCapacity(): Reading<Capacity> {
        val stats = appContext.getSystemService(StorageStatsManager::class.java)
        if (stats != null) {
            try {
                val total = stats.getTotalBytes(StorageManager.UUID_DEFAULT)
                val free = stats.getFreeBytes(StorageManager.UUID_DEFAULT)
                val r = Capacity.of(total, free, CapacityMethod.SYSTEM_STATS)
                if (r is Reading.Value) return r
            } catch (e: IOException) {
                // weiter mit dem Dateisystem
            } catch (e: RuntimeException) {
                // weiter mit dem Dateisystem
            }
        }
        return fileSystemCapacity(Environment.getDataDirectory())
    }

    private fun fileSystemCapacity(directory: File): Reading<Capacity> = try {
        val fs = StatFs(directory.path)
        Capacity.of(fs.totalBytes, fs.availableBytes, CapacityMethod.FILE_SYSTEM)
    } catch (e: IllegalArgumentException) {
        unavailable(Missing.Failed("Dateisystem nicht lesbar"))
    } catch (e: RuntimeException) {
        unavailable(Missing.Failed(e.javaClass.simpleName))
    }

    private fun dataPartition(): Reading<DataPartition> = try {
        val fs = StatFs(Environment.getDataDirectory().path)
        val size = fs.totalBytes
        val available = fs.availableBytes
        if (size > 0 && available in 0..size) {
            reported(DataPartition(size, available), CapacityMethod.FILE_SYSTEM.label)
        } else {
            unavailable(Missing.Implausible("Partition $size B, verfügbar $available B"))
        }
    } catch (e: RuntimeException) {
        unavailable(Missing.Failed(e.javaClass.simpleName))
    }
}
