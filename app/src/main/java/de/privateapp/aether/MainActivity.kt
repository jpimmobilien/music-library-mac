package de.privateapp.aether

import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.ViewTreeObserver
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import de.privateapp.aether.ui.AetherRoot

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
        setContent { AetherRoot(graph, startScreen) }
        keepSplashUntilAppearanceLoaded(graph)
    }

    companion object {
        /** Startbereich (home, files, storage, device, motion, settings, trash, privacy) – nur für Bildschirmfotos. */
        const val EXTRA_START_SCREEN = "orbit.snapshot"
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
