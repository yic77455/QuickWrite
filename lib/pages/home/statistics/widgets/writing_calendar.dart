import 'package:flutter/material.dart';
import 'package:quick_write/core/services/writing_stats_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';

/// 码字日历
///
/// 展示当月每日的码字字数，号数下方显示对应字数。
/// 点击日期可切换"今日数据"卡片展示的日期。
/// 支持上一月/下一月切换。
class WritingCalendar extends StatelessWidget {
  /// 当前查看的月份（指向该月第一天）
  final DateTime month;

  /// 当月每日统计列表
  final List<DailyStat> calendarStats;

  /// 当前选中的日期
  final DateTime selectedDate;

  /// 点击日期回调
  final ValueChanged<DateTime> onDateSelected;

  /// 上一月回调
  final VoidCallback onPreviousMonth;

  /// 下一月回调
  final VoidCallback onNextMonth;

  const WritingCalendar({
    required this.month,
    required this.calendarStats,
    required this.selectedDate,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    super.key,
  });

  /// 星期表头
  static const List<String> _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 将统计列表转为日期 -> 字数的映射
    final statMap = <DateTime, int>{};
    for (final stat in calendarStats) {
      statMap[stat.date] = stat.wordsAdded;
    }

    // 计算日历网格所需的日期
    final days = _buildMonthDays(month);
    final today = _normalizeDate(DateTime.now());

    // 判断是否可以切换到下一月（禁止翻到未来月份）
    final canGoNext = month.year < today.year ||
        (month.year == today.year && month.month < today.month);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 月份导航
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  onPressed: onPreviousMonth,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${month.year}年${month.month}月',
                      style: context.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  onPressed: canGoNext ? onNextMonth : null,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 星期表头
            Row(
              children: _weekLabels.map((label) {
                return Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: context.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // 日期网格
            ..._buildWeekRows(context, days, statMap, today, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 构建日期网格的每一行（按周分组）
  List<Widget> _buildWeekRows(
    BuildContext context,
    List<DateTime?> days,
    Map<DateTime, int> statMap,
    DateTime today,
    ColorScheme colorScheme,
  ) {
    final rows = <Widget>[];
    for (int i = 0; i < days.length; i += 7) {
      final weekDays = days.sublist(i, i + 7);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: weekDays.map((date) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: date == null
                      ? const SizedBox(height: 56)
                      : _buildDayCell(context, date, statMap[date] ?? 0, today, colorScheme),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }
    return rows;
  }

  /// 构建单个日期格子
  ///
  /// 字体颜色区分规则：
  /// - 今天：primary 色 + 粗体 + 边框
  /// - 过去有数据：onSurface（正常色）
  /// - 过去无数据：onSurfaceVariant（较淡）
  /// - 未来：onSurfaceVariant 半透明
  /// - 选中：primary 色背景
  Widget _buildDayCell(
    BuildContext context,
    DateTime date,
    int wordCount,
    DateTime today,
    ColorScheme colorScheme,
  ) {
    final isSelected = _normalizeDate(selectedDate) == date;
    final isToday = today == date;
    final isFuture = date.isAfter(today);
    final hasData = wordCount > 0;

    // 号数颜色
    Color dayColor;
    if (isSelected) {
      dayColor = colorScheme.primary;
    } else if (isToday) {
      dayColor = colorScheme.primary;
    } else if (isFuture) {
      dayColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    } else if (hasData) {
      dayColor = colorScheme.onSurface;
    } else {
      dayColor = colorScheme.onSurfaceVariant;
    }

    return InkWell(
      onTap: isFuture ? null : () => onDateSelected(date),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isToday
              ? Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: context.bodyMedium?.copyWith(
                fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                color: dayColor,
              ),
            ),
            const SizedBox(height: 2),
            // 今天和过去都显示字数（哪怕为0），未来不显示
            if (!isFuture)
              Text(
                hasData ? WordCountUtils.formatWordCountShort(wordCount, wanThreshold: 100000) : '0',
                style: context.labelSmall?.copyWith(
                  fontSize: 10,
                  color: hasData
                      ? colorScheme.primary.withValues(alpha: 0.8)
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建当月日期列表（含前置空位补齐周一起始）
  List<DateTime?> _buildMonthDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 周一为 1，周日为 7；前置空位数 = (weekday - 1)
    final leadingBlanks = firstDay.weekday - 1;

    final days = <DateTime?>[];
    for (int i = 0; i < leadingBlanks; i++) {
      days.add(null);
    }
    for (int d = 1; d <= daysInMonth; d++) {
      days.add(DateTime(month.year, month.month, d));
    }
    // 尾部补齐到 7 的倍数
    while (days.length % 7 != 0) {
      days.add(null);
    }
    return days;
  }

  /// 将日期归一化为当天零点
  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);
}
