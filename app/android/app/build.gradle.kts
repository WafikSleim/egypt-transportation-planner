import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, read from `android/key.properties`, which is
// NOT in the repository and never will be - it names a keystore file and
// carries two passwords. `android/key.properties.example` shows the shape and
// `app/README.md` has the exact `keytool` command that produces the keystore.
//
// The file is optional on purpose. Without it `signingConfigs.release` is
// never created and the release build falls back to the debug keys, so
// `flutter build apk --release`, CI and a fresh clone all still work - they
// just produce something that cannot be uploaded to Play. That is the right
// failure: unsigned-for-release is visible the moment you try to publish,
// whereas a build that refuses to run at all would break every contributor
// who only wants to check that the app compiles.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "org.egypttransport.egypt_transport"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Required by flutter_local_notifications (#21), which uses the
        // java.time APIs to schedule a reminder and needs them backported on
        // the older Androids this app is aimed at. Without it the app does
        // not build at all, so this is not an optimisation to tidy away.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "org.egypttransport.egypt_transport"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    // See the note above: debug keys keep the build working
                    // for anyone without the maintainer's keystore.
                    signingConfigs.getByName("debug")
                }

            // R8. It only ever touches the JVM half of this app - the Flutter
            // engine, the Dart AOT snapshot and MapLibre's native libraries
            // are `.so` files R8 cannot see - so the saving is the plugin
            // shims and their transitive Android libraries, not the bulk of
            // the APK. Worth having anyway: those libraries pull in
            // play-services-base and play-services-location through
            // maplibre_gl, and none of that is reachable from this app.
            //
            // `isShrinkResources` requires `isMinifyEnabled`; setting it
            // alone fails the build.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // The other half of isCoreLibraryDesugaringEnabled above. Version pinned
    // to what flutter_local_notifications 22's own README asks for.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
