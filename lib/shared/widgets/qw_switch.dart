import 'package:flutter/material.dart';

/// 紧凑型自定义开关
///
/// 采用 CustomPainter 直接绘制轨道与滑块，动画由 AnimationController 驱动，
/// 仅触发重绘而不重建组件树；外层包裹 RepaintBoundary 隔离重绘范围，
/// 避免开关动画引起父级组件重绘。
class QwSwitch extends StatefulWidget {
  /// 当前是否处于开启状态
  final bool value;

  /// 状态切换回调；为 null 时开关不可交互
  final ValueChanged<bool>? onChanged;

  /// 开启态轨道颜色，默认跟随主题主色
  final Color? activeColor;

  const QwSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
  });

  @override
  State<QwSwitch> createState() => _QwSwitchState();
}

class _QwSwitchState extends State<QwSwitch>
    with SingleTickerProviderStateMixin {
  /// 控制滑块位置与颜色过渡的动画控制器（0.0 关闭，1.0 开启）
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant QwSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部 value 变化时驱动动画过渡到目标位置
    if (oldWidget.value != widget.value) {
      _controller.animateTo(
        widget.value ? 1.0 : 0.0,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 是否可交互
  bool get _enabled => widget.onChanged != null;

  /// 点击切换状态
  void _handleTap() {
    if (!_enabled) return;
    widget.onChanged!(!widget.value);
  }

  /// 水平拖动时实时跟随滑块位置
  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_enabled) return;
    final travel = _kTrackWidth -
        _kThumbPadding * 2 -
        (_kThumbDiameterOn + _kThumbDiameterOff) / 2;
    _controller.value =
        (_controller.value + details.delta.dx / travel).clamp(0.0, 1.0);
  }

  /// 拖动结束时根据位置与速度吸附到最近端
  void _handleDragEnd(DragEndDetails details) {
    if (!_enabled) return;
    final velocity = details.primaryVelocity ?? 0;
    // 具有明显横向速度时按方向切换，否则按位置是否越过半程判定
    final bool shouldTurnOn = velocity.abs() > 200
        ? velocity > 0
        : _controller.value > 0.5;
    if (shouldTurnOn != widget.value) {
      widget.onChanged!(shouldTurnOn);
    } else {
      // 未越过阈值则回到原位
      _controller.animateTo(
        widget.value ? 1.0 : 0.0,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    final activeColor = widget.activeColor ?? colorScheme.primary;
    // 关闭态轨道色：深浅色主题分别取中性灰，保证与背景有合适对比
    final inactiveTrackColor =
        isDark ? const Color(0xFF3A3A3C) : const Color(0xFFDFDFDF);

    return RepaintBoundary(
      child: Semantics(
        toggled: widget.value,
        enabled: _enabled,
        onTap: _enabled ? _handleTap : null,
        child: MouseRegion(
          cursor:
              _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            // 外层 padding 扩大点击命中区域，视觉尺寸保持紧凑
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: SizedBox(
                width: _kTrackWidth,
                height: _kTrackHeight,
                child: Opacity(
                  opacity: _enabled ? 1.0 : 0.4,
                  child: CustomPaint(
                    painter: _SwitchPainter(
                      animation: _controller,
                      activeTrackColor: activeColor,
                      inactiveTrackColor: inactiveTrackColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 开关尺寸常量
const double _kTrackWidth = 38.0;
const double _kTrackHeight = 22.0;
const double _kThumbDiameterOn = 16.0;
const double _kThumbDiameterOff = 14.0;
const double _kThumbPadding = 3.0;

/// 开关绘制器
///
/// 构造时传入 [Animation] 作为重绘信号源，动画每帧触发重绘而无需外部 setState。
class _SwitchPainter extends CustomPainter {
  /// 驱动重绘的动画
  final Animation<double> animation;

  /// 开启态轨道颜色
  final Color activeTrackColor;

  /// 关闭态轨道颜色
  final Color inactiveTrackColor;

  _SwitchPainter({
    required this.animation,
    required this.activeTrackColor,
    required this.inactiveTrackColor,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;

    // 绘制轨道：圆角矩形，颜色在开关两态间插值过渡
    final trackColor = Color.lerp(inactiveTrackColor, activeTrackColor, t)!;
    final trackRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(trackRRect, Paint()..color = trackColor);

    // 滑块直径在关闭态（小）与开启态（大）之间随动画进度插值
    final thumbDiameter =
        _kThumbDiameterOff + (_kThumbDiameterOn - _kThumbDiameterOff) * t;
    final thumbRadius = thumbDiameter / 2;
    // 滑块圆心 x 在两端中心点之间线性插值，保证两态均贴边垂直居中
    final offCenterX = _kThumbPadding + _kThumbDiameterOff / 2;
    final onCenterX = size.width - _kThumbPadding - _kThumbDiameterOn / 2;
    final thumbCenter = Offset(
      offCenterX + (onCenterX - offCenterX) * t,
      size.height / 2,
    );

    // 滑块投影，增加层次感
    canvas.drawCircle(
      thumbCenter + const Offset(0, 0.5),
      thumbRadius,
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    // 绘制滑块
    canvas.drawCircle(thumbCenter, thumbRadius, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SwitchPainter oldDelegate) {
    return oldDelegate.activeTrackColor != activeTrackColor ||
        oldDelegate.inactiveTrackColor != inactiveTrackColor;
  }
}
