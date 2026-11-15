/// 自定义高亮单项配置
///
/// 描述一条需要高亮显示的内容及其对应的高亮颜色。
/// [keyword] 在字面量模式下是原样匹配的关键词，在正则模式下是正则表达式；
/// 默认字面量模式，旧配置文件缺少 [isRegex] 字段时同样按字面量解析。
class CustomHighlightItem {
  /// 需要高亮显示的关键词（字面量模式）或正则表达式（正则模式）
  final String keyword;

  /// 高亮颜色的十六进制字符串（#RRGGBB 格式）
  final String colorHex;

  /// 是否把 [keyword] 当作正则表达式解析
  ///
  /// false（默认）时使用与旧版本完全一致的逐字匹配，不做任何转义/语义变化。
  final bool isRegex;

  const CustomHighlightItem({
    required this.keyword,
    required this.colorHex,
    this.isRegex = false,
  });

  /// 从 JSON 反序列化
  factory CustomHighlightItem.fromJson(Map<String, dynamic> json) {
    return CustomHighlightItem(
      keyword: (json['keyword'] as String?) ?? '',
      colorHex: (json['colorHex'] as String?) ?? '#FFB300',
      // 旧配置无此字段；云端下来的异常类型也一律降级为字面量，避免解析失败
      isRegex: json['isRegex'] == true,
    );
  }

  /// 序列化为 JSON
  ///
  /// 字面量模式不写入新字段，保证旧配置文件的字节内容不变（旧版本也能无损读取），
  /// 同时避免只为默认模式触发一次不必要的云同步。
  Map<String, dynamic> toJson() => {
        'keyword': keyword,
        'colorHex': colorHex,
        if (isRegex) 'isRegex': true,
      };

  /// 创建一份修改后的副本
  CustomHighlightItem copyWith({
    String? keyword,
    String? colorHex,
    bool? isRegex,
  }) {
    return CustomHighlightItem(
      keyword: keyword ?? this.keyword,
      colorHex: colorHex ?? this.colorHex,
      isRegex: isRegex ?? this.isRegex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomHighlightItem &&
          other.keyword == keyword &&
          other.colorHex == colorHex &&
          other.isRegex == isRegex;

  @override
  int get hashCode => Object.hash(keyword, colorHex, isRegex);
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
