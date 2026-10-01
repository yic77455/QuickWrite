import 'package:flutter/material.dart';

/// 云同步状态管理 Provider
///
/// 管理云同步功能的界面状态，包括：
/// - 云服务连接状态与上次同步时间
/// - 自动同步相关设置项
///
/// 通过 [notifyListeners] 通知界面刷新，
/// 设置项的持久化与实际同步逻辑由云同步服务负责
class CloudSyncProvider extends ChangeNotifier {
  // ================= 连接状态 =================

  /// 是否已连接云服务
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  /// 上次同步时间（null 表示尚未同步过）
  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  // ================= 同步设置 =================

  /// 是否启用自动同步
  bool _autoSyncEnabled = false;
  bool get autoSyncEnabled => _autoSyncEnabled;

  /// 自动同步间隔（分钟）
  int _syncIntervalMinutes = 30;
  int get syncIntervalMinutes => _syncIntervalMinutes;

  /// 应用启动时自动同步
  bool _syncOnStartup = false;
  bool get syncOnStartup => _syncOnStartup;

  /// 应用退出时自动同步
  bool _syncOnExit = false;
  bool get syncOnExit => _syncOnExit;

  /// 是否将本地备份目录纳入同步范围
  bool _syncBackups = false;
  bool get syncBackups => _syncBackups;

  // ================= 状态更新方法 =================

  /// 更新连接状态
  void setConnected(bool value) {
    if (_isConnected == value) return;
    _isConnected = value;
    notifyListeners();
  }

  /// 更新上次同步时间
  void setLastSyncTime(DateTime? value) {
    _lastSyncTime = value;
    notifyListeners();
  }

  /// 更新自动同步开关
  void setAutoSyncEnabled(bool value) {
    if (_autoSyncEnabled == value) return;
    _autoSyncEnabled = value;
    notifyListeners();
  }

  /// 更新自动同步间隔
  void setSyncIntervalMinutes(int value) {
    if (_syncIntervalMinutes == value) return;
    _syncIntervalMinutes = value;
    notifyListeners();
  }

  /// 更新启动时自动同步开关
  void setSyncOnStartup(bool value) {
    if (_syncOnStartup == value) return;
    _syncOnStartup = value;
    notifyListeners();
  }

  /// 更新退出时自动同步开关
  void setSyncOnExit(bool value) {
    if (_syncOnExit == value) return;
    _syncOnExit = value;
    notifyListeners();
  }

  /// 更新是否同步备份目录
  void setSyncBackups(bool value) {
    if (_syncBackups == value) return;
    _syncBackups = value;
    notifyListeners();
  }
}
