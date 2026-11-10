import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/models/outline_link.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';

/// 大纲关联服务
///
/// 负责单个设定项「大纲节点文本关联到其他文件」的持久化读写：
/// 关联目标与关联文本范围统一保存在与设定项文件同名的伴生 `.link.json` 中，
/// 与大纲 Markdown 分离，避免关联信息影响导出与备份内容。
class OutlineLinkService {
  /// 读取设定项的关联文件内容
  ///
  /// 文件不存在或格式非法时返回空内容。
  Future<OutlineLinkFile> read(String? settingItemFilePath) async {
    final String? linkPath = BookFolderService.linkFilePath(settingItemFilePath);
    if (linkPath == null) return OutlineLinkFile.empty;

    try {
      final File file = File(linkPath);
      if (!await file.exists()) return OutlineLinkFile.empty;

      final dynamic data = jsonDecode(await file.readAsString());
      if (data is! Map) return OutlineLinkFile.empty;

      // 解析关联标识到关联目标的映射
      final Map<String, OutlineLinkTarget> links = {};
      final dynamic rawLinks = data['links'];
      if (rawLinks is Map) {
        for (final entry in rawLinks.entries) {
          final String id = entry.key.toString();
          final dynamic value = entry.value;
          if (id.isEmpty || value is! Map) continue;
          links[id] = OutlineLinkTarget.fromJson(Map<String, dynamic>.from(value));
        }
      }

      // 解析节点路径到关联文本范围的映射
      final Map<String, List<OutlineLinkRange>> nodes = {};
      final dynamic rawNodes = data['nodes'];
      if (rawNodes is Map) {
        for (final entry in rawNodes.entries) {
          final String path = entry.key.toString();
          final dynamic value = entry.value;
          if (path.isEmpty || value is! List) continue;
          final List<OutlineLinkRange> ranges = [
            for (final range in value)
              if (range is Map<String, dynamic>) OutlineLinkRange.fromJson(range),
          ];
          if (ranges.isNotEmpty) nodes[path] = ranges;
        }
      }

      return OutlineLinkFile(links: links, nodes: nodes);
    } catch (e) {
      debugPrint('读取大纲关联失败: $e');
      return OutlineLinkFile.empty;
    }
  }

  /// 保存设定项的关联文件
  ///
  /// [links] 为关联标识到关联目标的映射，[nodes] 为节点路径到关联文本范围的映射；
  /// 两者均无内容时删除伴生文件，避免残留空配置。
  Future<bool> save({
    required String? settingItemFilePath,
    required Map<String, OutlineLinkTarget> links,
    required Map<String, List<OutlineLinkRange>> nodes,
  }) async {
    final String? linkPath = BookFolderService.linkFilePath(settingItemFilePath);
    if (linkPath == null) return false;

    try {
      final File file = File(linkPath);

      // 按节点路径与关联标识排序后写入，保证文件内容稳定、便于比对
      final List<String> paths = nodes.keys.toList()..sort(_compareNodePaths);
      final Map<String, dynamic> serializedNodes = {};
      for (final path in paths) {
        final List<OutlineLinkRange> ranges = nodes[path] ?? const [];
        if (ranges.isEmpty) continue;
        serializedNodes[path] = [for (final range in ranges) range.toJson()];
      }

      final List<String> linkIds = links.keys.toList()..sort();
      final Map<String, dynamic> serializedLinks = {
        for (final id in linkIds) id: links[id]!.toJson(),
      };

      // 没有任何关联时不保留空文件，同时清理历史上可能残留的空配置
      if (serializedNodes.isEmpty || serializedLinks.isEmpty) {
        final bool fileExists = await file.exists();
        if (fileExists) {
          await file.delete();
          CloudSyncService.instance.notifyLocalChange();
        }
        return true;
      }

      final String content = const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'links': serializedLinks,
        'nodes': serializedNodes,
      });
      // 内容未变化时跳过写入，避免自动保存反复产生无意义的磁盘写入与云同步
      if (await file.exists() && await file.readAsString() == content) return true;

      final Directory parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString(content);
      // 关联配置已落盘，交由云同步服务安排一次同步
      CloudSyncService.instance.notifyLocalChange();
      return true;
    } catch (e) {
      debugPrint('保存大纲关联失败: $e');
      return false;
    }
  }

  /// 随大纲文件重命名迁移关联文件
  Future<void> rename(String? oldFilePath, String? newFilePath) async {
    final String? oldLinkPath = BookFolderService.linkFilePath(oldFilePath);
    final String? newLinkPath = BookFolderService.linkFilePath(newFilePath);
    if (oldLinkPath == null || newLinkPath == null || oldLinkPath == newLinkPath) {
      return;
    }

    try {
      final File oldFile = File(oldLinkPath);
      if (!await oldFile.exists()) return;
      final File newFile = File(newLinkPath);
      if (!await newFile.parent.exists()) {
        await newFile.parent.create(recursive: true);
      }
      // 目标文件已存在时先移除，避免重命名因目标存在而失败
      if (await newFile.exists()) {
        await newFile.delete();
      }
      await oldFile.rename(newLinkPath);
      // 关联文件参与云同步，重命名后安排一次同步
      CloudSyncService.instance.notifyLocalChange();
    } catch (e) {
      debugPrint('重命名大纲关联文件失败: $e');
    }
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
