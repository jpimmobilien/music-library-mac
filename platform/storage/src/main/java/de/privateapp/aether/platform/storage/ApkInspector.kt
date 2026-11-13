package de.privateapp.aether.platform.storage

import android.content.Context
import android.os.Build
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.reported
import de.privateapp.aether.model.unavailable

/** Angaben aus einem App-Paket (APK), so wie Android sie aus der Datei liest – ohne es zu installieren. */
data class ApkDetails(
    val label: String?,
    val packageName: String,
    val versionName: String?,
    val versionCode: Long,
    val minSdk: Int?,
    val targetSdk: Int?,
    /** Version der installierten App mit diesem Paketnamen, falls ORBIT sie sehen kann. */
    val installedVersionName: String?,
    /**
     * `true` = installiert. `null` = nicht feststellbar: Seit Android 11 sieht eine App andere Apps nur eingeschränkt
     * (Paketsichtbarkeit). ORBIT fragt dafür bewusst nicht nach der Berechtigung, alle Apps zu sehen – „nicht
     * gefunden“ heißt deshalb nicht „nicht installiert“. Der Android-Installer zeigt es vor der Installation selbst.
     */
    val installed: Boolean?,
)

class ApkInspector(context: Context) {
    private val appContext = context.applicationContext

    /** Liest die Angaben – blockiert kurz (Datei wird geöffnet), also nicht auf dem Hauptthread aufrufen. */
    fun inspect(path: String): Reading<ApkDetails> {
        val pm = appContext.packageManager
        val info = try {
            ThumbnailLoader.archiveInfo(pm, path)
        } catch (e: RuntimeException) {
            null
        } ?: return unavailable(Missing.Failed("Android kann dieses App-Paket nicht lesen (beschädigt oder unvollständig)"))
        val app = info.applicationInfo
        app?.sourceDir = path
        app?.publicSourceDir = path
        val installed = try {
            pm.getPackageInfo(info.packageName, 0)
        } catch (e: Exception) {
            null
        }
        return reported(
            ApkDetails(
                label = app?.loadLabel(pm)?.toString(),
                packageName = info.packageName,
                versionName = info.versionName,
                versionCode = info.longVersionCode,
                minSdk = app?.minSdkVersion,
                targetSdk = app?.targetSdkVersion,
                installedVersionName = installed?.versionName,
                installed = if (installed != null) true else null,
            ),
            "PackageManager (aus der Datei gelesen)",
        )
    }

    companion object {
        /** Android-Version zu einer API-Stufe („12“ für 31) – unbekannte Stufen bleiben als „API n“ stehen. */
        fun releaseFor(api: Int): String = when {
            api == 36 -> "16"
            api == 35 -> "15"
            api == 34 -> "14"
            api == 33 -> "13"
            api == 32 -> "12L"
            api == 31 -> "12"
            api == 30 -> "11"
            api == 29 -> "10"
            api == 28 -> "9"
            api == 27 -> "8.1"
            api == 26 -> "8.0"
            api == 25 -> "7.1"
            api == 24 -> "7.0"
            api == 23 -> "6.0"
            api == 22 -> "5.1"
            api == 21 -> "5.0"
            else -> "API $api"
        }

        val deviceApi: Int get() = Build.VERSION.SDK_INT
    }
}
