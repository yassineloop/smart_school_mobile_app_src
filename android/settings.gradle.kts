pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").let { localPropertiesFile ->
            if (localPropertiesFile.exists()) {
                localPropertiesFile.inputStream().use { properties.load(it) }
            }
        }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
            ?: System.getenv("FLUTTER_ROOT")
            ?: System.getenv("FLUTTER_SDK")
        require(flutterSdkPath != null) {
            "flutter.sdk is not set in local.properties or FLUTTER_ROOT/FLUTTER_SDK environment variables. " +
            "Please add 'flutter.sdk=C:\\path\\to\\flutter' to 'android/local.properties'."
        }
        val flutterToolsGradle = file("$flutterSdkPath/packages/flutter_tools/gradle")
        require(flutterToolsGradle.exists()) {
            "The Flutter SDK path '$flutterSdkPath' specified in local.properties does not exist or is missing 'packages/flutter_tools/gradle'. " +
            "Please update 'flutter.sdk' in 'android/local.properties' to point to your actual Flutter SDK directory."
        }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
