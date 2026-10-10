import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/workspace/custom_highlight_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/find_match_highlighter.dart';
import 'package:quick_write/core/utils/highlight_range_resolver.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor 行样式构建器
///
/// 作为编辑器的 [CodeLineSpanBuilder] 注入，在每一行渲染前生成 TextSpan：
/// - 注入排版设置：CodeEditorStyle 提供字体、字号、行高、字间距与文字颜色，
///   加粗、斜体、下划线需要在此叠加到基础样式上
/// - 注入高亮：对话高亮、自定义关键词高亮、查找匹配高亮统一解析为带优先级的范围后着色
///
/// 范围解析在全文层面完成并缓存（含每行起始偏移），逐行渲染时按行切片，
/// 避免对全文重复解析。文本、高亮配置或查找匹配变化后需调用 [update] 刷新缓存。
class ReEditorSpanBuilder {
  ReEditorSpanBuilder({this.customHighlightService});

  /// 自定义关键词高亮服务（为 null 时不参与着色）
  final CustomHighlightService? customHighlightService;

  /// 查找匹配范围（相对于全文的扁平偏移量）
  List<TextSelection> findMatches = const [];

  /// 当前选中匹配在 [findMatches] 中的索引（-1 表示无选中）
  int currentMatchIndex = -1;

  /// 缓存：上一次参与解析的文本
  String _text = '';

  /// 缓存：上一次参与解析的配置指纹
  String _configSignature = '';

  /// 缓存：按优先级合并后的全文高亮范围（按起始偏移升序）
  List<HighlightRange> _ranges = const [];

  /// 缓存：每一行在全文中的起始偏移量
  List<int> _lineStarts = const [];

  /// 根据当前文本与高亮配置刷新缓存
  ///
  /// 文本与配置均未变化时直接复用缓存，避免逐帧重复解析。
  void update({required BuildContext context, required String text}) {
    final String signature = _configSignatureOf();
    if (text == _text && signature == _configSignature) return;
    _text = text;
    _configSignature = signature;
    _lineStarts = HighlightRangeResolver.lineStarts(text);
    _ranges = _resolveRanges(context, text);
  }

  /// 构建单行的 TextSpan，供 re_editor 逐行调用
  TextSpan call({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextStyle style,
    required TextSpan textSpan,
  }) {
    final SettingsService settings = SettingsService.instance;
    // 叠加编辑器的排版设置（CodeEditorStyle 未覆盖的部分）
    final TextStyle baseStyle = style.copyWith(
      fontFamily: settings.fontFamily,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      fontWeight: settings.isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: settings.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: settings.isUnderline ? TextDecoration.underline : TextDecoration.none,
    );

    final String lineText = codeLine.text;
    final List<HighlightRange> lineRanges = _rangesForLine(index, lineText.length);
    if (lineRanges.isEmpty) return TextSpan(text: lineText, style: baseStyle);

    // 将全文范围换算为行内范围后按边界切片着色
    final int lineStart = _lineStarts[index];
    final List<InlineSpan> spans = [];
    int cursor = 0;
    for (final HighlightRange range in lineRanges) {
      final int start = (range.start - lineStart).clamp(cursor, lineText.length);
      final int end = (range.end - lineStart).clamp(start, lineText.length);
      if (start > cursor) {
        spans.add(TextSpan(text: lineText.substring(cursor, start), style: baseStyle));
      }
      if (end > start) {
        spans.add(TextSpan(
          text: lineText.substring(start, end),
          style: baseStyle.copyWith(color: range.color),
        ));
      }
      cursor = end;
    }
    if (cursor < lineText.length) {
      spans.add(TextSpan(text: lineText.substring(cursor), style: baseStyle));
    }
    return TextSpan(children: spans, style: baseStyle);
  }

  /// 解析全文高亮范围并按优先级合并
  List<HighlightRange> _resolveRanges(BuildContext context, String text) {
    final SettingsService settings = SettingsService.instance;
    final List<HighlightRange> ranges = [];

    // 对话高亮
    if (settings.dialogueHighlightEnabled) {
      ranges.addAll(HighlightRangeResolver.parseDialogueRanges(
        text,
        ColorUtils.getDialogueHighlightColorForTheme(context),
      ));
    }

    // 自定义关键词高亮
    final CustomHighlightService? service = customHighlightService;
    if (service != null && service.enabled) {
      for (final item in service.items) {
        ranges.addAll(HighlightRangeResolver.parseKeywordRanges(
          text,
          item.keyword,
          ColorUtils.parseHex(item.colorHex),
        ));
      }
    }

    // 查找匹配高亮
    if (findMatches.isNotEmpty) {
      ranges.addAll(HighlightRangeResolver.parseFindMatchRanges(
        findMatches,
        currentMatchIndex,
        FindMatchHighlighter.getMatchColor(context),
        FindMatchHighlighter.getCurrentMatchColor(context),
      ));
    }

    return HighlightRangeResolver.mergeRanges(ranges);
  }

  /// 取指定行内涉及的高亮范围（返回全文偏移，由调用方换算行内偏移）
  List<HighlightRange> _rangesForLine(int index, int lineLength) {
    if (_lineStarts.isEmpty || index < 0 || index >= _lineStarts.length) return const [];
    final int lineStart = _lineStarts[index];
    final int lineEnd = lineStart + lineLength;
    final List<HighlightRange> result = [];
    int i = HighlightRangeResolver.firstOverlappingIndex(_ranges, lineStart);
    while (i < _ranges.length && _ranges[i].start < lineEnd) {
      result.add(_ranges[i]);
      i++;
    }
    return result;
  }

  /// 生成高亮配置指纹，用于判断是否需要重新解析
  String _configSignatureOf() {
    final SettingsService settings = SettingsService.instance;
    final StringBuffer buffer = StringBuffer()
      ..write(settings.dialogueHighlightEnabled)
      ..write('|')
      ..write(currentMatchIndex)
      ..write('|')
      ..write(findMatches.length);

    final CustomHighlightService? service = customHighlightService;
    if (service != null && service.enabled) {
      for (final item in service.items) {
        buffer
          ..write('|')
          ..write(item.keyword)
          ..write(':')
          ..write(item.colorHex);
      }
    }
    return buffer.toString();
  }
}