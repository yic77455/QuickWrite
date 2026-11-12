import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/models/outline_link.dart';
import 'package:quick_write/core/models/outline_note.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';

/// 设定项大纲伴生数据集合
///
/// 关键词、关联与备注统一保存在同一个 `.json` 中，
/// 各字段按「层级索引路径」或标识与大纲节点对应。
/// 折叠状态属于本地界面状态，单独保存在 `.fold.json`，不在此列。
class OutlineCompanionData {
  /// 节点路径 → 关键词数据
  Map<String, OutlineKeywordFileNode> keywords;

  /// 关联标识 → 关联目标
  Map<String, OutlineLinkTarget> links;

  /// 节点路径 → 关联文本范围
  Map<String, List<OutlineLinkRange>> linkNodes;

  /// 节点路径 → 备注与图片数据
  Map<String, OutlineNoteData> notes;

  OutlineCompanionData({
    Map<String, OutlineKeywordFileNode>? keywords,
    Map<String, OutlineLinkTarget>? links,
    Map<String, List<OutlineLinkRange>>? linkNodes,
    Map<String, OutlineNoteData>? notes,
  })  : keywords = keywords ?? {},
        links = links ?? {},
        linkNodes = linkNodes ?? {},
        notes = notes ?? {};

  /// 是否没有任何有效内容
  bool get isEmpty =>
      keywords.values.every((node) => node.keywords.isEmpty) &&
      links.isEmpty &&
      linkNodes.values.every((ranges) => ranges.isEmpty) &&
      notes.values.every((note) => note.isEmpty);

  /// 全部合并 [other]（以 [other] 的条目覆盖同键数据）
  void mergeFrom(OutlineCompanionData other) {
    keywords.addAll(other.keywords);
    links.addAll(other.links);
    linkNodes.addAll(other.linkNodes);
    notes.addAll(other.notes);
  }
}

/// 大纲伴生文件读写
///
/// 所有读写操作在同一任务链中串行执行，避免关键词、关联、备注的保存
/// 并发读写同一文件而互相覆盖。
class OutlineCompanionStore {
  OutlineCompanionStore._();

  /// 全局单例
  static final OutlineCompanionStore instance = OutlineCompanionStore._();

  /// 读写任务链
  Future<void> _taskChain = Future.value();

  // ================= 对外接口 =================

  /// 读取设定项的伴生数据
  Future<OutlineCompanionData> read(String? settingItemFilePath) {
    return _enqueue(() => _loadData(settingItemFilePath));
  }

  /// 读取关键词
  Future<Map<String, OutlineKeywordFileNode>> readKeywords(String? settingItemFilePath) async {
    return (await read(settingItemFilePath)).keywords;
  }

  /// 读取关联目标与关联文本范围
  Future<OutlineLinkFile> readLinks(String? settingItemFilePath) async {
    final OutlineCompanionData data = await read(settingItemFilePath);
    return OutlineLinkFile(links: data.links, nodes: data.linkNodes);
  }

  /// 读取备注与图片
  Future<Map<String, OutlineNoteData>> readNotes(String? settingItemFilePath) async {
    return (await read(settingItemFilePath)).notes;
  }

  /// 更新伴生数据
  ///
  /// [mutate] 在读取到的最新数据上执行修改，返回值表示文件内容是否发生变化。
  Future<bool> update(
    String? settingItemFilePath,
    void Function(OutlineCompanionData data) mutate,
  ) {
    final String? metaPath = BookFolderService.outlineMetaFilePath(settingItemFilePath);
    if (metaPath == null) return Future.value(false);

    return _enqueue(() async {
      try {
        final OutlineCompanionData data = await _loadData(settingItemFilePath);
        final String before = _encode(data);
        mutate(data);
        final String after = _encode(data);
        if (before == after) return false;

        await _writeOrDelete(metaPath, data);
        CloudSyncService.instance.notifyLocalChange();
        return true;
      } catch (e) {
        debugPrint('保存大纲伴生文件失败: $e');
        return false;
      }
    });
  }

  /// 保存关键词数据
  Future<bool> updateKeywords(
    String? settingItemFilePath,
    Map<String, OutlineKeywordFileNode> nodes,
  ) {
    return update(settingItemFilePath, (data) {
      data.keywords = Map<String, OutlineKeywordFileNode>.of(nodes);
    });
  }

  /// 保存关联目标与关联文本范围
  Future<bool> updateLinks({
    required String? settingItemFilePath,
    required Map<String, OutlineLinkTarget> links,
    required Map<String, List<OutlineLinkRange>> nodes,
  }) {
    return update(settingItemFilePath, (data) {
      data.links = Map<String, OutlineLinkTarget>.of(links);
      data.linkNodes = {
        for (final entry in nodes.entries) entry.key: List<OutlineLinkRange>.of(entry.value),
      };
    });
  }

  /// 保存备注与图片数据
  Future<bool> updateNotes(
    String? settingItemFilePath,
    Map<String, OutlineNoteData> nodes,
  ) {
    return update(settingItemFilePath, (data) {
      data.notes = Map<String, OutlineNoteData>.of(nodes);
    });
  }

  /// 随设定项文件重命名或移动迁移伴生文件
  ///
  /// 旧路径的数据会合并到新路径：同键条目以旧路径（当前设定项）的数据为准，
  /// 新路径独有的条目保留；迁移完成后删除旧位置的伴生文件。
  Future<void> move(String? oldFilePath, String? newFilePath) {
    if (oldFilePath == null ||
        newFilePath == null ||
        oldFilePath.isEmpty ||
        newFilePath.isEmpty ||
        oldFilePath == newFilePath) {
      return Future.value();
    }

    final String? oldMetaPath = BookFolderService.outlineMetaFilePath(oldFilePath);
    final String? newMetaPath = BookFolderService.outlineMetaFilePath(newFilePath);
    if (oldMetaPath == null || newMetaPath == null) return Future.value();

    return _enqueue(() async {
      try {
        final OutlineCompanionData source = await _loadData(oldFilePath);
        final File oldFile = File(oldMetaPath);
        final bool hasOldFile = await oldFile.exists();
        if (source.isEmpty && !hasOldFile) return;

        final OutlineCompanionData target = await _loadData(newFilePath);
        target.mergeFrom(source);
        await _writeOrDelete(newMetaPath, target);

        if (await oldFile.exists()) {
          await oldFile.delete();
        }
        CloudSyncService.instance.notifyLocalChange();
      } catch (e) {
        debugPrint('迁移大纲伴生文件失败: $e');
      }
    });
  }

  // ================= 任务链 =================

  /// 把操作追加到任务链，保证同一时刻只有一个读写在执行
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _taskChain = _taskChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, stackTrace) {
        debugPrint('大纲伴生文件操作失败: $e');
        completer.completeError(e, stackTrace);
      }
    });
    return completer.future;
  }

  // ================= 读取 =================

  /// 读取伴生数据，文件不存在时返回空数据
  Future<OutlineCompanionData> _loadData(String? settingItemFilePath) async {
    final String? metaPath = BookFolderService.outlineMetaFilePath(settingItemFilePath);
    if (metaPath == null) return OutlineCompanionData();

    try {
      final File metaFile = File(metaPath);
      if (!await metaFile.exists()) return OutlineCompanionData();
      return _readMetaFile(metaFile);
    } catch (e) {
      debugPrint('读取大纲伴生文件失败: $e');
      return OutlineCompanionData();
    }
  }

  /// 解析合并伴生文件
  Future<OutlineCompanionData> _readMetaFile(File file) async {
    final Map<String, dynamic>? json = await _readJsonMap(file);
    if (json == null) return OutlineCompanionData();

    final Map<String, dynamic>? links = _asMap(json['links']);
    return OutlineCompanionData(
      keywords: _parseKeywords(json['keywords']),
      links: _parseLinkTargets(links?['links']),
      linkNodes: _parseLinkNodes(links?['nodes']),
      notes: _parseNotes(json['notes']),
    );
  }

  // ================= 写入 =================

  /// 写入或删除合并伴生文件
  Future<void> _writeOrDelete(String metaPath, OutlineCompanionData data) async {
    final File file = File(metaPath);

    // 没有任何内容时不保留空文件
    if (data.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }

    final String content = const JsonEncoder.withIndent('  ').convert(_toJson(data));
    if (await file.exists() && await file.readAsString() == content) return;

    final Directory parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
    await file.writeAsString(content);
  }

  /// 把数据编码为稳定顺序的 JSON 字符串，用于判断内容是否变化
  String _encode(OutlineCompanionData data) =>
      data.isEmpty ? '' : jsonEncode(_toJson(data));

  /// 转换为便于阅读和比对的 JSON 结构
  Map<String, dynamic> _toJson(OutlineCompanionData data) {
    final Map<String, dynamic> json = {'version': 2};

    final List<String> keywordPaths = data.keywords.keys
        .where((path) => data.keywords[path]!.keywords.isNotEmpty)
        .toList()
      ..sort(_compareNodePaths);
    if (keywordPaths.isNotEmpty) {
      json['keywords'] = {
        for (final path in keywordPaths) path: data.keywords[path]!.toJson(),
      };
    }

    final List<String> linkIds = data.links.keys.toList()..sort();
    final List<String> linkPaths = data.linkNodes.keys
        .where((path) => data.linkNodes[path]!.isNotEmpty)
        .toList()
      ..sort(_compareNodePaths);
    if (linkIds.isNotEmpty || linkPaths.isNotEmpty) {
      json['links'] = {
        if (linkIds.isNotEmpty)
          'links': {
            for (final id in linkIds) id: data.links[id]!.toJson(),
          },
        if (linkPaths.isNotEmpty)
          'nodes': {
            for (final path in linkPaths)
              path: [for (final range in data.linkNodes[path]!) range.toJson()],
          },
      };
    }

    final List<String> notePaths = data.notes.keys
        .where((path) => !data.notes[path]!.isEmpty)
        .toList()
      ..sort(_compareNodePaths);
    if (notePaths.isNotEmpty) {
      json['notes'] = {
        for (final path in notePaths) path: data.notes[path]!.toJson(),
      };
    }

    return json;
  }

  // ================= 解析工具 =================

  /// 解析关键词映射
  Map<String, OutlineKeywordFileNode> _parseKeywords(dynamic raw) {
    final Map<String, OutlineKeywordFileNode> result = {};
    final Map<String, dynamic>? map = _asMap(raw);
    if (map == null) return result;
    for (final entry in map.entries) {
      final Map<String, dynamic>? value = _asMap(entry.value);
      if (entry.key.isEmpty || value == null) continue;
      result[entry.key] = OutlineKeywordFileNode.fromJson(value);
    }
    return result;
  }

  /// 解析关联目标映射
  Map<String, OutlineLinkTarget> _parseLinkTargets(dynamic raw) {
    final Map<String, OutlineLinkTarget> result = {};
    final Map<String, dynamic>? map = _asMap(raw);
    if (map == null) return result;
    for (final entry in map.entries) {
      final Map<String, dynamic>? value = _asMap(entry.value);
      if (entry.key.isEmpty || value == null) continue;
      result[entry.key] = OutlineLinkTarget.fromJson(value).copyWith(id: entry.key);
    }
    return result;
  }

  /// 解析节点路径到关联文本范围的映射
  Map<String, List<OutlineLinkRange>> _parseLinkNodes(dynamic raw) {
    final Map<String, List<OutlineLinkRange>> result = {};
    final Map<String, dynamic>? map = _asMap(raw);
    if (map == null) return result;
    for (final entry in map.entries) {
      final dynamic rawRanges = entry.value;
      if (entry.key.isEmpty || rawRanges is! List) continue;

      final List<OutlineLinkRange> ranges = [];
      for (final range in rawRanges) {
        final Map<String, dynamic>? value = _asMap(range);
        if (value == null) continue;
        ranges.add(OutlineLinkRange.fromJson(value));
      }
      if (ranges.isNotEmpty) result[entry.key] = ranges;
    }
    return result;
  }

  /// 解析节点路径到备注与图片的映射
  Map<String, OutlineNoteData> _parseNotes(dynamic raw) {
    final Map<String, OutlineNoteData> result = {};
    final Map<String, dynamic>? map = _asMap(raw);
    if (map == null) return result;
    for (final entry in map.entries) {
      final Map<String, dynamic>? value = _asMap(entry.value);
      if (entry.key.isEmpty || value == null) continue;
      final OutlineNoteData note = OutlineNoteData.fromJson(value);
      if (note.isEmpty) continue;
      result[entry.key] = note;
    }
    return result;
  }

  /// 读取 JSON 对象，文件不存在或格式非法时返回 null
  Future<Map<String, dynamic>?> _readJsonMap(File file) async {
    try {
      if (!await file.exists()) return null;
      final dynamic decoded = jsonDecode(await file.readAsString());
      return _asMap(decoded);
    } catch (e) {
      debugPrint('解析大纲伴生文件失败: ${file.path}，$e');
      return null;
    }
  }

  /// 转换为字符串键的 Map，非 Map 类型返回 null
  Map<String, dynamic>? _asMap(dynamic value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  /// 比较两个节点层级路径的先后顺序
  ///
  /// 路径形如 `0.2.1`，按每级索引数值比较，保证同级顺序与大纲树一致。
  int _compareNodePaths(String a, String b) {
    final List<int> segmentsA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final List<int> segmentsB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final int length = segmentsA.length < segmentsB.length ? segmentsA.length : segmentsB.length;
    for (int i = 0; i < length; i++) {
      final int diff = segmentsA[i] - segmentsB[i];
      if (diff != 0) return diff;
    }
    return segmentsA.length - segmentsB.length;
  }
}
