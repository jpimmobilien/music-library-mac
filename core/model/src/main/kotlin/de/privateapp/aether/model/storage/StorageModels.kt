package de.privateapp.aether.model.storage

import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.derived
import de.privateapp.aether.model.unavailable

/** Art eines Speicherorts. Die Oberfläche zeigt zusätzlich immer die Bezeichnung von Android. */
enum class VolumeKind(val label: String) {
    INTERNAL("Interner Speicher"),
    SD_CARD("SD-Karte"),
    USB("USB-Speicher"),

    /** Wechseldatenträger, dessen Art Android nicht eindeutig benennt. */
    REMOVABLE("Wechseldatenträger"),
    OTHER("Weiterer Speicher"),
    ;

    val isExternal: Boolean get() = this == SD_CARD || this == USB || this == REMOVABLE

    companion object {
        private val usbWord = Regex("""\busb\b""", RegexOption.IGNORE_CASE)
        private val sdWord = Regex("""\b(micro)?sd(hc|xc)?\b""", RegexOption.IGNORE_CASE)

        /**
         * Android nennt über öffentliche Schnittstellen nicht, ob ein Wechseldatenträger eine SD-Karte oder ein
         * USB-Speicher ist – wohl aber eine Bezeichnung („SD-Karte“, „USB-Speicher von SanDisk“ …). Daraus wird
         * nur das Symbol gewählt; ist die Bezeichnung nicht eindeutig, heißt es neutral „Wechseldatenträger“.
         */
        fun classify(isPrimary: Boolean, isRemovable: Boolean, description: String?): VolumeKind {
            if (isPrimary) return INTERNAL
            if (!isRemovable) return OTHER
            val d = description.orEmpty()
            return when {
                usbWord.containsMatchIn(d) -> USB
                sdWord.containsMatchIn(d) -> SD_CARD
                else -> REMOVABLE
            }
        }
    }
}

/** Zustand laut Android (`Environment.MEDIA_*`). */
enum class MountState(val androidValue: String, val label: String) {
    MOUNTED("mounted", "Eingebunden"),
    MOUNTED_READ_ONLY("mounted_ro", "Eingebunden, nur lesbar"),
    CHECKING("checking", "Wird geprüft"),
    UNMOUNTED("unmounted", "Nicht eingebunden"),
    EJECTING("ejecting", "Wird ausgeworfen"),
    REMOVED("removed", "Entfernt"),
    BAD_REMOVAL("bad_removal", "Ohne Auswerfen entfernt"),
    UNMOUNTABLE("unmountable", "Nicht lesbar (Dateisystem beschädigt oder unbekannt)"),
    NO_FILESYSTEM("nofs", "Ohne lesbares Dateisystem"),
    SHARED("shared", "Per USB freigegeben"),
    UNKNOWN("unknown", "Unbekannter Zustand"),
    ;

    val isMounted: Boolean get() = this == MOUNTED || this == MOUNTED_READ_ONLY
    val isWritable: Boolean get() = this == MOUNTED

    companion object {
        fun fromAndroid(value: String?): MountState = entries.firstOrNull { it.androidValue == value } ?: UNKNOWN
    }
}

/** Wie die Kapazität ermittelt wurde – wird als Quelle angezeigt. */
enum class CapacityMethod(val label: String) {
    /** `StorageStatsManager`: Kapazität des Datenträgers (wie im Handel angegeben) und freier Platz wie in den Einstellungen. */
    SYSTEM_STATS("Android-Speicherstatistik"),

    /** `StatFs`: Werte des eingebundenen Dateisystems. */
    FILE_SYSTEM("Dateisystem (StatFs)"),
}

/**
 * Gesamtgröße und freier Platz eines Datenträgers. Nur stimmige Werte sind möglich (Gesamtgröße > 0,
 * frei 0 … gesamt); Werte von Android werden über [of] geprüft. Belegt = gesamt − frei ist berechnet.
 */
data class Capacity(
    val totalBytes: Long,
    val freeBytes: Long,
    val method: CapacityMethod,
) {
    init {
        require(totalBytes > 0L && freeBytes in 0L..totalBytes) { "Unstimmige Kapazität: gesamt $totalBytes, frei $freeBytes" }
    }

    val usedBytes: Long get() = totalBytes - freeBytes

    /** Anteil des belegten Platzes 0…1. */
    val usedFraction: Double get() = usedBytes.toDouble() / totalBytes.toDouble()

    companion object {
        /**
         * Prüft die Werte: Gesamtgröße > 0, freier Platz 0 … Gesamtgröße. Etwas anderes liefert Android nur bei
         * Fehlern – dann wird nichts angezeigt statt eines falschen Werts.
         */
        fun of(totalBytes: Long?, freeBytes: Long?, method: CapacityMethod): Reading<Capacity> {
            if (totalBytes == null || freeBytes == null) return unavailable(Missing.NotReported)
            if (totalBytes <= 0L || freeBytes < 0L || freeBytes > totalBytes) {
                return unavailable(Missing.Implausible("gesamt $totalBytes B, frei $freeBytes B"))
            }
            return Reading.Value(Capacity(totalBytes, freeBytes, method), source = method.label)
        }
    }
}

/**
 * Nur interner Speicher: Kennzahlen der Datenpartition laut Dateisystem. Zusammen mit der
 * Android-Speicherstatistik lässt sich zeigen, was die Kapazität „im Handel“ vom nutzbaren Platz trennt.
 */
data class DataPartition(
    /** Größe der Datenpartition (`StatFs.totalBytes`). */
    val sizeBytes: Long,
    /** Für Apps sofort nutzbar (`StatFs.availableBytes`). */
    val availableBytes: Long,
)

/** Momentaufnahme eines Speicherorts. */
data class StorageVolumeInfo(
    /** Stabile Kennung: „primary“ für den internen Speicher, sonst die UUID des Datenträgers. */
    val id: String,
    val kind: VolumeKind,
    /** Bezeichnung von Android (in der Systemsprache), z. B. „SD-Karte von SanDisk“. */
    val description: String,
    val isPrimary: Boolean,
    val isRemovable: Boolean,
    val isEmulated: Boolean,
    val state: MountState,
    /** Pfad im Dateisystem, falls Android ihn nennt (nur bei eingebundenen Datenträgern). */
    val path: String?,
    val capacity: Reading<Capacity>,
    /** Nur beim internen Speicher; sonst `null`. */
    val partition: Reading<DataPartition>?,
) {
    /**
     * Interner Speicher: Teil der Kapazität außerhalb der Datenpartition (Betriebssystem, Firmware,
     * Rundung der Handelsangabe). Berechnet aus Kapazität (Speicherstatistik) − Größe der Datenpartition.
     */
    val outsideDataPartition: Reading<Long>?
        get() {
            val p = (partition as? Reading.Value)?.value ?: return null
            val c = (capacity as? Reading.Value)?.value ?: return null
            if (c.method != CapacityMethod.SYSTEM_STATS) return null
            val diff = c.totalBytes - p.sizeBytes
            return if (diff > 0L) derived(diff, "Kapazität − Datenpartition") else null
        }

    /**
     * Interner Speicher: zwischengespeicherte Daten, die Android bei Platzbedarf selbst löscht. Android rechnet
     * sie zum freien Platz („frei“ laut Speicherstatistik = sofort nutzbar + freigebbarer Cache).
     * Unter 1 MB wird nichts angezeigt (Messzeitpunkte unterscheiden sich minimal).
     */
    val reclaimableCache: Reading<Long>?
        get() {
            val p = (partition as? Reading.Value)?.value ?: return null
            val c = (capacity as? Reading.Value)?.value ?: return null
            if (c.method != CapacityMethod.SYSTEM_STATS) return null
            val diff = c.freeBytes - p.availableBytes
            return if (diff >= 1_000_000L) derived(diff, "frei laut Speicherstatistik − sofort nutzbar") else null
        }
}

/** Alle Speicherorte zu einem Zeitpunkt. */
data class StorageOverview(
    val volumes: List<StorageVolumeInfo>,
    val observedAtMillis: Long,
) {
    val internal: StorageVolumeInfo? get() = volumes.firstOrNull { it.isPrimary }
    val external: List<StorageVolumeInfo> get() = volumes.filter { !it.isPrimary }
}
