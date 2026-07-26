/// 自定义高亮单项配置
///
/// 描述一个需要高亮显示的关键词（或字）及其对应的高亮颜色。
class CustomHighlightItem {
  /// 需要高亮显示的关键词或字
  final String keyword;

  /// 高亮颜色的十六进制字符串（#RRGGBB 格式）
  final String colorHex;

  const CustomHighlightItem({
    required this.keyword,
    required this.colorHex,
  });

  /// 从 JSON 反序列化
  factory CustomHighlightItem.fromJson(Map<String, dynamic> json) {
    return CustomHighlightItem(
      keyword: (json['keyword'] as String?) ?? '',
      colorHex: (json['colorHex'] as String?) ?? '#FFB300',
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'keyword': keyword,
        'colorHex': colorHex,
      };

  /// 创建一份修改后的副本
  CustomHighlightItem copyWith({
    String? keyword,
    String? colorHex,
  }) {
    return CustomHighlightItem(
      keyword: keyword ?? this.keyword,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomHighlightItem &&
          other.keyword == keyword &&
          other.colorHex == colorHex;

  @override
  int get hashCode => Object.hash(keyword, colorHex);
}

/// 自定义高亮整体配置
///
/// 包含启用开关与高亮项列表，作为单本书的自定义高亮配置持久化到书籍根目录。
class CustomHighlightConfig {
  /// 是否启用自定义高亮
  final bool enabled;

  /// 高亮项列表
  final List<CustomHighlightItem> items;

  const CustomHighlightConfig({
    this.enabled = false,
    this.items = const [],
  });

  /// 空配置（默认值）
  static const CustomHighlightConfig empty = CustomHighlightConfig();

  /// 从 JSON 反序列化
  factory CustomHighlightConfig.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <CustomHighlightItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          items.add(CustomHighlightItem.fromJson(item));
        }
      }
    }
    return CustomHighlightConfig(
      enabled: (json['enabled'] as bool?) ?? false,
      items: items,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'items': items.map((e) => e.toJson()).toList(),
      };

  /// 创建一份修改后的副本
  CustomHighlightConfig copyWith({
    bool? enabled,
    List<CustomHighlightItem>? items,
  }) {
    return CustomHighlightConfig(
      enabled: enabled ?? this.enabled,
      items: items ?? this.items,
    );
  }
}
