import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'stats_line_chart.dart';

/// 统计图表卡片
///
/// 带标题的折线图容器，用于展示码字字数或码字时长趋势。
class StatsChartCard extends StatelessWidget {
  /// 卡片标题
  final String title;

  /// 标题图标
  final IconData icon;

  /// 折线图数据点
  final List<ChartPoint> points;

  /// 折线颜色
  final Color lineColor;

  /// 数值标签（如"字数"、"时长"），显示在 tooltip 数值前
  final String valueLabel;

  /// Y 轴数值格式化函数
  final String Function(int value) valueFormatter;

  /// tooltip 数值格式化函数，为 null 时与 [valueFormatter] 一致
  final String Function(int value)? tooltipValueFormatter;

  const StatsChartCard({
    required this.title,
    required this.icon,
    required this.points,
    required this.lineColor,
    required this.valueLabel,
    required this.valueFormatter,
    this.tooltipValueFormatter,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: lineColor),
                const SizedBox(width: 6),
                Text(title, style: context.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            StatsLineChart(
              points: points,
              lineColor: lineColor,
              unit: '',
              valueLabel: valueLabel,
              valueFormatter: valueFormatter,
              tooltipValueFormatter: tooltipValueFormatter,
            ),
          ],
        ),
      ),
    );
  }
}
