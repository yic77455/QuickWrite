import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/writing_stats_service.dart';

/// 码字会话追踪器
///
/// 追踪当前工作台会话的码字统计数据，供工具面板实时展示，
/// 并通过防抖机制将增量持久化到 [WritingStatsService]。
///
/// 内部维护两套字数：
/// - added（含粘贴）：反映"当前文本相对今早的净增"
/// - typed（不含粘贴）：反映"今日键盘累计输入"，用于计算码字速度
///
/// 撤销/恢复操作不调用本追踪器，因此不影响今日码字与码字速度。
class WritingSessionTracker extends ChangeNotifier {
  // ================= 会话统计数据 =================

  /// 今日净增字数（含粘贴，从数据库加载，随用户码字实时更新）
  int _todayWordsAdded = 0;

  /// 今日键盘输入字数（不含粘贴，从数据库加载，随用户码字实时更新）
  int _todayTypedWords = 0;

  /// 本次会话净增字数（含粘贴，打开工作台时重置为 0）
  int _sessionWordsAdded = 0;

  /// 本次会话键盘输入字数（不含粘贴，打开工作台时重置为 0）
  int _sessionTypedWords = 0;

  /// 今日码字（根据"是否包含粘贴字数"开关返回 added 或 typed）
  int get todayWords =>
      MiscCacheService.instance.isStatsIncludePasteWords() ? _todayWordsAdded : _todayTypedWords;

  /// 本次码字（根据"是否包含粘贴字数"开关返回 added 或 typed）
  int get sessionWords =>
      MiscCacheService.instance.isStatsIncludePasteWords() ? _sessionWordsAdded : _sessionTypedWords;

  /// 码字时长（秒，打开工作台时重置）
  int _sessionDurationSeconds = 0;
  int get sessionDurationSeconds => _sessionDurationSeconds;

  /// 空闲时长（秒，打开工作台时重置，为累计总空闲时长）
  int _idleDurationSeconds = 0;
  int get idleDurationSeconds => _idleDurationSeconds;

  /// 码字速度（字/分，基于键盘输入字数计算，不含粘贴与撤销/恢复）
  int get writingSpeed {
    if (_sessionDurationSeconds == 0) return 0;
    return (_sessionTypedWords * 60 / _sessionDurationSeconds).round();
  }

  // ================= 活动追踪状态 =================

  /// 最近一次编辑活动时间，用于判断用户是否仍在活跃码字
  DateTime _lastActivityTime = DateTime.now();

  /// 是否已开始码字（首次编辑活动后才为 true，在此之前不计时）
  bool _hasStartedWriting = false;

  /// 每秒触发的计时器，用于更新码字时长、空闲时长并检测跨天
  Timer? _timer;

  /// 是否已释放
  bool _isDisposed = false;

  /// 空闲判定阈值（秒）：超过此时间无编辑活动则视为空闲
  static const int _idleThresholdSeconds = 60;

  // ================= 持久化状态 =================

  /// 当前追踪的书籍 UUID（用于持久化写入）
  String _bookUuid = '';

  /// 待持久化的键盘输入字数增量
  int _pendingTypedDelta = 0;

  /// 待持久化的粘贴字数增量
  int _pendingPastedDelta = 0;

  /// 待持久化的码字时长（秒）
  int _pendingDurationSeconds = 0;

  /// 防抖定时器：累积增量后延迟写入数据库，避免频繁 IO
  Timer? _flushTimer;

  /// 防抖延迟（毫秒）：停止输入 2 秒后写入统计数据库
  static const int _flushDebounceMs = 2000;

  /// 时长落库阈值（秒）：累积满 60 秒写入一次数据库
  static const int _durationFlushInterval = 60;

  /// 当前统计日期（归一化为当天零点，用于跨天检测）
  DateTime _currentDate = DateTime.now();

  // ================= 外部回调 =================

  /// 跨天回调：跨天时触发，由调用方重置各章节的基线字数
  VoidCallback? onDayChanged;

  /// 持久化完成回调：每次 flush 写入数据库后触发，由调用方通知首页刷新
  VoidCallback? onFlushed;

  /// 初始化会话追踪器
  ///
  /// 从数据库加载今日码字数据（含粘贴与键盘输入两套字段），并启动每秒计时器。
  /// 在工作台初始化时调用。
  Future<void> init(String bookUuid) async {
    _bookUuid = bookUuid;
    _lastActivityTime = DateTime.now();
    _currentDate = _normalizeDate(DateTime.now());

    // 从数据库读取今日码字数据
    final todayStat = await WritingStatsService.instance.getDailyStat(
      bookUuid,
      _currentDate,
    );
    _todayWordsAdded = todayStat.wordsAdded;
    _todayTypedWords = todayStat.typedWords;

    // 启动每秒计时器，驱动时长统计、跨天检测和 UI 刷新
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    notifyListeners();
  }

  /// 更新码字字数
  ///
  /// [typedDelta] 为键盘输入引起的字数增量（正为新增，负为删除），
  /// [pastedDelta] 为粘贴操作引起的字数增量。
  ///
  /// 同时累积到内存（即时刷新 UI）和 pending（防抖写入数据库）。
  /// 撤销/恢复不调用本方法，因此不影响今日码字与码字速度。
  void onWordsChanged({int typedDelta = 0, int pastedDelta = 0}) {
    if (_isDisposed) return;
    if (typedDelta == 0 && pastedDelta == 0) return;

    // 累积到内存（即时刷新 UI）
    _todayWordsAdded += typedDelta + pastedDelta;
    _todayTypedWords += typedDelta;
    _sessionWordsAdded += typedDelta + pastedDelta;
    _sessionTypedWords += typedDelta;

    // 累积到 pending（防抖写入数据库）
    _pendingTypedDelta += typedDelta;
    _pendingPastedDelta += pastedDelta;

    // 标记已开始码字并刷新活跃时间，重置防抖定时器
    _hasStartedWriting = true;
    _lastActivityTime = DateTime.now();
    _scheduleFlush();

    notifyListeners();
  }

  /// 记录用户编辑活动
  ///
  /// 每次用户输入时调用，刷新最近活动时间以维持"活跃"状态。
  void onActivity() {
    _hasStartedWriting = true;
    _lastActivityTime = DateTime.now();
  }

  /// 每秒计时回调
  ///
  /// 依次执行：
  /// 1. 跨天检测：跨天时先 flush 昨日增量，再重置今日字段并通知调用方重置基线
  /// 2. 时长统计：根据最近活动时间判断活跃/空闲并累加相应时长
  /// 3. 通知 UI 刷新
  void _tick() {
    if (_isDisposed) return;

    final now = DateTime.now();
    final today = _normalizeDate(now);

    // 跨天检测
    if (today != _currentDate) {
      _handleDayChange();
      _currentDate = today;
    }

    // 时长统计：用户开始码字后才计时，活跃时累加码字时长并累积落库，空闲时累加空闲时长
    if (_hasStartedWriting) {
      final idleSeconds = now.difference(_lastActivityTime).inSeconds;
      if (idleSeconds <= _idleThresholdSeconds) {
        _sessionDurationSeconds++;
        _pendingDurationSeconds++;
        if (_pendingDurationSeconds >= _durationFlushInterval) {
          _flushDuration();
        }
      } else {
        _idleDurationSeconds++;
      }
    }

    notifyListeners();
  }

  /// 处理跨天：flush 昨日增量后重置今日字段，并通知调用方重置章节基线
  void _handleDayChange() {
    // 先把昨日增量与时长写入数据库（仍写入昨日的记录）
    _flushPending();
    _flushDuration();

    // 重置今日与会话字段，开始新一天统计
    _todayWordsAdded = 0;
    _todayTypedWords = 0;
    _sessionWordsAdded = 0;
    _sessionTypedWords = 0;
    _sessionDurationSeconds = 0;
    _idleDurationSeconds = 0;

    // 通知调用方重置所有章节的基线，避免删除旧内容被错误计入新一天
    onDayChanged?.call();
  }

  /// 调度防抖写入：每次有新增量时重置定时器，2 秒后无新增量则执行写入
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: _flushDebounceMs), _flushPending);
  }

  /// 将待持久化的增量写入统计数据库
  ///
  /// [totalDelta] = typedDelta + pastedDelta，对应数据库的 wordsAdded 字段；
  /// [typedDelta] 对应 typedWords 字段。
  /// 写入完成后清零 pending 并通知调用方触发首页刷新。
  void _flushPending() {
    _flushTimer?.cancel();
    _flushTimer = null;

    final typedDelta = _pendingTypedDelta;
    final pastedDelta = _pendingPastedDelta;
    final totalDelta = typedDelta + pastedDelta;

    if (totalDelta == 0) return;
    if (_bookUuid.isEmpty) return;

    _pendingTypedDelta = 0;
    _pendingPastedDelta = 0;

    // 异步写入，不阻塞 UI
    WritingStatsService.instance
        .recordWordsAdded(_bookUuid, totalDelta, typedDelta)
        .then((_) => onFlushed?.call())
        .catchError((e) => debugPrint('写入码字统计失败: $e'));
  }

  /// 将累积的码字时长写入统计数据库
  ///
  /// 满落库阈值、跨天或释放时调用，写入完成后通知调用方触发首页刷新。
  void _flushDuration() {
    if (_pendingDurationSeconds <= 0 || _bookUuid.isEmpty) return;
    final seconds = _pendingDurationSeconds;
    _pendingDurationSeconds = 0;
    // 异步写入，不阻塞 UI
    WritingStatsService.instance
        .addDuration(_bookUuid, seconds)
        .then((_) => onFlushed?.call())
        .catchError((e) => debugPrint('写入码字时长失败: $e'));
  }

  /// 将日期归一化为当天零点
  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _flushTimer?.cancel();
    // 释放前强制写入剩余字数与时长，避免数据丢失
    _flushPending();
    _flushDuration();
    super.dispose();
  }
}
