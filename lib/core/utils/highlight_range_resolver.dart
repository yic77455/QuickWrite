import 'package:flutter/widgets.dart';
import 'package:quick_write/core/utils/custom_highlight_regex.dart';

/// 带颜色与优先级的高亮范围
///
/// 用于统一表示对话高亮、自定义关键词高亮与查找匹配高亮，
/// 便于按优先级合并重叠区域。[priority] 数值越大优先级越高，
/// 重叠时高优先级范围的颜色覆盖低优先级。
class HighlightRange {
  /// 范围起始偏移（含）
  final int start;

  /// 范围结束偏移（不含）
  final int end;

  /// 该范围使用的高亮颜色
  final Color color;

  /// 优先级（数值越大优先级越高）
  final int priority;

  /// 颜色的呈现方式：true 作为文字底色，false 覆盖文字颜色
  final bool background;

  /// 叠加到文字上的字重（null 表示沿用编辑器基础字重）
  final FontWeight? fontWeight;

  /// 叠加到文字上的装饰线（null 表示沿用编辑器基础样式）
  ///
  /// 敏感词标红使用删除线标识，其它高亮类型不设置该字段。
  final TextDecoration? decoration;

  /// 装饰线颜色（null 表示跟随文字颜色）
  final Color? decorationColor;

  const HighlightRange(
    this.start,
    this.end,
    this.color,
    this.priority, {
    this.background = false,
    this.fontWeight,
    this.decoration,
    this.decorationColor,
  });

  @override
  String toString() => 'HighlightRange($start, $end, priority: $priority)';
}

/// 高亮范围解析器
///
/// 提供各类高亮范围的解析与合并原语，供编辑器的文本渲染层复用：
/// 解析对话范围、解析关键词范围、解析查找匹配范围，以及按优先级合并重叠范围。
///
/// 全部为无状态纯函数，调用方可自行决定缓存策略。
class HighlightRangeResolver {
  HighlightRangeResolver._();

  /// 对话高亮优先级（最低）
  static const int dialoguePriority = 0;

  /// 自定义关键词高亮优先级
  static const int customKeywordPriority = 1;

  /// 大纲关键词高亮优先级（仅按住关键词修饰键时参与）
  static const int outlineKeywordPriority = 2;

  /// 查找匹配高亮优先级
  static const int findMatchPriority = 3;

  /// 当前选中查找匹配的高亮优先级（最高）
  static const int currentFindMatchPriority = 4;

  /// 敏感词高亮优先级（高于查找匹配，始终以标红呈现）
  static const int sensitiveWordPriority = 5;

  /// 中文引号对定义
  ///
  /// 支持：双引号 “”、单引号 ‘’、角引号 「」
  static const List<(String, String)> quotePairs = [
    ('\u201C', '\u201D'),
    ('\u2018', '\u2019'),
    ('\u300C', '\u300D'),
  ];

  /// 解析文本中的对话范围
  ///
  /// 遍历所有引号对，找出成对包裹的起止位置；未闭合的引号会被跳过。
  static List<HighlightRange> parseDialogueRanges(
    String text,
    Color color, {
    int priority = dialoguePriority,
  }) {
    final List<HighlightRange> ranges = [];
    for (final (String open, String close) in quotePairs) {
      int searchStart = 0;
      while (searchStart < text.length) {
        final int openIndex = text.indexOf(open, searchStart);
        if (openIndex == -1) break;
        final int closeIndex = text.indexOf(close, openIndex + open.length);
        if (closeIndex == -1) {
          // 未找到匹配的右引号，跳过该左引号继续向后查找
          searchStart = openIndex + 1;
          continue;
        }
        ranges.add(HighlightRange(openIndex, closeIndex + close.length, color, priority));
        searchStart = closeIndex + close.length;
      }
    }
    return ranges;
  }

  /// 解析单个关键词在文本中的所有出现范围
  static List<HighlightRange> parseKeywordRanges(
    String text,
    String keyword,
    Color color, {
    int priority = customKeywordPriority,
  }) {
    if (keyword.isEmpty) return const [];
    final List<HighlightRange> ranges = [];
    int searchStart = 0;
    while (searchStart <= text.length - keyword.length) {
      final int index = text.indexOf(keyword, searchStart);
      if (index == -1) break;
      ranges.add(HighlightRange(index, index + keyword.length, color, priority));
      searchStart = index + keyword.length;
    }
    return ranges;
  }

  /// 解析单个正则表达式在文本中的所有命中范围
  ///
  /// 字面量模式仍走 [parseKeywordRanges]，此处只处理已经编译成功的表达式；
  /// 编译失败（非法正则）由调用方跳过，不产生任何范围。命中区间由
  /// CustomHighlightRegex 计算，含捕获组时只着色第 1 组。
  static List<HighlightRange> parseRegexRanges(
    String text,
    RegExp regex,
    Color color, {
    int priority = customKeywordPriority,
  }) {
    final List<HighlightRange> ranges = [];
    for (final match in CustomHighlightRegex.findMatches(text, regex)) {
      ranges.add(HighlightRange(match.start, match.end, color, priority));
    }
    return ranges;
  }

  /// 解析查找匹配范围
  ///
  /// [currentMatchIndex] 指向当前选中的匹配项（-1 表示无选中），该项使用更高优先级，
  /// 使其底色覆盖其它匹配项。匹配范围的颜色统一作为文字底色呈现。
  static List<HighlightRange> parseFindMatchRanges(
    List<TextSelection> matches,
    int currentMatchIndex,
    Color matchColor,
    Color currentMatchColor,
  ) {
    final List<HighlightRange> ranges = [];
    for (int i = 0; i < matches.length; i++) {
      final TextSelection match = matches[i];
      if (!match.isValid) continue;
      final bool isCurrent = i == currentMatchIndex;
      ranges.add(HighlightRange(
        match.start,
        match.end,
        isCurrent ? currentMatchColor : matchColor,
        isCurrent ? currentFindMatchPriority : findMatchPriority,
        background: true,
      ));
    }
    return ranges;
  }

  /// 解析文本中所有敏感词的出现范围
  ///
  /// 匹配不区分大小写，长词优先：同一段文字被多个词命中时由长词着色，
  /// 结果统一使用标红与删除线呈现，并采用最高优先级覆盖其它着色。
  static List<HighlightRange> parseSensitiveWordRanges(
    String text,
    List<String> words,
    Color color,
  ) {
    if (words.isEmpty || text.isEmpty) return const [];

    final String lowerText = text.toLowerCase();
    // 按长度降序匹配，保证长词优先着色
    final List<String> sorted = [
      for (final word in words)
        if (word.isNotEmpty) word.toLowerCase(),
    ]..sort((a, b) => b.length.compareTo(a.length));

    final List<HighlightRange> ranges = [];
    for (final word in sorted) {
      int searchStart = 0;
      while (searchStart <= lowerText.length - word.length) {
        final int index = lowerText.indexOf(word, searchStart);
        if (index == -1) break;
        ranges.add(HighlightRange(
          index,
          index + word.length,
          color,
          sensitiveWordPriority,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.lineThrough,
          decorationColor: color,
        ));
        searchStart = index + word.length;
      }
    }
    return ranges;
  }

  /// 合并带颜色的范围，处理重叠区域（高优先级覆盖低优先级）
  ///
  /// 使用扫描线算法：以所有范围的边界点为切分点，将文本切成不重叠的小段，
  /// 每段使用覆盖它的最高优先级范围的颜色，颜色相同的连续小段会被合并。
  static List<HighlightRange> mergeRanges(List<HighlightRange> input) {
    if (input.isEmpty) return const [];

    // 收集所有边界点并排序去重
    final Set<int> points = {};
    for (final HighlightRange range in input) {
      points.add(range.start);
      points.add(range.end);
    }
    final List<int> sortedPoints = points.toList()..sort();

    final List<HighlightRange> result = [];
    for (int i = 0; i < sortedPoints.length - 1; i++) {
      final int segStart = sortedPoints[i];
      final int segEnd = sortedPoints[i + 1];
      if (segStart >= segEnd) continue;

      // 找出覆盖此段的所有范围中优先级最高的
      HighlightRange? best;
      for (final HighlightRange range in input) {
        if (range.start <= segStart && range.end >= segEnd) {
          if (best == null || range.priority > best.priority) {
            best = range;
          }
        }
      }
      if (best == null) continue;

      // 与上一段颜色、呈现方式、字重、装饰线相同且连续时合并为一段
      if (result.isNotEmpty &&
          result.last.color == best.color &&
          result.last.background == best.background &&
          result.last.fontWeight == best.fontWeight &&
          result.last.decoration == best.decoration &&
          result.last.decorationColor == best.decorationColor &&
          result.last.end == segStart) {
        result[result.length - 1] = HighlightRange(result.last.start, segEnd,
            best.color, best.priority,
            background: best.background,
            fontWeight: best.fontWeight,
            decoration: best.decoration,
            decorationColor: best.decorationColor);
      } else {
        result.add(HighlightRange(segStart, segEnd, best.color, best.priority,
            background: best.background,
            fontWeight: best.fontWeight,
            decoration: best.decoration,
            decorationColor: best.decorationColor));
      }
    }
    return result;
  }

  /// 计算每一行在全文中的起始偏移量
  ///
  /// 行分隔符使用 `\n`，与编辑器的行模型保持一致；结果长度等于文本行数。
  static List<int> lineStarts(String text) {
    final List<int> starts = [0];
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        starts.add(i + 1);
      }
    }
    return starts;
  }

  /// 在排序后的范围列表中查找第一个可能与 `[rangeStart, rangeEnd)` 相交的范围下标
  ///
  /// 用于按行取范围时避免逐条扫描全文范围。
  static int firstOverlappingIndex(List<HighlightRange> sortedRanges, int rangeStart) {
    int low = 0;
    int high = sortedRanges.length;
    while (low < high) {
      final int mid = (low + high) >> 1;
      if (sortedRanges[mid].end <= rangeStart) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}