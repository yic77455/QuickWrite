import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/models/name_gen/name_gen_options.dart';

/// 随机取名缓存数据模型
///
/// 词典内容由词典存取服务从 JSON 文件加载。
class NameGenCacheData {
  /// 各类别当前选中的词典 ID（键为类别 ID）
  final Map<String, String> selectedDictionaryIds;

  /// 被用户删除的内置词典 ID 集合
  ///
  /// 内置词典无法从应用资源中真正移除，删除后记录在此，加载时跳过，
  /// 从而实现与自定义词典一致的删除效果。
  final Set<String> hiddenBuiltinIds;

  /// 最近一次使用的生成参数（null 表示尚未保存过参数）
  final NameGenOptions? options;

  /// 生成历史（键为类别 ID，值为名字列表，最新在前）
  final Map<String, List<String>> history;

  const NameGenCacheData({
    this.selectedDictionaryIds = const {},
    this.hiddenBuiltinIds = const {},
    this.options,
    this.history = const {},
  });

  /// 从 JSON Map 创建实例
  factory NameGenCacheData.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['history'] as Map<String, dynamic>? ?? {};
    final rawOptions = json['options'] as Map<String, dynamic>?;
    final rawSelected = json['selectedDictionaryIds'] as Map<String, dynamic>?;
    final rawHidden = json['hiddenBuiltinIds'] as List<dynamic>? ?? const [];

    return NameGenCacheData(
      // 新版按类别记录选中词典；旧版缓存仅有按人名、地名记录的字段
      selectedDictionaryIds: rawSelected != null
          ? rawSelected.map((key, value) => MapEntry(key, value as String))
          : _parseLegacySelected(json),
      hiddenBuiltinIds: rawHidden.map((e) => e as String).toSet(),
      options: rawOptions == null ? null : NameGenOptions.fromJson(rawOptions),
      history: _parseNameMap(rawHistory),
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'selectedDictionaryIds': selectedDictionaryIds,
      'hiddenBuiltinIds': hiddenBuiltinIds.toList(),
      'options': options?.toJson(),
      'history': history,
    };
  }

  /// 创建副本
  NameGenCacheData copyWith({
    Map<String, String>? selectedDictionaryIds,
    Set<String>? hiddenBuiltinIds,
    NameGenOptions? options,
    Map<String, List<String>>? history,
  }) {
    return NameGenCacheData(
      selectedDictionaryIds: selectedDictionaryIds ?? this.selectedDictionaryIds,
      hiddenBuiltinIds: hiddenBuiltinIds ?? this.hiddenBuiltinIds,
      options: options ?? this.options,
      history: history ?? this.history,
    );
  }

  /// 解析旧版缓存中按人名、地名分别保存的选中词典
  static Map<String, String> _parseLegacySelected(Map<String, dynamic> json) {
    final result = <String, String>{};
    final person = json['selectedPersonDictId'] as String? ?? '';
    final place = json['selectedPlaceDictId'] as String? ?? '';
    if (person.isNotEmpty) result[NameCategory.person.id] = person;
    if (place.isNotEmpty) result[NameCategory.place.id] = place;
    return result;
  }

  /// 解析"类别 ID -> 名字列表"的映射
  static Map<String, List<String>> _parseNameMap(Map<String, dynamic> json) {
    final result = <String, List<String>>{};
    json.forEach((key, value) {
      result[key] = (value as List<dynamic>).map((e) => e as String).toList();
    });
    return result;
  }
}
