import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';

/// 云同步状态存储
///
/// 负责本机同步状态的持久化，存放于 {应用根目录}/sync/state.json：
/// - 同步基线：每个逻辑文件上一次同步完成时两端的状态，是三方比对的依据
///
/// 该状态与设备绑定，不参与云端同步
class SyncStateStore {
  // ================= 单例模式 =================

  static final SyncStateStore instance = SyncStateStore._internal();
  SyncStateStore._internal();

  // ================= 常量定义 =================

  /// 状态文件名
  static const String _stateFileName = 'state.json';

  /// 状态文件结构版本号
  static const int _schemaVersion = 1;

  /// 取不到设备名称时使用的替代名称
  static const String _fallbackDeviceName = '未知设备';

  /// 逻辑键中表示章节目录的片段
  static const String _chaptersDirSegment = '/chapters/';

  // ================= 状态属性 =================

  /// 同步基线：逻辑键 → 基线记录
  final Map<String, SyncBaselineRecord> _baselines = {};

  /// 获取同步基线（只读）
  Map<String, SyncBaselineRecord> get baselines => Map.unmodifiable(_baselines);

  /// 元数据实体基线：集合名 → 上次同步完成时的存活实体标识
  ///
  /// 基线中存在、当前本地不存在的实体即被视为本地已删除，
  /// 使删除识别无需在每个删除入口埋点
  final Map<String, Set<String>> _entityBaselines = {};

  /// 获取元数据实体基线（只读）
  Map<String, Set<String>> get entityBaselines =>
      Map.unmodifiable(_entityBaselines);

  /// 更新元数据实体基线
  void setEntityBaselines(Map<String, Set<String>> baselines) {
    _entityBaselines
      ..clear()
      ..addAll(baselines);
  }

  /// 是否留有同步基线
  bool get hasBaselines => _baselines.isNotEmpty || _entityBaselines.isNotEmpty;

  /// 清空全部同步基线
  ///
  /// 用于远端数据被整体清空后重新建立关联：基线归零后，
  /// 本地内容会被视为全新数据完整推送上去，而不是被当作「远端已删除」
  void clearSyncBaselines() {
    _baselines.clear();
    _entityBaselines.clear();
  }

  /// 本机设备名称
  ///
  /// 用于生成冲突副本的文件名，已过滤掉文件名中不允许的字符
  String get deviceName {
    try {
      final name = Platform.localHostname.trim();
      if (name.isEmpty) return _fallbackDeviceName;
      return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    } catch (e) {
      debugPrint('获取设备名称失败: $e');
      return _fallbackDeviceName;
    }
  }

  /// 状态文件完整路径
  String? _stateFilePath;

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ================= 初始化方法 =================

  /// 初始化状态存储
  ///
  /// 从本机读取已保存的同步状态，应在应用启动时调用
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('SyncStateStore 已经初始化，跳过重复初始化');
      return;
    }

    // 确保 AppPaths 已初始化
    if (!AppPaths.instance.isInitialized) {
      await AppPaths.instance.initialize();
    }

    // 构建状态文件路径
    final syncPath = await AppPaths.instance.getSyncPath();
    _stateFilePath = '$syncPath${Platform.pathSeparator}$_stateFileName';

    await _load();
    _isInitialized = true;
    debugPrint('SyncStateStore 初始化完成，基线数量: ${_baselines.length}');
  }

  // ================= 基线读写 =================

  /// 获取指定逻辑键的基线记录
  SyncBaselineRecord? baselineOf(String key) => _baselines[key];

  /// 写入指定逻辑键的基线记录
  void putBaseline(String key, SyncBaselineRecord record) {
    _baselines[key] = record;
  }

  /// 删除指定逻辑键的基线记录
  void removeBaseline(String key) {
    _baselines.remove(key);
  }

  /// 将该逻辑键标记为墓碑
  ///
  /// 用于记录删除动作已同步完成，避免已删除的文件在下次同步时被重新拉回
  void markDeleted(String key, {DateTime? syncedAt}) {
    _baselines[key] = SyncBaselineRecord()
      ..deleted = true
      ..syncedAt = syncedAt ?? DateTime.now();
  }

  /// 清理已不再使用的章节正文哈希缓存
  ///
  /// 章节被删除后其哈希缓存不再有任何用处，及时清理可避免状态文件无限增长
  void pruneChapterHashCache(Set<String> activeKeys) {
    _baselines.removeWhere(
      (key, _) =>
          key.contains(_chaptersDirSegment) &&
          key.endsWith(GlobalConstants.chapterFileExtension) &&
          !activeKeys.contains(key),
    );
  }

  /// 记录一次传输完成后的双方状态
  ///
  /// [localHash] 传输后本地文件的内容哈希
  /// [localSize] 传输后本地文件的大小（字节）
  /// [localModifiedAt] 传输后本地文件的修改时间
  /// [remoteContentId] 传输后远端文件的内容标识
  void recordSynced({
    required String key,
    required String localHash,
    required int localSize,
    required DateTime localModifiedAt,
    required String remoteContentId,
  }) {
    _baselines[key] = SyncBaselineRecord()
      ..localHash = localHash
      ..localSize = localSize
      ..localModifiedMs = localModifiedAt.millisecondsSinceEpoch
      ..remoteContentId = remoteContentId
      ..syncedAt = DateTime.now();
  }

  // ================= 持久化 =================

  /// 从本机加载同步状态
  Future<void> _load() async {
    if (_stateFilePath == null) return;

    final stateFile = File(_stateFilePath!);
    if (!await stateFile.exists()) return;

    try {
      final jsonMap =
          json.decode(await stateFile.readAsString()) as Map<String, dynamic>;
      final rawBaselines = jsonMap['baselines'];
      if (rawBaselines is Map) {
        for (final entry in rawBaselines.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _baselines[entry.key as String] = SyncBaselineRecord.fromJson(
              value,
            );
          }
        }
      }

      final rawEntityBaselines = jsonMap['entityBaselines'];
      if (rawEntityBaselines is Map) {
        for (final entry in rawEntityBaselines.entries) {
          final value = entry.value;
          if (value is List) {
            _entityBaselines[entry.key as String] = value
                .whereType<String>()
                .toSet();
          }
        }
      }
    } catch (e) {
      debugPrint('读取同步状态失败: $e');
    }
  }

  /// 将同步状态保存到本机
  ///
  /// 返回是否保存成功
  Future<bool> save() async {
    if (_stateFilePath == null) {
      debugPrint('同步状态路径为空，无法保存');
      return false;
    }

    try {
      final jsonMap = <String, dynamic>{
        'version': _schemaVersion,
        'baselines': _baselines.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'entityBaselines': _entityBaselines.map(
          (key, value) => MapEntry(key, value.toList()),
        ),
      };
      final content = const JsonEncoder.withIndent('  ').convert(jsonMap);
      await File(_stateFilePath!).writeAsString(content);
      return true;
    } catch (e) {
      debugPrint('保存同步状态失败: $e');
      return false;
    }
  }
}
