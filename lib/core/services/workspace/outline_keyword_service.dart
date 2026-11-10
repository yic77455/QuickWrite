import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';
import 'package:quick_write/core/utils/relative_path_utils.dart';

/// 大纲关键词服务
///
/// 负责单本书「大纲节点绑定关键词」的读写与书籍级聚合索引：
/// - 每个设定项的关键词持久化到与设定项文件同名的伴生 `.kw.json`；
/// - 加载时聚合全部设定项的关键词，建立「关键词 → 绑定节点」的一对一索引，
///   供正文编辑器在 Ctrl 状态下高亮、悬停预览与跳转；
/// - 关键词在整本书内唯一，重复绑定时按设定项顺序保留第一条。
///
/// 生命周期由 [WorkspaceProvider] 管理：每本书的工作台持有一个独立实例。
class OutlineKeywordService extends ChangeNotifier {
  /// 书籍级关键词索引项（按设定项顺序排列）
  final List<OutlineKeywordEntry> _entries = [];

  /// 关键词到绑定节点的映射（关键词全局唯一）
  final Map<String, OutlineKeywordEntry> _byKeyword = {};

  /// 索引版本号
  ///
  /// 每次索引变化时递增，供正文编辑器的样式构建器判断是否需要重算缓存。
  int _revision = 0;

  /// 当前书籍的全部关键词索引项（只读）
  List<OutlineKeywordEntry> get entries => List.unmodifiable(_entries);

  /// 索引版本号
  int get revision => _revision;

  /// 书籍内全部已绑定的关键词（只读）
  Iterable<String> get keywords => _byKeyword.keys;

  /// 查询关键词绑定的节点（未绑定时返回 null）
  OutlineKeywordEntry? entryForKeyword(String keyword) => _byKeyword[keyword];

  /// 查询关键词当前绑定的节点，用于新增关键词时的冲突校验
  OutlineKeywordEntry? findKeywordOwner(String keyword) => _byKeyword[keyword];

  /// 从指定书籍目录加载全部设定项的关键词
  ///
  /// [settingItems] 用于把伴生文件路径映射回设定项 UUID 与标题；
  /// 单个文件读取失败只跳过该文件，不影响其它设定项。
  Future<void> load({
    required String bookFolderPath,
    required List<SettingItemModel> settingItems,
  }) async {
    _entries.clear();

    for (final item in settingItems) {
      final String? keywordPath = _keywordPathOfItem(bookFolderPath, item);
      if (keywordPath == null) continue;
      final Map<String, OutlineKeywordFileNode> nodes = await _readKeywordFile(keywordPath);
      if (nodes.isEmpty) continue;
      _appendEntries(settingItemUuid: item.uuid, settingItemTitle: item.title, nodes: nodes);
    }

    _rebuildKeywordIndex();
  }

  /// 读取单个设定项的关键词文件内容
  ///
  /// 返回「节点路径 → 节点关键词」的映射；文件不存在或格式非法时返回空映射。
  Future<Map<String, OutlineKeywordFileNode>> readSettingKeywords(String? settingItemFilePath) {
    final String? keywordPath = BookFolderService.keywordFilePath(settingItemFilePath);
    if (keywordPath == null) return Future.value(<String, OutlineKeywordFileNode>{});
    return _readKeywordFile(keywordPath);
  }

  /// 保存单个设定项的关键词并同步内存索引
  ///
  /// [nodes] 为当前大纲树中带关键词的节点（含文本、子孙节点快照与关键词）；
  /// 写入完成后刷新该设定项在书籍索引中的条目，使正文编辑器无需重启即可生效。
  Future<bool> saveSettingKeywords({
    required String settingItemFilePath,
    required String settingItemUuid,
    required String settingItemTitle,
    required Map<String, OutlineKeywordFileNode> nodes,
  }) async {
    final String? keywordPath = BookFolderService.keywordFilePath(settingItemFilePath);
    if (keywordPath == null) return false;

    try {
      final File file = File(keywordPath);

      // 按节点路径排序后写入，保证文件内容稳定、便于比对
      final List<String> paths = nodes.keys.toList()..sort(_compareNodePaths);
      final Map<String, dynamic> serialized = {};
      for (final path in paths) {
        final OutlineKeywordFileNode node = nodes[path]!;
        if (node.keywords.isEmpty) continue;
        serialized[path] = node.toJson();
      }

      // 没有任何关键词时不保留空文件，同时清理历史上可能残留的空配置
      if (serialized.isEmpty) {
        final bool fileExists = await file.exists();
        if (fileExists) {
          await file.delete();
          CloudSyncService.instance.notifyLocalChange();
        }
        // 仅当文件确实被删除或索引中仍有该设定项的条目时才刷新索引，
        // 避免没有关键词的设定项在每次输入时都触发全量索引重建
        final bool hasEntries = _entries.any((entry) => entry.settingItemUuid == settingItemUuid);
        if (fileExists || hasEntries) {
          applySettingKeywords(
            settingItemUuid: settingItemUuid,
            settingItemTitle: settingItemTitle,
            nodes: const {},
          );
        }
        return true;
      }

      final String content = const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'nodes': serialized,
      });
      // 内容未变化时跳过写入，避免自动保存反复产生无意义的磁盘写入与云同步
      if (await file.exists() && await file.readAsString() == content) return true;

      final Directory parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString(content);
      // 关键词配置已落盘，交由云同步服务安排一次同步
      CloudSyncService.instance.notifyLocalChange();
    } catch (e) {
      debugPrint('保存大纲关键词失败: $e');
      return false;
    }

    // 保存成功后同步内存索引，保证同一会话内的冲突校验与正文高亮立即生效
    applySettingKeywords(
      settingItemUuid: settingItemUuid,
      settingItemTitle: settingItemTitle,
      nodes: nodes,
    );
    return true;
  }

  /// 用最新的节点关键词替换指定设定项在索引中的条目（不写盘）
  ///
  /// 大纲编辑器在关键词变化后立即调用，使「关键词全局唯一」的冲突校验
  /// 不被自动保存的延迟影响；正文编辑器也会据此刷新高亮。
  void applySettingKeywords({
    required String settingItemUuid,
    required String settingItemTitle,
    required Map<String, OutlineKeywordFileNode> nodes,
  }) {
    _entries.removeWhere((entry) => entry.settingItemUuid == settingItemUuid);
    _appendEntries(settingItemUuid: settingItemUuid, settingItemTitle: settingItemTitle, nodes: nodes);
    _rebuildKeywordIndex();
  }

  /// 随大纲文件重命名迁移关键词文件
  Future<void> renameSettingKeywords(String? oldFilePath, String? newFilePath) async {
    final String? oldKeywordPath = BookFolderService.keywordFilePath(oldFilePath);
    final String? newKeywordPath = BookFolderService.keywordFilePath(newFilePath);
    if (oldKeywordPath == null || newKeywordPath == null || oldKeywordPath == newKeywordPath) {
      return;
    }

    try {
      final File oldFile = File(oldKeywordPath);
      if (!await oldFile.exists()) return;
      final File newFile = File(newKeywordPath);
      if (!await newFile.parent.exists()) {
        await newFile.parent.create(recursive: true);
      }
      // 目标文件已存在时先移除，避免重命名因目标存在而失败
      if (await newFile.exists()) {
        await newFile.delete();
      }
      await oldFile.rename(newKeywordPath);
      // 关键词文件参与云同步，重命名后安排一次同步
      CloudSyncService.instance.notifyLocalChange();
    } catch (e) {
      debugPrint('重命名大纲关键词文件失败: $e');
    }
  }

  /// 计算设定项对应的关键词文件绝对路径
  ///
  /// 设定项文件路径相对于书籍的 settings 目录存放，此处在拼接绝对路径后
  /// 再替换为关键词文件后缀；相对路径为空时返回 null。
  String? _keywordPathOfItem(String bookFolderPath, SettingItemModel item) {
    if (item.filePath.isEmpty) return null;
    final String settingItemPath =
        '$bookFolderPath${Platform.pathSeparator}settings${Platform.pathSeparator}'
        '${relativePathToPlatform(item.filePath)}';
    return BookFolderService.keywordFilePath(settingItemPath);
  }

  /// 读取关键词文件并解析为「节点路径 → 节点关键词」映射
  Future<Map<String, OutlineKeywordFileNode>> _readKeywordFile(String keywordPath) async {
    try {
      final File file = File(keywordPath);
      if (!await file.exists()) return const {};

      final dynamic data = jsonDecode(await file.readAsString());
      if (data is! Map) return const {};
      final dynamic nodes = data['nodes'];
      if (nodes is! Map) return const {};

      final Map<String, OutlineKeywordFileNode> result = {};
      for (final entry in nodes.entries) {
        final String path = entry.key.toString();
        final dynamic value = entry.value;
        if (path.isEmpty || value is! Map) continue;
        result[path] = OutlineKeywordFileNode.fromJson(Map<String, dynamic>.from(value));
      }
      return result;
    } catch (e) {
      debugPrint('读取大纲关键词失败: $e');
      return const {};
    }
  }

  /// 将单个设定项的关键词节点追加到索引列表
  ///
  /// 同一节点内的重复关键词会被忽略，无关键词的节点不产生条目。
  void _appendEntries({
    required String settingItemUuid,
    required String settingItemTitle,
    required Map<String, OutlineKeywordFileNode> nodes,
  }) {
    final List<String> paths = nodes.keys.toList()..sort(_compareNodePaths);
    for (final path in paths) {
      final OutlineKeywordFileNode node = nodes[path]!;
      final List<OutlineKeyword> keywords = _dedupeKeywords(node.keywords);
      if (keywords.isEmpty) continue;
      _entries.add(OutlineKeywordEntry(
        settingItemUuid: settingItemUuid,
        settingItemTitle: settingItemTitle,
        nodePath: path,
        nodeText: node.text,
        children: node.children,
        keywords: keywords,
      ));
    }
  }

  /// 过滤空关键词与同一节点内的重复关键词
  List<OutlineKeyword> _dedupeKeywords(List<OutlineKeyword> keywords) {
    final Set<String> seen = {};
    final List<OutlineKeyword> result = [];
    for (final keyword in keywords) {
      final String text = keyword.keyword.trim();
      if (text.isEmpty || !seen.add(text)) continue;
      result.add(keyword.copyWith(keyword: text));
    }
    return result;
  }

  /// 重建关键词索引并通知监听者
  ///
  /// 关键词全局唯一：出现多个节点绑定同一关键词时，保留索引顺序中先出现的一条。
  void _rebuildKeywordIndex() {
    _byKeyword.clear();
    for (final entry in _entries) {
      for (final keyword in entry.keywords) {
        final OutlineKeywordEntry? existing = _byKeyword[keyword.keyword];
        if (existing != null) {
          if (existing.settingItemUuid != entry.settingItemUuid || existing.nodePath != entry.nodePath) {
            debugPrint('关键词「${keyword.keyword}」重复绑定，已保留先绑定的节点');
          }
          continue;
        }
        _byKeyword[keyword.keyword] = entry;
      }
    }
    _revision++;
    notifyListeners();
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
