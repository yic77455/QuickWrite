import 'dart:io';
import 'package:flutter/foundation.dart';

/// 外部链接工具类
///
/// 提供跨平台的"在系统默认浏览器中打开链接"功能：
/// - Windows：调用 explorer
/// - macOS：调用 open
/// - Linux：调用 xdg-open
class UrlOpener {
  UrlOpener._();

  /// 在系统默认浏览器中打开指定链接
  ///
  /// [url] 需要打开的链接地址，返回是否成功发起打开操作
  static Future<bool> open(String url) async {
    try {
      String command;
      List<String> args;

      if (Platform.isWindows) {
        command = 'explorer';
        args = [url];
      } else if (Platform.isMacOS) {
        command = 'open';
        args = [url];
      } else if (Platform.isLinux) {
        command = 'xdg-open';
        args = [url];
      } else {
        debugPrint('当前平台不支持打开外部链接');
        return false;
      }

      final result = await Process.run(command, args);
      // Windows 的 explorer 会把请求转发给现有进程并立即退出，
      // 退出码通常为 1，无法作为失败判据，因此只要未抛异常即视为成功
      if (Platform.isWindows) return true;
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('打开链接失败: $e');
      return false;
    }
  }
}