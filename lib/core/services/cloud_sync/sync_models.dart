/// 云同步逻辑文件模型
///
/// 定义同步过程中涉及的本地文件、远端文件、同步基线与同步计划的统一表示。
/// 其中「逻辑键」是文件在同步命名空间中的唯一标识，等同于该文件在远端的相对路径，
/// 例如 `books/{书籍UUID}/chapters/{章节UUID}.txt`，与本地书名无关
library;

/// 同步过程中临时文件使用的后缀
///
/// 上传与下载都先把数据写到临时文件，确认完整后再替换目标文件，
/// 同时索引本地文件时会跳过该后缀，避免临时文件被当作正式文件同步
const String kSyncTempSuffix = '.qwsync-tmp';

/// 触发用户确认的同步影响面比例阈值
///
/// 一次同步需要处理的文件占本地文件总数的比例超过该值时，
/// 视为改动面过大，需要用户确认后再执行
const double kSyncImpactConfirmRatio = 0.3;

/// 触发影响面确认所需的最少文件数量
///
/// 本地内容较少时占比天然偏高，设置下限可避免小幅改动被反复要求确认
const int kSyncImpactMinItemCount = 20;

/// 本地逻辑文件
///
/// 表示一个参与同步的本地文件及其当前内容特征
class LocalSyncFile {
  /// 逻辑键（等于远端相对路径，统一使用正斜杠分隔）
  final String key;

  /// 本地文件的绝对路径
  final String localPath;

  /// 文件大小（字节）
  final int size;

  /// 文件最后修改时间
  final DateTime modifiedAt;

  /// 文件内容哈希（sha256 十六进制字符串）
  final String contentHash;

  const LocalSyncFile({
    required this.key,
    required this.localPath,
    required this.size,
    required this.modifiedAt,
    required this.contentHash,
  });
}

/// 远端逻辑文件
///
/// 表示远端服务器上的一个文件及其当前内容特征
class RemoteSyncFile {
  /// 逻辑键（相对远端同步目录的路径，统一使用正斜杠分隔）
  final String key;

  /// 服务端返回的 ETag（部分服务端可能为空）
  final String etag;

  /// 文件大小（字节）
  final int size;

  /// 文件最后修改时间（服务端可能不返回）
  final DateTime? modifiedAt;

  const RemoteSyncFile({
    required this.key,
    required this.etag,
    required this.size,
    this.modifiedAt,
  });

  /// 内容标识
  ///
  /// 优先使用服务端返回的 ETag；服务端未提供 ETag 时退化为「大小-修改时间」，
  /// 用于判断远端内容是否发生变化
  String get contentId => etag.isNotEmpty
      ? etag
      : '$size-${modifiedAt?.millisecondsSinceEpoch ?? 0}';
}

/// 同步基线记录
///
/// 记录某个逻辑文件在上一次同步完成时两端的状态，是三方比对的依据。
/// 同时充当哈希缓存：本地文件的大小与修改时间未变时，
/// 可直接复用 [localHash] 而无需重新计算文件哈希
class SyncBaselineRecord {
  /// 上次同步完成时本地文件的内容哈希
  String? localHash;

  /// 上次同步完成时本地文件的大小（字节）
  int? localSize;

  /// 上次同步完成时本地文件的修改时间（毫秒时间戳）
  int? localModifiedMs;

  /// 上次同步完成时远端文件的内容标识
  String? remoteContentId;

  /// 上次同步完成时间
  DateTime? syncedAt;

  /// 墓碑标记
  ///
  /// 为 true 时表示该文件的删除动作已完成同步，用于避免已删除文件被反复重建
  bool deleted = false;

  SyncBaselineRecord();

  /// 从 JSON 反序列化
  SyncBaselineRecord.fromJson(Map<String, dynamic> json)
    : localHash = json['localHash'] as String?,
      localSize = json['localSize'] as int?,
      localModifiedMs = json['localModifiedMs'] as int?,
      remoteContentId = json['remoteContentId'] as String?,
      syncedAt = json['syncedAt'] != null
          ? DateTime.tryParse(json['syncedAt'] as String)
          : null,
      deleted = json['deleted'] as bool? ?? false;

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
    'localHash': localHash,
    'localSize': localSize,
    'localModifiedMs': localModifiedMs,
    'remoteContentId': remoteContentId,
    'syncedAt': syncedAt?.toIso8601String(),
    'deleted': deleted,
  };
}

/// 同步动作
///
/// 描述计划层针对单个逻辑文件给出的处理方式。文件层不做删除决策，
/// 因为「文件缺失」无法区分被删除、尚未下载与本地丢失三种情况
enum SyncAction {
  /// 上传本地文件到远端
  upload,

  /// 从远端下载文件覆盖本地
  download,

  /// 两端都存在无法自动合并的修改，保留双份
  keepBoth,
}

/// 同步计划项
///
/// 描述针对一个逻辑文件需要执行的动作
class SyncPlanItem {
  /// 逻辑键
  final String key;

  /// 需要执行的动作
  final SyncAction action;

  /// 当前的本地文件（本地不存在时为 null）
  final LocalSyncFile? local;

  /// 当前的远端文件（远端不存在时为 null）
  final RemoteSyncFile? remote;

  const SyncPlanItem({
    required this.key,
    required this.action,
    this.local,
    this.remote,
  });
}

/// 同步计划
///
/// 承载一次比对得出的全部待执行动作，只包含需要处理的项目，跳过项不会出现在列表中
class SyncPlan {
  /// 待执行的动作清单
  final List<SyncPlanItem> items;

  const SyncPlan(this.items);

  /// 待上传的文件数量
  int get uploadCount => _countOf(SyncAction.upload);

  /// 待下载的文件数量
  int get downloadCount => _countOf(SyncAction.download);

  /// 需要保留双份的冲突数量
  int get conflictCount => _countOf(SyncAction.keepBoth);

  /// 待处理项目总数
  int get totalCount => items.length;

  /// 是否存在待处理的项目
  bool get hasChanges => items.isNotEmpty;

  /// 统计指定动作的项目数量
  int _countOf(SyncAction action) =>
      items.where((item) => item.action == action).length;
}

/// 同步风险预检结果
///
/// 描述一次同步在真正传输文件之前的影响面，用于决定是否需要用户确认。
/// 首次同步与改动面过大的同步都属于高风险操作，误操作可能造成大量上传或下载
class SyncRiskAssessment {
  /// 是否为首次同步（本机尚无任何同步基线）
  final bool isFirstSync;

  /// 本次待处理的计划项数量
  final int planItemCount;

  /// 本地逻辑文件总数
  final int localFileCount;

  /// 待上传的文件数量
  final int uploadCount;

  /// 待下载的文件数量
  final int downloadCount;

  /// 需要保留双份的冲突数量
  final int conflictCount;

  /// 本次将删除的远端书籍正文目录数量
  final int deletedBookDirCount;

  const SyncRiskAssessment({
    required this.isFirstSync,
    required this.planItemCount,
    required this.localFileCount,
    this.uploadCount = 0,
    this.downloadCount = 0,
    this.conflictCount = 0,
    this.deletedBookDirCount = 0,
  });

  /// 受影响文件占本地文件总数的比例
  ///
  /// 本地尚无文件时，只要存在待处理内容即视为全部受影响
  double get impactRatio {
    if (localFileCount == 0) return planItemCount > 0 ? 1 : 0;
    return planItemCount / localFileCount;
  }

  /// 影响面比例对应的百分比整数
  int get impactPercent => (impactRatio * 100).round();

  /// 是否需要用户确认后才执行
  ///
  /// 删除云端书籍正文目录属于不可逆操作，无论改动面大小都必须确认
  bool get needsConfirmation {
    if (deletedBookDirCount > 0) return true;
    if (planItemCount == 0) return false;
    if (isFirstSync) return true;
    return planItemCount >= kSyncImpactMinItemCount &&
        impactRatio > kSyncImpactConfirmRatio;
  }

  /// 待处理内容的简要描述，例如「上传 3 个，下载 1 个」
  String get changeSummary {
    final parts = <String>[];
    if (uploadCount > 0) parts.add('上传 $uploadCount 个');
    if (downloadCount > 0) parts.add('下载 $downloadCount 个');
    if (conflictCount > 0) parts.add('保留双份 $conflictCount 个');
    if (deletedBookDirCount > 0) parts.add('删除云端书籍目录 $deletedBookDirCount 个');
    return parts.isEmpty ? '无待处理内容' : parts.join('，');
  }

  /// 高风险原因的描述，null 表示本次同步无需确认
  String? get reason {
    if (deletedBookDirCount > 0) {
      return '本次同步会删除 $deletedBookDirCount 本书在云端的正文目录（$changeSummary）';
    }
    if (isFirstSync) {
      return '本机尚未同步过，本次会把本地内容与云端进行首次合并（$changeSummary）';
    }
    return '本次需要处理 $planItemCount 个文件，约占本地内容的 $impactPercent%（$changeSummary）';
  }
}

/// 单个计划项的执行结果
class SyncOutcome {
  /// 逻辑键
  final String key;

  /// 执行的动作
  final SyncAction action;

  /// 是否执行成功
  final bool success;

  /// 附加说明（失败时为错误原因）
  final String? message;

  /// 是否因服务端请求频率限制而失败
  final bool rateLimited;

  /// 本次执行中另存出的冲突副本路径
  final List<String> conflictCopyPaths;

  const SyncOutcome({
    required this.key,
    required this.action,
    required this.success,
    this.message,
    this.rateLimited = false,
    this.conflictCopyPaths = const [],
  });
}

/// 一次同步的执行汇总
class SyncSummary {
  /// 各计划项的执行结果
  final List<SyncOutcome> outcomes;

  /// 因服务端限流而提前中止时未处理的项目数量
  ///
  /// 这些项目在下次同步时会被重新纳入，不会丢失
  final int abortedCount;

  /// 元数据写回本地的实体数量
  final int metadataUpsertCount;

  /// 元数据从本地移除的实体数量
  final int metadataRemovalCount;

  /// 从远端读取到的元数据文件数量
  final int metadataRemoteFileCount;

  /// 清理掉的已删除书籍正文目录数量
  final int deletedBookDirCount;

  /// 是否因用户未确认而中止了正文传输
  final bool cancelled;

  /// 本次同步的风险预检结果（未经过预检时为 null）
  final SyncRiskAssessment? risk;

  /// 完整性校验中未能在远端确认的已上传文件数量
  ///
  /// 为 0 表示本轮上传的文件都已确认在远端就位
  final int integrityIssueCount;

  const SyncSummary({
    required this.outcomes,
    this.abortedCount = 0,
    this.metadataUpsertCount = 0,
    this.metadataRemovalCount = 0,
    this.metadataRemoteFileCount = 0,
    this.deletedBookDirCount = 0,
    this.cancelled = false,
    this.risk,
    this.integrityIssueCount = 0,
  });

  /// 执行成功的数量
  int get doneCount => outcomes.where((outcome) => outcome.success).length;

  /// 执行失败的数量
  int get failedCount => outcomes.length - doneCount;

  /// 执行失败的结果列表
  List<SyncOutcome> get failures =>
      outcomes.where((outcome) => !outcome.success).toList();

  /// 保留双份的冲突数量
  int get conflictCount => outcomes
      .where(
        (outcome) => outcome.success && outcome.action == SyncAction.keepBoth,
      )
      .length;

  /// 另存出的冲突副本路径清单
  ///
  /// 包含两端同时修改产生的副本，以及下载归档包补齐缺失章节时为保留本地修改而写出的副本
  List<String> get conflictCopyPaths => [
    for (final outcome in outcomes)
      if (outcome.success) ...outcome.conflictCopyPaths,
  ];

  /// 是否存在需要处理的项目
  bool get hasChanges =>
      outcomes.isNotEmpty ||
      abortedCount > 0 ||
      metadataUpsertCount > 0 ||
      metadataRemovalCount > 0 ||
      deletedBookDirCount > 0;

  /// 统计指定动作已成功的数量
  int countOf(SyncAction action) => outcomes
      .where((outcome) => outcome.success && outcome.action == action)
      .length;
}

/// 同步进度
///
/// 描述正文文件同步的推进情况，用于向界面反馈当前的同步位置
class SyncProgress {
  /// 已处理的文件数量
  final int done;

  /// 需要处理的文件总数
  final int total;

  const SyncProgress({required this.done, required this.total});
}
