// Zugriff auf Geräte-Systemdienste: Akku (BatteryManager), Thermalstatus und thermische Reserve
// (PowerManager), Geräteübersicht (Build, ActivityManager, Display) und Sensorliste (SensorManager).
// Nur offizielle APIs, keine Berechtigung, keine Systemdateien. Ab Phase 6: Live-Sensoren.

plugins {
    alias(libs.plugins.android.library)
    // Kein "org.jetbrains.kotlin.android" nötig: AGP 9 kompiliert Kotlin selbst.
}

android {
    namespace = "de.privateapp.aether.platform.device"
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
    api(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.core.ktx)
}
