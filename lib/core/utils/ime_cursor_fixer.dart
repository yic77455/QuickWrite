import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';

/// 核心工具类：解决 Flutter Windows 平台下 IME 候选框位置不跟随光标的 BUG
///
/// 问题背景：
/// 在 Flutter Windows 桌面端，当使用中文输入法（如微软拼音、搜狗、RIME小狼毫等）时，候选框经常会出现在窗口左上角（0,0）或者发生跳动闪烁。
/// 这是由于 Flutter 引擎底层对WM_IME_STARTCOMPOSITION 和 WM_IME_COMPOSITION 消息处理存在缺陷导致的。
///
/// 解决原理：
/// 1. Dart 侧（此类）：精确计算输入框内真实的光标/组合文本矩形（通过 RenderEditable），
///    一方面通过 MethodChannel 发送给 C++ 侧，另一方面回填给引擎的光标矩形缓存。
/// 2. C++ 侧：通过 Win32 Subclass 劫持 Flutter 子窗口的 IME 消息，在 Flutter 引擎设置了错误坐标后，同步覆盖为正确的坐标。
class ImeCursorFixer {
  ImeCursorFixer._();

  /// 与 C++ 侧通信的通道
  static const MethodChannel _channel = MethodChannel('ime_cursor_channel');

  /// 仅在需要修正输入法候选框位置的平台启用
  static bool get _enabled => PlatformCapabilities.needsImeCursorFix;

  /// 上报输入法跟随区域到 C++ 侧缓存
  ///
  /// [globalRect] 光标或组合文本在屏幕上的绝对逻辑矩形。
  /// [textHeight] 文字字形高度（通常取字号），用于把组字窗口锚定在文字行底部，
  /// 使候选框出现在整行文字下方而不是压在行中间。
  ///
  /// 这里保留亚像素精度，不做取整：C++ 侧与引擎使用相同的「先乘 DPI 再截断」
  /// 换算方式，两者才能得到完全一致的物理像素，避免输入法窗口上下抖动。
  static Future<void> reportRect(Rect globalRect, {required double textHeight}) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('updateCursorPosition', {
        'x': globalRect.left,
        'y': globalRect.top,
        'width': globalRect.width,
        'height': globalRect.height,
        'textHeight': textHeight,
      });
    } catch (e) {
      debugPrint('ImeCursorFixer channel error: $e');
    }
  }

  /// 用真实光标矩形覆盖 Flutter 引擎内部记录的光标矩形
  ///
  /// 框架在没有组合文本时会把光标矩形按文本起始位置上报，引擎据此定位输入法窗口，
  /// 导致每次开始组字时候选框先出现在文本开头、再跳到光标处。这里在组字开始前
  /// 把真实光标矩形回填给引擎，使引擎自身的定位结果始终正确，从根源上消除闪烁。
  ///
  /// [localRect] 光标在渲染层局部坐标系下的矩形，与框架上报组合区域时使用的坐标系一致。
  static Future<void> reportCaretRectToEngine(Rect localRect) async {
    if (!_enabled || !localRect.isFinite) return;
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.setMarkedTextRect', {
        'x': localRect.left,
        'y': localRect.top,
        'width': localRect.width,
        'height': localRect.height,
      });
    } catch (e) {
      debugPrint('ImeCursorFixer engine channel error: $e');
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
    // 当前平台不需要修正输入法候选框时，跳过整个上报流程
    if (!PlatformCapabilities.needsImeCursorFix) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryReportNow());
  }

  /// 触发来源 2：焦点获取
  /// 用于修复微软拼音等输入法在输入第一个键时的候选框错位问题。
  void _onFocusChanged() {
    // 当前平台不需要修正输入法候选框时，跳过整个上报流程
    if (!PlatformCapabilities.needsImeCursorFix) return;
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

    // 与框架上报组合区域的规则保持一致：存在组合文本时取整段组合文本的矩形，
    // 否则取当前光标的矩形。组字窗口锚定矩形左上角，因此候选框不会随着
    // 拼音字符的增加而向右推移，也不会在键起键落时来回震动。
    final composing = value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    Rect? rect;
    if (isComposing) {
      rect = renderEditable.getRectForComposingRange(composing);
    }
    rect ??= renderEditable.getLocalRectForCaret(
      isComposing ? TextPosition(offset: composing.start) : selection.extent,
    );

    // 无组合文本时，框架会把光标矩形按文本起始位置上报给引擎，导致引擎在
    // 组字开始瞬间把输入法窗口定位到文本开头。这里用真实光标矩形覆盖引擎缓存，
    // 让引擎自身的定位始终正确，避免候选框先闪到别处再跳回光标处。
    if (!isComposing) {
      ImeCursorFixer.reportCaretRectToEngine(rect);
    }

    // 光标/组合区域在视图坐标系下的绝对矩形，交由 C++ 侧定位输入法窗口
    final globalRect = renderEditable.localToGlobal(rect.topLeft) & rect.size;

    // 字号决定文字字形高度；缺少样式信息时按行高的 70% 估算
    final double textHeight = renderEditable.text?.style?.fontSize ?? rect.height * 0.7;
    ImeCursorFixer.reportRect(globalRect, textHeight: textHeight);
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
