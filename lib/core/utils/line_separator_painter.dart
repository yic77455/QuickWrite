import 'package:flutter/widgets.dart';
import 'package:quick_write/core/services/settings_service.dart';

/// 行间线排版缓存
///
/// 复用 TextPainter 实例并缓存 layout 结果，避免每次 paint 都重新对全文排版。
/// 仅在文本内容、字体参数或内容宽度真正变化时才重新执行 layout，
/// 滚动、视口重绘等不改变文本的场景下直接复用缓存的行位置列表。
class LineSeparatorLayoutCache {
  /// 复用的 TextPainter 实例，避免每次 paint 都创建新对象
  TextPainter? _textPainter;

  // ===== 缓存键（用于 O(1) 快速判断是否需要重新排版）=====
  int? _cachedTextLength;
  int? _cachedTextHashCode;
  double? _cachedWidth;
  double? _cachedFontSize;
  double? _cachedLineHeight;
  double? _cachedLetterSpacing;
  String? _cachedFontFamily;
  bool? _cachedIsBold;
  bool? _cachedIsItalic;

  // ===== 缓存结果 =====
  /// 每一行底部的 Y 坐标列表
  List<double> _cachedLineBottoms = const [];

  /// 单行步进高度（fontSize * lineHeight），用于底部边距延伸区域计算
  double _cachedLineStride = 0.0;

  /// 获取所有行的底部 Y 坐标列表
  ///
  /// 首先比较缓存键，命中则直接返回缓存；未命中则复用 TextPainter 重新排版。
  /// 使用 length + hashCode 做 O(1) 快速比较，避免对长文本做 O(n) 字符串比较。
  List<double> getLineBottoms({
    required String text,
    required double contentWidth,
    required String fontFamily,
    required double fontSize,
    required double lineHeight,
    required double letterSpacing,
    required bool isBold,
    required bool isItalic,
  }) {
    final int textHashCode = text.hashCode;
    final int textLength = text.length;

    // 缓存命中：所有键一致，直接返回缓存结果
    if (_cachedTextHashCode == textHashCode &&
        _cachedTextLength == textLength &&
        _cachedWidth == contentWidth &&
        _cachedFontSize == fontSize &&
        _cachedLineHeight == lineHeight &&
        _cachedLetterSpacing == letterSpacing &&
        _cachedFontFamily == fontFamily &&
        _cachedIsBold == isBold &&
        _cachedIsItalic == isItalic) {
      return _cachedLineBottoms;
    }

    // 缓存未命中，重新排版
    _performLayout(
      text: text,
      contentWidth: contentWidth,
      fontFamily: fontFamily,
      fontSize: fontSize,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      isBold: isBold,
      isItalic: isItalic,
    );

    // 更新缓存键
    _cachedTextHashCode = textHashCode;
    _cachedTextLength = textLength;
    _cachedWidth = contentWidth;
    _cachedFontSize = fontSize;
    _cachedLineHeight = lineHeight;
    _cachedLetterSpacing = letterSpacing;
    _cachedFontFamily = fontFamily;
    _cachedIsBold = isBold;
    _cachedIsItalic = isItalic;

    return _cachedLineBottoms;
  }

  /// 获取缓存的行步进高度
  double get cachedLineStride => _cachedLineStride;

  /// 执行实际排版，复用 TextPainter 实例
  void _performLayout({
    required String text,
    required double contentWidth,
    required String fontFamily,
    required double fontSize,
    required double lineHeight,
    required double letterSpacing,
    required bool isBold,
    required bool isItalic,
  }) {
    // 构建与编辑器一致的文本样式
    final textStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      height: lineHeight,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
      color: const Color(0xFF000000),
    );

    // 复用 TextPainter 实例，避免每次都创建新对象
    _textPainter ??= TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    _textPainter!.text = TextSpan(text: text, style: textStyle);
    // 按可用宽度布局（模拟 TextField 的自动换行行为）
    _textPainter!.layout(maxWidth: contentWidth);

    final List<double> bottoms = [];
    // 遍历 TextPainter 的每一行，通过累计高度计算每行的底部 Y 坐标
    double currentY = 0.0;
    for (final line in _textPainter!.computeLineMetrics()) {
      currentY += line.height;
      bottoms.add(currentY);
    }

    _cachedLineBottoms = bottoms;
    _cachedLineStride = fontSize * lineHeight;
  }

  /// 释放资源
  void dispose() {
    _textPainter?.dispose();
    _textPainter = null;
    _cachedLineBottoms = const [];
  }
}

/// 行间线前景绘制器
///
/// 继承自 Flutter 的 CustomPainter，作为 CustomPaint 的 foregroundPainter 使用，
/// 在编辑器文字层之上绘制行间分隔线。
///
/// 性能优化点：
/// - 通过 [cache] 复用 TextPainter 实例并缓存排版结果，
///   避免每次 paint 都重新对全文排版
/// - 通过 [scrollController] 作为 repaint Listenable，滚动时自动触发重绘
/// - 仅绘制视口可见区域内的行，长文本下避免绘制数万行不可见线
class LineSeparatorPainter extends CustomPainter {
  /// 文本内容
  final String text;

  /// 行间线颜色
  final Color color;

  /// 行间线样式：'solid'（实线）或 'dashed'（虚线）
  final String style;

  /// 行间线不透明度（0.0 ~ 1.0）
  final double opacity;

  /// 内容区域可用宽度（用于 TextPainter 布局计算自动换行）
  final double contentWidth;

  /// 字体大小
  final double fontSize;

  /// 行高倍数
  final double lineHeight;

  /// 字间距
  final double letterSpacing;

  /// 字体名称
  final String fontFamily;

  /// 是否加粗
  final bool isBold;

  /// 是否斜体
  final bool isItalic;

  /// 底部边距比例（0.0 ~ 1.0），用于将行间线延伸至底部边距区域
  final double bottomMarginRatio;

  /// 排版缓存，复用 TextPainter 实例与排版结果
  final LineSeparatorLayoutCache cache;

  /// 滚动控制器，作为 repaint Listenable 让滚动时自动触发重绘，并提供视口信息
  final ScrollController? scrollController;

  /// 虚线模式下每段划线的长度（像素）
  static const double _dashLength = 6.0;

  /// 虚线模式下每段间隙的长度（像素）
  static const double _dashGap = 4.0;

  /// 行间线粗细（像素）
  static const double _lineThickness = 1.0;

  LineSeparatorPainter({
    required this.text,
    required this.color,
    required this.style,
    required this.opacity,
    required this.contentWidth,
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    required this.fontFamily,
    required this.isBold,
    required this.isItalic,
    required this.cache,
    this.scrollController,
    this.bottomMarginRatio = 0.0,
  }) : super(repaint: scrollController);

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty && contentWidth <= 0) return;

    // 构建画笔，应用不透明度
    final Paint paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineThickness;

    // 从缓存获取所有行的底部 Y 坐标（命中缓存时不会重新排版）
    final List<double> lineBottoms = cache.getLineBottoms(
      text: text,
      contentWidth: contentWidth,
      fontFamily: fontFamily,
      fontSize: fontSize,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      isBold: isBold,
      isItalic: isItalic,
    );

    if (lineBottoms.isEmpty) return;

    final double lineStride = cache.cachedLineStride;

    // 计算可见区域的纵向范围
    // 多预留一行作为缓冲，避免边缘抖动时出现缝隙
    final bool hasViewport = scrollController?.hasClients == true;
    final double viewportTop =
        hasViewport ? scrollController!.offset - lineStride : double.negativeInfinity;
    final double viewportBottom = hasViewport
        ? scrollController!.offset + scrollController!.position.viewportDimension + lineStride
        : double.infinity;

    // 在每行底部绘制水平线（仅可见区域内的行）
    for (final lineY in lineBottoms) {
      if (lineY < viewportTop || lineY > viewportBottom) continue;
      _drawHorizontalLine(canvas, paint, size.width, lineY);
    }

    // 根据底部边距比例计算需要延伸到的总高度
    // canvasHeight 是 TextField 内容高度，乘以 (1 + bottomMarginRatio) 得到包含底部边距的总高度
    final double totalHeight = bottomMarginRatio > 0
        ? size.height * (1.0 + bottomMarginRatio)
        : size.height;

    // 如果最后一行底部未超出目标高度，继续按行高间隔向下延伸绘制
    // 这样可以覆盖底部边距区域和末尾空白区域
    if (totalHeight < double.infinity && totalHeight > lineBottoms.last) {
      double nextY = lineBottoms.last + lineStride;
      while (nextY < totalHeight) {
        if (nextY >= viewportTop && nextY <= viewportBottom) {
          _drawHorizontalLine(canvas, paint, size.width, nextY);
        }
        nextY += lineStride;
      }
    }
  }

  @override
  bool shouldRepaint(covariant LineSeparatorPainter oldDelegate) {
    // scrollController 由父类 repaint Listenable 处理，无需在此比较
    // 缓存命中由 cache 内部判断，文本变化通过 text 字段触发比较
    return oldDelegate.text != text ||
        oldDelegate.color != color ||
        oldDelegate.style != style ||
        oldDelegate.opacity != opacity ||
        oldDelegate.contentWidth != contentWidth ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.letterSpacing != letterSpacing ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.isBold != isBold ||
        oldDelegate.isItalic != isItalic ||
        oldDelegate.bottomMarginRatio != bottomMarginRatio;
  }

  /// 根据当前样式绘制一条水平线
  void _drawHorizontalLine(Canvas canvas, Paint paint, double width, double y) {
    if (style == 'dashed') {
      _drawDashedLine(canvas, paint, 0, y, width, y);
    } else {
      canvas.drawLine(Offset(0, y), Offset(width, y), paint);
    }
  }

  /// 绘制虚线段
  void _drawDashedLine(Canvas canvas, Paint paint, double x1, double y1, double x2, double y2) {
    final double totalLength = (x2 - x1).abs();
    if (totalLength <= 0) return;

    double currentX = x1;
    final int direction = x2 > x1 ? 1 : -1;

    while ((direction > 0 && currentX < x2) || (direction < 0 && currentX > x2)) {
      double segmentEndX = currentX + direction * _dashLength;
      if (direction > 0 && segmentEndX > x2) segmentEndX = x2;
      if (direction < 0 && segmentEndX < x2) segmentEndX = x2;

      canvas.drawLine(Offset(currentX, y1), Offset(segmentEndX, y2), paint);
      currentX = segmentEndX + direction * _dashGap;
    }
  }
}

/// 创建行间线绘制器的工厂方法
///
/// 从 SettingsService 读取当前设置，构建 LineSeparatorPainter 实例
LineSeparatorPainter createLineSeparatorPainter({
  required String text,
  required Color color,
  required double contentWidth,
  required LineSeparatorLayoutCache cache,
  ScrollController? scrollController,
  double bottomMarginRatio = 0.0,
}) {
  final settings = SettingsService.instance;
  return LineSeparatorPainter(
    text: text,
    color: color,
    style: settings.lineSeparatorStyle,
    opacity: settings.lineSeparatorOpacity,
    contentWidth: contentWidth,
    fontSize: settings.fontSize,
    lineHeight: settings.lineHeight,
    letterSpacing: settings.letterSpacing,
    fontFamily: settings.fontFamily,
    isBold: settings.isBold,
    isItalic: settings.isItalic,
    bottomMarginRatio: bottomMarginRatio,
    cache: cache,
    scrollController: scrollController,
  );
}
