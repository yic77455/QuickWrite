import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_result.dart';
import 'package:quick_write/core/services/cloud_sync/remote_storage.dart';
import 'package:quick_write/core/services/cloud_sync/s3_client.dart';
import 'package:quick_write/core/services/cloud_sync/sync_config_store.dart';
import 'package:quick_write/core/services/cloud_sync/sync_engine.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:quick_write/core/services/cloud_sync/sync_scheduler.dart';
import 'package:quick_write/core/services/cloud_sync/sync_state_store.dart';
import 'package:quick_write/core/services/cloud_sync/webdav_client.dart';

/// 云同步服务（门面）
///
/// 作为界面层访问云同步能力的统一入口，负责：
/// - 连接配置的保存与连接状态维护
/// - 连接测试、建立连接与断开连接
/// - 调度同步引擎并聚合同步状态供界面展示
/// - 按设置安排自动同步的执行时机
class CloudSyncService extends ChangeNotifier {
  // ================= 单例模式 =================

  static final CloudSyncService instance = CloudSyncService._internal();
  CloudSyncService._internal();

  // ================= 常量定义 =================

  /// 应用退出前等待同步完成的最长时间
  ///
  /// 超过该时长仍然允许退出：同步过程中的写入都是原子操作，
  /// 未完成的部分会在下次同步时自动补齐
  static const Duration _exitSyncTimeout = Duration(seconds: 30);

  /// 应用启动后延迟执行首次同步的时长
  ///
  /// 留出时间让界面与数据库完成初始化，避免同步打断其他初始化流程
  static const Duration _startupSyncDelay = Duration(seconds: 5);

  // ================= 状态属性 =================

  /// 本机配置存储
  final SyncConfigStore _config = SyncConfigStore.instance;

  /// 本机同步状态存储
  final SyncStateStore _stateStore = SyncStateStore.instance;

  /// 自动同步调度器
  late final SyncScheduler _scheduler = SyncScheduler(onTrigger: _autoSync);

  /// 当前使用的远端存储客户端（未连接时为 null）
  RemoteStorage? _storage;

  /// 当前使用的同步引擎（未连接时为 null）
  SyncEngine? _engine;

  /// 正在执行的同步任务（null 表示当前没有同步在执行）
  Future<CloudSyncResult>? _runningSync;

  /// 同步执行期间是否又发生了本地变更
  ///
  /// 实时同步要求「每次保存都同步」，同步进行中的保存不能直接丢弃，
  /// 需要在其结束后补一次，否则最后一次改动会一直停留在本地
  bool _localChangePending = false;

  /// 待用户确认的高风险同步（null 表示没有）
  SyncRiskAssessment? _pendingRisk;

  /// 同步风险确认回调
  ///
  /// 由应用启动时注入，首次同步或影响面过大时调用；未注入时视为用户未确认
  Future<bool> Function(SyncRiskAssessment risk)? _riskConfirmHandler;

  /// 是否禁止弹出风险确认
  ///
  /// 退出阶段界面已隐藏，弹窗无人可见，此时遇到高风险同步直接跳过
  bool _suppressRiskPrompt = false;

  /// 后台同步提示回调
  ///
  /// 由应用启动时注入，自动同步出现异常结果时用于第一时间告知用户；未注入时不提示
  void Function(String message)? _noticeHandler;

  /// 最近一次已提示的后台同步异常信息，相同的信息不重复打扰用户
  String? _lastNoticeMessage;

  /// 同步冲突副本提示回调
  ///
  /// 由应用启动时注入，同步为本机版本另存出冲突副本时用于提醒用户；未注入时不提示
  void Function(List<SyncConflictCopy> conflicts)? _conflictNoticeHandler;

  /// 启动同步的完成信号（未安排启动同步时为 null）
  ///
  /// 应用启动时若安排了启动同步，此处保存其完成信号，
  /// 供完整性校验等待同步结束，避免校验读到同步前的过期状态
  Completer<void>? _startupSyncSignal;

  /// 正文文件的同步进度（未同步时为 null）
  SyncProgress? _syncProgress;

  /// 是否正在执行连接相关的耗时操作
  bool _isBusy = false;
  bool get isBusy => _isBusy;

  /// 同步完成的轮次
  ///
  /// 每次同步结束后自增，供界面判断是否需要重新加载数据
  int _syncRevision = 0;
  int get syncRevision => _syncRevision;

  /// 是否已完成初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ================= 只读状态 =================

  /// 是否已连接云服务
  bool get isConnected => _config.isConnected;

  /// 当前同步进度（没有待处理的文件时为 null）
  SyncProgress? get syncProgress {
    final progress = _syncProgress;
    return progress == null || progress.total == 0 ? null : progress;
  }

  /// 上次同步完成时间（null 表示尚未同步过）
  DateTime? get lastSyncTime => _config.lastSyncTime;

  /// 待用户确认的高风险同步（null 表示没有）
  SyncRiskAssessment? get pendingRisk => _pendingRisk;

  /// 是否启用自动同步
  bool get autoSyncEnabled => _config.autoSyncEnabled;

  /// 自动同步间隔（分钟），0 表示实时同步
  int get syncIntervalMinutes => _config.syncIntervalMinutes;

  /// 是否启用实时同步
  ///
  /// 实时同步在每次本地保存后立即执行一次同步，不再等待周期定时器
  bool get isRealtimeSync => _config.isRealtimeSync;

  /// 应用启动时自动同步
  bool get syncOnStartup => _config.syncOnStartup;

  /// 应用退出时自动同步
  bool get syncOnExit => _config.syncOnExit;

  /// 存储平台类型
  RemoteStorageKind get storageKind => _config.storageKind;

  /// 服务器地址（WebDAV）或服务端点（S3）
  String get serverUrl => _config.serverUrl;

  /// 登录账号（WebDAV）或 Access Key（S3）
  String get username => _config.username;

  /// S3 区域
  String get s3Region => _config.s3Region;

  /// S3 存储桶
  String get s3Bucket => _config.s3Bucket;

  /// S3 是否使用路径风格访问
  bool get s3PathStyle => _config.s3PathStyle;

  /// 远端目录
  String get remoteDir => _config.remoteDir;

  /// 章节是否以归档包的形式上传
  ///
  /// 仅坚果云需要：该平台限制每 30 分钟的请求次数，
  /// 逐章上传会迅速耗尽配额；其他平台逐章上传以节省单次同步的流量
  bool get chapterPackingEnabled => _config.connectionConfig.packsChapters;

  /// 当前平台的识别结果，用于界面提示采用的传输策略
  String get platformLabel => _config.connectionConfig.platformLabel;

  /// 当前是否指向坚果云（无论是否已连接）
  bool get isJianguoyun => isJianguoyunHost(_config.serverUrl);

  // ================= 初始化方法 =================

  /// 初始化服务
  ///
  /// 读取本机保存的连接配置与同步状态，应在应用启动时调用
  Future<void> initialize() async {
    await _config.initialize();
    await _stateStore.initialize();
    _isInitialized = true;

    // 本机连接配置已不完整时，重置连接状态
    if (_config.isConnected && !_hasCompleteCredentials) {
      _config.isConnected = false;
      await _config.saveConfig();
    }

    // 处于已连接状态时，提前建立客户端并开启自动同步
    if (_config.isConnected) {
      _rebuildClient();
      _applySchedulerSettings();
      _scheduleStartupSync();
    }

    // 输出初始化结果，用于确认自动同步的配置是否按预期生效
    debugPrint(
      '云同步初始化完成：已连接=${_config.isConnected}，'
      '平台=${_config.storageKind.label}，'
      '自动同步=${_config.autoSyncEnabled}，'
      '同步间隔=${_config.isRealtimeSync ? '实时' : '${_config.syncIntervalMinutes} 分钟'}，'
      '章节归档=${_config.connectionConfig.packsChapters}',
    );

    notifyListeners();
  }

  // ================= 连接操作 =================

  /// 测试服务器连接是否可用
  ///
  /// 仅校验地址与凭据的正确性，不会保存配置
  Future<CloudSyncResult> testConnection(CloudConnectionConfig config) async {
    final invalidMessage = _validateConnection(config);
    if (invalidMessage != null) return CloudSyncResult.failure(invalidMessage);

    _setBusy(true);
    final client = _createClient(config);
    try {
      // 验证服务可达且鉴权通过
      await client.ping();
      // 验证远端目录可用
      await client.ensureDirectory(client.remoteDir);
      return CloudSyncResult.success(
        '连接成功，服务器可正常访问（${config.platformLabel}）',
      );
    } catch (e) {
      return CloudSyncResult.failure('连接失败：${describeRemoteError(e)}');
    } finally {
      client.dispose();
      _setBusy(false);
    }
  }

  /// 建立连接
  ///
  /// 连接测试通过后保存配置并标记为已连接状态
  Future<CloudSyncResult> connect(CloudConnectionConfig config) async {
    final result = await testConnection(config);
    if (!result.success) return result;

    // 持久化连接配置
    _config.storageKind = config.kind;
    _config.remoteDir = SyncConfigStore.normalizeRemoteDir(config.remoteDir);
    if (config.kind == RemoteStorageKind.s3) {
      _config.serverUrl = config.endpoint.trim();
      _config.username = config.account.trim();
      _config.s3Region = config.region.trim().isEmpty
          ? kS3DefaultRegion
          : config.region.trim();
      _config.s3Bucket = config.bucket.trim();
      _config.s3PathStyle = config.pathStyle;
      await _config.saveS3SecretKey(config.secret);
    } else {
      _config.serverUrl = config.endpoint.trim();
      _config.username = config.account.trim();
      await _config.savePassword(config.secret);
    }
    _config.isConnected = true;
    await _config.saveConfig();

    // 重建客户端供后续同步使用
    _rebuildClient();
    _applySchedulerSettings();
    notifyListeners();
    return const CloudSyncResult.success('已连接云服务');
  }

  /// 断开连接
  ///
  /// 释放连接资源并停止同步，本机保留配置以便下次快速连接
  Future<void> disconnect() async {
    _scheduler.stop();
    _storage?.dispose();
    _storage = null;
    _engine = null;
    _pendingRisk = null;
    _localChangePending = false;
    _config.isConnected = false;
    await _config.saveConfig();
    notifyListeners();
  }

  // ================= 同步操作 =================

  /// 执行一次同步预演
  ///
  /// 比对本地与远端的差异并统计待处理数量，不会传输或删除任何文件
  Future<CloudSyncResult> previewSync() async {
    final engine = _engine;
    if (engine == null) {
      return const CloudSyncResult.failure('请先连接云服务');
    }

    _setBusy(true);
    try {
      final plan = await engine.buildPlan();
      return CloudSyncResult.success(_describePlan(plan));
    } catch (e) {
      return CloudSyncResult.failure('同步预演失败：${describeRemoteError(e)}');
    } finally {
      _setBusy(false);
    }
  }

  /// 设置同步风险确认回调
  ///
  /// 应用启动时注入该回调，使同步被风险预检拦截时能够征求用户意见；
  /// 传入 null 表示清除，此后同步不再请求确认
  void setRiskConfirmHandler(
    Future<bool> Function(SyncRiskAssessment risk)? handler,
  ) {
    _riskConfirmHandler = handler;
  }

  /// 设置后台同步的提示回调
  ///
  /// 应用启动时注入该回调，用于把自动同步的异常结果第一时间呈现给用户；
  /// 传入 null 表示清除，此后后台同步不再提示
  void setNoticeHandler(void Function(String message)? handler) {
    _noticeHandler = handler;
  }

  /// 设置同步冲突副本的提示回调
  ///
  /// 应用启动时注入该回调，用于在同步为本机版本另存出冲突副本时弹出提示；
  /// 传入 null 表示清除，此后不再提示
  void setConflictNoticeHandler(
    void Function(List<SyncConflictCopy> conflicts)? handler,
  ) {
    _conflictNoticeHandler = handler;
  }

  /// 等待启动同步结束
  ///
  /// 未安排启动同步时立即返回，供完整性校验在同步补齐缺失文件后再进行检测
  Future<void> awaitStartupSync() async {
    final signal = _startupSyncSignal;
    if (signal == null) return;
    await signal.future;
  }

  /// 执行一次完整同步
  ///
  /// 同一时刻只允许一个同步任务，重复调用会复用正在执行的任务
  Future<CloudSyncResult> syncNow() {
    if (_engine == null) {
      return Future.value(const CloudSyncResult.failure('请先连接云服务'));
    }

    final running = _runningSync;
    if (running != null) {
      debugPrint('已有同步任务在执行，复用本次任务');
      return running;
    }

    _localChangePending = false;
    final future = _executeSync();
    _runningSync = future;
    return future.whenComplete(() {
      _runningSync = null;
      _scheduleFollowUpSync();
    });
  }

  /// 清空云端同步数据
  ///
  /// 删除远端同步目录下的全部内容，本地文件不受影响。
  /// 远端内容清空后同步基线随之失效，下次同步会把本地内容作为全新数据完整推送
  Future<CloudSyncResult> clearRemoteData() async {
    final storage = _storage;
    if (storage == null) {
      return const CloudSyncResult.failure('请先连接云服务');
    }
    if (_runningSync != null) {
      return const CloudSyncResult.failure('正在同步中，请稍后再试');
    }

    _setBusy(true);
    try {
      await storage.clearDirectory(storage.remoteDir);
      // 远端目录已清空，清除目录缓存以便下次同步重新创建
      storage.resetDirectoryCache();
      _stateStore.clearSyncBaselines();
      await _stateStore.save();
      _config.lastSyncTime = null;
      await _config.saveConfig();
      notifyListeners();
      return const CloudSyncResult.success('已清空云端同步数据');
    } catch (e) {
      return CloudSyncResult.failure(
        '清空云端数据失败：${describeRemoteError(e)}',
      );
    } finally {
      _setBusy(false);
    }
  }

  /// 执行同步并汇总结果
  Future<CloudSyncResult> _executeSync() async {
    final engine = _engine!;

    // 是否改动了本地数据：实时同步会在每次保存后执行，
    // 若空转一轮也通知界面刷新，会让书架反复重载
    var dataChanged = false;

    _setBusy(true);
    try {
      final summary = await engine.sync(
        onProgress: _onSyncProgress,
        onConfirmRisk: _confirmRisk,
      );

      // 未获得确认时保留待确认状态，由界面引导用户手动触发
      if (summary.cancelled) {
        _pendingRisk = summary.risk;
        dataChanged = summary.hasChanges;
        notifyListeners();
        return CloudSyncResult.failure(_describeSummary(summary));
      }
      _pendingRisk = null;
      dataChanged = summary.hasChanges;

      // 为本机版本另存出冲突副本时立即提醒用户，避免副本只留在磁盘上被忽略
      final conflicts = summary.conflictCopies;
      if (conflicts.isNotEmpty) {
        _conflictNoticeHandler?.call(conflicts);
      }

      // 记录本次同步的完成时间：个别文件处理失败时同样属于已执行过一次同步，
      // 失败的部分因未写入基线，会在下次同步自动重试
      _config.lastSyncTime = DateTime.now();
      await _config.saveConfig();
      return CloudSyncResult.success(_describeSummary(summary));
    } catch (e) {
      // 异常发生前可能已经写入部分元数据，交由界面重新加载以保证显示一致
      dataChanged = true;
      return CloudSyncResult.failure('同步失败：${describeRemoteError(e)}');
    } finally {
      _syncProgress = null;
      if (dataChanged) _syncRevision++;
      _setBusy(false);
    }
  }

  /// 请求用户确认高风险同步
  ///
  /// 未注入确认回调时返回 false：后台自动同步无法征求用户意见，
  /// 遇到高风险操作时宁可不执行，也不做可能造成大量改动的传输；
  /// 退出阶段界面已隐藏，同样按未确认处理
  Future<bool> _confirmRisk(SyncRiskAssessment risk) async {
    if (_suppressRiskPrompt) return false;
    final handler = _riskConfirmHandler;
    if (handler == null) return false;
    return handler(risk);
  }

  // ================= 自动同步 =================

  /// 通知本地内容发生了变化
  ///
  /// 定时模式下内容静置一段时间后才会推送，避免编辑过程中的连续保存反复触发同步；
  /// 实时模式下每次保存都会安排一次同步，若此时正在同步则记为待补，
  /// 在本次同步结束后立即再同步一次，保证最后一次保存也能落到云端
  void notifyLocalChange() {
    if (!_canAutoSync) return;
    if (_config.isRealtimeSync && _runningSync != null) {
      _localChangePending = true;
    }
    _scheduler.notifyLocalChange();
  }

  /// 应用退出前的处理
  ///
  /// 启用退出时同步时先等待一次同步完成；未启用或等待超时则直接放行，
  /// 返回 false 会取消退出，这里始终允许退出
  Future<bool> handleAppExit() async {
    if (!willSyncOnExit) return true;

    // 退出阶段界面已隐藏，无法展示确认弹窗，遇到高风险同步时跳过本次同步
    _suppressRiskPrompt = true;
    try {
      await Future.any([syncNow(), Future<void>.delayed(_exitSyncTimeout)]);
    } catch (e) {
      debugPrint('退出前同步失败: $e');
    } finally {
      _suppressRiskPrompt = false;
    }
    return true;
  }

  /// 自动同步的统一入口
  ///
  /// 不满足条件或已有同步在执行时直接跳过，异常在内部消化，不会抛给调度器
  Future<void> _autoSync() async {
    if (!_canAutoSync) return;

    // 存在待确认的高风险同步时不再反复尝试，避免持续消耗服务端请求配额
    if (_pendingRisk != null) {
      debugPrint('存在待确认的高风险同步，跳过本次自动同步');
      return;
    }

    if (_runningSync != null) {
      // 实时同步下这次保存不能被丢弃，标记为待补，由本轮同步结束时接手
      if (_config.isRealtimeSync) _localChangePending = true;
      debugPrint('已有同步任务在执行，跳过本次自动同步');
      return;
    }

    final result = await syncNow();
    if (result.success) {
      _lastNoticeMessage = null;
      return;
    }

    debugPrint('自动同步未完成：${result.message}');
    // 同一问题不重复提示；确认弹窗关闭后本次提示仍会补上，避免状态变得无迹可寻
    if (_lastNoticeMessage == result.message) return;
    _lastNoticeMessage = result.message;
    _noticeHandler?.call(result.message);
  }

  /// 实时同步：本轮同步期间又发生过保存时，补一次同步
  ///
  /// 同步过程中用户仍可能继续编辑并保存，这些改动不在本轮的计划内，
  /// 若不在结束后立即补一次，最后一次改动会一直停留在本地
  void _scheduleFollowUpSync() {
    if (!_config.isRealtimeSync || !_localChangePending) return;
    // 退出阶段与待确认状态下不再自动发起，避免在不可见时消耗请求配额
    if (!_canAutoSync || _pendingRisk != null || _suppressRiskPrompt) return;

    _localChangePending = false;
    debugPrint('实时同步：本轮同步期间有新的保存，安排补同步');
    _scheduler.notifyLocalChange();
  }

  /// 上报同步进度
  void _onSyncProgress(int done, int total) {
    _syncProgress = SyncProgress(done: done, total: total);
    notifyListeners();
  }

  /// 按当前设置配置自动同步的调度方式
  ///
  /// 实时模式不启动周期定时器，同步完全由保存动作驱动
  void _applySchedulerSettings() {
    if (!_canAutoSync) {
      _scheduler.applyInterval(null);
      return;
    }
    final realtime = _config.isRealtimeSync;
    _scheduler.applyInterval(
      realtime ? null : Duration(minutes: _config.syncIntervalMinutes),
      realtime: realtime,
    );
  }

  /// 按设置安排应用启动后的首次同步
  ///
  /// 同时记录完成信号，使完整性校验能够等待同步结束
  void _scheduleStartupSync() {
    if (!_config.syncOnStartup) return;

    final signal = Completer<void>();
    _startupSyncSignal = signal;

    Timer(_startupSyncDelay, () async {
      try {
        await _autoSync();
      } finally {
        if (!signal.isCompleted) signal.complete();
      }
    });
  }

  /// 当前是否具备自动同步的条件
  bool get _canAutoSync =>
      _isInitialized && _config.isConnected && _config.autoSyncEnabled;

  /// 当前是否需要处理退出时同步
  bool get willSyncOnExit =>
      _isInitialized && _config.isConnected && _config.syncOnExit;

  // ================= 同步设置更新 =================

  /// 更新自动同步开关
  Future<void> setAutoSyncEnabled(bool value) async {
    if (_config.autoSyncEnabled == value) return;
    _config.autoSyncEnabled = value;
    await _config.saveConfig();
    _applySchedulerSettings();
    notifyListeners();
  }

  /// 更新自动同步间隔
  Future<void> setSyncIntervalMinutes(int value) async {
    if (_config.syncIntervalMinutes == value) return;
    _config.syncIntervalMinutes = value;
    await _config.saveConfig();
    _applySchedulerSettings();
    notifyListeners();
  }

  /// 更新启动时自动同步开关
  Future<void> setSyncOnStartup(bool value) async {
    if (_config.syncOnStartup == value) return;
    _config.syncOnStartup = value;
    await _config.saveConfig();
    notifyListeners();
  }

  /// 更新退出时自动同步开关
  Future<void> setSyncOnExit(bool value) async {
    if (_config.syncOnExit == value) return;
    _config.syncOnExit = value;
    await _config.saveConfig();
    notifyListeners();
  }

  // ================= 工具方法 =================

  /// 判断本机保存的连接配置是否完整
  bool get _hasCompleteCredentials {
    switch (_config.storageKind) {
      case RemoteStorageKind.webDav:
        return WebDavClient.isValidServerUrl(_config.serverUrl) &&
            _config.username.isNotEmpty &&
            _config.password.isNotEmpty;
      case RemoteStorageKind.s3:
        return S3Client.isValidEndpoint(_config.serverUrl) &&
            _config.s3Bucket.isNotEmpty &&
            _config.username.isNotEmpty &&
            _config.s3SecretKey.isNotEmpty;
    }
  }

  /// 按连接参数创建远端客户端
  RemoteStorage _createClient(CloudConnectionConfig config) {
    final remoteDir = SyncConfigStore.normalizeRemoteDir(config.remoteDir);
    switch (config.kind) {
      case RemoteStorageKind.webDav:
        return WebDavClient(
          serverUrl: config.endpoint.trim(),
          username: config.account.trim(),
          password: config.secret,
          remoteDir: remoteDir,
        );
      case RemoteStorageKind.s3:
        return S3Client(
          endpoint: config.endpoint,
          bucket: config.bucket.trim(),
          region: config.region,
          accessKey: config.account.trim(),
          secretKey: config.secret,
          remoteDir: remoteDir,
          pathStyle: config.pathStyle,
        );
    }
  }

  /// 创建或重建底层客户端与同步引擎
  ///
  /// 章节是否打包由平台决定：只有坚果云这类限制请求次数的平台才使用归档包，
  /// 其他平台逐章同步，每次只上传改动的章节
  void _rebuildClient() {
    final config = _config.connectionConfig;
    _storage?.dispose();
    _storage = _createClient(config);
    _engine = SyncEngine(
      storage: _storage!,
      stateStore: _stateStore,
      packChapters: config.packsChapters,
    );
  }

  /// 更新忙碌状态并通知界面
  void _setBusy(bool value) {
    if (_isBusy == value) return;
    _isBusy = value;
    notifyListeners();
  }

  /// 将同步计划转换为便于用户理解的提示文本
  String _describePlan(SyncPlan plan) {
    if (!plan.hasChanges) {
      return '同步预演完成：本地与云端内容一致，无需处理';
    }

    final parts = <String>[];
    _addCountPart(parts, '上传', plan.uploadCount);
    _addCountPart(parts, '下载', plan.downloadCount);
    _addCountPart(parts, '保留双份', plan.conflictCount);
    return '同步预演：${parts.join('，')}（尚未实际传输）';
  }

  /// 将同步结果转换为便于用户理解的提示文本
  String _describeSummary(SyncSummary summary) {
    // 风险预检未通过时说明暂停原因，并指出重新发起的位置
    if (summary.cancelled) {
      return '本次同步未执行：${summary.risk?.reason ?? '本次同步改动较大'}。'
          '可在云同步页面重新发起';
    }

    if (!summary.hasChanges) {
      return '同步完成：本地与云端内容一致';
    }

    final parts = <String>[];
    _addCountPart(parts, '远端元数据文件', summary.metadataRemoteFileCount);
    _addCountPart(parts, '元数据更新', summary.metadataUpsertCount);
    _addCountPart(parts, '元数据删除', summary.metadataRemovalCount);
    _addCountPart(parts, '上传', summary.countOf(SyncAction.upload));
    _addCountPart(parts, '下载', summary.countOf(SyncAction.download));
    _addCountPart(parts, '保留双份', summary.conflictCount);
    _addCountPart(parts, '清理书籍目录', summary.deletedBookDirCount);

    // 服务端限流导致中断时，说明剩余内容稍后可以继续同步
    if (summary.abortedCount > 0) {
      _addCountPart(parts, '已失败', summary.failedCount);
      final done = summary.doneCount > 0 ? '已同步 ${summary.doneCount} 个文件，' : '';
      return '同步中断：$done服务端请求频率已达上限，'
          '剩余 ${summary.abortedCount} 个稍后再试（${parts.isEmpty ? '无' : parts.join('，')}）';
    }

    _addCountPart(parts, '失败', summary.failedCount);
    final firstFailure = summary.failures.isEmpty
        ? null
        : summary.failures.first;
    final detail = firstFailure == null ? '' : '（例如：${firstFailure.message}）';
    return '同步完成：${parts.join('，')}$detail（${_describeIntegrity(summary)}）';
  }

  /// 描述同步后的完整性校验结果
  String _describeIntegrity(SyncSummary summary) {
    if (summary.integrityIssueCount == 0) return '完整性校验通过';
    return '完整性校验未通过，${summary.integrityIssueCount} 个上传文件未能在云端确认，'
        '下次同步会自动重试';
  }

  /// 追加一项数量统计（数量为 0 时忽略）
  void _addCountPart(List<String> parts, String label, int count) {
    if (count > 0) parts.add('$label $count 个');
  }

  /// 校验连接参数
  ///
  /// 参数合法时返回 null，否则返回对应的错误提示
  String? _validateConnection(CloudConnectionConfig config) {
    switch (config.kind) {
      case RemoteStorageKind.webDav:
        if (config.endpoint.trim().isEmpty) return '请填写服务器地址';
        if (!WebDavClient.isValidServerUrl(config.endpoint)) {
          return '服务器地址无效，请填写以 https:// 开头的完整地址';
        }
        if (config.account.trim().isEmpty) return '请填写账号';
        if (config.secret.isEmpty) return '请填写密码';
      case RemoteStorageKind.s3:
        if (config.endpoint.trim().isEmpty) return '请填写服务端点';
        if (!S3Client.isValidEndpoint(config.endpoint)) {
          return '服务端点无效，请填写以 https:// 开头的完整地址（本地服务可使用 http://）';
        }
        if (config.bucket.trim().isEmpty) return '请填写存储桶名称';
        if (config.account.trim().isEmpty) return '请填写 Access Key';
        if (config.secret.isEmpty) return '请填写 Secret Key';
    }
    return null;
  }
}
