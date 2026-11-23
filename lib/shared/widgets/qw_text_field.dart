import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/utils/find_match_highlighter.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
import 'package:quick_write/shared/widgets/qw_text_field_painter.dart';

Widget _qwDefaultContextMenuBuilder(
  BuildContext context,
  EditableTextState state,
) {
  if (SystemContextMenu.isSupportedByField(state)) {
    return SystemContextMenu.editableText(editableTextState: state);
  }
  return AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
}

/// 带统一选区与字底色绘制的 TextField 封装
///
/// 内置选区色置透明，改由 [QwTextFieldPainter] 绘制，参数与 TextField 一一对应。
class QwTextField extends StatefulWidget {
  const QwTextField({
    super.key,
    this.groupId = EditableText,
    this.controller,
    this.focusNode,
    this.undoController,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textDirection,
    this.readOnly = false,
    this.showCursor,
    this.autofocus = false,
    this.statesController,
    this.obscuringCharacter = '•',
    this.obscureText = false,
    this.autocorrect,
    this.smartDashesType,
    this.smartQuotesType,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.maxLength,
    this.maxLengthEnforcement,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onAppPrivateCommand,
    this.inputFormatters,
    this.enabled,
    this.ignorePointers,
    this.cursorWidth = 2.0,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorOpacityAnimates,
    this.cursorColor,
    this.cursorErrorColor,
    this.selectionColor,
    this.selectionHeightStyle,
    this.selectionWidthStyle,
    this.keyboardAppearance,
    this.scrollPadding = const EdgeInsets.all(20.0),
    this.dragStartBehavior = DragStartBehavior.start,
    this.enableInteractiveSelection,
    this.selectAllOnFocus,
    this.selectionControls,
    this.onTap,
    this.onTapAlwaysCalled = false,
    this.onTapOutside,
    this.onTapUpOutside,
    this.mouseCursor,
    this.buildCounter,
    this.scrollController,
    this.scrollPhysics,
    this.autofillHints = const <String>[],
    this.contentInsertionConfiguration,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.stylusHandwritingEnabled =
        EditableText.defaultStylusHandwritingEnabled,
    this.enableIMEPersonalizedLearning = true,
    this.contextMenuBuilder = _qwDefaultContextMenuBuilder,
    this.canRequestFocus = true,
    this.spellCheckConfiguration,
    this.magnifierConfiguration,
    this.hintLocales,
  });

  final Object groupId;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final UndoHistoryController? undoController;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextDirection? textDirection;
  final bool readOnly;
  final bool? showCursor;
  final bool autofocus;
  final WidgetStatesController? statesController;
  final String obscuringCharacter;
  final bool obscureText;
  final bool? autocorrect;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final AppPrivateCommandCallback? onAppPrivateCommand;
  final List<TextInputFormatter>? inputFormatters;
  final bool? enabled;
  final bool? ignorePointers;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final bool? cursorOpacityAnimates;
  final Color? cursorColor;
  final Color? cursorErrorColor;
  final Color? selectionColor;
  final ui.BoxHeightStyle? selectionHeightStyle;
  final ui.BoxWidthStyle? selectionWidthStyle;
  final Brightness? keyboardAppearance;
  final EdgeInsets scrollPadding;
  final DragStartBehavior dragStartBehavior;
  final bool? enableInteractiveSelection;
  final bool? selectAllOnFocus;
  final TextSelectionControls? selectionControls;
  final GestureTapCallback? onTap;
  final bool onTapAlwaysCalled;
  final TapRegionCallback? onTapOutside;
  final TapRegionUpCallback? onTapUpOutside;
  final MouseCursor? mouseCursor;
  final InputCounterWidgetBuilder? buildCounter;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;
  final Iterable<String>? autofillHints;
  final ContentInsertionConfiguration? contentInsertionConfiguration;
  final Clip clipBehavior;
  final String? restorationId;
  final bool stylusHandwritingEnabled;
  final bool enableIMEPersonalizedLearning;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final bool canRequestFocus;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final TextMagnifierConfiguration? magnifierConfiguration;
  final List<Locale>? hintLocales;

  @override
  State<QwTextField> createState() => _QwTextFieldState();
}

class _QwTextFieldState extends State<QwTextField> {
  final GlobalKey _anchorKey = GlobalKey();
  final QwCaretPainter _caretPainter = QwCaretPainter();
  late final QwTextFieldPainter _painter;

  Color _focusedColor(BuildContext context) =>
      widget.selectionColor ??
      computeFocusedSelectionColor(Theme.of(context).colorScheme);

  Color _unfocusedColor(BuildContext context) =>
      computePersistentSelectionColor(
        context,
        Theme.of(context).colorScheme.primary,
      );

  @override
  void initState() {
    super.initState();
    _painter = QwTextFieldPainter(
      controller: widget.controller,
      focusedColor: Colors.transparent,
      unfocusedColor: Colors.transparent,
      matchColor: Colors.transparent,
      currentMatchColor: Colors.transparent,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPainterColors();
  }

  @override
  void didUpdateWidget(covariant QwTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPainterColors();
  }

  void _syncPainterColors() {
    _painter.update(
      controller: widget.controller,
      focusedColor: _focusedColor(context),
      unfocusedColor: _unfocusedColor(context),
      matchColor: FindMatchHighlighter.getMatchColor(context),
      currentMatchColor: FindMatchHighlighter.getCurrentMatchColor(context),
    );
  }

  @override
  void dispose() {
    _painter.dispose();
    _caretPainter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderEditable = findPersistentRenderEditable(_anchorKey);
      if (renderEditable == null) return;
      if (!identical(renderEditable.painter, _painter)) {
        renderEditable.painter = _painter;
      }
      _caretPainter.attach(renderEditable);
      if (!identical(renderEditable.foregroundPainter, _caretPainter)) {
        renderEditable.foregroundPainter = _caretPainter;
      }
    });

    return KeyedSubtree(
      key: _anchorKey,
      child: DefaultSelectionStyle.merge(
        selectionColor: Colors.transparent,
        child: TextField(
          groupId: widget.groupId,
          controller: widget.controller,
          focusNode: widget.focusNode,
          undoController: widget.undoController,
          decoration: widget.decoration,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          style: widget.style,
          strutStyle: widget.strutStyle,
          textAlign: widget.textAlign,
          textAlignVertical: widget.textAlignVertical,
          textDirection: widget.textDirection,
          readOnly: widget.readOnly,
          showCursor: widget.showCursor,
          autofocus: widget.autofocus,
          statesController: widget.statesController,
          obscuringCharacter: widget.obscuringCharacter,
          obscureText: widget.obscureText,
          autocorrect: widget.autocorrect,
          smartDashesType: widget.smartDashesType,
          smartQuotesType: widget.smartQuotesType,
          enableSuggestions: widget.enableSuggestions,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          expands: widget.expands,
          maxLength: widget.maxLength,
          maxLengthEnforcement: widget.maxLengthEnforcement,
          onChanged: widget.onChanged,
          onEditingComplete: widget.onEditingComplete,
          onSubmitted: widget.onSubmitted,
          onAppPrivateCommand: widget.onAppPrivateCommand,
          inputFormatters: widget.inputFormatters,
          enabled: widget.enabled,
          ignorePointers: widget.ignorePointers,
          cursorWidth: widget.cursorWidth,
          cursorHeight: widget.cursorHeight,
          cursorRadius: widget.cursorRadius,
          cursorOpacityAnimates: widget.cursorOpacityAnimates,
          cursorColor: widget.cursorColor,
          cursorErrorColor: widget.cursorErrorColor,
          selectionHeightStyle: widget.selectionHeightStyle,
          selectionWidthStyle: widget.selectionWidthStyle,
          keyboardAppearance: widget.keyboardAppearance,
          scrollPadding: widget.scrollPadding,
          dragStartBehavior: widget.dragStartBehavior,
          enableInteractiveSelection: widget.enableInteractiveSelection,
          selectAllOnFocus: widget.selectAllOnFocus,
          selectionControls: widget.selectionControls,
          onTap: widget.onTap,
          onTapAlwaysCalled: widget.onTapAlwaysCalled,
          onTapOutside: widget.onTapOutside,
          onTapUpOutside: widget.onTapUpOutside,
          mouseCursor: widget.mouseCursor,
          buildCounter: widget.buildCounter,
          scrollController: widget.scrollController,
          scrollPhysics: widget.scrollPhysics,
          autofillHints: widget.autofillHints,
          contentInsertionConfiguration: widget.contentInsertionConfiguration,
          clipBehavior: widget.clipBehavior,
          restorationId: widget.restorationId,
          stylusHandwritingEnabled: widget.stylusHandwritingEnabled,
          enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
          contextMenuBuilder: widget.contextMenuBuilder,
          canRequestFocus: widget.canRequestFocus,
          spellCheckConfiguration: widget.spellCheckConfiguration,
          magnifierConfiguration: widget.magnifierConfiguration,
          hintLocales: widget.hintLocales,
        ),
      ),
    );
  }
}
