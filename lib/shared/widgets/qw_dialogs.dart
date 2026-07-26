import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 通用弹窗外壳
///
/// 提供可拖拽、圆角、阴影的弹窗容器
/// [adaptiveHeight] 是否自适应高度，为 true 时 height 作为最大高度
/// [anchorTop] 是否锚定顶部，为 true 时高度变化仅调整底部，顶部位置不变（需配合 adaptiveHeight 使用）
/// [draggable] 是否允许拖拽，默认为 true
/// [dialogInteractiveNotifier] 动态控制对话框的交互状态（拖拽和关闭），为 false 时禁止拖拽和点击遮罩关闭
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
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => _DraggableDialog(
      title: title,
      content: content,
      width: width,
      height: height,
      showCloseButton: showCloseButton,
      adaptiveHeight: adaptiveHeight,
      anchorTop: anchorTop,
      borderRadius: borderRadius,
      titleFontSize: titleFontSize,
      draggable: draggable,
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
  Offset _position = Offset.zero;
  bool _isInitialized = false;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final size = MediaQuery.of(context).size;
      // 仅非自适应高度模式需要预计算居中位置（绝对坐标）
      // 自适应高度模式使用 Center + Transform.translate，初始偏移为零即可实现居中
      // 锚定顶部模式下使用 Positioned 绝对定位，需要预计算居中位置
      if (!widget.adaptiveHeight || widget.anchorTop) {
        _position = Offset(
          (size.width - widget.width) / 2,
          (size.height - widget.height) / 2,
        );
      }
      _isInitialized = true;
    }
  }

  /// 获取当前是否可拖拽
  bool get _isDraggable {
    if (widget.dialogInteractiveNotifier != null) {
      return widget.dialogInteractiveNotifier!.value;
    }
    return widget.draggable;
  }

  @override
  Widget build(BuildContext context) {
    final dialogContent = Container(
      width: widget.width,
      height: widget.adaptiveHeight ? null : widget.height,
      constraints: widget.adaptiveHeight ? BoxConstraints(maxHeight: widget.height) : null,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
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
                      style: context.titleLarge?.copyWith(
                        fontSize: widget.titleFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.showCloseButton)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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
          Flexible(
            child: Material(
              color: Colors.transparent,
              child: widget.content,
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: _isDraggable,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 自适应高度 + 锚定顶部模式：使用 Positioned 绝对定位，高度变化时顶部位置不变
          if (widget.adaptiveHeight && widget.anchorTop)
            Positioned(
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                onPanUpdate: _isDraggable
                    ? (details) {
                        setState(() {
                          _position += details.delta;
                        });
                      }
                    : null,
                child: dialogContent,
              ),
            )
          // 自适应高度模式：使用 Center + Transform.translate 实现垂直居中
          // 初始偏移为零（自然居中），拖拽时累加偏移量
          else if (widget.adaptiveHeight)
            Center(
              child: Transform.translate(
                offset: _position,
                child: GestureDetector(
                  onPanUpdate: _isDraggable
                      ? (details) {
                          setState(() {
                            _position += details.delta;
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
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                onPanUpdate: _isDraggable
                    ? (details) {
                        setState(() {
                          _position += details.delta;
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
    height: subtitle != null ? 200 : 180,
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
              decoration: InputDecoration(
                hintText: widget.hintText,
                errorText: _errorMessage,
              ),
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
                padding: const EdgeInsets.fromLTRB(6,12,0,0),
                child: Text(
                  widget.subtitle!,
                  style: context.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: _isLoading ? null : _handleConfirm,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.confirmText,textAlign: TextAlign.center,),
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
Future<void> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String description,
  ConfirmType type = ConfirmType.info,
  String confirmText = '确定',
  String? cancelText,
  IconData? icon,
  VoidCallback? onConfirm,
}) {
  return showDialogBase(
    context: context,
    title: '',
    width: 420,
    height: 300,
    showCloseButton: false,
    adaptiveHeight: true,
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
            decoration: BoxDecoration(
              color: _getIconBackgroundColor(colorScheme),
              shape: BoxShape.circle,
            ),
            child: Icon(_getIcon(), size: 24, color: _getIconColor(colorScheme)),
          ),
          const SizedBox(height: 16),
          // 标题
          Text(
            title,
            style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          // 描述
          Text(
            description,
            textAlign: TextAlign.center,
            style: context.bodyLarge?.copyWith(
              height: 1.5,
              color: colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 20),
          // 按钮
          cancelText != null
              ? Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
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
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(cancelText!),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
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
            child: Icon(
              Icons.warning_amber_outlined,
              size: 24,
              color: colorScheme.tertiary,
            ),
          ),
          const SizedBox(height: 16),
          // 标题
          Text(
            title,
            style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          // 描述
          Text(
            description,
            textAlign: TextAlign.center,
            style: context.bodyLarge?.copyWith(
              height: 1.5,
              color: colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 20),
          // 三按钮组：保存 / 不保存 / 取消
          Row(
            children: [
              // 保存按钮（主操作，填充色突出）
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(UnsavedConfirmResult.save),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(saveText),
                ),
              ),
              const SizedBox(width: 8),
              // 不保存按钮（中性样式，提示会丢失修改）
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(UnsavedConfirmResult.discard),
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
                  onPressed: () =>
                      Navigator.of(context).pop(UnsavedConfirmResult.cancel),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
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

  const SelectItem({
    required this.label,
    required this.value,
    this.icon,
    this.disabled = false,
    this.selected = false,
  });
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
                            color: item.disabled
                                ? colorScheme.onSurface.withValues(alpha: 0.3)
                                : colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        if (item.selected)
                          Icon(
                            Icons.check,
                            size: 20,
                            color: colorScheme.primary,
                          ),
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
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
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
void Function() showLoadingDialog({
  required BuildContext context,
  required String message,
}) {
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
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 转圈加载动画
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            // 提示文字
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
