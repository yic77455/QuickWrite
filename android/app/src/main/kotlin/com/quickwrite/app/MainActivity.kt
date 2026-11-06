package com.quickwrite.app
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.Html
import android.text.Spanned
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
                    // 读取剪贴板中的 HTML 富文本
                    "readClipboardHtml" -> result.success(readClipboardHtml())
                    // 以 HTML 富文本写入剪贴板
                    "writeClipboardHtml" -> result.success(
                        writeClipboardHtml(
                            call.argument("text"),
                            call.argument("html"),
                        )
                    )
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

    // ================= 剪贴板富文本 =================

    /** 获取系统剪贴板服务 */
    private fun clipboardManager(): ClipboardManager =
        getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    /**
     * 读取剪贴板中的 HTML 内容。
     *
     * 优先使用 ClipData 自带的 text/html；没有 HTML 时，
     * 若文本是带样式的 Spanned，则转换为 HTML 以尽量保留粗体、颜色等格式。
     * 纯文本或无内容时返回 null，由 Dart 侧回退为纯文本解析。
     */
    private fun readClipboardHtml(): String? {
        val clip = clipboardManager().primaryClip ?: return null
        if (clip.itemCount == 0) return null

        val item = clip.getItemAt(0)
        val html = item.htmlText
        if (!html.isNullOrEmpty()) return html

        val text = item.text
        if (text is Spanned && text.isNotEmpty()) {
            return Html.toHtml(text, Html.TO_HTML_PARAGRAPH_LINES_CONSECUTIVE)
        }
        return null
    }

    /**
     * 以 HTML 富文本写入剪贴板。
     *
     * 同时写入纯文本与 HTML，便于纯文本目标和富文本目标分别取用。
     */
    private fun writeClipboardHtml(text: String?, html: String?): Boolean {
        if (text.isNullOrEmpty() && html.isNullOrEmpty()) return false

        return try {
            val clip = if (!html.isNullOrEmpty()) {
                ClipData.newHtmlText("quick_write", text ?: "", html)
            } else {
                ClipData.newPlainText("quick_write", text)
            }
            clipboardManager().setPrimaryClip(clip)
            true
        } catch (e: Exception) {
            false
        }
    }
}
