package de.privateapp.aether.model.device

import de.privateapp.aether.model.Reading

/** Arbeitsspeicher laut `ActivityManager.MemoryInfo`. */
data class MemoryFigures(
    /** Für Android nutzbarer Arbeitsspeicher (ohne vom Kernel reservierte Bereiche). */
    val totalBytes: Long,
    /** Derzeit verfügbar (frei plus schnell freigebbar). */
    val availableBytes: Long,
    /** Android meldet Speichermangel. */
    val lowMemory: Boolean,
    /** Ausstattung laut Hersteller (`advertisedMem`, Android 14+), sonst nicht verfügbar. */
    val advertisedBytes: Reading<Long>,
) {
    val usedFraction: Double get() = if (totalBytes > 0) ((totalBytes - availableBytes).toDouble() / totalBytes).coerceIn(0.0, 1.0) else 0.0
}

/** Bildschirm laut `WindowManager` und `Display`. */
data class DisplayFigures(
    /** Größtmögliche Fensterfläche in Pixeln (entspricht auf Telefonen der Displayauflösung). */
    val widthPx: Int,
    val heightPx: Int,
    val densityDpi: Int,
    /** Aktuelle Bildwiederholrate. */
    val refreshRateHz: Float,
    /** Höchste unterstützte Bildwiederholrate. */
    val maxRefreshRateHz: Float,
    val hdr: Boolean,
)

/** Geräteübersicht – nur Werte aus offiziellen Schnittstellen. */
data class DeviceSummary(
    /** Vom Nutzer bzw. Hersteller vergebener Gerätename („Gerätename“ in den Einstellungen). */
    val deviceName: Reading<String>,
    val manufacturer: String,
    val brand: String,
    val model: String,
    /** Interner Gerätecode (`Build.DEVICE`), z. B. „raven“. */
    val deviceCode: String,
    val androidRelease: String,
    val sdkInt: Int,
    val securityPatch: Reading<String>,
    val socManufacturer: Reading<String>,
    val socModel: Reading<String>,
    val supportedAbis: List<String>,
    val cpuCores: Int,
    val memory: Reading<MemoryFigures>,
    val display: Reading<DisplayFigures>,
    val sensorCount: Reading<Int>,
    /** Zeit seit dem letzten Neustart. */
    val uptimeMillis: Long,
) {
    /** Anzeigename: Gerätename, sonst Hersteller + Modell ohne doppelte Herstellerangabe. */
    val displayName: String
        get() = (deviceName as? Reading.Value)?.value ?: modelName(manufacturer, model)

    companion object {
        /** „Google“ + „Pixel 6 Pro“ → „Google Pixel 6 Pro“; „samsung“ + „Samsung Galaxy …“ → „Samsung Galaxy …“. */
        fun modelName(manufacturer: String, model: String): String {
            val m = model.trim()
            val maker = manufacturer.trim().replaceFirstChar { it.uppercaseChar() }
            return when {
                maker.isEmpty() -> m
                m.isEmpty() -> maker
                m.startsWith(maker, ignoreCase = true) -> m.replaceFirstChar { it.uppercaseChar() }
                else -> "$maker $m"
            }
        }

        /** Android-Versionsname aus der API-Stufe (für Hinweise wie „ab Android 14“). */
        fun releaseForApi(api: Int): String = when (api) {
            31 -> "12"
            32 -> "12L"
            33 -> "13"
            34 -> "14"
            35 -> "15"
            36 -> "16"
            37 -> "17"
            else -> "API $api"
        }
    }
}
