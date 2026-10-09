import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 云同步配置存储
///
/// 负责云同步配置在本机上的持久化，配置分为两部分存放：
/// - 非敏感配置（服务器地址、账号、远端目录、同步开关等）写入 {应用根目录}/sync/config.json
/// - 密码写入系统安全存储，避免以明文形式落盘
///
/// 该配置属于设备私有数据，不参与云端同步
class SyncConfigStore {
  // ================= 单例模式 =================

  static final SyncConfigStore instance = SyncConfigStore._internal();
  SyncConfigStore._internal();

  // ================= 常量定义 =================

  /// 配置文件名
  static const String _configFileName = 'config.json';

  /// 密码在系统安全存储中的键名
  static const String _passwordKey = 'cloud_sync_password';

  /// 默认远端目录名
  static const String defaultRemoteDir = 'QuickWrite';

  /// 默认自动同步间隔（分钟）
  static const int defaultSyncIntervalMinutes = 30;

  // ================= 状态属性 =================

  /// 服务器地址
  String serverUrl = '';

  /// 登录账号
  String username = '';

  /// 云端同步数据存放目录
  String remoteDir = defaultRemoteDir;

  /// 是否已建立连接
  bool isConnected = false;

  /// 上次同步完成时间
  DateTime? lastSyncTime;

  /// 是否启用自动同步
  bool autoSyncEnabled = false;

  /// 自动同步间隔（分钟）
  int syncIntervalMinutes = defaultSyncIntervalMinutes;

  /// 应用启动时自动同步
  bool syncOnStartup = false;

  /// 应用退出时自动同步
  bool syncOnExit = false;

  /// 登录密码（仅保存在内存与系统安全存储中）
  String _password = '';
  String get password => _password;

  /// 系统安全存储实例
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 配置文件完整路径
  String? _configFilePath;

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ================= 初始化方法 =================

  /// 初始化配置存储
  ///
  /// 从本机读取已保存的云同步配置，应在应用启动时调用
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('SyncConfigStore 已经初始化，跳过重复初始化');
      return;
    }

    // 确保 AppPaths 已初始化
    if (!AppPaths.instance.isInitialized) {
      await AppPaths.instance.initialize();
    }

    // 构建配置文件路径
    final syncPath = await AppPaths.instance.getSyncPath();
    _configFilePath = '$syncPath${Platform.pathSeparator}$_configFileName';

    await _load();
    _isInitialized = true;
    debugPrint('SyncConfigStore 初始化完成');
  }

  // ================= 读取方法 =================

  /// 从本机加载配置
  Future<void> _load() async {
    // 读取非敏感配置
    if (_configFilePath != null) {
      final configFile = File(_configFilePath!);
      if (await configFile.exists()) {
        try {
          final jsonMap =
              json.decode(await configFile.readAsString())
                  as Map<String, dynamic>;
          serverUrl = jsonMap['serverUrl'] as String? ?? '';
          username = jsonMap['username'] as String? ?? '';
          remoteDir = jsonMap['remoteDir'] as String? ?? defaultRemoteDir;
          isConnected = jsonMap['isConnected'] as bool? ?? false;
          lastSyncTime = jsonMap['lastSyncTime'] != null
              ? DateTime.tryParse(jsonMap['lastSyncTime'] as String)
              : null;
          autoSyncEnabled = jsonMap['autoSyncEnabled'] as bool? ?? false;
          syncIntervalMinutes =
              jsonMap['syncIntervalMinutes'] as int? ??
              defaultSyncIntervalMinutes;
          syncOnStartup = jsonMap['syncOnStartup'] as bool? ?? false;
          syncOnExit = jsonMap['syncOnExit'] as bool? ?? false;
        } catch (e) {
          debugPrint('读取云同步配置失败: $e');
        }
      }
    }

    // 读取密码
    try {
      _password = await _secureStorage.read(key: _passwordKey) ?? '';
    } catch (e) {
      debugPrint('读取云同步密码失败: $e');
    }
  }

  // ================= 保存方法 =================

  /// 保存非敏感配置
  ///
  /// 返回是否保存成功
  Future<bool> saveConfig() async {
    if (_configFilePath == null) {
      debugPrint('云同步配置路径为空，无法保存');
      return false;
    }

    try {
      final jsonMap = <String, dynamic>{
        'serverUrl': serverUrl,
        'username': username,
        'remoteDir': remoteDir,
        'isConnected': isConnected,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
        'autoSyncEnabled': autoSyncEnabled,
        'syncIntervalMinutes': syncIntervalMinutes,
        'syncOnStartup': syncOnStartup,
        'syncOnExit': syncOnExit,
      };
      final content = const JsonEncoder.withIndent('  ').convert(jsonMap);
      await File(_configFilePath!).writeAsString(content);
      return true;
    } catch (e) {
      debugPrint('保存云同步配置失败: $e');
      return false;
    }
  }

  /// 保存密码到系统安全存储
  ///
  /// 返回是否保存成功
  Future<bool> savePassword(String value) async {
    _password = value;
    try {
      await _secureStorage.write(key: _passwordKey, value: value);
      return true;
    } catch (e) {
      debugPrint('保存云同步密码失败: $e');
      return false;
    }
  }

  // ================= 工具方法 =================

  /// 规范化远端目录
  ///
  /// 去除首尾多余的斜杠，为空时使用默认目录
  static String normalizeRemoteDir(String dir) {
    var value = dir.trim();
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.isEmpty ? defaultRemoteDir : value;
  }
}
