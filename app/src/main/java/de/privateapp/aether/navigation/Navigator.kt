package de.privateapp.aether.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.vector.ImageVector
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.platform.storage.MediaCategory

/*
 * Eigene, kleine Navigation (Begründung: docs/ENTSCHEIDUNGEN.md): fünf Hauptbereiche mit je eigenem Verlauf –
 * wie man es von Premium-Apps kennt. Wechselt man den Bereich, bleibt der Verlauf des vorherigen erhalten;
 * erneutes Antippen des aktiven Bereichs führt zu dessen Anfang zurück. Zurück schließt erst die Unterseite,
 * dann führt es zur Übersicht, erst dort verlässt man die App.
 */

/** Hauptbereiche (Reihenfolge = Reihenfolge in der Navigation). */
enum class TopLevel(val label: String, val icon: ImageVector) {
    HOME("Übersicht", AetherIcons.Home),
    FILES("Dateien", AetherIcons.Folder),
    STORAGE("Speicher", AetherIcons.StorageRing),
    DEVICE("Gerät", AetherIcons.Phone),
    SETTINGS("Einstellungen", AetherIcons.Sliders),
}

/** Ziele innerhalb eines Bereichs. [key] ist stabil und wird beim Speichern des Zustands verwendet. */
sealed interface Route {
    val key: String

    data class Root(val area: TopLevel) : Route {
        override val key: String get() = "root:${area.name}"
    }

    data object Licenses : Route {
        override val key: String get() = "licenses"
    }

    data object Privacy : Route {
        override val key: String get() = "privacy"
    }

    /** Ein Ordner im Dateisystem (absoluter Pfad). */
    data class Folder(val path: String) : Route {
        override val key: String get() = "folder:$path"
    }

    /** Eine Dateikategorie aus dem Medienindex (Bilder, Dokumente, Zuletzt hinzugefügt …). */
    data class Category(val category: MediaCategory) : Route {
        override val key: String get() = "category:${category.name}"
    }

    data object Search : Route {
        override val key: String get() = "search"
    }

    data object Trash : Route {
        override val key: String get() = "trash"
    }

    /** Schnellansicht einer Datei (Bild, Text, PDF). */
    data class Preview(val path: String) : Route {
        override val key: String get() = "preview:$path"
    }

    /** Geschwindigkeit, Höhe, Kompass, Satelliten. */
    data object Motion : Route {
        override val key: String get() = "motion"
    }

    companion object {
        /** Gegenstück zu [key]; unbekannte Schlüssel (z. B. nach einem Update) werden verworfen. */
        fun fromKey(key: String): Route? = when {
            key.startsWith("root:") -> TopLevel.entries.firstOrNull { it.name == key.removePrefix("root:") }?.let { Root(it) }
            key.startsWith("folder:") -> Folder(key.removePrefix("folder:"))
            key.startsWith("category:") -> MediaCategory.entries.firstOrNull { it.name == key.removePrefix("category:") }?.let { Category(it) }
            key.startsWith("preview:") -> Preview(key.removePrefix("preview:"))
            key == Licenses.key -> Licenses
            key == Privacy.key -> Privacy
            key == Search.key -> Search
            key == Trash.key -> Trash
            key == Motion.key -> Motion
            else -> null
        }
    }
}

/** Schutz einer Seite mit ungesicherten Änderungen: [ask] zeigt die Rückfrage und ruft bei „Verwerfen“ `discard` auf. */
class UnsavedGuard(val routeKey: String, val ask: (discard: () -> Unit) -> Unit)

/** Art des letzten Wechsels – bestimmt die Übergangsbewegung. */
enum class NavMove { AREA, FORWARD, BACK }

@Stable
class AppNavigator internal constructor(initialArea: TopLevel, initialStacks: Map<TopLevel, List<Route>>) {
    var area by mutableStateOf(initialArea)
        private set

    var lastMove by mutableStateOf(NavMove.AREA)
        private set

    private val stacks = mutableStateMapOf<TopLevel, List<Route>>().apply { putAll(initialStacks) }

    /** Zähler je Bereich: erhöht sich, wenn der aktive Bereich erneut angetippt wird (Bildschirm scrollt nach oben). */
    private val reselects = mutableStateMapOf<TopLevel, Int>()

    /**
     * Geschlossene Unterseiten, deren gespeicherter Zustand (z. B. Scrollposition) verworfen werden soll – beim
     * nächsten Öffnen beginnen sie oben. Der Rahmen (AetherShell) leert die Liste.
     */
    val closedRoutes = mutableStateListOf<String>()

    private fun stackOf(a: TopLevel): List<Route> = stacks[a] ?: listOf(Route.Root(a))

    val current: Route get() = stackOf(area).last()

    val canGoBack: Boolean get() = stackOf(area).size > 1 || area != TopLevel.HOME

    fun reselectCount(a: TopLevel): Int = reselects[a] ?: 0

    /**
     * Eine Seite mit ungesicherten Änderungen (z. B. Texteditor) meldet sich hier an. Würde eine Navigation sie
     * schließen (erneutes Antippen des Bereichs, Zurückspringen in der Pfadleiste), fragt stattdessen [UnsavedGuard.ask]
     * – erst nach „Verwerfen“ wird geschlossen.
     */
    var unsavedGuard: UnsavedGuard? by mutableStateOf(null)

    /** `true`, wenn das Schließen von [closing] abgefangen wurde (dann übernimmt die Rückfrage). */
    private fun intercepted(closing: List<Route>, proceed: () -> Unit): Boolean {
        val guard = unsavedGuard ?: return false
        if (closing.none { it.key == guard.routeKey }) return false
        guard.ask {
            unsavedGuard = null
            proceed()
        }
        return true
    }

    fun select(a: TopLevel) {
        if (a == area) {
            if (stackOf(a).size > 1) {
                if (intercepted(stackOf(a).drop(1)) { select(a) }) return
                lastMove = NavMove.BACK
                closedRoutes += stackOf(a).drop(1).map { it.key }
                stacks[a] = listOf(Route.Root(a))
            } else {
                reselects[a] = reselectCount(a) + 1
            }
        } else {
            lastMove = NavMove.AREA
            area = a
        }
    }

    fun push(route: Route) {
        if (stackOf(area).last().key == route.key) return
        lastMove = NavMove.FORWARD
        stacks[area] = stackOf(area) + route
    }

    /**
     * Zu einem Ziel im aktuellen Verlauf zurückspringen (z. B. Pfadleiste eines Ordners). Ist es nicht im Verlauf,
     * wird es geöffnet.
     */
    fun popTo(route: Route) {
        val stack = stackOf(area)
        val index = stack.indexOfLast { it.key == route.key }
        if (index < 0) {
            push(route)
            return
        }
        if (index == stack.lastIndex) return
        if (intercepted(stack.drop(index + 1)) { popTo(route) }) return
        lastMove = NavMove.BACK
        closedRoutes += stack.drop(index + 1).map { it.key }
        stacks[area] = stack.take(index + 1)
    }

    /** Ersetzt das oberste Ziel (z. B. wenn ein geöffneter Ordner umbenannt wurde). */
    fun replaceTop(route: Route) {
        val stack = stackOf(area)
        if (stack.size <= 1) return
        closedRoutes += stack.last().key
        stacks[area] = stack.dropLast(1) + route
    }

    /**
     * Nach Umbenennen/Verschieben: geöffnete Seiten von [from] (und darin) zeigen auf den neuen Ort [to] – der Verlauf
     * bleibt erhalten, statt dass Seiten verschwinden.
     */
    fun remapPaths(from: String, to: String) {
        fun remap(p: String) = when {
            p == from -> to
            p.startsWith("$from/") -> to + p.removePrefix(from)
            else -> null
        }
        for (a in TopLevel.entries) {
            val stack = stackOf(a)
            var changed = false
            val next = stack.map { r ->
                val mapped = when (r) {
                    is Route.Folder -> remap(r.path)?.let { Route.Folder(it) }
                    is Route.Preview -> remap(r.path)?.let { Route.Preview(it) }
                    else -> null
                }
                if (mapped != null) {
                    changed = true
                    closedRoutes += r.key
                    mapped
                } else {
                    r
                }
            }
            if (changed) stacks[a] = next
        }
    }

    /** Alle Ziele aller Verläufe (z. B. um nach dem Löschen eines Ordners dessen Seiten zu schließen). */
    val allRoutes: List<Route> get() = TopLevel.entries.flatMap { stackOf(it) }

    /** Schließt in allen Verläufen Seiten, für die [predicate] gilt (nie den Anfang eines Bereichs). */
    fun closeWhere(predicate: (Route) -> Boolean) {
        for (a in TopLevel.entries) {
            val stack = stackOf(a)
            val firstBad = stack.indexOfFirst { it !is Route.Root && predicate(it) }
            if (firstBad > 0) {
                closedRoutes += stack.drop(firstBad).map { it.key }
                stacks[a] = stack.take(firstBad)
                if (a == area) lastMove = NavMove.BACK
            }
        }
    }

    /** `true`, wenn etwas geschlossen wurde; `false` = Anfang der Übersicht (System schließt die App). */
    fun back(): Boolean {
        val stack = stackOf(area)
        return when {
            stack.size > 1 -> {
                lastMove = NavMove.BACK
                closedRoutes += stack.last().key
                stacks[area] = stack.dropLast(1)
                true
            }
            area != TopLevel.HOME -> {
                lastMove = NavMove.AREA
                area = TopLevel.HOME
                true
            }
            else -> false
        }
    }

    /**
     * Zustand als einfache Liste (Bereich + Verlauf je Bereich) – überlebt Drehen und Prozessende. Trennzeichen ist
     * das Steuerzeichen „Unit Separator“, das in Dateipfaden nicht vorkommt.
     */
    internal fun snapshot(): ArrayList<String> =
        ArrayList(listOf(area.name) + TopLevel.entries.map { a -> stackOf(a).joinToString(SEPARATOR) { it.key } })

    companion object {
        private const val SEPARATOR = "\u001F"

        internal fun restore(saved: List<String>): AppNavigator {
            val area = TopLevel.entries.firstOrNull { it.name == saved.firstOrNull() } ?: TopLevel.HOME
            val stacks = TopLevel.entries.mapIndexed { i, a ->
                val routes = saved.getOrNull(i + 1).orEmpty().split(SEPARATOR).mapNotNull { Route.fromKey(it) }
                // Ein Verlauf beginnt immer mit dem Anfang seines Bereichs.
                a to (listOf<Route>(Route.Root(a)) + routes.dropWhile { it is Route.Root })
            }.toMap()
            return AppNavigator(area, stacks)
        }

        val StateSaver: Saver<AppNavigator, ArrayList<String>> = Saver(save = { it.snapshot() }, restore = { restore(it) })
    }
}

/** Navigation für tiefer liegende Bausteine (z. B. Dateiaktionen, die einen Ordner oder eine Vorschau öffnen). */
val LocalAppNavigator = staticCompositionLocalOf<AppNavigator> { error("AppNavigator nicht bereitgestellt") }

@Composable
fun rememberAppNavigator(): AppNavigator = rememberSaveable(saver = AppNavigator.StateSaver) {
    AppNavigator(TopLevel.HOME, TopLevel.entries.associateWith { listOf(Route.Root(it)) })
}
