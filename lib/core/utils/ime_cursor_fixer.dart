import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 核心工具类：解决 Flutter Windows 平台下 IME 候选框位置不跟随光标的 BUG
///
/// 问题背景：
/// 在 Flutter Windows 桌面端，当使用中文输入法（如微软拼音、搜狗、RIME小狼毫等）时，候选框经常会出现在窗口左上角（0,0）或者发生跳动闪烁。
/// 这是由于 Flutter 引擎底层对WM_IME_STARTCOMPOSITION 和 WM_IME_COMPOSITION 消息处理存在缺陷导致的。
///
/// 解决原理：
/// 1. Dart 侧（此类）：精确计算输入框内真实的光标坐标（通过 RenderEditable），并通过 MethodChannel 发送给 C++ 侧。
/// 2. C++ 侧：通过 Win32 Subclass 劫持 Flutter 子窗口的 IME 消息，在 Flutter 引擎设置了错误坐标后，同步覆盖为正确的坐标。
class ImeCursorFixer {
  ImeCursorFixer._();

  /// 与 C++ 侧通信的通道
  static const MethodChannel _channel = MethodChannel('ime_cursor_channel');

  /// 仅在 Windows 桌面端且非 Web 平台启用
  static bool get _enabled => !kIsWeb && Platform.isWindows;

  /// 上报当前光标绝对坐标到 C++ 侧缓存
  ///
  /// [globalOffset] 光标底部的屏幕绝对逻辑坐标
  /// [lineHeight] 光标的高度（用于计算候选框避让区域，防止遮挡文字）
  static Future<void> reportCursorPosition({required Offset globalOffset, double lineHeight = 20.0}) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('updateCursorPosition', {
        'x': globalOffset.dx.round(),
        'y': globalOffset.dy.round(),
        'height': lineHeight.round(),
      });
    } catch (e) {
      debugPrint('ImeCursorFixer channel error: $e');
    }
  }
}

/// 输入法光标修复包装器 Widget
///
/// 用于包裹 TextField，自动监听光标位置、文字变化、焦点状态和窗口大小变化，
/// 并将最新的光标坐标同步给底层。
///
/// 用法：
/// ```dart
/// ImeCursorFixerWrapper(
///   controller: _controller,
///   focusNode: _focusNode,
///   child: TextField(
///     controller: _controller,
///     focusNode: _focusNode,
///   ),
/// )
/// ```
class ImeCursorFixerWrapper extends StatefulWidget {
  /// 输入法光标修复包装器 Widget
  ///
  /// 用于包裹 TextField，自动监听光标位置、文字变化、焦点状态和窗口大小变化，
  /// 并将最新的光标坐标同步给底层。
  const ImeCursorFixerWrapper({super.key, required this.controller, required this.focusNode, required this.child});

  /// 绑定的文本控制器，用于监听输入文字和光标 Selection 变化
  final TextEditingController controller;

  /// 绑定的焦点节点，必须传入且与 TextField 共用同一个实例。
  final FocusNode focusNode;

  /// 被包裹的输入框组件（如 TextField）
  final Widget child;

  @override
  State<ImeCursorFixerWrapper> createState() => _ImeCursorFixerWrapperState();
}

class _ImeCursorFixerWrapperState extends State<ImeCursorFixerWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // 监听应用生命周期和窗口变化（例如窗口缩放、拖拽）
    WidgetsBinding.instance.addObserver(this);
    // 监听文字/光标变化（等下一帧 layout 更新后上报，保证坐标获取准确）
    widget.controller.addListener(_scheduleReport);
    // 监听焦点变化（获取焦点时立即同步上报）
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ImeCursorFixerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleReport);
      widget.controller.addListener(_scheduleReport);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_scheduleReport);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 窗口大小或位置改变时，如果当前输入框处于焦点状态，重新计算并上报绝对坐标
    if (widget.focusNode.hasFocus) {
      _scheduleReport();
    }
  }

  /// 触发来源 1：文字或光标位置发生变化
  /// 使用 addPostFrameCallback 是因为当前帧的布局可能还未完成，
  /// 需要等待 Flutter 渲染树排版完毕后，才能拿到最准确的光标屏幕坐标。
  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryReportNow());
  }

  /// 触发来源 2：焦点获取
  /// 用于修复微软拼音等输入法在输入第一个键时的候选框错位问题。
  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) return;

    // 获取焦点时同步上报。
    // 此时文字内容没有变化，layout 是当前帧的，getLocalRectForCaret 结果正确。
    // 目的：在用户按下第一个 IME 键（触发 WM_IME_STARTCOMPOSITION）之前，
    // C++ cache 里就已经存有正确的当前光标坐标，
    // 这样 WM_IME_STARTCOMPOSITION 触发时候选框能直接出现在正确位置。
    final reported = _tryReportNow();
    // 万一同步失败（例如 Widget 刚 build 还没 attach 到渲染树），等下一帧重试
    if (!reported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryReportNow());
    }
  }

  /// 立即尝试读取并上报光标坐标。
  ///
  /// 成功返回 true，失败（RenderEditable 还未 attach）返回 false。
  bool _tryReportNow() {
    if (!mounted) return false;

    // 找到底层的 RenderEditable，它是真正负责文字排版和渲染的节点
    final renderEditable = _findRenderEditable(context as Element);
    if (renderEditable == null || !renderEditable.attached) return false;

    final value = widget.controller.value;
    final selection = value.selection;
    if (!selection.isValid) return false;

    TextPosition targetPosition = selection.extent;

    // 如果正在进行拼音内嵌输入（composing），将候选框锚定在拼音的起始位置。
    // 避免打字时候选框跟着拼音不断向右推移，也防止在键起键落时光标状态切换导致的瞬间闪烁和震动。
    // 解决 RIME(小狼毫) / 微软拼音 等具有内嵌拼音特性输入法的跳动问题。
    if (value.composing.isValid && !value.composing.isCollapsed) {
      targetPosition = TextPosition(offset: value.composing.start);
    }

    // 直接从 RenderEditable 获取光标矩形，精度最高。
    // 这里读取的是 Flutter 内部真实的渲染结果，比使用 TextPainter 模拟计算更准。
    final caretRect = renderEditable.getLocalRectForCaret(targetPosition);

    // 光标底部的屏幕绝对坐标（输入法候选框应显示在光标下方）。
    // localToGlobal 在 Flutter Windows 上返回的是相对于 Flutter 客户区的逻辑像素坐标，
    // C++ 侧接收后乘以 DPI/96 即可得到 Win32 客户区物理像素坐标。
    final caretBottomGlobal = renderEditable.localToGlobal(caretRect.bottomLeft);

    // 计算字号：用于 C++ 侧配置 CFS_EXCLUDE 属性，划定输入法候选框的避让区域（防止候选框遮挡用户正在输入的文字）
    double fontSize = 14.0;
    final textSpan = renderEditable.text;
    if (textSpan?.style?.fontSize != null) {
      fontSize = textSpan!.style!.fontSize!;
    } else {
      // 兜底：光标高度的 70% 近似于字体的 cap-height
      fontSize = caretRect.height * 0.7;
    }

    ImeCursorFixer.reportCursorPosition(globalOffset: caretBottomGlobal, lineHeight: fontSize);
    return true;
  }

  /// 递归查找 TextField 内部真正负责文字渲染的 RenderEditable 节点
  RenderEditable? _findRenderEditable(Element root) {
    RenderEditable? result;
    void visitor(Element element) {
      if (result != null) return;
      if (element.renderObject is RenderEditable) {
        result = element.renderObject as RenderEditable;
      } else {
        element.visitChildren(visitor);
      }
    }

    root.visitChildren(visitor);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
