import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Native Google Maps SDK key. Read from wakey/.env (the same file Dart loads
// via flutter_dotenv) so a build works without an OS env var set; fall back to
// the MAPS_API_KEY env var if the file is missing.
val mapsApiKey: String = run {
    val envFile = file("../../.env")
    if (envFile.exists()) {
        val props = Properties()
        envFile.inputStream().use { props.load(it) }
        props.getProperty("MAPS_API_KEY") ?: System.getenv("MAPS_API_KEY") ?: ""
    } else {
        System.getenv("MAPS_API_KEY") ?: ""
    }
}

android {
    namespace = "com.wakey.wakey"
    // androidx.core:1.17.0 (transitive via google_maps_flutter) hard-requires
    // compileSdk 36. targetSdk stays at 34 so we don't opt into Android 14
    // runtime-behavior changes we haven't audited.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.wakey.wakey"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
