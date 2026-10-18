allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 兼容未声明 namespace 的旧版 Flutter 插件
//
// AGP 8 要求每个 Android 模块在构建脚本中显式声明 namespace，而部分老插件
// （如 isar_flutter_libs）只在 AndroidManifest 里写了 package，导致构建报
// “Namespace not specified”。这里在 Android 插件被应用时，为缺少 namespace 的模块补上，
// 取值使用模块自身的 group（插件在应用 Android 插件前已设置好 group）。
subprojects {
    val subproject = this
    plugins.withId("com.android.library") {
        runCatching {
            subproject.extensions.findByName("android")?.withGroovyBuilder {
                if (getProperty("namespace") == null) {
                    setProperty("namespace", subproject.group.toString())
                }
            }
        }
    }
}

// 跳过编译 SDK 过旧插件自身的资源校验任务
//
// isar_flutter_libs 声明 compileSdkVersion 30，而其依赖的 androidx 资源引用了仅 API 31 起
// 才提供的 android:attr/lStar，AGP 8 用该模块自身声明的编译 SDK 校验其资源会使 release
// 打包必然失败；同时 AGP 8 又禁止在模块评估完成后回改 compileSdk，无法从外部修正。
// 这里只关闭该模块的 verifyReleaseResources：其资源最终仍会在主模块按 compileSdk 36
// 完成链接校验，资源错误的检测能力不受影响。
subprojects {
    if (name == "isar_flutter_libs") {
        tasks.matching { it.name == "verifyReleaseResources" }.configureEach {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
