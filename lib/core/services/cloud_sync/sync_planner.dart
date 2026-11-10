import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';

/// 云同步计划器
///
/// 依据三方比对（本地现状、远端现状、上次同步基线）为每个逻辑文件决策处理动作。
/// 判定不依赖「谁的时间更新」，而是分别判断两端相对基线是否发生变更：
/// - 仅本地变更：上传
/// - 仅远端变更：下载
/// - 仅一端存在：补齐缺失的一方，不做删除
/// - 两端都存在且都变更：保留双份，绝不覆盖
/// - 两端都未变更：跳过
///
/// 文件的缺失是歧义的（被删除、尚未下载、本地丢失），因此本层一般不做删除决策；
/// 仅有设定项派生的伴生文件（关键词、关联）在确认本地删除时清理远端副本，
/// 避免旧副本在下次同步被重新下载。实体删除仍由元数据同步通过删除记录统一负责
class SyncPlanner {
  const SyncPlanner();

  /// 生成同步计划
  ///
  /// [localFiles] 本地逻辑文件表
  /// [remoteFiles] 远端文件清单
  /// [baselines] 上次同步基线
  SyncPlan buildPlan({
    required List<LocalSyncFile> localFiles,
    required List<RemoteSyncFile> remoteFiles,
    required Map<String, SyncBaselineRecord> baselines,
  }) {
    final localMap = {for (final file in localFiles) file.key: file};
    final remoteMap = {for (final file in remoteFiles) file.key: file};
    final localKeys = localMap.keys.toSet();

    // 逻辑键全集：任意一端存在或基线中留有记录的文件都需要比对
    final keys = <String>{
      ...localMap.keys,
      ...remoteMap.keys,
      ...baselines.keys,
    };

    final items = <SyncPlanItem>[];
    for (final key in keys) {
      final action = _decide(
        key: key,
        local: localMap[key],
        remote: remoteMap[key],
        baseline: baselines[key],
        localKeys: localKeys,
      );
      if (action == null) continue;
      items.add(
        SyncPlanItem(
          key: key,
          action: action,
          local: localMap[key],
          remote: remoteMap[key],
        ),
      );
    }

    // 按逻辑键排序，保证计划输出稳定，便于预览与排查
    items.sort((a, b) => a.key.compareTo(b.key));
    return SyncPlan(items);
  }

  /// 决策单个逻辑文件的处理动作
  ///
  /// 返回 null 表示无需处理
  SyncAction? _decide({
    required String key,
    LocalSyncFile? local,
    RemoteSyncFile? remote,
    SyncBaselineRecord? baseline,
    required Set<String> localKeys,
  }) {
    // 基线被标记为墓碑时，等同于没有基线，文件视为重新出现
    final hasBaseline = baseline != null && !baseline.deleted;

    // 本地相对基线是否发生变更（新增或内容改动）
    final localChanged =
        !hasBaseline || baseline.localHash != local?.contentHash;
    // 远端相对基线是否发生变更（新增或内容改动）
    final remoteChanged =
        !hasBaseline || baseline.remoteContentId != remote?.contentId;

    // 两端都不存在，无需处理
    if (local == null && remote == null) return null;

    // 仅本地存在：远端缺少该文件属于内容缺失，重新上传
    if (local != null && remote == null) return SyncAction.upload;

    // 仅远端存在：本地缺少该文件，通常重新下载；
    // 设定项伴生文件被主动删除时改为清理远端副本
    if (local == null && remote != null) {
      if (_shouldDeleteRemoteCompanion(
        key: key,
        remote: remote,
        baseline: baseline,
        localKeys: localKeys,
      )) {
        return SyncAction.deleteRemote;
      }
      return SyncAction.download;
    }

    // 两端都存在
    if (!hasBaseline) return SyncAction.keepBoth; // 两端各自新增同一文件
    if (localChanged && remoteChanged) return SyncAction.keepBoth; // 两端都改
    if (localChanged) return SyncAction.upload;
    if (remoteChanged) return SyncAction.download;
    return null; // 两端均未变更，跳过
  }

  /// 判断本地缺失的远端伴生文件是否应删除远端副本
  ///
  /// 满足以下条件时才删除，避免误删：
  /// - 上次同步留有基线，说明该伴生文件曾在本地存在
  /// - 远端内容自上次同步后未变化，其他设备新增的内容不被覆盖
  /// - 对应的设定项正文仍在本地，书籍目录整体不可用时不会误删云端文件
  bool _shouldDeleteRemoteCompanion({
    required String key,
    required RemoteSyncFile remote,
    required SyncBaselineRecord? baseline,
    required Set<String> localKeys,
  }) {
    if (baseline == null || baseline.deleted) return false;
    if (!BookFolderService.isSettingCompanionFile(key)) return false;

    final String? mainKey = _mainSettingKeyOf(key);
    if (mainKey == null || !localKeys.contains(mainKey)) return false;

    return baseline.remoteContentId == remote.contentId;
  }

  /// 由伴生文件逻辑键推导设定项正文的逻辑键
  ///
  /// 伴生文件与设定项文件同目录同名，仅扩展名不同。
  String? _mainSettingKeyOf(String key) {
    for (final String suffix in BookFolderService.settingCompanionFileSuffixes) {
      if (!key.endsWith(suffix)) continue;
      final String base = key.substring(0, key.length - suffix.length);
      return '$base${GlobalConstants.settingFileExtension}';
    }
    return null;
  }
}
