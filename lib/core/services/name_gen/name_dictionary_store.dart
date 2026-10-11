import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 词典存取服务
///
/// 负责取名词典 JSON 文件的读写，每个词典对应一个独立的 JSON 文件，
/// 文件内容遵循 [NameDictionary.toJson] 的结构：
/// ```json
/// {"id": "...", "name": "...", "category": "person|place",
///  "isBuiltin": true, "givenFirst": false, "pools": {...}}
/// ```
///
/// 词典按来源分为两类：
/// - 内置词典：存放于打包资源 `assets/dict/` 目录下，只读，来源于应用；
/// - 自定义词典：存放于应用目录下的 `dict/` 文件夹，由用户创建，可读写。
class NameDictionaryStore {
  // ================= 常量 =================

  /// 内置词典所在的资源目录
  static const String _assetDir = 'assets/dict';

  /// 词典文件后缀名
  static const String _fileExtension = '.json';

  // ================= 加载内置词典 =================

  /// 加载全部内置词典
  ///
  /// 枚举资源目录下的所有 `.json` 文件并逐一解析。词典来源为应用内置资源，
  /// 因此统一将 isBuiltin 置为 true。单个文件解析失败会被跳过，不影响其它词典。
  Future<List<NameDictionary>> loadBuiltinDictionaries() async {
    final result = <NameDictionary>[];
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest.listAssets().where(
          (key) => key.startsWith('$_assetDir/') && key.endsWith(_fileExtension),
        );
    for (final key in keys) {
      try {
        final content = await rootBundle.loadString(key);
        final dictionary = _parse(content);
        if (dictionary != null) {
          result.add(dictionary.copyWith(isBuiltin: true));
        }
      } catch (e) {
        debugPrint('NameDictionaryStore: 解析内置词典失败 $key: $e');
      }
    }
    return result;
  }

  // ================= 加载自定义词典 =================

  /// 加载全部自定义词典
  ///
  /// 枚举应用词典目录下的所有 `.json` 文件并逐一解析。词典来源为用户数据，
  /// 因此统一将 isBuiltin 置为 false。目录不存在或单个文件解析失败会被跳过。
  Future<List<NameDictionary>> loadCustomDictionaries() async {
    final result = <NameDictionary>[];
    try {
      final dir = Directory(await AppPaths.instance.getDictPath());
      if (!await dir.exists()) return result;
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith(_fileExtension)) continue;
        try {
          final content = await entity.readAsString();
          final dictionary = _parse(content);
          if (dictionary != null) {
            result.add(dictionary.copyWith(isBuiltin: false));
          }
        } catch (e) {
          debugPrint('NameDictionaryStore: 解析自定义词典失败 ${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('NameDictionaryStore: 加载自定义词典失败: $e');
    }
    return result;
  }

  // ================= 写入自定义词典 =================

  /// 保存自定义词典
  ///
  /// 以词典 ID 作为文件名写入应用词典目录。写入内容固定为非内置词典，
  /// 返回是否保存成功。
  Future<bool> saveDictionary(NameDictionary dictionary) async {
    try {
      final dirPath = await AppPaths.instance.getDictPath();
      final file = File(p.join(dirPath, '${dictionary.id}$_fileExtension'));
      final content = const JsonEncoder.withIndent('  ')
          .convert(dictionary.copyWith(isBuiltin: false).toJson());
      await file.writeAsString(content);
      return true;
    } catch (e) {
      debugPrint('NameDictionaryStore: 保存自定义词典失败 ${dictionary.id}: $e');
      return false;
    }
  }

  /// 删除自定义词典
  ///
  /// 删除应用词典目录下与词典 ID 对应的文件，文件不存在视为删除成功。
  Future<bool> deleteDictionary(String id) async {
    try {
      final dirPath = await AppPaths.instance.getDictPath();
      final file = File(p.join(dirPath, '$id$_fileExtension'));
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      debugPrint('NameDictionaryStore: 删除自定义词典失败 $id: $e');
      return false;
    }
  }

  // ================= 工具方法 =================

  /// 解析词典 JSON 文本，解析失败返回 null
  NameDictionary? _parse(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      return NameDictionary.fromJson(json);
    } catch (e) {
      debugPrint('NameDictionaryStore: 词典 JSON 解析失败: $e');
      return null;
    }
  }
}
