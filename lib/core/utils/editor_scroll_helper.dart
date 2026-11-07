import 'dart:async';
import 'package:flutter/material.dart';

/// 编辑器滚动保护器
///
/// 解决 IndexedStack 切换标签页时，滚动条被强制拉向光标位置的问题
class EditorScrollGuard {
  final ScrollController scrollController;
  VoidCallback? _scrollGuard;
  Timer? _unprotectTimer;

  EditorScrollGuard(this.scrollController);

  /// 启动滚动保护并锁定当前滚动位置
  ///
  /// 如果传入 [duration]，则会在指定时间后自动卸载保护
  void protect([Duration? duration]) {
    if (!scrollController.hasClients) return;
    
    // 如果已经处于保护状态，先卸载之前的保护
    unprotect();
    
    // 记录下保护开始时的滚动位置
    final targetOffset = scrollController.offset;
    
    _scrollGuard = () {
      if (!scrollController.hasClients) return;
      // 动态获取当前允许的最大滚动范围，防止目标位置越界导致无限 jumpTo 循环
      final minOffset = scrollController.position.minScrollExtent;
      final maxOffset = scrollController.position.maxScrollExtent;
      final clampedTarget = targetOffset.clamp(minOffset, maxOffset);
      
      // 一旦发现位置偏离（通常是被 requestFocus() 的自动滚动改变了），立即纠正
      if ((scrollController.offset - clampedTarget).abs() > 0.5) {
        scrollController.jumpTo(clampedTarget);
      }
    };
    
    scrollController.addListener(_scrollGuard!);

    if (duration != null) {
      _unprotectTimer?.cancel();
      _unprotectTimer = Timer(duration, unprotect);
    }
  }

  /// 卸载保护
  void unprotect() {
    _unprotectTimer?.cancel();
    _unprotectTimer = null;

    if (_scrollGuard != null) {
      scrollController.removeListener(_scrollGuard!);
      _scrollGuard = null;
    }
  }

  /// 在保护状态下，将保护目标更新为当前滚动位置
  ///
  /// 用于在 Layout 阶段补偿滚动偏移（如查找替换栏显示/隐藏导致的顶边距变化）后，
  /// 同步保护目标，避免保护器将滚动位置拉回补偿前的值导致视口内容闪烁。
  /// 若当前未处于保护状态，则不做任何操作。
  void retarget() {
    if (_scrollGuard == null || !scrollController.hasClients) return;
    // 读取补偿后的当前 offset 作为新目标
    final newTarget = scrollController.offset;
    // 移除旧 listener，复用原有的卸载定时器
    scrollController.removeListener(_scrollGuard!);
    _scrollGuard = () {
      if (!scrollController.hasClients) return;
      final minOffset = scrollController.position.minScrollExtent;
      final maxOffset = scrollController.position.maxScrollExtent;
      final clampedTarget = newTarget.clamp(minOffset, maxOffset);
      if ((scrollController.offset - clampedTarget).abs() > 0.5) {
        scrollController.jumpTo(clampedTarget);
      }
    };
    scrollController.addListener(_scrollGuard!);
  }

  void dispose() {
    unprotect();
  }
}

typedef ApplyContentDimensionsCallback = void Function(ScrollPosition position, double minScrollExtent, double maxScrollExtent);

/// 布局阶段修正滚动像素的回调
///
/// 返回 true 表示已通过 [ScrollPosition.correctPixels] 修改了滚动偏移，
/// 需要在本帧内重新布局以应用新的偏移。
typedef CorrectScrollOffsetCallback = bool Function(ScrollPosition position);

/// 自定义的 ScrollPosition，用于在 Layout 阶段同步拦截并修正滚动像素
class SyncScrollPosition extends ScrollPositionWithSingleContext {
  SyncScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels = 0.0,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    required this.onApplyContentDimensions,
    this.onCorrectScrollOffset,
  });

  final ApplyContentDimensionsCallback onApplyContentDimensions;

  /// 内容尺寸变化时按需修正滚动偏移的回调
  final CorrectScrollOffsetCallback? onCorrectScrollOffset;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // 在这里触发回调，允许在 Viewport 确定最终尺寸前，通过 correctPixels() 同步修改像素
    onApplyContentDimensions(this, minScrollExtent, maxScrollExtent);
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  @override
  bool correctForNewDimensions(ScrollMetrics oldPosition, ScrollMetrics newPosition) {
    // 内容尺寸变化后优先执行使用方的偏移修正；返回 false 使 Viewport 在本帧内重新布局，
    // 修正结果随本帧一起绘制，避免先按旧偏移渲染再滚动造成的视觉闪烁
    if (onCorrectScrollOffset?.call(this) ?? false) return false;
    return super.correctForNewDimensions(oldPosition, newPosition);
  }
}

/// 配合定制 ScrollPosition 使用的 Controller
class SyncScrollController extends ScrollController {
  SyncScrollController({
    super.initialScrollOffset = 0.0,
    super.keepScrollOffset = true,
    super.debugLabel,
    required this.onApplyContentDimensions,
    this.onCorrectScrollOffset,
  });

  final ApplyContentDimensionsCallback onApplyContentDimensions;

  /// 内容尺寸变化时按需修正滚动偏移的回调
  final CorrectScrollOffsetCallback? onCorrectScrollOffset;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SyncScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      onApplyContentDimensions: onApplyContentDimensions,
      onCorrectScrollOffset: onCorrectScrollOffset,
    );
  }
}