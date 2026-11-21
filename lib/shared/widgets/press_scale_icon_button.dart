import 'package:flutter/material.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 缩放反馈图标按钮
///
/// 按下时图标缩小并切换为按下色，松开或取消触摸后恢复
class PressScaleIconButton extends StatefulWidget {
  /// 按钮图标
  final IconData icon;

  /// 提示文本，鼠标悬停或移动端长按时显示
  final String tooltip;

  /// 点击回调，为 null 时按钮不可交互且无按下反馈
  final VoidCallback? onPressed;

  /// 是否处于选中状态，选中时图标使用 [selectedColor]
  final bool isSelected;

  /// 选中状态的图标颜色，默认使用主题主色
  final Color? selectedColor;

  /// 未选中状态的图标颜色，默认使用 [ColorScheme.onSurfaceVariant]
  final Color? unselectedColor;

  /// 按下状态的图标颜色
  ///
  /// 未选中时默认使用主题主色；选中时默认在选中色基础上加深（浅色主题）
  /// 或提亮（深色主题），保证两种状态下按下都有明显的颜色变化。
  final Color? pressedColor;

  /// 按钮边长，默认 44
  final double size;

  /// 图标大小，默认 20
  final double iconSize;

  /// 按下时的缩放比例，默认 0.82
  final double pressedScale;

  /// 缩放与变色动画时长
  final Duration duration;

  const PressScaleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isSelected = false,
    this.selectedColor,
    this.unselectedColor,
    this.pressedColor,
    this.size = 44,
    this.iconSize = 20,
    this.pressedScale = 0.82,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<PressScaleIconButton> createState() => _PressScaleIconButtonState();
}

class _PressScaleIconButtonState extends State<PressScaleIconButton> {
  /// 是否处于按下状态
  bool _pressed = false;

  /// 是否可交互
  bool get _enabled => widget.onPressed != null;

  @override
  void didUpdateWidget(covariant PressScaleIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 交互被禁用时复位，避免保持缩小状态
    if (!_enabled && _pressed) {
      _pressed = false;
    }
  }

  /// 进入按下状态
  void _press() {
    if (!_pressed) setState(() => _pressed = true);
  }

  /// 结束按下状态
  void _release() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // 选中态与未选中态使用各自的常态色，按下时统一使用按下色
    final Color baseColor = widget.isSelected
        ? (widget.selectedColor ?? colorScheme.primary)
        : (widget.unselectedColor ?? colorScheme.onSurfaceVariant);
    // 未选中时按下高亮为主题主色；选中时在原色上叠加前景色，保证仍有颜色反馈
    final Color pressedColor = widget.pressedColor ??
        (widget.isSelected
            ? Color.alphaBlend(colorScheme.onSurface.withValues(alpha: 0.2), baseColor)
            : colorScheme.primary);
    final Color iconColor = _pressed ? pressedColor : baseColor;

    return CursorTooltipTarget(
      tooltipContent: Text(widget.tooltip),
      child: Listener(
        // 原始指针事件不受手势竞争影响，按下反馈可立即出现
        onPointerDown: _enabled ? (_) => _press() : null,
        onPointerUp: _enabled ? (_) => _release() : null,
        onPointerCancel: _enabled ? (_) => _release() : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? widget.pressedScale : 1,
            duration: widget.duration,
            curve: Curves.easeOut,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Center(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: iconColor),
                  duration: widget.duration,
                  builder: (context, color, _) =>
                      Icon(widget.icon, size: widget.iconSize, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
