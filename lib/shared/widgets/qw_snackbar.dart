import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 全局 SnackBar 服务
/// 
/// 提供统一的浮动提示显示，优化显示逻辑：
/// - 新提示会立即替换当前显示的提示
/// - 统一样式：圆角、居中、自适应内容大小
/// - 使用 Overlay 实现，不影响底部区域的点击操作
class SnackBarService {
  SnackBarService._();
  
  static final SnackBarService instance = SnackBarService._();
  
  /// 当前显示的 OverlayEntry
  static OverlayEntry? _currentEntry;
  
  /// 当前显示的定时器
  static Timer? _currentTimer;
  
  /// 显示浮动提示
  /// 
  /// [context] 上下文
  /// [message] 提示消息
  /// [duration] 显示时长，默认 3 秒
  static void show(BuildContext context, String message, {Duration? duration}) {
    showOnOverlay(Overlay.of(context), message, duration: duration);
  }

  /// 在指定的 Overlay 上显示浮动提示
  ///
  /// 适用于没有页面上下文的场景（如通过根导航器从服务层发起提示），
  /// 此时无法通过 [show] 查找 Overlay
  static void showOnOverlay(
    OverlayState overlay,
    String message, {
    Duration? duration,
  }) {
    // 立即清除当前显示的提示
    _dismissCurrent();

    // 创建 OverlayEntry
    _currentEntry = OverlayEntry(
      builder: (context) => _SnackBarOverlay(message: message),
    );

    // 插入 Overlay
    overlay.insert(_currentEntry!);

    // 设置自动消失定时器
    _currentTimer = Timer(duration ?? const Duration(seconds: 3), () {
      _dismissCurrent();
    });
  }
  
  /// 清除当前显示的提示
  static void _dismissCurrent() {
    _currentTimer?.cancel();
    _currentTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
  
  /// 显示成功提示
  static void showSuccess(BuildContext context, String message, {Duration? duration}) {
    show(context, message, duration: duration);
  }
  
  /// 显示错误提示
  static void showError(BuildContext context, String message, {Duration? duration}) {
    show(context, message, duration: duration ?? const Duration(seconds: 3));
  }
}

/// SnackBar Overlay 组件
/// 
/// 使用 Positioned 定位在底部居中，只占用实际显示区域
/// 其他区域的点击事件正常传递到下层组件
class _SnackBarOverlay extends StatefulWidget {
  final String message;
  
  const _SnackBarOverlay({required this.message});
  
  @override
  State<_SnackBarOverlay> createState() => _SnackBarOverlayState();
}

class _SnackBarOverlayState extends State<_SnackBarOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // 初始化动画控制器
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // 淡入动画
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    
    // 从下往上滑入动画
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    
    // 启动入场动画
    _controller.forward();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: context.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
