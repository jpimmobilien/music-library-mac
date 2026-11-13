package de.privateapp.aether.platform.storage

/**
 * Kategorien der Dateiübersicht. Sie werden aus dem Medienindex von Android (MediaStore) gelesen, der mit
 * „Zugriff auf alle Dateien“ sämtliche Dateien des gemeinsamen Speichers und eingebundener SD-Karten/USB-Speicher
 * enthält – nicht nur Medien.
 */
enum class MediaCategory(val label: String, val description: String) {
    IMAGES("Bilder", "Fotos, Screenshots und Grafiken"),
    VIDEOS("Videos", "Aufnahmen und Filme"),
    MUSIC("Musik", "Von Android als Musik erkannte Titel"),
    AUDIO("Audio", "Sprachaufnahmen, Töne und weitere Audiodateien"),
    DOCUMENTS("Dokumente", "Text-, Tabellen- und Präsentationsdokumente"),
    PDF("PDFs", "PDF-Dokumente"),
    TEXT("Textdateien", "Text, Markdown, CSV, JSON, Protokolle"),
    ARCHIVES("Archive", "ZIP, RAR, 7z, TAR und weitere"),
    APKS("App-Pakete", "Installationsdateien (APK)"),
    DOWNLOADS("Downloads", "Inhalt des Download-Ordners"),
    RECENT("Zuletzt hinzugefügt", "Neueste Dateien der letzten 30 Tage"),
}
