package de.privateapp.aether.ui.settings

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.BuildConfig
import de.privateapp.aether.design.AccentSwatch
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherColors
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.EffectConfig
import de.privateapp.aether.design.InfoRow
import de.privateapp.aether.design.LocalResolvedAccent
import de.privateapp.aether.design.LocalSystemReducedMotion
import de.privateapp.aether.design.NavRow
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.PaletteSpec
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.ScreenTitle
import de.privateapp.aether.design.SectionLabel
import de.privateapp.aether.design.SegmentedControl
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.ThemeTile
import de.privateapp.aether.design.ToggleRow
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.appearance.AccentChoice
import de.privateapp.aether.model.appearance.AppearanceSettings
import de.privateapp.aether.model.appearance.EffectIntensity
import de.privateapp.aether.model.appearance.ThemeStyle
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.settings.FilesPrefs
import de.privateapp.aether.settings.SettingsStore
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import de.privateapp.aether.ui.common.GridRows
import de.privateapp.aether.ui.common.ScreenList
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class SettingsViewModel(private val store: SettingsStore, loaded: StateFlow<AppearanceSettings?>) : ViewModel() {
    /** Bereits beim Start geladen – die Auswahl springt beim Öffnen nicht von der Vorgabe auf den echten Wert. */
    val appearance: StateFlow<AppearanceSettings?> = loaded

    fun setTheme(t: ThemeStyle) = viewModelScope.launch { store.setTheme(t) }
    fun setAccent(a: AccentChoice) = viewModelScope.launch { store.setAccent(a) }
    fun setIntensity(i: EffectIntensity) = viewModelScope.launch { store.setIntensity(i) }
    fun setReduceMotion(r: Boolean) = viewModelScope.launch { store.setReduceMotion(r) }
    fun setHaptics(h: Boolean) = viewModelScope.launch { store.setHaptics(h) }
    fun reset() = viewModelScope.launch { store.resetAppearance() }

    fun setShowHidden(show: Boolean) = viewModelScope.launch { store.setShowHidden(show) }
    fun clearRecentFiles() = viewModelScope.launch { store.clearRecentFiles() }
    fun clearRecentSearches() = viewModelScope.launch { store.clearRecentSearches() }
}

/**
 * Einstellungen: Darstellung (Theme, Akzent, Effektstärke, Bewegung), Dateien, Datenschutz, Lizenzen. Jede Änderung
 * wird sofort sichtbar und lokal gespeichert.
 */
@Composable
fun SettingsScreen(graph: AppGraph, insets: PaddingValues, reselect: Int, onNavigate: (Route) -> Unit) {
    val vm: SettingsViewModel = viewModel { SettingsViewModel(graph.settings, graph.appearance) }
    val loaded by vm.appearance.collectAsStateWithLifecycle()
    val settings = loaded ?: AppearanceSettings.Default
    val colors = Aether.colors
    val type = Aether.type
    val systemDark = isSystemInDarkTheme()
    val lowRam = !Aether.effects.blur && Aether.effects.glassMaterial

    ScreenList(insets, reselect) {
        item(key = "title") { ScreenTitle("Einstellungen", subtitle = "Darstellung, Dateien, Datenschutz und Informationen") }

        item(key = "s-appearance") { SectionLabel("Darstellung") }
        item(key = "theme") {
            Panel {
                PanelHeader(icon = AetherIcons.Contrast, title = "Design", subtitle = "Fünf vollständig gestaltete Themes")
                Spacer(Modifier.height(Spacing.l))
                GridRows(ThemeStyle.entries, columns = 2) { theme, cellModifier ->
                    val base = PaletteSpec.base(theme, systemDark)
                    val accentArgb = if (settings.accent == AccentChoice.SYSTEM) {
                        colors.accent.toArgb().toLong() and 0xFFFFFFFFL
                    } else {
                        (PaletteSpec.accents[settings.accent] ?: PaletteSpec.fallbackAccent).forDark(base.isDark)
                    }
                    val preview = remember(base, accentArgb, settings.intensity) {
                        AetherColors.from(base, accentArgb, EffectConfig.of(base, settings.intensity, lowRamDevice = false))
                    }
                    ThemeTile(
                        preview = preview,
                        title = theme.label,
                        description = theme.description,
                        selected = settings.theme == theme,
                        onClick = { vm.setTheme(theme) },
                        modifier = cellModifier,
                    )
                }
            }
        }
        item(key = "accent") {
            val resolved = LocalResolvedAccent.current
            val context = LocalContext.current
            val dark = colors.isDark
            // Vorschau der Systemfarbe (Material You) – auch wenn sie gerade nicht gewählt ist.
            val systemAccent = remember(context, dark) {
                try {
                    if (dark) dynamicDarkColorScheme(context).primary else dynamicLightColorScheme(context).primary
                } catch (e: RuntimeException) {
                    null
                }
            }
            Panel {
                PanelHeader(icon = AetherIcons.Sparkle, title = "Akzentfarbe", subtitle = "Für Bedienelemente, Auswahl und Diagramme")
                Spacer(Modifier.height(Spacing.m))
                GridRows(AccentChoice.entries, columns = 4) { accent, cellModifier ->
                    val swatch = if (accent == AccentChoice.SYSTEM) {
                        systemAccent ?: colors.textTertiary
                    } else {
                        AetherColors.argb((PaletteSpec.accents[accent] ?: PaletteSpec.fallbackAccent).forDark(colors.isDark))
                    }
                    AccentSwatch(
                        color = swatch,
                        label = accent.label,
                        selected = settings.accent == accent,
                        onClick = { vm.setAccent(accent) },
                        modifier = cellModifier,
                    )
                }
                if (settings.accent == AccentChoice.SYSTEM && resolved.systemAccentRejected) {
                    Spacer(Modifier.height(Spacing.m))
                    Notice(
                        title = "Systemfarbe zu kontrastarm",
                        message = "Die Farbe aus deinem Hintergrundbild wäre in diesem Theme nicht gut lesbar. ORBIT verwendet deshalb Ocean Blue.",
                        tone = Tone.INFO,
                    )
                }
                Spacer(Modifier.height(Spacing.s))
                Text(
                    "Warn- und Fehlerfarben bleiben unabhängig vom Akzent gleich und erscheinen immer mit Symbol und Text.",
                    color = colors.textSecondary,
                    style = type.footnote,
                )
            }
        }
        item(key = "intensity") {
            Panel {
                PanelHeader(icon = AetherIcons.Layers, title = "Effektstärke", subtitle = "Unschärfe, Transparenz, Licht und Bewegung")
                Spacer(Modifier.height(Spacing.l))
                SegmentedControl(
                    options = EffectIntensity.entries,
                    selected = settings.intensity,
                    onSelect = { vm.setIntensity(it) },
                    label = { it.label },
                )
                Spacer(Modifier.height(Spacing.s))
                Text(settings.intensity.description, color = colors.textSecondary, style = type.footnote)
                if (settings.theme == ThemeStyle.MINIMAL_LIGHT && settings.intensity != EffectIntensity.MINIMAL) {
                    Spacer(Modifier.height(Spacing.s))
                    Text("„Minimal Hell“ verzichtet bewusst auf Glas – hier wirkt die Effektstärke nur auf Bewegung und Atmosphäre.", color = colors.textTertiary, style = type.footnote)
                }
                if (lowRam && settings.intensity != EffectIntensity.MINIMAL) {
                    Spacer(Modifier.height(Spacing.s))
                    Text("Dieses Gerät meldet wenig Arbeitsspeicher – die Echtzeit-Unschärfe bleibt deshalb aus.", color = colors.textTertiary, style = type.footnote)
                }
            }
        }
        item(key = "motion") {
            val systemReduced = LocalSystemReducedMotion.current
            Panel {
                ToggleRow(
                    title = "Bewegung reduzieren",
                    description = "Übergänge werden kurze Überblendungen, Werte springen ohne Gleiten.",
                    checked = settings.reduceMotion || systemReduced,
                    onCheckedChange = { vm.setReduceMotion(it) },
                    enabled = !systemReduced,
                    note = if (systemReduced) "Android hat „Animationen entfernen“ aktiviert – die Bewegung ist bereits reduziert." else null,
                )
                Spacer(Modifier.height(Spacing.s))
                ToggleRow(
                    title = "Haptisches Feedback",
                    description = "Kurzes Tippen beim Wechsel der Bereiche, Bestätigung nach abgeschlossenen Dateivorgängen. Die Vibrationseinstellung von Android hat Vorrang.",
                    checked = settings.haptics,
                    onCheckedChange = { vm.setHaptics(it) },
                )
            }
        }
        item(key = "reset") {
            Column(Modifier.fillMaxWidth()) {
                PillButton("Darstellung zurücksetzen", onClick = { vm.reset() }, icon = AetherIcons.Refresh)
            }
        }

        item(key = "s-files") { SectionLabel("Dateien") }
        item(key = "files") {
            val prefs by graph.filesPrefs.collectAsStateWithLifecycle()
            val p = prefs ?: FilesPrefs()
            Panel {
                ToggleRow(
                    title = "Versteckte Objekte zeigen",
                    description = "Dateien und Ordner, deren Name mit einem Punkt beginnt (z. B. „.thumbnails“). Meist Daten von Apps.",
                    checked = p.showHidden,
                    onCheckedChange = { vm.setShowHidden(it) },
                )
                Spacer(Modifier.height(Spacing.s))
                InfoRow("Zuletzt geöffnet", if (p.recentFiles.isEmpty()) "Leer" else "${p.recentFiles.size} Einträge", caption = "Nur auf diesem Gerät gespeichert")
                InfoRow("Suchverlauf", if (p.recentSearches.isEmpty()) "Leer" else "${p.recentSearches.size} Einträge")
                Spacer(Modifier.height(Spacing.s))
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    PillButton("Verlauf löschen", onClick = { vm.clearRecentFiles(); vm.clearRecentSearches() }, icon = AetherIcons.Trash, enabled = p.recentFiles.isNotEmpty() || p.recentSearches.isNotEmpty())
                }
            }
        }

        item(key = "s-privacy") { SectionLabel("Datenschutz") }
        item(key = "privacy") {
            Panel(contentPadding = PaddingValues(horizontal = Spacing.m, vertical = Spacing.s)) {
                NavRow(
                    title = "Datenschutz und Berechtigungen",
                    subtitle = "Was ORBIT darf – und was nicht",
                    icon = AetherIcons.Shield,
                    onClick = { onNavigate(Route.Privacy) },
                )
            }
        }

        item(key = "s-about") { SectionLabel("Über") }
        item(key = "about") {
            Panel {
                InfoRow("App", BuildConfig.APP_NAME)
                InfoRow("Version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", caption = "Phase 3 – Dateimanager und Bewegung")
                Spacer(Modifier.height(Spacing.xs))
                NavRow(title = "Lizenzen", subtitle = "Schrift Inter (SIL Open Font License)", icon = AetherIcons.Document, onClick = { onNavigate(Route.Licenses) })
            }
        }
    }
}
