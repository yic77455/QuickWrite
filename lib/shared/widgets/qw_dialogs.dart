import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 移动端弹窗距离屏幕左右两侧的最小间距
///
/// 移动端屏幕较窄，弹窗宽度需据此收窄，避免左右两侧完全贴边
const double _mobileDialogHorizontalMargin = 20;

/// 弹窗距离屏幕上下边缘的最小留白
///
/// 弹窗的最大高度据此从屏幕高度折算，保证不论窗口大小都能完整显示
const double _dialogVerticalMargin = 24;

/// 弹窗底部与输入法顶部之间需保持的最小间距
///
/// 输入法顶部距弹窗底部不足该间距时即视为过于接近，弹窗需上移避让以保证底部按钮可见
const double _keyboardDialogGap = 16;

/// 通用弹窗外壳
///
/// 提供可拖拽、圆角、阴影的弹窗容器
/// [adaptiveHeight] 是否自适应高度，为 true 时 height 作为最大高度（移动端放宽至屏幕可用高度）
/// [anchorTop] 是否锚定顶部，为 true 时高度变化仅调整底部，顶部位置不变（需配合 adaptiveHeight 使用）
/// [draggable] 是否允许拖拽，默认为 true；移动端始终禁用拖拽
/// [dialogInteractiveNotifier] 动态控制对话框的交互状态（拖拽和关闭），为 false 时禁止拖拽和点击遮罩关闭
///
/// 移动端会将弹窗宽度收窄至左右两侧各留出 [_mobileDialogHorizontalMargin] 的间距
Future<T?> showDialogBase<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  double width = 400,
  double height = 300,
  bool showCloseButton = true,
  bool adaptiveHeight = false,
  bool anchorTop = false,
  double borderRadius = 12,
  double titleFontSize = 16,
  bool barrierDismissible = true,
  bool draggable = true,
  ValueListenable<bool>? dialogInteractiveNotifier,
}) {
  // 移动端屏幕较窄：收窄弹窗宽度，避免左右两侧贴边；同时关闭拖拽，
  // 防止触摸操作下弹窗被误拖走
  double effectiveWidth = width;
  bool effectiveDraggable = draggable;
  if (PlatformCapabilities.isMobile) {
    final double maxWidth = MediaQuery.sizeOf(context).width - _mobileDialogHorizontalMargin * 2;
    if (effectiveWidth > maxWidth) effectiveWidth = maxWidth;
    effectiveDraggable = false;
  }

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => _DraggableDialog(
      title: title,
      content: content,
      width: effectiveWidth,
      height: height,
      showCloseButton: showCloseButton,
      adaptiveHeight: adaptiveHeight,
      anchorTop: anchorTop,
      borderRadius: borderRadius,
      titleFontSize: titleFontSize,
      draggable: effectiveDraggable,
      dialogInteractiveNotifier: dialogInteractiveNotifier,
    ),
  );
}

/// 可拖拽弹窗组件
class _DraggableDialog extends StatefulWidget {
  final String title;
  final Widget content;
  final double width;
  final double height;
  final bool showCloseButton;
  final bool adaptiveHeight;
  final bool anchorTop;
  final double borderRadius;
  final double titleFontSize;
  final bool draggable;
  final ValueListenable<bool>? dialogInteractiveNotifier;

  const _DraggableDialog({
    required this.title,
    required this.content,
    required this.width,
    required this.height,
    required this.showCloseButton,
    this.adaptiveHeight = false,
    this.anchorTop = false,
    this.borderRadius = 12,
    this.titleFontSize = 16,
    this.draggable = true,
    this.dialogInteractiveNotifier,
  });

  @override
  State<_DraggableDialog> createState() => _DraggableDialogState();
}

class _DraggableDialogState extends State<_DraggableDialog> {
  /// 用户拖拽产生的偏移量（相对默认位置，初始为零）
  Offset _dragOffset = Offset.zero;

  /// 弹窗为避让输入法而上移的偏移量
  ///
  /// 仅当输入框会被输入法遮挡或与输入法过于接近时才大于零，其余情况保持为零
  double _keyboardShift = 0;

  /// 弹窗内容区域的锚点，用于测量弹窗的实际位置与尺寸以计算避让偏移
  final GlobalKey _dialogKey = GlobalKey();

  /// 是否已为当前帧安排避让偏移的重新评估，避免同帧重复调度
  bool _shiftUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.dialogInteractiveNotifier?.addListener(_onInteractiveChanged);
  }

  @override
  void dispose() {
    widget.dialogInteractiveNotifier?.removeListener(_onInteractiveChanged);
    super.dispose();
  }

  void _onInteractiveChanged() {
    setState(() {});
  }

  /// 键盘弹出时输入法占用的底部高度
  double _keyboardInset(BuildContext context) => MediaQuery.viewInsetsOf(context).bottom;

  /// 屏幕的可用高度（扣除上下留白与输入法占用的高度）
  ///
  /// [keyboardInset] 为当前生效的输入法高度（后台弹窗不受输入法影响，传入 0）；
  /// 可用高度据此扣减，弹窗收窄后仍能完整显示在输入法上方（内容超出时自动转为滚动）
  double _screenAvailableHeight(double keyboardInset) {
    final double visible = MediaQuery.sizeOf(context).height - keyboardInset - _dialogVerticalMargin * 2;
    return math.max(0, visible);
  }

  /// 计算弹窗允许的最大高度
  ///
  /// [available] 为当前屏幕可用高度；自适应高度弹窗按内容自然高度伸展，
  /// 移动端上限放宽到屏幕可用高度，使窄屏下文字换行导致内容变高时弹窗能随之增高；
  /// 其余情况以声明高度为准，仅在屏幕高度不足时收窄，避免弹窗超出可视区域
  double _resolveMaxHeight(double available) {
    if (widget.adaptiveHeight && PlatformCapabilities.isMobile) return available;
    return math.min(widget.height, available);
  }

  /// 安排一次避让偏移的重新评估
  ///
  /// 偏移依赖弹窗与输入框的实际布局结果，需在当前帧布局完成后读取，
  /// 因此推迟到帧末执行，并保证同一帧只调度一次
  void _scheduleKeyboardShiftUpdate(double screenHeight, double keyboardInset) {
    if (_shiftUpdateScheduled) return;
    _shiftUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shiftUpdateScheduled = false;
      _updateKeyboardShift(screenHeight, keyboardInset);
    });
  }

  /// 重新评估弹窗为避让输入法需要上移的偏移量
  ///
  /// 仅当弹窗底部会被输入法遮挡，或弹窗底部与输入法顶部不足 [_keyboardDialogGap] 时才上移，
  /// 上移幅度以刚好让弹窗底部（按钮所在位置）避开输入法为准；
  /// 同时限制上移量，避免弹窗顶部被顶出屏幕外
  void _updateKeyboardShift(double screenHeight, double keyboardInset) {
    if (!mounted) return;

    final RenderBox? dialogBox = _dialogKey.currentContext?.findRenderObject() as RenderBox?;
    // 弹窗尚未完成布局时无法测量位置，无需避让
    if (dialogBox == null || !dialogBox.hasSize) {
      if (_keyboardShift != 0) setState(() => _keyboardShift = 0);
      return;
    }

    final double keyboardTop = screenHeight - keyboardInset;
    // 实测坐标已包含当前上移量，还原后得到弹窗不受避让影响的自然位置
    final double naturalDialogTop = dialogBox.localToGlobal(Offset.zero).dy + _keyboardShift;
    final double naturalDialogBottom = naturalDialogTop + dialogBox.size.height;

    // 弹窗底部需保持在输入法顶部上方 [_keyboardDialogGap] 处，据此得到所需上移量
    final double desiredShift = naturalDialogBottom + _keyboardDialogGap - keyboardTop;
    // 上移量上限：确保弹窗顶部不会越过屏幕留白而被顶出屏幕
    final double maxShift = math.max(0, naturalDialogTop - _dialogVerticalMargin);
    final double shift = desiredShift.clamp(0, maxShift).toDouble();

    if ((shift - _keyboardShift).abs() > 0.5) {
      setState(() => _keyboardShift = shift);
    }
  }

  /// 获取当前是否可拖拽
  ///
  /// [draggable] 为 false 时（如移动端）一律禁止拖拽，
  /// 否则由 [dialogInteractiveNotifier] 的当前值决定
  bool get _isDraggable {
    if (!widget.draggable) return false;
    return widget.dialogInteractiveNotifier?.value ?? true;
  }

  /// 获取当前是否允许通过返回键、Esc 或手势返回关闭弹窗
  ///
  /// 仅当存在进行中的操作（notifier 为 false）时返回 false
  bool get _canPop {
    final notifier = widget.dialogInteractiveNotifier;
    return notifier == null || notifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 仅最顶层的弹窗参与输入法避让；被其他弹窗覆盖的后台弹窗应保持静止，不随输入法移动或收窄
    final bool isTopmost = ModalRoute.of(context)?.isCurrent ?? true;
    // 读取输入法高度既用于计算避让，也使输入法弹出/收起时本组件重建，及时更新避让偏移
    final double keyboardInset = isTopmost ? _keyboardInset(context) : 0;
    final double screenHeight = MediaQuery.sizeOf(context).height;
    _scheduleKeyboardShiftUpdate(screenHeight, keyboardInset);

    final double available = _screenAvailableHeight(keyboardInset);
    final double maxHeight = _resolveMaxHeight(available);
    // 绝对定位模式（固定高度/锚定顶部）计算基础位置所参照的高度：
    // 以「声明高度与可用高度中的较小值」为参照，使弹窗按设计高度居中，
    // 且内容高度变化时（锚定顶部模式）顶部位置保持稳定
    final double referenceHeight = math.min(widget.height, available);
    final Size screenSize = MediaQuery.sizeOf(context);
    // 弹窗在未应用避让偏移前，纵向居中于整个屏幕
    final Offset basePosition = Offset(
      (screenSize.width - widget.width) / 2,
      (screenSize.height - referenceHeight) / 2,
    );
    final dialogContent = Container(
      key: _dialogKey,
      width: widget.width,
      height: widget.adaptiveHeight ? null : maxHeight,
      constraints: widget.adaptiveHeight ? BoxConstraints(maxHeight: maxHeight) : null,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        mainAxisSize: widget.adaptiveHeight ? MainAxisSize.min : MainAxisSize.max,
        children: [
          // 标题栏（拖拽区域）- 仅当标题不为空时显示
          if (widget.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: context.titleLarge?.copyWith(fontSize: widget.titleFontSize, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (widget.showCloseButton)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: colorScheme.onSurfaceVariant,
                      hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
                      highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                    ),
                ],
              ),
            ),
          // 无标题栏时显示关闭按钮
          if (widget.title.isEmpty && widget.showCloseButton)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
          // 内容区域
          // 自适应高度模式下内容按自然高度渲染，可超出弹窗的声明高度；
          // 超出最大高度时改为滚动，避免窄屏下文字换行导致内容溢出报错
          Flexible(
            child: Material(
              color: Colors.transparent,
              child: widget.adaptiveHeight ? SingleChildScrollView(child: widget.content) : widget.content,
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: _canPop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 自适应高度 + 锚定顶部模式：使用 Positioned 绝对定位，高度变化时顶部位置不变
          if (widget.adaptiveHeight && widget.anchorTop)
            Positioned(
              left: basePosition.dx + _dragOffset.dx,
              top: basePosition.dy + _dragOffset.dy - _keyboardShift,
              child: GestureDetector(
                onPanUpdate: _isDraggable
                    ? (details) {
                        setState(() {
                          _dragOffset += details.delta;
                        });
                      }
                    : null,
                child: dialogContent,
              ),
            )
          // 自适应高度模式：使用 Center + Transform.translate 实现垂直居中
          // 拖拽偏移叠加在避让偏移之上，初始为零即自然居中
          else if (widget.adaptiveHeight)
            Center(
              child: Transform.translate(
                offset: _dragOffset + Offset(0, -_keyboardShift),
                child: GestureDetector(
                  onPanUpdate: _isDraggable
                      ? (details) {
                          setState(() {
                            _dragOffset += details.delta;
                          });
                        }
                      : null,
                  child: dialogContent,
                ),
              ),
            )
          else
            // 固定高度模式：使用 Positioned 绝对定位
            Positioned(
              left: basePosition.dx + _dragOffset.dx,
              top: basePosition.dy + _dragOffset.dy - _keyboardShift,
              child: GestureDetector(
                onPanUpdate: _isDraggable
                    ? (details) {
                        setState(() {
                          _dragOffset += details.delta;
                        });
                      }
                    : null,
                child: dialogContent,
              ),
            ),
        ],
      ),
    );
  }
}

// ================= 输入对话框 =================

/// 显示输入对话框
///
/// [context] 上下文
/// [title] 标题
/// [hintText] 输入框提示文字
/// [confirmText] 确认按钮文字
/// [cancelText] 取消按钮文字
/// [initialValue] 初始值（用于编辑场景）
/// [onConfirm] 确认回调，参数为输入的值，返回错误信息（null 表示成功）
Future<void> showInputDialog({
  required BuildContext context,
  required String title,
  String hintText = '请输入',
  String confirmText = '确定',
  String cancelText = '取消',
  String? initialValue,
  String? subtitle,
  required Future<String?> Function(String) onConfirm,
}) {
  return showDialogBase(
    context: context,
    title: title,
    width: 360,
    // 自适应高度：弹窗高度由内容自然高度决定，height 仅作为上限
    height: 260,
    adaptiveHeight: true,
    content: _InputDialogContent(
      hintText: hintText,
      confirmText: confirmText,
      cancelText: cancelText,
      initialValue: initialValue,
      subtitle: subtitle,
      onConfirm: onConfirm,
    ),
  );
}

/// 输入对话框内容
class _InputDialogContent extends StatefulWidget {
  final String hintText;
  final String confirmText;
  final String cancelText;
  final String? initialValue;
  final String? subtitle;
  final Future<String?> Function(String) onConfirm;

  const _InputDialogContent({
    required this.hintText,
    required this.confirmText,
    required this.cancelText,
    this.initialValue,
    this.subtitle,
    required this.onConfirm,
  });

  @override
  State<_InputDialogContent> createState() => _InputDialogContentState();
}

class _InputDialogContentState extends State<_InputDialogContent> {
  late final TextEditingController _controller;
  // 焦点节点
  final _focusNode = FocusNode();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    final value = _controller.text.trim();

    if (value.isEmpty) {
      setState(() => _errorMessage = '请输入内容');
      return;
    }

    setState(() => _isLoading = true);

    final error = await widget.onConfirm(value);

    if (mounted) {
      if (error != null) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        children: [
          // 用 ImeCursorFixerWrapper 包裹 TextField，修复中文输入法光标跟随问题
          ImeCursorFixerWrapper(
            controller: _controller,
            focusNode: _focusNode,
            child: TextField(
              style: context.bodyLarge,
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              decoration: InputDecoration(hintText: widget.hintText, errorText: _errorMessage),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              onSubmitted: (_) => _handleConfirm(),
            ),
          ),
          // 副标题提示
          if (widget.subtitle != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 0, 0),
                child: Text(
                  widget.subtitle!,
                  style: context.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          // 输入框与按钮之间的固定间距，避免依赖剩余空间导致不同设备下间距不一致
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: _isLoading ? null : _handleConfirm,
                child: _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.confirmText, textAlign: TextAlign.center),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                child: Text(widget.cancelText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ================= 确认对话框 =================

/// 确认对话框类型
enum ConfirmType {
  /// 删除类型（红色警告）
  delete,

  /// 警告类型（蓝色提示）
  warning,

  /// 信息类型（普通提示）
  info,
}

/// 显示确认对话框
///
/// [context] 上下文
/// [title] 标题
/// [description] 描述文字
/// [type] 类型（默认 info）
/// [confirmText] 确认按钮文字
/// [cancelText] 取消按钮文字（为空则只显示确认按钮）
/// [icon] 自定义图标
/// [onConfirm] 确认回调
/// [barrierDismissible] 是否允许点击弹窗外部关闭，默认允许
///
/// 返回用户的选择：点击确认按钮返回 true，取消或直接关闭返回 false
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String description,
  ConfirmType type = ConfirmType.info,
  String confirmText = '确定',
  String? cancelText,
  IconData? icon,
  VoidCallback? onConfirm,
  bool barrierDismissible = true,
}) async {
  final confirmed = await showDialogBase<bool>(
    context: context,
    title: '',
    width: 420,
    height: 310,
    showCloseButton: false,
    adaptiveHeight: true,
    barrierDismissible: barrierDismissible,
    content: _ConfirmDialogContent(
      title: title,
      description: description,
      type: type,
      confirmText: confirmText,
      cancelText: cancelText,
      icon: icon,
      onConfirm: onConfirm,
    ),
  );
  return confirmed ?? false;
}

/// 确认对话框内容
class _ConfirmDialogContent extends StatelessWidget {
  final String title;
  final String description;
  final ConfirmType type;
  final String confirmText;
  final String? cancelText;
  final IconData? icon;
  final VoidCallback? onConfirm;

  const _ConfirmDialogContent({
    required this.title,
    required this.description,
    required this.type,
    required this.confirmText,
    this.cancelText,
    this.icon,
    this.onConfirm,
  });

  IconData _getIcon() {
    if (icon != null) return icon!;
    switch (type) {
      case ConfirmType.delete:
        return Icons.auto_delete_outlined;
      case ConfirmType.warning:
        return Icons.warning_amber_outlined;
      case ConfirmType.info:
        return Icons.info_outline;
    }
  }

  Color _getIconColor(ColorScheme colorScheme) {
    switch (type) {
      case ConfirmType.delete:
        return colorScheme.error;
      case ConfirmType.warning:
        return colorScheme.tertiary;
      case ConfirmType.info:
        return colorScheme.primary;
    }
  }

  Color _getIconBackgroundColor(ColorScheme colorScheme) {
    switch (type) {
      case ConfirmType.delete:
        return colorScheme.errorContainer.withValues(alpha: 0.5);
      case ConfirmType.warning:
        return colorScheme.tertiaryContainer.withValues(alpha: 0.5);
      case ConfirmType.info:
        return colorScheme.primaryContainer.withValues(alpha: 0.5);
    }
  }

  Color? _getConfirmButtonColor(ColorScheme colorScheme) {
    return type == ConfirmType.delete ? colorScheme.error : null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: _getIconBackgroundColor(colorScheme), shape: BoxShape.circle),
            child: Icon(_getIcon(), size: 24, color: _getIconColor(colorScheme)),
          ),
          const SizedBox(height: 16),
          // 标题
          Text(title, style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          // 描述
          Text(
            description,
            textAlign: TextAlign.center,
            style: context.bodyLarge?.copyWith(height: 1.5, color: colorScheme.onSurface.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 20),
          // 按钮
          cancelText != null
              ? Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop(true);
                          onConfirm?.call();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _getConfirmButtonColor(colorScheme),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(confirmText),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                        child: Text(cancelText!),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                      onConfirm?.call();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _getConfirmButtonColor(colorScheme),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(confirmText),
                  ),
                ),
        ],
      ),
    );
  }
}

// ================= 未保存确认对话框 =================

/// 未保存确认对话框结果
///
/// 用于在关闭标签页或关闭窗口前，让用户决定如何处理未保存的内容
enum UnsavedConfirmResult {
  /// 保存内容后继续关闭
  save,

  /// 不保存直接关闭（放弃修改）
  discard,

  /// 取消关闭操作
  cancel,
}

/// 显示未保存内容确认对话框
///
/// 当标签页或窗口存在未保存的修改时弹窗询问用户处理方式，
/// 提供三个按钮：保存、不保存、取消。
///
/// [context] 弹窗上下文
/// [title] 标题
/// [description] 描述文字
/// [saveText] 保存按钮文字
/// [discardText] 不保存按钮文字
/// [cancelText] 取消按钮文字
/// 返回用户选择的结果；若用户通过遮罩或 ESC 关闭则视为 [UnsavedConfirmResult.cancel]
Future<UnsavedConfirmResult> showUnsavedConfirmDialog({
  required BuildContext context,
  required String title,
  required String description,
  String saveText = '保存',
  String discardText = '不保存',
  String cancelText = '取消',
}) async {
  final result = await showDialogBase<UnsavedConfirmResult>(
    context: context,
    title: '',
    width: 420,
    height: 280,
    showCloseButton: false,
    adaptiveHeight: true,
    barrierDismissible: false,
    content: _UnsavedConfirmDialogContent(
      title: title,
      description: description,
      saveText: saveText,
      discardText: discardText,
      cancelText: cancelText,
    ),
  );
  return result ?? UnsavedConfirmResult.cancel;
}

/// 未保存确认对话框内容组件
class _UnsavedConfirmDialogContent extends StatelessWidget {
  final String title;
  final String description;
  final String saveText;
  final String discardText;
  final String cancelText;

  const _UnsavedConfirmDialogContent({
    required this.title,
    required this.description,
    required this.saveText,
    required this.discardText,
    required this.cancelText,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图标（警告色，提示存在未保存内容）
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_outlined, size: 24, color: colorScheme.tertiary),
          ),
          const SizedBox(height: 16),
          // 标题
          Text(title, style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          // 描述
          Text(
            description,
            textAlign: TextAlign.center,
            style: context.bodyLarge?.copyWith(height: 1.5, color: colorScheme.onSurface.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 20),
          // 三按钮组：保存 / 不保存 / 取消
          Row(
            children: [
              // 保存按钮（主操作，填充色突出）
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(UnsavedConfirmResult.save),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: Text(saveText),
                ),
              ),
              const SizedBox(width: 8),
              // 不保存按钮（中性样式，提示会丢失修改）
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(UnsavedConfirmResult.discard),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(discardText),
                ),
              ),
              const SizedBox(width: 8),
              // 取消按钮（弱化样式）
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(UnsavedConfirmResult.cancel),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: Text(cancelText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ================= 选择列表对话框 =================

/// 选择项数据
class SelectItem {
  /// 显示文字
  final String label;

  /// 图标
  final IconData? icon;

  /// 是否禁用
  final bool disabled;

  /// 是否选中
  final bool selected;

  /// 关联的数据
  final String value;

  const SelectItem({required this.label, required this.value, this.icon, this.disabled = false, this.selected = false});
}

/// 显示选择列表对话框
///
/// [context] 上下文
/// [title] 标题
/// [items] 选择项列表
/// [onSelected] 选择回调，参数为选中项的 value
/// [width] 弹窗宽度，默认 320
/// [height] 弹窗高度，默认 400
/// [borderRadius] 弹窗圆角，默认 12
/// [titleFontSize] 标题字体大小，默认 16
/// [itemPadding] 选项左右内边距，默认 16
/// [listPadding] 列表上下内边距，默认 12
Future<void> showSelectDialog({
  required BuildContext context,
  required String title,
  required List<SelectItem> items,
  required void Function(String) onSelected,
  double width = 320,
  double height = 400,
  double borderRadius = 12,
  double titleFontSize = 16,
  double itemPadding = 16,
  double listPadding = 12,
}) {
  return showDialogBase(
    context: context,
    title: title,
    width: width,
    height: height,
    borderRadius: borderRadius,
    titleFontSize: titleFontSize,
    content: _SelectDialogContent(
      items: items,
      onSelected: onSelected,
      itemPadding: itemPadding,
      listPadding: listPadding,
    ),
  );
}

/// 选择列表对话框内容
class _SelectDialogContent extends StatelessWidget {
  final List<SelectItem> items;
  final void Function(String) onSelected;
  final double itemPadding;
  final double listPadding;

  const _SelectDialogContent({
    required this.items,
    required this.onSelected,
    this.itemPadding = 16,
    this.listPadding = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 列表区域
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(vertical: listPadding),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: item.disabled
                      ? null
                      : () {
                          onSelected(item.value);
                          Navigator.of(context).pop();
                        },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: itemPadding, vertical: 12),
                    child: Row(
                      children: [
                        if (item.icon != null) ...[
                          Icon(
                            item.icon,
                            size: 20,
                            color: item.disabled
                                ? colorScheme.onSurface.withValues(alpha: 0.3)
                                : colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          item.label,
                          style: context.titleLarge?.copyWith(
                            fontSize: 15,
                            color: item.disabled ? colorScheme.onSurface.withValues(alpha: 0.3) : colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        if (item.selected) Icon(Icons.check, size: 20, color: colorScheme.primary),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // 底部取消按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          ),
        ),
      ],
    );
  }
}

// ================= 加载中弹窗 =================

/// 显示加载中弹窗（转圈提示）
///
/// 在耗时操作执行期间显示居中的转圈动画和提示文字，
/// 用户无法通过点击遮罩关闭弹窗（barrierDismissible: false）
///
/// [context] 构建上下文
/// [message] 加载提示文字
/// 返回一个用于关闭弹窗的函数，调用者需在操作完成后手动调用以关闭弹窗
void Function() showLoadingDialog({required BuildContext context, required String message}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      // 禁止通过 Esc 键、返回键、手势返回等任何方式关闭弹窗，
      // 只能由调用者通过返回的 dismissLoading 函数来关闭
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 转圈加载动画
              const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(height: 16),
              // 提示文字
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    ),
  );
  // 返回关闭弹窗的函数，由调用者在操作完成后调用
  return () {
    Navigator.of(context).pop();
  };
}
