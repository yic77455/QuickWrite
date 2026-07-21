import 'dart:ui' show Color;
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/text_style_range.dart';
import 'package:quick_write/core/models/outline_models.dart';

/// 大纲节点 Markdown 序列化/反序列化工具
///
/// 将节点的标题级别和文字样式区间转换为 Markdown 格式，
/// 或从 Markdown 文本还原节点属性。
class OutlineMarkdownCodec {
  OutlineMarkdownCodec._();

  /// 将单个节点序列化为 Markdown 行
  ///
  /// - 标题级别：行首添加对应数量的 `#`（H1=`#`，H2=`##`，H3=`###`）
  /// - 文字样式：根据区间插入 Markdown 内联标记
  ///   - 加粗：`**text**`
  ///   - 斜体：`*text*`
  ///   - 删除线：`~~text~~`
  ///   - 下划线：`<u>text</u>`（Markdown 无标准语法，使用 HTML 标签）
  static String serialize(OutlineNode node) {
    final text = node.text;
    final parts = <String>[];
    var currentPos = 0;

    // 按区间分段，每段独立包裹标记
    final sortedRanges = List<TextStyleRange>.from(node.styleRanges)
      ..sort((a, b) => a.start.compareTo(b.start));

    for (final range in sortedRanges) {
      if (range.flags.isEmpty) continue;
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(0, text.length);
      if (start >= end) continue;

      // 无样式的前导段
      if (currentPos < start) {
        parts.add(text.substring(currentPos, start));
      }

      // 为当前段包裹标记（嵌套顺序：bold > italic > strikethrough > underline > fc > bc）
      var segment = text.substring(start, end);
      if (range.flags.underline) segment = '<u>$segment</u>';
      if (range.flags.strikethrough) segment = '~~$segment~~';
      if (range.flags.italic) segment = '*$segment*';
      if (range.flags.bold) segment = '**$segment**';
      // 字体颜色标签：<fc#RRGGBB>text</fc>
      if (range.flags.foregroundColor != null) {
        segment = '<fc${ColorUtils.toHex(range.flags.foregroundColor!)}>$segment</fc>';
      }
      // 字底颜色标签：<bc#RRGGBB>text</bc>
      if (range.flags.backgroundColor != null) {
        segment = '<bc${ColorUtils.toHex(range.flags.backgroundColor!)}>$segment</bc>';
      }

      parts.add(segment);
      currentPos = end;
    }

    // 尾部无样式段
    if (currentPos < text.length) {
      parts.add(text.substring(currentPos));
    }

    var result = parts.join();

    // 添加标题前缀
    if (node.headingLevel > 0) {
      result = '${'#' * node.headingLevel} $result';
    }

    return result;
  }

  /// 从 Markdown 行反序列化节点属性
  ///
  /// 返回解析得到的纯文本、标题级别和样式区间列表。
  static ({String text, int headingLevel, List<TextStyleRange> styleRanges})
      deserialize(String line) {
    var pos = 0;

    // 1. 解析标题前缀（行首 # 数量）
    int headingLevel = 0;
    while (pos < line.length && line[pos] == '#') {
      headingLevel++;
      pos++;
    }
    // 标题级别超过 3 不支持，视为正文
    if (headingLevel > 3) {
      headingLevel = 0;
      pos = 0;
    } else if (headingLevel > 0) {
      // 跳过 # 后的空格
      if (pos < line.length && line[pos] == ' ') pos++;
    }

    // 2. 解析内联标记
    final remaining = line.substring(pos);
    final result = _parseInlineMarks(remaining);

    return (
      text: result.text,
      headingLevel: headingLevel,
      styleRanges: result.styleRanges,
    );
  }

  /// 解析内联标记，返回纯文本和样式区间
  ///
  /// 通过跟踪当前打开的标记状态，在标记变化时记录区间。
  /// 支持的标记：`**`（加粗）、`*`（斜体）、`~~`（删除线）、`<u>`（下划线）、
  /// `<fc#RRGGBB>`（字体颜色）、`<bc#RRGGBB>`（字底颜色）。
  static ({String text, List<TextStyleRange> styleRanges}) _parseInlineMarks(
      String markdown) {
    final textBuffer = StringBuffer();
    final ranges = <TextStyleRange>[];
    var currentFlags = TextStyleFlags.none;
    var segmentStart = 0;

    // 各标记的开关状态
    var boldOpen = false;
    var italicOpen = false;
    var strikeOpen = false;
    var underlineOpen = false;
    // 颜色标记的当前值（null 表示未打开）
    Color? fgColorOpen;
    Color? bgColorOpen;

    /// 刷新当前段：若当前段有样式且非空，记录到区间列表
    void flushSegment() {
      final currentLen = textBuffer.length;
      if (currentLen > segmentStart && !currentFlags.isEmpty) {
        ranges.add(TextStyleRange(
          start: segmentStart,
          end: currentLen,
          flags: currentFlags,
        ));
      }
      segmentStart = currentLen;
    }

    /// 重新计算当前标记状态
    void updateFlags() {
      currentFlags = TextStyleFlags(
        bold: boldOpen,
        italic: italicOpen,
        underline: underlineOpen,
        strikethrough: strikeOpen,
        foregroundColor: fgColorOpen,
        backgroundColor: bgColorOpen,
      );
    }

    var i = 0;
    while (i < markdown.length) {
      // 检查多字符标记（按长度降序匹配，避免 * 被 ** 误匹配）
      // 颜色标签：<fc#RRGGBB>（11字符）和 <bc#RRGGBB>（11字符）
      if (markdown.startsWith('<fc#', i) &&
          i + 10 < markdown.length &&
          markdown[i + 10] == '>') {
        flushSegment();
        fgColorOpen = ColorUtils.parseHex(markdown.substring(i + 3, i + 10));
        updateFlags();
        i += 11;
      } else if (markdown.startsWith('<bc#', i) &&
          i + 10 < markdown.length &&
          markdown[i + 10] == '>') {
        flushSegment();
        bgColorOpen = ColorUtils.parseHex(markdown.substring(i + 3, i + 10));
        updateFlags();
        i += 11;
      } else if (markdown.startsWith('</fc>', i)) {
        flushSegment();
        fgColorOpen = null;
        updateFlags();
        i += 5;
      } else if (markdown.startsWith('</bc>', i)) {
        flushSegment();
        bgColorOpen = null;
        updateFlags();
        i += 5;
      } else if (markdown.startsWith('**', i)) {
        flushSegment();
        boldOpen = !boldOpen;
        updateFlags();
        i += 2;
      } else if (markdown.startsWith('~~', i)) {
        flushSegment();
        strikeOpen = !strikeOpen;
        updateFlags();
        i += 2;
      } else if (markdown.startsWith('<u>', i)) {
        flushSegment();
        underlineOpen = true;
        updateFlags();
        i += 3;
      } else if (markdown.startsWith('</u>', i)) {
        flushSegment();
        underlineOpen = false;
        updateFlags();
        i += 4;
      } else if (markdown[i] == '*') {
        flushSegment();
        italicOpen = !italicOpen;
        updateFlags();
        i++;
      } else {
        textBuffer.write(markdown[i]);
        i++;
      }
    }

    // 刷新最后一段
    flushSegment();

    return (text: textBuffer.toString(), styleRanges: ranges);
  }
}
