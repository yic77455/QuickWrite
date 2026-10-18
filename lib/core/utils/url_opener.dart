import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/utils/android_native.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';

/// 外部链接工具类
///
/// 提供跨平台的"在系统默认浏览器中打开链接"功能：
/// - Windows：调用 explorer
/// - macOS：调用 open
/// - Linux：调用 xdg-open
/// - Android：通过原生 Intent 打开
class UrlOpener {
  UrlOpener._();

  /// 在系统默认浏览器中打开指定链接
  ///
  /// [url] 需要打开的链接地址，返回是否成功发起打开操作
  static Future<bool> open(String url) async {
    // 安卓端没有命令行打开工具，交给原生通道处理
    if (PlatformCapabilities.isAndroid) return AndroidNative.openUrl(url);

    try {
      String command;
      List<String> args;

      if (PlatformCapabilities.isWindows) {
        command = 'explorer';
        args = [url];
      } else if (PlatformCapabilities.isMacOS) {
        command = 'open';
        args = [url];
      } else if (PlatformCapabilities.isLinux) {
        command = 'xdg-open';
        args = [url];
      } else {
        debugPrint('当前平台不支持打开外部链接');
        return false;
      }

      final result = await Process.run(command, args);
      // Windows 的 explorer 会把请求转发给现有进程并立即退出，
      // 退出码通常为 1，无法作为失败判据，因此只要未抛异常即视为成功
      if (PlatformCapabilities.isWindows) return true;
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('打开链接失败: $e');
      return false;
    }
  }
}