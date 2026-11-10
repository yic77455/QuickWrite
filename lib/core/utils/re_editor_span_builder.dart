import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/workspace/custom_highlight_service.dart';
import 'package:quick_write/core/services/workspace/outline_keyword_service.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/find_match_highlighter.dart';
import 'package:quick_write/core/utils/highlight_range_resolver.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor 行样式构建器
///
/// 作为编辑器的 [CodeLineSpanBuilder] 注入，在每一行渲染前生成 TextSpan：
/// - 注入排版设置：CodeEditorStyle 提供字体、字号、行高、字间距与文字颜色，
///   加粗、斜体、下划线需要在此叠加到基础样式上
/// - 注入高亮：对话高亮、自定义关键词高亮、大纲关键词高亮、查找匹配高亮
///   统一解析为带优先级的范围后着色
///
/// 范围解析在全文层面完成并缓存（含每行起始偏移），逐行渲染时按行切片，
/// 避免对全文重复解析。文本、高亮配置或查找匹配变化后需调用 [update] 刷新缓存。
class ReEditorSpanBuilder {
  ReEditorSpanBuilder({this.customHighlightService, this.outlineKeywordService});

  /// 自定义关键词高亮服务（为 null 时不参与着色）
  final CustomHighlightService? customHighlightService;

  /// 大纲关键词服务（为 null 时不参与着色）
  final OutlineKeywordService? outlineKeywordService;

  /// 关键词修饰键是否按住（Windows/Linux 为 Ctrl，macOS 为 Command）
  ///
  /// 仅按下时解析大纲关键词范围并叠加高亮与悬停注解。
  bool ctrlPressed = false;

  /// 大纲关键词悬停进入回调（参数为关键词文本与命中的全局矩形）
  void Function(String keyword, List<Rect> rects)? onKeywordHover;

  /// 大纲关键词悬停离开回调
  void Function(String keyword)? onKeywordHoverExit;

  /// 查找匹配范围（相对于全文的扁平偏移量）
  List<TextSelection> findMatches = const [];

  /// 当前选中匹配在 [findMatches] 中的索引（-1 表示无选中）
  int currentMatchIndex = -1;

  /// 缓存：上一次参与解析的文本
  String _text = '';

  /// 缓存：上一次参与解析的配置指纹
  String _configSignature = '';

  /// 行首空白（含首行缩进的全角空格）匹配式
  static final RegExp _leadingWhitespace = RegExp(r'^[\u3000\s]+');

  /// 缓存：按优先级合并后的全文高亮范围（按起始偏移升序）
  List<HighlightRange> _ranges = const [];

  /// 缓存：大纲关键词命中区间（未与其他关键词重叠，供悬停注解识别关键词）
  List<({int start, int end, String keyword})> _outlineSegments = const [];

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
    // 行首缩进等空白不属于正文内容，下划线不绘制在其下方
    final int indentLength = settings.isUnderline ? _leadingWhitespaceLength(lineText) : 0;
    final List<HighlightRange> lineRanges = _rangesForLine(index, lineText.length);
    if (lineRanges.isEmpty && indentLength == 0) {
      return TextSpan(text: lineText, style: baseStyle);
    }
    final TextStyle plainStyle =
        indentLength > 0 ? baseStyle.copyWith(decoration: TextDecoration.none) : baseStyle;

    final List<InlineSpan> spans = [];
    int cursor = 0;
    // 先按无下划线样式补出行首缩进空白
    if (indentLength > 0) {
      spans.add(TextSpan(text: lineText.substring(0, indentLength), style: plainStyle));
      cursor = indentLength;
    }

    // 将全文范围换算为行内范围后按边界切片着色
    final int lineStart = _lineStarts[index];
    for (final HighlightRange range in lineRanges) {
      final int start = (range.start - lineStart).clamp(cursor, lineText.length);
      final int end = (range.end - lineStart).clamp(start, lineText.length);
      if (start > cursor) {
        spans.add(TextSpan(text: lineText.substring(cursor, start), style: baseStyle));
      }
      if (end > start) {
        // 查找匹配以文字底色标识，其余高亮覆盖文字颜色并可按范围叠加字重
        final TextStyle highlightStyle = range.background
            ? baseStyle.copyWith(backgroundColor: range.color)
            : baseStyle.copyWith(color: range.color, fontWeight: _resolveFontWeight(baseStyle, range.fontWeight));
        final String? keyword = _outlineKeywordFor(range.start, range.end);
        if (keyword != null && onKeywordHover != null) {
          // 大纲关键词命中段包成悬停注解，指针进入时由 re_editor 回调
          spans.add(MouseTrackerAnnotationTextSpan(
            text: lineText.substring(start, end),
            style: highlightStyle,
            mouseCursor: SystemMouseCursors.click,
            onEnterWithRect: (event, id, rects) => onKeywordHover?.call(keyword, rects),
            onExitWithRect: (event, id, rects) => onKeywordHoverExit?.call(keyword),
          ));
        } else {
          spans.add(TextSpan(
            text: lineText.substring(start, end),
            style: highlightStyle,
          ));
        }
      }
      cursor = end;
    }
    if (cursor < lineText.length) {
      spans.add(TextSpan(text: lineText.substring(cursor), style: baseStyle));
    }
    return TextSpan(children: spans, style: baseStyle);
  }

  /// 计算行首连续空白字符的数量（首行缩进等）
  int _leadingWhitespaceLength(String text) => _leadingWhitespace.matchAsPrefix(text)?.end ?? 0;

  /// 解析高亮范围的字重
  ///
  /// 范围自带字重时取基础字重与范围字重中更粗的一个，
  /// 避免把用户设置的加粗文本反而改细。
  FontWeight? _resolveFontWeight(TextStyle baseStyle, FontWeight? rangeWeight) {
    if (rangeWeight == null) return null;
    final FontWeight baseWeight = baseStyle.fontWeight ?? FontWeight.normal;
    return baseWeight.value > rangeWeight.value ? baseWeight : rangeWeight;
  }

  /// 查找覆盖指定全文区间的大纲关键词
  ///
  /// 命中区间互不重叠，合并后的着色段必然完整落在某一个关键词区间内。
  String? _outlineKeywordFor(int start, int end) {
    for (final segment in _outlineSegments) {
      if (segment.start <= start && segment.end >= end) return segment.keyword;
    }
    return null;
  }

  /// 查找覆盖指定全文偏移的大纲关键词
  ///
  /// 供移动端点按关键词时定位命中词，需在关键词高亮开启后调用。
  String? outlineKeywordAt(int offset) {
    for (final segment in _outlineSegments) {
      if (segment.start <= offset && offset < segment.end) return segment.keyword;
    }
    return null;
  }

  /// 解析全文高亮范围并按优先级合并
  List<HighlightRange> _resolveRanges(BuildContext context, String text) {
    final SettingsService settings = SettingsService.instance;
    final List<HighlightRange> ranges = [];
    _outlineSegments = const [];

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

    // 大纲关键词高亮（仅按住关键词修饰键时参与，优先级高于对话与自定义高亮）
    if (ctrlPressed) {
      final OutlineKeywordService? keywordService = outlineKeywordService;
      if (keywordService != null) {
        _addOutlineKeywordRanges(text, keywordService, ranges);
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

  /// 解析大纲关键词在文本中的命中范围
  ///
  /// 关键词按长度降序匹配，长词优先；已被占用的区间不再重复着色，
  /// 命中区间同时记录关键词文本，供悬停注解识别具体词条。
  void _addOutlineKeywordRanges(String text, OutlineKeywordService service, List<HighlightRange> ranges) {
    final List<String> keywords = service.keywords.toList()..sort((a, b) => b.length.compareTo(a.length));
    final List<({int start, int end, String keyword})> accepted = [];

    for (final keyword in keywords) {
      final OutlineKeywordEntry? entry = service.entryForKeyword(keyword);
      if (entry == null) continue;
      OutlineKeyword? binding;
      for (final item in entry.keywords) {
        if (item.keyword == keyword) {
          binding = item;
          break;
        }
      }
      if (binding == null) continue;

      final List<HighlightRange> matches = HighlightRangeResolver.parseKeywordRanges(
        text,
        keyword,
        binding.color,
        priority: HighlightRangeResolver.outlineKeywordPriority,
      );
      for (final match in matches) {
        // 与已接受的关键词区间重叠时跳过，保证长词优先且区间互不重叠
        final bool overlapped = accepted.any((segment) => match.start < segment.end && match.end > segment.start);
        if (overlapped) continue;
        accepted.add((start: match.start, end: match.end, keyword: keyword));
        ranges.add(HighlightRange(
          match.start,
          match.end,
          binding.color,
          HighlightRangeResolver.outlineKeywordPriority,
          fontWeight: FontWeight.w500,
        ));
      }
    }

    _outlineSegments = accepted;
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

    // 关键词修饰键状态决定是否参与大纲关键词高亮；按住时还需纳入关键词索引版本
    buffer
      ..write('|')
      ..write(ctrlPressed);
    if (ctrlPressed) {
      buffer
        ..write('|')
        ..write(outlineKeywordService?.revision ?? -1);
    }

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