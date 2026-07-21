import 'package:flutter/services.dart';
import 'package:quick_write/core/services/settings_service.dart';

/// 段落格式化工具
///
/// 当检测到用户输入换行符时，根据设置自动在段首添加两个全角空格，
/// 并根据设置自动插入空行
///
/// 另：当首行缩进开启时，退格删除行首的全角空格会一次性删除两个，
/// 避免用户需要连按两次退格才能清除段首缩进
class ParagraphFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final settings = SettingsService.instance;

    final String oldText = oldValue.text;
    final String newText = newValue.text;

    // 退格删除首行缩进的全角空格：一次退格连带删除两个 \u3000
    // 仅在首行缩进开启时生效，且要求删除的是行首两个连续全角空格中的一个
    if (settings.isFirstLineIndentEnabled &&
        newText.length == oldText.length - 1 &&
        newValue.selection.isCollapsed) {
      final int newCursor = newValue.selection.baseOffset;
      // 光标前至少要有一个字符（剩余的那个全角空格）
      if (newCursor >= 1 && newCursor < oldText.length) {
        // 被删除的字符在 oldText 中位于 newCursor 位置
        final bool deletedWasIndentSpace = oldText[newCursor] == '\u{3000}';
        // newText 中光标前一个字符也必须是全角空格（即剩余的那个缩进空格）
        final bool remainsIndentSpace = newText[newCursor - 1] == '\u{3000}';
        // 这两个全角空格必须位于行首（前面是换行符或文本起始）
        final bool atLineStart = newCursor < 2 || newText[newCursor - 2] == '\n';

        if (deletedWasIndentSpace && remainsIndentSpace && atLineStart) {
          // 连带删除剩余的全角空格
          final String resultText =
              newText.substring(0, newCursor - 1) + newText.substring(newCursor);
          return TextEditingValue(
            text: resultText,
            selection: TextSelection.collapsed(offset: newCursor - 1),
          );
        }
      }
    }

    // 检测是否只输入了一个换行符
    // 长度只增加了1，且新增的是换行符
    if (newText.length != oldText.length + 1) {
      return newValue;
    }

    final int cursorPos = newValue.selection.baseOffset;
    if (cursorPos <= 0 || newText[cursorPos - 1] != '\n') {
      return newValue;
    }

    // 检查换行前光标是否位于行首
    // 若位于行首（光标前为换行符或处于文本起始位置），说明用户是在已有段落行首按回车插入空行，
    // 不应触发首行缩进和自动空行；
    // 否则（行中或行末换行），正常触发首行缩进和自动空行
    final int oldCursorPos = cursorPos - 1; // 换行符插入前光标在旧文本中的位置
    final bool isAtLineStart = oldCursorPos == 0 || oldText[oldCursorPos - 1] == '\n';
    if (isAtLineStart) {
      // 光标位于行首，不触发自动格式化
      return newValue;
    }

    String resultText = newText;
    int cursorOffset = 0;

    // 处理自动空行：在换行符后再插入一个换行符
    if (settings.autoLineBreak) {
      resultText = '${resultText.substring(0, cursorPos)}\n${resultText.substring(cursorPos)}';
      cursorOffset += 1;
    }

    // 处理首行缩进：在换行符后插入两个全角空格
    if (settings.isFirstLineIndentEnabled) {
      final int indentCursorPos = cursorPos + cursorOffset;
      resultText = '${resultText.substring(0, indentCursorPos)}\u{3000}\u{3000}${resultText.substring(indentCursorPos)}';
      cursorOffset += 2;
    }

    if (cursorOffset > 0) {
      return TextEditingValue(
        text: resultText,
        selection: TextSelection.collapsed(offset: cursorPos + cursorOffset),
      );
    }

    return newValue;
  }

  /// 对文本进行段落格式化
  ///
  /// 根据设置项对已有文档进行格式化，包括首行缩进和自动空行
  /// 如果设置项关闭，则清除对应的格式
  static String formatText(String text) {
    final settings = SettingsService.instance;
    
    // 按换行符分割成行（同时处理单换行和双换行）
    final lines = text.split('\n');
    final List<String> contentLines = [];
    
    for (final line in lines) {
      // 跳过空行
      if (line.isEmpty) {
        continue;
      }
      contentLines.add(line);
    }
    
    final List<String> formattedLines = [];
    
    for (final line in contentLines) {
      String formattedLine = line;
      
      // 处理首行缩进
      if (settings.isFirstLineIndentEnabled) {
        // 开启时：去除行首已有的空白字符，然后添加两个全角空格
        formattedLine = formattedLine.replaceFirst(RegExp(r'^[\u{3000}\s]+'), '');
        formattedLine = '\u{3000}\u{3000}$formattedLine';
      } else {
        // 关闭时：清除行首的全角空格
        formattedLine = formattedLine.replaceFirst(RegExp(r'^[\u{3000}\s]+'), '');
      }
      
      formattedLines.add(formattedLine);
    }
    
    // 根据自动空行设置连接行
    if (settings.autoLineBreak) {
      return formattedLines.join('\n\n');
    } else {
      return formattedLines.join('\n');
    }
  }
}