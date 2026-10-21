// File: android/build.gradle.kts
// Root-level Gradle configuration for Flutter + Firebase

buildscript {
    dependencies {
        // Google Services plugin (updated)
        classpath("com.google.gms:google-services:4.4.0")
    }
}

plugins {
    // Android & Kotlin plugins declared but not applied here
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Use a fresh root build directory so stale Gradle reports cannot block this
// workspace's build.
layout.buildDirectory.set(layout.projectDirectory.dir("build-codex"))

subprojects {
    // Keep plugin build outputs in the project workspace. Gradle otherwise
    // writes them inside Pub's shared package cache, which may be read-only.
    if (project.name != "app") {
        project.layout.buildDirectory.set(
            rootProject.layout.buildDirectory.dir("flutter-plugin-build/${project.name}")
        )
    }

    // Required by Flutter for correct module evaluation
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
