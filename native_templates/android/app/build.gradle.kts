// 基于 `flutter create --platforms=android` 生成的 app/build.gradle.kts，
// 额外启用 core library desugaring，并支持 CI 注入长期固定的 release 签名。
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}
fun signingValue(property: String, environment: String): String? =
    providers.environmentVariable(environment).orNull
        ?: keystoreProperties.getProperty(property)

val signingStoreFile = signingValue("storeFile", "HORMONE_KEYSTORE_PATH")
val signingStorePassword = signingValue("storePassword", "HORMONE_KEYSTORE_PASSWORD")
val signingKeyAlias = signingValue("keyAlias", "HORMONE_KEY_ALIAS")
val signingKeyPassword = signingValue("keyPassword", "HORMONE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    signingStoreFile, signingStorePassword, signingKeyAlias, signingKeyPassword
).all { !it.isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
    && !hasReleaseSigning) {
    throw GradleException("Release signing is required. Configure key.properties or HORMONE signing environment variables.")
}

android {
    namespace = "com.aetikyue.hormone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // 为 flutter_local_notifications 等插件提供 java.time API 反糖。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aetikyue.hormone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ota_update 7.x 要求 API 23+；当前 Flutter stable 的实际构建基线为 API 24。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = signingKeyAlias
                keyPassword = signingKeyPassword
                storeFile = file(signingStoreFile!!)
                storePassword = signingStorePassword
            }
        }
    }

    buildTypes {
        release {
            // 不允许正式构建静默回退到 debug 签名。
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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
    // ota_update 7.x 的 AAR metadata 要求 2.1.4+。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
