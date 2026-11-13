package de.privateapp.aether.ui.files

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.files.Listing
import de.privateapp.aether.navigation.LocalAppNavigator
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.ui.common.ScreenList

/**
 * Ein Ordner – wie in „Dateien“ von Apple: Pfadleiste, Liste oder Raster, Menü für Darstellung, Sortierung und
 * versteckte Objekte, Auswahl mit Werkzeugleiste, Aktionen je Objekt. Leere, gesperrte und verschwundene Ordner
 * werden erklärt statt als leere Fläche gezeigt.
 */
@Composable
fun FolderScreen(graph: AppGraph, path: String, insets: PaddingValues, onBack: () -> Unit) {
    val vm: FolderViewModel = viewModel { FolderViewModel(graph, path) }
    val state by vm.state.collectAsStateWithLifecycle()
    val navigator = LocalAppNavigator.current
    val actions = fileActions
    val selection = vm.selection
    val selecting = selection != null

    LifecycleResumeEffect(vm) {
        vm.setVisible(true)
        onPauseOrDispose { vm.setVisible(false) }
    }
    BackHandler(enabled = selecting) { vm.endSelection() }
    EndSelectionOnOperation(graph, selection, vm::endSelection)
    SelectionToolbar(owner = "folder:$path", active = selecting, selected = vm.selectedEntries(), onDone = vm::endSelection)

    val title = FolderViewModel.title(path, state.root)
    val listing = state.listing
    val viewMode = state.prefs.viewMode
    val subtitle = when (listing) {
        is Listing.Entries -> buildString {
            append(if (state.entries.size == 1) "1 Objekt" else "${state.entries.size} Objekte")
            if (state.hiddenCount > 0) append(" · ${state.hiddenCount} versteckt")
            if (state.root?.readOnly == true) append(" · nur lesbar")
        }
        null -> "Wird gelesen …"
        else -> null
    }

    if (listing != null && listing !is Listing.Entries) {
        ScreenList(insets, reselect = 0) {
            item(key = "header") {
                BrowserHeader(title, null, onBack, null, {}, {}, false) {}
            }
            item(key = "problem") { ListingProblem(listing, onBack) }
        }
        return
    }

    BrowserGrid(insets, viewMode) {
        fullWidth("header") {
            Column {
                BrowserHeader(
                    title = title,
                    subtitle = subtitle,
                    onBack = onBack,
                    selectionCount = selection?.size,
                    onEndSelection = vm::endSelection,
                    onSelectAll = vm::selectAll,
                    allSelected = selection != null && selection.size == state.entries.size && state.entries.isNotEmpty(),
                ) {
                    BrowserMenu(
                        sort = state.prefs.sort,
                        onSort = { vm.setSort(it) },
                        viewMode = viewMode,
                        onViewMode = { vm.setViewMode(it) },
                        showHidden = state.prefs.showHidden,
                        onShowHidden = { vm.setShowHidden(it) },
                        extra = listOf(
                            MenuEntry("Auswählen", AetherIcons.SelectAll, enabled = state.entries.isNotEmpty()) { vm.startSelection() },
                            MenuEntry("Neuer Ordner", AetherIcons.FolderPlus, enabled = state.writable) { actions.newFolder(path) },
                            MenuEntry(if (state.isFavorite) "Aus Favoriten entfernen" else "Zu Favoriten", if (state.isFavorite) AetherIcons.StarFilled else AetherIcons.Star) {
                                actions.toggleFavorite(path)
                            },
                            MenuEntry("Informationen", AetherIcons.Info, enabled = state.directory != null) { state.directory?.let(actions::info) },
                        ),
                    )
                }
                PathBar(
                    segments = FolderViewModel.segments(path, state.root),
                    onSelect = { navigator.popTo(Route.Folder(it)) },
                    modifier = Modifier.padding(top = Spacing.s),
                )
                if (state.root?.readOnly == true) {
                    Spacer(Modifier.height(Spacing.s))
                    Notice(
                        title = "Nur lesbar",
                        message = "Android hat diesen Speicher schreibgeschützt eingebunden (z. B. Schreibschutz-Schalter der SD-Karte oder ein Dateisystem, das Android nur lesen kann). Kopieren von hier ist möglich, Ändern nicht.",
                        tone = Tone.WARNING,
                    )
                }
                Spacer(Modifier.height(Spacing.s))
            }
        }
        if (listing is Listing.Entries && state.entries.isEmpty()) {
            fullWidth("empty") {
                EmptyState(
                    icon = AetherIcons.Folder,
                    title = "Dieser Ordner ist leer",
                    message = if (state.hiddenCount > 0) {
                        "Er enthält ${state.hiddenCount} versteckte(s) Objekt(e). Über das Menü oben lassen sie sich einblenden."
                    } else {
                        "Kopiere oder verschiebe Dateien hierher – oder lege einen neuen Ordner an."
                    },
                    tone = Tone.ACCENT,
                    action = if (state.writable) {
                        { PillButton("Neuer Ordner", onClick = { actions.newFolder(path) }, icon = AetherIcons.FolderPlus) }
                    } else {
                        null
                    },
                )
            }
        }
        fileItems(
            entries = state.entries,
            viewMode = viewMode,
            selection = selection.orEmpty(),
            selecting = selecting,
            nowMillis = state.now,
            onOpen = actions::open,
            onToggle = vm::toggle,
            onStartSelection = vm::startSelection,
            onMore = { actions.showActions(listOf(it)) },
        )
    }
}

/** Ordner nicht lesbar, verschwunden oder gesperrt – mit ehrlicher Erklärung. */
@Composable
private fun ListingProblem(listing: Listing, onBack: () -> Unit) {
    when (listing) {
        is Listing.AccessDenied -> EmptyState(
            icon = AetherIcons.Lock,
            title = if (listing.protectedBySystem) "Von Android gesperrt" else "Kein Zugriff",
            message = if (listing.protectedBySystem) {
                "Seit Android 11 darf keine App die Ordner „Android/data“ und „Android/obb“ anderer Apps lesen – auch ein Dateimanager mit „Zugriff auf alle Dateien“ nicht. Die Daten gehören der jeweiligen App."
            } else {
                "Android erlaubt ORBIT nicht, diesen Ordner zu lesen. Prüfe unter „Dateien“, ob der Zugriff auf alle Dateien noch erlaubt ist."
            },
            tone = Tone.WARNING,
        )
        Listing.NotFound -> EmptyState(
            icon = AetherIcons.Folder,
            title = "Ordner nicht mehr vorhanden",
            message = "Er wurde gelöscht, verschoben oder der Speicher (z. B. die SD-Karte) wurde entfernt.",
            tone = Tone.WARNING,
            action = { PillButton("Zurück", onClick = onBack, icon = AetherIcons.ChevronLeft) },
        )
        Listing.NotADirectory -> EmptyState(
            icon = FileKind.OTHER.icon(),
            title = "Kein Ordner",
            message = "An dieser Stelle liegt inzwischen eine Datei.",
            tone = Tone.WARNING,
            action = { PillButton("Zurück", onClick = onBack, icon = AetherIcons.ChevronLeft) },
        )
        is Listing.Failed -> EmptyState(
            icon = AetherIcons.Warning,
            title = "Ordner konnte nicht gelesen werden",
            message = listing.detail,
            tone = Tone.CRITICAL,
        )
        is Listing.Entries -> Unit
    }
}
