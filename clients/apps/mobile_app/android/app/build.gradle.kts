import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.delivery.mobile_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.delivery.mobile_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // REQUIRED by flutter_appauth. It injects an intent-filter into the merged manifest for
        // this scheme so Keycloak's redirect back to `com.delivery.app://oauth2redirect` reopens
        // the app. Without it the browser tab hits the redirect and simply stops — the login
        // appears to hang with no error anywhere.
        //
        // Must stay in step with OIDC_REDIRECT_URL in lib/main.dart and with the mobile-app
        // client's redirect URIs in the Keycloak realm.
        manifestPlaceholders["appAuthRedirectScheme"] = "com.delivery.app"
        // The Google Maps Android key. Read from local.properties (gitignored) or the
        // GOOGLE_MAPS_API_KEY env var — never committed. Empty is a legal value: the manifest
        // meta-data is present either way, and the map surfaces simply stay on OSM until the
        // key exists. An Android Maps key ships inside the APK by design; its real protection
        // is the package+SHA-1 restriction set in the Google Cloud console, not secrecy.
        val localProps = Properties()
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) {
            localPropsFile.inputStream().use { localProps.load(it) }
        }
        manifestPlaceholders["googleMapsApiKey"] =
            (localProps.getProperty("googleMapsApiKey")
                ?: System.getenv("GOOGLE_MAPS_API_KEY") ?: "")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
