import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/cloud_sync/remote_storage.dart';
import 'package:quick_write/core/services/cloud_sync/s3_client.dart';

/// 云同步配置存储
///
/// 负责云同步配置在本机上的持久化，配置分为两部分存放：
/// - 非敏感配置（平台类型、服务器地址、账号、远端目录、同步开关等）
///   写入 {应用根目录}/sync/config.json
/// - 密钥（WebDAV 密码、S3 Secret Key）写入系统安全存储，避免以明文形式落盘
///
/// 该配置属于设备私有数据，不参与云端同步
class SyncConfigStore {
  // ================= 单例模式 =================

  static final SyncConfigStore instance = SyncConfigStore._internal();
  SyncConfigStore._internal();

  // ================= 常量定义 =================

  /// 配置文件名
  static const String _configFileName = 'config.json';

  /// WebDAV 密码在系统安全存储中的键名
  static const String _passwordKey = 'cloud_sync_password';

  /// S3 Secret Key 在系统安全存储中的键名
  static const String _s3SecretKeyKey = 'cloud_sync_s3_secret_key';

  /// 默认远端目录名
  static const String defaultRemoteDir = 'QuickWrite';

  /// 默认自动同步间隔（分钟）
  static const int defaultSyncIntervalMinutes = 30;

  /// 表示「实时同步」的间隔取值
  ///
  /// 间隔为 0 时不启动周期性定时器，改为在每次本地保存后立即同步
  static const int realtimeSyncIntervalMinutes = 0;

  // ================= 状态属性 =================

  /// 存储平台（WebDAV / S3）
  RemoteStorageKind storageKind = RemoteStorageKind.webDav;

  /// 服务器地址（WebDAV）或服务端点（S3）
  String serverUrl = '';

  /// 登录账号（WebDAV）或 Access Key（S3）
  String username = '';

  /// S3 区域
  String s3Region = kS3DefaultRegion;

  /// S3 存储桶
  String s3Bucket = '';

  /// S3 是否使用路径风格访问
  bool s3PathStyle = false;

  /// 云端同步数据存放目录（S3 下作为对象键前缀）
  String remoteDir = defaultRemoteDir;

  /// 是否已建立连接
  bool isConnected = false;

  /// 上次同步完成时间
  DateTime? lastSyncTime;

  /// 是否启用自动同步
  bool autoSyncEnabled = false;

  /// 自动同步间隔（分钟），0 表示实时同步
  int syncIntervalMinutes = defaultSyncIntervalMinutes;

  /// 应用启动时自动同步
  bool syncOnStartup = false;

  /// 应用退出时自动同步
  bool syncOnExit = false;

  /// 是否启用实时同步
  bool get isRealtimeSync => syncIntervalMinutes <= realtimeSyncIntervalMinutes;

  /// WebDAV 登录密码（仅保存在内存与系统安全存储中）
  String _password = '';
  String get password => _password;

  /// S3 Secret Key（仅保存在内存与系统安全存储中）
  String _s3SecretKey = '';
  String get s3SecretKey => _s3SecretKey;

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
          storageKind = RemoteStorageKind.fromId(
            jsonMap['storageKind'] as String?,
          );
          serverUrl = jsonMap['serverUrl'] as String? ?? '';
          username = jsonMap['username'] as String? ?? '';
          s3Region = jsonMap['s3Region'] as String? ?? kS3DefaultRegion;
          s3Bucket = jsonMap['s3Bucket'] as String? ?? '';
          s3PathStyle = jsonMap['s3PathStyle'] as bool? ?? false;
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

    // 读取密钥
    try {
      _password = await _secureStorage.read(key: _passwordKey) ?? '';
    } catch (e) {
      debugPrint('读取云同步密码失败: $e');
    }
    try {
      _s3SecretKey = await _secureStorage.read(key: _s3SecretKeyKey) ?? '';
    } catch (e) {
      debugPrint('读取 S3 密钥失败: $e');
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
        'storageKind': storageKind.id,
        'serverUrl': serverUrl,
        'username': username,
        's3Region': s3Region,
        's3Bucket': s3Bucket,
        's3PathStyle': s3PathStyle,
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

  /// 保存 S3 Secret Key 到系统安全存储
  ///
  /// 返回是否保存成功
  Future<bool> saveS3SecretKey(String value) async {
    _s3SecretKey = value;
    try {
      await _secureStorage.write(key: _s3SecretKeyKey, value: value);
      return true;
    } catch (e) {
      debugPrint('保存 S3 密钥失败: $e');
      return false;
    }
  }

  // ================= 工具方法 =================

  /// 由当前保存的配置构造连接参数
  CloudConnectionConfig get connectionConfig => CloudConnectionConfig(
    kind: storageKind,
    endpoint: serverUrl,
    account: username,
    secret: storageKind == RemoteStorageKind.s3 ? s3SecretKey : password,
    remoteDir: remoteDir,
    region: s3Region,
    bucket: s3Bucket,
    pathStyle: s3PathStyle,
  );

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
