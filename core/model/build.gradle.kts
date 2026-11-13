import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Datenmodelle, Formatierung und Deutungsregeln (Speicher, Akku, Thermalstatus, Gerät, Darstellung).
// Reines Kotlin-Modul ohne Android: kompiliert und testet auf der JVM (./gradlew :core:model:test).
// Hier wird festgelegt, WIE ein Messwert gedeutet und angezeigt wird – nicht, woher er kommt.

plugins {
    // Ohne Versionsangabe: Das Kotlin-Gradle-Plugin liegt bereits über die oberste
    // build.gradle.kts (buildscript) auf dem Klassenpfad – Version aus libs.versions.toml.
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation(libs.junit)
}
