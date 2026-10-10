import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor 选区与扁平偏移量的转换工具
///
/// re_editor 的选区以「行号 + 行内偏移」表示，而工作台的数据契约（查找替换、
/// 章节光标缓存、字数统计）统一使用相对于全文的扁平偏移量。这里集中提供两者的互转，
/// 并统一做越界收敛，避免各处自行换算产生偏差。
class CodeLineSelectionUtils {
  CodeLineSelectionUtils._();

  /// re_editor 使用的换行符，与 CodeLineOptions 的默认行分隔保持一致
  static const int _lineBreakCodeUnit = 0x0A;

  /// 将扁平偏移量换算为「行号 + 行内偏移」
  ///
  /// [flatOffset] 会被收敛到 `[0, text.length]`。
  static (int index, int offset) linePositionOf(String text, int flatOffset) {
    final int limit = flatOffset.clamp(0, text.length);
    int lineIndex = 0;
    int lineStart = 0;
    for (int i = 0; i < limit; i++) {
      if (text.codeUnitAt(i) == _lineBreakCodeUnit) {
        lineIndex++;
        lineStart = i + 1;
      }
    }
    return (lineIndex, limit - lineStart);
  }

  /// 将「行号 + 行内偏移」换算为扁平偏移量
  ///
  /// 行号超出实际行数时收敛到文末；行内偏移超出该行长度时收敛到行尾。
  static int flatOffsetOf(String text, int lineIndex, int lineOffset) {
    int lineStart = 0;
    int currentLine = 0;
    for (int i = 0; i < text.length && currentLine < lineIndex; i++) {
      if (text.codeUnitAt(i) == _lineBreakCodeUnit) {
        currentLine++;
        lineStart = i + 1;
      }
    }
    if (currentLine < lineIndex) return text.length;
    final int lineBreakIndex = text.indexOf('\n', lineStart);
    final int lineLength = (lineBreakIndex < 0 ? text.length : lineBreakIndex) - lineStart;
    return lineStart + lineOffset.clamp(0, lineLength);
  }

  /// 由扁平范围构造选区
  static CodeLineSelection selectionFromFlat(String text, int start, int end) {
    final (int startIndex, int startOffset) = linePositionOf(text, start);
    final (int endIndex, int endOffset) = linePositionOf(text, end);
    return CodeLineSelection(
      baseIndex: startIndex,
      baseOffset: startOffset,
      extentIndex: endIndex,
      extentOffset: endOffset,
    );
  }

  /// 由扁平偏移构造折叠选区（光标位置）
  static CodeLineSelection collapsedSelection(
    String text,
    int offset, {
    TextAffinity affinity = TextAffinity.downstream,
  }) {
    final (int index, int lineOffset) = linePositionOf(text, offset);
    return CodeLineSelection.collapsed(index: index, offset: lineOffset, affinity: affinity);
  }

  /// 由扁平 TextSelection 构造选区
  ///
  /// 保留 base/extent 的方向语义，便于还原反向选区与光标亲和性。
  static CodeLineSelection selectionFromTextSelection(String text, TextSelection selection) {
    if (!selection.isValid) return collapsedSelection(text, text.length);
    final (int baseIndex, int baseOffset) = linePositionOf(text, selection.baseOffset);
    final (int extentIndex, int extentOffset) = linePositionOf(text, selection.extentOffset);
    return CodeLineSelection(
      baseIndex: baseIndex,
      baseOffset: baseOffset,
      baseAffinity: selection.affinity,
      extentIndex: extentIndex,
      extentOffset: extentOffset,
      extentAffinity: selection.affinity,
    );
  }

  /// 将选区换算回扁平 TextSelection
  ///
  /// 同样保留 base/extent 的方向语义。
  static TextSelection flatSelectionOf(String text, CodeLineSelection selection) {
    final int base = flatOffsetOf(text, selection.baseIndex, selection.baseOffset);
    final int extent = flatOffsetOf(text, selection.extentIndex, selection.extentOffset);
    return TextSelection(
      baseOffset: base,
      extentOffset: extent,
      affinity: selection.extentAffinity,
    );
  }
}