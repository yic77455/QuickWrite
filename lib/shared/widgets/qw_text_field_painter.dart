import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:quick_write/core/utils/rich_text_controller.dart';

/// QwTextField 的统一背景绘制器
///
/// 依次绘制字底色、普通查找匹配、选区、当前匹配；选区颜色按焦点自动切换。
/// 所有矩形合并进 Path 一次填充，避免半透明重叠与行间 1px 细缝。
/// 在 foreground 层补画光标
///
/// 内置 caret 在部分平台排在自定义 painter 之前，会被字底色盖住；
/// 这里只在原本 caret 位于文字下方时补画，避免和内置 caret 重复。
class QwCaretPainter extends RenderEditablePainter {
  RenderEditable? _attached;
  VoidCallback? _showCursorListener;

  /// 监听 showCursor 的闪烁切换，触发 foreground 层重绘
  void attach(RenderEditable renderEditable) {
    if (identical(_attached, renderEditable)) return;
    detach();
    _attached = renderEditable;
    _showCursorListener = () => notifyListeners();
    renderEditable.showCursor.addListener(_showCursorListener!);
  }

  void detach() {
    final RenderEditable? renderEditable = _attached;
    final VoidCallback? listener = _showCursorListener;
    if (renderEditable != null && listener != null) {
      renderEditable.showCursor.removeListener(listener);
    }
    _attached = null;
    _showCursorListener = null;
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }

  @override
  bool shouldRepaint(covariant QwCaretPainter oldDelegate) => true;

  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {
    if (renderEditable.paintCursorAboveText) return;
    final TextSelection? selection = renderEditable.selection;
    if (selection == null || !selection.isValid || !selection.isCollapsed) return;
    if (!renderEditable.showCursor.value) return;
    final Color? color = renderEditable.cursorColor;
    if (color == null || color.a == 0) return;

    final Rect rect = renderEditable
        .getLocalRectForCaret(selection.extent)
        .shift(renderEditable.cursorOffset);
    final Paint paint = Paint()..color = color;
    final Radius? radius = renderEditable.cursorRadius;
    if (radius == null) {
      canvas.drawRect(rect, paint);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
    }
  }
}

class QwTextFieldPainter extends RenderEditablePainter {
  QwTextFieldPainter({
    this.controller,
    required this.focusedColor,
    required this.unfocusedColor,
    required this.matchColor,
    required this.currentMatchColor,
  });

  TextEditingController? controller;
  Color focusedColor;
  Color unfocusedColor;
  Color matchColor;
  Color currentMatchColor;

  void update({
    TextEditingController? controller,
    Color? focusedColor,
    Color? unfocusedColor,
    Color? matchColor,
    Color? currentMatchColor,
  }) {
    this.controller = controller ?? this.controller;
    this.focusedColor = focusedColor ?? this.focusedColor;
    this.unfocusedColor = unfocusedColor ?? this.unfocusedColor;
    this.matchColor = matchColor ?? this.matchColor;
    this.currentMatchColor = currentMatchColor ?? this.currentMatchColor;
    notifyListeners();
  }

  @override
  bool shouldRepaint(covariant QwTextFieldPainter oldDelegate) => true;

  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {
    final int textLength = renderEditable.plainText.length;
    final RichTextEditingController? rich =
        controller is RichTextEditingController
        ? controller as RichTextEditingController
        : null;

    if (rich != null) {
      for (final range in rich.styleRanges) {
        final Color? bg = range.flags.backgroundColor;
        if (bg == null) continue;
        _drawRange(
          canvas,
          renderEditable,
          range.start,
          range.end,
          bg,
          textLength,
          0.2,
          0.0,
        );
      }
      for (var i = 0; i < rich.findMatches.length; i++) {
        if (i == rich.currentMatchIndex) continue;
        final match = rich.findMatches[i];
        _drawRange(
          canvas,
          renderEditable,
          match.start,
          match.end,
          matchColor,
          textLength,
          0.2,
          0.0,
        );
      }
      if (rich.currentMatchIndex >= 0 &&
          rich.currentMatchIndex < rich.findMatches.length) {
        final match = rich.findMatches[rich.currentMatchIndex];
        _drawRange(
          canvas,
          renderEditable,
          match.start,
          match.end,
          currentMatchColor,
          textLength,
          0.2,
          1.0,
        );
      }
    }

    final TextSelection? selection = renderEditable.selection;
    if (selection != null && selection.isValid && !selection.isCollapsed) {
      final Path path = Path();
      _addRangeToPath(
        path,
        renderEditable,
        selection.start,
        selection.end,
        textLength,
        0.2,
        1.0,
      );
      if (renderEditable.selectionWidthStyle == ui.BoxWidthStyle.tight) {
        _addNewlineBlocks(path, renderEditable, selection, textLength);
      }
      final bool active =
          renderEditable.hasFocus || _isCurrentFindMatch(selection, rich);
      canvas.drawPath(
        path,
        Paint()..color = active ? focusedColor : unfocusedColor,
      );
    }

  }

  bool _isCurrentFindMatch(
    TextSelection selection,
    RichTextEditingController? rich,
  ) {
    if (rich == null ||
        rich.currentMatchIndex < 0 ||
        rich.currentMatchIndex >= rich.findMatches.length) {
      return false;
    }
    final TextSelection match = rich.findMatches[rich.currentMatchIndex];
    return selection.start == match.start && selection.end == match.end;
  }

  void _drawRange(
    Canvas canvas,
    RenderEditable renderEditable,
    int start,
    int end,
    Color color,
    int textLength,
    double expandX,
    double expandY,
  ) {
    if (start >= end) return;
    final Path path = Path();
    _addRangeToPath(
      path,
      renderEditable,
      start,
      end,
      textLength,
      expandX,
      expandY,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  void _addRangeToPath(
    Path path,
    RenderEditable renderEditable,
    int start,
    int end,
    int textLength,
    double expandX,
    double expandY,
  ) {
    final int from = start.clamp(0, textLength);
    final int to = end.clamp(0, textLength);
    if (from >= to) return;
    for (final TextBox box in renderEditable.getBoxesForSelection(
      TextSelection(baseOffset: from, extentOffset: to),
    )) {
      final Rect rect = box.toRect();
      if (rect.width <= 0.1) continue;
      path.addRect(
        Rect.fromLTRB(
          rect.left - expandX,
          rect.top - expandY,
          rect.right + expandX,
          rect.bottom + expandY,
        ),
      );
    }
  }

  void _addNewlineBlocks(
    Path path,
    RenderEditable renderEditable,
    TextSelection selection,
    int textLength,
  ) {
    final String plainText = renderEditable.plainText;
    final int end = selection.end.clamp(0, textLength);
    int index = selection.start.clamp(0, textLength);
    while (index < end) {
      final int newline = plainText.indexOf('\n', index);
      if (newline == -1 || newline >= end) break;
      final List<TextBox> boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: newline, extentOffset: newline + 1),
      );
      if (boxes.isNotEmpty) {
        final Rect rect = boxes.first.toRect();
        path.addRect(
          Rect.fromLTWH(
            rect.left,
            rect.top - 1.0,
            8.0,
            (rect.height > 0 ? rect.height : 14.0) + 2.0,
          ),
        );
      }
      index = newline + 1;
    }
  }
}
