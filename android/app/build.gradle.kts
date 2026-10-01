plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.laplazoleta.companion"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.laplazoleta.companion"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Android solo deja actualizar una app instalada si el APK nuevo lleva la MISMA firma. El APK que ya
    // está en el celular salió firmado con el debug.keystore de la PC del dueño; para que el CI genere APK
    // que lo actualicen, ese mismo keystore va como secreto (ANDROID_KEYSTORE_BASE64) y el workflow
    // exporta ANDROID_KEYSTORE_PATH. Sin esa variable (build local) se sigue firmando con el debug de la máquina.
    val keystoreCI = System.getenv("ANDROID_KEYSTORE_PATH")
    if (keystoreCI != null) {
        signingConfigs {
            create("ci") {
                storeFile = file(keystoreCI)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: "android"
                keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "androiddebugkey"
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keystoreCI != null) "ci" else "debug")
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
