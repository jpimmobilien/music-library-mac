// Liquid-Glass-Designsystem von AETHER: Farben und Themes, Schrift, Abstände, Bewegung, Glasmaterial,
// Symbole, Bausteine und Diagramme. Android-Bibliothek mit Compose; wird von :app verwendet.
// Die Farbwerte selbst liegen als reine Zahlen in PaletteSpec.kt und werden auf der JVM auf
// Kontrast geprüft (./gradlew :ui:designsystem:testDebugUnitTest).

plugins {
    alias(libs.plugins.android.library)
    // Kein "org.jetbrains.kotlin.android" nötig: AGP 9 kompiliert Kotlin selbst.
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "de.privateapp.aether.design"
    compileSdk = 37

    defaultConfig {
        minSdk = 31 // Android 12 – echte Hintergrundunschärfe (RenderEffect) überall verfügbar
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Darstellungs-Einstellungen (Theme, Akzent, Effektstärke) sind reine Kotlin-Typen aus core/model.
    api(project(":core:model"))

    api(platform(libs.androidx.compose.bom))
    api(libs.androidx.compose.ui)
    api(libs.androidx.compose.foundation)
    api(libs.androidx.compose.material3)

    testImplementation(libs.junit)
}
