import 'package:quick_write/core/services/settings_service.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor 段落缩进策略
///
/// re_editor 没有 TextInputFormatter 钩子，且其内置的回车行为只沿用行首 ASCII 空格，
/// 因此这里在控制器层复刻原有的段落格式化规则：
/// - 回车：在非行首位置换行后，按设置补空行；缩进由全角空格实现时补两个全角空格，
///   否则由编辑器排版绘制视觉缩进，不写入字符
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
  /// 光标位于成对符号之间时，将光标移至结束符号之后；
  /// 光标位于行首时不触发自动格式化，仅插入换行；
  /// 位于行中或行末时，按设置依次补空行与首行缩进。
  /// 仅在缩进由全角空格实现时写入缩进字符。
  void handleNewLine() {
    if (_jumpOverClosingSymbolIfNeeded()) return;

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
    if (settings.isFirstLineIndentEnabled && settings.isFullWidthSpaceIndentEnabled) {
      buffer.write(indent);
    }
    controller.replaceSelection(buffer.toString());
  }

  /// 成对符号回车跳出
  ///
  /// 光标位于某一对成对符号内部时（不论符号内是否已有内容），
  /// 把光标移到该对结束符号之后，不插入换行。
  /// 返回是否已处理（处理时不再执行换行）。
  bool _jumpOverClosingSymbolIfNeeded() {
    if (!SettingsService.instance.pairedSymbolEnterJumpEnabled) return false;

    // 成对符号取自快捷输入栏当前的符号表，随用户自定义即时生效
    final Map<String, String> closingSymbols = {
      for (final symbol in SettingsService.instance.quickInputSymbols)
        if (symbol.isPairStart) symbol.symbol: symbol.closing!,
    };
    // 结束符号到起始符号的反向映射，用于识别已闭合的符号
    final Map<String, String> openingSymbols = {
      for (final entry in closingSymbols.entries) entry.value: entry.key,
    };

    final CodeLineSelection selection = controller.selection;
    if (!selection.isCollapsed) return false;

    final String line = controller.codeLines[selection.startIndex].text;
    final int offset = selection.startOffset;

    // 扫描光标之前的文本，记录尚未闭合的起始符号
    final List<String> pending = [];
    for (int i = 0; i < offset; i++) {
      final String char = line[i];
      if (closingSymbols.containsKey(char)) {
        pending.add(char);
      } else if (openingSymbols.containsKey(char) &&
          pending.isNotEmpty &&
          closingSymbols[pending.last] == char) {
        pending.removeLast();
      }
    }
    if (pending.isEmpty) return false;

    // 光标处的嵌套深度，用于识别最内层符号的结束位置
    final int depth = pending.length;
    for (int i = offset; i < line.length; i++) {
      final String char = line[i];
      if (closingSymbols.containsKey(char)) {
        pending.add(char);
      } else if (openingSymbols.containsKey(char) &&
          pending.isNotEmpty &&
          closingSymbols[pending.last] == char) {
        pending.removeLast();
        // 回到光标所在的层级，说明已到达这对符号的结束处
        if (pending.length == depth - 1) {
          controller.selection = CodeLineSelection.collapsed(
            index: selection.startIndex,
            offset: i + char.length,
          );
          return true;
        }
      }
    }
    return false;
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