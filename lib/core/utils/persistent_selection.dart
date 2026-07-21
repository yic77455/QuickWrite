import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 失焦时绘制持久化选区的自定义 Painter
///
/// 继承自 Flutter 渲染层提供的 RenderEditablePainter 接口，
/// 可被注入到 RenderEditable.painter（backgroundPainter），与内置的 _selectionPainter 共享同一套坐标系统和排版数据。
///
/// 工作时机：仅当编辑器失去焦点 且 存在非折叠选区 时才绘制，
/// 获得焦点时不绘制（由内置 _selectionPainter 负责）。
///
/// 注入位置在 background 层（文字层之下），选区底色不会干扰文字本身的颜色和样式。
class PersistentSelectionOverlayPainter extends RenderEditablePainter {
  /// 当前是否处于失焦状态（外部设置）
  bool isUnfocused = false;

  /// 当前选区范围（外部设置）
  TextSelection selection = const TextSelection.collapsed(offset: -1);

  /// 失焦时的选区高亮颜色
  ///
  /// 默认值仅作兜底，实际值由外部通过 update() 注入，从主题色派生而来，确保跟随主题切换自动适配
  Color color = const Color(0xFFD0D0D0);

  /// 选区宽度样式（需与 TextField 的 selectionWidthStyle 保持一致）
  ///
  /// 仅当值为 BoxWidthStyle.tight 时才启用换行符的 8 像素补丁
  ui.BoxWidthStyle selectionWidthStyle = ui.BoxWidthStyle.tight;

  @override
  bool shouldRepaint(covariant PersistentSelectionOverlayPainter oldDelegate) {
    return oldDelegate.isUnfocused != isUnfocused || oldDelegate.selection != selection || oldDelegate.color != color;
  }

  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {
    // 只在失焦 + 有有效非折叠选区时绘制
    if (!isUnfocused || !selection.isValid || selection.isCollapsed) return;

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 使用 RenderEditable 公开 API 获取原始选区矩形列表
    final List<TextBox> boxes = renderEditable.getBoxesForSelection(selection);

    // 收集所有选中矩形
    List<Rect> allSelectionRects = [];

    // 收集普通文本的选中矩形（过滤掉 0 宽度废矩形）
    for (final box in boxes) {
      final Rect rect = box.toRect();
      if (rect.width > 0.1) {
        allSelectionRects.add(rect);
      }
    }

    // 收集换行符 \n 的专属矩形（与修改后的 Flutter 源码 _TextHighlightPainter 保持一致）
    if (selectionWidthStyle == ui.BoxWidthStyle.tight) {
      final String plainText = renderEditable.text?.toPlainText() ?? '';
      int searchIndex = selection.start;
      final int endIndex = selection.end > plainText.length ? plainText.length : selection.end;

      while (searchIndex < endIndex) {
        final int newlineIndex = plainText.indexOf('\n', searchIndex);
        if (newlineIndex == -1 || newlineIndex >= endIndex) break;

        final List<TextBox> nlBoxes = renderEditable.getBoxesForSelection(
          TextSelection(baseOffset: newlineIndex, extentOffset: newlineIndex + 1),
        );

        if (nlBoxes.isNotEmpty) {
          final Rect nlRect = nlBoxes.first.toRect();
          allSelectionRects.add(Rect.fromLTWH(nlRect.left, nlRect.top, 8.0, nlRect.height > 0 ? nlRect.height : 14.0));
        }

        searchIndex = newlineIndex + 1;
      }
    }

    // 桥接算法：排序 + 补缝
    // 对所有矩形按从上到下、从左到右排序
    allSelectionRects.sort((a, b) {
      // 不在同一行时按上下排（Y轴差距超过高度的一半视为不同行）
      if ((a.top - b.top).abs() > (a.height / 2)) {
        return a.top.compareTo(b.top);
      }
      // 同一行内按左右排
      return a.left.compareTo(b.left);
    });

    // 遍历并绘制，同时抹平相邻矩形之间的缝隙
    Rect? prevRect;
    for (final rect in allSelectionRects) {
      // 检查当前矩形是否和上一个矩形在同一行
      if (prevRect != null && (rect.top - prevRect.top).abs() < (rect.height / 2)) {
        double gap = rect.left - prevRect.right;

        // 如果它们之间有空隙（-1 ~ 12 像素范围内），画一个补丁矩形连接两块选区
        // gap > -1.0 覆盖抗锯齿导致的微小负数重叠
        // gap < 12.0 确保只连接真正相邻的选区块，不会跨过过大的空白
        if (gap > -1.0 && gap < 12.0) {
          canvas.drawRect(Rect.fromLTRB(prevRect.right - 0.5, rect.top, rect.left + 0.5, rect.bottom), paint);
        }
      }

      // 绘制矩形本身（略微外扩 0.2 个像素，彻底消灭抗锯齿带来的白边/间隙）
      canvas.drawRect(Rect.fromLTRB(rect.left - 0.2, rect.top, rect.right + 0.2, rect.bottom), paint);

      prevRect = rect; // 记录为上一块，供下一次循环比对
    }
  }

  /// 外部调用的更新入口，内部触发 ChangeNotifier 通知重绘
  ///
  /// 因为 notifyListeners() 是 protected 方法，不能从 State 直接调用，
  /// 所以通过这个公开方法桥接
  void update({bool? isUnfocused, TextSelection? selection, Color? color}) {
    if (isUnfocused != null) this.isUnfocused = isUnfocused;
    if (selection != null) this.selection = selection;
    if (color != null) this.color = color;
    notifyListeners();
  }
}

// ================= 持久化选区共享工具函数 =================
//
// 以下函数供正文编辑器和大纲编辑器共用，避免查找 RenderEditable、计算失焦颜色、
// 注入 Painter 等逻辑在两处重复实现。

/// 从 TextField 的 GlobalKey 查找底层 RenderEditable
///
/// 遍历渲染子树，递归查找真正负责文字排版的 RenderEditable。
RenderEditable? findPersistentRenderEditable(GlobalKey textFieldKey) {
  final renderObject = textFieldKey.currentContext?.findRenderObject();
  if (renderObject == null) return null;
  RenderEditable? result;
  void visitor(RenderObject child) {
    if (child is RenderEditable) {
      result = child;
      return;
    }
    child.visitChildren(visitor);
  }

  renderObject.visitChildren(visitor);
  return result;
}

/// 计算失焦时的选区高亮颜色
///
/// 从当前主题的选区色派生一个低饱和度的灰色，根据背景亮度自适应明暗。
Color computePersistentSelectionColor(BuildContext context, Color fallback) {
  // 从当前主题的文本选择主题中读取选区颜色，若未设置则回退到主色
  final Color selectionColor = Theme.of(context).textSelectionTheme.selectionColor ?? fallback;
  // 将选区颜色转为 HSL 色彩空间，方便独立调整饱和度和亮度
  final HSLColor hsl = HSLColor.fromColor(selectionColor);

  // 获取当前主题的背景颜色
  final Color backgroundColor = Theme.of(context).scaffoldBackgroundColor;
  // 将背景颜色转换为 HSL 色彩空间，获取其亮度值
  final double backgroundLightness = HSLColor.fromColor(backgroundColor).lightness;

  // 根据背景颜色的亮度计算目标选区亮度：
  // - 背景较亮（亮度 > 0.5）：使用较低亮度的灰色，确保对比度
  // - 背景较暗（亮度 <= 0.5）：使用较高亮度的灰色，确保可见性
  double targetLightness;
  if (backgroundLightness > 0.5) {
    // 亮色背景：使用较低亮度的灰色（0.82）
    targetLightness = 0.82;
  } else {
    // 暗色背景：使用较高亮度的灰色（0.25）
    targetLightness = 0.25;
  }

  return hsl.withSaturation(0.08).withLightness(targetLightness).toColor();
}

/// 将持久化选区 Painter 注入到 RenderEditable 的 painter（backgroundPainter）链中
///
/// 在文字层之下绘制选区底色，并完成首次状态初始化。
void attachPersistentSelectionPainter({
  required GlobalKey textFieldKey,
  required PersistentSelectionOverlayPainter painter,
  required TextEditingController controller,
  required FocusNode focusNode,
  required BuildContext context,
  required Color fallbackColor,
}) {
  final renderEditable = findPersistentRenderEditable(textFieldKey);
  if (renderEditable != null) {
    renderEditable.painter = painter;
    painter.update(
      isUnfocused: !focusNode.hasFocus,
      selection: controller.selection,
      color: computePersistentSelectionColor(context, fallbackColor),
    );
  }
}