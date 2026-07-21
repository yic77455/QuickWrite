import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 提示框显示方向
enum TooltipDirection { top, bottom, left, right }

/// ---------------------------------------------------------
/// 鼠标右下角提示框组件
///
/// 显示在鼠标光标右下方的提示框，适用于工具栏按钮等场景
/// 使用 Overlay 实现
/// ---------------------------------------------------------
class CursorTooltip {
  /// 当前显示的 OverlayEntry
  static OverlayEntry? _overlayEntry;

  /// 当前提示框 Widget 的 State Key
  static GlobalKey<_CursorTooltipWidgetState>? _tooltipKey;

  /// 是否正在播放退出动画
  static bool _isHiding = false;

  /// 显示提示框
  ///
  /// [context] - BuildContext，用于获取 Overlay 和 Theme
  /// [content] - 提示框内容 Widget
  /// [cursorOffset] - 鼠标光标位置
  /// [offsetX] - 相对于鼠标的 X 偏移量
  /// [offsetY] - 相对于鼠标的 Y 偏移量
  static void show({
    required BuildContext context,
    required Widget content,
    required Offset cursorOffset,
    double offsetX = 2,
    double offsetY = 20,
  }) {
    // 如果正在播放退出动画，立即移除旧提示框
    if (_overlayEntry != null) {
      _removeOverlayImmediately();
    }

    _isHiding = false;

    // 创建用于访问 State 的 Key
    _tooltipKey = GlobalKey<_CursorTooltipWidgetState>();

    final overlay = Overlay.of(context);

    // 获取主题中的 tooltip 样式
    final tooltipTheme = Theme.of(context).tooltipTheme;

    // 获取屏幕大小用于边缘检测
    final screenSize = MediaQuery.of(context).size;

    // 创建 OverlayEntry
    _overlayEntry = OverlayEntry(
      builder: (context) => _CursorTooltipWidget(
        key: _tooltipKey,
        cursorOffset: cursorOffset,
        offsetX: offsetX,
        offsetY: offsetY,
        screenSize: screenSize,
        tooltipTheme: tooltipTheme,
        content: content,
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  /// 隐藏提示框（带退出动画）
  static void hide() {
    if (_isHiding || _overlayEntry == null) return;

    _isHiding = true;

    // 触发退出动画
    _tooltipKey?.currentState?.animateOut(() {
      _removeOverlayImmediately();
    });
  }

  /// 立即移除 Overlay（无动画）
  static void _removeOverlayImmediately() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _tooltipKey = null;
    _isHiding = false;
  }
}

/// ---------------------------------------------------------
/// 鼠标右下角提示框 Widget
/// ---------------------------------------------------------
class _CursorTooltipWidget extends StatefulWidget {
  final Offset cursorOffset;
  final double offsetX;
  final double offsetY;
  final Size screenSize;
  final TooltipThemeData tooltipTheme;
  final Widget content;

  const _CursorTooltipWidget({
    super.key,
    required this.cursorOffset,
    required this.offsetX,
    required this.offsetY,
    required this.screenSize,
    required this.tooltipTheme,
    required this.content,
  });

  @override
  State<_CursorTooltipWidget> createState() => _CursorTooltipWidgetState();
}

class _CursorTooltipWidgetState extends State<_CursorTooltipWidget>
    with SingleTickerProviderStateMixin {
  // 动画控制器
  late AnimationController _controller;
  // 淡入淡出动画
  late Animation<double> _fadeAnimation;

  // 是否正在退出
  bool _isExiting = false;

  // tooltip 的 key，用于获取实际大小
  final GlobalKey _tooltipKey = GlobalKey();

  // tooltip 实际大小
  Size _tooltipSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    // 播放进入动画
    _controller.forward();

    // 在下一帧获取 tooltip 大小
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTooltipSize();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 测量 tooltip 的实际大小
  void _measureTooltipSize() {
    final renderBox =
        _tooltipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && mounted) {
      setState(() {
        _tooltipSize = renderBox.size;
      });
    }
  }

  /// 计算提示框位置
  /// 始终显示在鼠标右下角，位于边缘时调整位置确保不超出边界
  Offset _calculatePosition() {
    double x = widget.cursorOffset.dx + widget.offsetX;
    double y = widget.cursorOffset.dy + widget.offsetY;

    // 如果 tooltip 大小已知，进行边缘检测
    if (_tooltipSize != Size.zero) {
      // 右边缘检测：如果超出右边界，让 tooltip 右边与窗口右边界对齐
      if (x + _tooltipSize.width > widget.screenSize.width) {
        x = widget.screenSize.width - _tooltipSize.width;
      }

      // 下边缘检测：如果超出下边界，让 tooltip 下边与窗口下边界对齐
      if (y + _tooltipSize.height > widget.screenSize.height) {
        y = widget.screenSize.height - _tooltipSize.height;
      }
    }

    // 确保不会超出左边界和上边界
    x = x.clamp(0.0, widget.screenSize.width);
    y = y.clamp(0.0, widget.screenSize.height);

    return Offset(x, y);
  }

  /// 播放退出动画
  void animateOut(VoidCallback onComplete) {
    if (_isExiting) return;
    _isExiting = true;

    _controller.reverse().then((_) {
      if (mounted) {
        onComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = _calculatePosition();

    return Stack(
      children: [
        Positioned(
          left: position.dx,
          top: position.dy,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildTooltipContent(),
          ),
        ),
      ],
    );
  }

  /// 构建提示框内容（使用主题中的 tooltip 样式）
  Widget _buildTooltipContent() {
    // 从主题获取样式，如果没有则使用默认值
    final decoration = widget.tooltipTheme.decoration ?? 
        BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3C3C3C).withValues(alpha: 0.2),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
        );
    
    final textStyle = widget.tooltipTheme.textStyle ??
        context.bodySmall ??
        const TextStyle();

    return Container(
      key: _tooltipKey,
      decoration: decoration,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: DefaultTextStyle(
          style: textStyle,
          child: widget.content,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------
/// 鼠标右下角提示框目标组件包装器
///
/// 使用方式：
/// ```dart
/// CursorTooltipTarget(
///   tooltipContent: Text('提示内容'),  // 提示框内容
///   child: YourWidget(),              // 触发提示的组件
/// )
/// ```
/// ---------------------------------------------------------
class CursorTooltipTarget extends StatefulWidget {
  /// 子组件（触发提示框的目标）
  final Widget child;

  /// 提示框内容
  final Widget tooltipContent;

  /// 是否显示提示框
  final bool showTooltip;

  const CursorTooltipTarget({
    super.key,
    required this.child,
    required this.tooltipContent,
    this.showTooltip = true,
  });

  @override
  State<CursorTooltipTarget> createState() => _CursorTooltipTargetState();
}

class _CursorTooltipTargetState extends State<CursorTooltipTarget> {
  /// 鼠标是否悬停在目标组件上
  bool _isHovering = false;

  /// 提示框是否已显示
  bool _isTooltipShown = false;

  /// 是否已点击组件（点击后不再显示tooltip）
  bool _isClicked = false;

  /// 延迟显示提示框的定时器
  Timer? _showTooltipTimer;

  /// 最后一次鼠标位置（用于显示tooltip时使用最新位置）
  Offset? _lastCursorPosition;

  /// 提示框显示延迟时间（毫秒）
  static const int _showDelayMilliseconds = 500;

  @override
  void didUpdateWidget(CursorTooltipTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 showTooltip 变为 false 时，取消定时器并隐藏提示框
    if (!widget.showTooltip && oldWidget.showTooltip) {
      _showTooltipTimer?.cancel();
      CursorTooltip.hide();
      _isTooltipShown = false;
    }
  }

  @override
  void dispose() {
    _showTooltipTimer?.cancel();
    if (_isHovering) {
      CursorTooltip.hide();
    }
    super.dispose();
  }

  /// 开始延迟显示计时
  void _startShowTimer(Offset cursorOffset) {
    // 如果已点击，不显示tooltip
    if (_isClicked) return;

    // 更新最后鼠标位置
    _lastCursorPosition = cursorOffset;

    // 取消现有计时器
    _showTooltipTimer?.cancel();
    _showTooltipTimer = null;

    // 开始新的计时
    _showTooltipTimer = Timer(
      const Duration(milliseconds: _showDelayMilliseconds),
      () {
        // 定时器触发时，检查组件是否仍然存在且鼠标仍在悬停
        if (!mounted || !_isHovering || _isClicked) return;
        // 使用最后的鼠标位置显示 tooltip
        if (_lastCursorPosition != null) {
          _showTooltip(_lastCursorPosition!);
          _isTooltipShown = true;
        }
        _showTooltipTimer = null;
      },
    );
  }

  /// 处理点击事件
  void _handleTap() {
    // 取消计时器
    _showTooltipTimer?.cancel();
    _showTooltipTimer = null;
    // 隐藏已显示的提示框
    CursorTooltip.hide();
    _isTooltipShown = false;
    // 标记已点击
    _isClicked = true;
  }

  /// 显示提示框
  void _showTooltip(Offset cursorOffset) {
    CursorTooltip.show(
      context: context,
      content: widget.tooltipContent,
      cursorOffset: cursorOffset,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // 监听原始指针事件，不会被按钮等组件拦截
      onPointerDown: (_) => _handleTap(),
      child: MouseRegion(
        // 鼠标进入组件
        onEnter: (event) {
          _isHovering = true;
          if (widget.showTooltip && !_isTooltipShown && !_isClicked) {
            _startShowTimer(event.position);
          }
        },
        // 鼠标在组件内移动
        // 如果提示框已显示或已点击，不做任何事
        // 如果提示框未显示，重置计时器
        onHover: (event) {
          if (widget.showTooltip && !_isTooltipShown && !_isClicked) {
            _startShowTimer(event.position);
          }
        },
        // 鼠标离开组件
        onExit: (_) {
          _isHovering = false;
          _isTooltipShown = false;
          _isClicked = false;
          _lastCursorPosition = null;
          _showTooltipTimer?.cancel();
          _showTooltipTimer = null;
          if (widget.showTooltip) {
            CursorTooltip.hide();
          }
        },
        child: widget.child,
      ),
    );
  }
}

/// 带箭头的提示框组件
/// 
/// - 支持自定义提示框与目标组件位置、显示方向、箭头大小、间距
class ArrowTooltip {
  /// 当前显示的 OverlayEntry
  static OverlayEntry? _overlayEntry;

  /// 鼠标是否悬停在提示框上
  static bool _isHoveringTooltip = false;

  /// 当前提示框的唯一ID
  /// 用于区分不同图标的提示框，避免延迟任务相互干扰
  static int _currentId = 0;

  /// 当前提示框 Widget 的 State Key
  /// 用于触发退出动画
  static GlobalKey<_ArrowTooltipWidgetState>? _tooltipKey;

  /// 是否正在播放退出动画
  static bool _isHiding = false;

  /// 显示提示框，返回提示框ID
  ///
  /// [context] - BuildContext，用于获取 Overlay 和 Theme
  /// [content] - 提示框内容 Widget
  /// [targetRect] - 目标组件的位置和大小
  /// [direction] - 提示框相对于目标组件的显示方向
  /// [arrowSize] - 箭头大小
  /// [gap] - 提示框与目标组件的间距
  static int show({
    required BuildContext context,
    required Widget content,
    required Rect targetRect,
    TooltipDirection direction = TooltipDirection.right,
    double arrowSize = 6,
    double gap = 4,
  }) {
    // 如果正在播放退出动画，等待动画完成
    // 这里直接立即移除旧提示框，不等待动画
    if (_overlayEntry != null) {
      _removeOverlayImmediately();
    }

    // 生成新的唯一ID
    _currentId++;
    final tooltipId = _currentId;
    _isHiding = false;

    // 创建用于访问 State 的 Key
    _tooltipKey = GlobalKey<_ArrowTooltipWidgetState>();

    final overlay = Overlay.of(context);

    // 从主题中提取 tooltip 背景色
    final tooltipTheme = Theme.of(context).tooltipTheme;
    final decoration = tooltipTheme.decoration;
    final Color backgroundColor;
    if (decoration is BoxDecoration && decoration.color != null) {
      backgroundColor = decoration.color!;
    } else {
      // 兜底：使用主题的 surfaceContainerHighest
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    }

    // 创建 OverlayEntry
    _overlayEntry = OverlayEntry(
      builder: (context) => _ArrowTooltipWidget(
        key: _tooltipKey,
        tooltipId: tooltipId,
        targetRect: targetRect,
        direction: direction,
        arrowSize: arrowSize,
        gap: gap,
        backgroundColor: backgroundColor,
        content: content,
        onHoverChanged: (isHovering) {
          _isHoveringTooltip = isHovering;
        },
        onTooltipExit: () {
          // 鼠标离开提示框时，如果当前显示的还是这个提示框，则隐藏
          if (_currentId == tooltipId && !_isHiding) {
            hide();
          }
        },
      ),
    );

    overlay.insert(_overlayEntry!);
    return tooltipId;
  }

  /// 隐藏提示框
  static void hide() {
    // 如果正在隐藏或没有显示的提示框，直接返回
    if (_isHiding || _overlayEntry == null) return;

    _isHiding = true;

    // 触发退出动画
    _tooltipKey?.currentState?.animateOut(() {
      // 动画完成后真正移除 Overlay
      _removeOverlayImmediately();
    });
  }

  /// 立即移除 Overlay
  static void _removeOverlayImmediately() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _tooltipKey = null;
    _isHoveringTooltip = false;
    _isHiding = false;
  }

  /// 获取鼠标是否悬停在提示框上
  static bool get isHoveringTooltip => _isHoveringTooltip;

  /// 检查指定ID是否是当前显示的提示框
  static bool isCurrentTooltip(int? tooltipId) {
    return tooltipId != null && tooltipId == _currentId;
  }
}

/// ---------------------------------------------------------
/// 箭头提示框 Widget
/// ---------------------------------------------------------
class _ArrowTooltipWidget extends StatefulWidget {
  final int tooltipId;
  final Rect targetRect;
  final TooltipDirection direction;
  final double arrowSize;
  final double gap;
  final Color backgroundColor;
  final Widget content;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTooltipExit;

  const _ArrowTooltipWidget({
    super.key,
    required this.tooltipId,
    required this.targetRect,
    required this.direction,
    required this.arrowSize,
    required this.gap,
    required this.backgroundColor,
    required this.content,
    required this.onHoverChanged,
    required this.onTooltipExit,
  });

  @override
  State<_ArrowTooltipWidget> createState() => _ArrowTooltipWidgetState();
}

class _ArrowTooltipWidgetState extends State<_ArrowTooltipWidget>
    with SingleTickerProviderStateMixin {
  // 动画控制器
  late AnimationController _controller;
  // 淡入淡出动画
  late Animation<double> _fadeAnimation;
  // 缩放动画
  late Animation<double> _scaleAnimation;

  // 是否正在退出
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    // 从 0.9 缩放到 1.0，产生弹出效果
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    // 播放进入动画
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 播放退出动画
  /// [onComplete] - 动画完成回调
  void animateOut(VoidCallback onComplete) {
    if (_isExiting) return;
    _isExiting = true;

    // 反向播放动画（淡出 + 缩小）
    _controller.reverse().then((_) {
      if (mounted) {
        onComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 使用 Positioned 定位提示框
        Positioned(
          // 提示框左侧位置 = 目标组件右边缘 + 间距
          left: widget.targetRect.right + widget.gap,
          // 提示框顶部位置 = 目标组件中心 - 预估提示框高度的一半
          // 减去额外的偏移量，让提示框位置往上调整
          top:
              widget.targetRect.top +
              widget.targetRect.height / 2 -
              _estimateTooltipHeight() / 2 -
              8,
          child: MouseRegion(
            // 鼠标进入提示框时，通知父组件
            onEnter: (_) => widget.onHoverChanged(true),
            // 鼠标离开提示框时，通知父组件并触发隐藏
            onExit: (_) {
              widget.onHoverChanged(false);
              widget.onTooltipExit();
            },
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: _buildTooltipWithArrow(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 预估提示框高度（用于垂直居中定位）
  double _estimateTooltipHeight() {
    // 箭头高度
    return widget.arrowSize * 2;
  }

  /// 构建带箭头的提示框
  Widget _buildTooltipWithArrow() {
    // 箭头长度（水平方向）
    final arrowLength = widget.arrowSize * 1.2;
    // 箭头高度（垂直方向）
    final arrowHeight = widget.arrowSize * 2;

    return IntrinsicWidth(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 主体内容
          // 左侧留出箭头长度，使箭头尖端从主体左边缘伸出
          Padding(
            padding: EdgeInsets.only(left: arrowLength),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: Material(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(6),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: widget.content,
                ),
              ),
            ),
          ),
          // 箭头：位于主体左侧并绘制在主体之上，避免被主体阴影覆盖
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: arrowLength,
            child: Center(
              child: CustomPaint(
                size: Size(arrowLength, arrowHeight),
                painter: _ArrowPainter(
                  color: widget.backgroundColor,
                  width: arrowLength,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 箭头绘制器
class _ArrowPainter extends CustomPainter {
  final Color color;
  final double width;

  _ArrowPainter({required this.color, required this.width});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    // 绘制向左指的三角形箭头
    // 尖端在左边，底部在右边
    path.moveTo(0, canvasSize.height / 2); // 箭头尖端
    path.lineTo(width, 0); // 右上角
    path.lineTo(width, canvasSize.height); // 右下角
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) {
    return color != oldDelegate.color || width != oldDelegate.width;
  }
}

/// ---------------------------------------------------------
/// 提示框目标组件包装器
///
/// 使用方式：
/// ```dart
/// TooltipTarget(
///   showTooltip: true,                    // 是否显示提示框
///   direction: TooltipDirection.right,    // 提示框显示方向
///   tooltipContent: Text('提示内容'),      // 提示框内容
///   child: YourWidget(),                  // 触发提示的组件
/// )
/// ```
/// ---------------------------------------------------------
class TooltipTarget extends StatefulWidget {
  /// 子组件（触发提示框的目标）
  final Widget child;

  /// 提示框内容
  final Widget tooltipContent;

  /// 提示框显示方向
  final TooltipDirection direction;

  /// 是否显示提示框
  /// 用于外部控制（如导航栏展开时禁用提示）
  final bool showTooltip;

  const TooltipTarget({
    super.key,
    required this.child,
    required this.tooltipContent,
    this.direction = TooltipDirection.right,
    this.showTooltip = false,
  });

  @override
  State<TooltipTarget> createState() => _TooltipTargetState();
}

class _TooltipTargetState extends State<TooltipTarget> {
  /// 目标组件的 GlobalKey，用于获取位置信息
  final GlobalKey _targetKey = GlobalKey();

  /// 鼠标是否悬停在目标组件上
  bool _isHovering = false;

  /// 当前显示的提示框ID
  /// 用于判断延迟隐藏任务是否应该执行
  int? _currentTooltipId;

  /// 延迟显示提示框的定时器
  Timer? _showTooltipTimer;

  /// 提示框显示延迟时间（毫秒）
  static const int _showDelayMilliseconds = 300;

  @override
  void didUpdateWidget(TooltipTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 showTooltip 变为 false 时，取消定时器并隐藏提示框
    if (!widget.showTooltip && oldWidget.showTooltip) {
      _showTooltipTimer?.cancel();
      ArrowTooltip.hide();
    }
  }

  @override
  void dispose() {
    // 取消延迟显示的定时器
    _showTooltipTimer?.cancel();
    // 组件销毁时隐藏提示框
    if (_isHovering) {
      ArrowTooltip.hide();
    }
    super.dispose();
  }

  /// 请求显示提示框（带延迟）
  void _requestShowTooltip() {
    // 取消之前的定时器
    _showTooltipTimer?.cancel();

    // 设置延迟显示的定时器
    _showTooltipTimer = Timer(
      const Duration(milliseconds: _showDelayMilliseconds),
      () {
        // 定时器触发时，检查组件是否仍然存在且鼠标仍在悬停
        if (!mounted || !_isHovering) return;

        // 执行显示
        _showTooltip();
      },
    );
  }

  /// 显示提示框
  void _showTooltip() {
    // 获取目标组件的 RenderBox
    final renderBox =
        _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 计算目标组件在屏幕上的位置
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final targetRect = offset & size;

    // 显示提示框并记录ID
    _currentTooltipId = ArrowTooltip.show(
      context: context,
      content: widget.tooltipContent,
      targetRect: targetRect,
      direction: widget.direction,
    );
  }

  /// 请求隐藏提示框
  /// 会延迟一小段时间，检查鼠标是否移入了提示框
  void _requestHide() {
    // 记录当前要隐藏的提示框ID
    final tooltipIdToHide = _currentTooltipId;

    // 延迟检查，给鼠标移入提示框的时间
    Future.delayed(const Duration(milliseconds: 100), () {
      // 如果组件已销毁，不执行
      if (!mounted) return;

      // 如果当前显示的提示框已经不是要隐藏的那个，则忽略此请求
      // 这解决了快速切换图标时，旧图标的隐藏任务影响新提示框的问题
      if (!ArrowTooltip.isCurrentTooltip(tooltipIdToHide)) return;

      // 如果鼠标在提示框上，不隐藏
      if (ArrowTooltip.isHoveringTooltip) return;

      // 隐藏提示框
      ArrowTooltip.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      key: _targetKey,
      // 鼠标进入目标组件
      onEnter: (_) {
        _isHovering = true;
        if (widget.showTooltip) {
          _requestShowTooltip();
        }
      },
      // 鼠标离开目标组件
      onExit: (_) {
        _isHovering = false;
        // 取消延迟显示的定时器
        _showTooltipTimer?.cancel();
        if (widget.showTooltip) {
          _requestHide();
        }
      },
      child: widget.child,
    );
  }
}

/// ---------------------------------------------------------
/// 跟随鼠标的提示框
///
/// 通过 Overlay 显示，实时跟随鼠标位置；
/// 基于外部传入的 [Rect] 区域进行边缘检测：
/// 优先显示在鼠标右下方，空间不足时按 右上 > 左下 > 左上 顺序回退
/// （右优先于左，下优先于上）。
///
/// 使用 StatefulWidget + GlobalKey 自管理所有可变状态（位置、区域、内容），
/// 外部通过 [update] / [updatePosition] 更新，不调用 markNeedsBuild，
/// 避免 widget 子树重建导致闪烁。
/// ---------------------------------------------------------
class FollowTooltip {
  /// 当前显示的 OverlayEntry
  static OverlayEntry? _overlayEntry;

  /// tooltip Widget 的 State Key，用于直接更新状态避免重建
  static GlobalKey<_FollowTooltipWidgetState>? _tooltipKey;

  /// 当前是否正在显示
  static bool get isShowing => _overlayEntry != null;

  /// 显示提示框
  ///
  /// [context] - BuildContext，用于获取 Overlay
  /// [cursorPosition] - 鼠标全局坐标
  /// [region] - 边缘检测区域（全局坐标），tooltip 不会超出此区域
  /// [child] - 提示框内容 Widget
  static void show({
    required BuildContext context,
    required Offset cursorPosition,
    required Rect region,
    required Widget child,
  }) {
    // 已有显示时先移除
    if (_overlayEntry != null) {
      _removeImmediately();
    }

    _tooltipKey = GlobalKey<_FollowTooltipWidgetState>();

    _overlayEntry = OverlayEntry(
      builder: (_) => _FollowTooltipWidget(
        key: _tooltipKey,
        initialPosition: cursorPosition,
        region: region,
        child: child,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 更新位置、区域和内容
  static void update(Offset cursorPosition, Rect region, Widget child) {
    _tooltipKey?.currentState?.update(cursorPosition, region, child);
  }

  /// 仅更新位置和区域（内容不变时使用，性能更好）
  static void updatePosition(Offset cursorPosition, Rect region) {
    _tooltipKey?.currentState?.updatePosition(cursorPosition, region);
  }

  /// 隐藏提示框
  static void hide() {
    _removeImmediately();
  }

  /// 立即移除 Overlay
  static void _removeImmediately() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _tooltipKey = null;
  }
}

/// 跟随鼠标提示框相对鼠标的方位
enum FollowTooltipCorner {
  /// 鼠标右下方
  bottomRight,
  /// 鼠标左下方
  bottomLeft,
  /// 鼠标右上方
  topRight,
  /// 鼠标左上方
  topLeft,
}

/// ---------------------------------------------------------
/// 跟随鼠标提示框 Widget
/// ---------------------------------------------------------
class _FollowTooltipWidget extends StatefulWidget {
  /// 初始鼠标全局坐标
  final Offset initialPosition;

  /// 边缘检测区域（全局坐标）
  final Rect region;

  /// 提示框内容
  final Widget child;

  const _FollowTooltipWidget({
    super.key,
    required this.initialPosition,
    required this.region,
    required this.child,
  });

  @override
  State<_FollowTooltipWidget> createState() => _FollowTooltipWidgetState();
}

class _FollowTooltipWidgetState extends State<_FollowTooltipWidget> {
  /// 当前鼠标全局坐标
  late Offset _position;

  /// 当前边缘检测区域
  late Rect _region;

  /// 当前内容
  late Widget _child;

  /// tooltip 实际尺寸（测量后填充，用于判断空间是否充足）
  Size _tooltipSize = Size.zero;

  /// 内容容器的 Key，用于测量尺寸
  final GlobalKey _contentKey = GlobalKey();

  /// 鼠标与 tooltip 之间的间距
  static const double _gap = 16.0;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _region = widget.region;
    _child = widget.child;
    // 下一帧测量 tooltip 实际尺寸，用于判断空间是否充足
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSize();
    });
  }

  /// 测量 tooltip 实际尺寸
  void _measureSize() {
    final renderBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && mounted) {
      final newSize = renderBox.size;
      if (newSize != _tooltipSize) {
        setState(() {
          _tooltipSize = newSize;
        });
      }
    }
  }

  /// 更新位置、区域和内容
  void update(Offset position, Rect region, Widget child) {
    setState(() {
      _position = position;
      _region = region;
      _child = child;
    });
    // 内容变化后重新测量尺寸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSize();
    });
  }

  /// 仅更新位置和区域（内容不变时使用）
  void updatePosition(Offset position, Rect region) {
    if (_position == position && _region == region) return;
    setState(() {
      _position = position;
      _region = region;
    });
  }

  /// 计算方位
  ///
  /// 基于 [_region] 边缘检测，优先级：右下 > 右上 > 左下 > 左上
  /// （右优先于左，下优先于上）。
  /// 尚未测量出 tooltip 尺寸时默认显示在右下。
  FollowTooltipCorner _calculateCorner() {
    // 尚未测量出尺寸时默认右下
    if (_tooltipSize == Size.zero) {
      return FollowTooltipCorner.bottomRight;
    }

    final rightSpace = _region.right - _position.dx - _gap;
    final bottomSpace = _region.bottom - _position.dy - _gap;
    final showOnRight = rightSpace >= _tooltipSize.width;
    final showOnBottom = bottomSpace >= _tooltipSize.height;

    if (showOnRight && showOnBottom) return FollowTooltipCorner.bottomRight;
    if (showOnRight) return FollowTooltipCorner.topRight;
    if (showOnBottom) return FollowTooltipCorner.bottomLeft;
    return FollowTooltipCorner.topLeft;
  }

  @override
  Widget build(BuildContext context) {
    final corner = _calculateCorner();
    double left;
    double top;
    Offset translation;

    switch (corner) {
      case FollowTooltipCorner.bottomRight:
        // tooltip 左上角对齐鼠标+间距
        left = _position.dx + _gap;
        top = _position.dy + _gap;
        translation = Offset.zero;
        break;
      case FollowTooltipCorner.bottomLeft:
        // tooltip 右上角对齐鼠标-间距
        left = _position.dx - _gap;
        top = _position.dy + _gap;
        translation = const Offset(-1.0, 0.0);
        break;
      case FollowTooltipCorner.topRight:
        // tooltip 左下角对齐鼠标+间距
        left = _position.dx + _gap;
        top = _position.dy - _gap;
        translation = const Offset(0.0, -1.0);
        break;
      case FollowTooltipCorner.topLeft:
        // tooltip 右下角对齐鼠标-间距
        left = _position.dx - _gap;
        top = _position.dy - _gap;
        translation = const Offset(-1.0, -1.0);
        break;
    }

    return Positioned(
      left: left,
      top: top,
      child: FractionalTranslation(
        translation: translation,
        child: KeyedSubtree(
          key: _contentKey,
          child: _child,
        ),
      ),
    );
  }
}
