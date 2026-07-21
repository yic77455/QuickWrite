import 'package:flutter/material.dart';
import 'package:quick_write/core/services/writing_stats_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';

/// 数据总览卡片
///
/// 展示累计创作数据：创作天数、累计创作书籍数、累计字数、单日最高码字、单日最高时长。
class OverviewCard extends StatelessWidget {
  /// 总览数据
  final OverviewStats stats;

  const OverviewCard({required this.stats, super.key});

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
                Icon(Icons.data_usage_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('数据总览', style: context.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildItem(context, '创作天数', '${stats.writingDays} 天', Icons.calendar_today_outlined)),
                Expanded(child: _buildItem(context, '累计创作', '${stats.totalBooks} 本', Icons.menu_book_rounded)),
                Expanded(child: _buildItem(context, '累计字数', WordCountUtils.formatWordCount(stats.totalWordsAdded), Icons.text_fields)),
                Expanded(child: _buildItem(context, '单日最高码字', WordCountUtils.formatWordCount(stats.maxDayWords), Icons.trending_up_rounded)),
                Expanded(child: _buildItem(context, '单日最高时长', _formatDuration(stats.maxDayDuration), Icons.timer_rounded)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建单个统计项
  Widget _buildItem(BuildContext context, String label, String value, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 22, color: colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          value,
          style: context.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: context.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
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
