/// 自定义颜色缓存数据模型
///
/// 所有场景的自定义颜色统一存放在同一个缓存文件中，
/// 数据内部按「场景」分组，便于后续扩展其他自定义颜色场景。
class CustomColorCacheData {
  /// 场景键 → 该场景下按添加顺序排列的颜色十六进制字符串
  final Map<String, List<String>> colorsByScene;

  const CustomColorCacheData({this.colorsByScene = const {}});

  /// 从 JSON Map 创建实例
  factory CustomColorCacheData.fromJson(Map<String, dynamic> json) {
    final raw = json['colorsByScene'] as Map<String, dynamic>? ?? const {};
    return CustomColorCacheData(
      colorsByScene: {
        for (final entry in raw.entries)
          entry.key: (entry.value as List<dynamic>? ?? const [])
              .map((e) => e as String)
              .toList(growable: false),
      },
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {'colorsByScene': colorsByScene};
  }

  /// 创建副本
  CustomColorCacheData copyWith({Map<String, List<String>>? colorsByScene}) {
    return CustomColorCacheData(colorsByScene: colorsByScene ?? this.colorsByScene);
  }
}
