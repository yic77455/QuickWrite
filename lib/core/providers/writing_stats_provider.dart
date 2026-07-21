import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/writing_stats_service.dart';

/// 图表区间模式
enum ChartRangeMode {
  /// 本周
  week,
  /// 本月
  month,
}

/// 码字统计页面状态管理 Provider
///
/// 管理统计页面的筛选条件与加载的数据：
/// - 书籍筛选（全部或指定书籍）
/// - 日历查看月份
/// - 选中日期（用于"今日数据"卡片，可通过点击日历切换）
/// - 图表区间模式（本周/本月）
/// - 是否包含粘贴字数（仅影响统计界面的显示，不影响实际数据录入）
class WritingStatsProvider extends ChangeNotifier {
  WritingStatsProvider() {
    _selectedDate = _normalizeDate(DateTime.now());
    _calendarMonth = DateTime(_selectedDate.year, _selectedDate.month);
    _loadIncludePasteWords();
  }

  // ================= 筛选状态 =================

  /// 书籍筛选 UUID，空字符串表示"全部书籍"
  String _selectedBookUuid = '';
  String get selectedBookUuid => _selectedBookUuid;

  /// 选中日期（用于今日数据卡片展示）
  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  /// 日历当前查看的月份（指向该月第一天）
  DateTime _calendarMonth = DateTime.now();
  DateTime get calendarMonth => _calendarMonth;

  /// 图表区间模式
  ChartRangeMode _chartRangeMode = ChartRangeMode.week;
  ChartRangeMode get chartRangeMode => _chartRangeMode;

  /// 是否包含粘贴字数（仅影响统计界面的显示，不影响实际数据录入）
  bool _includePasteWords = true;
  bool get includePasteWords => _includePasteWords;

  /// 从缓存加载粘贴字数开关状态
  void _loadIncludePasteWords() {
    _includePasteWords = MiscCacheService.instance.isStatsIncludePasteWords();
  }

  // ================= 加载的数据（原始） =================

  /// 选中日期的统计数据（原始，含粘贴字数）
  DailyStat _rawSelectedDateStat = DailyStat(
    date: DateTime(2000),
    wordsAdded: 0,
    typedWords: 0,
    durationSeconds: 0,
  );

  /// 日历月份的每日统计（原始）
  List<DailyStat> _rawCalendarStats = [];

  /// 图表数据（原始，字数与时长共用同一份数据）
  List<DailyStat> _rawChartStats = [];

  /// 数据总览（原始）
  OverviewStats _rawOverviewStats = OverviewStats.empty();

  /// 连续码字天数
  int _consecutiveDays = 0;
  int get consecutiveDays => _consecutiveDays;

  /// 是否正在加载
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ================= 转换后的数据（供 UI 使用） =================

  /// 选中日期的统计数据（根据 [includePasteWords] 决定是否包含粘贴字数）
  DailyStat get selectedDateStat => _filterStat(_rawSelectedDateStat);

  /// 日历月份的每日统计（根据 [includePasteWords] 决定是否包含粘贴字数）
  List<DailyStat> get calendarStats =>
      _rawCalendarStats.map(_filterStat).toList();

  /// 字数图表数据（根据 [includePasteWords] 决定是否包含粘贴字数）
  List<DailyStat> get wordCountChartStats =>
      _rawChartStats.map(_filterStat).toList();

  /// 时长图表数据（时长不受粘贴字数开关影响，直接返回原始数据）
  List<DailyStat> get durationChartStats => _rawChartStats;

  /// 数据总览（根据 [includePasteWords] 决定是否包含粘贴字数）
  OverviewStats get overviewStats => _filterOverview(_rawOverviewStats);

  // ================= 状态变更方法 =================

  /// 设置书籍筛选
  Future<void> setSelectedBook(String bookUuid) async {
    if (_selectedBookUuid == bookUuid) return;
    _selectedBookUuid = bookUuid;
    notifyListeners();
    await _loadAll();
  }

  /// 设置选中日期（点击日历日期时调用）
  Future<void> setSelectedDate(DateTime date) async {
    final normalized = _normalizeDate(date);
    if (_selectedDate == normalized) return;
    _selectedDate = normalized;
    notifyListeners();
    await _loadSelectedDateStat();
  }

  /// 切换日历月份（-1 上月，1 下月）
  Future<void> changeCalendarMonth(int delta) async {
    _calendarMonth = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + delta,
    );
    notifyListeners();
    await _loadCalendarStats();
  }

  /// 设置图表区间模式
  Future<void> setChartRangeMode(ChartRangeMode mode) async {
    if (_chartRangeMode == mode) return;
    _chartRangeMode = mode;
    notifyListeners();
    await _loadChartStats();
  }

  /// 切换是否包含粘贴字数（仅影响统计界面的显示）
  void toggleIncludePasteWords() {
    _includePasteWords = !_includePasteWords;
    notifyListeners();
    MiscCacheService.instance.saveStatsIncludePasteWords(_includePasteWords);
  }

  /// 刷新全部数据
  Future<void> refresh() async {
    await _loadAll();
  }

  // ================= 数据加载方法 =================

  /// 加载所有统计数据
  Future<void> _loadAll() async {
    _isLoading = true;
    notifyListeners();

    await Future.wait([
      _loadSelectedDateStat(),
      _loadCalendarStats(),
      _loadChartStats(),
      _loadOverview(),
      _loadConsecutiveDays(),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  /// 加载选中日期的统计
  Future<void> _loadSelectedDateStat() async {
    _rawSelectedDateStat = await WritingStatsService.instance.getDailyStat(
      _selectedBookUuid,
      _selectedDate,
    );
    notifyListeners();
  }

  /// 加载日历月份的每日统计
  Future<void> _loadCalendarStats() async {
    _rawCalendarStats = await WritingStatsService.instance.getMonthlyDailyStats(
      _selectedBookUuid,
      _calendarMonth.year,
      _calendarMonth.month,
    );
    notifyListeners();
  }

  /// 加载图表数据（本周或本月）
  Future<void> _loadChartStats() async {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    if (_chartRangeMode == ChartRangeMode.week) {
      // 本周：从周一到今天
      final weekday = now.weekday; // 周一为 1
      start = now.subtract(Duration(days: weekday - 1));
    } else {
      // 本月：从月初到今天
      start = DateTime(now.year, now.month);
    }

    _rawChartStats = await WritingStatsService.instance.getDailyStatsForRange(
      _selectedBookUuid,
      start,
      end,
    );
    notifyListeners();
  }

  /// 加载数据总览
  Future<void> _loadOverview() async {
    _rawOverviewStats = await WritingStatsService.instance.getOverviewStats(
      _selectedBookUuid,
    );
    notifyListeners();
  }

  /// 加载连续码字天数
  Future<void> _loadConsecutiveDays() async {
    _consecutiveDays = await WritingStatsService.instance.getConsecutiveWritingDays(
      _selectedBookUuid,
    );
    notifyListeners();
  }

  // ================= 工具方法 =================

  /// 将日期归一化为当天零点
  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

  /// 根据 [includePasteWords] 过滤单日统计数据
  ///
  /// 关闭粘贴字数时，将 [DailyStat.wordsAdded] 替换为 [DailyStat.typedWords]，
  /// 使 UI 层读取 wordsAdded 时得到的是不含粘贴的字数。
  DailyStat _filterStat(DailyStat stat) {
    if (_includePasteWords) return stat;
    return DailyStat(
      date: stat.date,
      wordsAdded: stat.typedWords,
      typedWords: stat.typedWords,
      durationSeconds: stat.durationSeconds,
    );
  }

  /// 根据 [includePasteWords] 过滤总览数据
  ///
  /// 关闭粘贴字数时，将累计字数和单日最高字数替换为基于键盘输入的值。
  OverviewStats _filterOverview(OverviewStats stats) {
    if (_includePasteWords) return stats;
    return OverviewStats(
      writingDays: stats.writingDays,
      totalBooks: stats.totalBooks,
      totalWordsAdded: stats.totalTypedWords,
      totalTypedWords: stats.totalTypedWords,
      maxDayWords: stats.maxDayTypedWords,
      maxDayTypedWords: stats.maxDayTypedWords,
      maxDayDuration: stats.maxDayDuration,
    );
  }
}
