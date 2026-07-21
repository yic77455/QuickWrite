import 'dart:io';

import 'package:flutter/foundation.dart';

/// 文件管理器工具类
///
/// 提供跨平台的"在系统文件管理器中打开目录"功能：
/// - Windows：调用 explorer
/// - macOS：调用 open
/// - Linux：调用 xdg-open
class FileExplorer {
  FileExplorer._();

  /// 在系统文件管理器中打开指定目录
  ///
  /// [path] 目录绝对路径，若不存在则返回 false
  static Future<bool> openDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        debugPrint('目录不存在，无法打开: $path');
        return false;
      }

      String command;
      List<String> args;

      if (Platform.isWindows) {
        command = 'explorer';
        args = [path];
      } else if (Platform.isMacOS) {
        command = 'open';
        args = [path];
      } else if (Platform.isLinux) {
        command = 'xdg-open';
        args = [path];
      } else {
        debugPrint('当前平台不支持在文件管理器中打开目录');
        return false;
      }

      final result = await Process.run(command, args);
      // Windows 的 explorer 在已有进程运行时会把请求转发给现有进程并立即退出，
      // 退出码通常为 1，无法作为失败判据，因此只要未抛异常即视为成功
      if (Platform.isWindows) return true;
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('打开目录失败: $e');
      return false;
    }
  }
}
