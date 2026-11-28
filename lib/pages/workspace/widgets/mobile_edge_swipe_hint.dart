import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 移动端工作台左右边缘滑动引导
///
/// 全屏蒙版下，手指沿指示轨道滑入并配以主题色辉光，
/// 示意左缘右滑打开目录、右缘左滑打开码字统计；抽屉打开或页面卸载时由调用方关闭
class MobileEdgeSwipeHint {
  MobileEdgeSwipeHint._();

  static OverlayEntry? _entry;

  /// 显示边缘滑动引导
  static void show(BuildContext context) {
    if (_entry != null) return;
    final entry = OverlayEntry(builder: (_) => const _EdgeSwipeHintOverlay());
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  /// 关闭边缘滑动引导
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _EdgeSwipeHintOverlay extends StatefulWidget {
  const _EdgeSwipeHintOverlay();

  @override
  State<_EdgeSwipeHintOverlay> createState() => _EdgeSwipeHintOverlayState();
}

class _EdgeSwipeHintOverlayState extends State<_EdgeSwipeHintOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double width = math.min(280.0, screen.width - 16);
    final double topInset = MediaQuery.paddingOf(context).top;
    // 两组轨道线以内容区中线为轴上下对称，保证到顶部与底部的距离一致
    final double centerY = (screen.height + topInset) / 2;
    final double lineGap = math.min(210.0, math.max(120.0, screen.height * 0.2));
    final double leftLineY = centerY - lineGap / 2;
    final double rightLineY = centerY + lineGap / 2;
    final double leftTop = leftLineY - _SwipeDemo.trackCenterY;
    final double rightTop = rightLineY - _SwipeDemo.trackCenterY;
    final double burstRadiusX = math.min(176.0, screen.width * 0.45);
    final Animation<double> contentFade = CurvedAnimation(
      parent: _enter,
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );

    return IgnorePointer(
      child: Stack(
        children: [
          // 与其他引导保持一致的灰色蒙版
          Positioned.fill(
            child: FadeTransition(
              opacity: _enter,
              child: ColoredBox(
                color: colorScheme.scrim.withValues(alpha: 0.45),
              ),
            ),
          ),
          // 以屏幕边缘为圆心的大范围半椭圆辐射光
          _EdgeBurst(
            isLeft: true,
            centerY: leftLineY,
            radiusX: burstRadiusX,
            radiusY: 244,
            phase: 0,
            loop: _loop,
          ),
          _EdgeBurst(
            isLeft: false,
            centerY: rightLineY,
            radiusX: burstRadiusX,
            radiusY: 244,
            phase: 0.5,
            loop: _loop,
          ),
          _EdgeHint(
            isLeft: true,
            top: leftTop,
            width: width,
            phase: 0,
            fade: contentFade,
            loop: _loop,
            title: '打开目录',
            subtitle: '从屏幕左边缘向右滑动',
          ),
          _EdgeHint(
            isLeft: false,
            top: rightTop,
            width: width,
            phase: 0.5,
            fade: contentFade,
            loop: _loop,
            title: '打开码字统计',
            subtitle: '从屏幕右边缘向左滑动',
          ),
        ],
      ),
    );
  }
}

/// 边缘半椭圆辐射光：圆心落在屏幕边缘的轨道线端点，向内扩散到箭头略外侧
class _EdgeBurst extends StatelessWidget {
  final bool isLeft;
  final double centerY;
  final double radiusX;
  final double radiusY;
  final double phase;
  final Animation<double> loop;

  const _EdgeBurst({
    required this.isLeft,
    required this.centerY,
    required this.radiusX,
    required this.radiusY,
    required this.phase,
    required this.loop,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return Positioned(
      left: isLeft ? -radiusX : null,
      right: isLeft ? null : -radiusX,
      top: centerY - radiusY,
      width: radiusX * 2,
      height: radiusY * 2,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final double t = (loop.value + phase) % 1.0;
          final double breath =
              0.84 + 0.16 * (0.5 + 0.5 * math.sin(t * math.pi * 2));
          return CustomPaint(
            painter: _BurstPainter(color: primary, opacity: breath),
          );
        },
      ),
    );
  }
}

/// 将圆形径向渐变压成椭圆，随透明度呼吸
class _BurstPainter extends CustomPainter {
  final Color color;
  final double opacity;

  const _BurstPainter({required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2;
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.42 * opacity),
          color.withValues(alpha: 0.2 * opacity),
          color.withValues(alpha: 0.05 * opacity),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.4, 0.75, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, size.height / size.width);
    canvas.drawCircle(Offset.zero, radius, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}

/// 单侧手势提示：滑动手势演示 + 说明文案
class _EdgeHint extends StatelessWidget {
  final bool isLeft;
  final double top;
  final double width;
  final double phase;
  final Animation<double> fade;
  final Animation<double> loop;
  final String title;
  final String subtitle;

  const _EdgeHint({
    required this.isLeft,
    required this.top,
    required this.width,
    required this.phase,
    required this.fade,
    required this.loop,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: top,
      width: width,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: fade,
          child: Column(
            children: [
              Align(
                alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
                child: _SwipeDemo(isLeft: isLeft, loop: loop, phase: phase),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.labelLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0.5,
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  letterSpacing: 0.3,
                  color: Colors.white.withValues(alpha: 0.78),
                  shadows: const [
                    Shadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手势演示：箭头末端为圆心的主题色辉光、指示轨道与循环滑入的手指
class _SwipeDemo extends StatelessWidget {
  static const double _width = 140;
  static const double _height = 58;
  static const double _travel = 76;

  /// 轨道中线距演示区顶部的距离，边缘辐射光据此对齐
  static const double trackCenterY = 29;

  final bool isLeft;
  final Animation<double> loop;
  final double phase;

  const _SwipeDemo({
    required this.isLeft,
    required this.loop,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final double t = (loop.value + phase) % 1.0;
          final double move =
              Curves.easeInOutCubic.transform(((t - 0.08) / 0.55).clamp(0.0, 1.0));
          final double handOpacity = t < 0.08
              ? t / 0.08
              : (t < 0.66 ? 1.0 : ((0.9 - t) / 0.24).clamp(0.0, 1.0));

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 指示轨道
              Positioned(
                left: isLeft ? 4 : null,
                right: isLeft ? null : 4,
                top: 28,
                width: 118,
                height: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    gradient: LinearGradient(
                      begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
                      end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
              ),
              // 方向箭头
              Positioned(
                left: isLeft ? 116 : null,
                right: isLeft ? null : 116,
                top: 17,
                child: Icon(
                  isLeft ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                  size: 24,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              // 手指沿轨道滑入
              Positioned(
                left: isLeft ? move * _travel : null,
                right: isLeft ? null : move * _travel,
                top: 11,
                child: Opacity(
                  opacity: handOpacity,
                  child: const Icon(
                    Icons.touch_app_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
