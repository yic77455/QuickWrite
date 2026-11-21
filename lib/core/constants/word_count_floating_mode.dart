/// 移动端字数浮窗的显示样式
///
/// 控制浮窗中每一行统计的展示内容：
/// 标准模式显示图标、标签与数值；精简模式隐藏标签；极简模式仅保留数值。
/// [id] 用于持久化到配置文件，[label] 用于设置面板的选项文字。
enum WordCountFloatingMode {
  /// 图标 + 标签 + 数值
  standard('standard', '标准'),

  /// 图标 + 数值（不显示标签）
  compact('compact', '精简'),

  /// 仅数值（不显示图标与标签）
  minimal('minimal', '极简');

  /// 持久化到配置文件的标识
  final String id;

  /// 设置面板中显示的选项文字
  final String label;

  const WordCountFloatingMode(this.id, this.label);

  /// 是否显示图标
  bool get showIcon => this != WordCountFloatingMode.minimal;

  /// 是否显示标签
  bool get showLabel => this == WordCountFloatingMode.standard;

  /// 默认显示样式
  static const WordCountFloatingMode defaultMode = WordCountFloatingMode.standard;

  /// 按持久化标识解析显示样式
  ///
  /// 标识为空或无法识别时回退到 [defaultMode]，兼容配置文件缺失该字段的情况
  static WordCountFloatingMode fromId(String? id) {
    for (final mode in WordCountFloatingMode.values) {
      if (mode.id == id) return mode;
    }
    return defaultMode;
  }
}
