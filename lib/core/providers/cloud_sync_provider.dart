import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_result.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/cloud_sync/remote_storage.dart';
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

  /// 存储平台类型
  RemoteStorageKind get storageKind => _service.storageKind;

  /// 已保存的服务器地址（WebDAV）或服务端点（S3）
  String get serverUrl => _service.serverUrl;

  /// 已保存的登录账号（WebDAV）或 Access Key（S3）
  String get username => _service.username;

  /// 已保存的远端目录
  String get remoteDir => _service.remoteDir;

  /// 已保存的 S3 区域
  String get s3Region => _service.s3Region;

  /// 已保存的 S3 存储桶
  String get s3Bucket => _service.s3Bucket;

  /// 已保存的 S3 路径风格设置
  bool get s3PathStyle => _service.s3PathStyle;

  /// 章节是否以归档包上传（仅坚果云为 true）
  bool get chapterPackingEnabled => _service.chapterPackingEnabled;

  /// 当前平台的识别结果
  String get platformLabel => _service.platformLabel;

  /// 当前是否指向坚果云
  bool get isJianguoyun => _service.isJianguoyun;

  // ================= 同步设置 =================

  /// 是否启用自动同步
  bool get autoSyncEnabled => _service.autoSyncEnabled;

  /// 自动同步间隔（分钟），0 表示实时同步
  int get syncIntervalMinutes => _service.syncIntervalMinutes;

  /// 是否启用实时同步
  bool get isRealtimeSync => _service.isRealtimeSync;

  /// 应用启动时自动同步
  bool get syncOnStartup => _service.syncOnStartup;

  /// 应用退出时自动同步
  bool get syncOnExit => _service.syncOnExit;

  // ================= 连接操作 =================

  /// 测试服务器连接
  Future<CloudSyncResult> testConnection(CloudConnectionConfig config) =>
      _service.testConnection(config);

  /// 建立连接
  Future<CloudSyncResult> connect(CloudConnectionConfig config) =>
      _service.connect(config);

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
