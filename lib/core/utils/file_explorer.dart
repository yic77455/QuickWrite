import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/utils/windows_explorer.dart';

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

  /// 在系统文件管理器中定位并选中给定路径
  ///
  /// [paths] 待定位的路径列表：
  /// - 已存在的条目会被选中，Windows 下同一目录的条目会在同一个
  ///   资源管理器窗口中被一起选中，不同目录会分别打开
  /// - 不存在的条目无法被选中，退化为打开其所在目录
  ///
  /// 其他平台退化为逐个打开所在目录
  static Future<bool> revealAll(List<String> paths) async {
    if (paths.isEmpty) return false;

    // 按是否存在分组：存在的用于选中，不存在的用于兜底打开所在目录
    final existing = <String>[];
    final missing = <String>[];
    for (final path in paths) {
      if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
        missing.add(path);
      } else {
        existing.add(path);
      }
    }

    var success = false;

    // Windows 优先通过 shell 接口一次选中同目录的全部已存在条目
    if (existing.isNotEmpty) {
      if (Platform.isWindows && WindowsExplorer.revealAll(existing)) {
        success = true;
      } else {
        for (final path in existing) {
          success = await _revealOne(path) || success;
        }
      }
    }

    // 不存在的条目无法被选中，退化为打开其所在目录，便于用户手动查找
    for (final path in missing) {
      success = await _revealOne(File(path).parent.path) || success;
    }

    return success;
  }

  /// 在系统文件管理器中定位并选中单个文件或目录
  ///
  /// [path] 文件或目录的绝对路径，若不存在则返回 false。
  /// 文件会被选中，目录会被直接打开
  static Future<bool> _revealOne(String path) async {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.notFound) {
        debugPrint('路径不存在，无法定位: $path');
        return false;
      }

      if (Platform.isWindows) {
        // Windows 对目录直接打开，对文件使用 /select 选中
        final args = type == FileSystemEntityType.directory
            ? [path]
            : ['/select,', path];
        await Process.run('explorer', args);
        return true;
      }

      if (Platform.isMacOS) {
        // -R 会定位到目标位置并选中该条目
        await Process.run('open', ['-R', path]);
        return true;
      }

      if (Platform.isLinux) {
        // 平台无统一的选中能力，退化为打开所在目录
        final dirPath = type == FileSystemEntityType.directory
            ? path
            : File(path).parent.path;
        await Process.run('xdg-open', [dirPath]);
        return true;
      }

      debugPrint('当前平台不支持在文件管理器中定位路径');
      return false;
    } catch (e) {
      debugPrint('定位路径失败: $e');
      return false;
    }
  }
}
