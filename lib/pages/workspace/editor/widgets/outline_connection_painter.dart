import 'package:flutter/material.dart';

/// 大纲连接线绘制常量
///
/// 集中管理连接线、圆点等视觉元素的尺寸与位置参数，
/// 避免魔法数字散落在各处
class OutlineConnectionMetrics {
  OutlineConnectionMetrics._();

  /// 连接线宽度
  static const double lineWidth = 1.5;

  /// 圆点半径
  static const double dotRadius = 3.0;

  /// 圆点中心相对于第一行文字中线的垂直偏移
  static const double dotVerticalOffset = 5.0;

  /// 折叠态圆点背景半径
  ///
  /// 比圆点半径大，在圆点底部衬出一圈背景，用于提示该节点存在被折叠的子节点
  static const double collapsedDotBackgroundRadius = 8.0;
}

/// 大纲节点连接线绘制器
///
/// 在 CustomPaint 中绘制节点行前的连接线和圆点
///
/// 绘制规则：
/// - 深度为 0 的根节点仅绘制圆点，不绘制连接线
/// - 深度 > 0 的节点从列 1 到列 depth 绘制连接线
/// - 圆点始终绘制在列 (depth + 1) 的中心，y 坐标为单行文字高度的一半加固定偏移
/// - 所有列按 [columnOffset] 整体横向偏移，用于调整整块指示区的左边界
class OutlineConnectionPainter extends CustomPainter {
  /// 节点深度
  final int depth;

  /// 列偏移（单位：列）
  ///
  /// 桌面端为 0；移动端折叠入口移至行尾，行首不再为折叠箭头预留列，
  /// 传入 -1 使连接线与圆点整体左移一列，缩小节点与屏幕左侧的间距
  final int columnOffset;

  /// 每级缩进宽度
  final double indentWidth;

  /// 单行文字高度
  final double textLineHeight;

  /// 连接线颜色
  final Color lineColor;

  /// 圆点颜色
  final Color dotColor;

  /// 圆点中心相对第一行文字中线的垂直偏移
  final double dotVerticalOffset;

  /// 折叠态圆点背景色
  ///
  /// 非空时在圆点位置额外绘制一层背景圆，用于提示该节点存在被折叠的子节点；
  /// 展开态与无子节点的节点传 null，不绘制背景
  final Color? collapsedDotBackgroundColor;

  OutlineConnectionPainter({
    required this.depth,
    this.columnOffset = 0,
    required this.indentWidth,
    required this.textLineHeight,
    required this.lineColor,
    required this.dotColor,
    this.dotVerticalOffset = OutlineConnectionMetrics.dotVerticalOffset,
    this.collapsedDotBackgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 圆点中心 y 坐标（与第一行文字垂直居中对齐）
    final dotCenterY = textLineHeight / 2 + dotVerticalOffset;

    // 绘制连接线
    // 对于 depth > 0 的节点，从列 1 到列 depth 依次绘制
    for (int i = 1; i <= depth; i++) {
      // 连接线 x 坐标（列中心）
      final x = (i + columnOffset) * indentWidth + indentWidth / 2;
      final lineLeft = x - OutlineConnectionMetrics.lineWidth / 2;

      // 连接线贯穿整个节点行高度
      final linePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTRB(lineLeft, 0, lineLeft + OutlineConnectionMetrics.lineWidth, size.height),
        linePaint,
      );
    }

    // 绘制圆点
    // 圆点位于列 (depth + 1) 的中心
    final dotCenterX = (depth + 1 + columnOffset) * indentWidth + indentWidth / 2;
    final dotCenter = Offset(dotCenterX, dotCenterY);

    // 折叠态：先在圆点处绘制一圈背景，作为子节点被折叠的视觉标记
    if (collapsedDotBackgroundColor != null) {
      final backgroundPaint = Paint()
        ..color = collapsedDotBackgroundColor!
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        dotCenter,
        OutlineConnectionMetrics.collapsedDotBackgroundRadius,
        backgroundPaint,
      );
    }

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      dotCenter,
      OutlineConnectionMetrics.dotRadius,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant OutlineConnectionPainter oldDelegate) {
    // 比较所有影响绘制的关键字段
    return oldDelegate.depth != depth ||
        oldDelegate.columnOffset != columnOffset ||
        oldDelegate.indentWidth != indentWidth ||
        oldDelegate.textLineHeight != textLineHeight ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.dotVerticalOffset != dotVerticalOffset ||
        oldDelegate.collapsedDotBackgroundColor != collapsedDotBackgroundColor;
  }
}
