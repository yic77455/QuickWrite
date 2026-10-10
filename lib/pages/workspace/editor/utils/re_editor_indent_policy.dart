import 'package:quick_write/core/services/settings_service.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor 段落缩进策略
///
/// re_editor 没有 TextInputFormatter 钩子，且其内置的回车行为只沿用行首 ASCII 空格，
/// 因此这里在控制器层复刻原有的段落格式化规则：
/// - 回车：在非行首位置换行后，按设置补空行与两个全角空格缩进
/// - Tab：插入两个全角空格作为缩进
/// - 退格：行首的双全角缩进一次性删除，其余情况执行默认退格
///
/// 各方法由编辑器覆盖对应快捷键动作后调用。
class ReEditorIndentPolicy {
  ReEditorIndentPolicy({required this.controller});

  /// 段落首行缩进使用的两个全角空格
  static const String indent = '\u3000\u3000';

  /// 被操作的编辑控制器
  final CodeLineEditingController controller;

  /// 处理回车
  ///
  /// 光标位于行首时不触发自动格式化，仅插入换行；
  /// 位于行中或行末时，按设置依次补空行与首行缩进。
  void handleNewLine() {
    final SettingsService settings = SettingsService.instance;
    final CodeLineSelection selection = controller.selection;
    final bool atLineStart = selection.isCollapsed && selection.startOffset == 0;
    if (atLineStart) {
      controller.replaceSelection('\n');
      return;
    }

    final StringBuffer buffer = StringBuffer('\n');
    if (settings.autoLineBreak) {
      buffer.write('\n');
    }
    if (settings.isFirstLineIndentEnabled) {
      buffer.write(indent);
    }
    controller.replaceSelection(buffer.toString());
  }

  /// 处理 Tab：在光标处插入两个全角空格
  void handleTab() {
    controller.replaceSelection(indent);
  }

  /// 处理退格
  ///
  /// 光标位于行首两个全角空格之后时，一次删除两个；否则执行默认退格。
  void handleBackspace() {
    if (_removeLineStartIndentIfNeeded()) return;
    controller.deleteBackward();
  }

  /// 判断并删除行首的双全角缩进
  ///
  /// 返回是否已处理（处理时不再执行默认退格）。
  bool _removeLineStartIndentIfNeeded() {
    if (!SettingsService.instance.isFirstLineIndentEnabled) return false;

    final CodeLineSelection selection = controller.selection;
    if (!selection.isCollapsed || selection.startOffset != indent.length) return false;

    final CodeLine line = controller.codeLines[selection.startIndex];
    if (!line.text.startsWith(indent)) return false;

    // 选中行首两个全角空格后删除，光标自然落到行首
    controller.selection = CodeLineSelection(
      baseIndex: selection.startIndex,
      baseOffset: 0,
      extentIndex: selection.startIndex,
      extentOffset: indent.length,
    );
    controller.deleteSelection();
    return true;
  }
}