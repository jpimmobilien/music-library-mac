package de.privateapp.aether.ui.settings

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.InfoRow
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.ui.common.ScreenList
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.StatusBadge
import de.privateapp.aether.platform.storage.AllFilesAccess
import de.privateapp.aether.ui.common.SubpageHeader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/** Lizenztext der Schrift Inter (SIL Open Font License 1.1) – aus den App-Ressourcen, ohne Internet. */
@Composable
fun LicensesScreen(insets: PaddingValues, onBack: () -> Unit) {
    val context = LocalContext.current
    val text by produceState<String?>(initialValue = null, context) {
        value = withContext(Dispatchers.IO) {
            try {
                context.assets.open("licenses/OFL-Inter.txt").bufferedReader().use { it.readText() }
            } catch (e: IOException) {
                "Lizenztext konnte nicht gelesen werden (${e.message})."
            }
        }
    }
    val colors = Aether.colors
    val type = Aether.type
    ScreenList(insets, reselect = 0) {
        item(key = "header") { SubpageHeader("Lizenzen", onBack) }
        item(key = "inter") {
            Panel {
                PanelHeader(icon = AetherIcons.Document, title = "Inter", subtitle = "Schrift der Oberfläche · SIL Open Font License 1.1")
                Spacer(Modifier.height(Spacing.m))
                Text(text ?: "Wird geladen …", color = colors.textSecondary, style = type.footnote)
            }
        }
        item(key = "libraries") {
            Panel {
                PanelHeader(icon = AetherIcons.Layers, title = "Bibliotheken", subtitle = "Apache License 2.0")
                Spacer(Modifier.height(Spacing.s))
                Text(
                    "Android Jetpack (Compose, Material 3, Activity, Lifecycle, DataStore, Core) und Kotlin Coroutines – " +
                        "Copyright The Android Open Source Project bzw. JetBrains s.r.o., lizenziert unter der Apache License 2.0.",
                    color = colors.textSecondary,
                    style = type.footnote,
                )
            }
        }
    }
}

/** Datenschutz und Berechtigungen – in Klartext und mit dem aktuellen Stand jeder Berechtigung. */
@Composable
fun PrivacyScreen(graph: AppGraph, insets: PaddingValues, onBack: () -> Unit) {
    val colors = Aether.colors
    val type = Aether.type
    val context = LocalContext.current
    // Berechtigungen ändert man in den Android-Einstellungen – bei jeder Rückkehr neu lesen.
    var tick by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        tick++
        onPauseOrDispose { }
    }
    val states = remember(tick) { PermissionStates.read(context, graph) }
    ScreenList(insets, reselect = 0) {
        item(key = "header") { SubpageHeader("Datenschutz", onBack) }
        item(key = "principles") {
            Panel {
                PanelHeader(icon = AetherIcons.Shield, title = "Grundsätze", tone = Tone.SUCCESS)
                Spacer(Modifier.height(Spacing.s))
                InfoRow("Internet", "Keine Berechtigung", caption = "ORBIT kann keine Daten senden – auch keine Dateien")
                InfoRow("Telemetrie und Analyse", "Keine")
                InfoRow("Werbung", "Keine")
                InfoRow("Einstellungen, Verlauf", "Nur auf diesem Gerät", caption = "von Android-Sicherungen ausgenommen")
                InfoRow("Hintergrundüberwachung", "Keine", caption = "Werte werden nur gelesen, solange sie angezeigt werden")
                InfoRow("Löschen", "Erst in den Papierkorb", caption = "endgültig nur nach Bestätigung; nie automatisch")
            }
        }
        item(key = "permissions") {
            Panel {
                PanelHeader(icon = AetherIcons.Lock, title = "Berechtigungen", subtitle = "Aktueller Stand – antippen zum Ändern")
                Spacer(Modifier.height(Spacing.s))
                PermissionRow(
                    title = "Zugriff auf alle Dateien",
                    state = if (states.allFiles) "Erlaubt" else "Nicht erlaubt",
                    granted = states.allFiles,
                    purpose = "Dateimanager: Ordner und Dateien auf internem Speicher, SD-Karte und USB-Speicher lesen, ändern und löschen.",
                ) { launch(context, AllFilesAccess.settingsIntent(context), AllFilesAccess.fallbackIntent()) }
                PermissionRow(
                    title = "Standort",
                    state = when (states.location) {
                        LocationGrant.PRECISE -> "Genau"
                        LocationGrant.APPROXIMATE -> "Nur ungefähr"
                        LocationGrant.NONE -> "Nicht erlaubt"
                    },
                    granted = states.location != LocationGrant.NONE,
                    purpose = "Nur für „Gerät › Bewegung“ (Geschwindigkeit, Höhe, Satelliten) und nur, solange die Seite offen ist. Wird weder gespeichert noch gesendet.",
                ) { launch(context, AllFilesAccess.appDetailsIntent(context), null) }
                PermissionRow(
                    title = "Benachrichtigungen",
                    state = if (states.notifications) "Erlaubt" else "Nicht erlaubt",
                    granted = states.notifications,
                    purpose = "Fortschritt langer Dateivorgänge, wenn du die App währenddessen verlässt. Ohne sie läuft der Vorgang trotzdem.",
                ) { launch(context, notificationSettings(context), AllFilesAccess.appDetailsIntent(context)) }
                PermissionRow(
                    title = "Apps installieren",
                    state = if (states.installs) "Erlaubt" else "Nicht erlaubt",
                    granted = states.installs,
                    purpose = "Nur, um ein angetipptes App-Paket (APK) an den Installer von Android zu übergeben. Android fragt vor jeder Installation selbst.",
                ) { launch(context, graph.fileIntents.unknownSourcesSettings().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), AllFilesAccess.appDetailsIntent(context)) }
                Spacer(Modifier.height(Spacing.s))
                Text(
                    "Jede Berechtigung lässt sich jederzeit in den Android-Einstellungen entziehen; ORBIT zeigt dann ehrlich, was ohne sie nicht geht.",
                    color = colors.textSecondary,
                    style = type.footnote,
                )
            }
        }
    }
}

private enum class LocationGrant { PRECISE, APPROXIMATE, NONE }

private data class PermissionStates(val allFiles: Boolean, val location: LocationGrant, val notifications: Boolean, val installs: Boolean) {
    companion object {
        fun read(context: Context, graph: AppGraph): PermissionStates {
            fun has(p: String) = ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED
            return PermissionStates(
                allFiles = AllFilesAccess.isGranted(),
                location = when {
                    has(Manifest.permission.ACCESS_FINE_LOCATION) -> LocationGrant.PRECISE
                    has(Manifest.permission.ACCESS_COARSE_LOCATION) -> LocationGrant.APPROXIMATE
                    else -> LocationGrant.NONE
                },
                notifications = NotificationManagerCompat.from(context).areNotificationsEnabled(),
                installs = graph.fileIntents.canRequestInstalls(),
            )
        }
    }
}

private fun notificationSettings(context: Context): Intent =
    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

private fun launch(context: Context, intent: Intent, fallback: Intent?) {
    try {
        context.startActivity(intent)
    } catch (e: RuntimeException) {
        if (fallback != null) {
            try {
                context.startActivity(fallback)
            } catch (e2: RuntimeException) {
                // Keine Einstellungsseite vorhanden – nichts zu tun.
            }
        }
    }
}

@Composable
private fun PermissionRow(title: String, state: String, granted: Boolean, purpose: String, onClick: () -> Unit) {
    val colors = Aether.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.control))
            .clickable(role = Role.Button, onClickLabel = "In den Einstellungen ändern", onClick = onClick)
            .padding(vertical = Spacing.s, horizontal = Spacing.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = colors.text, style = Aether.type.bodyStrong, modifier = Modifier.weight(1f))
            StatusBadge(state, if (granted) Tone.SUCCESS else Tone.NEUTRAL)
        }
        Spacer(Modifier.height(Spacing.xxs))
        Text(purpose, color = colors.textSecondary, style = Aether.type.footnote)
    }
}
