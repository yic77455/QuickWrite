package com.quickwrite.app
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.Settings
import android.text.Html
import android.text.Spanned
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

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

        /** 选择书籍文件夹的请求码 */
        private const val REQUEST_CODE_PICK_BOOK_FOLDER = 4101
    }

    /** 等待系统文件夹选择器返回结果的回调 */
    private var pendingFolderPickResult: MethodChannel.Result? = null

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
                    // 选择书籍文件夹，返回目录树 URI
                    "pickBookFolder" -> pickBookFolder(result)
                    // 列出授权目录下的章节文件
                    "listChapterFiles" -> listChapterFiles(call.argument("treeUri"), result)
                    // 读取授权文件的字节内容
                    "readFileBytes" -> readFileBytes(call.argument("uri"), result)
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

    // ================= 文件夹导入（SAF） =================

    /**
     * 拉起系统文件夹选择器。
     *
     * 安卓 11 起应用无法直接枚举共享存储中的任意目录，只能通过 SAF 获得
     * content:// 授权。这里返回目录树 URI，后续按 URI 列目录、按 URI 读取文件。
     */
    private fun pickBookFolder(result: MethodChannel.Result) {
        if (pendingFolderPickResult != null) {
            result.error("picker_busy", "已有正在进行的文件夹选择", null)
            return
        }

        pendingFolderPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                )
            }
            startActivityForResult(intent, REQUEST_CODE_PICK_BOOK_FOLDER)
        } catch (e: Exception) {
            pendingFolderPickResult = null
            result.error("picker_unavailable", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != REQUEST_CODE_PICK_BOOK_FOLDER) return

        val result = pendingFolderPickResult ?: return
        pendingFolderPickResult = null

        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            result.success(null)
            return
        }

        // 申请持久读权限，避免进程重启后再次访问该目录被拒绝
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) {
            // 授权失败不影响本次导入
        }

        result.success(
            mapOf(
                "uri" to treeUri.toString(),
                "name" to queryFolderDisplayName(treeUri),
            )
        )
    }

    /**
     * 列出授权目录下根级文件与一层子目录中的 txt/docx。
     *
     * 与桌面端的目录规则保持一致：根级文件没有分卷，一层子目录名作为分卷名。
     */
    private fun listChapterFiles(treeUri: String?, result: MethodChannel.Result) {
        if (treeUri.isNullOrEmpty()) {
            result.success(emptyList<Map<String, String>>())
            return
        }

        val tree = Uri.parse(treeUri)
        thread {
            val files = mutableListOf<Map<String, String>>()
            try {
                val rootDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
                    tree,
                    DocumentsContract.getTreeDocumentId(tree)
                )
                val children = queryChildren(tree, rootDocumentUri)

                // 根级文件视为无分卷章节
                children.filter { !it.isDirectory }.forEach {
                    addChapterFile(it, "", files)
                }

                // 一层子目录视为分卷
                children.filter { it.isDirectory }.forEach { dir ->
                    if (dir.name.startsWith(".")) return@forEach
                    queryChildren(tree, dir.uri)
                        .filter { !it.isDirectory }
                        .forEach { addChapterFile(it, dir.name, files) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("list_failed", e.message, null) }
                return@thread
            }

            runOnUiThread { result.success(files) }
        }
    }

    /** 读取授权文件的全部字节内容 */
    private fun readFileBytes(uriString: String?, result: MethodChannel.Result) {
        if (uriString.isNullOrEmpty()) {
            result.success(null)
            return
        }

        thread {
            val bytes = try {
                contentResolver.openInputStream(Uri.parse(uriString))?.use { it.readBytes() }
            } catch (e: Exception) {
                runOnUiThread { result.error("read_failed", e.message, null) }
                return@thread
            }

            runOnUiThread { result.success(bytes) }
        }
    }

    /** 查询目录的直接子项 */
    private fun queryChildren(treeUri: Uri, parentUri: Uri): List<SafChild> {
        val parentId = DocumentsContract.getDocumentId(parentUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )

        val children = mutableListOf<SafChild>()
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val isDirectory =
                    cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR

                children.add(
                    SafChild(
                        uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId),
                        name = name,
                        isDirectory = isDirectory,
                    )
                )
            }
        }
        return children
    }

    /** 查询目录自身的显示名 */
    private fun queryFolderDisplayName(treeUri: Uri): String {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )
        contentResolver.query(
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(0)?.takeIf { it.isNotEmpty() }?.let { return it }
            }
        }

        // 查询不到时退回目录 ID 中冒号后的部分
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return documentId.substringAfter(':', documentId)
    }

    /** 把受支持的章节文件加入结果列表 */
    private fun addChapterFile(
        child: SafChild,
        volumeName: String,
        out: MutableList<Map<String, String>>
    ) {
        // 跳过隐藏文件
        if (child.name.startsWith(".")) return

        // 只处理 txt 和 docx 文件
        val extension = child.name.substringAfterLast('.', "").lowercase()
        if (extension != "txt" && extension != "docx") return

        out.add(
            mapOf(
                "uri" to child.uri.toString(),
                "fileName" to child.name,
                "volumeName" to volumeName,
            )
        )
    }

    /** SAF 目录子项的查询结果 */
    private data class SafChild(
        val uri: Uri,
        val name: String,
        val isDirectory: Boolean,
    )

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
