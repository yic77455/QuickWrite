import 'dart:async';

import 'package:flutter/foundation.dart';

/// 云同步调度器
///
/// 负责挑选自动同步的执行时机，真正的同步动作由上层通过 [onTrigger] 提供：
/// - 本地内容变化后按同步间隔模式触发：实时模式下几乎立即同步，定时模式下静置一段时间
/// - 按设定的时间间隔周期性触发（实时模式不使用周期定时器）
///
/// 该类只关心「什么时候同步」，不关心「怎么同步」，
/// 是否满足同步条件由上层在 [onTrigger] 中判断
class SyncScheduler {
  SyncScheduler({required Future<void> Function() onTrigger})
    : _onTrigger = onTrigger;

  /// 定时模式下，本地内容变化后需要静置的时长
  ///
  /// 编辑过程中会持续保存，等待内容稳定后再同步可以避免无谓的传输
  static const Duration debounceDuration = Duration(seconds: 60);

  /// 实时模式下，本地内容变化后需要静置的时长
  ///
  /// 保存动作本身已经是防抖后的结果（停止输入才会保存），
  /// 这里只留极短的合并窗口，用于吸收连续触发的多次保存
  static const Duration realtimeDebounceDuration = Duration(seconds: 1);

  /// 触发同步的动作
  final Future<void> Function() _onTrigger;

  /// 内容变化的防抖定时器
  Timer? _debounceTimer;

  /// 周期性同步定时器
  Timer? _intervalTimer;

  /// 是否处于实时同步模式
  bool _realtime = false;

  /// 通知本地内容发生了变化
  ///
  /// 每次调用都会重新计时：实时模式下等待 [realtimeDebounceDuration] 后同步，
  /// 定时模式下等待 [debounceDuration]，只有内容停止变化达到设定时长后才会触发
  void notifyLocalChange() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      _realtime ? realtimeDebounceDuration : debounceDuration,
      () => _trigger(_realtime ? '保存后实时同步' : '本地内容变化'),
    );
  }

  /// 设置周期性同步的间隔
  ///
  /// [interval] 为 null 或 [realtime] 为 true 时不启动周期定时器：
  /// 实时同步完全由保存动作驱动，再叠加周期同步只会重复消耗请求配额
  void applyInterval(Duration? interval, {bool realtime = false}) {
    _realtime = realtime;
    _intervalTimer?.cancel();
    _intervalTimer = (realtime || interval == null)
        ? null
        : Timer.periodic(interval, (_) => _trigger('到达同步间隔'));

    // 输出周期同步的当前状态
    if (realtime) {
      debugPrint('自动同步已切换为实时模式，每次保存后立即同步');
    } else {
      debugPrint(
        interval == null
            ? '自动同步计时器未启动'
            : '自动同步计时器已启动，间隔 ${interval.inMinutes} 分钟',
      );
    }
  }

  /// 停止全部调度并清除待触发的任务
  void stop() {
    final hadTimer = _debounceTimer != null || _intervalTimer != null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _intervalTimer?.cancel();
    _intervalTimer = null;

    // 输出周期同步的当前状态
    if (hadTimer) debugPrint('自动同步计时器已停止');
  }

  /// 触发一次同步
  ///
  /// [source] 触发本次同步的来源描述，便于区分不同的触发通路
  /// 触发动作由同步流程内部消化异常，这里仅做兜底，避免异常逃逸到定时器
  void _trigger(String source) {
    debugPrint('自动同步触发（$source）');
    _onTrigger().catchError((Object error) {
      debugPrint('同步触发失败: $error');
    });
  }
}
