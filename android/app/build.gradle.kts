import java.util.Properties
import java.io.FileInputStream
import groovy.json.JsonSlurper

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.daltontewanger.whatdoyouwant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.daltontewanger.whatdoyouwant"
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("production") {
            dimension = "environment"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
        }
        create("local") {
            dimension = "environment"
            applicationIdSuffix = ".local"
            versionNameSuffix = "-local"
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = (keystoreProperties["storeFile"] as? String)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

dependencies {
  // Import the Firebase BoM
  implementation(platform("com.google.firebase:firebase-bom:33.14.0"))

  implementation("com.google.firebase:firebase-analytics")

  // Add the dependencies for any other desired Firebase products
  // https://firebase.google.com/docs/android/setup#available-libraries
}

flutter {
    source = "../.."
}

// Fail before build tasks execute if native and Dart environments disagree.
gradle.taskGraph.whenReady {
    val appTasks = gradle.startParameter.taskNames.map { it.lowercase() }
    val stagingBuild = appTasks.any { it.contains("staging") }
    val productionBuild = appTasks.any { it.contains("production") }
    val localBuild = appTasks.any { it.contains("local") }
    val requestedBuild = appTasks.any { Regex("(^|:)(assemble|bundle|install|build).*").containsMatchIn(it) }
    check(!requestedBuild || stagingBuild || productionBuild || localBuild) { "Select an explicit local, staging or production flavor." }
    val entry = (project.findProperty("target") as? String ?: "lib/main.dart")
        .replace('\\', '/').substringAfterLast("lib/")
    check(listOf(stagingBuild, productionBuild, localBuild).count { it } <= 1) { "Build one environment at a time." }
    if (stagingBuild || productionBuild || localBuild) {
        check(!localBuild || appTasks.none { it.contains("release") || it.contains("profile") }) { "Local emulator builds must use debug mode." }
        val valid = when {
            localBuild -> entry == "main_local.dart"
            stagingBuild -> entry == "main_staging.dart"
            else -> entry == "main.dart"
        }
        check(valid) { "Firebase environment mismatch: Android flavor and Dart entry point disagree." }
        val configFile = when {
            localBuild -> file("src/local/google-services.json")
            stagingBuild -> file("src/staging/google-services.json")
            else -> file("google-services.json")
        }
        val config = JsonSlurper().parse(configFile) as Map<*, *>
        val info = config["project_info"] as Map<*, *>
        val expected = when {
            localBuild -> "demo-whatdoyouwant"
            stagingBuild -> "whatdoyouwant-staging"
            else -> "what-do-you-want-8a404"
        }
        check(info["project_id"] == expected) { "Firebase native project mismatch." }
        val expectedPackage = "com.daltontewanger.whatdoyouwant" + when {
            localBuild -> ".local"
            stagingBuild -> ".staging"
            else -> ""
        }
        val clients = config["client"] as List<*>
        check(clients.any {
            val client = (it as Map<*, *>)["client_info"] as Map<*, *>
            (client["android_client_info"] as Map<*, *>)["package_name"] == expectedPackage
        }) { "Firebase native package mismatch." }
    }
}
