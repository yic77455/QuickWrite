import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/services/database_service.dart';
import 'package:quick_write/core/services/cloud_sync/metadata_sync.dart';
import 'package:quick_write/core/services/cloud_sync/remote_storage.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:quick_write/core/services/cloud_sync/sync_planner.dart';
import 'package:quick_write/core/services/cloud_sync/sync_state_store.dart';
import 'package:quick_write/core/services/cloud_sync/sync_transfer.dart';
import 'package:quick_write/core/services/cloud_sync/workspace_indexer.dart';

/// 云同步引擎
///
/// 负责一次同步的完整流程，分为两个阶段：
/// 1. 元数据同步：先合并书籍、章节等实体，使本地具备正确的章节结构
/// 2. 正文同步：再索引本地文件、三方比对生成差异计划并执行传输
///
/// 两个阶段必须按此顺序执行：章节正文按固定的章节顺序划分同步单元，
/// 只有两端实体结构一致，划分结果才会一致，正文比对才有意义
class SyncEngine {
  SyncEngine({
    required RemoteStorage storage,
    required SyncStateStore stateStore,
    WorkspaceIndexer indexer = const WorkspaceIndexer(),
    SyncPlanner planner = const SyncPlanner(),
    bool packChapters = true,
  }) : _storage = storage,
       _stateStore = stateStore,
       _indexer = indexer,
       _planner = planner,
       _packChapters = packChapters,
       _transfer = SyncTransfer(storage: storage, stateStore: stateStore),
       _metadataSync = MetadataSync(storage: storage, stateStore: stateStore);

  /// 单次同步允许的最大并发传输数
  ///
  /// 网络传输是同步耗时的主要来源，适度并发可以明显缩短整体耗时，
  /// 但并发过高容易触发网盘限流，因此保持在较小范围
  static const int _maxConcurrency = 3;

  /// 远端通信客户端
  final RemoteStorage _storage;

  /// 本机同步状态存储
  final SyncStateStore _stateStore;

  /// 本地文件索引器
  final WorkspaceIndexer _indexer;

  /// 差异计划器
  final SyncPlanner _planner;

  /// 传输执行器
  final SyncTransfer _transfer;

  /// 元数据同步器
  final MetadataSync _metadataSync;

  /// 是否把章节合并为归档包传输
  ///
  /// 仅坚果云这类限制请求次数的平台开启；其余平台逐章传输，
  /// 每次同步只上传改动过的章节，节省流量
  final bool _packChapters;

  // ================= 差异比对 =================

  /// 生成本次同步的差异计划
  ///
  /// 仅基于当前本地实体推演，不会改动任何数据，可用于同步前的预演
  Future<SyncPlan> buildPlan() async {
    final index = await _buildIndex();
    return _buildPlanFrom(index);
  }

  // ================= 同步执行 =================

  /// 执行一次完整同步
  ///
  /// [onProgress] 用于上报正文文件的同步进度，参数依次为已处理数量与总数
  /// [onConfirmRisk] 在首次同步或影响面过大时调用，返回 false 表示用户未确认，
  /// 此时只完成元数据合并，正文传输会被中止
  Future<SyncSummary> sync({
    void Function(int done, int total)? onProgress,
    Future<bool> Function(SyncRiskAssessment risk)? onConfirmRisk,
  }) async {
    final isar = await _requireIsar();

    // 是否首次同步需在元数据合并前判断，合并过程本身会建立实体基线
    final isFirstSync = !_stateStore.hasBaselines;

    // 第一阶段：先合并元数据，本地实体结构就绪后再比对正文
    final metadataResult = await _metadataSync.run(isar: isar);

    // 被删除的词典需连带清理其远端文件，否则会在下一次同步被重新拉回
    await _applyDictDeletions(metadataResult.deletedDictIds);

    // 被删除的主题需连带清理其远端文件，否则会在下一次同步被重新拉回
    await _applyThemeDeletions(metadataResult.deletedThemeIds);

    // 第二阶段：正文同步
    final index = await _buildIndex();
    final plan = await _buildPlanFrom(index);

    // 查找待清理的远端书籍正文目录：删除不可逆，需在执行前纳入风险预检
    final deletableBookDirs = await _metadataSync.findDeletableBookDirs(
      metadataResult.deletedBookUuids,
    );

    // 风险预检：删除云端目录、首次同步或影响面过大时交由上层决定是否继续
    final risk = SyncRiskAssessment(
      isFirstSync: isFirstSync,
      planItemCount: plan.totalCount,
      localFileCount: index.files.length,
      uploadCount: plan.uploadCount,
      downloadCount: plan.downloadCount,
      conflictCount: plan.conflictCount,
      deletedBookDirCount: deletableBookDirs.length,
    );
    if (risk.needsConfirmation &&
        (onConfirmRisk == null || !await onConfirmRisk(risk))) {
      // 未确认时不清理远端目录，保留已完成的元数据合并结果，正文留待下次同步
      await _stateStore.save();
      return SyncSummary(
        outcomes: const [],
        cancelled: true,
        risk: risk,
        metadataUpsertCount: metadataResult.upsertCount,
        metadataRemovalCount: metadataResult.removalCount,
        metadataRemoteFileCount: metadataResult.remoteFileCount,
      );
    }

    // 确认通过后再执行不可逆的远端目录删除
    final deletedBookDirCount = await _metadataSync.deleteBookDirs(
      deletableBookDirs,
    );

    // 服务端开始限流时置位，用于提前停止派发新任务
    var rateLimited = false;
    final tasks = <Future<SyncOutcome> Function()>[];
    for (final item in plan.items) {
      tasks.add(() async {
        final outcome = await _runItem(item, index);
        if (!outcome.success && outcome.rateLimited) rateLimited = true;
        return outcome;
      });
    }

    final outcomes = await _runWithLimit(
      tasks,
      _maxConcurrency,
      () => rateLimited,
      onProgress: onProgress,
    );
    final integrityIssueCount = await _applyUploadBaselines(plan, outcomes);
    // 扫描阶段可能更新了章节正文的哈希缓存，统一落盘以便下次同步直接复用
    await _stateStore.save();

    return SyncSummary(
      outcomes: outcomes,
      abortedCount: plan.items.length - outcomes.length,
      metadataUpsertCount: metadataResult.upsertCount,
      metadataRemovalCount: metadataResult.removalCount,
      metadataRemoteFileCount: metadataResult.remoteFileCount,
      deletedBookDirCount: deletedBookDirCount,
      risk: risk,
      integrityIssueCount: integrityIssueCount,
    );
  }

  // ================= 内部实现 =================

  /// 清理已删除词典的远端文件
  ///
  /// 词典在文件层是普通文件，而文件层不对「本地缺失」做删除决策，
  /// 因此删除后的远端副本需在元数据确认删除记录后统一清理
  Future<void> _applyDictDeletions(Set<String> deletedDictIds) async {
    if (deletedDictIds.isEmpty) return;

    for (final id in deletedDictIds) {
      try {
        await _storage.deleteFile(_storage.remotePathOf(dictSyncKeyOf(id)));
      } catch (e) {
        // 单个词典清理失败不影响其余同步，遗留的远端文件会在下次同步重试
        debugPrint('清理远端词典失败: $id，$e');
      }
    }
  }

  /// 清理已删除主题的远端文件
  ///
  /// 主题在文件层是普通文件，而文件层不对「本地缺失」做删除决策，
  /// 因此删除后的远端副本需在元数据确认删除记录后统一清理
  Future<void> _applyThemeDeletions(Set<String> deletedThemeIds) async {
    if (deletedThemeIds.isEmpty) return;

    for (final id in deletedThemeIds) {
      try {
        await _storage.deleteFile(_storage.remotePathOf(themeSyncKeyOf(id)));
      } catch (e) {
        // 单个主题清理失败不影响其余同步，遗留的远端文件会在下次同步重试
        debugPrint('清理远端主题失败: $id，$e');
      }
    }
  }

  /// 扫描本地工作区
  ///
  /// 扫描结果同时携带章节正文的哈希缓存，写回状态存储后，
  /// 下次同步即可跳过未变化章节的内容读取与哈希计算
  Future<WorkspaceIndex> _buildIndex() async {
    final index = await _indexer.scan(
      isar: await _requireIsar(),
      baselines: _stateStore.baselines,
      cachedHashes: _stateStore.hashCache,
      packChapters: _packChapters,
    );

    // 扫描结果只写入独立的哈希缓存，不改动同步基线：
    // 基线必须保持「上次同步完成时」的状态，否则本地改动会被误判为已同步
    for (final entry in index.chapterHashCache.entries) {
      final cached = entry.value;
      _stateStore.cacheLocalHash(
        key: entry.key,
        hash: cached.hash,
        size: cached.size,
        modifiedAt: cached.modifiedAt,
      );
    }
    _stateStore.pruneChapterHashCache(index.chapterHashCache.keys.toSet());

    return index;
  }

  /// 结合远端清单生成差异计划
  Future<SyncPlan> _buildPlanFrom(WorkspaceIndex index) async {
    // 确保远端同步目录存在，避免首次同步时列举失败
    await _storage.ensureDirectory(_storage.remoteDir);

    // 只处理能在本地定位的文件：远端存在但本地数据库尚无对应实体的文件，
    // 需等待元数据同步在本机建立实体后才能落到具体路径
    final remoteFiles = (await _storage.listFilesRecursive())
        .where((file) => index.localPathOf(file.key) != null)
        .toList();

    return _planner.buildPlan(
      localFiles: index.files,
      remoteFiles: remoteFiles,
      baselines: _stateStore.baselines,
    );
  }

  /// 回填上传项的基线并校验上传结果
  ///
  /// 上传完成后需要记录远端的内容标识，才能在下一次同步中判断远端是否变化。
  /// 这里在全部传输结束后统一列举一次远端，用一次目录级请求换取
  /// 每个文件一次属性查询，大幅减少请求次数；
  /// 同时核对每个已上传文件是否已在远端就位，返回未能确认的数量
  Future<int> _applyUploadBaselines(
    SyncPlan plan,
    List<SyncOutcome> outcomes,
  ) async {
    final uploadedKeys = <String>{
      for (final outcome in outcomes)
        if (outcome.success && outcome.action == SyncAction.upload) outcome.key,
    };
    if (uploadedKeys.isEmpty) return 0;

    final List<RemoteSyncFile> remoteFiles;
    try {
      remoteFiles = await _storage.listFilesRecursive();
    } catch (e) {
      // 列举失败时不写入基线，下次同步会通过内容比对自动补齐
      debugPrint('回读远端内容标识失败，将在下次同步自动补齐: $e');
      return 0;
    }

    final remoteByKey = {for (final file in remoteFiles) file.key: file};
    final itemByKey = {for (final item in plan.items) item.key: item};

    var integrityIssueCount = 0;
    for (final key in uploadedKeys) {
      final local = itemByKey[key]?.local;
      final remote = remoteByKey[key];
      if (local == null || remote == null) {
        // 远端未能查到该文件，说明上传未真正落盘
        debugPrint('上传结果校验未通过，远端缺少: $key');
        integrityIssueCount++;
        continue;
      }

      _stateStore.recordSynced(
        key: key,
        localHash: local.contentHash,
        localSize: local.size,
        localModifiedAt: local.modifiedAt,
        remoteContentId: remote.contentId,
      );
    }

    return integrityIssueCount;
  }

  /// 执行单个计划项并把异常转换为执行结果
  Future<SyncOutcome> _runItem(SyncPlanItem item, WorkspaceIndex index) async {
    try {
      final copies = await _transfer.run(item, index);
      return SyncOutcome(
        key: item.key,
        action: item.action,
        success: true,
        conflictCopies: copies,
      );
    } catch (e) {
      debugPrint('同步失败 [${item.action.name}] ${item.key}: $e');
      return SyncOutcome(
        key: item.key,
        action: item.action,
        success: false,
        message: e.toString(),
        rateLimited: isRemoteRateLimitError(e),
      );
    }
  }

  /// 以受限并发执行任务
  ///
  /// [shouldStop] 返回 true 时不再派发新的任务，已派发的任务会自然结束
  /// [onProgress] 在每个任务结束后上报一次处理进度
  Future<List<SyncOutcome>> _runWithLimit(
    List<Future<SyncOutcome> Function()> tasks,
    int limit,
    bool Function() shouldStop, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (tasks.isEmpty) return [];

    final outcomes = <SyncOutcome>[];
    var nextIndex = 0;
    var completed = 0;
    onProgress?.call(0, tasks.length);

    Future<void> worker() async {
      while (true) {
        if (shouldStop()) return;

        final index = nextIndex++;
        if (index >= tasks.length) return;
        outcomes.add(await tasks[index]());
        onProgress?.call(++completed, tasks.length);
      }
    }

    final workerCount = limit < tasks.length ? limit : tasks.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return outcomes;
  }

  /// 获取应用数据库实例
  ///
  /// 数据库尚未打开时按完整集合定义打开，使同步不依赖其他模块的初始化顺序
  Future<Isar> _requireIsar() => DatabaseService.instance.open();
}
