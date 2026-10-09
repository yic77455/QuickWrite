/// 未设置哨兵
///
/// [KeyColors.copyWith] 借助它区分「不修改该字段」与「将该字段重置为未覆盖（null）」
const Object _unset = Object();

/// 自定义主题的关键色集合
///
/// 关键色是用户可直接调整的语义色，其余语义色在应用时由关键色自动派生。
/// 所有字段均为十六进制颜色字符串（#RRGGBB），为 null 表示未覆盖、继承基底主题。
/// 明暗两种基底各持有一份关键色，从而在切换亮/暗模式时分别生效。
class KeyColors {
  /// 主色调（用于主要按钮、选中状态等）
  final String? primary;

  /// 强调色（次要强调，对应次要颜色组）
  final String? accent;

  /// 页面主背景色
  final String? background;

  /// 表面色（面板、侧边栏、工具栏、标签栏）
  final String? surface;

  /// 主要文字颜色
  final String? text;

  /// 链接/次级强调文字颜色
  final String? textSecondary;

  /// 边框色（对应可见轮廓）
  final String? border;

  /// 悬停背景色
  final String? hover;

  /// 选中背景色
  final String? selection;

  /// 错误色
  final String? error;

  const KeyColors({
    this.primary,
    this.accent,
    this.background,
    this.surface,
    this.text,
    this.textSecondary,
    this.border,
    this.hover,
    this.selection,
    this.error,
  });

  /// 空关键色集合，所有字段均未覆盖
  static const KeyColors empty = KeyColors();

  /// 从 JSON Map 创建关键色集合
  factory KeyColors.fromJson(Map<String, dynamic> json) {
    return KeyColors(
      primary: json['primary'] as String?,
      accent: json['accent'] as String?,
      background: json['background'] as String?,
      surface: json['surface'] as String?,
      text: json['text'] as String?,
      textSecondary: json['textSecondary'] as String?,
      border: json['border'] as String?,
      hover: json['hover'] as String?,
      selection: json['selection'] as String?,
      error: json['error'] as String?,
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'primary': primary,
      'accent': accent,
      'background': background,
      'surface': surface,
      'text': text,
      'textSecondary': textSecondary,
      'border': border,
      'hover': hover,
      'selection': selection,
      'error': error,
    };
  }

  /// 创建设置副本，用于更新部分关键色
  ///
  /// 未传入的字段保持原值；显式传入 null 表示将该字段重置为未覆盖状态
  KeyColors copyWith({
    Object? primary = _unset,
    Object? accent = _unset,
    Object? background = _unset,
    Object? surface = _unset,
    Object? text = _unset,
    Object? textSecondary = _unset,
    Object? border = _unset,
    Object? hover = _unset,
    Object? selection = _unset,
    Object? error = _unset,
  }) {
    return KeyColors(
      primary: identical(primary, _unset) ? this.primary : primary as String?,
      accent: identical(accent, _unset) ? this.accent : accent as String?,
      background: identical(background, _unset) ? this.background : background as String?,
      surface: identical(surface, _unset) ? this.surface : surface as String?,
      text: identical(text, _unset) ? this.text : text as String?,
      textSecondary: identical(textSecondary, _unset) ? this.textSecondary : textSecondary as String?,
      border: identical(border, _unset) ? this.border : border as String?,
      hover: identical(hover, _unset) ? this.hover : hover as String?,
      selection: identical(selection, _unset) ? this.selection : selection as String?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeyColors &&
        other.primary == primary &&
        other.accent == accent &&
        other.background == background &&
        other.surface == surface &&
        other.text == text &&
        other.textSecondary == textSecondary &&
        other.border == border &&
        other.hover == hover &&
        other.selection == selection &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(
        primary,
        accent,
        background,
        surface,
        text,
        textSecondary,
        border,
        hover,
        selection,
        error,
      );

  @override
  String toString() =>
      'KeyColors(primary: $primary, background: $background, surface: $surface, text: $text)';
}

/// 一套自定义主题
///
/// 由亮色与暗色两份关键色组成，用户在明暗模式切换时分别应用对应关键色，
/// 未覆盖的字段继承对应亮/暗基底主题。
class CustomTheme {
  /// 唯一标识
  final String id;

  /// 显示名称
  final String name;

  /// 亮色基底下的关键色
  final KeyColors light;

  /// 暗色基底下的关键色
  final KeyColors dark;

  const CustomTheme({
    required this.id,
    required this.name,
    this.light = KeyColors.empty,
    this.dark = KeyColors.empty,
  });

  /// 从 JSON Map 创建自定义主题
  factory CustomTheme.fromJson(Map<String, dynamic> json) {
    return CustomTheme(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '自定义主题',
      light: KeyColors.fromJson(json['light'] as Map<String, dynamic>? ?? {}),
      dark: KeyColors.fromJson(json['dark'] as Map<String, dynamic>? ?? {}),
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'light': light.toJson(),
      'dark': dark.toJson(),
    };
  }

  /// 创建设置副本，用于更新部分字段
  CustomTheme copyWith({
    String? id,
    String? name,
    KeyColors? light,
    KeyColors? dark,
  }) {
    return CustomTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      light: light ?? this.light,
      dark: dark ?? this.dark,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomTheme &&
        other.id == id &&
        other.name == name &&
        other.light == light &&
        other.dark == dark;
  }

  @override
  int get hashCode => Object.hash(id, name, light, dark);

  @override
  String toString() => 'CustomTheme(id: $id, name: $name)';
}