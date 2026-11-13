package de.privateapp.aether.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherColors
import de.privateapp.aether.design.PaletteSpec
import de.privateapp.aether.design.AetherTheme
import de.privateapp.aether.model.appearance.AppearanceSettings
import de.privateapp.aether.navigation.AppNavigator
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.navigation.TopLevel
import de.privateapp.aether.navigation.rememberAppNavigator
import de.privateapp.aether.ui.device.DeviceScreen
import de.privateapp.aether.ui.files.FilesScreen
import de.privateapp.aether.ui.home.HomeScreen
import de.privateapp.aether.ui.files.CategoryScreen
import de.privateapp.aether.ui.files.FileActions
import de.privateapp.aether.ui.files.FileActionsHost
import de.privateapp.aether.ui.orbit.OrbitIntroOverlay
import de.privateapp.aether.ui.files.FileActionsViewModel
import de.privateapp.aether.ui.files.FolderScreen
import de.privateapp.aether.ui.files.LocalFileActions
import de.privateapp.aether.ui.files.OperationOverlay
import de.privateapp.aether.ui.files.SearchScreen
import de.privateapp.aether.ui.files.TrashScreen
import de.privateapp.aether.ui.files.preview.PreviewScreen
import de.privateapp.aether.navigation.LocalAppNavigator
import de.privateapp.aether.files.OperationTexts
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.distinctUntilChanged
import de.privateapp.aether.ui.motion.MotionScreen
import de.privateapp.aether.ui.settings.LicensesScreen
import de.privateapp.aether.ui.settings.PrivacyScreen
import de.privateapp.aether.ui.settings.SettingsScreen
import de.privateapp.aether.ui.storage.StorageScreen

/**
 * Wurzel der Oberfläche: lädt die Darstellungs-Einstellungen, setzt das Theme und die Systemleisten und
 * verteilt die Ziele der Navigation auf die Bildschirme.
 */
@Composable
fun AetherRoot(graph: AppGraph, startScreen: String? = null, snapshot: SnapshotAppearance? = null) {
    val appearance: AppearanceSettings? by graph.appearance.collectAsStateWithLifecycle()
    val settings = appearance?.let { a ->
        if (snapshot == null) a else a.copy(theme = snapshot.theme ?: a.theme, intensity = snapshot.intensity ?: a.intensity)
    }
    if (settings == null) {
        // Nur in den ersten Millisekunden nach dem Start (der Startbildschirm deckt sie ab, siehe MainActivity).
        val base = if (isSystemInDarkTheme()) PaletteSpec.GlassDark else PaletteSpec.GlassLight
        Box(Modifier.fillMaxSize().background(AetherColors.argb(base.background)))
        return
    }
    AetherTheme(settings) {
        SystemBarsAppearance(darkTheme = Aether.colors.isDark)
        val navigator = rememberAppNavigator()
        LaunchedEffect(startScreen) { if (startScreen != null) openStartScreen(navigator, startScreen) }
        // Dateiaktionen gehören der Aktivität (nicht einer Seite): Dialoge und Rückmeldungen überstehen Seitenwechsel.
        val actionsVm: FileActionsViewModel = viewModel { FileActionsViewModel(graph) }
        val context = LocalContext.current
        val actions = remember(actionsVm, navigator, context) { FileActions(actionsVm, navigator, context) }
        BackHandler(enabled = navigator.canGoBack) { navigator.back() }
        AskForNotificationsOnFirstLongOperation(graph)
        CompositionLocalProvider(LocalAppNavigator provides navigator, LocalFileActions provides actions) {
        AetherShell(
            navigator,
            overlay = { backdrop, clearance -> OperationOverlay(actions, backdrop, clearance) },
        ) { route, insets ->
            when (route) {
                is Route.Root -> when (route.area) {
                    TopLevel.HOME -> HomeScreen(
                        graph,
                        insets,
                        navigator.reselectCount(TopLevel.HOME),
                        onOpen = { navigator.select(it) },
                        onOpenRoute = { area, target ->
                            navigator.select(area)
                            navigator.push(target)
                        },
                    )
                    TopLevel.FILES -> FilesScreen(graph, insets, navigator.reselectCount(TopLevel.FILES))
                    TopLevel.STORAGE -> StorageScreen(graph, insets, navigator.reselectCount(TopLevel.STORAGE))
                    TopLevel.DEVICE -> DeviceScreen(graph, insets, navigator.reselectCount(TopLevel.DEVICE), onOpenMotion = { navigator.push(Route.Motion) })
                    TopLevel.SETTINGS -> SettingsScreen(graph, insets, navigator.reselectCount(TopLevel.SETTINGS), onNavigate = { navigator.push(it) })
                }
                Route.Licenses -> LicensesScreen(insets, onBack = { navigator.back() })
                Route.Privacy -> PrivacyScreen(graph, insets, onBack = { navigator.back() })
                Route.Motion -> MotionScreen(graph, insets, onBack = { navigator.back() })
                is Route.Folder -> FolderScreen(graph, route.path, insets, onBack = { navigator.back() })
                is Route.Category -> CategoryScreen(graph, route.category, insets, onBack = { navigator.back() })
                Route.Search -> SearchScreen(graph, insets, onBack = { navigator.back() })
                Route.Trash -> TrashScreen(graph, insets, onBack = { navigator.back() })
                is Route.Preview -> PreviewScreen(graph, route.path, insets, onBack = { navigator.back() })
            }
        }
        FileActionsHost(actions)
        // ORBIT-Auftakt beim Kaltstart (≈ 0,8 s, über dem fertigen Inhalt, ohne Eingaben abzufangen)
        OrbitIntroOverlay()
        }
    }
}

/** Darstellung für Bildschirmfotos (MainActivity.EXTRA_THEME/EXTRA_EFFECTS) – gilt nur für diese Sitzung. */
data class SnapshotAppearance(
    val theme: de.privateapp.aether.model.appearance.ThemeStyle?,
    val intensity: de.privateapp.aether.model.appearance.EffectIntensity?,
)

/** Startbereich für Bildschirmfotos (MainActivity.EXTRA_START_SCREEN); Unbekanntes wird ignoriert. */
private fun openStartScreen(navigator: AppNavigator, screen: String) {
    when (screen) {
        "home" -> navigator.select(TopLevel.HOME)
        "files" -> navigator.select(TopLevel.FILES)
        "storage" -> navigator.select(TopLevel.STORAGE)
        "device" -> navigator.select(TopLevel.DEVICE)
        "settings" -> navigator.select(TopLevel.SETTINGS)
        "motion" -> {
            navigator.select(TopLevel.DEVICE)
            navigator.push(Route.Motion)
        }
        "globe" -> {
            // Bewegung › Sensor-Globus: Kopf, Geschwindigkeit, Kacheln, Kompass, Höhe, dann der Globus (Index 5)
            de.privateapp.aether.ui.common.SnapshotHints.motionStartIndex = 5
            navigator.select(TopLevel.DEVICE)
            navigator.push(Route.Motion)
        }
        "trash" -> {
            navigator.select(TopLevel.FILES)
            navigator.push(Route.Trash)
        }
        "privacy" -> {
            navigator.select(TopLevel.SETTINGS)
            navigator.push(Route.Privacy)
        }
    }
}

/**
 * Lange Vorgänge zeigen ihren Fortschritt auch in einer Benachrichtigung. Android 13+ fragt dafür einmal um Erlaubnis –
 * erst im passenden Moment (beim ersten langen Vorgang), nie beim Start. Abgelehnt? Der Vorgang läuft trotzdem.
 */
@Composable
private fun AskForNotificationsOnFirstLongOperation(graph: AppGraph) {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(graph) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@LaunchedEffect
        // Nur auf den Beginn eines langen Vorgangs reagieren – nicht auf jeden Fortschrittsschritt.
        graph.operations.jobs.map { jobs -> jobs.any { OperationTexts.mayTakeLong(it.operation) } }.distinctUntilChanged().collect { long ->
            if (!long) return@collect
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            if (granted || graph.settings.notificationsAsked.first()) return@collect
            graph.settings.setNotificationsAsked()
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

/** Symbolfarbe von Status- und Navigationsleiste passend zum Theme (z. B. Deep Dark bei hellem System). */
@Composable
private fun SystemBarsAppearance(darkTheme: Boolean) {
    val view = LocalView.current
    LaunchedEffect(darkTheme, view) {
        val window = view.context.findActivity()?.window ?: return@LaunchedEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !darkTheme
            isAppearanceLightNavigationBars = !darkTheme
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
