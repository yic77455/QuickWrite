import 'dart:math' as math;
import 'dart:ui' show Color;

/// 文字样式标记位
///
/// 用一组布尔值表示一段文字的样式开关，
/// 每个标记位独立，可任意组合。
/// [foregroundColor] 和 [backgroundColor] 为可选的颜色属性，
/// 用于字体颜色和字底颜色功能。
class TextStyleFlags {
  /// 加粗
  final bool bold;

  /// 斜体
  final bool italic;

  /// 下划线
  final bool underline;

  /// 删除线
  final bool strikethrough;

  /// 字体颜色（null 表示使用默认颜色）
  final Color? foregroundColor;

  /// 字底颜色（null 表示使用默认背景）
  final Color? backgroundColor;

  const TextStyleFlags({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.foregroundColor,
    this.backgroundColor,
  });

  /// 空样式（所有标记位均为 false，颜色为 null）
  static const TextStyleFlags none = TextStyleFlags();

  /// 是否没有任何样式标记
  bool get isEmpty =>
      !bold &&
      !italic &&
      !underline &&
      !strikethrough &&
      foregroundColor == null &&
      backgroundColor == null;

  /// 合并两组样式（区间叠加时使用）
  ///
  /// 布尔标记位取或运算；颜色属性以 [other] 优先（后覆盖前）。
  TextStyleFlags merge(TextStyleFlags other) => TextStyleFlags(
        bold: bold || other.bold,
        italic: italic || other.italic,
        underline: underline || other.underline,
        strikethrough: strikethrough || other.strikethrough,
        foregroundColor: other.foregroundColor ?? foregroundColor,
        backgroundColor: other.backgroundColor ?? backgroundColor,
      );

  /// 切换指定标记位
  ///
  /// 传入非 null 的标记位会被覆盖为新值，未传入的保持不变。
  TextStyleFlags toggle({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
  }) =>
      TextStyleFlags(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
      );

  /// 复制并修改属性
  ///
  /// 布尔标记位通过 nullable 参数覆盖；
  /// 颜色属性通过 [foregroundColor]/[backgroundColor] 设置新值，
  /// 通过 [clearForegroundColor]/[clearBackgroundColor] 清除为 null。
  TextStyleFlags copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    Color? foregroundColor,
    Color? backgroundColor,
    bool clearForegroundColor = false,
    bool clearBackgroundColor = false,
  }) =>
      TextStyleFlags(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        foregroundColor:
            clearForegroundColor ? null : (foregroundColor ?? this.foregroundColor),
        backgroundColor:
            clearBackgroundColor ? null : (backgroundColor ?? this.backgroundColor),
      );

  /// 切换加粗标记位的函数（用于 [TextStyleRangeUtils.applyToggle]）
  static TextStyleFlags toggleBold(TextStyleFlags current) =>
      current.toggle(bold: !current.bold);

  /// 切换斜体标记位的函数
  static TextStyleFlags toggleItalic(TextStyleFlags current) =>
      current.toggle(italic: !current.italic);

  /// 切换下划线标记位的函数
  static TextStyleFlags toggleUnderline(TextStyleFlags current) =>
      current.toggle(underline: !current.underline);

  /// 切换删除线标记位的函数
  static TextStyleFlags toggleStrikethrough(TextStyleFlags current) =>
      current.toggle(strikethrough: !current.strikethrough);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextStyleFlags &&
          bold == other.bold &&
          italic == other.italic &&
          underline == other.underline &&
          strikethrough == other.strikethrough &&
          foregroundColor == other.foregroundColor &&
          backgroundColor == other.backgroundColor;

  @override
  int get hashCode => Object.hash(
      bold, italic, underline, strikethrough, foregroundColor, backgroundColor);

  @override
  String toString() =>
      'TextStyleFlags(b:$bold, i:$italic, u:$underline, s:$strikethrough, '
      'fc:$foregroundColor, bc:$backgroundColor)';
}

/// 样式区间
///
/// 表示文本中 [start, end) 范围内的样式标记。
/// 区间为左闭右开，end 不包含在内。
class TextStyleRange {
  /// 起始位置（包含）
  final int start;

  /// 结束位置（不包含）
  final int end;

  /// 该区间的样式标记
  final TextStyleFlags flags;

  const TextStyleRange({
    required this.start,
    required this.end,
    required this.flags,
  });

  TextStyleRange copyWith({
    int? start,
    int? end,
    TextStyleFlags? flags,
  }) =>
      TextStyleRange(
        start: start ?? this.start,
        end: end ?? this.end,
        flags: flags ?? this.flags,
      );

  /// 区间长度
  int get length => end - start;

  @override
  String toString() => 'TextStyleRange($start-$end, $flags)';
}

/// 样式区间操作工具
///
/// 提供对 [TextStyleRange] 列表的规范化、样式切换、合并等操作，
/// 用于富文本编辑中区间样式的维护。
class TextStyleRangeUtils {
  TextStyleRangeUtils._();

  /// 对文本区间应用样式切换
  ///
  /// [ranges] 现有样式区间列表
  /// [start] [end] 目标区间（左闭右开）
  /// [toggleFn] 接收目标区间内当前的样式，返回切换后的新样式
  /// [textLength] 文本总长度，用于边界裁剪
  ///
  /// 返回新的区间列表，已规范化为不重叠、相邻相同样式合并的形式。
  static List<TextStyleRange> applyToggle(
    List<TextStyleRange> ranges,
    int start,
    int end,
    TextStyleFlags Function(TextStyleFlags current) toggleFn,
    int textLength,
  ) {
    // 边界裁剪
    start = start.clamp(0, textLength);
    end = end.clamp(0, textLength);
    if (start >= end) return _normalize(ranges, textLength);

    // 1. 规范化为不重叠的原子段，每段携带合并后的样式
    final atoms = _atomize(ranges, textLength);

    // 2. 对每个原子段：若与 [start, end] 重叠，拆分为前/中/后三段，
    //    中段应用 toggleFn，前/后段保留原样式
    final result = <TextStyleRange>[];
    for (final atom in atoms) {
      if (atom.end <= start || atom.start >= end) {
        // 无重叠，原样保留（跳过空样式段）
        if (!atom.flags.isEmpty) result.add(atom);
        continue;
      }
      // 前段：在 start 之前的部分
      if (atom.start < start && !atom.flags.isEmpty) {
        result.add(TextStyleRange(
          start: atom.start,
          end: start,
          flags: atom.flags,
        ));
      }
      // 中段：与 [start, end] 重叠的部分，应用样式切换
      final midStart = math.max(atom.start, start);
      final midEnd = math.min(atom.end, end);
      final newFlags = toggleFn(atom.flags);
      if (!newFlags.isEmpty) {
        result.add(TextStyleRange(
          start: midStart,
          end: midEnd,
          flags: newFlags,
        ));
      }
      // 后段：在 end 之后的部分
      if (atom.end > end && !atom.flags.isEmpty) {
        result.add(TextStyleRange(
          start: end,
          end: atom.end,
          flags: atom.flags,
        ));
      }
    }

    // 3. 合并相邻且样式相同的段
    return _mergeAdjacent(result);
  }

  /// 调整区间位置以适配文本插入
  ///
  /// 在 [insertPos] 处插入长度为 [insertLength] 的文本时：
  /// - 完全在插入点之前的区间保持不变
  /// - 完全在插入点之后的区间整体后移
  /// - 跨越插入点（包括末尾恰好位于插入点）的区间延伸 end 以包含新文本，使新键入的文字继承前一段的样式
  static List<TextStyleRange> adjustForInsertion(
    List<TextStyleRange> ranges,
    int insertPos,
    int insertLength,
  ) {
    final result = <TextStyleRange>[];
    for (final r in ranges) {
      if (r.end < insertPos) {
        // 区间完全在插入点之前，不变
        result.add(r);
      } else if (r.start >= insertPos) {
        // 区间完全在插入点之后，整体后移
        result.add(r.copyWith(
          start: r.start + insertLength,
          end: r.end + insertLength,
        ));
      } else {
        // 区间跨越或紧邻插入点（r.end == insertPos），
        // 延伸 end 以包含新文本，使新键入文字继承前一段样式
        result.add(r.copyWith(end: r.end + insertLength));
      }
    }
    return result;
  }

  /// 调整区间位置以适配文本删除
  ///
  /// 删除 [deleteStart, deleteEnd) 范围的文本时，
  /// 相应调整或移除受影响的区间。
  static List<TextStyleRange> adjustForDeletion(
    List<TextStyleRange> ranges,
    int deleteStart,
    int deleteEnd,
  ) {
    if (deleteStart >= deleteEnd) return List.of(ranges);
    final deletedLength = deleteEnd - deleteStart;
    final result = <TextStyleRange>[];
    for (final r in ranges) {
      if (r.end <= deleteStart) {
        // 区间完全在删除区之前，不变
        result.add(r);
      } else if (r.start >= deleteEnd) {
        // 区间完全在删除区之后，整体前移
        result.add(r.copyWith(
          start: r.start - deletedLength,
          end: r.end - deletedLength,
        ));
      } else if (r.start >= deleteStart && r.end <= deleteEnd) {
        // 区间完全在删除区内，丢弃
        continue;
      } else {
        // 区间与删除区部分重叠，裁剪
        final newStart = r.start < deleteStart ? r.start : deleteStart;
        final newEnd = r.end > deleteEnd ? r.end - deletedLength : deleteStart;
        if (newStart < newEnd && !r.flags.isEmpty) {
          result.add(TextStyleRange(
            start: newStart,
            end: newEnd,
            flags: r.flags,
          ));
        }
      }
    }
    return _mergeAdjacent(result);
  }

  /// 裁剪区间到 [0, textLength] 范围内
  ///
  /// 文本长度变化后调用，丢弃超出范围的区间，裁剪边界。
  static List<TextStyleRange> clampToTextLength(
    List<TextStyleRange> ranges,
    int textLength,
  ) {
    final result = <TextStyleRange>[];
    for (final r in ranges) {
      final newStart = r.start.clamp(0, textLength);
      final newEnd = r.end.clamp(0, textLength);
      if (newStart < newEnd && !r.flags.isEmpty) {
        result.add(TextStyleRange(
          start: newStart,
          end: newEnd,
          flags: r.flags,
        ));
      }
    }
    return _mergeAdjacent(result);
  }

  /// 根据文本变化调整样式区间
  ///
  /// 比较旧文本和新文本，找到变化区间（公共前缀和后缀之间的部分），
  /// 先移除被删除文本对应的区间，再将后续区间后移以适配插入的文本。
  ///
  /// 用于文本编辑时维护样式区间的正确位置。
  static List<TextStyleRange> adjustForTextChange(
    List<TextStyleRange> ranges,
    String oldText,
    String newText,
  ) {
    final oldLen = oldText.length;
    final newLen = newText.length;
    if (oldText == newText) return ranges;

    // 找公共前缀长度
    int prefixLen = 0;
    while (prefixLen < oldLen &&
        prefixLen < newLen &&
        oldText[prefixLen] == newText[prefixLen]) {
      prefixLen++;
    }

    // 找公共后缀起始位置
    int oldSuffixStart = oldLen;
    int newSuffixStart = newLen;
    while (oldSuffixStart > prefixLen &&
        newSuffixStart > prefixLen &&
        oldText[oldSuffixStart - 1] == newText[newSuffixStart - 1]) {
      oldSuffixStart--;
      newSuffixStart--;
    }

    // 变化区间：oldText[prefixLen, oldSuffixStart) 被替换为 newText[prefixLen, newSuffixStart)
    final deleteStart = prefixLen;
    final deleteEnd = oldSuffixStart;
    final insertLength = newSuffixStart - prefixLen;

    // 先调整删除，再调整插入
    var result = adjustForDeletion(ranges, deleteStart, deleteEnd);
    result = adjustForInsertion(result, deleteStart, insertLength);
    return result;
  }

  /// 将重叠的区间列表规范化为不重叠的原子段
  ///
  /// 每个原子段携带其覆盖的所有原始区间的合并样式。
  static List<TextStyleRange> _atomize(
    List<TextStyleRange> ranges,
    int textLength,
  ) {
    if (ranges.isEmpty) {
      return textLength > 0
          ? [TextStyleRange(start: 0, end: textLength, flags: TextStyleFlags.none)]
          : [];
    }

    // 收集所有边界点
    final points = <int>{0, textLength};
    for (final r in ranges) {
      points.add(r.start.clamp(0, textLength));
      points.add(r.end.clamp(0, textLength));
    }
    final sortedPoints = points.toList()..sort();

    final atoms = <TextStyleRange>[];
    for (var i = 0; i < sortedPoints.length - 1; i++) {
      final s = sortedPoints[i];
      final e = sortedPoints[i + 1];
      if (s >= e) continue;
      // 合并所有覆盖 [s, e] 的区间样式
      var flags = TextStyleFlags.none;
      for (final r in ranges) {
        if (r.start <= s && r.end >= e) {
          flags = flags.merge(r.flags);
        }
      }
      atoms.add(TextStyleRange(start: s, end: e, flags: flags));
    }
    return atoms;
  }

  /// 合并相邻且样式相同的区间
  static List<TextStyleRange> _mergeAdjacent(List<TextStyleRange> ranges) {
    if (ranges.isEmpty) return ranges;
    final sorted = List<TextStyleRange>.from(ranges)
      ..sort((a, b) => a.start.compareTo(b.start));
    final result = <TextStyleRange>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      final last = result.last;
      final cur = sorted[i];
      if (last.end == cur.start && last.flags == cur.flags) {
        result[result.length - 1] = TextStyleRange(
          start: last.start,
          end: cur.end,
          flags: last.flags,
        );
      } else {
        result.add(cur);
      }
    }
    return result;
  }

  /// 规范化区间列表（合并相邻、裁剪到文本长度、移除空样式段）
  static List<TextStyleRange> _normalize(
    List<TextStyleRange> ranges,
    int textLength,
  ) {
    return _mergeAdjacent(
      ranges
          .where((r) => !r.flags.isEmpty && r.start < r.end)
          .map((r) => TextStyleRange(
                start: r.start.clamp(0, textLength),
                end: r.end.clamp(0, textLength),
                flags: r.flags,
              ))
          .where((r) => r.start < r.end)
          .toList(),
    );
  }
}
