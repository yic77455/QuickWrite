import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 查找匹配高亮工具
///
/// 在编辑器的 TextSpan 列表上叠加查找匹配项的背景高亮，
/// 使所有匹配的关键词以浅色标识，当前选中的匹配项以更醒目的颜色标识。
class FindMatchHighlighter {
  /// 将查找匹配高亮应用到一组按文本顺序排列的 TextSpan 上
  ///
  /// [spans] 已构建好的扁平 TextSpan 列表，每个 span 的 [TextSpan.text] 非空
  /// [matches] 匹配范围列表，偏移量相对于 spans 拼接后的完整文本
  /// [currentMatchIndex] 当前选中匹配在 [matches] 中的索引（-1 表示无选中）
  /// [matchColor] 普通匹配项的背景色
  /// [currentMatchColor] 当前选中匹配项的背景色
  ///
  /// 返回新的 TextSpan 列表，匹配范围内的文本被附加了背景色
  static List<TextSpan> apply({
    required List<TextSpan> spans,
    required List<TextSelection> matches,
    required int currentMatchIndex,
    required Color matchColor,
    required Color currentMatchColor,
  }) {
    if (matches.isEmpty || spans.isEmpty) return spans;

    final result = <TextSpan>[];
    int currentOffset = 0;

    for (final span in spans) {
      final spanText = span.text ?? '';
      final spanLength = spanText.length;
      final spanEnd = currentOffset + spanLength;

      // 收集与当前 span 重叠的匹配项索引
      final overlapping = <int>[];
      for (int i = 0; i < matches.length; i++) {
        final m = matches[i];
        // 跳过空范围匹配
        if (m.start >= m.end) continue;
        // 判断是否与当前 span 重叠（左闭右开区间）
        if (m.start < spanEnd && m.end > currentOffset) {
          overlapping.add(i);
        }
      }

      if (overlapping.isEmpty) {
        // 无重叠：原样保留
        result.add(span);
      } else {
        // 有重叠：按匹配边界分段，对落在匹配范围内的段附加背景色
        int pos = currentOffset;
        for (final idx in overlapping) {
          final m = matches[idx];
          // 将匹配范围裁剪到当前 span 范围内
          final matchStart = math.max(m.start, currentOffset);
          final matchEnd = math.min(m.end, spanEnd);

          // 匹配前的普通段
          if (matchStart > pos) {
            result.add(TextSpan(
              text: spanText.substring(pos - currentOffset, matchStart - currentOffset),
              style: span.style,
            ));
          }

          // 匹配段：当前选中匹配用 currentMatchColor，其他用 matchColor
          final isCurrent = idx == currentMatchIndex;
          result.add(TextSpan(
            text: spanText.substring(matchStart - currentOffset, matchEnd - currentOffset),
            style: span.style?.copyWith(
              backgroundColor: isCurrent ? currentMatchColor : matchColor,
            ),
          ));
          pos = matchEnd;
        }

        // 最后一个匹配之后的普通段
        if (pos < spanEnd) {
          result.add(TextSpan(
            text: spanText.substring(pos - currentOffset),
            style: span.style,
          ));
        }
      }

      currentOffset = spanEnd;
    }

    return result;
  }

  /// 获取普通匹配项的背景色（根据主题亮度自适应）
  static Color getMatchColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 暗色主题使用稍亮的黄色以保证可见性，亮色主题使用较淡的黄色
    return isDark
        ? const Color(0x66FFC107) // amber 500 @ 40%
        : const Color(0x55FFEB3B); // yellow 500 @ 33%
  }

  /// 获取当前选中匹配项的背景色（根据主题亮度自适应）
  static Color getCurrentMatchColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 当前匹配项需要比普通匹配更醒目
    return isDark
        ? const Color(0xFFFFC107) // amber 500 实色
        : const Color(0xFFFFA000); // amber 700 实色
  }
}
