import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor 输入法光标上报器
///
/// Windows 端候选框坐标由原生层劫持 IME 消息后覆盖（见 `windows/runner/flutter_window.cpp`），
/// 该机制与编辑器实现无关，因此这里只需按 re_editor 的光标模型算出光标/组合区域矩形，
/// 再通过 [ImeCursorFixer] 上报相同的通道数据。
///
/// 光标几何直接取自 re_editor 渲染对象提供的坐标换算结果，避免重复实现文本排版。
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
  State<ReEditorImeReporter> createState() => ReEditorImeReporterState();
}

class ReEditorImeReporterState extends State<ReEditorImeReporter> with WidgetsBindingObserver {
  /// 连续读取失败次数，用于诊断 re_editor 升级导致的坐标换算失配
  static const int _failureLogInterval = 60;

  /// 坐标读取失败时的最大重试次数（按帧计）
  static const int _maxReportRetries = 4;

  /// 缓存已找到的排版渲染对象，避免每次光标移动都遍历元素树
  Object? _cachedRender;

  /// 连续读取失败次数
  int _failureCount = 0;

  /// 立即上报当前光标矩形
  ///
  /// 编辑器在布局阶段修正滚动位置后调用，使引擎在当帧内就拿到滚动后的坐标，
  /// 不必等到下一帧才纠正输入法窗口，避免候选框先出现在滚动前的位置再跳回。
  void reportNow() {
    if (!PlatformCapabilities.needsImeCursorFix) return;
    if (!_tryReportNow()) _scheduleReport();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    widget.focusNode.addListener(_onFocusChanged);
    widget.scrollController?.addListener(_scheduleReport);
  }

  @override
  void didUpdateWidget(ReEditorImeReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
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
    widget.controller.removeListener(_onControllerChanged);
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

  /// 光标或文本变化时立即上报
  ///
  /// 鼠标点击或方向键移动光标后选区已确定、排版也未变化，
  /// 此时同步上报可确保引擎在用户下一次按键之前就拿到新位置，
  /// 避免首次输入时候选框仍按旧光标显示。
  void _onControllerChanged() {
    if (!PlatformCapabilities.needsImeCursorFix) return;
    _tryReportNow();
    // 文本变化会改变排版与滚动，帧后再核对一次最终位置
    _scheduleReport();
  }

  /// 等当前帧布局完成后再读取光标坐标
  void _scheduleReport() {
    // 当前平台不需要修正输入法候选框时，跳过整个上报流程
    if (!PlatformCapabilities.needsImeCursorFix) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportWithRetry(0);
      // 排版与滚动可能在本帧末才稳定，下一帧再核对一次
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportWithRetry(0));
    });
  }

  /// 获取焦点时立即上报
  ///
  /// 目的是在用户按下第一个 IME 键触发合成开始之前，原生层已缓存正确的光标坐标。
  void _onFocusChanged() {
    // 当前平台不需要修正输入法候选框时，跳过整个上报流程
    if (!PlatformCapabilities.needsImeCursorFix) return;
    if (!widget.focusNode.hasFocus) return;
    if (!_tryReportNow()) {
      // 组件刚构建尚未完成布局时读取失败，等下一帧重试
      _scheduleReport();
    }
  }

  /// 上报光标矩形，读取失败时在后续帧继续尝试
  ///
  /// 换行后光标落在新增的行上，该行在当帧排版完成前取不到坐标；
  /// 若此时放弃上报，输入法会一直停留在换行前的屏幕位置。
  void _reportWithRetry(int attempt) {
    if (!mounted) return;
    if (_tryReportNow()) return;
    if (attempt >= _maxReportRetries) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportWithRetry(attempt + 1));
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

    try {
      // 通过渲染对象换算光标在视口局部坐标系下的位置。
      // 方法名与参数类型均为公开成员，仅所属类不对外公开，因此以动态调用接入。
      final dynamic codeFieldRender = render;
      final double lineHeight = codeFieldRender.lineHeight as double;
      final Offset? caretOffset =
          codeFieldRender.calculateTextPositionViewportOffset(selection.extent) as Offset?;
      if (caretOffset == null) {
        _recordFailure('光标不在可见区域内');
        return false;
      }

      final Rect localRect = Rect.fromLTWH(caretOffset.dx, caretOffset.dy, 0, lineHeight);
      final RenderBox renderBox = render as RenderBox;

      _failureCount = 0;

      // 先同步包含滚动位移的变换矩阵，再同步光标矩形：
      // 引擎按「矩形 × 变换」计算输入法窗口位置，两者都必须是当前值，
      // 否则换行引起滚动后候选框会停留在滚动前的位置。
      ImeCursorFixer.reportEditableTransform(
        size: renderBox.size,
        transform: renderBox.getTransformTo(null).storage,
      );
      // 组字范围在上屏瞬间可能尚未与最新文本同步，因此定位一律使用选区光标；
      // 这里把真实光标矩形回填给引擎，使其在任何时刻都基于当前光标定位。
      ImeCursorFixer.reportCaretRectToEngine(localRect);
      // 将绝对矩形上报给原生层输入法窗口定位
      final Rect globalRect = renderBox.localToGlobal(localRect.topLeft) & localRect.size;

      // 字号决定文字字形高度，用于把组字窗口锚定在文字行底部
      final TextStyle textStyle = codeFieldRender.textStyle as TextStyle;
      final double textHeight = textStyle.fontSize ?? lineHeight * 0.7;
      ImeCursorFixer.reportRect(globalRect, textHeight: textHeight);
      return true;
    } catch (e) {
      _recordFailure('光标坐标换算失败: $e');
      return false;
    }
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