import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let(::file)
val hasReleaseSigning = releaseStoreFile?.isFile == true &&
    !keystoreProperties.getProperty("storePassword").isNullOrBlank() &&
    !keystoreProperties.getProperty("keyAlias").isNullOrBlank() &&
    !keystoreProperties.getProperty("keyPassword").isNullOrBlank()
val allowDebugReleaseSigning =
    providers.gradleProperty("allowDebugReleaseSigning").orNull
        ?.equals("true", ignoreCase = true) == true ||
        System.getenv("ALLOW_DEBUG_RELEASE_SIGNING")
            ?.equals("true", ignoreCase = true) == true

android {
    namespace = "com.kkape.mynas"
    compileSdk = 36
    ndkVersion = "28.2.13676358"  // NDK r28（jni 插件要求）

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.kkape.mynas"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // CMake 配置 - 编译 Chromaprint JNI
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    // CMake 构建配置
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // JNI 库目录
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            when {
                hasReleaseSigning ->
                    signingConfig = signingConfigs.getByName("release")
                allowDebugReleaseSigning ->
                    signingConfig = signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseArtifactRequested = allTasks.any { task ->
        val taskName = task.name.lowercase()
        task.project == project &&
            taskName.contains("release") &&
            (taskName.startsWith("assemble") ||
                taskName.startsWith("bundle") ||
                taskName.startsWith("package"))
    }
    if (releaseArtifactRequested && !hasReleaseSigning && !allowDebugReleaseSigning) {
        throw GradleException(
            "Release signing is not configured. Add android/key.properties with " +
                "storeFile, storePassword, keyAlias and keyPassword. " +
                "For local testing only, explicitly opt in to debug signing with " +
                "-PallowDebugReleaseSigning=true.",
        )
    }
}

flutter {
    source = "../.."
}
