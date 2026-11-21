/// 正文自动替换规则
///
/// 一条规则包含两段文本：用户在正文中输入的原文本，以及替换后的文本。
/// 例如原文本为「。。。」、替换为「……」时，输入「。。。」会自动改写为「……」。
class TextReplacementRule {
  /// 需要被替换的原文本
  final String trigger;

  /// 替换后的文本
  final String replacement;

  /// 是否启用该规则
  ///
  /// 关闭后该规则不参与替换，规则本身保留在列表中
  final bool enabled;

  const TextReplacementRule({
    required this.trigger,
    required this.replacement,
    this.enabled = true,
  });

  /// 从 JSON Map 创建替换规则
  ///
  /// 字段缺失或类型异常时按空文本处理；未记录开关状态的旧配置视为启用
  factory TextReplacementRule.fromJson(Map<String, dynamic> json) {
    final Object? rawTrigger = json['trigger'];
    final Object? rawReplacement = json['replacement'];
    final Object? rawEnabled = json['enabled'];
    return TextReplacementRule(
      trigger: rawTrigger is String ? rawTrigger : '',
      replacement: rawReplacement is String ? rawReplacement : '',
      enabled: rawEnabled is bool ? rawEnabled : true,
    );
  }

  /// 将替换规则转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'trigger': trigger,
      'replacement': replacement,
      'enabled': enabled,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TextReplacementRule &&
        other.trigger == trigger &&
        other.replacement == replacement &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(trigger, replacement, enabled);
}
