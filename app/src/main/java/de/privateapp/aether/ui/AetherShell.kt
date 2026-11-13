package de.privateapp.aether.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.launch
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import de.privateapp.aether.design.Backdrop
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AtmosphereBackground
import de.privateapp.aether.design.EdgeFade
import de.privateapp.aether.design.GlassCircleButton
import de.privateapp.aether.design.GlassRail
import de.privateapp.aether.design.GlassTabBar
import de.privateapp.aether.design.Motion
import de.privateapp.aether.design.NavItem
import de.privateapp.aether.design.RailWidth
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.TabBarHeight
import de.privateapp.aether.design.backdropSource
import de.privateapp.aether.design.rememberBackdrop
import de.privateapp.aether.navigation.AppNavigator
import de.privateapp.aether.navigation.NavMove
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.navigation.TopLevel

/** Ab dieser Fensterbreite steht die Navigation als Leiste links (Tablets, Faltgeräte, große Querformate). */
private val WideLayoutMinWidth = 600.dp

/**
 * Die Leiste links braucht für fünf Bereiche rund 360 dp Höhe plus Systemleisten. Telefone im Querformat sind
 * dafür zu niedrig – dort bleibt die Reiterleiste unten (sonst wären Einträge abgeschnitten oder zu klein).
 */
private val WideLayoutMinHeight = 480.dp

/**
 * Rahmen der App: atmosphärischer Hintergrund, Inhalt (als Quelle für die Glas-Unschärfe), Kantenübergang
 * unter der Statusleiste und die schwebende Navigation. Auf Telefonen: vier Bereiche in der Reiterleiste,
 * daneben eine runde Schaltfläche für die Einstellungen. Auf breiten Fenstern: Leiste links mit allen fünf.
 *
 * [content] bekommt die Abstände, die der Inhalt freihalten muss (Systemleisten, Navigation).
 */
@Composable
fun AetherShell(
    navigator: AppNavigator,
    overlay: @Composable BoxScope.(backdrop: Backdrop, bottomClearance: Dp) -> Unit = { _, _ -> },
    content: @Composable (route: Route, insets: PaddingValues) -> Unit,
) {
    val chrome = remember { ShellChrome() }
    CompositionLocalProvider(LocalShellChrome provides chrome) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            // Werte sofort festhalten (nicht in tieferen Row/Column-Bereichen auf den Scope zugreifen).
            val wide = maxWidth >= WideLayoutMinWidth && maxHeight >= WideLayoutMinHeight
            val fullHeight = maxHeight
            ShellLayout(navigator, chrome, wide, fullHeight, overlay, content)
        }
    }
}

/**
 * Schwebende Bedienelemente, die eine Seite vorübergehend selbst stellt: z. B. ersetzt bei einer Dateiauswahl eine
 * Werkzeugleiste (Teilen, Kopieren, Löschen …) die Reiterleiste – an derselben Stelle und in derselben Höhe.
 */
@Stable
class ShellChrome {
    internal var bottomBar: (@Composable (Backdrop) -> Unit)? by mutableStateOf(null)
    internal var bottomBarOwner: String? by mutableStateOf(null)
}

val LocalShellChrome = staticCompositionLocalOf { ShellChrome() }

/**
 * Ersetzt die Reiterleiste durch [bar], solange [active] gilt und die Seite angezeigt wird. [owner] ist ein
 * eindeutiger Schlüssel der Seite (z. B. der Schlüssel ihrer Route), damit eine verschwindende Seite nicht die
 * Leiste der neuen entfernt.
 */
@Composable
fun BottomBarOverride(owner: String, active: Boolean, bar: @Composable (Backdrop) -> Unit) {
    val chrome = LocalShellChrome.current
    val currentBar by rememberUpdatedState(bar)
    DisposableEffect(owner, active) {
        if (active) {
            chrome.bottomBarOwner = owner
            chrome.bottomBar = { backdrop -> currentBar(backdrop) }
        } else if (chrome.bottomBarOwner == owner) {
            chrome.bottomBar = null
            chrome.bottomBarOwner = null
        }
        onDispose {
            if (chrome.bottomBarOwner == owner) {
                chrome.bottomBar = null
                chrome.bottomBarOwner = null
            }
        }
    }
}

@Composable
private fun ShellLayout(
    navigator: AppNavigator,
    chrome: ShellChrome,
    wide: Boolean,
    fullHeight: Dp,
    overlay: @Composable BoxScope.(backdrop: Backdrop, bottomClearance: Dp) -> Unit,
    content: @Composable (route: Route, insets: PaddingValues) -> Unit,
) {
    val backdrop = rememberBackdrop()
    val motion = Aether.motion
    val system = WindowInsets.safeDrawing.asPaddingValues()
    val dir = LocalLayoutDirection.current
    val top = system.calculateTopPadding()
    val bottom = system.calculateBottomPadding()
    val start = system.calculateStartPadding(dir)
    val end = system.calculateEndPadding(dir)
    val barGap = Spacing.m

    val contentInsets = if (wide) {
        PaddingValues(start = start + barGap + RailWidth + Spacing.s, end = end, top = top, bottom = bottom)
    } else {
        PaddingValues(start = start, end = end, top = top, bottom = bottom + barGap + TabBarHeight + Spacing.s)
    }

    val holder = rememberSaveableStateHolder()
    // Im ViewModel der Aktivität gehalten: übersteht Drehen und Größenänderungen (Auswahl, Listen bleiben).
    val stores = viewModel { RouteStoresHolder() }.stores
    // Geschlossene Seiten vergessen: gespeicherten Zustand sofort (ein noch sichtbarer Inhalt speichert dann nicht
    // mehr), ihre ViewModels erst nach dem Ausblenden – sonst bräche der Inhalt mitten in der Bewegung ab.
    //
    // Das verzögerte Freigeben läuft in einem eigenen Scope: Ein LaunchedEffect mit der Listengröße als Schlüssel würde
    // durch das Leeren der Liste selbst abgebrochen und die ViewModels nie freigeben (Auswahl und Dateibeobachter
    // blieben sonst erhalten – Befund der Durchsicht).
    val cleanupScope = rememberCoroutineScope()
    val pendingClear = remember { mutableSetOf<String>() }
    LaunchedEffect(navigator) {
        snapshotFlow { navigator.closedRoutes.toList() }.collect { keys ->
            if (keys.isEmpty()) return@collect
            navigator.closedRoutes.removeAll(keys)
            keys.forEach { holder.removeState(it) }
            pendingClear += keys
            cleanupScope.launch {
                delay(Motion.EMPHASIZED_MS + 150L)
                val open = navigator.allRoutes.map { it.key }.toSet()
                keys.filter { it !in open }.forEach {
                    stores.clear(it)
                    pendingClear -= it
                }
                keys.filter { it in open }.forEach { pendingClear -= it }
            }
        }
    }
    DisposableEffect(navigator) {
        onDispose {
            // Rahmen verschwindet (z. B. Drehen) vor Ablauf der Wartezeit: geschlossene Seiten trotzdem freigeben.
            val open = navigator.allRoutes.map { it.key }.toSet()
            pendingClear.filter { it !in open }.forEach { stores.clear(it) }
            pendingClear.clear()
        }
    }
    Box(Modifier.fillMaxSize()) {
        // 1. Hintergrund und Inhalt – zugleich Quelle der Glas-Unschärfe (deckend durch den Hintergrund).
        Box(Modifier.fillMaxSize().backdropSource(backdrop)) {
            AtmosphereBackground()
            AnimatedContent(
                targetState = navigator.current,
                transitionSpec = { transitionFor(navigator.lastMove, motion.reduced) },
                contentKey = { it.key },
                label = "screen",
            ) { route ->
                holder.SaveableStateProvider(route.key) {
                    CompositionLocalProvider(LocalViewModelStoreOwner provides stores.owner(route.key)) {
                        content(route, contentInsets)
                    }
                }
            }
        }

        // 2. Kantenübergang unter der Statusleiste.
        EdgeFade(
            top = true,
            fullHeight = fullHeight,
            modifier = Modifier.fillMaxWidth().height(top + 18.dp).align(Alignment.TopCenter),
        )

        // 3. Schwebende Navigation – oder die Werkzeugleiste, die eine Seite gerade stellt (z. B. bei einer Auswahl).
        val override = chrome.bottomBar
        if (wide) {
            GlassRail(
                items = TopLevel.entries.map { NavItem(it.label, it.icon) },
                selectedIndex = navigator.area.ordinal,
                onSelect = { navigator.select(TopLevel.entries[it]) },
                backdrop = backdrop,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = start + barGap, top = top + barGap, bottom = bottom + barGap),
            )
        }
        val bottomPadding = Modifier
            .align(Alignment.BottomCenter)
            .fillMaxWidth()
            .padding(start = if (wide) start + barGap + RailWidth + Spacing.s else start + barGap, end = end + barGap, bottom = bottom + barGap)
        AnimatedContent(
            targetState = override,
            transitionSpec = {
                (fadeIn(motion.fade(Motion.QUICK_MS)) + scaleIn(motion.standard(), initialScale = 0.96f)) togetherWith fadeOut(motion.fade(Motion.QUICK_MS))
            },
            contentKey = { it != null },
            modifier = bottomPadding,
            label = "bottomBar",
        ) { bar ->
            when {
                bar != null -> Box(Modifier.fillMaxWidth().widthIn(max = Spacing.contentMaxWidth), contentAlignment = Alignment.Center) { bar(backdrop) }
                wide -> Spacer(Modifier.fillMaxWidth())
                else -> {
                    val tabs = TopLevel.entries.filter { it != TopLevel.SETTINGS }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                        GlassTabBar(
                            items = tabs.map { NavItem(it.label, it.icon) },
                            selectedIndex = tabs.indexOf(navigator.area),
                            onSelect = { navigator.select(tabs[it]) },
                            backdrop = backdrop,
                            modifier = Modifier.weight(1f),
                        )
                        GlassCircleButton(
                            icon = TopLevel.SETTINGS.icon,
                            contentDescription = TopLevel.SETTINGS.label,
                            onClick = { navigator.select(TopLevel.SETTINGS) },
                            backdrop = backdrop,
                            selected = navigator.area == TopLevel.SETTINGS,
                            asTab = true,
                        )
                    }
                }
            }
        }

        // 4. Darüber: Fortschritt laufender Vorgänge, Rückmeldungen, Dialoge (liegen über der Navigation).
        val clearance = if (wide) bottom + barGap else bottom + barGap + TabBarHeight + Spacing.s
        overlay(backdrop, clearance)
    }
}

/**
 * Eigener ViewModel-Speicher je Seite: Jeder geöffnete Ordner hat seinen eigenen Zustand (Auswahl, Liste), und
 * beim Schließen der Seite wird er freigegeben – wie bei Navigationsbibliotheken, aber ohne zusätzliche Abhängigkeit.
 */
internal class RouteStoresHolder : ViewModel() {
    val stores = RouteViewModelStores()

    override fun onCleared() {
        stores.clearAll()
    }
}

internal class RouteViewModelStores {
    private val owners = HashMap<String, ViewModelStoreOwner>()

    fun clearAll() {
        owners.values.forEach { it.viewModelStore.clear() }
        owners.clear()
    }

    fun owner(key: String): ViewModelStoreOwner = owners.getOrPut(key) {
        val store = ViewModelStore()
        object : ViewModelStoreOwner {
            override val viewModelStore: ViewModelStore = store
        }
    }

    fun clear(key: String) {
        owners.remove(key)?.viewModelStore?.clear()
    }
}

/**
 * Übergänge: Bereichswechsel als ruhige Überblendung mit leichter Tiefe, Unterseiten gleiten von rechts
 * herein (zurück: nach rechts hinaus). Bei reduzierter Bewegung nur eine kurze Überblendung.
 */
private fun transitionFor(move: NavMove, reduced: Boolean): ContentTransform {
    if (reduced) return fadeIn(tween(Motion.REDUCED_FADE_MS)) togetherWith fadeOut(tween(Motion.REDUCED_FADE_MS))
    return when (move) {
        NavMove.AREA ->
            (fadeIn(tween(Motion.STANDARD_MS, delayMillis = 40, easing = Motion.Standard)) + scaleIn(tween(Motion.STANDARD_MS, easing = Motion.Standard), initialScale = 0.985f)) togetherWith
                fadeOut(tween(Motion.QUICK_MS, easing = Motion.Exit))
        NavMove.FORWARD ->
            (slideInHorizontally(tween(Motion.EMPHASIZED_MS, easing = Motion.Emphasized)) { it / 3 } + fadeIn(tween(Motion.STANDARD_MS))) togetherWith
                (slideOutHorizontally(tween(Motion.EMPHASIZED_MS, easing = Motion.Emphasized)) { -it / 8 } + fadeOut(tween(Motion.QUICK_MS)))
        NavMove.BACK ->
            (slideInHorizontally(tween(Motion.EMPHASIZED_MS, easing = Motion.Emphasized)) { -it / 8 } + fadeIn(tween(Motion.STANDARD_MS))) togetherWith
                (slideOutHorizontally(tween(Motion.EMPHASIZED_MS, easing = Motion.Emphasized)) { it / 3 } + fadeOut(tween(Motion.QUICK_MS)))
    }
}
