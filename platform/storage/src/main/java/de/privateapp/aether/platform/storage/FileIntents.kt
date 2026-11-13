package de.privateapp.aether.platform.storage

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import java.io.File

/** Ergebnis beim Übergeben einer Datei an eine andere App. */
enum class LaunchResult(val message: String?) {
    STARTED(null),
    NO_APP("Auf diesem Gerät ist keine App installiert, die diese Datei öffnen kann."),
    NOT_SHAREABLE("Diese Datei kann nicht an andere Apps übergeben werden."),
    FAILED("Die Datei konnte nicht übergeben werden."),
}

/**
 * Dateien in anderen Apps öffnen, teilen und App-Pakete installieren.
 *
 * Andere Apps erhalten nie einen Dateipfad, sondern eine `content://`-Adresse des eigenen FileProviders, die nur
 * für genau diese Datei und nur zum Lesen freigegeben wird ([Intent.FLAG_GRANT_READ_URI_PERMISSION]). Der Provider
 * selbst ist nicht exportiert: Ohne diese Freigabe kann keine App über ihn auf Dateien zugreifen.
 */
class FileIntents(context: Context, private val authority: String) {

    private val appContext = context.applicationContext

    fun uriFor(path: String): Uri? = try {
        FileProvider.getUriForFile(appContext, authority, File(path))
    } catch (e: IllegalArgumentException) {
        null
    }

    /** „Öffnen“: Android wählt die Standard-App oder fragt einmal nach. */
    fun view(entry: FileEntry): Intent? {
        val uri = uriFor(entry.path) ?: return null
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mimeFor(entry))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    /** „Öffnen mit …“: immer die Auswahl der Apps, ohne Standard zu speichern. */
    fun openWith(entry: FileEntry): Intent? = view(entry)?.let { Intent.createChooser(it, "Öffnen mit") }

    /** Teilen einer oder mehrerer Dateien (nur Dateien – Ordner können nicht geteilt werden). */
    fun share(entries: List<FileEntry>): Intent? {
        val files = entries.filter { !it.isDirectory }
        if (files.isEmpty()) return null
        val uris = files.mapNotNull { uriFor(it.path) }
        if (uris.size != files.size) return null
        val type = commonMime(files.map { mimeFor(it) })
        val send = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris.first())
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        }
        send.type = type
        // ClipData sorgt dafür, dass die Leseberechtigung bei allen Zielen ankommt (auch bei mehreren Dateien).
        val clip = ClipData.newRawUri(files.first().name, uris.first())
        uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        send.clipData = clip
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val title = if (files.size == 1) files.first().name else "${files.size} Dateien teilen"
        return Intent.createChooser(send, title)
    }

    /** Darf ORBIT Installationen anstoßen? Der Nutzer erlaubt das einmalig in den Einstellungen („Unbekannte Apps“). */
    fun canRequestInstalls(): Boolean = try {
        appContext.packageManager.canRequestPackageInstalls()
    } catch (e: RuntimeException) {
        false
    }

    fun unknownSourcesSettings(): Intent =
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.fromParts("package", appContext.packageName, null))

    /** Übergibt ein App-Paket an den Paketinstaller von Android – der zeigt Name, Rechte und fragt nach. */
    fun install(entry: FileEntry): Intent? {
        if (entry.kind != FileKind.APK) return null
        val uri = uriFor(entry.path) ?: return null
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    /** Startet [intent] aus einer Aktivität heraus und meldet ehrlich, ob das geklappt hat. */
    fun launch(activityContext: Context, intent: Intent?): LaunchResult {
        if (intent == null) return LaunchResult.NOT_SHAREABLE
        return try {
            activityContext.startActivity(intent)
            LaunchResult.STARTED
        } catch (e: ActivityNotFoundException) {
            LaunchResult.NO_APP
        } catch (e: SecurityException) {
            LaunchResult.FAILED
        } catch (e: RuntimeException) {
            LaunchResult.FAILED
        }
    }

    private fun mimeFor(entry: FileEntry): String = when {
        entry.kind == FileKind.APK -> APK_MIME
        else -> entry.mimeType ?: "application/octet-stream"
    }

    companion object {
        const val APK_MIME = "application/vnd.android.package-archive"

        // Gemeinsamer Typ mehrerer Dateien: alle gleich → dieser; gleiche Gruppe (z. B. nur Bilder) → Gruppe mit
        // Platzhalter; sonst „beliebiger Typ“.
        fun commonMime(types: List<String>): String {
            val distinct = types.distinct()
            if (distinct.size == 1) return distinct.first()
            val groups = distinct.map { it.substringBefore('/') }.distinct()
            return if (groups.size == 1) "${groups.first()}/*" else "*/*"
        }
    }
}
