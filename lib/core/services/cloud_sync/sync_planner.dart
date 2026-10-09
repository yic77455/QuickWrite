import 'package:quick_write/core/services/cloud_sync/sync_models.dart';

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
/// 文件的缺失是歧义的（被删除、尚未下载、本地丢失），因此本层不做删除决策；
/// 实体的删除由元数据同步通过删除记录统一负责
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

    // 逻辑键全集：任意一端存在或基线中留有记录的文件都需要比对
    final keys = <String>{
      ...localMap.keys,
      ...remoteMap.keys,
      ...baselines.keys,
    };

    final items = <SyncPlanItem>[];
    for (final key in keys) {
      final action = _decide(
        local: localMap[key],
        remote: remoteMap[key],
        baseline: baselines[key],
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
    LocalSyncFile? local,
    RemoteSyncFile? remote,
    SyncBaselineRecord? baseline,
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

    // 仅远端存在：本地缺少该文件，重新下载
    if (local == null && remote != null) return SyncAction.download;

    // 两端都存在
    if (!hasBaseline) return SyncAction.keepBoth; // 两端各自新增同一文件
    if (localChanged && remoteChanged) return SyncAction.keepBoth; // 两端都改
    if (localChanged) return SyncAction.upload;
    if (remoteChanged) return SyncAction.download;
    return null; // 两端均未变更，跳过
  }
}
