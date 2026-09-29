plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.easybasket.grocery"
    compileSdk = flutter.compileSdkVersion
    // Use highest NDK required by plugins (backward compatible)
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Unique Application ID for Google Play Store
        // Changed to avoid Kotlin reserved keyword 'in'
        applicationId = "com.easybasket.grocery"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Keystore file path (relative to android/app/)
            val keystoreFile = file("easy-basket-key.jks")
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                // Use environment variables for passwords (more secure)
                val keystorePassword = System.getenv("KEYSTORE_PASSWORD") ?: "nik3122@@"
                val keyPassword = System.getenv("KEY_PASSWORD") ?: "nik3122@@"
                storePassword = keystorePassword
                keyAlias = "easy-basket-key"
                this.keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        release {
            // ALWAYS use release signing config - required for Play Store
            val keystoreFile = file("easy-basket-key.jks")
            if (keystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // No fallback - fail if keystore doesn't exist
                throw GradleException("Release keystore not found! Please ensure easy-basket-key.jks exists in android/app/")
            }
            // FULL debug symbols so Flutter's strip check finds expected files (see flutter/flutter#181031)
            ndk {
                debugSymbolLevel = "full"
            }
            // Disable minification for testing APK (enable for Play Store)
            isMinifyEnabled = false
            isShrinkResources = false
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
