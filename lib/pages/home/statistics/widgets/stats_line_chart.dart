import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 折线图数据点
class ChartPoint {
  /// X 轴标签
  final String label;

  /// 数值
  final int value;

  const ChartPoint({required this.label, required this.value});
}

/// 统计折线图
///
/// 使用 [CustomPaint] 绘制带网格、坐标轴、填充区域的折线图。
/// 用于展示码字字数与码字时长的趋势变化。
class StatsLineChart extends StatefulWidget {
  /// 数据点列表
  final List<ChartPoint> points;

  /// 折线颜色
  final Color lineColor;

  /// 数值单位（用于 Y 轴提示）
  final String unit;

  /// 数值标签（如"字数"、"时长"），显示在 tooltip 数值前
  final String valueLabel;

  /// Y 轴数值格式化函数（将 int 转为展示字符串）
  final String Function(int value) valueFormatter;

  /// tooltip 数值格式化函数，为 null 时与 [valueFormatter] 一致
  final String Function(int value)? tooltipValueFormatter;

  const StatsLineChart({
    required this.points,
    required this.lineColor,
    required this.unit,
    required this.valueLabel,
    required this.valueFormatter,
    this.tooltipValueFormatter,
    super.key,
  });

  @override
  State<StatsLineChart> createState() => _StatsLineChartState();
}

class _StatsLineChartState extends State<StatsLineChart> {
  /// 当前悬停的数据点索引（-1 表示未悬停）
  int _hoveredIndex = -1;

  /// 图表区域 Key，用于获取图表全局坐标以进行边缘检测
  final GlobalKey _chartKey = GlobalKey();

  // 绘图区域内边距（与 painter 保持一致）
  static const double _leftPadding = 48;
  static const double _rightPadding = 16;

  @override
  void dispose() {
    FollowTooltip.hide();
    super.dispose();
  }

  /// 获取图表的全局边界区域
  ///
  /// 用于 tooltip 边缘检测，确保 tooltip 不会超出图表区域。
  Rect _getChartRegion(double chartWidth, double chartHeight) {
    final renderBox =
        _chartKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    return origin & Size(chartWidth, chartHeight);
  }

  /// 鼠标悬停处理
  void _onHover(PointerHoverEvent event, double chartWidth, double chartHeight) {
    final index = _findNearestPoint(event.localPosition.dx, chartWidth);
    final region = _getChartRegion(chartWidth, chartHeight);

    if (index == _hoveredIndex) {
      // 索引未变：仅更新 tooltip 位置，不触发重绘
      if (index >= 0) {
        FollowTooltip.updatePosition(event.position, region);
      }
      return;
    }

    // 索引变化：更新索引、tooltip、触发重绘虚线
    _hoveredIndex = index;
    if (index >= 0) {
      _showOrUpdateTooltip(event, region);
    } else {
      FollowTooltip.hide();
    }
    setState(() {});
  }

  /// 鼠标离开图表处理
  void _onExit() {
    FollowTooltip.hide();
    if (_hoveredIndex != -1) {
      _hoveredIndex = -1;
      setState(() {});
    }
  }

  /// 显示或更新 tooltip
  ///
  /// 首次调用时创建 [OverlayEntry] 并传入初始内容，
  /// 后续直接通过 [FollowTooltip.update] 更新位置和内容。
  void _showOrUpdateTooltip(PointerHoverEvent event, Rect region) {
    final point = widget.points[_hoveredIndex];
    final formatter = widget.tooltipValueFormatter ?? widget.valueFormatter;
    final content = _ChartTooltipContent(
      label: point.label,
      valueLabel: widget.valueLabel,
      value: formatter(point.value),
    );

    if (!FollowTooltip.isShowing) {
      FollowTooltip.show(
        context: context,
        cursorPosition: event.position,
        region: region,
        child: content,
      );
    } else {
      FollowTooltip.update(event.position, region, content);
    }
  }

  /// 根据鼠标 x 坐标找到最接近的数据点索引
  int _findNearestPoint(double mouseX, double chartWidth) {
    if (widget.points.isEmpty) return -1;
    final plotLeft = _leftPadding;
    final plotRight = chartWidth - _rightPadding;
    final plotWidth = plotRight - plotLeft;
    if (plotWidth <= 0) return -1;

    // 鼠标在绘图区域外时不悬停
    if (mouseX < plotLeft - 10 || mouseX > plotRight + 10) return -1;

    if (widget.points.length == 1) return 0;

    final stepX = plotWidth / (widget.points.length - 1);
    final index = ((mouseX - plotLeft) / stepX).round();
    return index.clamp(0, widget.points.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 220.0;
        return MouseRegion(
          key: _chartKey,
          onHover: (event) => _onHover(event, width, height),
          onExit: (_) => _onExit(),
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _LineChartPainter(
                points: widget.points,
                lineColor: widget.lineColor,
                valueFormatter: widget.valueFormatter,
                textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                gridColor: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                hoveredIndex: _hoveredIndex,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 折线图 tooltip 内容
///
/// 负责构建 tooltip 的视觉呈现（背景、文字、布局），
/// 位置管理由 [FollowTooltip] 负责。
class _ChartTooltipContent extends StatelessWidget {
  /// 第一行日期标签
  final String label;

  /// 第二行数值前的标签（"字数" / "时长"）
  final String valueLabel;

  /// 第二行数值文本
  final String value;

  const _ChartTooltipContent({
    required this.label,
    required this.valueLabel,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltipTheme = theme.tooltipTheme;
    final decoration = tooltipTheme.decoration ??
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
    final baseStyle = tooltipTheme.textStyle ?? theme.textTheme.bodySmall ?? const TextStyle();
    final baseColor = baseStyle.color ?? theme.colorScheme.onSurface;
    final dimStyle = baseStyle.copyWith(
      fontSize: 11,
      color: baseColor.withValues(alpha: 0.6),
    );
    final valueLabelStyle = baseStyle.copyWith(
      fontSize: 12,
      color: baseColor.withValues(alpha: 0.6),
    );
    final valueStyle = baseStyle.copyWith(
      fontSize: 12,
      color: baseColor,
    );

    return Container(
      constraints: const BoxConstraints(minWidth: 90),
      decoration: decoration,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: dimStyle),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(valueLabel, style: valueLabelStyle),
                  Text(value, style: valueStyle),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 折线图绘制器
class _LineChartPainter extends CustomPainter {
  final List<ChartPoint> points;
  final Color lineColor;
  final String Function(int value) valueFormatter;
  final Color textColor;
  final Color gridColor;
  final int hoveredIndex;

  _LineChartPainter({
    required this.points,
    required this.lineColor,
    required this.valueFormatter,
    required this.textColor,
    required this.gridColor,
    required this.hoveredIndex,
  });

  // 绘图区域内边距：左留 Y 轴标签，底留 X 轴标签，上右留少量间距
  static const double _leftPadding = 48;
  static const double _rightPadding = 16;
  static const double _topPadding = 16;
  static const double _bottomPadding = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _leftPadding;
    final plotRight = size.width - _rightPadding;
    final plotTop = _topPadding;
    final plotBottom = size.height - _bottomPadding;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    // 计算数据范围
    final maxValue = points.isEmpty
        ? 0
        : points.fold(0, (max, p) => p.value > max ? p.value : max);
    // Y 轴上限取整到 4 等分时为整数，最小为 1 避免除零
    final int yMax = _niceMax(maxValue);
    final yStep = yMax / 4;

    // 绘制水平网格线与 Y 轴标签
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: textColor, fontSize: 10);
    for (int i = 0; i <= 4; i++) {
      final y = plotBottom - (plotHeight * i / 4);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      final value = (yStep * i).round();
      final tp = TextPainter(
        text: TextSpan(text: valueFormatter(value), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotLeft - tp.width - 6, y - tp.height / 2));
    }

    if (points.isEmpty || plotWidth <= 0) return;

    // 计算每个数据点的坐标
    final stepX = points.length == 1 ? 0.0 : plotWidth / (points.length - 1);
    final pointOffsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = plotLeft + stepX * i;
      final ratio = yMax == 0 ? 0.0 : points[i].value / yMax;
      final y = plotBottom - plotHeight * ratio;
      pointOffsets.add(Offset(x, y));
    }

    // 绘制折线下方的渐变填充
    if (pointOffsets.length >= 2) {
      final fillPath = Path()
        ..moveTo(pointOffsets.first.dx, plotBottom)
        ..addPolygon(pointOffsets, false)
        ..lineTo(pointOffsets.last.dx, plotBottom)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.25),
            lineColor.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(plotLeft, plotTop, plotWidth, plotHeight));
      canvas.drawPath(fillPath, fillPaint);
    }

    // 绘制折线
    if (pointOffsets.length >= 2) {
      final linePath = Path()..addPolygon(pointOffsets, false);
      canvas.drawPath(
        linePath,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 绘制数据点
    final dotPaint = Paint()..color = lineColor;
    final dotRadius = points.length > 14 ? 2.0 : 3.0;
    for (final offset in pointOffsets) {
      canvas.drawCircle(offset, dotRadius, dotPaint);
    }

    // 绘制 X 轴标签（数据点过多时隔点显示）
    final labelInterval = _xLabelInterval(points.length);
    for (int i = 0; i < points.length; i++) {
      if (i % labelInterval != 0 && i != points.length - 1) continue;
      final tp = TextPainter(
        text: TextSpan(text: points[i].label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = pointOffsets[i].dx - tp.width / 2;
      tp.paint(canvas, Offset(x, plotBottom + 8));
    }

    // 绘制悬停效果：竖直虚线 + 高亮点
    if (hoveredIndex >= 0 && hoveredIndex < pointOffsets.length) {
      _drawHoverGuide(canvas, hoveredIndex, pointOffsets, plotTop, plotBottom);
    }
  }

  /// 绘制悬停指示：竖直虚线 + 高亮点
  void _drawHoverGuide(
    Canvas canvas,
    int index,
    List<Offset> pointOffsets,
    double plotTop,
    double plotBottom,
  ) {
    final hoverPoint = pointOffsets[index];

    // 绘制竖直虚线
    final dashPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dashPath = Path();
    double y = plotTop;
    const dashHeight = 4.0;
    const gapHeight = 3.0;
    while (y < plotBottom) {
      dashPath.moveTo(hoverPoint.dx, y);
      dashPath.lineTo(hoverPoint.dx, y + dashHeight);
      y += dashHeight + gapHeight;
    }
    canvas.drawPath(dashPath, dashPaint);

    // 绘制悬停点高亮（外圈 + 白色内圈）
    canvas.drawCircle(hoverPoint, 5, Paint()..color = lineColor);
    canvas.drawCircle(hoverPoint, 3, Paint()..color = Colors.white);
  }

  /// 计算 Y 轴友好的最大值，使 4 等分后为整数
  int _niceMax(int maxValue) {
    if (maxValue <= 0) return 4;
    // 向上取整到最近的"友好"刻度
    final magnitude = pow(10, (maxValue.toString().length - 1)).toInt();
    final normalized = maxValue / magnitude;
    double niceNormalized;
    if (normalized <= 1) {
      niceNormalized = 1;
    } else if (normalized <= 2) {
      niceNormalized = 2;
    } else if (normalized <= 5) {
      niceNormalized = 5;
    } else {
      niceNormalized = 10;
    }
    final nice = (niceNormalized * magnitude).toInt();
    // 确保大于实际最大值
    return nice > maxValue ? nice : maxValue + magnitude;
  }

  /// 根据数据点数量决定 X 轴标签显示间隔
  int _xLabelInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 15) return 2;
    if (count <= 31) return 5;
    return 7;
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}
