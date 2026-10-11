part of re_editor;

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

class _CodeParagraphProvider {

  final Map<TextSpan, _ParagraphImpl> _cachedParagraphs;

  ui.TextStyle? _style;
  ui.ParagraphConstraints? _constraints;
  ui.ParagraphStyle? _paragraphStyle;
  double? _preferredLineHeight;
  int? _maxLengthSingleLineRendering;

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

  IParagraph build(TextSpan span, double maxWidth) {
    if (maxWidth != _constraints?.width) {
      _constraints = ui.ParagraphConstraints(
        width: maxWidth
      );
      clearCache();
    }
    final _ParagraphImpl? cache = _cachedParagraphs[span];
    if (cache != null) {
      return cache;
    }
    final _ParagraphImpl impl;
    // Trucate the span if it's too long.
    final String plainText = span.toPlainText();
    final int? renderingLength = _maxLengthSingleLineRendering;
    if (renderingLength != null && plainText.length > renderingLength) {
      impl = _build(trucate(span, renderingLength), plainText.substring(0, renderingLength), true);
    } else {
      impl = _build(span, plainText, false);
    }
    _cachedParagraphs[span] = impl;
    return impl;
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

  _ParagraphImpl _build(TextSpan span, String plainText, bool trucated) {
    final ui.ParagraphStyle? style = _paragraphStyle;
    if (style == null) {
      throw AssertionError('Must call updateBaseStyle before build Paragraph.');
    }
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(style);
    span.build(builder);
    final ui.Paragraph paragraph = builder.build();
    paragraph.layout(_constraints!);
    return _ParagraphImpl(
      text: plainText,
      span: span,
      paragraph: paragraph,
      trucated: trucated,
      preferredLineHeight: _preferredLineHeight!,
    );
  }

}
