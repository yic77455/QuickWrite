import 'package:flutter/widgets.dart';

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

  const HighlightRange(
    this.start,
    this.end,
    this.color,
    this.priority, {
    this.background = false,
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

  /// 查找匹配高亮优先级
  static const int findMatchPriority = 2;

  /// 当前选中查找匹配的高亮优先级（最高）
  static const int currentFindMatchPriority = 3;

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

      // 与上一段颜色、呈现方式相同且连续时合并为一段
      if (result.isNotEmpty &&
          result.last.color == best.color &&
          result.last.background == best.background &&
          result.last.end == segStart) {
        result[result.length - 1] = HighlightRange(result.last.start, segEnd,
            best.color, best.priority, background: best.background);
      } else {
        result.add(HighlightRange(segStart, segEnd, best.color, best.priority,
            background: best.background));
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