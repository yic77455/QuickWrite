import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Color;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// 剪贴板 HTML 解析得到的临时节点
///
/// 不包含节点 ID，由大纲编辑器创建真实节点时生成。
class ParsedOutlineNode {
  ParsedOutlineNode({
    required this.text,
    this.headingLevel = 0,
    List<TextStyleRange>? styleRanges,
    List<ParsedOutlineNode>? children,
  }) : styleRanges = styleRanges ?? [],
       children = children ?? [];

  /// 节点纯文本
  final String text;

  /// 标题级别（0=正文, 1=H1, 2=H2, 3=H3）
  final int headingLevel;

  /// 文字样式区间
  final List<TextStyleRange> styleRanges;

  /// 子节点列表
  final List<ParsedOutlineNode> children;
}

/// 大纲富文本 HTML 编解码
///
/// 负责在大纲节点与 HTML 之间转换，供剪贴板富文本复制粘贴使用：
/// - 导出：层级转为嵌套 `<ul><li>`，标题转为 `<h1>`~`<h3>`，
///   文字样式转为带 CSS 的 `<span>`。
/// - 导入：从 HTML 中还原纯文本、标题级别、样式区间与列表层级。
class OutlineHtmlCodec {
  OutlineHtmlCodec._();

  // ================= 导出 =================

  /// 将扁平节点列表序列化为 HTML 片段
  ///
  /// [nodes] 需按文档顺序排列，深度通过嵌套列表表达。
  static String serializeNodes(List<FlatNode> nodes) {
    if (nodes.isEmpty) return '';

    final roots = <_HtmlEntry>[];
    // 栈记录已序列化节点及其原始深度，用于还原选中范围内的相对层级
    final stack = <(_HtmlEntry, int)>[];

    for (final flat in nodes) {
      final entry = _HtmlEntry(
        serializeInline(
          flat.node.text,
          flat.node.styleRanges,
          headingLevel: flat.node.headingLevel,
        ),
      );
      while (stack.isNotEmpty && stack.last.$2 >= flat.depth) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(entry);
      } else {
        stack.last.$1.children.add(entry);
      }
      stack.add((entry, flat.depth));
    }

    return _writeList(roots);
  }

  /// 将文本片段序列化为内联 HTML
  ///
  /// [ranges] 中的样式区间以 [text] 起点为 0 计算位置；
  /// [headingLevel] 大于 0 时用对应标题标签包裹。
  static String serializeInline(
    String text,
    List<TextStyleRange> ranges, {
    int headingLevel = 0,
  }) {
    final buffer = StringBuffer();
    // 按起点排序，保证片段按文本顺序输出
    final sortedRanges = List<TextStyleRange>.from(ranges)
      ..sort((a, b) => a.start.compareTo(b.start));

    var currentPos = 0;
    for (final range in sortedRanges) {
      if (range.flags.isEmpty) continue;
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(0, text.length);
      // 跳过空区间及与前段重叠的区间（样式区间应为不重叠形式）
      if (start >= end || start < currentPos) continue;

      if (currentPos < start) {
        buffer.write(_escapeHtml(text.substring(currentPos, start)));
      }
      final segment = _escapeHtml(text.substring(start, end));
      final css = _buildCss(range.flags);
      if (css.isEmpty) {
        buffer.write(segment);
      } else {
        buffer.write('<span style="$css">$segment</span>');
      }
      currentPos = end;
    }

    if (currentPos < text.length) {
      buffer.write(_escapeHtml(text.substring(currentPos)));
    }

    final content = buffer.toString();
    if (headingLevel >= 1 && headingLevel <= 3) {
      return '<h$headingLevel>$content</h$headingLevel>';
    }
    return content;
  }

  /// 将嵌套节点写成 `<ul><li>` 结构
  static String _writeList(List<_HtmlEntry> entries) {
    final buffer = StringBuffer('<ul>');
    for (final entry in entries) {
      buffer.write('<li>');
      buffer.write(entry.content);
      if (entry.children.isNotEmpty) {
        buffer.write(_writeList(entry.children));
      }
      buffer.write('</li>');
    }
    buffer.write('</ul>');
    return buffer.toString();
  }

  /// 将样式标记位转换为 CSS 声明
  static String _buildCss(TextStyleFlags flags) {
    final declarations = <String>[];
    if (flags.bold) declarations.add('font-weight:bold');
    if (flags.italic) declarations.add('font-style:italic');

    final decorations = <String>[];
    if (flags.underline) decorations.add('underline');
    if (flags.strikethrough) decorations.add('line-through');
    if (decorations.isNotEmpty) {
      declarations.add('text-decoration:${decorations.join(' ')}');
    }

    if (flags.foregroundColor != null) {
      declarations.add('color:${ColorUtils.toHex(flags.foregroundColor!)}');
    }
    if (flags.backgroundColor != null) {
      declarations.add(
        'background-color:${ColorUtils.toHex(flags.backgroundColor!)}',
      );
    }
    return declarations.join(';');
  }

  /// 转义 HTML 特殊字符，并把连续空格转换为不换行空格以避免被压缩
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')
        .replaceAllMapped(
          RegExp(r'  +'),
          (match) => ' ${'\u00A0' * (match.group(0)!.length - 1)}',
        );
  }

  // ================= 导入 =================

  /// 将 HTML 解析为节点列表
  ///
  /// 支持段落、标题、嵌套列表以及常见的内联样式；
  /// 层级深度不超过 [maxDepth]，空白块会被忽略。
  static List<ParsedOutlineNode> parseHtml(String html, {int maxDepth = 20}) {
    final document = html_parser.parse(html);
    return _HtmlOutlineParser(maxDepth).parse(document);
  }
}

/// 导出阶段使用的临时 HTML 条目
class _HtmlEntry {
  _HtmlEntry(this.content);

  /// 节点内容 HTML
  final String content;

  /// 子条目
  final List<_HtmlEntry> children = [];
}

/// HTML 转节点解析器
///
/// 按文档顺序累积块内文本，并在块结束时根据嵌套深度建立父子关系。
class _HtmlOutlineParser {
  _HtmlOutlineParser(this.maxDepth);

  /// 允许的最大层级深度
  final int maxDepth;

  /// 解析得到的根节点列表
  final List<ParsedOutlineNode> roots = [];

  /// 已落地节点及其深度的栈，用于建立父子关系
  final List<(ParsedOutlineNode, int)> _stack = [];

  /// 当前块内累积的文本
  final StringBuffer _buffer = StringBuffer();

  /// 当前块内累积的样式区间
  final List<TextStyleRange> _ranges = [];

  /// 当前块的深度
  int _blockDepth = 0;

  /// 当前块的标题级别
  int _headingLevel = 0;

  /// 从 `data-json` 中解析出的文本片段样式（按文本顺序排列）
  final List<({String text, TextStyleFlags flags})> _jsonSegments = [];

  /// 当前已对齐到的 JSON 片段下标
  int _jsonIndex = 0;

  /// 不参与正文解析的元素
  static const Set<String> _ignoredTags = {
    'head',
    'style',
    'script',
    'meta',
    'title',
    'link',
  };

  /// 解析文档并返回节点列表
  List<ParsedOutlineNode> parse(dom.Document document) {
    // 部分编辑器（如幕布）把完整样式写在 data-json 中，优先读取
    _loadJsonSegments(document);

    final body = document.body;
    if (body != null) {
      _walk(body, 0, TextStyleFlags.none);
    } else {
      for (final node in document.nodes) {
        _walk(node, 0, TextStyleFlags.none);
      }
    }
    // 落地文档末尾没有块包裹的文本
    _flush(_blockDepth);
    return roots;
  }

  /// 遍历节点，块级元素单独落地，内联元素继承样式
  void _walk(dom.Node node, int depth, TextStyleFlags inherited) {
    if (node is dom.Text) {
      _append(node.text, inherited);
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName?.toLowerCase() ?? '';
    if (_ignoredTags.contains(tag)) return;

    final style = inherited.merge(_elementStyle(node, tag));

    if (tag == 'br') {
      _flush(depth);
      return;
    }

    if (tag == 'ul' || tag == 'ol') {
      _flush(depth);
      for (final child in node.nodes) {
        _walk(child, depth, style);
      }
      return;
    }

    if (tag == 'li' || tag == 'p' || tag == 'div' || _isHeading(tag)) {
      _walkBlock(node, depth, style, _headingLevelOf(tag));
      return;
    }

    // 内联元素：继承样式继续向内遍历
    for (final child in node.nodes) {
      _walk(child, depth, style);
    }
  }

  /// 处理一个块级元素
  ///
  /// 块内嵌套的列表会先落地当前文字，再作为当前节点的子节点处理。
  void _walkBlock(
    dom.Element block,
    int depth,
    TextStyleFlags style,
    int headingLevel,
  ) {
    final blockDepth = math.min(depth, maxDepth);
    _flush(blockDepth);

    final previousDepth = _blockDepth;
    final previousHeading = _headingLevel;
    _blockDepth = blockDepth;
    _headingLevel = headingLevel;

    for (final child in block.nodes) {
      if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        if (_ignoredTags.contains(tag)) continue;

        if (tag == 'ul' || tag == 'ol') {
          _flush(blockDepth);
          // 嵌套列表的条目作为当前块的子节点
          _walk(child, blockDepth + 1, style.merge(_elementStyle(child, tag)));
          continue;
        }
        if (tag == 'p' || tag == 'div' || _isHeading(tag)) {
          _walkBlock(
            child,
            blockDepth,
            style.merge(_elementStyle(child, tag)),
            _headingLevelOf(tag),
          );
          continue;
        }
        if (tag == 'br') {
          _flush(blockDepth);
          continue;
        }
      }
      _walk(child, blockDepth, style);
    }

    _flush(blockDepth);
    _blockDepth = previousDepth;
    _headingLevel = previousHeading;
  }

  /// 累积文本及其样式
  void _append(String raw, TextStyleFlags style) {
    // 折叠 HTML 源码中的换行与连续空白
    final text = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return;

    // 与 data-json 片段按文本顺序对齐时，采用其中的精确样式
    final TextStyleFlags effectiveStyle = _matchJsonStyle(text, style);

    final start = _buffer.length;
    _buffer.write(text);
    if (!effectiveStyle.isEmpty) {
      _ranges.add(
        TextStyleRange(
          start: start,
          end: start + text.length,
          flags: effectiveStyle,
        ),
      );
    }
  }

  /// 将当前文本块与 data-json 片段对齐并合并样式
  ///
  /// 对齐成功时使用其中的样式；同时保留 HTML 标签/类名解析出的样式作为兜底。
  TextStyleFlags _matchJsonStyle(String text, TextStyleFlags style) {
    if (_jsonIndex >= _jsonSegments.length) return style;

    if (_jsonSegments[_jsonIndex].text == text) {
      final flags = style.merge(_jsonSegments[_jsonIndex].flags);
      _jsonIndex++;
      return flags;
    }

    // 空白文本不参与对齐，避免影响后续片段的匹配
    if (text.trim().isEmpty) return style;

    // 文本切分与 JSON 片段不一致时，尝试在后续片段中重新定位
    for (var i = _jsonIndex; i < _jsonSegments.length; i++) {
      if (_jsonSegments[i].text == text) {
        final flags = style.merge(_jsonSegments[i].flags);
        _jsonIndex = i + 1;
        return flags;
      }
    }
    return style;
  }

  /// 读取 data-json 中的文本片段样式
  ///
  /// 幕布等编辑器把完整样式写在 `data-json` 属性中，HTML 类名只是简化表达；
  /// 数据格式不符合预期时忽略，退回按 HTML 解析。
  void _loadJsonSegments(dom.Document document) {
    final dom.Element? element = document.querySelector('.mm-editor-clipboard');
    final String? payload = element?.attributes['data-json'];
    if (payload == null || payload.isEmpty) return;

    try {
      final dynamic decoded = jsonDecode(Uri.decodeComponent(payload));
      if (decoded is! Map) return;

      final dynamic data = decoded['data'];
      if (data is! List) return;

      for (final dynamic item in data) {
        if (item is! Map) continue;
        final dynamic text = item['text'];
        if (text is! String || text.isEmpty) continue;

        final dynamic style = item['style'];
        _jsonSegments.add((
          text: text,
          flags: style is Map ? _jsonStyleFlags(style) : TextStyleFlags.none,
        ));
      }
    } catch (_) {
      _jsonSegments.clear();
    }
  }

  /// 将 data-json 中的样式映射转换为样式标记
  static TextStyleFlags _jsonStyleFlags(Map<dynamic, dynamic> style) {
    var flags = TextStyleFlags.none;
    if (style['bold'] == true) flags = flags.copyWith(bold: true);
    if (style['italic'] == true) flags = flags.copyWith(italic: true);
    if (style['underline'] == true) flags = flags.copyWith(underline: true);
    if (style['strikethrough'] == true ||
        style['strike'] == true ||
        style['lineThrough'] == true) {
      flags = flags.copyWith(strikethrough: true);
    }

    final dynamic color = style['color'];
    if (color is String) {
      final Color? parsed = _parseCssColor(color);
      if (parsed != null) flags = flags.copyWith(foregroundColor: parsed);
    }

    final dynamic background = style['backgroundColor'] ?? style['background'];
    if (background is String) {
      final Color? parsed = _parseCssColor(background);
      if (parsed != null) flags = flags.copyWith(backgroundColor: parsed);
    }
    return flags;
  }

  /// 落地当前块：去除首尾空白后按深度插入节点树
  void _flush(int depth) {
    final raw = _buffer.toString();
    final rawRanges = List<TextStyleRange>.of(_ranges);
    _buffer.clear();
    _ranges.clear();
    if (raw.isEmpty) return;

    var start = 0;
    var end = raw.length;
    while (start < end && _isWhitespace(raw.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isWhitespace(raw.codeUnitAt(end - 1))) {
      end--;
    }
    if (start >= end) return;

    final node = ParsedOutlineNode(
      text: raw.substring(start, end),
      headingLevel: _headingLevel,
      styleRanges: TextStyleRangeUtils.slice(rawRanges, start, end),
    );
    _attach(node, math.min(depth, maxDepth));
  }

  /// 按深度把节点挂到最近的祖先上
  void _attach(ParsedOutlineNode node, int depth) {
    while (_stack.isNotEmpty && _stack.last.$2 >= depth) {
      _stack.removeLast();
    }
    if (_stack.isEmpty) {
      roots.add(node);
    } else {
      _stack.last.$1.children.add(node);
    }
    _stack.add((node, depth));
  }

  /// 提取元素自身的样式（标签语义 + 内联 CSS）
  TextStyleFlags _elementStyle(dom.Element element, String tag) {
    var flags = TextStyleFlags.none;

    switch (tag) {
      case 'b':
      case 'strong':
        flags = flags.copyWith(bold: true);
        break;
      case 'i':
      case 'em':
        flags = flags.copyWith(italic: true);
        break;
      case 'u':
      case 'ins':
        flags = flags.copyWith(underline: true);
        break;
      case 's':
      case 'strike':
      case 'del':
        flags = flags.copyWith(strikethrough: true);
        break;
    }

    final styleAttribute = element.attributes['style'];
    if (styleAttribute != null && styleAttribute.isNotEmpty) {
      flags = flags.merge(_parseCss(styleAttribute));
    }

    // 部分编辑器（如幕布）不用内联 CSS，而是把样式写成语义类名
    final classAttribute = element.attributes['class'];
    if (classAttribute != null && classAttribute.isNotEmpty) {
      flags = flags.merge(_parseClassStyles(classAttribute));
    }

    // 兼容 <font color="..."> 这类旧式标签
    final colorAttribute = element.attributes['color'];
    if (colorAttribute != null) {
      final color = _parseCssColor(colorAttribute);
      if (color != null) flags = flags.copyWith(foregroundColor: color);
    }

    return flags;
  }

  /// 解析类名中表达的样式
  ///
  /// 支持 `bold`、`italic`、`underline`、`strikethrough` 等语义类名，
  /// 以及 `text-color-blue`、`bg-color-yellow` 这类带颜色名的类名。
  TextStyleFlags _parseClassStyles(String classAttribute) {
    var flags = TextStyleFlags.none;
    for (final rawToken in classAttribute.split(RegExp(r'\s+'))) {
      final token = rawToken.trim().toLowerCase();
      if (token.isEmpty) continue;

      if (token == 'bold' || token == 'font-bold') {
        flags = flags.copyWith(bold: true);
        continue;
      }
      if (token == 'italic' || token == 'font-italic') {
        flags = flags.copyWith(italic: true);
        continue;
      }
      if (token == 'underline') {
        flags = flags.copyWith(underline: true);
        continue;
      }
      if (token == 'strikethrough' ||
          token == 'strike' ||
          token == 'line-through') {
        flags = flags.copyWith(strikethrough: true);
        continue;
      }

      final String? foregroundName = _extractColorName(token, const [
        'text-color-',
        'color-',
      ]);
      if (foregroundName != null) {
        final Color? color = _colorFromName(foregroundName);
        if (color != null && !_isDefaultBlack(color)) {
          flags = flags.copyWith(foregroundColor: color);
        }
        continue;
      }

      final String? backgroundName = _extractColorName(token, const [
        'bg-color-',
        'background-color-',
        'text-bg-',
        'bg-',
      ]);
      if (backgroundName != null) {
        final Color? color = _colorFromName(backgroundName);
        if (color != null) {
          flags = flags.copyWith(backgroundColor: color);
        }
      }
    }
    return flags;
  }

  /// 从类名中剥离颜色前缀，返回颜色名
  static String? _extractColorName(String token, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (token.startsWith(prefix)) return token.substring(prefix.length);
    }
    return null;
  }

  /// 将颜色名转换为颜色，支持 `light-blue` 这类连字符写法
  static Color? _colorFromName(String name) =>
      _namedColors[name.replaceAll('-', '')];

  /// 解析内联 CSS 声明
  TextStyleFlags _parseCss(String css) {
    var flags = TextStyleFlags.none;
    for (final declaration in css.split(';')) {
      final index = declaration.indexOf(':');
      if (index <= 0) continue;

      final property = declaration.substring(0, index).trim().toLowerCase();
      final value = declaration.substring(index + 1).trim().toLowerCase();

      switch (property) {
        case 'font-weight':
          final weight = int.tryParse(value);
          if (value == 'bold' ||
              value == 'bolder' ||
              (weight != null && weight >= 600)) {
            flags = flags.copyWith(bold: true);
          }
          break;
        case 'font-style':
          if (value == 'italic' || value == 'oblique') {
            flags = flags.copyWith(italic: true);
          }
          break;
        case 'text-decoration':
        case 'text-decoration-line':
          if (value.contains('underline')) {
            flags = flags.copyWith(underline: true);
          }
          if (value.contains('line-through')) {
            flags = flags.copyWith(strikethrough: true);
          }
          break;
        case 'color':
          final color = _parseCssColor(value);
          if (color != null) flags = flags.copyWith(foregroundColor: color);
          break;
        case 'background-color':
        case 'background':
          final color = _parseCssColor(value);
          if (color != null) flags = flags.copyWith(backgroundColor: color);
          break;
      }
    }
    return flags;
  }

  /// 解析 CSS 颜色值
  ///
  /// 支持 `#RGB`、`#RRGGBB`、`#RRGGBBAA`、`rgb()`、`rgba()` 与常见颜色名；
  /// 纯黑视为默认文字色，返回 null 以使用主题默认颜色。
  static Color? _parseCssColor(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    if (const {
      'transparent',
      'inherit',
      'initial',
      'unset',
      'currentcolor',
      'windowtext',
      'none',
    }.contains(value)) {
      return null;
    }

    Color? color;
    if (value.startsWith('#')) {
      color = _parseHexColor(value.substring(1));
    } else {
      final rgbMatch = RegExp(r'^rgba?\((.+)\)$').firstMatch(value);
      if (rgbMatch != null) {
        color = _parseRgbChannels(rgbMatch.group(1)!);
      }
    }
    color ??= _namedColors[value];

    // 忽略纯黑，避免外部文本在深色主题下不可见
    if (color != null && _isDefaultBlack(color)) return null;
    return color;
  }

  /// 判断颜色是否为纯黑（视为默认文字色）
  static bool _isDefaultBlack(Color color) =>
      color.r == 0 && color.g == 0 && color.b == 0;

  /// 解析十六进制颜色（不含前导 #）
  static Color? _parseHexColor(String hex) {
    var normalized = hex;
    if (normalized.length == 3 || normalized.length == 4) {
      // 缩写形式逐位展开，如 #abc -> #aabbcc
      normalized = normalized.split('').map((char) => '$char$char').join();
    }
    if (normalized.length != 6 && normalized.length != 8) return null;

    final value = int.tryParse(normalized, radix: 16);
    if (value == null) return null;
    if (normalized.length == 6) {
      return Color(0xFF000000 | value);
    }
    // CSS 的 #RRGGBBAA 与 ARGB 通道顺序不同，需要重新排列
    final red = (value >> 24) & 0xFF;
    final green = (value >> 16) & 0xFF;
    final blue = (value >> 8) & 0xFF;
    final alpha = value & 0xFF;
    return Color.fromARGB(alpha, red, green, blue);
  }

  /// 解析 rgb()/rgba() 括号内的通道值
  static Color? _parseRgbChannels(String raw) {
    final parts = raw.split(',').map((part) => part.trim()).toList();
    if (parts.length < 3) return null;

    int? parseChannel(String part) {
      if (part.endsWith('%')) {
        final percent = double.tryParse(part.substring(0, part.length - 1));
        if (percent == null) return null;
        return (percent * 255 / 100).round().clamp(0, 255);
      }
      final value = double.tryParse(part);
      if (value == null) return null;
      return value.round().clamp(0, 255);
    }

    final red = parseChannel(parts[0]);
    final green = parseChannel(parts[1]);
    final blue = parseChannel(parts[2]);
    if (red == null || green == null || blue == null) return null;

    var alpha = 255;
    if (parts.length >= 4) {
      final part = parts[3];
      double? value;
      if (part.endsWith('%')) {
        final percent = double.tryParse(part.substring(0, part.length - 1));
        value = percent == null ? null : percent / 100;
      } else {
        value = double.tryParse(part);
      }
      if (value != null) alpha = (value * 255).round().clamp(0, 255);
    }

    return Color.fromARGB(alpha, red, green, blue);
  }

  /// 常见 CSS 颜色名
  static const Map<String, Color> _namedColors = {
    'black': Color(0xFF000000),
    'silver': Color(0xFFC0C0C0),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
    'white': Color(0xFFFFFFFF),
    'maroon': Color(0xFF800000),
    'red': Color(0xFFFF0000),
    'purple': Color(0xFF800080),
    'fuchsia': Color(0xFFFF00FF),
    'magenta': Color(0xFFFF00FF),
    'green': Color(0xFF008000),
    'lime': Color(0xFF00FF00),
    'olive': Color(0xFF808000),
    'yellow': Color(0xFFFFFF00),
    'navy': Color(0xFF000080),
    'blue': Color(0xFF0000FF),
    'teal': Color(0xFF008080),
    'aqua': Color(0xFF00FFFF),
    'cyan': Color(0xFF00FFFF),
    'orange': Color(0xFFFFA500),
    'brown': Color(0xFFA52A2A),
    'pink': Color(0xFFFFC0CB),
    'gold': Color(0xFFFFD700),
    'darkred': Color(0xFF8B0000),
    'darkgreen': Color(0xFF006400),
    'darkblue': Color(0xFF00008B),
    'darkorange': Color(0xFFFF8C00),
    'darkgray': Color(0xFFA9A9A9),
    'darkgrey': Color(0xFFA9A9A9),
    'lightgray': Color(0xFFD3D3D3),
    'lightgrey': Color(0xFFD3D3D3),
    'lightblue': Color(0xFFADD8E6),
    'lightgreen': Color(0xFF90EE90),
  };

  /// 判断是否为标题标签
  static bool _isHeading(String tag) =>
      tag == 'h1' ||
      tag == 'h2' ||
      tag == 'h3' ||
      tag == 'h4' ||
      tag == 'h5' ||
      tag == 'h6';

  /// 将标题标签映射为大纲标题级别（最多 3 级）
  static int _headingLevelOf(String tag) {
    if (tag == 'h1') return 1;
    if (tag == 'h2') return 2;
    if (_isHeading(tag)) return 3;
    return 0;
  }

  /// 判断单个字符是否为空白
  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0xA0;
}
