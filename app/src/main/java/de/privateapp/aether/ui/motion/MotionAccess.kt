package de.privateapp.aether.ui.motion

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.motion.LocationAccess
import de.privateapp.aether.model.motion.LocationPermission

/** Ergebnis der letzten Rückfrage nach dem Standort – bestimmt, welche Schaltfläche zuerst kommt. */
private enum class AskResult {
    NOT_ASKED,

    /** Abgelehnt; Android würde erneut fragen. */
    DENIED,

    /**
     * Abgelehnt und Android zeigt keine Begründung mehr an: entweder „Nicht mehr fragen“ (zweimal abgelehnt) oder der
     * Dialog wurde weggewischt. Beides lässt sich von außen nicht unterscheiden – deshalb gibt es dann beide Wege.
     */
    MAYBE_BLOCKED,
}

/**
 * Erklärt, warum die Seite den Standort braucht, und führt zur passenden Freigabe: Rückfrage von Android,
 * App-Einstellungen oder Standort-Einstellungen. Wird nur angezeigt, solange GPS nicht nutzbar ist.
 */
@Composable
internal fun LocationAccessPanel(access: LocationAccess, onAccessChanged: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val type = Aether.type
    val context = LocalContext.current
    val activity = LocalActivity.current
    var result by rememberSaveable { mutableStateOf(AskResult.NOT_ASKED) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        onAccessChanged()
        result = when {
            granted[Manifest.permission.ACCESS_FINE_LOCATION] == true -> AskResult.NOT_ASKED
            activity?.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) == true -> AskResult.DENIED
            else -> AskResult.MAYBE_BLOCKED
        }
    }
    // Android verlangt, „Genau“ und „Ungefähr“ gemeinsam zu erfragen; der Nutzer wählt im Dialog.
    val ask = { launcher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)) }

    Panel(modifier) {
        when {
            !access.hasGps -> {
                PanelHeader(AetherIcons.LocationPin, "Kein GPS-Empfänger", subtitle = "Nicht verfügbar auf diesem Gerät", tone = Tone.NEUTRAL)
                Spacer(Modifier.height(Spacing.m))
                Text(
                    "Android meldet auf diesem Gerät keinen GPS-Empfänger. Geschwindigkeit, GPS-Höhe und Satelliten gibt es deshalb nicht – Kompass und Luftdruck funktionieren unabhängig davon.",
                    color = colors.textSecondary,
                    style = type.callout,
                )
            }
            access.permission == LocationPermission.NONE -> {
                PanelHeader(AetherIcons.LocationPin, "Standort für Geschwindigkeit und Höhe", subtitle = "Freigabe „Genauer Standort“")
                Spacer(Modifier.height(Spacing.m))
                Text(
                    "Geschwindigkeit, Höhe und Satelliten kommen vom GPS-Empfänger. ORBIT nutzt ihn nur, solange diese Seite geöffnet ist – nie im Hintergrund. Die App hat keine Internet-Berechtigung: Position und Messwerte verlassen das Gerät nicht.",
                    color = colors.textSecondary,
                    style = type.callout,
                )
                Spacer(Modifier.height(Spacing.l))
                when (result) {
                    AskResult.MAYBE_BLOCKED -> {
                        Text(
                            "Falls Android nicht mehr nachfragt, lässt sich der Standort in den App-Einstellungen unter „Berechtigungen“ freigeben – dort „Nur während der Nutzung der App zulassen“ und „Genauen Standort verwenden“ wählen.",
                            color = colors.textSecondary,
                            style = type.footnote,
                        )
                        Spacer(Modifier.height(Spacing.m))
                        PillButton("App-Einstellungen öffnen", onClick = { context.openAppSettings() }, modifier = Modifier.fillMaxWidth(), icon = AetherIcons.OpenExternal, primary = true)
                        Spacer(Modifier.height(Spacing.s))
                        PillButton("Erneut fragen", onClick = ask, modifier = Modifier.fillMaxWidth())
                    }
                    else -> PillButton(
                        if (result == AskResult.DENIED) "Erneut fragen" else "Standort erlauben",
                        onClick = ask,
                        modifier = Modifier.fillMaxWidth(),
                        icon = AetherIcons.LocationPin,
                        primary = true,
                    )
                }
            }
            access.permission == LocationPermission.APPROXIMATE -> {
                PanelHeader(AetherIcons.LocationPin, "Nur ungefährer Standort freigegeben", subtitle = "Für Live-Werte fehlt „Genauer Standort“", tone = Tone.WARNING)
                Spacer(Modifier.height(Spacing.m))
                Text(
                    "Mit „Ungefährer Standort“ liefert Android eine auf etwa 2 km vergröberte Position – ohne Geschwindigkeit, Kurs, Höhe und Satelliten. Der Kompass nutzt sie trotzdem, um auf geografisch Nord umzurechnen.",
                    color = colors.textSecondary,
                    style = type.callout,
                )
                Spacer(Modifier.height(Spacing.l))
                PillButton("Genauen Standort erlauben", onClick = ask, modifier = Modifier.fillMaxWidth(), icon = AetherIcons.LocationPin, primary = true)
                Spacer(Modifier.height(Spacing.s))
                PillButton("App-Einstellungen öffnen", onClick = { context.openAppSettings() }, modifier = Modifier.fillMaxWidth(), icon = AetherIcons.OpenExternal)
            }
            !access.servicesEnabled -> {
                PanelHeader(AetherIcons.LocationPin, "Standort ist ausgeschaltet", subtitle = "Android-Einstellungen › Standort", tone = Tone.WARNING)
                Spacer(Modifier.height(Spacing.m))
                Text(
                    "Die Freigabe ist erteilt, aber der Standort ist im System ausgeschaltet. Sobald er eingeschaltet ist, startet die Messung hier von selbst.",
                    color = colors.textSecondary,
                    style = type.callout,
                )
                Spacer(Modifier.height(Spacing.l))
                PillButton("Standort-Einstellungen öffnen", onClick = { context.openLocationSettings() }, modifier = Modifier.fillMaxWidth(), icon = AetherIcons.OpenExternal, primary = true)
            }
        }
    }
}

private fun Context.openAppSettings() {
    startOrFallback(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
}

private fun Context.openLocationSettings() {
    startOrFallback(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
}

/** Manche Hersteller-Oberflächen kennen einzelne Einstellungsseiten nicht – dann die allgemeinen Einstellungen. */
private fun Context.startOrFallback(intent: Intent) {
    try {
        startActivity(intent)
    } catch (e: ActivityNotFoundException) {
        try {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        } catch (ignored: ActivityNotFoundException) {
            // Ohne Einstellungs-App gibt es nichts zu öffnen; die Erklärung im Text bleibt stehen.
        }
    }
}
