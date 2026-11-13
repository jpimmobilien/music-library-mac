// App-Modul: Aktivität, Navigation, Bildschirme, ViewModels und gespeicherte Einstellungen.
// Zugriffe auf Android-Systemdienste liegen in platform/*, Fachlogik und Deutungsregeln in core/model,
// das Designsystem in ui/designsystem.

plugins {
    alias(libs.plugins.android.application)
    // Kein "org.jetbrains.kotlin.android" nötig: AGP 9 kompiliert Kotlin selbst.
    alias(libs.plugins.kotlin.compose)
}

// App-Name zentral aus gradle.properties (aether.appName) – Anzeigename und BuildConfig.APP_NAME.
val appName: String = providers.gradleProperty("aether.appName").getOrElse("Aether").trim().ifEmpty { "Aether" }

android {
    namespace = "de.privateapp.aether"
    compileSdk = 37

    defaultConfig {
        applicationId = "de.privateapp.aether"
        minSdk = 31 // Android 12: RenderEffect für das Glas, StorageVolume.getDirectory, Thermal-Reserve
        targetSdk = 36 // Android 16
        // Bei jeder neuen Version, die du installierst, um 1 erhöhen (siehe README).
        versionCode = 3
        versionName = "0.4.0"

        resValue("string", "app_name", appName)
        buildConfigField("String", "APP_NAME", "\"" + appName.replace("\\", "\\\\").replace("\"", "\\\"") + "\"")
    }

    // Projektschlüssel (docs/SIGNATUR.md): Jede Version – aus Android Studio oder aus dem automatischen Build –
    // trägt dieselbe Signatur und ersetzt die vorherige ohne Deinstallation. Er liegt bewusst im Projekt und ist
    // damit nicht geheim: geeignet für eine privat installierte App, nicht für eine Veröffentlichung im Play Store.
    signingConfigs {
        create("orbit") {
            storeFile = file("signing/orbit-project.keystore")
            storePassword = "orbit-project"
            keyAlias = "orbit"
            keyPassword = "orbit-project"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("orbit")
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("orbit")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
        // In AGP 9 standardmäßig aus – wird für den zentral konfigurierbaren App-Namen gebraucht.
        resValues = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(project(":ui:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":platform:storage"))
    implementation(project(":platform:device"))

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)

    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(libs.androidx.datastore.preferences)

    testImplementation(libs.junit)
}
