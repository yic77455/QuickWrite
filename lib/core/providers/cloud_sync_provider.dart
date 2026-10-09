import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_result.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';

/// 云同步状态管理 Provider
///
/// 作为界面层的视图模型，向界面暴露云同步的连接状态、同步设置与操作入口，
/// 数据的持久化与实际同步逻辑由 [CloudSyncService] 负责
class CloudSyncProvider extends ChangeNotifier {
  CloudSyncProvider() {
    _service.addListener(_onServiceChanged);
  }

  /// 云同步服务
  final CloudSyncService _service = CloudSyncService.instance;

  /// 服务状态变化回调（保持引用一致，便于移除监听）
  late final VoidCallback _onServiceChanged = notifyListeners;

  // ================= 连接状态 =================

  /// 是否已连接云服务
  bool get isConnected => _service.isConnected;

  /// 是否正在执行连接相关的耗时操作
  bool get isBusy => _service.isBusy;

  /// 上次同步时间（null 表示尚未同步过）
  DateTime? get lastSyncTime => _service.lastSyncTime;

  /// 当前同步进度（没有待处理的文件时为 null）
  SyncProgress? get syncProgress => _service.syncProgress;

  /// 待用户确认的高风险同步（null 表示没有）
  SyncRiskAssessment? get pendingRisk => _service.pendingRisk;

  /// 已保存的服务器地址
  String get serverUrl => _service.serverUrl;

  /// 已保存的登录账号
  String get username => _service.username;

  /// 已保存的远端目录
  String get remoteDir => _service.remoteDir;

  // ================= 同步设置 =================

  /// 是否启用自动同步
  bool get autoSyncEnabled => _service.autoSyncEnabled;

  /// 自动同步间隔（分钟）
  int get syncIntervalMinutes => _service.syncIntervalMinutes;

  /// 应用启动时自动同步
  bool get syncOnStartup => _service.syncOnStartup;

  /// 应用退出时自动同步
  bool get syncOnExit => _service.syncOnExit;

  // ================= 连接操作 =================

  /// 测试服务器连接
  Future<CloudSyncResult> testConnection({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteDir,
  }) {
    return _service.testConnection(
      serverUrl: serverUrl,
      username: username,
      password: password,
      remoteDir: remoteDir,
    );
  }

  /// 建立连接
  Future<CloudSyncResult> connect({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteDir,
  }) {
    return _service.connect(
      serverUrl: serverUrl,
      username: username,
      password: password,
      remoteDir: remoteDir,
    );
  }

  /// 断开连接
  Future<void> disconnect() => _service.disconnect();

  // ================= 同步操作 =================

  /// 执行一次同步预演（仅统计差异，不传输文件）
  Future<CloudSyncResult> previewSync() => _service.previewSync();

  /// 执行一次完整同步
  Future<CloudSyncResult> syncNow() => _service.syncNow();

  /// 清空云端同步数据
  Future<CloudSyncResult> clearRemoteData() => _service.clearRemoteData();

  // ================= 同步设置更新 =================

  /// 更新自动同步开关
  Future<void> setAutoSyncEnabled(bool value) => _service.setAutoSyncEnabled(value);

  /// 更新自动同步间隔
  Future<void> setSyncIntervalMinutes(int value) =>
      _service.setSyncIntervalMinutes(value);

  /// 更新启动时自动同步开关
  Future<void> setSyncOnStartup(bool value) => _service.setSyncOnStartup(value);

  /// 更新退出时自动同步开关
  Future<void> setSyncOnExit(bool value) => _service.setSyncOnExit(value);

  // ================= 生命周期 =================

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
