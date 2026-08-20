pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// PINNED to versions already present in the local Gradle cache.
//
// `flutter create` generated AGP 9.0.1 / Kotlin 2.3.20, and neither has a single jar in
// ~/.gradle/caches - the downloads from dl.google.com and repo.maven.apache.org time out on this
// network. AGP 8.11.1 and Kotlin 2.2.20 are fully cached from other projects on this machine, so
// pinning here lets the build resolve without reaching Google's Maven at all.
//
// If you move to a network that can reach those hosts, raising these is safe - just re-check that
// the Gradle wrapper version in gradle/wrapper/gradle-wrapper.properties stays compatible with the
// AGP version (AGP 8.11 needs Gradle 8.13+).
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
