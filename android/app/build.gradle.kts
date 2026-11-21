import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKey = Properties().apply {
    if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { load(it) }
}

android {
    namespace = "dev.airport.airport_mobile"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "dev.airport.airport_mobile"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeyFile.exists()) {
            create("release") {
                fun required(name: String) = releaseKey.getProperty(name)
                    ?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("Missing release signing property: $name")
                keyAlias = required("keyAlias")
                keyPassword = required("keyPassword")
                storeFile = file(required("storeFile"))
                storePassword = required("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Without a private release key, build unsigned for validation.
            // Never silently ship a publicly reproducible debug identity.
            signingConfig = if (releaseKeyFile.exists()) signingConfigs.getByName("release") else null
        }
    }
}

// AGP 9 new DSL: Kotlin JVM target is configured via the Kotlin compilerOptions.
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
