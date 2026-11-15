import 'package:flutter/material.dart';

/// 按下缩放组件
///
/// 包裹任意子组件，按下时整体缩小、松开或取消触摸后恢复原大小，
/// 用于为无背景的按钮类元素提供轻量的点击反馈。
class PressScale extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 点击回调，为 null 时组件不可交互且无缩放反馈
  final VoidCallback? onTap;

  /// 按下时的缩放比例
  final double pressedScale;

  /// 缩放动画时长
  final Duration duration;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.85,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  /// 是否处于按下状态
  bool _pressed = false;

  /// 是否可交互
  bool get _enabled => widget.onTap != null;

  @override
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 交互被禁用时复位，避免保持缩小状态
    if (!_enabled && _pressed) {
      _pressed = false;
    }
  }

  /// 结束按下状态
  void _release() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _enabled
          ? (_) {
              _release();
              widget.onTap!();
            }
          : null,
      onTapCancel: _enabled ? _release : null,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
