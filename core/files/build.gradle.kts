import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Dateilogik von AETHER: Dateiarten, Sortierung, Namensprüfung, Auflisten und alle Dateivorgänge (Kopieren,
// Verschieben, Papierkorb, Wiederherstellen, Löschen, Umbenennen, Ordner, ZIP, Textänderungen) – mit geprüfter
// Kopie, Konfliktbehandlung, Fortschritt und Abbruch.
// Reines Kotlin-Modul ohne Android: dieselbe java.io/java.nio-Umsetzung läuft auf dem Gerät und in den Tests
// gegen echte Dateien in temporären Ordnern (./gradlew :core:files:test).

plugins {
    // Ohne Versionsangabe: Das Kotlin-Gradle-Plugin liegt bereits über die oberste build.gradle.kts auf dem Klassenpfad.
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
    api(libs.kotlinx.coroutines.core)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
