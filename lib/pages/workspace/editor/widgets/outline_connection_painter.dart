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

  /// 圆点外轮廓的基础半径
  ///
  /// 比圆点半径大，折叠态常显一圈轮廓，用于提示该节点存在被折叠的子节点
  static const double collapsedDotBackgroundRadius = 8.0;

  /// 圆点外轮廓在鼠标悬停时放大到的半径
  ///
  /// 比基础半径更大，悬停时轮廓从基础半径（或圆点内部）向外扩大，提示该圆点可拖拽
  static const double hoverDotBackgroundRadius = 10.0;
}

/// 同级连接线的高亮列
///
/// 当前编辑节点的圆点位于列 (depth + 1)，该列上的连接线由其后代节点行绘制，
/// 从圆点下方一直延伸到下一个同级节点所在行，即为需要点亮的连接线
class OutlineSiblingLineHighlight {
  /// 高亮竖线所在列（列号与节点深度使用同一坐标系）
  final int column;

  /// 高亮颜色
  final Color color;

  const OutlineSiblingLineHighlight({required this.column, required this.color});
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
/// - 当前编辑节点的圆点使用高亮色绘制，其到下一个同级节点之间的连接线叠加高亮
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

  /// 圆点外轮廓颜色
  ///
  /// 非空时在圆点外绘制一圈轮廓：折叠态常显，悬停时由外部动画放大，
  /// 不显示轮廓时传 null
  final Color? dotOutlineColor;

  /// 圆点外轮廓半径
  ///
  /// 折叠态取基础半径，鼠标悬停时由外部动画放大到悬停半径；
  /// 展开态且未悬停时取 0，轮廓收进圆点内部不可见
  final double dotOutlineRadius;

  /// 当前编辑节点的圆点高亮色
  ///
  /// 非空时圆点使用该颜色绘制，用于标识当前正在编辑的节点；
  /// 其他节点传 null，沿用普通圆点颜色
  final Color? activeDotColor;

  /// 同级连接线高亮配置
  ///
  /// 非空时高亮当前编辑节点到下一个同级节点之间的连接线，
  /// 未处于该连接线上的行传 null
  final OutlineSiblingLineHighlight? siblingLineHighlight;

  OutlineConnectionPainter({
    required this.depth,
    this.columnOffset = 0,
    required this.indentWidth,
    required this.textLineHeight,
    required this.lineColor,
    required this.dotColor,
    this.dotVerticalOffset = OutlineConnectionMetrics.dotVerticalOffset,
    required this.dotOutlineColor,
    required this.dotOutlineRadius,
    this.activeDotColor,
    this.siblingLineHighlight,
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

      // 当前编辑节点到下一个同级节点的连接线整行高亮
      final highlight = siblingLineHighlight;
      if (highlight != null && highlight.column == i) {
        canvas.drawRect(
          Rect.fromLTRB(lineLeft, 0, lineLeft + OutlineConnectionMetrics.lineWidth, size.height),
          Paint()
            ..color = highlight.color
            ..style = PaintingStyle.fill,
        );
      }
    }

    // 绘制圆点
    // 圆点位于列 (depth + 1) 的中心
    final dotCenterX = (depth + 1 + columnOffset) * indentWidth + indentWidth / 2;
    final dotCenter = Offset(dotCenterX, dotCenterY);

    // 圆点外轮廓：折叠态常显，悬停时由外部动画放大；半径收进圆点内部时不绘制
    if (dotOutlineColor != null && dotOutlineRadius > OutlineConnectionMetrics.dotRadius) {
      canvas.drawCircle(
        dotCenter,
        dotOutlineRadius,
        Paint()
          ..color = dotOutlineColor!
          ..style = PaintingStyle.fill,
      );
    }

    final dotPaint = Paint()
      ..color = activeDotColor ?? dotColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dotCenter, OutlineConnectionMetrics.dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant OutlineConnectionPainter oldDelegate) {
    final oldHighlight = oldDelegate.siblingLineHighlight;
    final highlight = siblingLineHighlight;
    // 比较所有影响绘制的关键字段
    return oldDelegate.depth != depth ||
        oldDelegate.columnOffset != columnOffset ||
        oldDelegate.indentWidth != indentWidth ||
        oldDelegate.textLineHeight != textLineHeight ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.dotVerticalOffset != dotVerticalOffset ||
        oldDelegate.dotOutlineColor != dotOutlineColor ||
        oldDelegate.dotOutlineRadius != dotOutlineRadius ||
        oldDelegate.activeDotColor != activeDotColor ||
        oldHighlight?.column != highlight?.column ||
        oldHighlight?.color != highlight?.color;
  }
}
