package de.privateapp.aether.platform.device

import android.app.ActivityManager
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.Display
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.device.DeviceSummary
import de.privateapp.aether.model.device.DisplayFigures
import de.privateapp.aether.model.device.MemoryFigures
import de.privateapp.aether.model.reported
import de.privateapp.aether.model.unavailable
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Geräteübersicht aus offiziellen Schnittstellen (`Build`, `ActivityManager`, `DisplayManager`, `SensorManager`,
 * `Settings.Global`). Keine Berechtigung, keine Systemdateien, kein Root.
 */
class DeviceInfoReader(
    context: Context,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val appContext = context.applicationContext

    suspend fun read(): DeviceSummary = withContext(io) {
        DeviceSummary(
            deviceName = deviceName(),
            manufacturer = Build.MANUFACTURER.orEmpty(),
            brand = Build.BRAND.orEmpty(),
            model = Build.MODEL.orEmpty(),
            deviceCode = Build.DEVICE.orEmpty(),
            androidRelease = Build.VERSION.RELEASE_OR_CODENAME.orEmpty(),
            sdkInt = Build.VERSION.SDK_INT,
            securityPatch = text(Build.VERSION.SECURITY_PATCH, "Build.VERSION"),
            socManufacturer = text(Build.SOC_MANUFACTURER, "Build"),
            socModel = text(Build.SOC_MODEL, "Build"),
            supportedAbis = Build.SUPPORTED_ABIS?.toList().orEmpty(),
            cpuCores = Runtime.getRuntime().availableProcessors(),
            memory = memory(),
            display = display(),
            sensorCount = sensorCount(),
            uptimeMillis = SystemClock.elapsedRealtime(),
        )
    }

    private fun text(value: String?, source: String): Reading<String> {
        val v = value?.trim()
        return if (v.isNullOrEmpty() || v.equals("unknown", ignoreCase = true)) unavailable(Missing.NotReported) else reported(v, source)
    }

    /** Gerätename aus den Einstellungen (vom Nutzer bzw. Hersteller vergeben, z. B. „Pixel 6 Pro“). */
    private fun deviceName(): Reading<String> = try {
        text(Settings.Global.getString(appContext.contentResolver, Settings.Global.DEVICE_NAME), "Einstellungen › Gerätename")
    } catch (e: RuntimeException) {
        unavailable(Missing.NotReported)
    }

    private fun memory(): Reading<MemoryFigures> {
        val am = appContext.getSystemService(ActivityManager::class.java) ?: return unavailable(Missing.NotReported)
        return try {
            val info = ActivityManager.MemoryInfo()
            am.getMemoryInfo(info)
            if (info.totalMem <= 0L) return unavailable(Missing.NotReported)
            val advertised: Reading<Long> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                if (info.advertisedMem > 0L) reported(info.advertisedMem, "ActivityManager") else unavailable(Missing.NotReported)
            } else {
                unavailable(Missing.RequiresAndroid(34, "14"))
            }
            reported(
                MemoryFigures(
                    totalBytes = info.totalMem,
                    availableBytes = info.availMem.coerceIn(0L, info.totalMem),
                    lowMemory = info.lowMemory,
                    advertisedBytes = advertised,
                ),
                "ActivityManager",
            )
        } catch (e: RuntimeException) {
            unavailable(Missing.Failed(e.javaClass.simpleName))
        }
    }

    /** Physische Auflösung des eingebauten Displays im aktuellen Modus und Bildwiederholraten. */
    private fun display(): Reading<DisplayFigures> = try {
        val dm = appContext.getSystemService(DisplayManager::class.java)
        val display = dm?.getDisplay(Display.DEFAULT_DISPLAY) ?: return unavailable(Missing.NotReported)
        val mode = display.mode
        val maxRefresh = display.supportedModes.maxOfOrNull { it.refreshRate } ?: display.refreshRate
        reported(
            DisplayFigures(
                widthPx = minOf(mode.physicalWidth, mode.physicalHeight),
                heightPx = maxOf(mode.physicalWidth, mode.physicalHeight),
                densityDpi = appContext.resources.configuration.densityDpi,
                refreshRateHz = display.refreshRate,
                maxRefreshRateHz = maxRefresh,
                hdr = display.isHdr,
            ),
            "DisplayManager",
        )
    } catch (e: RuntimeException) {
        unavailable(Missing.Failed(e.javaClass.simpleName))
    }

    private fun sensorCount(): Reading<Int> = try {
        val sm = appContext.getSystemService(SensorManager::class.java)
        if (sm == null) unavailable(Missing.NotReported) else reported(sm.getSensorList(Sensor.TYPE_ALL).size, "SensorManager")
    } catch (e: RuntimeException) {
        unavailable(Missing.Failed(e.javaClass.simpleName))
    }
}
