import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/workspace/custom_highlight_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/find_match_highlighter.dart';

/// 文本范围，用于标记对话区域的起止位置
class _TextRange {
  final int start;
  final int end;
  _TextRange(this.start, this.end);
}

/// 带颜色与优先级的高亮范围
///
/// 用于统一表示对话高亮与自定义关键词高亮，便于合并重叠区域。
/// [priority] 数值越大优先级越高，重叠时高优先级范围的颜色覆盖低优先级。
class _ColoredRange {
  /// 范围起始偏移（含）
  final int start;

  /// 范围结束偏移（不含）
  final int end;

  /// 该范围使用的高亮颜色
  final Color color;

  /// 优先级（数值越大优先级越高）
  final int priority;

  _ColoredRange(this.start, this.end, this.color, this.priority);
}

/// 文本高亮控制器
///
/// 继承 TextEditingController，覆盖 buildTextSpan 方法，在编辑器中实时渲染以下高亮：
/// - 对话高亮：识别中文引号包裹的对话内容，统一应用对话色
/// - 自定义关键词高亮：按用户配置的关键词列表与颜色逐字匹配并着色
/// - 查找匹配高亮：在上述高亮之上叠加查找/替换的匹配范围
///
/// 当多种高亮范围重叠时，优先级为：查找匹配 > 自定义关键词 > 对话。
///
/// 支持的对话引号对：
/// - 双引号："" （U+201C, U+201D）
/// - 单引号：'' （U+2018, U+2019）
/// - 角引号：「」 （U+300C, U+300D）
class TextHighlightController extends TextEditingController {
  TextHighlightController({super.text, CustomHighlightService? customHighlightService})
      : _customHighlightService = customHighlightService;

  /// 自定义高亮服务（可选）
  ///
  /// 由工作台注入，用于在文本上叠加用户自定义关键词的高亮颜色。
  /// 为 null 时不参与高亮渲染（如备份预览等不依赖书籍配置的场景）。
  final CustomHighlightService? _customHighlightService;

  /// 查找匹配范围列表（相对于控制器文本的偏移量）
  ///
  /// 由外部（编辑器）设置，用于在文本上叠加查找匹配高亮。
  List<TextSelection> _findMatches = const [];

  /// 当前选中匹配在 [_findMatches] 中的索引（-1 表示无选中）
  int _currentMatchIndex = -1;

  /// 设置查找匹配列表
  ///
  /// 不调用 [notifyListeners]，因为此属性通常在父组件的 build 阶段设置，
  /// 父组件重建会带动内部 TextField 重建，从而调用 [buildTextSpan] 读取最新值。
  set findMatches(List<TextSelection> value) {
    _findMatches = value;
  }

  /// 设置当前选中匹配索引
  ///
  /// 不调用 [notifyListeners]，原因同 [findMatches]。
  set currentMatchIndex(int value) {
    _currentMatchIndex = value;
  }

  /// 中文引号对定义
  static const List<(String, String)> _quotePairs = [
    ('\u201C', '\u201D'), // "" 双引号
    ('\u2018', '\u2019'), // '' 单引号
    ('\u300C', '\u300D'), // 「」 角引号
  ];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool withComposing = false,
  }) {
    final hasFindMatches = _findMatches.isNotEmpty;
    final dialogueEnabled = SettingsService.instance.dialogueHighlightEnabled;
    final customHighlightEnabled = _customHighlightService?.enabled ?? false;
    final hasCustomKeywords =
        customHighlightEnabled && _customHighlightService!.items.isNotEmpty;

    // 对话高亮、自定义关键词高亮、查找匹配均未启用时，使用默认行为
    if (!dialogueEnabled && !hasCustomKeywords && !hasFindMatches) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final text = this.text;
    if (text.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    // 获取 composing 区域（IME 输入中的文本范围）
    final composingStart =
        withComposing && value.composing.isValid ? value.composing.start : -1;
    final composingEnd =
        withComposing && value.composing.isValid ? value.composing.end : -1;

    // 收集所有需要着色的范围（对话范围与关键词范围统一为带颜色的范围）
    final coloredRanges = <_ColoredRange>[];

    // 对话范围（priority 0，优先级最低）
    if (dialogueEnabled) {
      final dialogueColor = ColorUtils.getDialogueHighlightColorForTheme(context);
      for (final range in _parseDialogueRanges(text)) {
        coloredRanges.add(_ColoredRange(range.start, range.end, dialogueColor, 0));
      }
    }

    // 自定义关键词范围（priority 1，优先级高于对话，重叠时覆盖对话颜色）
    if (hasCustomKeywords) {
      for (final item in _customHighlightService.items) {
        final keyword = item.keyword;
        if (keyword.isEmpty) continue;
        final color = ColorUtils.parseHex(item.colorHex);
        int searchStart = 0;
        while (searchStart <= text.length - keyword.length) {
          final index = text.indexOf(keyword, searchStart);
          if (index == -1) break;
          coloredRanges.add(_ColoredRange(index, index + keyword.length, color, 1));
          searchStart = index + keyword.length;
        }
      }
    }

    // 无任何高亮范围且无查找匹配时，使用默认行为
    if (coloredRanges.isEmpty && !hasFindMatches) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // 合并范围（处理重叠，高优先级覆盖低优先级）
    final mergedRanges = _mergeColoredRanges(coloredRanges);

    // 构建带高亮的 TextSpan 列表
    final spans = <TextSpan>[];
    if (mergedRanges.isEmpty) {
      // 无高亮范围：整段文本作为普通文本
      _addSpansForRange(spans, text, 0, text.length, style, composingStart, composingEnd);
    } else {
      int lastEnd = 0;
      for (final range in mergedRanges) {
        // 添加高亮范围前的普通文本
        if (range.start > lastEnd) {
          _addSpansForRange(
            spans,
            text,
            lastEnd,
            range.start,
            style,
            composingStart,
            composingEnd,
          );
        }
        // 添加高亮范围文本（保留基础样式属性，仅替换颜色）
        final rangeStyle = style?.copyWith(color: range.color) ?? TextStyle(color: range.color);
        _addSpansForRange(
          spans,
          text,
          range.start,
          range.end,
          rangeStyle,
          composingStart,
          composingEnd,
        );
        lastEnd = range.end;
      }
      // 添加最后的普通文本
      if (lastEnd < text.length) {
        _addSpansForRange(
          spans,
          text,
          lastEnd,
          text.length,
          style,
          composingStart,
          composingEnd,
        );
      }
    }

    // 叠加查找匹配高亮
    if (hasFindMatches) {
      final highlightedSpans = FindMatchHighlighter.apply(
        spans: spans,
        matches: _findMatches,
        currentMatchIndex: _currentMatchIndex,
        matchColor: FindMatchHighlighter.getMatchColor(context),
        currentMatchColor: FindMatchHighlighter.getCurrentMatchColor(context),
      );
      return TextSpan(children: highlightedSpans, style: style);
    }

    return TextSpan(children: spans, style: style);
  }

  /// 为指定范围添加 TextSpan，同时处理 composing 区域的下划线样式
  ///
  /// [spans] 目标列表
  /// [text] 完整文本
  /// [start] 当前片段起始位置
  /// [end] 当前片段结束位置
  /// [baseStyle] 当前片段的基础样式（普通文本或对话文本）
  /// [composingStart] composing 区域起始位置（-1 表示无 composing）
  /// [composingEnd] composing 区域结束位置
  void _addSpansForRange(
    List<TextSpan> spans,
    String text,
    int start,
    int end,
    TextStyle? baseStyle,
    int composingStart,
    int composingEnd,
  ) {
    if (start >= end) return;

    // 无 composing 区域重叠，直接添加
    if (composingStart < 0 ||
        end <= composingStart ||
        start >= composingEnd) {
      spans.add(TextSpan(text: text.substring(start, end), style: baseStyle));
      return;
    }

    // 有重叠，分段处理：前段（composing 之前）
    if (start < composingStart) {
      spans.add(TextSpan(
        text: text.substring(start, composingStart),
        style: baseStyle,
      ));
    }

    // 中段（composing 区域内，添加下划线）
    final cs = start > composingStart ? start : composingStart;
    final ce = end < composingEnd ? end : composingEnd;
    if (cs < ce) {
      spans.add(TextSpan(
        text: text.substring(cs, ce),
        style: baseStyle?.merge(const TextStyle(
          decoration: TextDecoration.underline,
        )),
      ));
    }

    // 后段（composing 之后）
    if (composingEnd < end) {
      spans.add(TextSpan(
        text: text.substring(composingEnd, end),
        style: baseStyle,
      ));
    }
  }

  /// 合并带颜色的范围，处理重叠区域（高优先级覆盖低优先级）
  ///
  /// 使用扫描线算法：以所有范围的边界点为切分点，将文本切成不重叠的小段，
  /// 每段使用覆盖它的最高优先级范围的颜色，颜色相同的连续小段会被合并。
  List<_ColoredRange> _mergeColoredRanges(List<_ColoredRange> input) {
    if (input.isEmpty) return [];

    // 收集所有边界点并排序去重
    final points = <int>{};
    for (final r in input) {
      points.add(r.start);
      points.add(r.end);
    }
    final sortedPoints = points.toList()..sort();

    final result = <_ColoredRange>[];
    for (int i = 0; i < sortedPoints.length - 1; i++) {
      final segStart = sortedPoints[i];
      final segEnd = sortedPoints[i + 1];
      if (segStart >= segEnd) continue;

      // 找出覆盖此段的所有范围中优先级最高的
      _ColoredRange? best;
      for (final r in input) {
        if (r.start <= segStart && r.end >= segEnd) {
          if (best == null || r.priority > best.priority) {
            best = r;
          }
        }
      }

      if (best != null) {
        // 与上一段合并（颜色相同且连续时合并为一段）
        if (result.isNotEmpty &&
            result.last.color == best.color &&
            result.last.end == segStart) {
          result[result.length - 1] =
              _ColoredRange(result.last.start, segEnd, best.color, best.priority);
        } else {
          result.add(_ColoredRange(segStart, segEnd, best.color, best.priority));
        }
      }
    }

    return result;
  }

  /// 解析文本中的对话区域
  ///
  /// 遍历所有引号对，找出匹配的起止位置，
  /// 结果按起始位置排序并合并重叠区域
  List<_TextRange> _parseDialogueRanges(String text) {
    final ranges = <_TextRange>[];

    for (final pair in _quotePairs) {
      int searchStart = 0;
      while (searchStart < text.length) {
        final openIndex = text.indexOf(pair.$1, searchStart);
        if (openIndex == -1) break;

        final closeIndex = text.indexOf(pair.$2, openIndex + 1);
        if (closeIndex == -1) {
          // 未找到匹配的右引号，跳过
          searchStart = openIndex + 1;
          continue;
        }

        ranges.add(_TextRange(openIndex, closeIndex + 1));
        searchStart = closeIndex + 1;
      }
    }

    // 按起始位置排序
    ranges.sort((a, b) => a.start.compareTo(b.start));

    // 合并重叠区域
    final mergedRanges = <_TextRange>[];
    for (final range in ranges) {
      if (mergedRanges.isEmpty || mergedRanges.last.end < range.start) {
        mergedRanges.add(range);
      } else {
        // 重叠时扩展前一个区域的结束位置
        mergedRanges[mergedRanges.length - 1] = _TextRange(
          mergedRanges.last.start,
          range.end > mergedRanges.last.end ? range.end : mergedRanges.last.end,
        );
      }
    }

    return mergedRanges;
  }
}
