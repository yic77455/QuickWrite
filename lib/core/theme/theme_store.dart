import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/theme/custom_theme.dart';

/// 自定义主题存取服务
///
/// 负责自定义主题 JSON 文件的读写，每个主题对应一个独立的 JSON 文件，
/// 文件名即主题 ID，文件内容遵循 [CustomTheme.toJson] 的结构：
/// ```json
/// {"id": "...", "name": "...", "light": {...}, "dark": {...}}
/// ```
///
/// 主题文件集中存放于应用目录下的 `theme/` 文件夹，删除主题即删除对应文件
class ThemeStore {
  // ================= 常量 =================

  /// 主题文件后缀名
  static const String _fileExtension = '.json';

  // ================= 加载主题 =================

  /// 加载全部自定义主题
  ///
  /// 枚举主题目录下的所有 `.json` 文件并逐一解析。单个文件解析失败会被跳过，
  /// 不影响其它主题加载。目录不存在时返回空列表。
  Future<List<CustomTheme>> loadAll() async {
    final result = <CustomTheme>[];
    try {
      final dir = Directory(await AppPaths.instance.getThemePath());
      if (!await dir.exists()) return result;

      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith(_fileExtension)) continue;
        try {
          final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          final theme = CustomTheme.fromJson(json);
          if (theme.id.isNotEmpty) result.add(theme);
        } catch (e) {
          debugPrint('ThemeStore: 解析主题失败 ${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('ThemeStore: 加载主题失败: $e');
    }
    return result;
  }

  // ================= 保存主题 =================

  /// 以 [themes] 为完整主题集合同步主题文件
  ///
  /// 写入列表中每个主题的文件，并删除目录中已不在列表内的主题文件，
  /// 使磁盘状态与传入集合保持一致。返回是否全部成功。
  Future<bool> syncAll(List<CustomTheme> themes) async {
    try {
      final dirPath = await AppPaths.instance.getThemePath();
      await _removeMissing(dirPath, {for (final theme in themes) theme.id});

      for (final theme in themes) {
        await _writeTheme(dirPath, theme);
      }
      return true;
    } catch (e) {
      debugPrint('ThemeStore: 保存主题失败: $e');
      return false;
    }
  }

  // ================= 内部实现 =================

  /// 删除目录中不在 [keepIds] 内的主题文件
  Future<void> _removeMissing(String dirPath, Set<String> keepIds) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith(_fileExtension)) continue;
      final id = _idOfFile(entity.path);
      if (id == null || !keepIds.contains(id)) {
        await entity.delete();
      }
    }
  }

  /// 将单个主题写入其对应的文件
  Future<void> _writeTheme(String dirPath, CustomTheme theme) async {
    final content = const JsonEncoder.withIndent('  ').convert(theme.toJson());
    await File(_filePathOf(dirPath, theme.id)).writeAsString(content);
  }

  // ================= 工具方法 =================

  /// 主题文件的完整路径
  String _filePathOf(String dirPath, String id) =>
      '$dirPath${Platform.pathSeparator}$id$_fileExtension';

  /// 从主题文件路径中解析主题 ID
  ///
  /// 文件名即主题 ID，无法识别时返回 null
  String? _idOfFile(String path) {
    final name = path.split(Platform.pathSeparator).last;
    if (!name.endsWith(_fileExtension)) return null;
    return name.substring(0, name.length - _fileExtension.length);
  }
}