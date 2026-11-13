pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

// ---------------------------------------------------------------------------------------------
// Android-SDK finden (gegen „SDK location not found“) – ohne einen Pfad im Projekt festzuschreiben.
//
// Normalerweise trägt Android Studio den SDK-Pfad beim Öffnen bzw. Synchronisieren selbst in die
// Datei local.properties ein. Diese Datei ist rechnerspezifisch und gehört deshalb NICHT ins ZIP.
// Fehlt sie oder zeigt sie auf einen ungültigen Ordner (z. B. Projekt neu entpackt oder Bau mit
// ./gradlew im Terminal), sucht dieser Block das SDK am Standardort DIESES Rechners
// (macOS: ~/Library/Android/sdk) und legt local.properties an. Ein gültiger Eintrag in
// local.properties sowie ANDROID_HOME/ANDROID_SDK_ROOT haben immer Vorrang; andere Einträge in
// local.properties bleiben erhalten. Außerhalb des Projektordners wird nichts verändert.
// (Gleicher Block wie in Musikbibliothek 1.3.0 und DriveGlass 1.1.0.)
// ---------------------------------------------------------------------------------------------
run {
    val localProperties = settingsDir.resolve("local.properties")
    val props = java.util.Properties()
    if (localProperties.isFile) localProperties.inputStream().use { props.load(it) }
    fun isSdk(path: String?): Boolean = !path.isNullOrBlank() && java.io.File(path).resolve("platforms").isDirectory
    val configured = isSdk(props.getProperty("sdk.dir")) ||
        isSdk(System.getenv("ANDROID_HOME")) ||
        isSdk(System.getenv("ANDROID_SDK_ROOT"))
    if (!configured) {
        val home = System.getProperty("user.home")
        val candidates = listOfNotNull(
            "$home/Library/Android/sdk", // macOS – Standardort von Android Studio
            "$home/Android/Sdk", // Linux
            System.getenv("LOCALAPPDATA")?.let { "$it/Android/Sdk" }, // Windows
        )
        val found = candidates.firstOrNull { isSdk(it) }
        if (found != null) {
            props.setProperty("sdk.dir", found)
            localProperties.outputStream().use {
                props.store(it, "Automatically created by settings.gradle.kts (ORBIT). Machine-specific - do not share.")
            }
        } else {
            org.gradle.api.logging.Logging.getLogger("ORBIT").warn(
                "ORBIT: Android-SDK nicht gefunden. In Android Studio: Settings > Languages & Frameworks > " +
                    "Android SDK (Pfad prüfen), dann File > Sync Project with Gradle Files.",
            )
        }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ORBIT"

// App: Aktivität, Navigation, Bildschirme, ViewModels, Einstellungen (DataStore)
include(":app")

// Liquid-Glass-Designsystem: Farben, Themes, Schrift, Glas, Symbole, Bausteine, Diagramme
include(":ui:designsystem")

// Reine Kotlin-Module ohne Android (JVM-testbar)
include(":core:model") // Datenmodelle, Formatierung und Deutungsregeln
include(":core:files") // Dateiarten, Sortierung, Namen, Auflisten und alle Dateivorgänge

// Zugriff auf Android-Systemdienste – nur hier, nie aus der Oberfläche heraus
include(":platform:storage") // Speichervolumes, Kapazität (später: Dateisystem, MediaStore, SAF)
include(":platform:device") // Akku, Thermalstatus, Geräteübersicht (später: Sensoren)
