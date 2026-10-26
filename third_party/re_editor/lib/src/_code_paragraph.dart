part of re_editor;

/// 全角空格
///
/// 正文行首出现该字符时，表示该行已由字符实现首行缩进，视觉缩进不再叠加。
const String _kFullWidthSpace = '\u3000';

class _ParagraphImpl extends IParagraph {

  // Unicode value for a zero width joiner character.
  static const int _zwjUtf16 = 0x200d;

  final String text;
  final TextSpan span;
  final ui.Paragraph paragraph;
  final bool _trucated;
  final double _preferredLineHeight;
  final int _lineCount;

  // For performance, do not init here
  Map<TextPosition, Offset?>? _offsets;

  _ParagraphImpl({
    required this.text,
    required this.span,
    required this.paragraph,
    required bool trucated,
    required double preferredLineHeight,
  }) : _trucated = trucated,
    _preferredLineHeight = preferredLineHeight,
    _lineCount = (paragraph.height / preferredLineHeight).ceil();

  int get runeLength => text.runes.length;

  int? codeUnitAt(int index) {
    if (index < 0 || index >= length) {
      return null;
    }
    return text.codeUnitAt(index);
  }

  @override
  double get width => _applyFloatingPointHack(max(0, paragraph.longestLine));

  @override
  double get height => lineCount * preferredLineHeight;

  @override
  double get preferredLineHeight => _preferredLineHeight;

  @override
  int get length => text.length;

  @override
  int get lineCount => _lineCount;

  @override
  bool get trucated => _trucated;

  @override
  void draw(Canvas canvas, Offset offset) {
    canvas.drawParagraph(paragraph, offset);
  }

  @override
  TextPosition getPosition(Offset offset) {
    final TextPosition position = paragraph.getPositionForOffset(offset);
    return position;
  }

  @override
  InlineSpan? getSpanForPosition(TextPosition position) {
    if (position.offset >= length - 1) {
      return null;
    }
    return span.getSpanForPosition(position);
  }

  @override
  TextRange getRangeForSpan(InlineSpan span) {
    int offset = 0;
    this.span.visitChildren((child) {
      if (identical(child, span)) {
        return false;
      }
      offset += child.length;
      return true;
    });
    return TextRange(
      start: offset,
      end: offset + span.length
    );
  }

  @override
  TextRange getWord(Offset offset) {
    final TextRange range = paragraph.getWordBoundary(getPosition(offset));
    // 引擎已给出多字符的单词范围（如拉丁字母单词）时直接采用
    if (range.end - range.start > 1) {
      return range;
    }
    // 引擎未内置中文分词时会按单字返回，优先使用注入的分词器，否则退化为连续汉字区间
    final TextRange? resolved = codeWordBoundaryResolver?.call(text, range.start);
    if (resolved != null) {
      return resolved;
    }
    return _hanWordRange(range.start) ?? range;
  }

  /// 以 [offset] 所在汉字为中心扩展出连续汉字区间
  ///
  /// 遇到标点、空白、字母数字等非汉字字符即停止；当前位置不是汉字时返回 null。
  TextRange? _hanWordRange(int offset) {
    if (text.isEmpty) {
      return null;
    }
    int index = offset.clamp(0, text.length - 1);
    if (!_isHanCodeUnit(text.codeUnitAt(index))) {
      // 光标落在汉字右边界时，回退一个字符判定
      if (index == 0 || !_isHanCodeUnit(text.codeUnitAt(index - 1))) {
        return null;
      }
      index -= 1;
    }
    int start = index;
    int end = index + 1;
    while (start > 0 && _isHanCodeUnit(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < text.length && _isHanCodeUnit(text.codeUnitAt(end))) {
      end++;
    }
    return TextRange(start: start, end: end);
  }

  /// 判断是否为汉字码元
  ///
  /// 涵盖基本区、扩展 A、兼容区与叠字符号「々」，扩展 B 及以上（代理对）不在处理范围内。
  bool _isHanCodeUnit(int codeUnit) {
    return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
        (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) ||
        codeUnit == 0x3007 ||
        codeUnit == 0x3005;
  }

  @override
  TextRange getLineBoundary(TextPosition position) {
    return paragraph.getLineBoundary(position);
  }

  @override
  Offset? getOffset(TextPosition position) {
    Offset? offset = _offsets?[position];
    if (offset != null) {
      return offset;
    }
    if (text.isEmpty) {
      return Offset(_lineStartInset, 0);
    }
    if (position.offset == 0) {
      return Offset(_lineStartInset, 0);
    }
    if (position.affinity == TextAffinity.downstream) {
      offset = _getOffsetDownstream(position.offset) ?? _getOffsetUpstream(position.offset);
    } else {
      offset = _getOffsetUpstream(position.offset) ?? _getOffsetDownstream(position.offset);
    }
    (_offsets ??= {})[position] = offset;
    return offset;
  }

  @override
  List<Rect> getRangeRects(TextRange range) {
    if (text.isEmpty) {
      return [
        Rect.fromLTWH(_lineStartInset, 0, 0, _preferredLineHeight)
      ];
    }
    if (range.isCollapsed) {
      return const [];
    }
    return paragraph.getBoxesForRange(range.start, range.end, boxHeightStyle: ui.BoxHeightStyle.max).map((e) => e.toRect()).toList();
  }

  /// 排版时字间距会在首个字形之前额外插入半个字间距的空白，
  /// 空行与行首没有字形，需要按相同间距给出起始横坐标，才能与有内容的行保持一致。
  double get _lineStartInset => (span.style?.letterSpacing ?? 0) / 2;

  Offset? _getOffsetDownstream(int position) {
    final int? nextCodeUnit = codeUnitAt(min(position, text.length - 1));
    if (nextCodeUnit == null) {
      return null;
    }
    // Check for multi-code-unit glyphs such as emojis or zero width joiner.
    final int graphemeClusterLength = _isUtf16Surrogate(nextCodeUnit) ||
      _isUnicodeDirectionality(nextCodeUnit) || codeUnitAt(position) == _zwjUtf16 ? 2 : 1;
    final List<TextBox> boxes = paragraph.getBoxesForRange(position,
      position + graphemeClusterLength, boxHeightStyle: ui.BoxHeightStyle.strut);
    if (boxes.isEmpty) {
      return null;
    }
    return Offset(boxes.first.left, boxes.first.top);
  }

  Offset? _getOffsetUpstream(int position) {
    final int? prevCodeUnit = codeUnitAt(max(0, position - 1));
    if (prevCodeUnit == null) {
      return null;
    }
    // Check for multi-code-unit glyphs such as emojis or zero width joiner.
    final int graphemeClusterLength = _isUtf16Surrogate(prevCodeUnit) ||
      _isUnicodeDirectionality(prevCodeUnit) || codeUnitAt(position) == _zwjUtf16 ? 2 : 1;
    final List<TextBox> boxes = paragraph.getBoxesForRange(position - graphemeClusterLength,
      position, boxHeightStyle: ui.BoxHeightStyle.strut);
    if (boxes.isEmpty) {
      return null;
    }
    return Offset(boxes.first.right, boxes.first.top);
  }

  // Returns true if the given value is a valid UTF-16 surrogate. The value
  // must be a UTF-16 code unit, meaning it must be in the range 0x0000-0xFFFF.
  //
  // See also:
  //   * https://en.wikipedia.org/wiki/UTF-16#Code_points_from_U+010000_to_U+10FFFF
  bool _isUtf16Surrogate(int value) {
    return value & 0xF800 == 0xD800;
  }

  // Checks if the glyph is either [Unicode.RLM] or [Unicode.LRM]. These values take
  // up zero space and do not have valid bounding boxes around them.
  //
  // We do not directly use the [Unicode] constants since they are strings.
  bool _isUnicodeDirectionality(int value) {
    return value == 0x200F || value == 0x200E;
  }

  // Unfortunately, using full precision floating point here causes bad layouts
  // because floating point math isn't associative. If we add and subtract
  // padding, for example, we'll get different values when we estimate sizes and
  // when we actually compute layout because the operations will end up associated
  // differently. To work around this problem for now, we round fractional pixel
  // values up to the nearest whole pixel value. The right long-term fix is to do
  // layout using fixed precision arithmetic.
  double _applyFloatingPointHack(double layoutValue) {
    return layoutValue.ceilToDouble();
  }

}

/// 截取文本分段中 [start, end) 区间的内容
///
/// 按先序遍历累计字符游标，区间之外的子分段被丢弃，与区间相交的子分段按交集
/// 截断文本，各层样式原样保留。遍历必须完整走完每个节点的子分段，
/// 否则后续节点的起始偏移会与文本错位。区间为空时返回空分段。
TextSpan _subSpan(TextSpan span, int start, int end) {
  int cursor = 0;

  TextSpan? slice(TextSpan node) {
    String? slicedText;
    final String? text = node.text;
    if (text != null) {
      final int textStart = cursor;
      final int textEnd = textStart + text.length;
      cursor = textEnd;
      final int from = max(start, textStart);
      final int to = min(end, textEnd);
      if (to > from) {
        slicedText = text.substring(from - textStart, to - textStart);
      }
    }
    final List<InlineSpan> children = [];
    for (final InlineSpan child in node.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) {
        final TextSpan? sliced = slice(child);
        if (sliced != null) {
          children.add(sliced);
        }
      }
    }
    if (slicedText == null && children.isEmpty) {
      return null;
    }
    return TextSpan(
      text: slicedText,
      children: children.isEmpty ? null : children,
      style: node.style,
    );
  }

  return slice(span) ?? const TextSpan(text: '');
}

/// 判断 [target] 是否为 [root] 自身或其后代分段
bool _containsSpan(InlineSpan root, InlineSpan target) {
  if (identical(root, target)) {
    return true;
  }
  bool found = false;
  root.visitChildren((child) {
    if (_containsSpan(child, target)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// 视觉首行缩进段落
///
/// 一个逻辑行拆成两段排版：首行按「完整宽度 − 缩进」排版并整体右移绘制，
/// 首行之后的文字按完整宽度排版、从行首位置开始绘制，从而实现 Word/WPS
/// 那样不占用正文字符的首行缩进。
///
/// 对外仍表现为一个普通段落：[length] 与逻辑行文本一致，光标、选区与命中测试
/// 的偏移换算在首行与后续行之间分派，调用方无需感知内部拆分。
class _FirstLineIndentParagraph extends IParagraph {

  /// 首行排版结果（按缩进后的宽度排版整行文本，绘制时只取第一视觉行）
  final _ParagraphImpl _first;

  /// 首行之后文字的排版结果，整行只有一个视觉行时为 null
  final _ParagraphImpl? _rest;

  /// 首行右侧缩进的宽度（像素）
  final double _indent;

  /// 首行结束处的字符偏移
  final int _split;

  /// 整行文本
  final String _text;

  _FirstLineIndentParagraph({
    required _ParagraphImpl first,
    required _ParagraphImpl? rest,
    required double indent,
    required int split,
    required String text,
  }) : _first = first,
    _rest = rest,
    _indent = indent,
    _split = split,
    _text = text;

  /// 首行的行高
  double get _firstLineHeight => _first.preferredLineHeight;

  @override
  double get width => max(_first.width + _indent, _rest?.width ?? 0);

  @override
  double get height => _firstLineHeight + (_rest?.height ?? 0);

  @override
  double get preferredLineHeight => _first.preferredLineHeight;

  @override
  bool get trucated => _first.trucated;

  @override
  int get length => _text.length;

  @override
  int get lineCount => 1 + (_rest?.lineCount ?? 0);

  @override
  void draw(Canvas canvas, Offset offset) {
    final _ParagraphImpl? rest = _rest;
    if (rest == null) {
      _first.draw(canvas, offset + Offset(_indent, 0));
      return;
    }
    // 首行段落内还包含后续视觉行，按第一视觉行的底边裁剪，避免重复绘制
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy, width, _firstLineHeight));
    _first.draw(canvas, offset + Offset(_indent, 0));
    canvas.restore();
    rest.draw(canvas, offset + Offset(0, _firstLineHeight));
  }

  @override
  TextPosition getPosition(Offset offset) {
    final _ParagraphImpl? rest = _rest;
    if (rest == null || offset.dy < _firstLineHeight) {
      return _first.getPosition(Offset(offset.dx - _indent, offset.dy));
    }
    // 后续行段落的偏移以首行结束处为起点，需换算回整行偏移
    final TextPosition position = rest.getPosition(
      Offset(offset.dx, offset.dy - _firstLineHeight)
    );
    return TextPosition(
      offset: position.offset + _split,
      affinity: position.affinity
    );
  }

  @override
  Offset? getOffset(TextPosition position) {
    final _ParagraphImpl? rest = _rest;
    final int offset = position.offset;
    if (rest == null || offset < _split) {
      final Offset? value = _first.getOffset(position);
      return value == null ? null : value + Offset(_indent, 0);
    }
    if (offset > _split) {
      final Offset? value = rest.getOffset(TextPosition(
        offset: offset - _split,
        affinity: position.affinity
      ));
      return value == null ? null : value + Offset(0, _firstLineHeight);
    }
    // 首行与后续行的分界处：上游亲和性取首行末端，下游亲和性取下一行行首
    if (position.affinity == TextAffinity.upstream) {
      final Offset? value = _first.getOffset(TextPosition(
        offset: _split,
        affinity: TextAffinity.upstream
      ));
      return value == null ? null : value + Offset(_indent, 0);
    }
    final Offset? value = rest.getOffset(const TextPosition(
      offset: 0,
      affinity: TextAffinity.upstream
    ));
    return value == null ? null : value + Offset(0, _firstLineHeight);
  }

  @override
  List<Rect> getRangeRects(TextRange range) {
    if (_text.isEmpty) {
      final Offset? origin = _first.getOffset(const TextPosition(offset: 0));
      return [
        Rect.fromLTWH((origin?.dx ?? 0) + _indent, 0, 0, _firstLineHeight)
      ];
    }
    if (range.isCollapsed) {
      return const [];
    }
    final _ParagraphImpl? rest = _rest;
    if (rest == null || range.end <= _split) {
      return _first.getRangeRects(range)
          .map((rect) => rect.translate(_indent, 0))
          .toList();
    }
    if (range.start >= _split) {
      return rest.getRangeRects(TextRange(
        start: range.start - _split,
        end: range.end - _split
      )).map((rect) => rect.translate(0, _firstLineHeight)).toList();
    }
    return [
      ..._first.getRangeRects(TextRange(start: range.start, end: _split))
          .map((rect) => rect.translate(_indent, 0)),
      ...rest.getRangeRects(TextRange(start: 0, end: range.end - _split))
          .map((rect) => rect.translate(0, _firstLineHeight)),
    ];
  }

  @override
  TextRange getWord(Offset offset) {
    final _ParagraphImpl? rest = _rest;
    if (rest == null || offset.dy < _firstLineHeight) {
      return _first.getWord(Offset(offset.dx - _indent, offset.dy));
    }
    final TextRange range = rest.getWord(Offset(offset.dx, offset.dy - _firstLineHeight));
    return TextRange(start: range.start + _split, end: range.end + _split);
  }

  @override
  TextRange getLineBoundary(TextPosition position) {
    final _ParagraphImpl? rest = _rest;
    if (rest == null) {
      return _first.getLineBoundary(position);
    }
    final int offset = position.offset;
    final bool inRest = offset > _split ||
        (offset == _split && position.affinity == TextAffinity.downstream);
    if (!inRest) {
      return _first.getLineBoundary(position);
    }
    final TextRange range = rest.getLineBoundary(TextPosition(
      offset: offset - _split,
      affinity: position.affinity
    ));
    return TextRange(start: range.start + _split, end: range.end + _split);
  }

  @override
  InlineSpan? getSpanForPosition(TextPosition position) {
    final _ParagraphImpl? rest = _rest;
    if (rest == null || position.offset < _split) {
      return _first.getSpanForPosition(position);
    }
    return rest.getSpanForPosition(TextPosition(
      offset: position.offset - _split,
      affinity: position.affinity
    ));
  }

  @override
  TextRange getRangeForSpan(InlineSpan span) {
    final _ParagraphImpl? rest = _rest;
    if (rest != null && _containsSpan(rest.span, span)) {
      final TextRange range = rest.getRangeForSpan(span);
      return TextRange(start: range.start + _split, end: range.end + _split);
    }
    return _first.getRangeForSpan(span);
  }

}

class _CodeParagraphProvider {

  final Map<TextSpan, IParagraph> _cachedParagraphs;

  ui.TextStyle? _style;
  ui.ParagraphConstraints? _constraints;
  ui.ParagraphStyle? _paragraphStyle;
  double? _preferredLineHeight;
  int? _maxLengthSingleLineRendering;

  /// 视觉首行缩进的宽度（像素）
  ///
  /// 大于零时每行首行按缩减后的宽度排版并右移绘制，正文不写入缩进字符。
  double _firstLineIndent = 0;

  _CodeParagraphProvider() : _cachedParagraphs = {};

  void updateBaseStyle(TextStyle style) {
    final ui.TextStyle uiStyle = style.getTextStyle();
    if (uiStyle == _style) {
      return;
    }
    _paragraphStyle = style.getParagraphStyle(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontSize: style.fontSize,
        fontFamily: style.fontFamily,
        height: style.height,
        forceStrutHeight: true,
      )
    );
    _style = uiStyle;
    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    painter.text = TextSpan(
      text: '0',
      style: style
    );
    _preferredLineHeight = painter.preferredLineHeight;
    clearCache();
  }

  void updateMaxLengthSingleLineRendering(int? maxLengthSingleLineRendering) {
    if (_maxLengthSingleLineRendering == maxLengthSingleLineRendering) {
      return;
    }
    _maxLengthSingleLineRendering = maxLengthSingleLineRendering;
    clearCache();
  }

  /// 更新视觉首行缩进宽度
  void updateFirstLineIndent(double value) {
    if (_firstLineIndent == value) {
      return;
    }
    _firstLineIndent = value;
    clearCache();
  }

  IParagraph build(TextSpan span, double maxWidth) {
    if (maxWidth != _constraints?.width) {
      _constraints = ui.ParagraphConstraints(
        width: maxWidth
      );
      clearCache();
    }
    final IParagraph? cache = _cachedParagraphs[span];
    if (cache != null) {
      return cache;
    }
    // Trucate the span if it's too long.
    final String plainText = span.toPlainText();
    final int? renderingLength = _maxLengthSingleLineRendering;
    final TextSpan effectiveSpan;
    final String effectiveText;
    final bool trucated;
    if (renderingLength != null && plainText.length > renderingLength) {
      effectiveSpan = trucate(span, renderingLength);
      effectiveText = plainText.substring(0, renderingLength);
      trucated = true;
    } else {
      effectiveSpan = span;
      effectiveText = plainText;
      trucated = false;
    }
    final IParagraph impl = _firstLineIndent > 0
        ? _buildFirstLineIndent(effectiveSpan, effectiveText, trucated, maxWidth)
        : _build(effectiveSpan, effectiveText, trucated);
    _cachedParagraphs[span] = impl;
    return impl;
  }

  /// 构建带视觉首行缩进的段落
  ///
  /// 先按「完整宽度 − 缩进」排版整行以取得首行的结束位置，再把首行之后的文字
  /// 按完整宽度单独排版；行首已有全角空格的行不施加缩进，避免与存量字符缩进叠加。
  IParagraph _buildFirstLineIndent(
    TextSpan span,
    String text,
    bool trucated,
    double maxWidth,
  ) {
    final double firstLineWidth = maxWidth - _firstLineIndent;
    if (!maxWidth.isFinite || firstLineWidth <= 0 || text.startsWith(_kFullWidthSpace)) {
      return _build(span, text, trucated);
    }
    if (text.isEmpty) {
      // 空行同样保留缩进，使回车后光标落在缩进位置，输入首字时不再跳动
      return _FirstLineIndentParagraph(
        first: _build(span, text, trucated, maxWidth: firstLineWidth),
        rest: null,
        indent: _firstLineIndent,
        split: 0,
        text: text,
      );
    }
    final _ParagraphImpl first = _build(span, text, trucated, maxWidth: firstLineWidth);
    final TextRange firstLine = first.getLineBoundary(const TextPosition(offset: 0));
    final int split = firstLine.end.clamp(0, text.length);
    if (split <= 0) {
      return _build(span, text, trucated);
    }
    if (split >= text.length) {
      // 整行都容纳在首行内，无需拆分后续内容
      return _FirstLineIndentParagraph(
        first: first,
        rest: null,
        indent: _firstLineIndent,
        split: text.length,
        text: text,
      );
    }
    final String restText = text.substring(split);
    final _ParagraphImpl rest = _build(
      _subSpan(span, split, text.length),
      restText,
      trucated,
    );
    return _FirstLineIndentParagraph(
      first: first,
      rest: rest,
      indent: _firstLineIndent,
      split: split,
      text: text,
    );
  }

  TextSpan trucate(TextSpan span, int maxLength) {
    int currentLength = 0;
    TextSpan truncateSpan(TextSpan span) {
      if (currentLength >= maxLength) {
        return const TextSpan(text: '');
      }
      String? text = span.text;
      if (text != null) {
        int remainingLength = maxLength - currentLength;
        if (text.length > remainingLength) {
          text = text.substring(0, remainingLength);
        }
        currentLength += text.length;
        return TextSpan(
          text: text,
          style: span.style
        );
      }
      final List<InlineSpan> children = [];
      for (InlineSpan child in span.children ?? const []) {
        if (currentLength >= maxLength) {
          break;
        }
        if (child is TextSpan) {
          children.add(truncateSpan(child));
        } else {
          children.add(child);
        }
      }
      return TextSpan(
        children: children,
        style: span.style
      );
    }
    return truncateSpan(span);
  }

  void clearCache() {
    _cachedParagraphs.clear();
  }

  _ParagraphImpl _build(
    TextSpan span,
    String plainText,
    bool trucated, {
    double? maxWidth,
  }) {
    final ui.ParagraphStyle? style = _paragraphStyle;
    if (style == null) {
      throw AssertionError('Must call updateBaseStyle before build Paragraph.');
    }
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(style);
    span.build(builder);
    final ui.Paragraph paragraph = builder.build();
    paragraph.layout(maxWidth == null
        ? _constraints!
        : ui.ParagraphConstraints(width: maxWidth));
    return _ParagraphImpl(
      text: plainText,
      span: span,
      paragraph: paragraph,
      trucated: trucated,
      preferredLineHeight: _preferredLineHeight!,
    );
  }

}
