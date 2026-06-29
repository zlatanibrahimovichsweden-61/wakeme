import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Drop a `key.properties` next to this module's parent
// (android/key.properties — gitignored) with: storeFile, storePassword,
// keyAlias, keyPassword. Until that file exists, release builds fall back to
// the debug key so `flutter run --release` and test builds keep working.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.wakeme.wakeme"
    // androidx.core:1.17.0 (transitive via google_maps_flutter) hard-requires
    // compileSdk 36. targetSdk is 35 (Android 15) to meet Google Play's current
    // minimum target-API requirement for new apps / updates.
    compileSdk = 36
    // Pinned to the NDK already installed locally. flutter.ndkVersion resolves
    // to 28.2.13676358, which wasn't present and whose auto-download stalled;
    // 29.0.13113456 is already on disk, so we use it to avoid the re-download.
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.wakeme.wakeme"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] =
            System.getenv("MAPS_API_KEY") ?: ""
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real upload key once android/key.properties exists;
            // otherwise fall back to the debug key so test builds still work.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
