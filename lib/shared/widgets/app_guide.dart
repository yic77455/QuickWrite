import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';

/// 一次性引导：遮罩非重点区域并拦截交互，气泡锚定目标控件，按 ID 记忆避免重复打扰
class AppGuide {
  AppGuide._();

  static OverlayEntry? _activeEntry;
  static _GuideRequest? _activeRequest;
  static final List<_GuideRequest> _queue = [];

  /// 展示引导并返回可提前关闭的句柄；已有引导时排队，关闭后依次展示
  /// 已展示过的 ID 返回 null
  static GuideHandle? showOnce({
    required BuildContext context,
    required String id,
    required GlobalKey targetKey,
    required String message,
    String title = '提示',
    String buttonText = '知道了',
  }) {
    // 目标未布局时不弹引导，避免遮罩挡住界面却没有可见提示
    final renderObject = targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    if (MiscCacheService.instance.isGuideShown(id)) return null;
    final request = _GuideRequest(
      id: id,
      overlay: Overlay.of(context),
      targetKey: targetKey,
      title: title,
      message: message,
      buttonText: buttonText,
    );
    if (_activeEntry == null) {
      _show(request);
    } else {
      _queue.add(request);
    }
    return GuideHandle(request);
  }

  /// 关闭当前引导并展示队列中的下一个
  static void dismiss() {
    if (_activeRequest == null) return;
    _removeActive();
    _showNext();
  }

  static void _cancel(_GuideRequest request) {
    request.cancelled = true;
    if (identical(request, _activeRequest)) {
      dismiss();
    } else {
      _queue.remove(request);
    }
  }

  static bool _show(_GuideRequest request) {
    if (request.cancelled || !request.overlay.mounted) return false;
    final renderObject = request.targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final entry = OverlayEntry(
      builder: (_) => _GuideTip(
        targetKey: request.targetKey,
        title: request.title,
        message: request.message,
        buttonText: request.buttonText,
        onDismiss: dismiss,
      ),
    );
    _activeEntry = entry;
    _activeRequest = request;
    request.overlay.insert(entry);
    // 排队项可能在展示前被取消，因此真正显示时才记为已展示
    unawaited(MiscCacheService.instance.markGuideShown(request.id));
    return true;
  }

  static void _showNext() {
    if (_activeEntry != null) return;
    while (_queue.isNotEmpty) {
      if (_show(_queue.removeAt(0))) return;
    }
  }

  static void _removeActive() {
    _activeEntry?.remove();
    _activeEntry = null;
    _activeRequest = null;
  }
}

/// 等待展示的引导请求
class _GuideRequest {
  final String id;
  final OverlayState overlay;
  final GlobalKey targetKey;
  final String title;
  final String message;
  final String buttonText;
  bool cancelled = false;

  _GuideRequest({
    required this.id,
    required this.overlay,
    required this.targetKey,
    required this.title,
    required this.message,
    required this.buttonText,
  });
}

/// 引导句柄，页面卸载时可主动关闭
class GuideHandle {
  final Object _request;

  const GuideHandle(this._request);

  void dismiss() => AppGuide._cancel(_request as _GuideRequest);
}

/// 锚定目标的引导气泡
class _GuideTip extends StatefulWidget {
  final GlobalKey targetKey;
  final String title;
  final String message;
  final String buttonText;
  final VoidCallback onDismiss;

  const _GuideTip({
    required this.targetKey,
    required this.title,
    required this.message,
    required this.buttonText,
    required this.onDismiss,
  });

  @override
  State<_GuideTip> createState() => _GuideTipState();
}

class _GuideTipState extends State<_GuideTip> with SingleTickerProviderStateMixin {
  static const double _bubbleWidth = 260;
  static const double _gap = 10;
  static const double _edgePadding = 12;
  static const double _bubbleMinLeft = 2;
  static const double _arrowInset = 20;
  static const double _highlightPadding = 4;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderObject = widget.targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return const SizedBox.shrink();
    }

    final Rect target = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final Rect highlight = target.inflate(_highlightPadding);
    final Size screen = MediaQuery.sizeOf(context);
    final double maxLeft = math.max(_bubbleMinLeft, screen.width - _bubbleWidth - _edgePadding);
    final double left = (target.center.dx - _arrowInset + 1).clamp(_bubbleMinLeft, maxLeft);
    final double arrowLeft = (target.center.dx - left + 1)
        .clamp(_arrowInset, _bubbleWidth - _arrowInset);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _GuideScrimPainter(
                hole: highlight,
                color: colorScheme.scrim.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        Positioned(
          left: highlight.left,
          top: highlight.top,
          width: highlight.width,
          height: highlight.height,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Positioned(
          left: left,
          top: target.bottom + _gap,
          width: _bubbleWidth,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
              child: _buildBubble(context, colorScheme, arrowLeft),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(BuildContext context, ColorScheme colorScheme, double arrowLeft) {
    final Color background = colorScheme.surfaceContainerHigh;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: Container(
            width: _bubbleWidth,
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colorScheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: widget.onDismiss, child: Text(widget.buttonText)),
                ),
              ],
            ),
          ),
        ),
        // 箭头盖在卡片阴影之上，避免被阴影压暗形成色差
        Positioned(
          left: arrowLeft - 7,
          top: -6,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 12, height: 12, color: background),
          ),
        ),
      ],
    );
  }
}

/// 非重点区域遮罩，目标区域留出透明洞
class _GuideScrimPainter extends CustomPainter {
  final Rect hole;
  final Color color;

  const _GuideScrimPainter({required this.hole, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(10)));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GuideScrimPainter oldDelegate) {
    return oldDelegate.hole != hole || oldDelegate.color != color;
  }
}
