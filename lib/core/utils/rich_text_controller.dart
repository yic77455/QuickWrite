import 'package:flutter/widgets.dart';
import 'package:quick_write/core/utils/find_match_highlighter.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// 富文本编辑控制器
///
/// 在 [TextEditingController] 基础上增加样式区间支持，
/// 重写 [buildTextSpan] 根据 [styleRanges] 生成带样式的 [TextSpan]。
///
/// 样式区间维护由外部（编辑器）完成，本类只负责渲染。
class RichTextEditingController extends TextEditingController {
  /// 样式区间列表
  ///
  /// 由外部维护并设置，应为不重叠、按 start 排序的规范形式。
  List<TextStyleRange> _styleRanges = const [];

  /// 样式应用器
  ///
  /// 接收基础样式（来自 TextField 的 style）和区间标记位，
  /// 返回叠加样式后的最终 [TextStyle]。
  /// 由外部设置，因为需要访问主题色等上下文信息。
  TextStyle Function(TextStyle baseStyle, TextStyleFlags flags) styleResolver;

  RichTextEditingController({
    required this.styleResolver,
    super.text,
  });

  /// 获取样式区间列表
  List<TextStyleRange> get styleRanges => _styleRanges;

  /// 设置样式区间列表并触发重建
  set styleRanges(List<TextStyleRange> ranges) {
    _styleRanges = ranges;
    notifyListeners();
  }

  /// 查找匹配范围列表（相对于本节点控制器文本的偏移量）
  ///
  /// 由外部（大纲编辑器）设置，用于在节点文本上叠加查找匹配高亮。
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

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final baseStyle = style ?? const TextStyle();
    final hasFindMatches = _findMatches.isNotEmpty;

    // 无样式区间且无查找匹配时，使用默认构建
    if (_styleRanges.isEmpty && !hasFindMatches) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    if (text.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    // 按 start 排序，确保分段顺序正确
    final sortedRanges = List<TextStyleRange>.from(_styleRanges)
      ..sort((a, b) => a.start.compareTo(b.start));

    final children = <TextSpan>[];
    var currentPos = 0;

    for (final range in sortedRanges) {
      // 跳过无效区间
      if (range.start >= range.end || range.flags.isEmpty) continue;

      // 裁剪到文本长度范围内
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(0, text.length);
      if (start >= end) continue;

      // 添加无样式的前导段
      if (currentPos < start) {
        children.add(TextSpan(
          text: text.substring(currentPos, start),
          style: baseStyle,
        ));
      }

      // 添加带样式的段
      children.add(TextSpan(
        text: text.substring(start, end),
        style: styleResolver(baseStyle, range.flags),
      ));
      currentPos = end;
    }

    // 添加尾部无样式段
    if (currentPos < text.length) {
      children.add(TextSpan(
        text: text.substring(currentPos),
        style: baseStyle,
      ));
    }

    // 无有效分段且无查找匹配时，回退到默认构建
    if (children.isEmpty && !hasFindMatches) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // children 为空时（仅有查找匹配），将整段文本作为单一普通段
    if (children.isEmpty) {
      children.add(TextSpan(text: text, style: baseStyle));
    }

    // 叠加查找匹配高亮
    if (hasFindMatches) {
      final highlightedChildren = FindMatchHighlighter.apply(
        spans: children,
        matches: _findMatches,
        currentMatchIndex: _currentMatchIndex,
        matchColor: FindMatchHighlighter.getMatchColor(context),
        currentMatchColor: FindMatchHighlighter.getCurrentMatchColor(context),
      );
      return TextSpan(style: baseStyle, children: highlightedChildren);
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

/// 默认样式解析器：将样式标记位叠加到基础样式
///
/// 处理加粗、斜体、下划线、删除线四种标记：
/// - 加粗/斜体：直接设置 fontWeight/fontStyle
/// - 下划线/删除线：合并到 decoration
/// - 删除线状态下叠加半透明灰色到原文字颜色，保留原色基调
/// - 字体颜色/字底颜色：直接覆盖基础样式的 color/backgroundColor
TextStyle defaultStyleResolver(TextStyle baseStyle, TextStyleFlags flags) {
  var style = baseStyle;
  if (flags.bold) {
    style = style.copyWith(fontWeight: FontWeight.bold);
  }
  if (flags.italic) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  // 文字颜色：优先使用区间标记的字体颜色，其次基础样式颜色
  // 删除线状态下叠加灰色，保留原色基调
  var color = flags.foregroundColor ?? baseStyle.color ?? const Color(0xFF000000);
  if (flags.strikethrough) {
    color = Color.alphaBlend(
      const Color.fromARGB(128, 128, 128, 128),
      color,
    );
  }
  // 装饰：下划线 + 删除线合并
  final decorations = <TextDecoration>[];
  if (flags.underline) decorations.add(TextDecoration.underline);
  if (flags.strikethrough) decorations.add(TextDecoration.lineThrough);
  return style.copyWith(
    color: color,
    backgroundColor: flags.backgroundColor ?? baseStyle.backgroundColor,
    decoration: TextDecoration.combine(decorations),
    decorationColor: color,
  );
}
