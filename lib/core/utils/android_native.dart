import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';

/// 安卓原生能力入口
///
/// 打开外部链接、拉起安装程序等能力在桌面端由命令行工具实现，
/// 安卓端没有对应实现，统一转由 MainActivity 注册的方法通道执行。
/// 非安卓平台上的调用一律返回失败，避免触发通道未实现的异常。
class AndroidNative {
  AndroidNative._();

  /// 与原生端约定的通道名称
  static const MethodChannel _channel = MethodChannel('com.quickwrite.app/native');

  /// 在系统浏览器中打开链接，返回是否成功发起跳转
  static Future<bool> openUrl(String url) async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('openUrl', {'url': url}) ?? false;
  }

  /// 查询当前是否已获得「安装未知应用」授权
  static Future<bool> canInstallPackages() async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('canInstallPackages') ?? false;
  }

  /// 跳转到系统的「安装未知应用」授权页面，返回是否成功发起跳转
  static Future<bool> openInstallPermissionSettings() async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('openInstallPermissionSettings') ?? false;
  }

  /// 拉起系统安装程序安装指定路径的安装包，返回是否成功发起跳转
  static Future<bool> installApk(String path) async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('installApk', {'path': path}) ?? false;
  }

  /// 读取系统剪贴板中的 HTML 内容，无富文本时返回 null
  static Future<String?> readClipboardHtml() async {
    if (!PlatformCapabilities.isAndroid) return null;
    return await _invoke<String>('readClipboardHtml');
  }

  /// 以 HTML 富文本写入系统剪贴板，返回是否写入成功
  static Future<bool> writeClipboardHtml({
    required String text,
    required String html,
  }) async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('writeClipboardHtml', {'text': text, 'html': html}) ?? false;
  }

  /// 拉起系统文件夹选择器，返回授权目录；用户取消时返回 null
  static Future<SafFolderPick?> pickBookFolder() async {
    if (!PlatformCapabilities.isAndroid) return null;

    final data = await _invoke<Map<dynamic, dynamic>>('pickBookFolder');
    final treeUri = data?['uri'];
    if (treeUri is! String || treeUri.isEmpty) return null;

    final name = data?['name'];
    return SafFolderPick(
      treeUri: treeUri,
      name: name is String ? name : '',
    );
  }

  /// 列出授权目录下根级与一层子目录中的章节文件
  static Future<List<SafChapterFile>> listChapterFiles(String treeUri) async {
    if (!PlatformCapabilities.isAndroid) return const [];

    final raw = await _invoke<List<dynamic>>('listChapterFiles', {'treeUri': treeUri});
    if (raw == null) return const [];

    final files = <SafChapterFile>[];
    for (final item in raw) {
      if (item is! Map) continue;

      final uri = item['uri'];
      final fileName = item['fileName'];
      if (uri is! String || fileName is! String) continue;

      final volumeName = item['volumeName'];
      files.add(SafChapterFile(
        uri: uri,
        fileName: fileName,
        volumeName: volumeName is String ? volumeName : '',
      ));
    }
    return files;
  }

  /// 读取授权文件的全部字节，读取失败返回 null
  static Future<Uint8List?> readFileBytes(String uri) async {
    if (!PlatformCapabilities.isAndroid) return null;
    return _invoke<Uint8List>('readFileBytes', {'uri': uri});
  }

  /// 调用原生方法，并把通道异常统一降级为调用失败
  static Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (e) {
      debugPrint('调用安卓原生能力失败（$method）: $e');
      return null;
    }
  }
}

/// 系统文件夹选择器返回的授权目录
class SafFolderPick {
  /// 目录树 URI，后续列目录与读取文件都以它为根
  final String treeUri;

  /// 目录显示名（作为默认书名）
  final String name;

  const SafFolderPick({required this.treeUri, required this.name});
}

/// 授权目录中的一个候选章节文件
class SafChapterFile {
  /// 文件 URI
  final String uri;

  /// 文件显示名（含扩展名）
  final String fileName;

  /// 所属分卷名，文件位于目录根级时为空字符串
  final String volumeName;

  const SafChapterFile({
    required this.uri,
    required this.fileName,
    required this.volumeName,
  });
}
