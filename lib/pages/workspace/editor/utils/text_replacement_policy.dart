import 'package:quick_write/core/models/text_replacement_rule.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:re_editor/re_editor.dart';

/// 正文自动替换策略
///
/// 用于编辑器主动插入文本（如快捷输入栏的符号与快捷短语）的场景：
/// 插入后若光标前文本以某条规则的原文本结尾，则把这段原文本改写为规则指定的替换文本。
/// 键盘输入与输入法输入由编辑器在输入链路中直接处理，不经过本策略。
class TextReplacementPolicy {
  TextReplacementPolicy({required this.controller});

  /// 被操作的编辑控制器
  final CodeLineEditingController controller;

  /// 在光标处尝试应用自动替换规则
  ///
  /// 仅处理光标位于单行内部、且光标前文本以规则原文本结尾的情况；
  /// 多条规则同时命中时取原文本最长的一条。
  /// 返回是否已执行替换。
  bool applyIfMatched() {
    final List<TextReplacementRule> rules = SettingsService.instance.textReplacementRules;
    if (rules.isEmpty) return false;

    final CodeLineSelection selection = controller.selection;
    if (!selection.isCollapsed) return false;

    final int index = selection.startIndex;
    final int offset = selection.startOffset;
    if (offset == 0) return false;

    final String line = controller.codeLines[index].text;
    if (offset > line.length) return false;

    TextReplacementRule? matched;
    for (final TextReplacementRule rule in rules) {
      if (!rule.enabled) continue;
      final String trigger = rule.trigger;
      if (trigger.isEmpty || trigger.length > offset) continue;
      // 已有更长的规则命中时，短规则不再覆盖
      if (matched != null && trigger.length <= matched.trigger.length) continue;
      if (!line.startsWith(trigger, offset - trigger.length)) continue;
      matched = rule;
    }
    if (matched == null || matched.trigger == matched.replacement) return false;

    final int start = offset - matched.trigger.length;
    controller.replaceSelection(
      matched.replacement,
      CodeLineSelection(
        baseIndex: index,
        baseOffset: start,
        extentIndex: index,
        extentOffset: offset,
      ),
    );
    return true;
  }
}
