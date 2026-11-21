import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';

/// 敏感词词库的云同步逻辑键
///
/// 词库为全局数据，与具体书籍无关，因此存放在应用级键空间中，
/// 参与云同步后可在多台设备间共用同一份词库。
const String kSensitiveWordSyncKey = 'app/sensitive_words.json';

/// 敏感词服务
///
/// 负责全局敏感词词库的加载、保存与标红开关：
/// - 词库以 JSON 文件形式持久化到应用根目录，所有书籍共用，随应用文件参与云同步；
/// - 标红开关属于本机的显示偏好，仅持久化到杂项缓存，不参与同步；
/// - 词库或开关变化时通过 [ChangeNotifier] 通知正文编辑器立即重绘高亮。
///
/// 以单例形式供各窗口共用，在应用启动时通过 [initialize] 载入一次。
class SensitiveWordService extends ChangeNotifier {
  // ================= 单例模式 =================

  static final SensitiveWordService instance = SensitiveWordService._internal();

  /// 私有构造函数
  SensitiveWordService._internal();

  /// 当前词条列表（初始为空，加载完成后更新）
  List<String> _words = const [];

  /// 正文敏感词标红开关（默认开启）
  bool _highlightEnabled = true;

  /// 词库版本号
  ///
  /// 每次词库内容变化时递增，供正文编辑器的样式构建器判断是否需要重算缓存。
  int _revision = 0;

  /// 是否已完成首次加载
  bool _initialized = false;

  /// 当前词条列表（只读）
  List<String> get words => List.unmodifiable(_words);

  /// 正文是否开启敏感词标红
  bool get highlightEnabled => _highlightEnabled;

  /// 词库版本号
  int get revision => _revision;

  /// 从应用根目录加载全局词库与标红开关
  ///
  /// 词库文件不存在时使用空词库，待用户编辑保存后再写入文件。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 标红开关为本机偏好，从杂项缓存恢复
    _highlightEnabled = MiscCacheService.instance.isSensitiveWordHighlightEnabled();

    try {
      final file = File(AppPaths.instance.sensitiveWordFilePath);
      if (await file.exists()) {
        _words = _parseWords(json.decode(await file.readAsString()));
      } else {
        _words = const [];
      }
    } catch (e) {
      debugPrint('加载敏感词词库失败: $e，使用空词库');
      _words = const [];
    }
    _revision++;
    notifyListeners();
  }

  /// 设置正文敏感词标红开关
  ///
  /// 开关状态写入杂项缓存，切换后立即通知编辑器重绘。
  Future<void> setHighlightEnabled(bool enabled) async {
    if (_highlightEnabled == enabled) return;
    _highlightEnabled = enabled;
    await MiscCacheService.instance.saveSensitiveWordHighlightEnabled(enabled);
    notifyListeners();
  }

  /// 批量替换全部词条
  ///
  /// 词条会自动去除首尾空白并去重；保存后通知编辑器按新词库重绘高亮。
  Future<bool> replaceAll(List<String> words) async {
    _words = _normalizeWords(words);
    _revision++;
    final bool saved = await _save();
    notifyListeners();
    return saved;
  }

  /// 保存词库到应用根目录
  Future<bool> _save() async {
    try {
      final file = File(AppPaths.instance.sensitiveWordFilePath);
      // 确保应用根目录存在（通常已由启动流程创建，此处兜底）
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      final content = const JsonEncoder.withIndent('  ').convert({'words': _words});
      await file.writeAsString(content);
      // 词库已落盘，交由云同步服务安排一次同步
      CloudSyncService.instance.notifyLocalChange();
      return true;
    } catch (e) {
      debugPrint('保存敏感词词库失败: $e');
      return false;
    }
  }

  /// 解析词库文件内容
  ///
  /// 兼容 `{"words": [...]}` 对象与纯数组两种格式，非法内容返回空列表。
  List<String> _parseWords(dynamic json) {
    if (json is Map<String, dynamic>) {
      final dynamic words = json['words'];
      if (words is List) {
        return _normalizeWords(words.map((e) => e.toString()).toList());
      }
    } else if (json is List) {
      return _normalizeWords(json.map((e) => e.toString()).toList());
    }
    return const [];
  }

  /// 去除首尾空白、过滤空词并按首次出现顺序去重
  List<String> _normalizeWords(List<String> source) {
    final result = <String>[];
    for (final word in source) {
      final trimmed = word.trim();
      if (trimmed.isEmpty || result.contains(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }
}
