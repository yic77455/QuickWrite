import 'package:quick_write/core/models/name_gen/name_gen_options.dart';

/// 随机取名缓存数据模型
///
/// 词典内容由词典存取服务从 JSON 文件加载。
class NameGenCacheData {
  /// 人名类别当前选中的词典 ID
  final String selectedPersonDictId;

  /// 地名类别当前选中的词典 ID
  final String selectedPlaceDictId;

  /// 最近一次使用的生成参数（null 表示尚未保存过参数）
  final NameGenOptions? options;

  /// 生成历史（键为类别 ID，值为名字列表，最新在前）
  final Map<String, List<String>> history;

  const NameGenCacheData({
    this.selectedPersonDictId = '',
    this.selectedPlaceDictId = '',
    this.options,
    this.history = const {},
  });

  /// 从 JSON Map 创建实例
  factory NameGenCacheData.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['history'] as Map<String, dynamic>? ?? {};
    final rawOptions = json['options'] as Map<String, dynamic>?;

    return NameGenCacheData(
      selectedPersonDictId: json['selectedPersonDictId'] as String? ?? '',
      selectedPlaceDictId: json['selectedPlaceDictId'] as String? ?? '',
      options: rawOptions == null ? null : NameGenOptions.fromJson(rawOptions),
      history: _parseNameMap(rawHistory),
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'selectedPersonDictId': selectedPersonDictId,
      'selectedPlaceDictId': selectedPlaceDictId,
      'options': options?.toJson(),
      'history': history,
    };
  }

  /// 创建副本
  NameGenCacheData copyWith({
    String? selectedPersonDictId,
    String? selectedPlaceDictId,
    NameGenOptions? options,
    Map<String, List<String>>? history,
  }) {
    return NameGenCacheData(
      selectedPersonDictId: selectedPersonDictId ?? this.selectedPersonDictId,
      selectedPlaceDictId: selectedPlaceDictId ?? this.selectedPlaceDictId,
      options: options ?? this.options,
      history: history ?? this.history,
    );
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
