import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/find_match_highlighter.dart';

/// 文本范围，用于标记对话区域的起止位置
class _TextRange {
  final int start;
  final int end;
  _TextRange(this.start, this.end);
}

/// 对话高亮控制器
///
/// 继承 TextEditingController，覆盖 buildTextSpan 方法，
/// 对文本中中文引号包裹的对话内容应用高亮颜色。
/// 支持的引号对：
/// - 双引号："" （U+201C, U+201D）
/// - 单引号：'' （U+2018, U+2019）
/// - 角引号：「」 （U+300C, U+300D）
class DialogueHighlightController extends TextEditingController {
  DialogueHighlightController({super.text});

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

    // 对话高亮未启用且无查找匹配时，使用默认行为
    if (!dialogueEnabled && !hasFindMatches) {
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

    // 解析对话区域（仅在对话高亮启用时）
    final dialogueRanges =
        dialogueEnabled ? _parseDialogueRanges(text) : <_TextRange>[];

    // 无对话区域且无查找匹配时，使用默认行为
    if (dialogueRanges.isEmpty && !hasFindMatches) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // 获取对话高亮颜色
    final dialogueColor = ColorUtils.getDialogueHighlightColorForTheme(context);
    // 构建对话样式：保留基础样式的所有属性，仅替换颜色
    final dialogueStyle = style?.copyWith(color: dialogueColor) ??
        TextStyle(color: dialogueColor);

    // 构建带对话高亮的 TextSpan 列表
    final spans = <TextSpan>[];
    if (dialogueRanges.isEmpty) {
      // 无对话区域：整段文本作为普通文本
      _addSpansForRange(spans, text, 0, text.length, style, composingStart, composingEnd);
    } else {
      int lastEnd = 0;
      for (final range in dialogueRanges) {
        // 添加对话前的普通文本
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
        // 添加对话文本（使用对话样式）
        _addSpansForRange(
          spans,
          text,
          range.start,
          range.end,
          dialogueStyle,
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
