// Oberste Build-Datei. Hier werden nur Plugin-Versionen festgelegt; die eigentliche
// Konfiguration steht in den build.gradle.kts der einzelnen Module.

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // AGP 9 enthält Kotlin bereits ("built-in Kotlin"). Mit diesem Eintrag wird die
        // Kotlin-Version ausdrücklich festgelegt, damit sie exakt zur Version des
        // Compose-Compiler-Plugins passt (beide kommen aus gradle/libs.versions.toml).
        // Derselbe Eintrag stellt das Plugin "org.jetbrains.kotlin.jvm" für das reine
        // Kotlin-Modul core/model bereit (dort deshalb ohne Versionsangabe).
        classpath(libs.kotlin.gradle.plugin)
    }
}

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
