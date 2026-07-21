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
}

/// 大纲节点连接线绘制器
///
/// 在 CustomPaint 中绘制节点行前的连接线和圆点
///
/// 绘制规则：
/// - 深度为 0 的根节点仅绘制圆点，不绘制连接线
/// - 深度 > 0 的节点从列 1 到列 depth 绘制连接线
/// - 圆点始终绘制在列 (depth + 1) 的中心，y 坐标为单行文字高度的一半加固定偏移
class OutlineConnectionPainter extends CustomPainter {
  /// 节点深度
  final int depth;

  /// 每级缩进宽度
  final double indentWidth;

  /// 单行文字高度
  final double textLineHeight;

  /// 连接线颜色
  final Color lineColor;

  /// 圆点颜色
  final Color dotColor;

  OutlineConnectionPainter({
    required this.depth,
    required this.indentWidth,
    required this.textLineHeight,
    required this.lineColor,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 圆点中心 y 坐标（与第一行文字垂直居中对齐）
    final dotCenterY = textLineHeight / 2 + OutlineConnectionMetrics.dotVerticalOffset;

    // 绘制连接线
    // 对于 depth > 0 的节点，从列 1 到列 depth 依次绘制
    for (int i = 1; i <= depth; i++) {
      // 连接线 x 坐标（列中心）
      final x = i * indentWidth + indentWidth / 2;
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
    final dotCenterX = (depth + 1) * indentWidth + indentWidth / 2;
    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(dotCenterX, dotCenterY),
      OutlineConnectionMetrics.dotRadius,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant OutlineConnectionPainter oldDelegate) {
    // 比较所有影响绘制的关键字段
    return oldDelegate.depth != depth ||
        oldDelegate.indentWidth != indentWidth ||
        oldDelegate.textLineHeight != textLineHeight ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.dotColor != dotColor;
  }
}
