import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/group.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/models/recycle_item.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/writing_stat.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 单日码字统计结果
class DailyStat {
  /// 统计日期（归一化为当天零点）
  final DateTime date;

  /// 当日净增字数（含粘贴）
  final int wordsAdded;

  /// 当日键盘输入字数（不含粘贴，用于计算码字速度）
  final int typedWords;

  /// 当日码字时长（秒）
  final int durationSeconds;

  const DailyStat({
    required this.date,
    required this.wordsAdded,
    required this.typedWords,
    required this.durationSeconds,
  });

  /// 空记录
  factory DailyStat.empty(DateTime date) => DailyStat(
        date: date,
        wordsAdded: 0,
        typedWords: 0,
        durationSeconds: 0,
      );
}

/// 数据总览结果
class OverviewStats {
  /// 创作天数（有码字活动的天数）
  final int writingDays;

  /// 累计创作书籍数
  final int totalBooks;

  /// 累计码字字数（含粘贴）
  final int totalWordsAdded;

  /// 累计键盘输入字数（不含粘贴）
  final int totalTypedWords;

  /// 单日最高码字数（含粘贴）
  final int maxDayWords;

  /// 单日最高键盘输入字数（不含粘贴）
  final int maxDayTypedWords;

  /// 单日最高码字时长（秒）
  final int maxDayDuration;

  const OverviewStats({
    required this.writingDays,
    required this.totalBooks,
    required this.totalWordsAdded,
    required this.totalTypedWords,
    required this.maxDayWords,
    required this.maxDayTypedWords,
    required this.maxDayDuration,
  });

  /// 空总览
  factory OverviewStats.empty() => const OverviewStats(
        writingDays: 0,
        totalBooks: 0,
        totalWordsAdded: 0,
        totalTypedWords: 0,
        maxDayWords: 0,
        maxDayTypedWords: 0,
        maxDayDuration: 0,
      );
}

/// 码字统计服务
///
/// 单例模式，负责读写 [WritingStatModel] 数据：
/// - 记录章节保存时的字数增量
/// - 累积码字时长
/// - 提供按日、按区间、按书籍的聚合查询
///
/// [bookUuid] 为空字符串时表示"全部书籍"，由服务层汇总所有书籍数据。
class WritingStatsService {
  // ================= 单例模式 =================
  static final WritingStatsService instance = WritingStatsService._internal();
  WritingStatsService._internal();

  /// 缓存的 Isar 实例，避免并发调用时重复打开数据库
  Isar? _isar;

  /// 获取 Isar 实例
  ///
  /// 优先使用缓存；其次复用已打开的实例；若不存在则按全量 Schema 打开。
  Future<Isar> _getIsar() async {
    if (_isar != null) return _isar!;

    final name = AppPaths.instance.databaseName;
    _isar = Isar.getInstance(name) ??
        await Isar.open(
          [
            BookModelSchema,
            GroupModelSchema,
            RecycleBinModelSchema,
            RecycleItemModelSchema,
            ChapterModelSchema,
            VolumeModelSchema,
            SettingGroupModelSchema,
            SettingItemModelSchema,
            WritingStatModelSchema,
          ],
          directory: AppPaths.instance.databaseDirectory,
          name: name,
        );
    return _isar!;
  }

  // ================= 写入方法 =================

  /// 记录字数增量到指定书籍的当日统计
  ///
  /// [bookUuid] 书籍 UUID
  /// [totalDelta] 总字数增量（含粘贴，可为负值，负值表示码字过程中的删除）
  /// [typedDelta] 键盘输入字数增量（不含粘贴，可为负值）
  Future<void> recordWordsAdded(String bookUuid, int totalDelta, int typedDelta) async {
    if (bookUuid.isEmpty) return;
    final isar = await _getIsar();
    final today = _normalizeDate(DateTime.now());

    await isar.writeTxn(() async {
      final existing = await isar.writingStatModels
          .where()
          .bookUuidEqualTo(bookUuid)
          .filter()
          .dateEqualTo(today)
          .findFirst();

      if (existing != null) {
        existing.wordsAdded += totalDelta;
        existing.typedWords += typedDelta;
        existing.updatedAt = DateTime.now();
        await isar.writingStatModels.put(existing);
      } else {
        final stat = WritingStatModel()
          ..bookUuid = bookUuid
          ..date = today
          ..wordsAdded = totalDelta
          ..typedWords = typedDelta
          ..durationSeconds = 0
          ..updatedAt = DateTime.now();
        await isar.writingStatModels.put(stat);
      }
    });
  }

  /// 累积码字时长到指定书籍的当日统计
  ///
  /// [bookUuid] 书籍 UUID；[seconds] 时长增量（秒）。
  Future<void> addDuration(String bookUuid, int seconds) async {
    if (seconds <= 0 || bookUuid.isEmpty) return;
    final isar = await _getIsar();
    final today = _normalizeDate(DateTime.now());

    await isar.writeTxn(() async {
      final existing = await isar.writingStatModels
          .where()
          .bookUuidEqualTo(bookUuid)
          .filter()
          .dateEqualTo(today)
          .findFirst();

      if (existing != null) {
        existing.durationSeconds += seconds;
        existing.updatedAt = DateTime.now();
        await isar.writingStatModels.put(existing);
      } else {
        final stat = WritingStatModel()
          ..bookUuid = bookUuid
          ..date = today
          ..wordsAdded = 0
          ..durationSeconds = seconds
          ..updatedAt = DateTime.now();
        await isar.writingStatModels.put(stat);
      }
    });
  }

  /// 清空所有码字统计数据
  ///
  /// 删除全部书籍的历史统计记录，操作不可恢复
  Future<void> clearAllStats() async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.writingStatModels.clear();
    });
    debugPrint('已清空所有码字统计数据');
  }

  // ================= 查询方法 =================

  /// 获取指定书籍某日的统计
  ///
  /// [bookUuid] 为空字符串时汇总全部书籍。
  Future<DailyStat> getDailyStat(String bookUuid, DateTime date) async {
    final isar = await _getIsar();
    final normalized = _normalizeDate(date);

    if (bookUuid.isEmpty) {
      // 全部书籍：汇总当日所有记录
      final stats = await isar.writingStatModels
          .where()
          .dateEqualTo(normalized)
          .findAll();
      return DailyStat(
        date: normalized,
        wordsAdded: stats.fold(0, (s, e) => s + e.wordsAdded),
        typedWords: stats.fold(0, (s, e) => s + e.typedWords),
        durationSeconds: stats.fold(0, (s, e) => s + e.durationSeconds),
      );
    }

    final stat = await isar.writingStatModels
        .where()
        .bookUuidEqualTo(bookUuid)
        .filter()
        .dateEqualTo(normalized)
        .findFirst();

    if (stat == null) return DailyStat.empty(normalized);
    return DailyStat(
      date: normalized,
      wordsAdded: stat.wordsAdded,
      typedWords: stat.typedWords,
      durationSeconds: stat.durationSeconds,
    );
  }

  /// 获取指定书籍在日期区间内每日的统计列表
  ///
  /// 返回区间内每一天的记录（无数据的天返回空记录），便于图表直接绘制。
  /// [bookUuid] 为空字符串时汇总全部书籍。
  Future<List<DailyStat>> getDailyStatsForRange(
    String bookUuid,
    DateTime start,
    DateTime end,
  ) async {
    final isar = await _getIsar();
    final normalizedStart = _normalizeDate(start);
    final normalizedEnd = _normalizeDate(end);

    // 拉取区间内的原始记录
    final rawStats = await isar.writingStatModels
        .where()
        .dateBetween(normalizedStart, normalizedEnd)
        .filter()
        .optional(bookUuid.isNotEmpty, (q) => q.bookUuidEqualTo(bookUuid))
        .findAll();

    // 按日期聚合（全部书籍场景下同一天可能有多条记录）
    final Map<DateTime, DailyStat> aggregated = {};
    for (final stat in rawStats) {
      final day = _normalizeDate(stat.date);
      final existing = aggregated[day];
      if (existing != null) {
        aggregated[day] = DailyStat(
          date: day,
          wordsAdded: existing.wordsAdded + stat.wordsAdded,
          typedWords: existing.typedWords + stat.typedWords,
          durationSeconds: existing.durationSeconds + stat.durationSeconds,
        );
      } else {
        aggregated[day] = DailyStat(
          date: day,
          wordsAdded: stat.wordsAdded,
          typedWords: stat.typedWords,
          durationSeconds: stat.durationSeconds,
        );
      }
    }

    // 按天补齐空记录，保证图表横轴连续
    final result = <DailyStat>[];
    var cursor = normalizedStart;
    while (!cursor.isAfter(normalizedEnd)) {
      result.add(aggregated[cursor] ?? DailyStat.empty(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  /// 获取指定书籍当月的每日统计（用于码字日历）
  ///
  /// [bookUuid] 为空字符串时汇总全部书籍。
  Future<List<DailyStat>> getMonthlyDailyStats(
    String bookUuid,
    int year,
    int month,
  ) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1, 0); // 当月最后一天
    return getDailyStatsForRange(bookUuid, start, end);
  }

  /// 获取数据总览
  ///
  /// [bookUuid] 为空字符串时汇总全部书籍。
  Future<OverviewStats> getOverviewStats(String bookUuid) async {
    final isar = await _getIsar();

    // 累计创作书籍数：统计历史所有有过码字记录的书籍（含已删除的书）
    final allStats = await isar.writingStatModels.where().findAll();
    final totalBooks = allStats.map((s) => s.bookUuid).toSet().length;

    final stats = allStats
        .where((s) => bookUuid.isEmpty || s.bookUuid == bookUuid)
        .toList();

    if (stats.isEmpty) {
      return OverviewStats(
        writingDays: 0,
        totalBooks: totalBooks,
        totalWordsAdded: 0,
        totalTypedWords: 0,
        maxDayWords: 0,
        maxDayTypedWords: 0,
        maxDayDuration: 0,
      );
    }

    // 按日期聚合，统计有活动的天数
    final Map<DateTime, DailyStat> aggregated = {};
    for (final stat in stats) {
      final day = _normalizeDate(stat.date);
      final existing = aggregated[day];
      if (existing != null) {
        aggregated[day] = DailyStat(
          date: day,
          wordsAdded: existing.wordsAdded + stat.wordsAdded,
          typedWords: existing.typedWords + stat.typedWords,
          durationSeconds: existing.durationSeconds + stat.durationSeconds,
        );
      } else {
        aggregated[day] = DailyStat(
          date: day,
          wordsAdded: stat.wordsAdded,
          typedWords: stat.typedWords,
          durationSeconds: stat.durationSeconds,
        );
      }
    }

    int writingDays = 0;
    int totalWords = 0;
    int totalTyped = 0;
    int maxDayWords = 0;
    int maxDayTypedWords = 0;
    int maxDayDuration = 0;

    for (final day in aggregated.values) {
      // 有码字活动：字数或时长大于 0
      if (day.wordsAdded > 0 || day.durationSeconds > 0) {
        writingDays++;
      }
      totalWords += day.wordsAdded;
      totalTyped += day.typedWords;
      if (day.wordsAdded > maxDayWords) maxDayWords = day.wordsAdded;
      if (day.typedWords > maxDayTypedWords) maxDayTypedWords = day.typedWords;
      if (day.durationSeconds > maxDayDuration) maxDayDuration = day.durationSeconds;
    }

    return OverviewStats(
      writingDays: writingDays,
      totalBooks: totalBooks,
      totalWordsAdded: totalWords,
      totalTypedWords: totalTyped,
      maxDayWords: maxDayWords,
      maxDayTypedWords: maxDayTypedWords,
      maxDayDuration: maxDayDuration,
    );
  }

  /// 获取连续码字天数
  ///
  /// 从今日向前回溯，遇到无活动的日期即停止。
  /// [bookUuid] 为空字符串时汇总全部书籍。
  Future<int> getConsecutiveWritingDays(String bookUuid) async {
    final isar = await _getIsar();
    final today = _normalizeDate(DateTime.now());

    // 一次性拉取最近 365 天的记录用于回溯，避免逐日查询
    final start = today.subtract(const Duration(days: 365));
    final stats = await isar.writingStatModels
        .where()
        .dateBetween(start, today)
        .filter()
        .optional(bookUuid.isNotEmpty, (q) => q.bookUuidEqualTo(bookUuid))
        .findAll();

    final Map<DateTime, bool> activeDays = {};
    for (final stat in stats) {
      final day = _normalizeDate(stat.date);
      final hasActivity = stat.wordsAdded > 0 || stat.durationSeconds > 0;
      if (hasActivity) {
        activeDays[day] = true;
      }
    }

    int streak = 0;
    var cursor = today;
    // 今日无活动时，从昨日开始计算连续天数（避免今日尚未码字时显示 0）
    if (!activeDays.containsKey(today)) {
      cursor = today.subtract(const Duration(days: 1));
    }
    while (activeDays.containsKey(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ================= 工具方法 =================

  /// 将日期归一化为当天零点
  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);
}
