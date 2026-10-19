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

    // Dos ediciones del mismo código (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`): la de siempre (almacén) y Nodo Sur
    // Servicios, con el bot de WhatsApp adentro. Otro applicationId: se instalan una al lado de la otra (el dueño tiene su almacén
    // y el negocio de servicios que atiende en el mismo celular). Node y el bot (`src/servicios/`, `src/gastronomia/`) van solo en las
    // ediciones aparte.
    flavorDimensions += "edicion"
    productFlavors {
        create("almacen") {
            dimension = "edicion"
            manifestPlaceholders["nombreApp"] = "Nodo Gestión"
        }
        create("servicios") {
            dimension = "edicion"
            applicationId = "com.laplazoleta.servicios"
            manifestPlaceholders["nombreApp"] = "Nodo Estudio"
        }
        // Nodo Gastro (El dueño, 2026-10-16, `docs/PLAN-GASTRONOMIA.md`): rotisería y comida para llevar, también con el
        // bot adentro. Su manifiesto es el de servicios (el servicio del bot), en `src/gastronomia/`.
        create("gastronomia") {
            dimension = "edicion"
            applicationId = "com.laplazoleta.gastronomia"
            manifestPlaceholders["nombreApp"] = "Nodo Gastro"
        }
    }

    // Prueba del bot adentro de la app: Node (libns_node.so) tiene que quedar descomprimido en la carpeta de librerías para poder
    // ejecutarlo (Android no deja ejecutar desde los datos de la app).
    packaging {
        jniLibs {
            useLegacyPackaging = true
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

dependencies {
    // Notificaciones con la app cerrada (`MainActivity.kt`). Sin el plugin de Google Services: Firebase se inicializa desde Dart.
    implementation("com.google.firebase:firebase-messaging:24.1.0")
}
