import 'package:flutter/material.dart';
import 'package:quick_write/core/services/writing_stats_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
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
    final bool isMobile = PlatformCapabilities.isMobile;

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
            SizedBox(height: isMobile ? 12 : 16),
            // 数据项：移动端每行 3 项分行排布，桌面端单行并排
            if (isMobile)
              ..._buildMobileGrid(context)
            else
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

  /// 构建移动端数据项网格
  ///
  /// 每行排列 3 项，末行不足时用空白占位，保证各列宽度与其余各行一致。
  List<Widget> _buildMobileGrid(BuildContext context) {
    final items = <Widget>[
      _buildItem(context, '创作天数', '${stats.writingDays} 天', Icons.calendar_today_outlined),
      _buildItem(context, '累计创作', '${stats.totalBooks} 本', Icons.menu_book_rounded),
      _buildItem(context, '累计字数', WordCountUtils.formatWordCount(stats.totalWordsAdded), Icons.text_fields),
      _buildItem(context, '单日最高码字', WordCountUtils.formatWordCount(stats.maxDayWords), Icons.trending_up_rounded),
      _buildItem(context, '单日最高时长', _formatDuration(stats.maxDayDuration), Icons.timer_rounded),
    ];

    const int perRow = 3;
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += perRow) {
      final rowItems = items.sublist(i, (i + perRow).clamp(0, items.length));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in rowItems) Expanded(child: item),
            // 空白占位：补齐末行缺少的列，使该行列宽与前几行保持一致
            for (int k = rowItems.length; k < perRow; k++) const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + perRow < items.length) {
        rows.add(const SizedBox(height: 20));
      }
    }
    return rows;
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
          // 移动端列宽较窄，数值字号适当收小以保证完整显示
          style: (PlatformCapabilities.isMobile ? context.titleMedium : context.titleLarge)
              ?.copyWith(fontWeight: FontWeight.bold),
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
