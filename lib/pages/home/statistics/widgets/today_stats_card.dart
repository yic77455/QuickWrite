import 'package:flutter/material.dart';
import 'package:quick_write/core/services/writing_stats_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';

/// 今日数据卡片
///
/// 展示选中日期的码字字数、码字时长、码字速度、连续码字天数。
/// 默认展示今日数据，点击码字日历上的日期可切换查看其他日期。
class TodayStatsCard extends StatelessWidget {
  /// 选中日期的统计
  final DailyStat stat;

  /// 连续码字天数
  final int consecutiveDays;

  const TodayStatsCard({
    required this.stat,
    required this.consecutiveDays,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 码字速度 = 键盘输入字数 / 时长（小时），排除粘贴字数，无时长时为 0
    final hours = stat.durationSeconds / 3600.0;
    final speed = hours > 0 ? (stat.typedWords / hours).round() : 0;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题：展示选中日期
            Row(
              children: [
                Icon(Icons.insights_rounded, size: 22, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  _formatDateLabel(stat.date),
                  style: context.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 码字字数（核心指标，放大显示）
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _buildPrimaryMetric(
                context,
                label: '码字字数',
                value: WordCountUtils.formatWordCount(stat.wordsAdded, wanThreshold: 100000),
                icon: Icons.text_fields,
                color: colorScheme.primary,
              ),
            ),
            const Divider(height: 32),
            const SizedBox(height: 8),
            // 次要指标网格
            Row(
              children: [
                Expanded(
                  child: _buildMetric(
                    context,
                    label: '码字时长',
                    value: _formatDuration(stat.durationSeconds),
                    icon: Icons.timer_outlined,
                  ),
                ),
                Expanded(
                  child: _buildMetric(
                    context,
                    label: '码字速度',
                    value: '$speed 字/时',
                    icon: Icons.speed_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMetric(
                    context,
                    label: '连续码字',
                    value: '$consecutiveDays 天',
                    icon: Icons.local_fire_department_outlined,
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建主要指标（大字号突出显示）
  Widget _buildPrimaryMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(
                value,
                style: context.headlineLarge?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建次要指标（紧凑布局）
  Widget _buildMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              Text(value, style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  /// 格式化日期标签
  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date == today) return '今日数据';
    return '${date.month}月${date.day}日数据';
  }

  /// 格式化时长（秒 -> "X时Y分" 或 "Y分"）
  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0 分';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours 时 $minutes 分';
    }
    return '$minutes 分';
  }
}
