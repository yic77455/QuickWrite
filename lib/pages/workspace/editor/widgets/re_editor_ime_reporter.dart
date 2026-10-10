import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor 输入法光标上报器
///
/// Windows 端候选框坐标由原生层劫持 IME 消息后覆盖（见 `windows/runner/flutter_window.cpp`），
/// 该机制与编辑器实现无关，因此这里只需按 re_editor 的光标模型算出光标矩形，
/// 再通过 [ImeCursorFixer] 上报相同的通道数据。
///
/// 光标几何直接取自 re_editor 渲染对象提供的屏幕坐标换算结果，避免重复实现文本排版。
/// 取值失败时跳过本次上报，由原生层沿用上一次坐标。
class ReEditorImeReporter extends StatefulWidget {
  const ReEditorImeReporter({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.child,
    this.scrollController,
  });

  /// 编辑控制器，用于读取选区与拼音合成范围
  final CodeLineEditingController controller;

  /// 编辑器焦点节点，用于在获取焦点时立即上报坐标
  final FocusNode focusNode;

  /// 编辑器内部滚动控制器，滚动时同步刷新坐标
  final ScrollController? scrollController;

  /// 被包裹的编辑器组件
  final Widget child;

  @override
  State<ReEditorImeReporter> createState() => _ReEditorImeReporterState();
}

class _ReEditorImeReporterState extends State<ReEditorImeReporter> with WidgetsBindingObserver {
  /// 连续读取失败次数，用于诊断 re_editor 升级导致的坐标换算失配
  static const int _failureLogInterval = 60;

  /// 缓存已找到的排版渲染对象，避免每次光标移动都遍历元素树
  Object? _cachedRender;

  /// 连续读取失败次数
  int _failureCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_scheduleReport);
    widget.focusNode.addListener(_onFocusChanged);
    widget.scrollController?.addListener(_scheduleReport);
  }

  @override
  void didUpdateWidget(ReEditorImeReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleReport);
      widget.controller.addListener(_scheduleReport);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_scheduleReport);
      widget.scrollController?.addListener(_scheduleReport);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_scheduleReport);
    widget.focusNode.removeListener(_onFocusChanged);
    widget.scrollController?.removeListener(_scheduleReport);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 窗口大小或位置变化后光标屏幕坐标随之改变，需要重新上报
    if (widget.focusNode.hasFocus) {
      _scheduleReport();
    }
  }

  /// 等当前帧布局完成后再读取光标坐标
  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryReportNow());
  }

  /// 获取焦点时立即上报
  ///
  /// 目的是在用户按下第一个 IME 键触发合成开始之前，原生层已缓存正确的光标坐标。
  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) return;
    if (!_tryReportNow()) {
      // 组件刚构建尚未完成布局时读取失败，等下一帧重试
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryReportNow());
    }
  }

  /// 读取光标矩形并上报；渲染对象不可用或读取失败时返回 false
  bool _tryReportNow() {
    if (!mounted) return false;

    final Object? render = _findCodeFieldRender(context as Element);
    if (render == null) {
      _recordFailure('未找到排版渲染对象');
      return false;
    }

    final CodeLineSelection selection = widget.controller.selection;
    // 正在输入拼音时锚定到拼音起始位置，避免候选框随拼音右移而跳动
    final TextRange composing = widget.controller.composing;
    final CodeLinePosition anchor = composing.isValid && !composing.isCollapsed
        ? selection.extent.copyWith(offset: composing.start)
        : selection.extent;

    final Offset? caretBottom;
    try {
      // 通过渲染对象换算光标底部的屏幕坐标。
      // 方法名与参数类型均为公开成员，仅所属类不对外公开，因此以动态调用接入。
      caretBottom = (render as dynamic).calculateTextPositionScreenOffset(anchor, true) as Offset?;
    } catch (e) {
      _recordFailure('光标坐标换算失败: $e');
      return false;
    }
    if (caretBottom == null) {
      _recordFailure('光标不在可见区域内');
      return false;
    }

    _failureCount = 0;
    ImeCursorFixer.reportCursorPosition(
      globalOffset: caretBottom,
      lineHeight: SettingsService.instance.fontSize,
    );
    return true;
  }

  /// 记录读取失败并按间隔输出诊断日志
  void _recordFailure(String reason) {
    _failureCount++;
    if (_failureCount == 1 || _failureCount % _failureLogInterval == 0) {
      debugPrint('re_editor 输入法光标上报失败（第 $_failureCount 次）：$reason');
    }
  }

  /// 查找 re_editor 内部负责文字排版的渲染对象
  ///
  /// 该对象在文本与视口变化时不会重建，找到后缓存复用，仅在脱离渲染树时重新查找。
  Object? _findCodeFieldRender(Element root) {
    final Object? cached = _cachedRender;
    if (cached is RenderObject && cached.attached) {
      return cached;
    }

    Object? result;
    void visitor(Element element) {
      if (result != null) return;
      final RenderObject? renderObject = element.renderObject;
      if (renderObject != null &&
          renderObject.runtimeType.toString().contains('CodeFieldRender')) {
        result = renderObject;
        return;
      }
      element.visitChildren(visitor);
    }

    root.visitChildren(visitor);
    _cachedRender = result;
    return result;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}