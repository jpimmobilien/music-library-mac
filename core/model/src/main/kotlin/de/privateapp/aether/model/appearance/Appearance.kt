package de.privateapp.aether.model.appearance

/*
 * Darstellungs-Einstellungen als reine Kotlin-Typen: gespeichert werden nur die Namen der Einträge.
 * Unbekannte oder fehlende Werte (z. B. nach einem Update) fallen auf die Vorgabe zurück.
 */

/** Grundlegendes Design. */
enum class ThemeStyle(val label: String, val description: String) {
    ADAPTIVE("Adaptiv", "Hell oder dunkel wie Android – mit Liquid Glass"),
    GLASS_LIGHT("Liquid Glass Hell", "Lichte, räumliche Glasflächen"),
    GLASS_DARK("Liquid Glass Dunkel", "Tiefe, leuchtende Glasflächen"),
    MINIMAL_LIGHT("Minimal Hell", "Klare, deckende Flächen ohne Glas"),
    DEEP_DARK("Deep Dark", "Echtes Schwarz für OLED-Displays"),
}

/** Akzentfarbe für Bedienelemente, Auswahl und Diagramme. Statusfarben (Warnung, Fehler) bleiben fest. */
enum class AccentChoice(val label: String) {
    OCEAN("Ocean Blue"),
    ARCTIC("Arctic Cyan"),
    VIOLET("Violet"),
    EMERALD("Emerald"),
    AMBER("Amber"),
    ROSE("Rose"),
    GRAPHITE("Graphite"),

    /** Systemfarbe aus dem Hintergrundbild (Material You, Android 12+). */
    SYSTEM("Systemfarbe"),
}

/** Stärke der visuellen Effekte. „Minimal“ ist zugleich der Leistungsmodus. */
enum class EffectIntensity(val label: String, val description: String) {
    MINIMAL("Minimal", "Ohne Unschärfe und Lichteffekte – schont Akku und Leistung"),
    BALANCED("Ausgewogen", "Glas für schwebende Leisten, ruhige Flächen im Inhalt"),
    IMMERSIVE("Immersiv", "Kräftigere Tiefe, mehr Licht und Transparenz"),
}

data class AppearanceSettings(
    val theme: ThemeStyle = ThemeStyle.ADAPTIVE,
    val accent: AccentChoice = AccentChoice.OCEAN,
    val intensity: EffectIntensity = EffectIntensity.BALANCED,
    /** Bewegung zusätzlich zur Android-Einstellung „Animationen entfernen“ reduzieren. */
    val reduceMotion: Boolean = false,
) {
    companion object {
        val Default = AppearanceSettings()
    }
}

/** Speicherformat: Namen der Einträge ↔ Werte, tolerant gegenüber Unbekanntem. */
object AppearanceCodec {
    fun theme(name: String?): ThemeStyle = ThemeStyle.entries.firstOrNull { it.name == name } ?: AppearanceSettings.Default.theme

    fun accent(name: String?): AccentChoice = AccentChoice.entries.firstOrNull { it.name == name } ?: AppearanceSettings.Default.accent

    fun intensity(name: String?): EffectIntensity =
        EffectIntensity.entries.firstOrNull { it.name == name } ?: AppearanceSettings.Default.intensity
}
