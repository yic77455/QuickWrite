part of re_editor;

class _CodeInputController extends ChangeNotifier implements DeltaTextInputClient {

  CodeLineEditingController _controller;
  FocusNode _focusNode;
  bool _readOnly;
  bool _autocompleteSymbols;

  /// 自动补全使用的成对符号，为空时沿用内置符号表
  List<CodeSymbolPair>? _autocompletePairs;

  /// 外部换行处理，为空时使用控制器默认换行
  VoidCallback? _newLineHandler;

  bool _updateCausedByFloatingCursor;
  late Offset _floatingCursorStartingOffset;

  TextInputConnection? _textInputConnection;
  TextEditingValue? _remoteEditingValue;

  final _CodeFloatingCursorController _floatingCursorController;
  Timer? _floatingCursorScrollTimer;

  GlobalKey? _editorKey;

  _CodeInputController({
    required CodeLineEditingController controller,
    required _CodeFloatingCursorController floatingCursorController,
    required FocusNode focusNode,
    required bool readOnly,
    required bool autocompleteSymbols,
    List<CodeSymbolPair>? autocompletePairs,
    VoidCallback? newLineHandler,
  }) : _controller = controller,
    _floatingCursorController = floatingCursorController,
    _focusNode = focusNode,
    _readOnly = readOnly,
    _updateCausedByFloatingCursor = false,
    _autocompleteSymbols = autocompleteSymbols,
    _autocompletePairs = autocompletePairs,
    _newLineHandler = newLineHandler {
    _controller.addListener(_onCodeEditingChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void bindEditor(GlobalKey key) {
    _editorKey = key;
  }

  set controller(CodeLineEditingController value) {
    if (_controller == value) {
      return;
    }
    _controller.removeListener(_onCodeEditingChanged);
    _controller = value;
    _controller.addListener(_onCodeEditingChanged);
    _onCodeEditingChanged();
  }

  set focusNode(FocusNode value) {
    if (_focusNode == value) {
      return;
    }
    _focusNode.removeListener(_onFocusChanged);
    _focusNode = value;
    _focusNode.addListener(_onFocusChanged);
  }

  set readOnly(bool value) {
    if (_readOnly == value) {
      return;
    }
    _readOnly = value;
  }

  set autocompleteSymbols(bool value) {
    if (_autocompleteSymbols == value) {
      return;
    }
    _autocompleteSymbols = value;
  }

  set autocompletePairs(List<CodeSymbolPair>? value) {
    if (listEquals(_autocompletePairs, value)) {
      return;
    }
    _autocompletePairs = value;
  }

  set newLineHandler(VoidCallback? value) {
    if (_newLineHandler == value) {
      return;
    }
    _newLineHandler = value;
  }

  /// 执行换行
  ///
  /// 移动端软键盘的换行不经过快捷键机制，非空时交由外部换行处理接管，
  /// 使移动端与桌面端共用同一套换行规则；为空时使用控制器默认换行。
  void applyNewLine() {
    final VoidCallback? handler = _newLineHandler;
    if (handler != null) {
      handler();
    } else {
      _controller.applyNewLine();
    }
  }

  set value(CodeLineEditingValue value) {
    _controller.value = value;
  }

  CodeLineEditingValue get value => _controller.value;

  set codeLines(CodeLines value) {
    _controller.codeLines = value.isEmpty ? _kInitialCodeLines : value;
  }

  CodeLines get codeLines => _controller.codeLines;

  set selection(CodeLineSelection value) => _controller.selection = value;

  CodeLineSelection get selection => _controller.selection;

  set composing(TextRange value) => _controller.composing = value;

  TextRange get composing => _controller.composing;

  @override
  void connectionClosed() {
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue => _buildTextEditingValue();

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) {
      // Fix issue #42, iOS will insert duplicate new lines.
      // We only do this on Android.
      if (kIsAndroid) {
        applyNewLine();
      }
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
  }

  @override
  void showToolbar() {
  }

  @override
  void insertTextPlaceholder(Size size) {
  }

  @override
  void removeTextPlaceholder() {
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if (_updateCausedByFloatingCursor) {
      // This is necessary because otherwise the content of the line where the floating cursor was started
      // will be pasted over to the line where the floating cursor was stopped.
      _updateCausedByFloatingCursor = false;
      return;
    }

    if (textEditingDeltas.any((delta) => delta is TextEditingDeltaInsertion && delta.textInserted == '\n')) {
      TextEditingValue newValue = _remoteEditingValue!;
      for (final TextEditingDelta delta in textEditingDeltas) {
        newValue = delta.apply(newValue);
      }
      _remoteEditingValue = newValue;
      applyNewLine();
      return;
    }

    // _Trace.begin('updateEditingValue all');
    TextEditingValue newValue = _remoteEditingValue!;
    bool smartChange = false;
    for (final TextEditingDelta delta in textEditingDeltas) {
      if (_autocompleteSymbols) {
        TextEditingDelta newDelta = _SmartTextEditingDelta(delta, _autocompletePairs).apply(selection);
        if (newDelta != delta) {
          smartChange = true;
        }
        newValue = newDelta.apply(newValue);
      } else {
        newValue = delta.apply(newValue);
      }
    }
    if (newValue == _remoteEditingValue) {
      return;
    }
    // 输入法若已改写镜像文本，说明本次变更携带有实际输入内容
    final bool textChanged = smartChange || newValue.text != _remoteEditingValue!.text;
    // 本次光标在镜像中移动的步数，用于区分方向键与输入法的行首行尾操作
    final int caretMove = newValue.selection.start - _remoteEditingValue!.selection.start;
    if (!smartChange) {
      _remoteEditingValue = newValue;
    }
    // print('update text ${newValue.text}');
    // print('update selection ${newValue.selection}');
    // print('update composing ${newValue.composing}');
    if (newValue.usePrefix) {
      if (_handleCursorBeyondMirror(newValue, textChanged: textChanged, caretMove: caretMove)) {
        return;
      }
      if (newValue.selection.isCollapsed && newValue.selection.start == 0) {
        _controller.deleteBackward();
      } else {
        _controller.edit(newValue.removePrefixIfNecessary().removeSuffixIfNecessary());
      }
    } else {
      _controller.edit(newValue);
    }
    notifyListeners();
    // _Trace.end('updateEditingValue all');
  }

  /// 处理光标越过镜像两端零宽哨兵的选区变更
  ///
  /// 光标越过哨兵时镜像文本没有变化，表示输入法把光标移出了镜像：
  /// 单步越过哨兵对应方向键，跨多步越过对应输入法的行首行尾操作。
  /// 返回是否已处理本次变更，未处理时仍按普通选区变更处理。
  bool _handleCursorBeyondMirror(TextEditingValue value, {
    required bool textChanged,
    required int caretMove,
  }) {
    if (textChanged || !value.usePrefix || !value.selection.isCollapsed) {
      return false;
    }
    if (value.selection.start == 0) {
      if (caretMove == -1) {
        // 光标在行首继续左移，移至上一行行尾
        _controller.moveCursor(AxisDirection.left);
      } else {
        // 输入法把光标移至行首
        selection = CodeLineSelection.collapsed(
          index: selection.extentIndex,
          offset: 0
        );
        _controller.makeCursorCenterIfInvisible();
      }
      return true;
    }
    if (value.selection.start == value.text.length) {
      if (caretMove == 1) {
        // 光标在行尾继续右移，移至下一行行首
        _controller.moveCursor(AxisDirection.right);
      } else {
        // 输入法把光标移至行尾
        selection = CodeLineSelection.collapsed(
          index: selection.extentIndex,
          offset: codeLines[selection.extentIndex].length
        );
        _controller.makeCursorCenterIfInvisible();
      }
      return true;
    }
    return false;
  }

  @override
  void updateEditingValue(TextEditingValue textEditingValue) {
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    _updateCausedByFloatingCursor = true;
    final _CodeFieldRender? render = _editorKey?.currentContext?.findRenderObject() as _CodeFieldRender?;
    if (render == null) {
      return;
    }
    switch(point.state) {
      case FloatingCursorDragState.Start:
        _floatingCursorStartingOffset = render.calculateTextPositionViewportOffset(selection.base)!;
        _floatingCursorController.setFloatingCursorPositions(
          floatingCursorOffset: _floatingCursorStartingOffset,
          finalCursorSelection: selection,
        );
        break;
      case FloatingCursorDragState.Update:
        final Offset updatedOffset = _floatingCursorStartingOffset + point.offset!;

        final double topBound = render.paintBounds.top + render.paddingTop;
        final double leftBound = render.paintBounds.left + render.paddingLeft;
        final double bottomBound = render.paintBounds.bottom - render.paddingBottom - render.floatingCursorHeight;
        final double rightBound = render.paintBounds.right - render.paddingRight;

        // Clamp the offset coordinates to the paint bounds
        Offset clampedUpdatedOffset = Offset(
          updatedOffset.dx.clamp(leftBound, rightBound),
          updatedOffset.dy.clamp(topBound, bottomBound),
        );

        // An adjustment is made on the y-axis so that whenever it is in between lines, the line where the center
        // of the floating cursor is will be selected.
        Offset adjustedClampedUpdatedOffset = clampedUpdatedOffset + Offset(0, render.floatingCursorHeight / 2);
        final CodeLinePosition newPosition = render.calculateTextPosition(adjustedClampedUpdatedOffset)!;

        // The offset at which the actual cursor would end up if floating cursor was terminated now.
        final Offset? snappedNewOffset = render.calculateTextPositionViewportOffset(newPosition);

        CodeLineSelection newSelection = CodeLineSelection.fromPosition(position: newPosition);


        if (clampedUpdatedOffset != updatedOffset) {
          // When the cursor is at one of the edges, adjust the starting offset so that the floating cursor
          // does not get "loose" when starting to move in the opposite direction.
          _floatingCursorStartingOffset += clampedUpdatedOffset - updatedOffset;
        }

        if (clampedUpdatedOffset.dy == topBound || clampedUpdatedOffset.dy == bottomBound || clampedUpdatedOffset.dx == rightBound || clampedUpdatedOffset.dx == leftBound) {
          _floatingCursorScrollTimer ??= Timer.periodic(const Duration(milliseconds: 50), (timer) {
            render.autoScrollWhenDraggingFloatingCursor(clampedUpdatedOffset);
            final CodeLinePosition newPos = render.calculateTextPosition(adjustedClampedUpdatedOffset)!;
            final Offset? snappedNewOffset = render.calculateTextPositionViewportOffset(newPos);

            // This step ensures that the preview cursor will keep updating when scrolling
            if (adjustedClampedUpdatedOffset.dx > snappedNewOffset!.dx + render.textStyle.fontSize!) {
              _floatingCursorController.updatePreviewCursorOffset(snappedNewOffset);
            }
            else {
              _floatingCursorController.updatePreviewCursorOffset(null);
            }
          });
        }
        else {
          if (_floatingCursorScrollTimer != null) {
            _floatingCursorScrollTimer!.cancel();
            _floatingCursorScrollTimer = null;
          }
        }

        // Only turn on the preview cursor if we are away from the end of the line (relatively to the font size)
        if (adjustedClampedUpdatedOffset.dx > snappedNewOffset!.dx + render.textStyle.fontSize!) {
          _floatingCursorController.setFloatingCursorPositions(
            floatingCursorOffset: clampedUpdatedOffset,
            previewCursorOffset: snappedNewOffset,
            finalCursorOffset: snappedNewOffset,
            finalCursorSelection:newSelection
          );
        }
        else {
          _floatingCursorController.setFloatingCursorPositions(
            floatingCursorOffset: clampedUpdatedOffset,
            finalCursorOffset: snappedNewOffset,
            finalCursorSelection: newSelection
          );
        }

        break;
      case FloatingCursorDragState.End:
        if (_floatingCursorScrollTimer != null) {
          _floatingCursorScrollTimer!.cancel();
          _floatingCursorScrollTimer = null;
        }
        selection = _floatingCursorController.value.finalCursorSelection!;
        final CodeLinePosition finalPosition = CodeLinePosition(
          index: selection.baseIndex,
          offset: selection.baseOffset,
          affinity: selection.baseAffinity);

        final Offset? finalOffset = render.calculateTextPositionViewportOffset(finalPosition);

        // If the final selection is in not the viewport, make it visible without animating the floating cursor.
        // Otherwise, play the floating cursor reset animation.
        if (finalOffset != null && (finalOffset.dx < 0 || finalOffset.dy < 0)) {
          render.makePositionCenterIfInvisible(
            CodeLinePosition(
              index: selection.baseIndex,
              offset: selection.baseOffset,
              affinity: selection.baseAffinity),
            animated: true);
            _floatingCursorController.disableFloatingCursor();
        }
        else {
          _floatingCursorController.animateDisableFloatingCursor();
        }


    }
  }

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
  }

  @override
  void performSelector(String selectorName) {
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
  }

  bool onFocusReceived() => false;

  void ensureInput() {
    if (_focusNode.hasFocus) {
      if (!_readOnly) {
        _openInputConnection();
      }
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  void notifyListeners() {
    // Do nothing here.
    super.notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    _closeInputConnectionIfNeeded();
    _controller.removeListener(_onCodeEditingChanged);
    _focusNode.removeListener(_onFocusChanged);
  }

  bool get _hasInputConnection => _textInputConnection?.attached ?? false;

  void _onCodeEditingChanged() {
    _updateRemoteEditingValueIfNeeded();
    _updateRemoteComposingIfNeeded();
  }

  void _updateRemoteEditingValueIfNeeded() {
    if (!_hasInputConnection) {
      return;
    }
    TextEditingValue localValue = _buildTextEditingValue();
    if (localValue == _remoteEditingValue) {
      return;
    }
    if (localValue.composing.isValid && max(localValue.composing.start, localValue.composing.end) > localValue.text.length) {
      localValue = localValue.copyWith(
        composing: TextRange.empty
      );
    }
    // print('post text ${localValue.text}');
    // print('post selection ${localValue.selection}');
    // print('post composing ${localValue.composing}');
    _remoteEditingValue = localValue;

    _textInputConnection!.setEditingState(localValue);
  }

  void _updateRemoteComposingIfNeeded({
    bool retry = false
  }) {
    if (!_hasInputConnection) {
      return;
    }
    final _CodeFieldRender? render = _editorKey?.currentContext?.findRenderObject() as _CodeFieldRender?;
    if (render == null) {
      return;
    }
    final TextRange composing = _remoteEditingValue?.composing ?? TextRange.empty;
    Offset? composingStart;
    // 仅在存在实际组合文本时上报组合区域；
    // 无效组合范围换算出的坐标会落在行首，干扰输入法窗口的定位
    if (composing.isValid && !composing.isCollapsed) {
      composingStart = render.calculateTextPositionViewportOffset(selection.base.copyWith(
        offset: composing.start
      ));
      final Offset? composingEnd = render.calculateTextPositionViewportOffset(selection.extent.copyWith(
        offset: composing.end
      ));
      if (composingStart != null && composingEnd != null) {
        _textInputConnection!.setComposingRect(Rect.fromPoints(composingStart, composingEnd + Offset(0, render.lineHeight)));
      }
    }
    final Offset? caret = render.calculateTextPositionViewportOffset(selection.base) ?? composingStart;
    if (caret != null) {
      _textInputConnection!.setCaretRect(Rect.fromLTWH(caret.dx, caret.dy, render.cursorWidth, render.lineHeight));
    } else if (!retry) {
      Future.delayed(const Duration(milliseconds: 10), () {
        _updateRemoteComposingIfNeeded(
          retry: true
        );
      });
    }
  }

  void _updateRemoteEditableSizeAndTransform() {
    if (!_hasInputConnection) {
      return;
    }
    final _CodeFieldRender? render = _editorKey?.currentContext?.findRenderObject() as _CodeFieldRender?;
    if (render == null || !render.hasSize) {
      return;
    }
    _textInputConnection!.setEditableSizeAndTransform(render.size, render.getTransformTo(null));
  }

  void _onFocusChanged() {
    _openOrCloseInputConnectionIfNeeded();
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (_focusNode.hasFocus && !_readOnly) {
      if (_focusNode.consumeKeyboardToken()) {
        _openInputConnection();
      }
    } else {
      _closeInputConnectionIfNeeded();
      _controller.clearComposing();
    }
  }

  void _openInputConnection() {
    final BuildContext? context = _editorKey?.currentContext;
    if (context == null) {
      return;
    }
    if (!_hasInputConnection) {
      // Fix PlatformException issue on new flutter version.
      // See https://github.com/reqable/re-editor/issues/83
      final TextInputConnection connection = TextInput.attach(this,
        _TextInputConfiguration(
          flutterViewId: View.maybeOf(context)?.viewId ?? 0,
          enableDeltaModel: true,
          inputAction: TextInputAction.newline,
          autocorrect: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          textCapitalization: TextCapitalization.none,
          keyboardAppearance: Theme.of(context).brightness,
        ),
      );
      _remoteEditingValue = _buildTextEditingValue();
      connection.setEditingState(_remoteEditingValue!);
      connection.show();
      _textInputConnection = connection;
    } else {
      _textInputConnection?.show();
    }
    _updateRemoteComposingIfNeeded();
    _updateRemoteEditableSizeAndTransform();
  }

  void _closeInputConnectionIfNeeded() {
    if (_hasInputConnection) {
      _textInputConnection!.close();
    }
    _textInputConnection = null;
  }

  /// 构建推送给输入法的镜像文本
  ///
  /// 镜像只包含光标所在行的文本，移动端额外在镜像两端追加零宽哨兵，
  /// 使输入法方向键在行首与行尾仍有移动余量。
  TextEditingValue _buildTextEditingValue() {
    final TextSelection textSelection;
    if (selection.isSameLine) {
      textSelection = TextSelection(
        baseOffset: selection.baseOffset,
        extentOffset: selection.extentOffset
      );
    } else {
      if (selection.baseIndex < selection.extentIndex) {
        textSelection = TextSelection(
          baseOffset: selection.baseOffset,
          extentOffset: codeLines[selection.baseIndex].length
        );
      } else {
        textSelection = TextSelection(
          baseOffset: 0,
          extentOffset: selection.baseOffset
        );
      }
    }
    return TextEditingValue(
      text: codeLines[selection.baseIndex].text,
      selection: textSelection,
      composing: composing
    ).appendPrefixIfNecessary().appendSuffixIfNecessary();
  }

}

class _SmartTextEditingDelta {

  /// 内置的成对符号（起始与结束不同）
  static const List<_ClosureSymbol> _defaultClosureSymbols = [
    _ClosureSymbol('{', '}'),
    _ClosureSymbol('[', ']'),
    _ClosureSymbol('(', ')'),
  ];

  /// 内置的引号符号（起始与结束相同）
  static const List<String> _defaultQuoteSymbols = [
    '\'', '"', '`'
  ];

  /// 内置的可包裹选区的成对符号
  static const List<_ClosureSymbol> _defaultWrapSymbols = [
    _ClosureSymbol('{', '}'),
    _ClosureSymbol('[', ']'),
    _ClosureSymbol('(', ')'),
    _ClosureSymbol('\'', '\''),
    _ClosureSymbol('"', '"'),
    _ClosureSymbol('`', '`'),
  ];

  /// 生效的成对符号（起始与结束不同）
  final List<_ClosureSymbol> _closureSymbols;

  /// 生效的引号符号（起始与结束相同）
  final List<String> _quoteSymbols;

  /// 生效的可包裹选区的成对符号
  final List<_ClosureSymbol> _wrapSymbols;

  final TextEditingDelta _delta;

  /// [pairs] 为空时沿用内置符号表，否则按传入的符号表构造成对与引号两类符号
  _SmartTextEditingDelta(this._delta, [List<CodeSymbolPair>? pairs])
    : _closureSymbols = pairs == null
        ? _defaultClosureSymbols
        : pairs
            .where((e) => e.left != e.right)
            .map((e) => _ClosureSymbol(e.left, e.right))
            .toList(),
      _quoteSymbols = pairs == null
        ? _defaultQuoteSymbols
        : pairs
            .where((e) => e.left == e.right)
            .map((e) => e.left)
            .toList(),
      _wrapSymbols = pairs == null
        ? _defaultWrapSymbols
        : pairs.map((e) => _ClosureSymbol(e.left, e.right)).toList();

  TextEditingDelta apply(CodeLineSelection selection) {
    TextEditingDelta delta = _delta;
    if (delta is TextEditingDeltaInsertion) {
      delta = _smartInsertion(delta);
    } else if (delta is TextEditingDeltaReplacement) {
      delta = _smartReplacement(delta, selection);
    }
    return delta;
  }

  TextEditingDelta _smartInsertion(TextEditingDeltaInsertion delta) {
    for (final _ClosureSymbol symbol in _closureSymbols) {
      if (delta.textInserted == symbol.left) {
        if (!_shouldAutoClosed(delta.oldText, delta.insertionOffset, symbol)) {
          break;
        }
        return TextEditingDeltaInsertion(
          oldText: delta.oldText,
          textInserted: symbol.toString(),
          insertionOffset: delta.insertionOffset,
          selection: delta.selection,
          composing: delta.composing,
        );
      } else if (delta.textInserted == symbol.right) {
        if (!_shouldSkipClosed(delta.oldText, delta.insertionOffset, symbol)) {
          break;
        }
        return TextEditingDeltaNonTextUpdate(
          oldText: delta.oldText,
          selection: TextSelection.collapsed(
            offset: delta.insertionOffset + 1
          ),
          composing: delta.composing
        );
      }
    }
    for (final String symbol in _quoteSymbols) {
      if (delta.textInserted != symbol) {
        continue;
      }
      if (!_shouldAutoQuoted(delta.oldText, symbol, delta.insertionOffset)) {
        break;
      }
      return TextEditingDeltaInsertion(
        oldText: delta.oldText,
        textInserted: symbol * 2,
        insertionOffset: delta.insertionOffset,
        selection: delta.selection,
        composing: delta.composing,
      );
    }
    return delta;
  }

  TextEditingDelta _smartReplacement(TextEditingDeltaReplacement delta, CodeLineSelection selection) {
    if (!selection.isSameLine) {
      return delta;
    }
    if (delta.replacementText.length > 1) {
      return delta;
    }
    final int index = _wrapSymbols.indexWhere((element) => element.left == delta.replacementText);
    if (index < 0) {
      return delta;
    }
    final _ClosureSymbol symbol = _wrapSymbols[index];
    return TextEditingDeltaReplacement(
      oldText: delta.oldText,
      replacementText: symbol.left + delta.textReplaced + symbol.right,
      replacedRange: delta.replacedRange,
      selection: TextSelection(
        baseOffset: selection.startOffset + 1,
        extentOffset: selection.endOffset + 1
      ),
      composing: delta.composing
    );
  }

  bool _shouldAutoClosed(String text, int offset, _ClosureSymbol symbol) {
    final Characters characters = text.characters;
    if (characters.isEmpty) {
      return true;
    }
    int leftSymbolCount = 0;
    int rightSymbolCount = 0;
    for (int i = 0; i < characters.length; i++) {
      final String character = characters.elementAt(i);
      if (i <= offset) {
        if (character == symbol.left) {
          leftSymbolCount++;
        } else if (character == symbol.right) {
          leftSymbolCount--;
        }
      } else {
        if (character == symbol.left) {
          rightSymbolCount--;
        } else if (character == symbol.right) {
          rightSymbolCount++;
        }
      }
    }
    return max(0, leftSymbolCount) >= rightSymbolCount;
  }

  bool _shouldSkipClosed(String text, int offset, _ClosureSymbol symbol) {
    if (text.isEmpty) {
      return false;
    }
    if (offset == text.length) {
      return false;
    }
    return text.substring(offset, offset + 1) == symbol.right;
  }

  bool _shouldAutoQuoted(String text, String symbol, int offset) {
    final Characters characters = text.characters;
    if (characters.isEmpty) {
      return true;
    }
    int leftSymbolCount = 0;
    int rightSymbolCount = 0;
    for (int i = 0; i < characters.length; i++) {
      final String character = characters.elementAt(i);
      if (i < offset) {
        if (character == symbol) {
          leftSymbolCount++;
        }
      } else {
        if (character == symbol) {
          rightSymbolCount++;
        }
      }
    }
    if (leftSymbolCount == 0 && rightSymbolCount == 0) {
      return true;
    }
    if (rightSymbolCount == 0) {
      return leftSymbolCount % 2 == 0;
    }
    if (leftSymbolCount == 0) {
      return rightSymbolCount % 2 == 0;
    }
    return leftSymbolCount % 2 == rightSymbolCount % 2;
  }

}

class _ClosureSymbol {
  final String left;
  final String right;

  const _ClosureSymbol(this.left, this.right);

  @override
  String toString() {
    return left + right;
  }

}

const String _kPrefix = '\u200b';

/// 镜像末尾追加的零宽哨兵
///
/// 输入法方向键只能在镜像文本内移动光标，末尾追加哨兵后光标位于行尾时
/// 仍有一次向右移动的余量，使输入法上报的选区变更能够触发跨行光标移动。
const String _kSuffix = '\u200b';

extension _TextEditingValueExtension on TextEditingValue {

  bool get startWithPrefix => text.startsWith(_kPrefix);

  bool get endWithSuffix => text.endsWith(_kSuffix);

  bool get usePrefix => kIsIOS || kIsAndroid;

  TextEditingValue appendPrefixIfNecessary() {
    if (!usePrefix) {
      return this;
    }
    return copyWith(
      text: '$_kPrefix$text',
      selection: selection.copyWith(
        baseOffset: selection.baseOffset + 1,
        extentOffset: selection.extentOffset + 1,
      ),
      composing: composing.isValid ? TextRange(
        start: composing.start + 1,
        end: composing.end + 1
      ) : composing
    );
  }

  TextEditingValue removePrefixIfNecessary() {
    if (!usePrefix) {
      return this;
    }
    if (!startWithPrefix) {
      return this;
    }
    return copyWith(
      text: text.substring(1),
      selection: selection.copyWith(
        baseOffset: max(0, selection.baseOffset - 1),
        extentOffset: max(0, selection.extentOffset - 1),
      ),
      composing: composing.isValid ? TextRange(
        start: max(0, composing.start - 1),
        end: max(0, composing.end - 1)
      ) : null
    );
  }

  TextEditingValue appendSuffixIfNecessary() {
    if (!usePrefix) {
      return this;
    }
    return copyWith(
      text: '$text$_kSuffix'
    );
  }

  TextEditingValue removeSuffixIfNecessary() {
    if (!usePrefix) {
      return this;
    }
    if (!endWithSuffix) {
      return this;
    }
    final String newText = text.substring(0, text.length - 1);
    return copyWith(
      text: newText,
      selection: selection.copyWith(
        baseOffset: min(selection.baseOffset, newText.length),
        extentOffset: min(selection.extentOffset, newText.length),
      )
    );
  }

}

class _TextInputConfiguration extends TextInputConfiguration {

  final int flutterViewId;

  const _TextInputConfiguration({
    required this.flutterViewId,
    required super.enableDeltaModel,
    required super.inputAction,
    super.autocorrect = false,
    super.smartDashesType = SmartDashesType.disabled,
    super.smartQuotesType = SmartQuotesType.disabled,
    super.textCapitalization = TextCapitalization.none,
    super.keyboardAppearance,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'viewId': flutterViewId,
    };
  }

}