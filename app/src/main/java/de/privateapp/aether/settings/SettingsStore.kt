package de.privateapp.aether.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import de.privateapp.aether.model.appearance.AccentChoice
import de.privateapp.aether.model.appearance.AppearanceCodec
import de.privateapp.aether.model.appearance.AppearanceSettings
import de.privateapp.aether.model.appearance.EffectIntensity
import de.privateapp.aether.model.appearance.ThemeStyle
import de.privateapp.aether.files.SortKey
import de.privateapp.aether.files.SortOrder
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import java.io.IOException

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/**
 * Einstellungen, lokal gespeichert (DataStore, nur auf diesem Gerät; von der Sicherung ausgenommen –
 * siehe AndroidManifest `allowBackup`). Unbekannte oder beschädigte Werte fallen auf die Vorgabe zurück.
 */
class SettingsStore(context: Context) {
    private val store = context.applicationContext.settingsDataStore

    val appearance: Flow<AppearanceSettings> = store.data
        .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e }
        .map { read(it) }
        .distinctUntilChanged()

    suspend fun setTheme(theme: ThemeStyle) = update { it.copy(theme = theme) }

    suspend fun setAccent(accent: AccentChoice) = update { it.copy(accent = accent) }

    suspend fun setIntensity(intensity: EffectIntensity) = update { it.copy(intensity = intensity) }

    suspend fun setReduceMotion(reduce: Boolean) = update { it.copy(reduceMotion = reduce) }

    suspend fun setHaptics(enabled: Boolean) = update { it.copy(haptics = enabled) }

    suspend fun resetAppearance() = update { AppearanceSettings.Default }

    // --- Dateien ------------------------------------------------------------------------------------------------

    val files: Flow<FilesPrefs> = store.data
        .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e }
        .map { readFiles(it) }
        .distinctUntilChanged()

    suspend fun setViewMode(mode: ViewMode, forMedia: Boolean) = store.edit {
        it[if (forMedia) MEDIA_VIEW_MODE else VIEW_MODE] = mode.name
    }

    suspend fun setSort(order: SortOrder) = store.edit {
        it[SORT_KEY] = order.key.name
        it[SORT_ASCENDING] = order.ascending
    }

    suspend fun setShowHidden(show: Boolean) = store.edit { it[SHOW_HIDDEN] = show }

    suspend fun toggleFavorite(path: String) = store.edit {
        val list = decodeList(it[FAVORITES])
        it[FAVORITES] = encodeList(if (path in list) list - path else list + path)
    }

    suspend fun removeFavorite(path: String) = store.edit { it[FAVORITES] = encodeList(decodeList(it[FAVORITES]) - path) }

    /** Favoriten, die gelöscht wurden oder in gelöschten Ordnern lagen, entfernen. */
    suspend fun removeFavoritesUnder(paths: Collection<String>) {
        if (paths.isEmpty()) return
        store.edit {
            it[FAVORITES] = encodeList(decodeList(it[FAVORITES]).filterNot { f -> paths.any { r -> f == r || f.startsWith("$r/") } })
        }
    }

    /** Ersetzt Pfade nach Umbenennen/Verschieben (Favoriten und „Zuletzt geöffnet“ zeigen weiter auf das Richtige). */
    suspend fun movePaths(from: String, to: String) = store.edit {
        fun remap(p: String) = when {
            p == from -> to
            p.startsWith("$from/") -> to + p.removePrefix(from)
            else -> p
        }
        it[FAVORITES] = encodeList(decodeList(it[FAVORITES]).map(::remap).distinct())
        it[RECENT_FILES] = encodeList(decodeList(it[RECENT_FILES]).map(::remap).distinct())
    }

    suspend fun addRecentSearch(text: String) {
        val t = text.trim()
        if (t.isEmpty()) return
        store.edit { it[RECENT_SEARCHES] = encodeList((listOf(t) + decodeList(it[RECENT_SEARCHES]).filterNot { s -> s.equals(t, true) }).take(8)) }
    }

    suspend fun clearRecentSearches() = store.edit { it.remove(RECENT_SEARCHES) }

    suspend fun addRecentFile(path: String) = store.edit {
        it[RECENT_FILES] = encodeList((listOf(path) + (decodeList(it[RECENT_FILES]) - path)).take(20))
    }

    suspend fun removeRecentFiles(paths: Collection<String>) = store.edit {
        it[RECENT_FILES] = encodeList(decodeList(it[RECENT_FILES]).filterNot { p -> paths.any { r -> p == r || p.startsWith("$r/") } })
    }

    suspend fun clearRecentFiles() = store.edit { it.remove(RECENT_FILES) }

    /** Wurde schon einmal nach Benachrichtigungen gefragt (für den Fortschritt langer Vorgänge)? Nur einmal fragen. */
    val notificationsAsked: Flow<Boolean> = store.data
        .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e }
        .map { it[NOTIFICATIONS_ASKED] ?: false }
        .distinctUntilChanged()

    suspend fun setNotificationsAsked() = store.edit { it[NOTIFICATIONS_ASKED] = true }

    private fun readFiles(p: Preferences) = FilesPrefs(
        viewMode = ViewMode.entries.firstOrNull { it.name == p[VIEW_MODE] } ?: ViewMode.LIST,
        mediaViewMode = ViewMode.entries.firstOrNull { it.name == p[MEDIA_VIEW_MODE] } ?: ViewMode.GRID,
        sort = SortOrder(
            key = SortKey.entries.firstOrNull { it.name == p[SORT_KEY] } ?: SortKey.NAME,
            ascending = p[SORT_ASCENDING] ?: true,
        ),
        showHidden = p[SHOW_HIDDEN] ?: false,
        favorites = decodeList(p[FAVORITES]),
        recentSearches = decodeList(p[RECENT_SEARCHES]),
        recentFiles = decodeList(p[RECENT_FILES]),
    )

    private suspend fun update(transform: (AppearanceSettings) -> AppearanceSettings) {
        store.edit { prefs ->
            val next = transform(read(prefs))
            prefs[THEME] = next.theme.name
            prefs[ACCENT] = next.accent.name
            prefs[INTENSITY] = next.intensity.name
            prefs[REDUCE_MOTION] = next.reduceMotion
            prefs[HAPTICS] = next.haptics
        }
    }

    private fun read(p: Preferences) = AppearanceSettings(
        theme = AppearanceCodec.theme(p[THEME]),
        accent = AppearanceCodec.accent(p[ACCENT]),
        intensity = AppearanceCodec.intensity(p[INTENSITY]),
        reduceMotion = p[REDUCE_MOTION] ?: AppearanceSettings.Default.reduceMotion,
        haptics = p[HAPTICS] ?: AppearanceSettings.Default.haptics,
    )

    private companion object {
        val THEME = stringPreferencesKey("appearance.theme")
        val ACCENT = stringPreferencesKey("appearance.accent")
        val INTENSITY = stringPreferencesKey("appearance.intensity")
        val REDUCE_MOTION = booleanPreferencesKey("appearance.reduceMotion")
        val HAPTICS = booleanPreferencesKey("appearance.haptics")

        val VIEW_MODE = stringPreferencesKey("files.viewMode")
        val MEDIA_VIEW_MODE = stringPreferencesKey("files.mediaViewMode")
        val SORT_KEY = stringPreferencesKey("files.sortKey")
        val SORT_ASCENDING = booleanPreferencesKey("files.sortAscending")
        val SHOW_HIDDEN = booleanPreferencesKey("files.showHidden")
        val FAVORITES = stringPreferencesKey("files.favorites")
        val RECENT_SEARCHES = stringPreferencesKey("files.recentSearches")
        val RECENT_FILES = stringPreferencesKey("files.recentFiles")
        val NOTIFICATIONS_ASKED = booleanPreferencesKey("files.notificationsAsked")

        /** Listen als ein Text mit dem Steuerzeichen „Record Separator“, das in Pfaden und Suchtexten nicht vorkommt. */
        private const val LIST_SEPARATOR = "\u001E"

        fun encodeList(list: List<String>): String = list.joinToString(LIST_SEPARATOR)

        fun decodeList(text: String?): List<String> =
            if (text.isNullOrEmpty()) emptyList() else text.split(LIST_SEPARATOR).filter { it.isNotEmpty() }
    }
}

/** Darstellung von Ordnern und Kategorien. */
enum class ViewMode(val label: String) {
    LIST("Liste"),
    GRID("Raster"),
}

/** Einstellungen der Dateiverwaltung. */
data class FilesPrefs(
    /** Ansicht für Ordner, Suche und Dokument-Kategorien. */
    val viewMode: ViewMode = ViewMode.LIST,
    /** Ansicht für Bilder- und Video-Kategorien (Vorgabe Raster wie in Fotos-Apps). */
    val mediaViewMode: ViewMode = ViewMode.GRID,
    val sort: SortOrder = SortOrder(),
    val showHidden: Boolean = false,
    val favorites: List<String> = emptyList(),
    val recentSearches: List<String> = emptyList(),
    val recentFiles: List<String> = emptyList(),
)
