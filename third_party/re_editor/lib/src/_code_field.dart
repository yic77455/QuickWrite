part of re_editor;

/// 行首空白前缀（含全角空格、制表符等）
final RegExp _kLeadingWhitespace = RegExp(r'^\s*');

class _CodeField extends SingleChildRenderObjectWidget {

  final ViewportOffset verticalViewport;
  final ViewportOffset? horizontalViewport;
  final double verticalScrollbarWidth;
  final double horizontalScrollbarHeight;
  final CodeLines codes;
  final CodeLineSelection selection;
  final List<CodeLineSelection>? highlightSelections;
  final TextStyle textStyle;
  final bool hasFocus;
  final _CodeHighlighter highlighter;
  final ValueNotifier<bool> showCursorNotifier;
  final ValueNotifier<_FloatingCursorState> floatingCursorNotifier;
  final ValueChanged<List<CodeLineRenderParagraph>> onRenderParagraphsChanged;
  final Color selectionColor;
  final Color highlightColor;
  final Color cursorColor;
  final Color floatingCursorColor;
  final Color? cursorLineColor;
  final Color? chunkIndicatorColor;
  final double cursorWidth;
  final double floatingCursorWidth;
  final EdgeInsetsGeometry padding;
  final bool readOnly;
  final int? maxLengthSingleLineRendering;
  final LayerLink startHandleLayerLink;
  final LayerLink endHandleLayerLink;
  final ScrollController? externalScrollController;
  final double externalContentOffset;

  _CodeField({
    super.key,
    required this.verticalViewport,
    required this.horizontalViewport,
    required this.verticalScrollbarWidth,
    required this.horizontalScrollbarHeight,
    required this.codes,
    required this.selection,
    required this.highlightSelections,
    required this.textStyle,
    required this.hasFocus,
    required this.highlighter,
    required this.showCursorNotifier,
    required this.floatingCursorNotifier,
    required this.onRenderParagraphsChanged,
    required this.selectionColor,
    required this.highlightColor,
    required this.cursorColor,
    floatingCursorColor,
    this.cursorLineColor,
    this.chunkIndicatorColor,
    required this.cursorWidth,
    floatingCursorWidth,
    required this.padding,
    required this.readOnly,
    this.maxLengthSingleLineRendering,
    required this.startHandleLayerLink,
    required this.endHandleLayerLink,
    required this.externalScrollController,
    required this.externalContentOffset,
  }): assert(codes.isNotEmpty),
      floatingCursorColor = floatingCursorColor ?? cursorColor,
      floatingCursorWidth = floatingCursorWidth ?? cursorWidth;


  @override
  RenderObject createRenderObject(BuildContext context) => _CodeFieldRender(
    verticalViewport: verticalViewport,
    horizontalViewport: horizontalViewport,
    verticalScrollbarWidth: verticalScrollbarWidth,
    horizontalScrollbarHeight: horizontalScrollbarHeight,
    codes: codes,
    selection: selection,
    highlightSelections: highlightSelections,
    textStyle: textStyle,
    hasFocus: hasFocus,
    highlighter: highlighter,
    showCursorNotifier: showCursorNotifier,
    floatingCursorNotifier: floatingCursorNotifier,
    onRenderParagraphsChanged: onRenderParagraphsChanged,
    selectionColor: selectionColor,
    highlightColor: highlightColor,
    cursorColor: cursorColor,
    floatingCursorColor: floatingCursorColor,
    cursorLineColor: cursorLineColor,
    chunkIndicatorColor: chunkIndicatorColor,
    cursorWidth: cursorWidth,
    floatingCursorWidth: floatingCursorWidth,
    padding: padding,
    readOnly: readOnly,
    maxLengthSingleLineRendering: maxLengthSingleLineRendering,
    startHandleLayerLink: startHandleLayerLink,
    endHandleLayerLink: endHandleLayerLink,
    externalScrollController: externalScrollController,
    externalContentOffset: externalContentOffset,
  );

  @override
  void updateRenderObject(BuildContext context, covariant _CodeFieldRender renderObject) {
    renderObject
      ..verticalViewport = verticalViewport
      ..horizontalViewport = horizontalViewport
      ..verticalScrollbarWidth = verticalScrollbarWidth
      ..horizontalScrollbarHeight = horizontalScrollbarHeight
      ..codes = codes
      ..selection = selection
      ..highlightSelections = highlightSelections
      ..textStyle = textStyle
      ..hasFocus = hasFocus
      ..highlighter = highlighter
      ..showCursorNotifier = showCursorNotifier
      ..floatingCursorNotifier = floatingCursorNotifier
      ..onRenderParagraphsChanged = onRenderParagraphsChanged
      ..selectionColor = selectionColor
      ..highlightColor = highlightColor
      ..cursorColor = cursorColor
      ..floatingCursorColor = floatingCursorColor
      ..cursorLineColor = cursorLineColor
      ..chunkIndicatorColor = chunkIndicatorColor
      ..cursorWidth = cursorWidth
      ..floatingCursorWidth = floatingCursorWidth
      ..padding = padding
      ..readOnly = readOnly
      ..maxLengthSingleLineRendering = maxLengthSingleLineRendering
      ..startHandleLayerLink = startHandleLayerLink
      ..endHandleLayerLink = endHandleLayerLink
      ..externalScrollController = externalScrollController
      ..externalContentOffset = externalContentOffset;
  }

}

const Duration positionCenteringDuration = Duration(milliseconds: 300);

class _CodeFieldRender extends RenderBox implements MouseTrackerAnnotation {

  /// 自适应高度模式下计算可见段落时额外构建的缓冲行数
  static const int _intrinsicBufferLines = 3;

  /// 外部视口尺寸重试的最大次数
  static const int _maxViewportRetry = 5;

  /// 外部滚动定位重试的最大次数
  static const int _maxRevealRetry = 3;

  ViewportOffset _verticalViewport;
  ViewportOffset? _horizontalViewport;
  double _verticalScrollbarWidth;
  double _horizontalScrollbarHeight;
  CodeLines _codes;
  CodeLineSelection _selection;
  TextStyle _textStyle;
  bool _hasFocus;
  _CodeHighlighter _highlighter;
  ValueNotifier<bool> _showCursorNotifier;
  ValueNotifier<_FloatingCursorState> _floatingCursorNotifier;
  ValueChanged<List<CodeLineRenderParagraph>> _onRenderParagraphsChanged;
  EdgeInsetsGeometry _padding;
  bool _readOnly;
  int? _maxLengthSingleLineRendering;
  Color? _chunkIndicatorColor;
  ScrollController? _externalScrollController;
  double _externalContentOffset;

  double? _horizontalViewportSize;
  double? _verticalViewportSize;
  MouseCursor _cursor;

  /// 自适应高度模式下的行高前缀和
  ///
  /// 第 i 项为第 i 行顶部相对正文顶部的偏移，末项为正文总高；为空表示需要重建。
  List<double>? _lineTops;

  /// 构建 [_lineTops] 时使用的排版宽度
  double _lineTopsWidth = -1;

  /// 外部视口尺寸重试次数
  int _viewportRetryCount = 0;

  /// 外部视口重试是否已排队，避免同一帧内重复排队
  bool _viewportRetryScheduled = false;

  final Paint _paint;
  final List<CodeLineRenderParagraph> _displayParagraphs;
  final List<_CodeChunkIndicator> _chunkIndicators;
  late final _CodeFieldExtraRender _foregroundRender;
  late final _CodeFieldExtraRender _backgroundRender;
  late double _preferredLineHeight;

  _CodeFieldRender({
    required ViewportOffset verticalViewport,
    required ViewportOffset? horizontalViewport,
    required double verticalScrollbarWidth,
    required double horizontalScrollbarHeight,
    required CodeLines codes,
    required CodeLineSelection selection,
    required List<CodeLineSelection>? highlightSelections,
    required TextStyle textStyle,
    required bool hasFocus,
    required _CodeHighlighter highlighter,
    required ValueNotifier<bool> showCursorNotifier,
    required ValueNotifier<_FloatingCursorState> floatingCursorNotifier,
    required ValueChanged<List<CodeLineRenderParagraph>> onRenderParagraphsChanged,
    required Color selectionColor,
    required Color highlightColor,
    required Color cursorColor,
    required Color floatingCursorColor,
    Color? cursorLineColor,
    Color? chunkIndicatorColor,
    required double cursorWidth,
    required double floatingCursorWidth,
    required EdgeInsetsGeometry padding,
    required bool readOnly,
    int? maxLengthSingleLineRendering,
    required LayerLink startHandleLayerLink,
    required LayerLink endHandleLayerLink,
    ScrollController? externalScrollController,
    double externalContentOffset = 0.0,
  }) : _verticalViewport = verticalViewport,
    _horizontalViewport = horizontalViewport,
    _verticalScrollbarWidth = verticalScrollbarWidth,
    _horizontalScrollbarHeight = horizontalScrollbarHeight,
    _codes = codes,
    _selection = selection,
    _textStyle = textStyle,
    _hasFocus = hasFocus,
    _highlighter = highlighter,
    _showCursorNotifier = showCursorNotifier,
    _floatingCursorNotifier = floatingCursorNotifier,
    _onRenderParagraphsChanged = onRenderParagraphsChanged,
    _padding = padding,
    _readOnly = readOnly,
    _maxLengthSingleLineRendering = maxLengthSingleLineRendering,
    _chunkIndicatorColor = chunkIndicatorColor,
    _externalScrollController = externalScrollController,
    _externalContentOffset = externalContentOffset,
    _paint = Paint(),
    _displayParagraphs = [],
    _chunkIndicators = [],
    _cursor = SystemMouseCursors.text,
    _startHandleLayerLink = startHandleLayerLink,
    _endHandleLayerLink = endHandleLayerLink {
    _backgroundRender = _CodeFieldExtraRender(
      painters: [
        _CodeCursorLinePainter(cursorLineColor, _selection),
        _CodeFieldSelectionPainter(selectionColor, _selection),
        _CodeFieldHighlightPainter(highlightColor, highlightSelections ?? const [])
      ]
    );
    adoptChild(_backgroundRender);
    _foregroundRender = _CodeFieldExtraRender(
      painters: [
        _CodeFieldCursorPainter(
          position: _selection.extent,
          color: cursorColor,
          width: cursorWidth,
          height: 0.0,
          visible: _showCursorNotifier.value
        ),
        _CodeFieldFloatingCursorPainter(
          position: _floatingCursorNotifier.value,
          color: floatingCursorColor,
          width: floatingCursorWidth,
          height: 0.0,
        )
      ]
    );
    adoptChild(_foregroundRender);
    _calculatePreferredLineHeight();
  }

  set verticalViewport(ViewportOffset value) {
    if (_verticalViewport == value) {
      return;
    }
    if (attached) {
      _verticalViewport.removeListener(markNeedsLayout);
    }
    _verticalViewport = value;
    if (attached) {
      markNeedsLayout();
      _verticalViewport.addListener(markNeedsLayout);
    }
  }

  set horizontalViewport(ViewportOffset? value) {
    if (_horizontalViewport == value) {
      return;
    }
    if (attached) {
      _horizontalViewport?.removeListener(markNeedsLayout);
    }
    _horizontalViewport = value;
    if (attached) {
      markNeedsLayout();
      _horizontalViewport?.addListener(markNeedsLayout);
    }
  }

  set verticalScrollbarWidth(double value) {
    if (_verticalScrollbarWidth == value) {
      return;
    }
    _verticalScrollbarWidth = value;
    markNeedsLayout();
  }

  set horizontalScrollbarHeight(double value) {
    if (_horizontalScrollbarHeight == value) {
      return;
    }
    _horizontalScrollbarHeight = value;
    markNeedsLayout();
  }

  /// 外部滚动控制器
  ///
  /// 非空表示编辑器处于自适应高度模式，此时渲染器按内容高度排版，
  /// 并跟随外部滚动偏移刷新可见段落。
  set externalScrollController(ScrollController? value) {
    if (_externalScrollController == value) {
      return;
    }
    if (attached) {
      _externalScrollController?.removeListener(_onExternalScrollChanged);
    }
    _externalScrollController = value;
    if (attached) {
      value?.addListener(_onExternalScrollChanged);
    }
    markNeedsLayout();
  }

  set externalContentOffset(double value) {
    if (_externalContentOffset == value) {
      return;
    }
    _externalContentOffset = value;
    markNeedsLayout();
  }

  set codes(CodeLines value) {
    if (_codes.equals(value)) {
      return;
    }
    _codes = value;
    _lineTops = null;
    markNeedsLayout();
  }

  set selection(CodeLineSelection value) {
    if (_selection == value) {
      return;
    }
    _selection = value;
    _backgroundRender.find<_CodeCursorLinePainter>().selection = value;
    _backgroundRender.find<_CodeFieldSelectionPainter>().selection = value;
    _foregroundRender.find<_CodeFieldCursorPainter>().position = value.extent;
    if (kIsAndroid || kIsIOS) {
      _foregroundRender.find<_CodeFieldCursorPainter>().willDraw = _selection.isCollapsed;
    }
    markNeedsLayout();
  }

  set highlightSelections(List<CodeLineSelection>? value) {
    _backgroundRender.find<_CodeFieldHighlightPainter>().selections = value ?? const [];
  }

  set textStyle(TextStyle value) {
    if (_textStyle == value) {
      return;
    }
    final RenderComparison comparison = _textStyle.compareTo(value);
    _textStyle = value;
    if (comparison.index >= RenderComparison.layout.index) {
      _calculatePreferredLineHeight();
      _lineTops = null;
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  TextStyle get textStyle => _textStyle;

  bool get hasFocus => _hasFocus;

  set hasFocus(bool value) {
    if (_hasFocus == value) {
      return;
    }
    _hasFocus = value;
    markNeedsPaint();
  }

  set highlighter(_CodeHighlighter value) {
    if (_highlighter == value) {
      return;
    }
    if (attached) {
      _highlighter.removeListener(markNeedsLayout);
    }
    _highlighter = value;
    if (attached) {
      markNeedsLayout();
      _highlighter.addListener(markNeedsLayout);
    }
    _lineTops = null;
  }

  set showCursorNotifier(ValueNotifier<bool> value) {
    if (_showCursorNotifier == value) {
      return;
    }
    if (attached) {
      _showCursorNotifier.removeListener(_onCursorVisibleChanged);
    }
    _showCursorNotifier = value;
    if (attached) {
      _onCursorVisibleChanged();
      _showCursorNotifier.addListener(_onCursorVisibleChanged);
    }
  }

  set floatingCursorNotifier(ValueNotifier<_FloatingCursorState> value) {
    if (_floatingCursorNotifier == value) {
      return;
    }
    if (attached) {
      _floatingCursorNotifier.removeListener(_onFloatingCursorChanged);
    }
    _floatingCursorNotifier = value;
    if (attached) {
      _onFloatingCursorChanged();
      _floatingCursorNotifier.addListener(_onFloatingCursorChanged);
    }
  }

  set onRenderParagraphsChanged(ValueChanged<List<CodeLineRenderParagraph>> value) {
    if (_onRenderParagraphsChanged == value) {
      return;
    }
    _onRenderParagraphsChanged = value;
  }

  set selectionColor(Color value) {
    _backgroundRender.find<_CodeFieldSelectionPainter>().color = value;
  }

  set highlightColor(Color value) {
    _backgroundRender.find<_CodeFieldHighlightPainter>().color = value;
  }

  set cursorColor(Color value) {
    _foregroundRender.find<_CodeFieldCursorPainter>().color = value;
  }

  set floatingCursorColor(Color value) {
    _foregroundRender.find<_CodeFieldFloatingCursorPainter>().color = value;
  }

  set cursorLineColor(Color? value) {
    _backgroundRender.find<_CodeCursorLinePainter>().color = value;
  }

  set chunkIndicatorColor(Color? value) {
    if (_chunkIndicatorColor == value) {
      return;
    }
    _chunkIndicatorColor = value;
    markNeedsPaint();
  }

  set cursorWidth(double value) {
    _foregroundRender.find<_CodeFieldCursorPainter>().width = value;
  }

  set floatingCursorWidth(double value) {
    _foregroundRender.find<_CodeFieldFloatingCursorPainter>().width = value;
  }

  double get cursorWidth {
    return _foregroundRender.find<_CodeFieldCursorPainter>().width;
  }

  double get floatingCursorWidth {
    return _foregroundRender.find<_CodeFieldFloatingCursorPainter>().width;
  }

  double get floatingCursorHeight {
    return _foregroundRender.find<_CodeFieldFloatingCursorPainter>().height;
  }

  ValueNotifier<bool> get showCursorNotifier => _showCursorNotifier;

  /// The [LayerLink] of start selection handle.
  ///
  /// [RenderEditable] is responsible for calculating the [Offset] of this
  /// [LayerLink], which will be used as [CompositedTransformTarget] of start handle.
  LayerLink get startHandleLayerLink => _startHandleLayerLink;
  LayerLink _startHandleLayerLink;
  set startHandleLayerLink(LayerLink value) {
    if (_startHandleLayerLink == value) {
      return;
    }
    _startHandleLayerLink = value;
    markNeedsPaint();
  }

  /// The [LayerLink] of end selection handle.
  ///
  /// [RenderEditable] is responsible for calculating the [Offset] of this
  /// [LayerLink], which will be used as [CompositedTransformTarget] of end handle.
  LayerLink get endHandleLayerLink => _endHandleLayerLink;
  LayerLink _endHandleLayerLink;
  set endHandleLayerLink(LayerLink value) {
    if (_endHandleLayerLink == value) {
      return;
    }
    _endHandleLayerLink = value;
    markNeedsPaint();
  }

  /// Track whether position of the start of the selected text is within the viewport.
  ///
  /// For example, if the text contains "Hello World", and the user selects
  /// "Hello", then scrolls so only "World" is visible, this will become false.
  /// If the user scrolls back so that the "H" is visible again, this will
  /// become true.
  ///
  /// This bool indicates whether the text is scrolled so that the handle is
  /// inside the text field viewport, as opposed to whether it is actually
  /// visible on the screen.
  ValueListenable<bool> get selectionStartInViewport => _selectionStartInViewport;
  final ValueNotifier<bool> _selectionStartInViewport = ValueNotifier<bool>(true);

  /// Track whether position of the end of the selected text is within the viewport.
  ///
  /// For example, if the text contains "Hello World", and the user selects
  /// "World", then scrolls so only "Hello" is visible, this will become
  /// 'false'. If the user scrolls back so that the "d" is visible again, this
  /// will become 'true'.
  ///
  /// This bool indicates whether the text is scrolled so that the handle is
  /// inside the text field viewport, as opposed to whether it is actually
  /// visible on the screen.
  ValueListenable<bool> get selectionEndInViewport => _selectionEndInViewport;
  final ValueNotifier<bool> _selectionEndInViewport = ValueNotifier<bool>(true);

  double get lineHeight => _preferredLineHeight;

  EdgeInsetsGeometry get padding => _padding;

  double get paddingLeft => _padding.resolve(TextDirection.ltr).left;

  double get paddingTop => _padding.resolve(TextDirection.ltr).top;

  double get paddingRight => _padding.resolve(TextDirection.ltr).right;

  double get paddingBottom => _padding.resolve(TextDirection.ltr).bottom;

  set padding(EdgeInsetsGeometry value) {
    if (_padding == value) {
      return;
    }
    double offset = value.resolve(TextDirection.ltr).top - _padding.resolve(TextDirection.ltr).top;
    if (_verticalViewport.pixels > 0) {
      if (_verticalViewport.pixels + offset < 0) {
        _verticalViewport.correctBy(0);
      } else {
        _verticalViewport.correctBy(offset);
      }
    }
    _padding = value;
    _lineTops = null;
    markNeedsLayout();
  }

  set readOnly(bool value) {
    if (_readOnly == value) {
      return;
    }
    _readOnly = value;
    markNeedsPaint();
  }

  set maxLengthSingleLineRendering(int? value) {
    if (_maxLengthSingleLineRendering == value) {
      return;
    }
    _maxLengthSingleLineRendering = value;
    _lineTops = null;
    markNeedsLayout();
  }

  List<CodeLineRenderParagraph> get displayParagraphs => _displayParagraphs;

  Offset get paintOffset => Offset(_horizontalViewport?.pixels ?? 0, _verticalViewport.pixels);

  CodeLineRenderParagraph? findDisplayParagraphByLineIndex(int index) {
    for (final CodeLineRenderParagraph paragraph in _displayParagraphs) {
      if (paragraph.index == index) {
        return paragraph;
      }
    }
    return null;
  }

  CodeLineSelection? setPositionAt({
    required Offset position,
  }) {
    final Offset localPosition = globalToLocal(position);
    if (!isValidPointer(localPosition)) {
      return null;
    }
    final CodeLinePosition? result = calculateTextPosition(localPosition);
    if (result == null) {
      return null;
    }
    return CodeLineSelection.fromPosition(
      position: result,
    );
  }

  CodeLineSelection? extendPositionTo({
    required CodeLineSelection oldSelection,
    required Offset position,
    CodeLineSelection? anchor,
    bool allowOverflow = false,
  }) {
    final Offset localPosition = globalToLocal(position);
    if (!allowOverflow && !isValidPointer(localPosition)) {
      return null;
    }
    final CodeLinePosition? result = calculateTextPosition(
      Offset(
        min(size.width, max(0, localPosition.dx)),
        min(size.height - _preferredLineHeight / 2, max(_preferredLineHeight / 2, localPosition.dy))
      )
    );
    if (result == null) {
      return null;
    }
    if (anchor != null) {
      if (result.isBefore(anchor.start)) {
        return CodeLineSelection.fromPosition(
          position: result
        ).copyWith(
          baseIndex: anchor.end.index,
          baseOffset: anchor.end.offset,
          baseAffinity: anchor.end.affinity,
        );
      }
      if (result.isAfter(anchor.end)) {
        return CodeLineSelection.fromPosition(
          position: result
        ).copyWith(
          baseIndex: anchor.start.index,
          baseOffset: anchor.start.offset,
          baseAffinity: anchor.start.affinity,
        );
      }
      return anchor;
    }
    return oldSelection.copyWith(
      extentIndex: result.index,
      extentOffset: result.offset,
      extentAffinity: result.affinity
    );
  }

  CodeLineRange? selectWord({
    required Offset position,
  }) {
    final Offset localPosition = globalToLocal(position);
    if (!isValidPointer(localPosition)) {
      return null;
    }
    return _selectWord(localPosition);
  }

  /// 段落（整行）选区
  ///
  /// 返回点击位置所在代码行的文本范围：跳过段首空白（含全角缩进），从第一个
  /// 非空白字符开始选取；空行返回折叠范围以便放置光标。
  CodeLineRange? selectParagraph({
    required Offset position,
  }) {
    final Offset localPosition = globalToLocal(position);
    if (!isValidPointer(localPosition)) {
      return null;
    }
    final CodeLineRenderParagraph? target = _findDisplayRenderParagraph(localPosition + paintOffset);
    if (target == null) {
      return null;
    }
    final String line = _codes[target.index].text;
    final int start = _kLeadingWhitespace.firstMatch(line)!.end;
    return CodeLineRange(
      index: target.index,
      start: start,
      end: line.length
    );
  }

  void makePositionVisible(CodeLinePosition position, [int tryCount = 0]) {
    if (_intrinsic) {
      _revealInExternalViewport(position, center: false, tryCount: tryCount);
      return;
    }
    final Offset? offset = calculateTextPositionViewportOffset(position);
    if (offset == null) {
      if (_displayParagraphs.isNotEmpty) {
        final CodeLineRenderParagraph first = _displayParagraphs.first;
        if (position.index < first.index) {
          _verticalViewport.jumpTo(first.top + _preferredLineHeight * (position.index - first.index));
        }
        final CodeLineRenderParagraph last = _displayParagraphs.last;
        if (position.index > last.index) {
          _verticalViewport.jumpTo(max(0, last.bottom - size.height + _preferredLineHeight * (position.index - first.index)));
        }
      }
      if (tryCount < 10) {
        SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
          // Check whether the viewport is still valid.
          final ViewportOffset viewport = _verticalViewport;
          if (viewport is ScrollPosition && viewport.context.notificationContext == null) {
            return;
          }
          makePositionVisible(position, tryCount + 1);
        });
      }
      return;
    }
    if (offset.dy < 0) {
      _verticalViewport.jumpTo(_verticalViewport.pixels + offset.dy);
    } else if (offset.dy > size.height - _preferredLineHeight) {
      _verticalViewport.jumpTo(_verticalViewport.pixels + offset.dy - (size.height - _preferredLineHeight));
    }
    if (_horizontalViewport != null) {
      if (offset.dx < 0) {
        _horizontalViewport!.jumpTo(_horizontalViewport!.pixels + offset.dx);
      } else if (offset.dx > size.width - _preferredLineHeight) {
        _horizontalViewport!.jumpTo(_horizontalViewport!.pixels + offset.dx - (size.width - _preferredLineHeight));
      }
    }
  }

  void makePositionCenterIfInvisible(CodeLinePosition position, {int tryCount = 0, bool animated = false}) {
    if (_intrinsic) {
      _revealInExternalViewport(position, center: true, animated: animated, tryCount: tryCount);
      return;
    }
    void scrollViewport(ViewportOffset viewport, num target) {
      if (animated) {
        viewport.animateTo(target.toDouble(), duration: positionCenteringDuration, curve: Curves.decelerate);
      } else {
        viewport.jumpTo(target.toDouble());
      }
    }

    final Offset? offset = calculateTextPositionViewportOffset(position);
    if (offset == null) {
      if (_displayParagraphs.isNotEmpty) {
        final CodeLineRenderParagraph first = _displayParagraphs.first;
        if (position.index < first.index) {
          final double target = max(0, first.top - _preferredLineHeight * (first.index - position.index) - size.height / 2);
          scrollViewport(_verticalViewport, target);
        }
        final CodeLineRenderParagraph last = _displayParagraphs.last;
        if (position.index > last.index) {
          final double target = min(
            _verticalViewportSize!,
            last.bottom + size.height / 2 + _preferredLineHeight * (position.index - first.index),
          );
          scrollViewport(_verticalViewport, target);
        }
      }
      if (tryCount < 10) {
        SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
          // Check whether the viewport is still valid.
          final ViewportOffset viewport = _verticalViewport;
          if (viewport is ScrollPosition && viewport.context.notificationContext == null) {
            return;
          }
          makePositionCenterIfInvisible(position, tryCount: tryCount + 1);
        });
      }
      return;
    }
    if (offset.dy < paddingTop) {
      final double target = max(0, _verticalViewport.pixels + offset.dy - size.height / 2);
      scrollViewport(_verticalViewport, target);
    } else if (offset.dy > size.height - _preferredLineHeight - paddingBottom) {
      final double target = min(
        _verticalViewportSize!,
        _verticalViewport.pixels + offset.dy + _preferredLineHeight - size.height / 2,
      );
      scrollViewport(_verticalViewport, target);
    }

    if (_horizontalViewport != null) {
      if (offset.dx < 0) {
        final target = max(0, _horizontalViewport!.pixels + offset.dx - size.width / 2);
        scrollViewport(_horizontalViewport!, target);
      } else if (offset.dx > size.width - _preferredLineHeight) {
        final target = min(
          _horizontalViewportSize!,
          _horizontalViewport!.pixels + offset.dx + _preferredLineHeight - size.width / 2,
        );
        scrollViewport(_horizontalViewport!, target);
      }
    }
  }

  /// 自适应高度模式下让指定位置在外部滚动容器中可见
  ///
  /// [center] 为 true 时仅在该位置不可见时将其居中，否则只保证其进入可见区域。
  /// 内容刚变化时外部滚动范围可能尚未更新，此时下一帧再校正一次。
  void _revealInExternalViewport(
    CodeLinePosition position, {
    required bool center,
    bool animated = false,
    int tryCount = 0,
  }) {
    final ScrollPosition? scrollPosition = _externalScrollPosition;
    final List<double>? tops = _lineTops;
    if (scrollPosition == null ||
        !scrollPosition.hasContentDimensions ||
        tops == null ||
        position.index >= tops.length) {
      _retryRevealInExternalViewport(position, center: center, animated: animated, tryCount: tryCount);
      return;
    }
    // 目标位置换算到外部滚动容器的内容坐标系
    final double contentTop = paddingTop + tops[position.index] + _externalContentOffset;
    final double contentBottom = contentTop + _preferredLineHeight;
    final double viewportTop = scrollPosition.pixels;
    final double viewportBottom = viewportTop + scrollPosition.viewportDimension;
    final double target;
    if (center) {
      if (contentTop >= viewportTop && contentBottom <= viewportBottom) {
        return;
      }
      target = (contentTop + contentBottom) / 2 - scrollPosition.viewportDimension / 2;
    } else {
      if (contentTop < viewportTop) {
        target = contentTop;
      } else if (contentBottom > viewportBottom) {
        target = contentBottom - scrollPosition.viewportDimension;
      } else {
        return;
      }
    }
    final double clamped = target.clamp(scrollPosition.minScrollExtent, scrollPosition.maxScrollExtent);
    if ((clamped - scrollPosition.pixels).abs() > 0.5) {
      if (animated) {
        scrollPosition.animateTo(clamped, duration: positionCenteringDuration, curve: Curves.decelerate);
      } else {
        scrollPosition.jumpTo(clamped);
      }
    }
    if ((target - clamped).abs() > 0.5) {
      _retryRevealInExternalViewport(position, center: center, animated: animated, tryCount: tryCount);
    }
  }

  /// 下一帧重试让指定位置在外部滚动容器中可见
  void _retryRevealInExternalViewport(
    CodeLinePosition position, {
    required bool center,
    required bool animated,
    required int tryCount,
  }) {
    if (tryCount >= _maxRevealRetry) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) {
        _revealInExternalViewport(position, center: center, animated: animated, tryCount: tryCount + 1);
      }
    });
  }

  void forceRepaint() {
    _highlighter.clearCache();
    _displayParagraphs.clear();
    if (_intrinsic) {
      // 行高前缀和只依赖文本与排版参数，此处仅需按最新样式重建可见段落
      markNeedsLayout();
    } else {
      _updateDisplayRenderParagraphs();
    }
    markNeedsPaint();
  }

  void autoScrollWhenDragging(Offset dragPosition) {
    final Offset offset = globalToLocal(dragPosition);
    final double unit = _preferredLineHeight;
    if (_verticalViewportSize != null) {
      if (offset.dy < unit) {
        _alignTopEdge(
          offset: _verticalViewport.pixels - unit
        );
      } else if (offset.dy > size.height - unit) {
        _alignBottomEdge(
          offset: _verticalViewport.pixels + unit
        );
      }
    }
    if (_horizontalViewport != null && _horizontalViewportSize != null) {
      if (offset.dx < unit) {
        _horizontalViewport!.jumpTo(max(0, _horizontalViewport!.pixels - unit));
      } else if (offset.dx > size.width - unit) {
        _horizontalViewport!.jumpTo(min(_horizontalViewport!.pixels + unit, _horizontalViewportSize!));
      }
    }
  }

  void autoScrollWhenDraggingFloatingCursor(Offset offset) {
    final double unit = _preferredLineHeight;
    if (_verticalViewportSize != null) {
      if (offset.dy == paintBounds.top + paddingTop) {
        _alignTopEdge(
          offset: _verticalViewport.pixels - unit
        );
      } else if (offset.dy == paintBounds.bottom - paddingBottom - floatingCursorHeight) {
        _alignBottomEdge(
          offset: _verticalViewport.pixels + unit
        );
      }
    }
    if (_horizontalViewport != null && _horizontalViewportSize != null) {
      if (offset.dx < unit) {
        _horizontalViewport!.jumpTo(max(0, _horizontalViewport!.pixels - unit));
      } else if (offset.dx > size.width - unit) {
        _horizontalViewport!.jumpTo(min(_horizontalViewport!.pixels + unit, _horizontalViewportSize!));
      }
    }
  }

  int chunkIndicatorHitIndex(Offset position) {
    final Offset localPosition = globalToLocal(position);
    if (!isValidPointer(localPosition)) {
      return -1;
    }
    final int index = _chunkIndicators.indexWhere((chunk) => chunk.canExpand && chunk.region.contains(localPosition));
    if (index < 0) {
      return -1;
    }
    return _chunkIndicators[index].index;
  }

  /// 指定光标位置的横向像素坐标
  ///
  /// 位置所在行不在可见段落内时返回 null。
  double? caretDxOf(CodeLinePosition position) {
    final CodeLineRenderParagraph? paragraph = findDisplayParagraphByLineIndex(position.index);
    if (paragraph == null) {
      return null;
    }
    return paragraph.getOffset(position.textPosition)?.dx;
  }

  /// 上移一行后的光标位置
  ///
  /// [preferredDx] 为纵向移动期间保持的横向像素坐标，为空时按当前光标横坐标计算。
  CodeLinePosition? getUpPosition(CodeLinePosition position, {double? preferredDx}) {
    final CodeLineRenderParagraph? paragraph = findDisplayParagraphByLineIndex(position.index);
    if (paragraph == null) {
      return null;
    }
    final Offset? offset = paragraph.getOffset(position.textPosition);
    if (offset == null) {
      return null;
    }
    final double dx = preferredDx ?? offset.dx;
    if (offset.dy > 0) {
      return paragraph.getPosition(Offset(dx, offset.dy - paragraph.preferredLineHeight));
    }
    // The up position is not in this code line
    IParagraph? upParagraph = findDisplayParagraphByLineIndex(position.index - 1)?.paragraph;
    if (upParagraph == null) {
      if (position.index > 0) {
        upParagraph = _buildParagraph(position.index - 1);
      } else {
        return null;
      }
    }
    return CodeLinePosition.from(
      index: position.index - 1,
      position: upParagraph.getPosition(Offset(dx, upParagraph.height - upParagraph.preferredLineHeight))
    );
  }

  /// 下移一行后的光标位置
  ///
  /// [preferredDx] 为纵向移动期间保持的横向像素坐标，为空时按当前光标横坐标计算。
  CodeLinePosition? getDownPosition(CodeLinePosition position, {double? preferredDx}) {
    final CodeLineRenderParagraph? paragraph = findDisplayParagraphByLineIndex(position.index);
    if (paragraph == null) {
      return null;
    }
    final Offset? offset = paragraph.getOffset(position.textPosition);
    if (offset == null) {
      return null;
    }
    final double dx = preferredDx ?? offset.dx;
    if (offset.dy < paragraph.height - paragraph.preferredLineHeight) {
      return paragraph.getPosition(Offset(dx, offset.dy + paragraph.preferredLineHeight));
    }
    // The up position is not in this code line
    IParagraph? downParagraph = findDisplayParagraphByLineIndex(position.index + 1)?.paragraph;
    if (downParagraph == null) {
      if (position.index < _codes.length - 1) {
        downParagraph = _buildParagraph(position.index + 1);
      } else {
        return null;
      }
    }
    return CodeLinePosition.from(
      index: position.index + 1,
      position: downParagraph.getPosition(Offset(dx, 0))
    );
  }

  @override
  MouseCursor get cursor => _cursor;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  @override
  bool get validForMouseTracker => true;

  @override
  bool hitTest(BoxHitTestResult result, { required Offset position }) {
    bool hitTarget = false;
    if (size.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      final CodeLineRenderParagraph? paragraph = _findDisplayRenderParagraph(position + paintOffset);
      final InlineSpan? span = paragraph?.getSpanForPosition(position - paragraph.offset + paintOffset);
      if (span is MouseTrackerAnnotationTextSpan) {
        result.add(HitTestEntry(_MouseTrackerAnnotationTextSpan(
          id: paragraph!.index,
          rects: paragraph.getRangeRects(paragraph.getRangeForSpan(span)).map((rect) {
            return Rect.fromPoints(localToGlobal(rect.topLeft + paragraph.offset - paintOffset), localToGlobal(rect.bottomRight + paragraph.offset - paintOffset));
          }).toList(),
          span: span,
        )));
      } else if (span is HitTestTarget) {
        result.add(HitTestEntry(span as HitTestTarget));
      }
      if (_chunkIndicators.where((chunk) => chunk.canExpand && chunk.region.contains(position)).isNotEmpty) {
        _cursor = SystemMouseCursors.click;
      } else if (span is TextSpan && span.mouseCursor != MouseCursor.defer) {
        _cursor = span.mouseCursor;
      } else {
        _cursor = SystemMouseCursors.text;
      }
      hitTarget = true;
    }
    return hitTarget;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void attach(covariant PipelineOwner owner) {
    super.attach(owner);
    _foregroundRender.attach(owner);
    _backgroundRender.attach(owner);
    _verticalViewport.addListener(markNeedsLayout);
    _horizontalViewport?.addListener(markNeedsPaint);
    _externalScrollController?.addListener(_onExternalScrollChanged);
    _highlighter.addListener(markNeedsLayout);
    _showCursorNotifier.addListener(_onCursorVisibleChanged);
    _floatingCursorNotifier.addListener(_onFloatingCursorChanged);
  }

  @override
  void detach() {
    _verticalViewport.removeListener(markNeedsLayout);
    _horizontalViewport?.removeListener(markNeedsPaint);
    _externalScrollController?.removeListener(_onExternalScrollChanged);
    _highlighter.removeListener(markNeedsLayout);
    _showCursorNotifier.removeListener(_onCursorVisibleChanged);
    _floatingCursorNotifier.removeListener(_onFloatingCursorChanged);
    super.detach();
    _foregroundRender.detach();
    _backgroundRender.detach();
  }

  @override
  void redepthChildren() {
    redepthChild(_foregroundRender);
    redepthChild(_backgroundRender);
    super.redepthChildren();
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    visitor(_foregroundRender);
    visitor(_backgroundRender);
    super.visitChildren(visitor);
  }

  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    _chunkIndicators.clear();
    _backgroundRender.markNeedsPaint();
    _foregroundRender.markNeedsPaint();
  }

  @override
  void performLayout() {
    // _Trace.begin('CodeField performLayout');
    assert(constraints.maxWidth > 0 && constraints.maxWidth != double.infinity,
      '_CodeField should have an explicit width.');
    if (_intrinsic) {
      _performIntrinsicLayout();
      return;
    }
    assert(constraints.maxHeight > 0 && constraints.maxHeight != double.infinity,
      '_CodeField should have an explicit height.');
    size = Size(constraints.maxWidth, constraints.maxHeight);
    _foregroundRender.layout(constraints);
    _backgroundRender.layout(constraints);
    if (_horizontalViewport != null) {
      _horizontalViewport!.applyViewportDimension(size.width);
    }
    _verticalViewport.applyViewportDimension(size.height);
    _updateDisplayRenderParagraphs();
    // _Trace.end('CodeField performLayout');
  }

  /// 是否为自适应高度模式
  ///
  /// 该模式下编辑器高度由内容决定、自身不承载滚动，可见范围取自外部滚动容器。
  bool get _intrinsic => _externalScrollController != null;

  /// 自适应高度布局
  ///
  /// 高度取内容总高（内边距 + 各行排版高度），并按外部滚动偏移只构建可见段落。
  void _performIntrinsicLayout() {
    final double effectiveWidth = constraints.maxWidth - _padding.horizontal;
    final List<double> tops = _ensureLineTops(effectiveWidth);
    size = Size(constraints.maxWidth, paddingTop + tops[_codes.length] + paddingBottom);
    final BoxConstraints childConstraints = BoxConstraints.tight(size);
    _foregroundRender.layout(childConstraints);
    _backgroundRender.layout(childConstraints);
    _updateIntrinsicDisplayParagraphs(effectiveWidth, tops);
  }

  /// 计算各行顶部相对正文顶部的偏移（前缀和）
  ///
  /// 前缀和只由行文本、排版宽度与样式决定：内容或排版参数变化后重建，
  /// 重建时逐行取行高，文本未变化的行直接命中段落缓存，无需重新排版。
  List<double> _ensureLineTops(double effectiveWidth) {
    final List<double>? cached = _lineTops;
    if (cached != null && _lineTopsWidth == effectiveWidth && cached.length == _codes.length + 1) {
      return cached;
    }
    final List<double> tops = List<double>.filled(_codes.length + 1, 0);
    double offset = 0;
    for (int i = 0; i < _codes.length; i++) {
      offset += _buildParagraph(i, effectiveWidth).height;
      tops[i + 1] = offset;
    }
    _lineTops = tops;
    _lineTopsWidth = effectiveWidth;
    return tops;
  }

  /// 按外部滚动偏移刷新可见段落
  void _updateIntrinsicDisplayParagraphs(double effectiveWidth, List<double> tops) {
    final ScrollPosition? position = _externalScrollPosition;
    // 布局过程中外部视口尺寸可能尚未确定，此时先构建全部段落，待下一帧再收敛
    if (position == null || !position.hasViewportDimension) {
      _fillDisplayParagraphs(effectiveWidth, tops, 0, double.infinity);
      _scheduleViewportRetry();
      return;
    }
    _viewportRetryCount = 0;
    // 外部滚动偏移换算到正文坐标系（扣除编辑器在滚动内容中的偏移与顶部内边距）
    final double visibleTop = position.pixels - _externalContentOffset - paddingTop;
    final double visibleBottom = visibleTop + position.viewportDimension;
    final double buffer = _preferredLineHeight * _intrinsicBufferLines;
    final int startIndex = _findLineIndexByOffset(tops, visibleTop - buffer);
    _fillDisplayParagraphs(effectiveWidth, tops, startIndex, visibleBottom + buffer);
  }

  /// 构建指定行区间内的段落
  ///
  /// [endOffset] 与 [_lineTops] 同为正文坐标系下的偏移，超出该偏移的行不再构建。
  void _fillDisplayParagraphs(double effectiveWidth, List<double> tops, int startIndex, double endOffset) {
    _displayParagraphs.clear();
    for (int i = startIndex; i < _codes.length; i++) {
      final double top = tops[i];
      if (top > endOffset) {
        break;
      }
      final IParagraph paragraph = _buildParagraph(i, effectiveWidth);
      _displayParagraphs.add(CodeLineRenderParagraph(
        index: i,
        paragraph: paragraph,
        offset: Offset(paddingLeft, top + paddingTop),
        chunkParent: _codes[i].chunkParent,
        chunkLongText: paragraph.trucated,
      ));
    }
    _onRenderParagraphsChanged(_displayParagraphs.map((e) => e.copyWith(
      offset: Offset(e.offset.dx - (_horizontalViewport?.pixels ?? 0), e.offset.dy)
    )).toList());
  }

  /// 二分查找偏移量所在的行
  ///
  /// [_lineTops] 为升序前缀和，返回最大的 i 使 `tops[i] <= offset`。
  int _findLineIndexByOffset(List<double> tops, double offset) {
    int low = 0;
    int high = tops.length - 1;
    while (low < high) {
      final int mid = (low + high + 1) >> 1;
      if (tops[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// 外部视口尺寸尚未就绪时，下一帧重新布局以收敛到可见范围
  void _scheduleViewportRetry() {
    if (_viewportRetryScheduled || _viewportRetryCount >= _maxViewportRetry) {
      return;
    }
    _viewportRetryScheduled = true;
    _viewportRetryCount++;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _viewportRetryScheduled = false;
      if (attached) {
        markNeedsLayout();
      }
    });
  }

  /// 外部滚动位置
  ///
  /// 滚动视图重建的同一帧内控制器可能短暂挂载新旧两个位置，
  /// 直接读取控制器自身会触发断言，因此取第一个已挂载的位置。
  ScrollPosition? get _externalScrollPosition {
    final ScrollController? controller = _externalScrollController;
    if (controller == null) {
      return null;
    }
    final Iterable<ScrollPosition> positions = controller.positions;
    return positions.isEmpty ? null : positions.first;
  }

  /// 外部滚动时刷新可见段落
  void _onExternalScrollChanged() {
    markNeedsLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // _Trace.begin('CodeField paint');
    context.paintChild(_backgroundRender, offset);

    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height));
    _drawText(canvas, offset);
    canvas.restore();

    _updateSelectionExtentsVisibility(offset);

    context.paintChild(_foregroundRender, offset);

    final Offset? startHandlePosition = calculateTextPositionViewportOffset(_selection.start);
    if (startHandlePosition != null) {
      _drawHandleLayer(context, _startHandleLayerLink, startHandlePosition, offset + Offset(0, _preferredLineHeight));
    }
    final Offset? endHandlePosition = calculateTextPositionViewportOffset(_selection.end);
    if (endHandlePosition != null) {
      _drawHandleLayer(context, _endHandleLayerLink, endHandlePosition, offset + Offset(0, _preferredLineHeight));
    }
    // _Trace.end('CodeField paint');
  }

  @override
  void dispose() {
    _foregroundRender.dispose();
    _backgroundRender.dispose();
    super.dispose();
  }

  CodeLinePosition? calculateTextPosition(Offset localPosition) {
    final Offset offset = localPosition + paintOffset;
    final CodeLineRenderParagraph? target = _findDisplayRenderParagraph(offset, true);
    if (target == null) {
      return null;
    }
    return target.getPosition(offset - target.offset);
  }

  Offset? calculateTextPositionViewportOffset(CodeLinePosition position) {
    final CodeLineRenderParagraph? paragraph = findDisplayParagraphByLineIndex(position.index);
    if (paragraph == null) {
      return null;
    }
    final Offset? offset = paragraph.getOffset(position);
    if (offset == null) {
      return null;
    }
    return offset + paragraph.offset - paintOffset;
  }

  Offset? calculateTextPositionScreenOffset(CodeLinePosition position, bool rightBottom) {
    final Offset? offset = calculateTextPositionViewportOffset(position);
    if (offset != null) {
      return localToGlobal(rightBottom ? offset + Offset(0, _preferredLineHeight) : offset);
    }
    return null;
  }

  void _updateDisplayRenderParagraphs() {
    final double effectiveWidth;
    if (_horizontalViewport == null) {
      effectiveWidth = constraints.maxWidth - _padding.horizontal;
    } else {
      effectiveWidth = double.infinity;
    }
    final double target = _verticalViewport.pixels;
    if (_displayParagraphs.isEmpty) {
      // Move the scroll offset to zero
      final int startIndex;
      if (target <= paddingTop) {
        startIndex = 0;
      } else {
        startIndex = min(((target - paddingTop) / _preferredLineHeight).ceil(), _codes.length - 1);
      }
      _displayParagraphs.addAll(_buildDisplayRenderParagraphs(startIndex, effectiveWidth));
    } else {
      if (_codes.length <= _displayParagraphs.first.index) {
        _displayParagraphs.clear();
        _updateDisplayRenderParagraphs();
        return;
      }
      if (target < _displayParagraphs.first.top) {
        int startIndex = 0;
        double delta = 0;
        double offset = _displayParagraphs.first.top;
        for (int i = _displayParagraphs.first.index - 1; i >= 0; i--) {
          final IParagraph paragraph = _buildParagraph(i, effectiveWidth);
          delta += paragraph.height - _preferredLineHeight;
          offset -= paragraph.height;
          if (target >= offset) {
            startIndex = i;
            break;
          }
        }
        _verticalViewport.correctBy(delta);
        _displayParagraphs.clear();
        _displayParagraphs.addAll(_buildDisplayRenderParagraphs(startIndex, effectiveWidth));
      } else if (target > _displayParagraphs.last.bottom) {
        final int startIndex;
        if (target <= paddingTop) {
          startIndex = 0;
        } else {
          startIndex = (target / _preferredLineHeight).floor();
        }
        _displayParagraphs.clear();
        _displayParagraphs.addAll(_buildDisplayRenderParagraphs(startIndex, effectiveWidth));
      } else {
        int startIndex = -1;
        double delta = 0;
        for (final CodeLineRenderParagraph paragraph in _displayParagraphs) {
          if (target <= paragraph.bottom) {
            startIndex = paragraph.index;
            break;
          }
          delta += paragraph.paragraph.height - _preferredLineHeight;
        }
        assert(startIndex >= 0);
        _verticalViewport.correctBy(-delta);
        _displayParagraphs.clear();
        _displayParagraphs.addAll(_buildDisplayRenderParagraphs(startIndex, effectiveWidth));
      }
    }
    // The codes length maybe changed, this will make the displayParagraphs empty.
    if (_displayParagraphs.isEmpty) {
      _updateDisplayRenderParagraphs();
      return;
    }
    final double totalHeight = _displayParagraphs.last.bottom + (_codes.length - (_displayParagraphs.last.index + 1)) * _preferredLineHeight + paddingBottom;
    _verticalViewportSize = max(0, totalHeight - size.height);
    if (_verticalViewport.pixels > _verticalViewportSize!) {
      _verticalViewport.correctBy(_verticalViewportSize! - _verticalViewport.pixels);
    }
    _verticalViewport.applyContentDimensions(0, _verticalViewportSize!);
    if (_horizontalViewport != null) {
      final double maxWidth = _displayParagraphs.map((e) => e.width).reduce(max);
      _horizontalViewportSize = max(0, maxWidth + _padding.horizontal - size.width);
      _horizontalViewport!.applyContentDimensions(0, _horizontalViewportSize!);
    }
    // applyContentDimensions will change the _verticalViewport.pixels, we should rebuild.
    if (_displayParagraphs.first.offset.dy > _verticalViewport.pixels + paddingTop) {
      _updateDisplayRenderParagraphs();
      return;
    }

    _onRenderParagraphsChanged(_displayParagraphs.map((e) => e.copyWith(
      offset: Offset(e.offset.dx - (_horizontalViewport?.pixels ?? 0) , e.offset.dy - _verticalViewport.pixels)
    )).toList());
  }

  void _drawText(Canvas canvas, Offset offset) {
    if (_displayParagraphs.isEmpty) {
      return;
    }
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    for (final CodeLineRenderParagraph paragraph in _displayParagraphs) {
      final Offset drawOffset = paragraph.offset - paintOffset;
      paragraph.draw(canvas, drawOffset);
      _drawChunkIndicatorIfNeeded(canvas, paragraph, drawOffset);
    }
    canvas.restore();
  }

  void _drawChunkIndicatorIfNeeded(Canvas canvas, CodeLineRenderParagraph paragraph, Offset offset) {
    if (!paragraph.chunkParent && !paragraph.chunkLongText) {
      return;
    }
    final Color? chunkIndicatorColor = _chunkIndicatorColor ?? _textStyle.color?.withAlpha(128);
    if (chunkIndicatorColor == null || chunkIndicatorColor == Colors.transparent) {
      return;
    }
    final Offset? end = paragraph.getOffset(TextPosition(offset: paragraph.length));
    if (end == null) {
      return;
    }
    final Rect region = _drawChunkIndicator(canvas, chunkIndicatorColor, offset + end);
    _chunkIndicators.add(_CodeChunkIndicator(region, paragraph.index, paragraph.chunkParent));
  }

  Rect _drawChunkIndicator(Canvas canvas, Color color, Offset offset) {
    _paint.color = color;
    final double dy = _preferredLineHeight / 2 + 1;
    const double radius = 1;
    const double start = 3;
    const double interval = 3;
    canvas.drawCircle(offset + Offset(start, dy), radius, _paint);
    canvas.drawCircle(offset + Offset(start + interval, dy), radius, _paint);
    canvas.drawCircle(offset + Offset(start + interval * 2, dy), radius, _paint);
    return Rect.fromLTWH(offset.dx + start - radius, offset.dy, start + interval * 2 + radius, _preferredLineHeight);
  }

  void _drawHandleLayer(PaintingContext context, LayerLink layer, Offset position, Offset offset) {
    final Offset point = Offset(
      clampDouble(position.dx, 0.0, size.width),
      clampDouble(position.dy, 0.0, size.height),
    );
    context.pushLayer(
      LeaderLayer(link: layer, offset: point + offset),
      super.paint,
      Offset.zero,
    );
  }

  void _updateSelectionExtentsVisibility(Offset effectiveOffset) {
    if (!kIsAndroid && !kIsIOS) {
      return;
    }
    final Rect visibleRegion = Offset.zero & size;
    // Check if the selection is visible with an approximation because a
    // difference between rounded and unrounded values causes the caret to be
    // reported as having a slightly (< 0.5) negative y offset. This rounding
    // happens in paragraph.cc's layout and TextPainter's
    // _applyFloatingPointHack. Ideally, the rounding mismatch will be fixed and
    // this can be changed to be a strict check instead of an approximation.
    const double visibleRegionSlop = 0.5;
    final Offset? startOffset = calculateTextPositionViewportOffset(_selection.start);
    if (startOffset == null) {
      _selectionStartInViewport.value = false;
    } else {
      _selectionStartInViewport.value = visibleRegion
        .inflate(visibleRegionSlop)
        .contains(startOffset);
    }
    final Offset? endOffset = calculateTextPositionViewportOffset(_selection.end);
    if (endOffset == null) {
      _selectionEndInViewport.value = false;
    } else {
      _selectionEndInViewport.value = visibleRegion
        .inflate(visibleRegionSlop)
        .contains(endOffset.dy < 0 ? endOffset : endOffset + Offset(0, _preferredLineHeight));
    }
  }

  void _calculatePreferredLineHeight() {
    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    painter.text = TextSpan(
      text: '0',
      style: _textStyle,
    );
    _preferredLineHeight = painter.preferredLineHeight;
    _foregroundRender.find<_CodeFieldCursorPainter>().height = painter.preferredLineHeight;
    _foregroundRender.find<_CodeFieldFloatingCursorPainter>().height = painter.preferredLineHeight;
  }

  void _onCursorVisibleChanged() {
    _foregroundRender.find<_CodeFieldCursorPainter>().visible = _showCursorNotifier.value;
  }

  void _onFloatingCursorChanged() {
    _foregroundRender.find<_CodeFieldFloatingCursorPainter>().position = _floatingCursorNotifier.value;
  }

  bool isValidPointer(Offset localPosition) {
    if (localPosition.dx <= 0 || localPosition.dx >= size.width - _verticalScrollbarWidth) {
      return false;
    }
    if (localPosition.dy <= 0) {
      return false;
    }
    if (localPosition.dy >= size.height - ((_horizontalViewportSize ?? -1) <= 0 ? 0 : _horizontalScrollbarHeight)) {
      return false;
    }
    return true;
  }

  bool isValidPointer2(Offset globalPosition) {
    final Offset localPosition = globalToLocal(globalPosition);
    return isValidPointer(localPosition);
  }

  CodeLineRange? _selectWord(Offset localPosition) {
    final Offset offset = localPosition + paintOffset;
    final CodeLineRenderParagraph? target = _findDisplayRenderParagraph(offset);
    if (target == null) {
      return null;
    }
    final CodeLineRange range = target.getWord(offset - target.offset);
    if (range.isCollapsed) {
      return null;
    }
    return range;
  }

  CodeLineRenderParagraph? _findDisplayRenderParagraph(Offset offset, [bool canOverflow = false]) {
    for (final CodeLineRenderParagraph paragraph in _displayParagraphs) {
      if (paragraph.inVerticalRange(offset)) {
        return paragraph;
      }
    }
    if (canOverflow && _displayParagraphs.isNotEmpty) {
      final CodeLineRenderParagraph top = _displayParagraphs.first;
      if (offset.dy <= top.bottom) {
        return top;
      }
      final CodeLineRenderParagraph bottom = _displayParagraphs.last;
      if (offset.dy >= bottom.top) {
        return bottom;
      }
    }
    return null;
  }

  void _alignTopEdge({
    double? offset
  }) {
    final double position = offset ?? _verticalViewport.pixels;
    if (position < paddingTop) {
      _verticalViewport.jumpTo(max(position, 0));
    } else {
      final double scroll = position ~/ _preferredLineHeight * _preferredLineHeight + paddingTop;
      if (scroll < _verticalViewport.pixels) {
        _verticalViewport.jumpTo(scroll);
      }
    }
  }

  void _alignBottomEdge({
    double? offset
  }) {
    final double? viewportMax = _verticalViewportSize;
    if (viewportMax == null) {
      return;
    }
    final double position = offset ?? _verticalViewport.pixels;
    if (position > viewportMax - paddingBottom) {
      _verticalViewport.jumpTo(min(position, viewportMax));
    } else {
      final double delta = (size.height / _preferredLineHeight).ceil() * _preferredLineHeight - size.height;
      final double scroll = position ~/ _preferredLineHeight * _preferredLineHeight + delta + paddingTop;
      if (scroll > _verticalViewport.pixels) {
        _verticalViewport.jumpTo(min(scroll, viewportMax));
      }
    }
  }

  List<CodeLineRenderParagraph> _buildDisplayRenderParagraphs(int startIndex, double maxWidth) {
    double offset = startIndex * _preferredLineHeight;
    final List<CodeLineRenderParagraph> paragraphs = [];
    for (int i = startIndex; i < _codes.length; i++) {
      final IParagraph paragraph = _buildParagraph(i, maxWidth);
      _displayParagraphs.add(CodeLineRenderParagraph(
        index: i,
        paragraph: paragraph,
        offset: Offset(paddingLeft, offset + paddingTop),
        chunkParent: _codes[i].chunkParent,
        chunkLongText: paragraph.trucated,
      ));
      offset += paragraph.height;
      if (offset + paddingTop >= _verticalViewport.pixels + size.height) {
        break;
      }
    }
    return paragraphs;
  }

  IParagraph _buildParagraph(int index, [double? maxWidth]) {
    return _highlighter.build(
      index: index,
      style: _textStyle,
      maxWidth: maxWidth ?? (_horizontalViewport == null ? size.width - padding.horizontal : double.infinity),
      maxLengthSingleLineRendering: _maxLengthSingleLineRendering,
    );
  }

}

class _CodeChunkIndicator {

  final Rect region;
  final int index;
  final bool canExpand;

  const _CodeChunkIndicator(this.region, this.index, this.canExpand);
}

abstract class _CodeFieldExtraPainter extends ChangeNotifier {

  void paint(Canvas canvas, Size size, _CodeFieldRender render);

}

class _CodeFieldExtraRender extends RenderBox {

  final List<_CodeFieldExtraPainter> painters;

  _CodeFieldExtraRender({
    required this.painters
  });

  @override
  _CodeFieldRender? get parent => super.parent as _CodeFieldRender?;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final _CodeFieldRender? parent = this.parent;
    assert(parent != null);
    // _Trace.begin('CodeField ExtraRender');
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height));
    for (final _CodeFieldExtraPainter painter in painters) {
      painter.paint(context.canvas, size, parent!);
    }
    canvas.restore();
    // _Trace.end('CodeField ExtraRender');
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final _CodeFieldExtraPainter painter in painters) {
      painter.addListener(markNeedsPaint);
    }
  }

  @override
  void detach() {
    for (final _CodeFieldExtraPainter painter in painters) {
      painter.removeListener(markNeedsPaint);
    }
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  T find<T extends _CodeFieldExtraPainter>() {
    T? result;
    for (final _CodeFieldExtraPainter painter in painters) {
      if (painter is T) {
        result = painter;
        break;
      }
    }
    assert(result != null, 'Failed to find $T');
    return result!;
  }
}

class _CodeCursorLinePainter extends _CodeFieldExtraPainter {

  final Paint _paint;
  Color? _color;
  CodeLineSelection _selection;

  _CodeCursorLinePainter(this._color, this._selection) : _paint = Paint() {
    _paint
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  }

  set color(Color? value) {
    if (_color == value) {
      return;
    }
    _color = value;
    notifyListeners();
  }

  set selection(CodeLineSelection value) {
    if (_selection == value) {
      return;
    }
    _selection = value;
    notifyListeners();
  }

  @override
  void paint(Canvas canvas, Size size, _CodeFieldRender render) {
    if (_color == null || _color == Colors.transparent || _color!.alpha == 0) {
      return;
    }
    if (!_selection.isCollapsed) {
      return;
    }
    final CodeLineRenderParagraph? paragraph = render.findDisplayParagraphByLineIndex(_selection.extentIndex);
    if (paragraph == null) {
      return;
    }
    Offset? offset = paragraph.getOffset(_selection.extent);
    if (offset == null) {
      return;
    }
    offset += paragraph.offset - render.paintOffset;
    if (offset.dy + paragraph.preferredLineHeight < 0 || offset.dy >= size.height) {
      return;
    }
    _paint.color = _color!;
    canvas.drawLine(Offset(0, offset.dy), Offset(size.width, offset.dy), _paint);
    canvas.drawLine(Offset(0, offset.dy + paragraph.preferredLineHeight),
      Offset(size.width, offset.dy + paragraph.preferredLineHeight), _paint);
  }

}

abstract class _CodeFieldSelectionsPainter extends _CodeFieldExtraPainter {

  static const Offset _newLinePadding = Offset(5.0, 0.0);

  final Paint _paint;
  Color _color;
  List<CodeLineSelection> _selections;

  _CodeFieldSelectionsPainter(this._color, this._selections) : _paint = Paint();

  set color(Color value) {
    if (_color == value) {
      return;
    }
    _color = value;
    notifyListeners();
  }

  set selections(List<CodeLineSelection> value) {
    if (listEquals(_selections, value)) {
      return;
    }
    _selections = value;
    notifyListeners();
  }

  @override
  void paint(Canvas canvas, Size size, _CodeFieldRender render) {
    if (_color == Colors.transparent || _color.alpha == 0) {
      return;
    }
    final List<CodeLineRenderParagraph> paragraphs = render.displayParagraphs;
    if (paragraphs.isEmpty) {
      return;
    }
    for (final CodeLineSelection selection in _selections) {
      if (selection.isCollapsed) {
        continue;
      }
      // 记录上一个已绘制矩形的底边（画布坐标），用于衔接相邻行
      double? previousBottom;
      int startIndex;
      int endIndex;
      for (final CodeLineRenderParagraph paragraph in paragraphs) {
        final CodeLinePosition start = selection.start;
        final CodeLinePosition end = selection.end;
        if (paragraph.index < start.index || paragraph.index > end.index) {
          continue;
        }
        if (paragraph.index == start.index) {
          startIndex = start.offset;
        } else {
          startIndex = 0;
        }
        if (paragraph.index == end.index) {
          endIndex = end.offset;
        } else {
          endIndex = paragraph.length;
        }
        final List<Rect> rects;
        if (startIndex == endIndex) {
          final Offset? offset = paragraph.getOffset(TextPosition(offset: startIndex));
          if (offset == null) {
            rects = const [];
          } else {
            rects = [
              Rect.fromLTWH(offset.dx, offset.dy, 0, paragraph.preferredLineHeight)
            ];
          }
        } else {
          rects = paragraph.getRangeRects(TextRange(
            start: startIndex,
            end: endIndex
          ));
        }
        if (rects.isEmpty) {
          continue;
        }
        final Offset paragraphOffset = paragraph.offset - render.paintOffset;
        for (final Rect rect in rects) {
          // 逐行排版时字符盒的高度略小于行高，相邻行（含自动换行的视觉行）的矩形之间会残留细缝，
          // 将当前矩形顶边上移到上一行的底边，使两行衔接处不留空白
          Rect current = rect;
          final double? bottom = previousBottom;
          if (bottom != null && current.top + paragraphOffset.dy > bottom) {
            current = Rect.fromLTRB(
              current.left,
              bottom - paragraphOffset.dy,
              current.right,
              current.bottom
            );
          }
          previousBottom = current.bottom + paragraphOffset.dy;
          if (rect == rects.last && paragraph.index < end.index) {
            _drawRect(canvas, Rect.fromPoints(current.topLeft, current.bottomRight + _newLinePadding),
              paragraphOffset);
          } else if (!current.isEmpty) {
            _drawRect(canvas, current, paragraphOffset);
          }
        }
      }
    }
  }

  void _drawRect(Canvas canvas, Rect rect, Offset offset) {
    _paint.color = _color;
    canvas.drawRect(Rect.fromPoints(rect.topLeft + offset, rect.bottomRight + offset), _paint);
  }

}

class _CodeFieldSelectionPainter extends _CodeFieldSelectionsPainter {

  _CodeFieldSelectionPainter(Color color, CodeLineSelection selection) :
    super(color, [selection]);

  set selection(CodeLineSelection value) {
    selections = [value];
  }

}

class _CodeFieldHighlightPainter extends _CodeFieldSelectionsPainter {

  _CodeFieldHighlightPainter(super.color, super.selections);

}

class _CodeFieldCursorPainter extends _CodeFieldExtraPainter {

  final Paint _paint;
  CodeLinePosition _position;
  Color _color;
  double _width;
  double _height;
  bool _visible;
  bool _willDraw;

  _CodeFieldCursorPainter({
    required CodeLinePosition position,
    required Color color,
    required double width,
    required double height,
    required bool visible,
  }) : _position = position,
    _color = color,
    _width = width,
    _height = height,
    _visible = visible,
    _willDraw = true,
    _paint = Paint();

  set position(CodeLinePosition value) {
    if (_position == value) {
      return;
    }
    _position = value;
    notifyListeners();
  }

  set color(Color value) {
    if (_color == value) {
      return;
    }
    _color = value;
    notifyListeners();
  }

  double get width => _width;

  set width(double value) {
    if (_width == value) {
      return;
    }
    _width = value;
    notifyListeners();
  }

  set height(double value) {
    if (_height == value) {
      return;
    }
    _height = value;
    notifyListeners();
  }

  set visible(bool value) {
    if (_visible == value) {
      return;
    }
    _visible = value;
    notifyListeners();
  }

  set willDraw(bool value) {
    if (_willDraw == value) {
      return;
    }
    _willDraw = value;
    notifyListeners();
  }

  @override
  void paint(Canvas canvas, Size size, _CodeFieldRender render) {
    if (!_visible || !_willDraw || _color == Colors.transparent || _color.alpha == 0) {
      return;
    }
    final CodeLineRenderParagraph? paragraph = render.findDisplayParagraphByLineIndex(_position.index);
    if (paragraph == null) {
      return;
    }
    Offset? offset = paragraph.getOffset(_position);
    if (offset == null) {
      return;
    }
    offset += paragraph.offset - render.paintOffset;
    if (offset.dx + _width < 0 || offset.dx >= size.width || offset.dy + _height < 0 || offset.dy >= size.height) {
      return;
    }
    _drawCaret(canvas, offset, size);
  }

  void _drawCaret(Canvas canvas, Offset offset, Size size) {
    _paint.color = _color;
    canvas.drawRRect(RRect.fromRectXY(Rect.fromLTWH(offset.dx - _width / 2, offset.dy, _width, _height), _width / 2, _width / 2), _paint);
  }

}

class _CodeFieldFloatingCursorPainter extends _CodeFieldExtraPainter {

  final Paint _paint;
  _FloatingCursorState _position;
  Color _color;
  double _width;
  double _height;

  _CodeFieldFloatingCursorPainter({
    required _FloatingCursorState position,
    required Color color,
    required double width,
    required double height,
  }) : _position = position,
    _color = color,
    _width = width,
    _height = height,
    _paint = Paint();

  set position(_FloatingCursorState value) {
    if (_position == value) {
      return;
    }
    _position = value;
    notifyListeners();
  }

  set color(Color value) {
    if (_color == value) {
      return;
    }
    _color = value;
    notifyListeners();
  }

  double get width => _width;

  set width(double value) {
    if (_width == value) {
      return;
    }
    _width = value;
    notifyListeners();
  }

  double get height => _height;

  set height(double value) {
    if (_height == value) {
      return;
    }
    _height = value;
    notifyListeners();
  }

  @override
  void paint(Canvas canvas, Size size, _CodeFieldRender render) {
    if (!_position.isActive() || _color == Colors.transparent || _color.alpha == 0) {
      return;
    }
    _drawFloatingCaret(canvas, _position.floatingCursorOffset!, size);
    if (_position.previewCursorOffset != null) {
      _drawPreviewCursor(canvas, _position.previewCursorOffset!, size);
    }
  }

  void _drawFloatingCaret(Canvas canvas, Offset offset, Size size) {
    final caretRect = RRect.fromRectXY(
      Rect.fromLTWH(offset.dx - _width / 2, offset.dy, _width, _height),
      _width / 2,
      _width / 2,
    );
    final path = Path()..addRRect(caretRect);

    canvas.drawShadow(
      path,
      Colors.black,
      4.0,
      true,
    );

    _paint.color = _color;
    canvas.drawRRect(RRect.fromRectXY(Rect.fromLTWH(offset.dx - _width / 2, offset.dy, _width, _height), _width / 2, _width / 2), _paint);
  }

  void _drawPreviewCursor(Canvas canvas, Offset offset, Size size) {
    _paint.color = _color.withAlpha(150);
    canvas.drawRRect(RRect.fromRectXY(Rect.fromLTWH(offset.dx - _width / 2, offset.dy, _width, _height), _width / 2, _width / 2), _paint);
  }

}
