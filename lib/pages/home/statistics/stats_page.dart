import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/providers/writing_stats_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'widgets/widgets.dart';

/// 码字统计页面
///
/// 展示码字日历、今日数据、创作字数/时长折线图、数据总览。
/// 顶部提供书籍筛选（全部或指定书籍），所有区块联动该筛选。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  void initState() {
    super.initState();
    // 页面初始化后加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WritingStatsProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final statsProvider = context.watch<WritingStatsProvider>();
    final bookshelf = context.watch<BookshelfProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 顶部标题栏：标题 + 粘贴字数开关 + 书籍筛选 + 刷新
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('码字统计', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(width: 8),
            // 粘贴字数统计开关（仅影响统计界面的显示）
            Transform.translate(
              offset: const Offset(0, 3),
              child: CursorTooltipTarget(
                showTooltip: true,
                tooltipContent: Text('是否包含粘贴字数', style: context.bodySmall),
                child: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: statsProvider.includePasteWords ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  style: IconButton.styleFrom(
                    backgroundColor: statsProvider.includePasteWords
                        ? colorScheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                  ),
                  onPressed: () => statsProvider.toggleIncludePasteWords(),
                ),
              ),
            ),
            const Spacer(),
            // 书籍筛选下拉框
            SizedBox(
              width: 200,
              child: CustomDropdown(
                width: 200,
                value: statsProvider.selectedBookUuid,
                items: _buildBookItems(bookshelf),
                onChanged: (value) => statsProvider.setSelectedBook(value),
              ),
            ),
            const SizedBox(width: 8),
            // 刷新按钮
            CursorTooltipTarget(
              showTooltip: true,
              tooltipContent: Text('刷新', style: context.bodySmall),
              child: IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => statsProvider.refresh()),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 统计区块（限制最大宽度并居中，避免窗口过宽时元素被拉伸失衡）
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 第一行：今日数据（左）+ 码字日历（右）
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 今日数据卡片
                      Expanded(
                        flex: 2,
                        child: TodayStatsCard(
                          stat: statsProvider.selectedDateStat,
                          consecutiveDays: statsProvider.consecutiveDays,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 码字日历
                      Expanded(
                        flex: 3,
                        child: WritingCalendar(
                          month: statsProvider.calendarMonth,
                          calendarStats: statsProvider.calendarStats,
                          selectedDate: statsProvider.selectedDate,
                          onDateSelected: (date) => statsProvider.setSelectedDate(date),
                          onPreviousMonth: () => statsProvider.changeCalendarMonth(-1),
                          onNextMonth: () => statsProvider.changeCalendarMonth(1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 本周/本月切换
                Row(
                  children: [
                    Text('创作趋势', style: context.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: SegmentedControl(
                        labels: const ['本周', '本月'],
                        selectedIndex: statsProvider.chartRangeMode == ChartRangeMode.week ? 0 : 1,
                        onChanged: (index) =>
                            statsProvider.setChartRangeMode(index == 0 ? ChartRangeMode.week : ChartRangeMode.month),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 第二行：字数统计图表 + 时长统计图表
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: StatsChartCard(
                        title: '创作字数统计',
                        icon: Icons.show_chart_rounded,
                        points: _toWordCountPoints(statsProvider.wordCountChartStats),
                        lineColor: colorScheme.primary,
                        valueLabel: '字数',
                        valueFormatter: _formatWordCountAxis,
                        tooltipValueFormatter: (v) => WordCountUtils.formatWordCountShort(v, wanThreshold: 100000),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StatsChartCard(
                        title: '创作时长统计',
                        icon: Icons.timeline_rounded,
                        points: _toDurationPoints(statsProvider.durationChartStats),
                        lineColor: colorScheme.tertiary,
                        valueLabel: '时长',
                        valueFormatter: _formatDurationAxis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 数据总览
                OverviewCard(stats: statsProvider.overviewStats),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建书籍筛选选项列表（含"全部书籍"）
  List<DropdownItem> _buildBookItems(BookshelfProvider bookshelf) {
    final items = <DropdownItem>[const DropdownItem(displayText: '全部书籍', value: '')];
    for (final book in bookshelf.books) {
      items.add(DropdownItem(displayText: book.title, value: book.uuid));
    }
    return items;
  }

  /// 将每日统计转为字数折线图数据点
  List<ChartPoint> _toWordCountPoints(List stats) {
    return stats.map((stat) {
      return ChartPoint(label: '${stat.date.month}/${stat.date.day}', value: stat.wordsAdded);
    }).toList();
  }

  /// 将每日统计转为时长折线图数据点
  List<ChartPoint> _toDurationPoints(List stats) {
    return stats.map((stat) {
      return ChartPoint(label: '${stat.date.month}/${stat.date.day}', value: stat.durationSeconds);
    }).toList();
  }

  /// Y 轴字数格式化（一万以上显示万）
  String _formatWordCountAxis(int value) => WordCountUtils.formatWordCountShort(value);

  /// Y 轴时长格式化（秒 -> 分钟/小时）
  String _formatDurationAxis(int value) {
    if (value <= 0) return '0';
    if (value >= 3600) {
      final hours = value / 3600.0;
      return '${hours.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}h';
    }
    return '${value ~/ 60}m';
  }
}
