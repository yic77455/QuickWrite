import 'package:flutter/material.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 悬停 / 按下缩放组件
///
/// 颜色色块、图标按钮等无背景元素的统一交互反馈：
/// 鼠标悬停时放大、按下时缩小，松开或取消触摸后恢复原大小。
/// [onTap] 为 null 时组件不可交互，也不产生缩放与指针变化。
/// [child] 与 [builder] 二选一，需要根据按压状态改变内容时使用 [builder]。
class PressScale extends StatefulWidget {
  /// 子组件
  final Widget? child;

  /// 带按下状态的子组件构建器
  final Widget Function(BuildContext context, bool pressed)? builder;

  /// 点击回调，为 null 时组件不可交互
  final VoidCallback? onTap;

  /// 按下时的缩放比例
  final double pressedScale;

  /// 悬停时的缩放比例
  final double hoverScale;

  /// 缩放动画时长
  final Duration duration;

  const PressScale({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.pressedScale = 0.9,
    this.hoverScale = 1.15,
    this.duration = const Duration(milliseconds: 120),
  }) : assert(child != null || builder != null, 'child 与 builder 必须提供一个');

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  /// 是否处于按下状态
  bool _pressed = false;

  /// 鼠标是否悬停在组件上
  bool _hovered = false;

  /// 是否可交互
  bool get _enabled => widget.onTap != null;

  @override
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 交互被禁用时复位，避免保持缩小或放大状态
    if (!_enabled) {
      _pressed = false;
      _hovered = false;
    }
  }

  /// 更新按下状态
  ///
  /// 使用原始指针事件驱动，按下反馈无需等待手势识别完成。
  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    // 按下优先于悬停，松开后回到悬停或原始大小
    final double scale =
        _pressed ? widget.pressedScale : (_hovered ? widget.hoverScale : 1);
    final Widget content = widget.builder?.call(context, _pressed) ?? widget.child!;

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _enabled ? (_) => setState(() => _hovered = false) : null,
      child: Listener(
        onPointerDown: _enabled ? (_) => _setPressed(true) : null,
        onPointerUp: _enabled ? (_) => _setPressed(false) : null,
        onPointerCancel: _enabled ? (_) => _setPressed(false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? widget.onTap : null,
          child: AnimatedScale(
            scale: scale,
            duration: widget.duration,
            curve: Curves.easeOut,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 缩放反馈图标按钮
///
/// 在 [PressScale] 的缩放交互之上，补充提示文本、选中色与按下变色。
class PressScaleIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // 选中态与未选中态使用各自的常态色，按下时统一使用按下色
    final Color baseColor = isSelected
        ? (selectedColor ?? colorScheme.primary)
        : (unselectedColor ?? colorScheme.onSurfaceVariant);
    // 未选中时按下高亮为主题主色；选中时在原色上叠加前景色，保证仍有颜色反馈
    final Color pressedColor = this.pressedColor ??
        (isSelected
            ? Color.alphaBlend(colorScheme.onSurface.withValues(alpha: 0.2), baseColor)
            : colorScheme.primary);

    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: PressScale(
        onTap: onPressed,
        pressedScale: pressedScale,
        // 图标按钮保持原有的纯按下反馈，悬停不放大
        hoverScale: 1,
        duration: duration,
        // 按压状态由 PressScale 统一持有，此处只负责按状态渲染图标
        builder: (context, pressed) => SizedBox(
          width: size,
          height: size,
          child: Center(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: pressed ? pressedColor : baseColor),
              duration: duration,
              builder: (context, color, _) => Icon(icon, size: iconSize, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
