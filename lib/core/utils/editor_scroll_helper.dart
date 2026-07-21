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

/// 编辑器底边距可见性保持器
///
/// 此类通过监听文本变化检测末尾换行操作，并在 Flutter 自动滚动完成后，
/// 额外向下补偿滚动偏移量，确保底边距始终保持在可视区域内。
class EditorBottomPaddingKeeper {
  /// 滚动控制器（外部 SingleChildScrollView 的控制器）
  final ScrollController scrollController;

  /// 文本编辑控制器，用于监听内容变化和光标位置
  final TextEditingController textController;

  /// 底边距占容器高度的比例系数
  ///
  /// 例如 0.6 表示底边距为容器高度的 60%，应与 Widget 层 Padding 定义保持一致
  final double paddingRatio;

  /// 上一次的文本长度，用于检测是否发生了"末尾追加单个字符"操作
  /// 仅记录长度而非完整字符串，确保每次对比开销为 O(1)
  int _previousTextLength = 0;

  /// 容器的最大可用高度（来自 LayoutBuilder 的 constraints.maxHeight）
  /// 用于计算底边距补偿值：_maxHeight * paddingRatio
  double _maxHeight = 0.0;

  EditorBottomPaddingKeeper({
    required this.scrollController,
    required this.textController,
    this.paddingRatio = 0.6,
  });

  /// 初始化监听器并记录初始文本长度
  ///
  /// 应在持有者 Widget 的 initState() 中调用
  void init() {
    _previousTextLength = textController.text.length;
    textController.addListener(_onTextChanged);
  }

  /// 更新容器高度缓存
  ///
  /// 应在 LayoutBuilder 的 builder 回调中调用，传入 constraints.maxHeight
  void updateMaxHeight(double maxHeight) {
    _maxHeight = maxHeight;
  }

  /// 清理所有内部资源
  ///
  /// 必须在持有者 Widget 的 dispose() 中调用，防止内存泄漏
  void dispose() {
    textController.removeListener(_onTextChanged);
  }

  /// 文本内容变化监听
  ///
  /// 检测文本增长操作（包括显式换行和输入文字导致的视觉换行），
  /// 并在内容高度增加时触发底边距补偿滚动
  void _onTextChanged() {
    final currentText = textController.text;
    final selection = textController.selection;
    final int currentLength = currentText.length;

    // 判定条件：
    // 1. 光标当前位于文本的最末尾位置
    // 2. 文本长度比上一次增加了
    final isCursorAtEnd = selection.extentOffset == currentLength;
    final isTextGrown = currentLength > _previousTextLength;

    // 更新历史记录，供下次对比使用
    _previousTextLength = currentLength;

    // 检测到文本增长且光标在末尾 → 触发底边距补偿
    if (isCursorAtEnd && isTextGrown) {
      _ensureBottomPaddingVisible();
    }
  }

  /// 确保编辑器底边距在可视区域内
  ///
  /// 在 Flutter 自动滚动完成后（通过 addPostFrameCallback 延迟执行），额外向下补偿一段距离，把底边距拉回可视区域。
  void _ensureBottomPaddingVisible() {
    if (_maxHeight <= 0) return;

    // 使用 addPostFrameCallback 等待当前帧的自动滚动完成后再介入
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      // 当前滚动位置能到达的最大偏移量（即：滚到最底部时的 offset）
      final double maxScrollOffset =
          scrollController.position.maxScrollExtent;

      // 当前实际滚动偏移量
      final double currentOffset = scrollController.offset;

      // 目标偏移量：直接滚到最大位置，确保底边距完全可见
      // 因为底边距是 Padding 的一部分，滚到最底部自然就能看到完整的底边距
      final double targetOffset = maxScrollOffset;

      // 只有当当前位置还没到达目标位置时才需要滚动补偿
      if (currentOffset < targetOffset) {
        scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }
}



typedef ApplyContentDimensionsCallback = void Function(ScrollPosition position, double minScrollExtent, double maxScrollExtent);

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
  });

  final ApplyContentDimensionsCallback onApplyContentDimensions;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // 在这里触发回调，允许在 Viewport 确定最终尺寸前，通过 correctPixels() 同步修改像素
    onApplyContentDimensions(this, minScrollExtent, maxScrollExtent);
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// 配合定制 ScrollPosition 使用的 Controller
class SyncScrollController extends ScrollController {
  SyncScrollController({
    super.initialScrollOffset = 0.0,
    super.keepScrollOffset = true,
    super.debugLabel,
    required this.onApplyContentDimensions,
  });

  final ApplyContentDimensionsCallback onApplyContentDimensions;

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
    );
  }
}