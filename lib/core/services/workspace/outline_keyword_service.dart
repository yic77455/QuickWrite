import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/models/outline_note.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';
import 'package:quick_write/core/services/workspace/outline_companion_store.dart';
import 'package:quick_write/core/utils/relative_path_utils.dart';

/// 大纲关键词服务
///
/// 负责单本书「大纲节点绑定关键词」的读写与书籍级聚合索引：
/// - 关键词与关联、备注统一保存在设定项的合并伴生 `.json`；
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
      final String? settingItemPath = _settingItemPathOf(bookFolderPath, item);
      if (settingItemPath == null) continue;
      final OutlineCompanionData data = await OutlineCompanionStore.instance.read(settingItemPath);
      if (data.keywords.isEmpty) continue;
      _appendEntries(
        settingItemUuid: item.uuid,
        settingItemTitle: item.title,
        settingItemFilePath: settingItemPath,
        nodes: data.keywords,
        // 备注区保存的表格用于补齐旧版关键词快照中缺失的表格
        notes: data.notes,
      );
    }

    _rebuildKeywordIndex();
  }

  /// 读取单个设定项的关键词
  ///
  /// 返回「节点路径 → 节点关键词」的映射；文件不存在或格式非法时返回空映射。
  Future<Map<String, OutlineKeywordFileNode>> readSettingKeywords(String? settingItemFilePath) {
    return OutlineCompanionStore.instance.readKeywords(settingItemFilePath);
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
    // 过滤没有关键词的节点，避免把空条目写入伴生文件
    final Map<String, OutlineKeywordFileNode> serialized = {
      for (final entry in nodes.entries)
        if (entry.value.keywords.isNotEmpty) entry.key: entry.value,
    };

    final bool hadEntries = _entries.any((entry) => entry.settingItemUuid == settingItemUuid);
    final bool changed = await OutlineCompanionStore.instance.updateKeywords(
      settingItemFilePath,
      serialized,
    );

    // 关键词内容未变化时跳过索引重建；
    // 关键词已清空但索引仍留有该设定项条目时，需要刷新索引将其移除
    if (changed || (serialized.isEmpty && hadEntries)) {
      applySettingKeywords(
        settingItemUuid: settingItemUuid,
        settingItemTitle: settingItemTitle,
        settingItemFilePath: settingItemFilePath,
        nodes: serialized,
      );
    }
    return true;
  }

  /// 用最新的节点关键词替换指定设定项在索引中的条目（不写盘）
  ///
  /// 大纲编辑器在关键词变化后立即调用，使「关键词全局唯一」的冲突校验
  /// 不被自动保存的延迟影响；正文编辑器也会据此刷新高亮。
  /// [settingItemFilePath] 用于把节点图片文件名解析为绝对路径。
  void applySettingKeywords({
    required String settingItemUuid,
    required String settingItemTitle,
    required String? settingItemFilePath,
    required Map<String, OutlineKeywordFileNode> nodes,
  }) {
    _entries.removeWhere((entry) => entry.settingItemUuid == settingItemUuid);
    _appendEntries(
      settingItemUuid: settingItemUuid,
      settingItemTitle: settingItemTitle,
      settingItemFilePath: settingItemFilePath,
      nodes: nodes,
    );
    _rebuildKeywordIndex();
  }

  /// 计算设定项的绝对文件路径
  ///
  /// 设定项文件路径相对于书籍的 settings 目录存放；
  /// 相对路径为空时返回 null。
  String? _settingItemPathOf(String bookFolderPath, SettingItemModel item) {
    if (item.filePath.isEmpty) return null;
    return '$bookFolderPath${Platform.pathSeparator}settings${Platform.pathSeparator}'
        '${relativePathToPlatform(item.filePath)}';
  }

  /// 将单个设定项的关键词节点追加到索引列表
  ///
  /// 同一节点内的重复关键词会被忽略，无关键词的节点不产生条目；
  /// 节点与子孙节点的图片文件名在此按设定项目录解析为绝对路径，
  /// 供正文悬浮卡片直接展示缩略图。
  /// [notes] 提供按节点路径保存的备注数据，用于补齐关键词快照中缺失的表格。
  void _appendEntries({
    required String settingItemUuid,
    required String settingItemTitle,
    required String? settingItemFilePath,
    required Map<String, OutlineKeywordFileNode> nodes,
    Map<String, OutlineNoteData> notes = const {},
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
        imagePath: _resolveImagePath(settingItemFilePath, node.imageFileName),
        children: _resolveChildren(
          parentPath: path,
          children: node.children,
          settingItemFilePath: settingItemFilePath,
          notes: notes,
        ),
        keywords: keywords,
      ));
    }
  }

  /// 构建子孙节点快照，解析图片路径并补齐表格
  ///
  /// 快照按前序排列并记录相对层级，遍历时还原每个节点在设定项大纲中的路径，
  /// 据此从 [notes] 中取出该节点的表格，供正文悬浮卡片展示。
  List<OutlineKeywordSubNode> _resolveChildren({
    required String parentPath,
    required List<OutlineKeywordSubNode> children,
    required String? settingItemFilePath,
    required Map<String, OutlineNoteData> notes,
  }) {
    // 当前节点的各级索引，长度随遍历层级伸缩
    final List<int> indices = [];
    final List<OutlineKeywordSubNode> resolved = [];

    for (final child in children) {
      final int depth = child.depth < 1 ? 1 : child.depth;
      // 回到当前层级的父级，再把当前层级的索引加一
      if (indices.length > depth) {
        indices.removeRange(depth, indices.length);
      }
      if (indices.length == depth) {
        indices[depth - 1]++;
      } else {
        while (indices.length < depth) {
          indices.add(0);
        }
      }

      final String childPath = '$parentPath.${indices.join('.')}';
      resolved.add(child.withImagePath(
        _resolveImagePath(settingItemFilePath, child.imageFileName),
        table: notes[childPath]?.table,
      ));
    }
    return resolved;
  }

  /// 把节点图片文件名解析为绝对路径
  ///
  /// 图片统一存放在设定项文件所在目录的 image 文件夹，
  /// 文件名为空或路径缺失时返回空字符串。
  String _resolveImagePath(String? settingItemFilePath, String imageFileName) {
    if (imageFileName.isEmpty) return '';
    return BookFolderService.settingImageFilePath(settingItemFilePath, imageFileName) ?? '';
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
