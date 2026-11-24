import 'package:flutter/material.dart';
import 'package:quick_write/shared/widgets/press_scale.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 圆形颜色色块选项
///
/// 统一关键词颜色、右键颜色面板、移动端颜色栏等处的色块外观与交互：
/// 选中时显示主题色外环，支持对勾与「无颜色」斜杠两种标记。
class ColorSwatchOption extends StatelessWidget {
  /// 色块颜色，无颜色色块为 null
  final Color? color;

  /// 是否选中
  final bool selected;

  /// 点击回调，为 null 时不可交互
  final VoidCallback? onTap;

  /// 色块外径
  final double size;

  /// 内部颜色圆直径
  final double innerSize;

  /// 选中对勾大小
  final double checkSize;

  /// 是否为无颜色色块（中性底色 + 斜杠）
  final bool isNone;

  /// 内圈是否描边
  final bool showInnerBorder;

  /// 点击热区边长，默认与 [size] 一致
  final double? hitTargetSize;

  /// 按下时的缩放比例
  final double pressedScale;

  /// 悬停提示文本，为 null 时不显示
  final String? tooltip;

  /// 删除模式下覆盖 - 号，点击交由调用方删除色块
  final bool deleteMode;

  const ColorSwatchOption({
    super.key,
    this.color,
    required this.selected,
    this.onTap,
    this.size = 28,
    this.innerSize = 20,
    this.checkSize = 13,
    this.isNone = false,
    this.showInnerBorder = false,
    this.hitTargetSize,
    this.pressedScale = 0.9,
    this.tooltip,
    this.deleteMode = false,
  }) : assert(isNone || color != null, '普通色块必须提供 color');

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color fillColor = isNone ? colorScheme.surfaceContainerHighest : color!;
    final bool useLightCheck = ThemeData.estimateBrightnessForColor(fillColor) == Brightness.dark;

    // 选中态微调：外圈直径 = innerSize + ringExtra，色圆直径 = innerSize - innerShrink
    const double ringWidth = 2;
    const double ringExtra = 3;
    const double innerShrink = 6;
    const Duration animationDuration = Duration(milliseconds: 120);
    final double outerSize = selected ? innerSize + ringExtra : size;
    final double effectiveInnerSize = selected ? innerSize - innerShrink : innerSize;
    final double effectiveCheckSize = selected ? checkSize - 4 : checkSize;

    final Widget inner = AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeOut,
      width: effectiveInnerSize,
      height: effectiveInnerSize,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: showInnerBorder
            ? Border.all(color: colorScheme.outlineVariant, width: 0.5)
            : null,
      ),
      child: deleteMode
          ? Icon(
              Icons.remove_rounded,
              size: checkSize + 2,
              color: useLightCheck ? Colors.white : Colors.black87,
            )
          : isNone
          ? CustomPaint(
              painter: _SlashPainter(
                color: selected
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              ),
            )
          : selected
          ? Icon(
              Icons.check_rounded,
              size: effectiveCheckSize,
              color: useLightCheck ? Colors.white : Colors.black87,
            )
          : null,
    );

    final Widget visual = AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeOut,
      width: outerSize,
      height: outerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colorScheme.primary : Colors.transparent,
          width: ringWidth,
        ),
      ),
      child: Center(child: inner),
    );

    final double target = hitTargetSize ?? size;
    final Widget swatch = PressScale(
      onTap: onTap,
      pressedScale: pressedScale,
      child: SizedBox(
        width: target,
        height: target,
        child: Center(child: visual),
      ),
    );

    if (tooltip == null) return swatch;
    return CursorTooltipTarget(
      tooltipContent: Text(tooltip!),
      child: swatch,
    );
  }
}

/// 无颜色色块的斜杠标记
class _SlashPainter extends CustomPainter {
  const _SlashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.24, size.height * 0.76),
      Offset(size.width * 0.76, size.height * 0.24),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter oldDelegate) => oldDelegate.color != color;
}
