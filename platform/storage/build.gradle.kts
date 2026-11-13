// Zugriff auf Speicher-Systemdienste: Speichervolumes (intern, SD-Karte, USB), Kapazität und freier Platz,
// „Zugriff auf alle Dateien“, Medienindex (MediaStore: Kategorien, Suche), Vorschaubilder, Übergabe an andere
// Apps (FileProvider) und Paketinstallation. Die eigentlichen Dateivorgänge liegen in core:files (JVM-getestet);
// die Oberfläche greift nie direkt auf Dateien oder Systemdienste zu.

plugins {
    alias(libs.plugins.android.library)
    // Kein "org.jetbrains.kotlin.android" nötig: AGP 9 kompiliert Kotlin selbst.
}

android {
    namespace = "de.privateapp.aether.platform.storage"
    compileSdk = 37

    defaultConfig {
        minSdk = 31
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":core:model"))
    api(project(":core:files"))
    api(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.core.ktx)
}
