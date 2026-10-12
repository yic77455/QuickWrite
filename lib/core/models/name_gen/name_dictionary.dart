/// 名字类别
///
/// 随机取名功能按类别区分人名与地名，两类使用不同的词典结构与生成规则。
enum NameCategory {
  /// 人名
  person('person', '人名'),

  /// 地名
  place('place', '地名');

  /// 类别唯一标识（用于持久化）
  final String id;

  /// 类别显示名称
  final String label;

  const NameCategory(this.id, this.label);

  /// 根据 ID 解析类别，未知 ID 回退为人名
  static NameCategory fromId(String id) =>
      values.firstWhere((c) => c.id == id, orElse: () => NameCategory.person);
}

/// 词典字库分组键
///
/// 不同类别使用不同的分组，各分组下存放对应的词条列表：
/// - 人名：姓氏、男性名字用字、女性名字用字
/// - 地名：主体词、后缀
class NamePoolKeys {
  /// 人名：姓氏
  static const String surname = 'surname';

  /// 人名：男性名字用字
  static const String male = 'male';

  /// 人名：女性名字用字
  static const String female = 'female';

  /// 地名：主体词
  static const String stem = 'stem';

  /// 地名：后缀
  static const String suffix = 'suffix';

  /// 获取指定类别的分组键列表（按编辑界面的显示顺序）
  static List<String> keysOf(NameCategory category) {
    switch (category) {
      case NameCategory.person:
        return const [surname, male, female];
      case NameCategory.place:
        return const [stem, suffix];
    }
  }

  /// 获取分组的显示名称
  static String labelOf(NameCategory category, String key) {
    switch (key) {
      case surname:
        return '姓氏';
      case male:
        return '男性用字';
      case female:
        return '女性用字';
      case stem:
        return '主体词';
      case suffix:
        return '后缀';
      default:
        return key;
    }
  }
}

/// 名字词典
///
/// 描述一个可用于生成人名的字库集合。词典可分为内置词典与自定义词典，
/// 内置词典随应用提供，自定义词典由用户创建。
class NameDictionary {
  /// 自定义词典排序序号的起始值
  ///
  /// 内置词典使用小于该值的序号，从而始终排在自定义词典之前，并向内扩展
  /// 预留出充足空间；自定义词典从该值起依次递增。
  static const int customOrderStart = 1000;

  /// 词典唯一标识
  final String id;

  /// 词典名称
  final String name;

  /// 所属类别（人名/地名）
  final NameCategory category;

  /// 是否为内置词典
  final bool isBuiltin;

  /// 排序序号
  ///
  /// 数值越小越靠前，默认词典取最小值 0，内置词典依次递增且均小于
  /// [customOrderStart]，自定义词典从 [customOrderStart] 起依次递增。
  final int orderIndex;

  /// 是否按"逐字"方式生成
  ///
  /// true 表示名字/主体词由多个单字组合而成，生成时可选字数；
  /// false 表示词条本身即完整的名字或地名，只能整词选取。
  final bool isCharBased;

  /// 是否"名在前"
  ///
  /// 仅对人物名有效：true 表示按"名+姓"顺序拼接（适用于西方人名），
  /// false 表示按"姓+名"顺序拼接。
  final bool givenFirst;

  /// 各分组的词条列表
  ///
  /// 键为 [NamePoolKeys] 中定义的常量，值为该分组的词条。
  /// 词条以单字为主时按"逐字"方式组合（如中文姓名的名字用字），
  /// 以整词为主时按"整词"方式选取（如西方人名的名字）。
  final Map<String, List<String>> pools;

  const NameDictionary({
    required this.id,
    required this.name,
    required this.category,
    this.isBuiltin = false,
    this.orderIndex = customOrderStart,
    this.isCharBased = false,
    this.givenFirst = false,
    this.pools = const {},
  });

  /// 从 JSON Map 创建实例
  factory NameDictionary.fromJson(Map<String, dynamic> json) {
    final rawPools = json['pools'] as Map<String, dynamic>? ?? {};
    final pools = <String, List<String>>{};
    rawPools.forEach((key, value) {
      pools[key] = (value as List<dynamic>).map((e) => e as String).toList();
    });

    final category = NameCategory.fromId(json['category'] as String? ?? '');

    return NameDictionary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: category,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      orderIndex: json['orderIndex'] as int? ?? customOrderStart,
      // 早期词典未声明生成方式，依据词条池推断以保持原行为
      isCharBased: json['isCharBased'] as bool? ?? inferCharBased(category, pools),
      givenFirst: json['givenFirst'] as bool? ?? false,
      pools: pools,
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category.id,
      'isBuiltin': isBuiltin,
      'orderIndex': orderIndex,
      'isCharBased': isCharBased,
      'givenFirst': givenFirst,
      'pools': pools,
    };
  }

  /// 创建副本
  NameDictionary copyWith({
    String? id,
    String? name,
    NameCategory? category,
    bool? isBuiltin,
    int? orderIndex,
    bool? isCharBased,
    bool? givenFirst,
    Map<String, List<String>>? pools,
  }) {
    return NameDictionary(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      orderIndex: orderIndex ?? this.orderIndex,
      isCharBased: isCharBased ?? this.isCharBased,
      givenFirst: givenFirst ?? this.givenFirst,
      pools: pools ?? this.pools,
    );
  }

  /// 读取指定分组的词条（分组不存在时返回空列表）
  List<String> pool(String key) => pools[key] ?? const [];

  /// 依据类别与词条池推断是否按"逐字"方式生成
  ///
  /// 人名依据男女名字用字池，地名依据主体词池；相关词条全部为单字时
  /// 按逐字生成。供未显式声明生成方式的词典（如早期自定义词典）使用。
  static bool inferCharBased(NameCategory category, Map<String, List<String>> pools) {
    switch (category) {
      case NameCategory.person:
        return _isCharPool(pools[NamePoolKeys.male] ?? const []) &&
            _isCharPool(pools[NamePoolKeys.female] ?? const []);
      case NameCategory.place:
        return _isCharPool(pools[NamePoolKeys.stem] ?? const []);
    }
  }

  /// 判断词条池是否全部由单字组成（空池视为逐字池）
  static bool _isCharPool(List<String> pool) =>
      pool.every((entry) => entry.runes.length == 1);
}
