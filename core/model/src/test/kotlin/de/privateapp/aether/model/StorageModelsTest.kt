package de.privateapp.aether.model

import de.privateapp.aether.model.storage.Capacity
import de.privateapp.aether.model.storage.CapacityMethod
import de.privateapp.aether.model.storage.DataPartition
import de.privateapp.aether.model.storage.MountState
import de.privateapp.aether.model.storage.StorageOverview
import de.privateapp.aether.model.storage.StorageVolumeInfo
import de.privateapp.aether.model.storage.VolumeKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StorageModelsTest {

    @Test
    fun volumeKindFromAndroidDescription() {
        assertEquals(VolumeKind.INTERNAL, VolumeKind.classify(isPrimary = true, isRemovable = false, description = "Interner gemeinsamer Speicher"))
        assertEquals(VolumeKind.SD_CARD, VolumeKind.classify(false, true, "SD-Karte von SanDisk"))
        assertEquals(VolumeKind.SD_CARD, VolumeKind.classify(false, true, "SanDisk SD card"))
        assertEquals(VolumeKind.SD_CARD, VolumeKind.classify(false, true, "microSD"))
        assertEquals(VolumeKind.USB, VolumeKind.classify(false, true, "USB-Speicher von Kingston"))
        assertEquals(VolumeKind.USB, VolumeKind.classify(false, true, "Generic USB drive"))
        // Nicht eindeutig: kein Raten
        assertEquals(VolumeKind.REMOVABLE, VolumeKind.classify(false, true, "Samsung Speicher"))
        assertEquals(VolumeKind.REMOVABLE, VolumeKind.classify(false, true, null))
        // „sd“ als Teil eines Worts ist keine SD-Karte
        assertEquals(VolumeKind.REMOVABLE, VolumeKind.classify(false, true, "Wechselmedium sdx-intern"))
        assertEquals(VolumeKind.OTHER, VolumeKind.classify(false, false, "SD-Karte"))
    }

    @Test
    fun mountStateFromAndroid() {
        assertEquals(MountState.MOUNTED, MountState.fromAndroid("mounted"))
        assertEquals(MountState.MOUNTED_READ_ONLY, MountState.fromAndroid("mounted_ro"))
        assertEquals(MountState.BAD_REMOVAL, MountState.fromAndroid("bad_removal"))
        assertEquals(MountState.UNKNOWN, MountState.fromAndroid("irgendwas"))
        assertEquals(MountState.UNKNOWN, MountState.fromAndroid(null))
        assertTrue(MountState.MOUNTED_READ_ONLY.isMounted && !MountState.MOUNTED_READ_ONLY.isWritable)
        assertTrue(!MountState.REMOVED.isMounted)
    }

    @Test
    fun capacityIsOnlyCreatedFromConsistentValues() {
        val ok = Capacity.of(128_000_000_000, 47_000_000_000, CapacityMethod.SYSTEM_STATS)
        assertTrue(ok is Reading.Value)
        val c = (ok as Reading.Value).value
        assertEquals(81_000_000_000, c.usedBytes)
        assertEquals(81.0 / 128.0, c.usedFraction, 1e-9)
        assertEquals(CapacityMethod.SYSTEM_STATS.label, ok.source)

        assertEquals(Missing.NotReported, (Capacity.of(null, 5, CapacityMethod.FILE_SYSTEM) as Reading.Unavailable).missing)
        assertTrue((Capacity.of(0, 0, CapacityMethod.FILE_SYSTEM) as Reading.Unavailable).missing is Missing.Implausible)
        assertTrue((Capacity.of(100, 101, CapacityMethod.FILE_SYSTEM) as Reading.Unavailable).missing is Missing.Implausible)
        assertTrue((Capacity.of(100, -1, CapacityMethod.FILE_SYSTEM) as Reading.Unavailable).missing is Missing.Implausible)
        // Voll und leer sind gültig
        assertTrue(Capacity.of(100, 0, CapacityMethod.FILE_SYSTEM) is Reading.Value)
        assertTrue(Capacity.of(100, 100, CapacityMethod.FILE_SYSTEM) is Reading.Value)
    }

    @Test(expected = IllegalArgumentException::class)
    fun capacityConstructorRejectsInconsistentValues() {
        Capacity(100, 200, CapacityMethod.FILE_SYSTEM)
    }

    private fun internal(total: Long, free: Long, partition: Long, available: Long, method: CapacityMethod = CapacityMethod.SYSTEM_STATS) =
        StorageVolumeInfo(
            id = "primary", kind = VolumeKind.INTERNAL, description = "Interner Speicher", isPrimary = true,
            isRemovable = false, isEmulated = true, state = MountState.MOUNTED, path = "/storage/emulated/0",
            capacity = Capacity.of(total, free, method),
            partition = reported(DataPartition(partition, available), "Dateisystem (StatFs)"),
        )

    @Test
    fun derivedInternalFiguresAreLabelledAsDerived() {
        val v = internal(total = 128_000_000_000, free = 47_500_000_000, partition = 110_000_000_000, available = 45_000_000_000)
        val outside = v.outsideDataPartition as Reading.Value
        assertEquals(18_000_000_000, outside.value)
        assertEquals(ValueKind.DERIVED, outside.kind)
        val cache = v.reclaimableCache as Reading.Value
        assertEquals(2_500_000_000, cache.value)
        assertEquals(ValueKind.DERIVED, cache.kind)
    }

    @Test
    fun derivedFiguresAreOmittedWhenNotMeaningful() {
        // Freier Platz laut Statistik ≈ sofort verfügbar (unter 1 MB Unterschied) → kein Cache-Wert
        val v = internal(total = 128_000_000_000, free = 45_000_500_000, partition = 110_000_000_000, available = 45_000_000_000)
        assertNull(v.reclaimableCache)
        // Kapazität nicht größer als Partition → kein Systemanteil
        val w = internal(total = 100_000_000_000, free = 40_000_000_000, partition = 100_000_000_000, available = 40_000_000_000)
        assertNull(w.outsideDataPartition)
        // Ersatzweise über das Dateisystem gemessen: Herleitung wäre sinnlos
        val f = internal(total = 110_000_000_000, free = 45_000_000_000, partition = 110_000_000_000, available = 44_000_000_000, method = CapacityMethod.FILE_SYSTEM)
        assertNull(f.outsideDataPartition)
        assertNull(f.reclaimableCache)
    }

    @Test
    fun overviewSeparatesInternalAndExternal() {
        val sd = StorageVolumeInfo(
            id = "1234-ABCD", kind = VolumeKind.SD_CARD, description = "SD-Karte", isPrimary = false, isRemovable = true,
            isEmulated = false, state = MountState.MOUNTED, path = "/storage/1234-ABCD",
            capacity = Capacity.of(64_000_000_000, 60_000_000_000, CapacityMethod.FILE_SYSTEM), partition = null,
        )
        val o = StorageOverview(listOf(internal(128_000_000_000, 47_000_000_000, 110_000_000_000, 45_000_000_000), sd), 0)
        assertEquals("primary", o.internal?.id)
        assertEquals(listOf(sd), o.external)
        assertNull(sd.outsideDataPartition)
        assertNull(sd.reclaimableCache)
    }
}
