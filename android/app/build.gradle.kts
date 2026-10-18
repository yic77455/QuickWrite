import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名信息（密钥库路径与口令）保存在 android/key.properties，该文件不纳入版本控制
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// 本次构建的目标架构，由 Flutter 以 -Ptarget-platform 传入（如 android-arm64）
//
// 打包时只保留目标架构的原生库：第三方库（isar 等）会为所有架构提供二进制文件，
// 而 Flutter 只为目标架构生成引擎，若把缺少引擎的架构一并打进包，对应设备能安装成功
// 却会在启动时崩溃。取值来源为目标平台到 ABI 名称的映射，未取到时不做限制，
// 沿用 Flutter 默认行为。
val abiByTargetPlatform = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
    "android-x86" to "x86",
)
val targetAbis = (project.findProperty("target-platform") as String?)
    ?.split(",")
    ?.mapNotNull { abiByTargetPlatform[it.trim()] }
    ?.takeIf { it.isNotEmpty() }

// 非目标架构的原生库目录，打包时整体排除（兼容库提供的原生库不参与 abiFilters 过滤）
val excludedNativeLibs = targetAbis
    ?.let { abis ->
        abiByTargetPlatform.values.filterNot { abis.contains(it) }.map { "lib/$it/**" }
    }
    .orEmpty()

android {
    namespace = "com.quickwrite.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.quickwrite.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
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
            // 已配置 key.properties 时使用正式签名，否则回退到调试签名以便在未配置签名的机器上打包测试
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            // 排除非目标架构的原生库目录
            excludes += excludedNativeLibs
        }
    }
}

dependencies {
    // 安卓端拉起安装包需要借助 androidx 的 FileProvider 提供 content:// 形式的文件地址
    implementation("androidx.core:core:1.13.1")
}

flutter {
    source = "../.."
}
