package de.privateapp.aether.platform.storage

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.Settings

/**
 * „Zugriff auf alle Dateien“ (MANAGE_EXTERNAL_STORAGE) – die Berechtigung, mit der ein Dateimanager unter
 * Android 11+ den gesamten gemeinsamen Speicher und eingebundene SD-Karten/USB-Speicher lesen, ändern und löschen
 * darf. Sie wird nicht per Dialog erteilt, sondern vom Nutzer in den Einstellungen eingeschaltet; Android meldet
 * die Änderung nicht – die App prüft deshalb bei jeder Rückkehr in den Vordergrund erneut ([isGranted]).
 *
 * Auch mit dieser Berechtigung bleiben `Android/data` und `Android/obb` anderer Apps gesperrt (ab Android 11
 * Systemvorgabe) – das ist kein Fehler von ORBIT.
 */
object AllFilesAccess {

    fun isGranted(): Boolean = try {
        Environment.isExternalStorageManager()
    } catch (e: RuntimeException) {
        false
    }

    /**
     * Öffnet die Einstellung direkt für ORBIT. Einige Hersteller (ältere MIUI-Versionen) kennen diese Seite nicht –
     * dann [fallbackIntent].
     */
    fun settingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Liste aller Apps mit dieser Berechtigung – der Nutzer wählt dort ORBIT. */
    fun fallbackIntent(): Intent =
        Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** App-Info von ORBIT (letzter Ausweg, wenn keine der beiden Seiten existiert). */
    fun appDetailsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
