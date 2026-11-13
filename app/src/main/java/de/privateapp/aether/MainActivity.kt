package de.privateapp.aether

import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.ViewTreeObserver
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import de.privateapp.aether.model.appearance.EffectIntensity
import de.privateapp.aether.model.appearance.ThemeStyle
import de.privateapp.aether.ui.AetherRoot
import de.privateapp.aether.ui.SnapshotAppearance

/** Einzige Activity. Die Oberfläche ist vollständig in Compose (siehe ui/AetherRoot). */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Randlos: Inhalte laufen unter Status- und Navigationsleiste; die Symbolfarbe der Systemleisten
        // folgt dem gewählten Theme (AetherRoot), nicht nur dem System.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val graph = (application as AetherApp).graph
        // Prüfmodus für Bildschirmfotos (ci/android_screens.sh): öffnet nur einen Bereich – keine Daten, keine Rechte.
        val startScreen = intent?.getStringExtra(EXTRA_START_SCREEN)?.takeIf { savedInstanceState == null }
        // Ebenfalls nur für Bildschirmfotos: Theme/Effektstärke für diese Sitzung (nichts wird gespeichert).
        val override = SnapshotAppearance(
            theme = intent?.getStringExtra(EXTRA_THEME)?.let { name -> ThemeStyle.entries.firstOrNull { it.name == name } },
            intensity = intent?.getStringExtra(EXTRA_EFFECTS)?.let { name -> EffectIntensity.entries.firstOrNull { it.name == name } },
        ).takeIf { it.theme != null || it.intensity != null }
        setContent { AetherRoot(graph, startScreen, override) }
        keepSplashUntilAppearanceLoaded(graph)
    }

    companion object {
        /** Startbereich (home, files, storage, device, motion, settings, trash, privacy) – nur für Bildschirmfotos. */
        const val EXTRA_START_SCREEN = "orbit.snapshot"

        /** Theme (Name aus ThemeStyle) bzw. Effektstärke (Name aus EffectIntensity) – nur für Bildschirmfotos, ungespeichert. */
        const val EXTRA_THEME = "orbit.theme"
        const val EXTRA_EFFECTS = "orbit.effects"
    }

    /**
     * Der Startbildschirm von Android bleibt stehen, bis die Darstellungs-Einstellungen gelesen sind (wenige
     * Millisekunden, höchstens 600 ms) – so erscheint nie kurz ein falsches Theme (z. B. hell vor Deep Dark).
     * Offizielles Vorgehen für den System-Startbildschirm ab Android 12 (OnPreDrawListener).
     */
    private fun keepSplashUntilAppearanceLoaded(graph: AppGraph) {
        val content: View = findViewById(android.R.id.content)
        val start = SystemClock.uptimeMillis()
        content.viewTreeObserver.addOnPreDrawListener(
            object : ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    val ready = graph.appearance.value != null || SystemClock.uptimeMillis() - start > 600L
                    if (ready) content.viewTreeObserver.removeOnPreDrawListener(this)
                    return ready
                }
            },
        )
    }
}
