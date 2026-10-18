package com.quickwrite.app
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用入口 Activity，同时承载移动端所需的部分系统原生能力。
 *
 * 桌面端已有的 UrlOpener / FileExplorer 等工具依赖桌面系统的命令行程序，
 * 安卓端没有对应实现，因此这些能力改由本 Activity 通过 MethodChannel 提供。
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** 与 Dart 侧约定的通道名称 */
        private const val CHANNEL_NAME = "com.quickwrite.app/native"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 在系统浏览器中打开链接
                    "openUrl" -> result.success(openUrl(call.argument("url")))
                    // 查询当前是否已获得「安装未知应用」授权
                    "canInstallPackages" -> result.success(canInstallPackages())
                    // 跳转到系统的「安装未知应用」授权页面
                    "openInstallPermissionSettings" -> result.success(openInstallPermissionSettings())
                    // 拉起系统安装程序安装指定路径的安装包
                    "installApk" -> result.success(installApk(call.argument("path")))
                    else -> result.notImplemented()
                }
            }
    }

    /** 在系统浏览器中打开链接，成功发起跳转返回 true */
    private fun openUrl(url: String?): Boolean {
        if (url.isNullOrEmpty()) return false

        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 是否已获得「安装未知应用」授权。
     *
     * 安卓 8.0 起该授权按应用逐个授予，未授权时无法拉起安装程序，
     * 更早的版本无此限制，直接视为已授权。
     */
    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /** 跳转到系统的「安装未知应用」授权页面，成功发起跳转返回 true */
    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false

        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 拉起系统安装程序安装指定路径的安装包，成功发起跳转返回 true。
     *
     * 安装包位于应用外部存储私有目录，需通过 FileProvider 转换为 content:// 地址传递给安装程序。
     */
    private fun installApk(path: String?): Boolean {
        if (path.isNullOrEmpty() || !canInstallPackages()) return false

        val file = File(path)
        if (!file.exists()) return false

        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
