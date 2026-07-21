import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 查找替换栏
///
/// 浮动在编辑器左上角的查找替换面板，支持查找导航、替换、大小写敏感、正则匹配等功能
class FindReplaceBar extends StatefulWidget {
  /// 查找文本变化回调
  final ValueChanged<String>? onFindTextChanged;

  /// 查找下一个回调
  final VoidCallback? onFindNext;

  /// 查找上一个回调
  final VoidCallback? onFindPrevious;

  /// 替换当前回调
  final VoidCallback? onReplaceCurrent;

  /// 替换全部回调
  final VoidCallback? onReplaceAll;

  /// 替换文本变化回调
  final ValueChanged<String>? onReplaceTextChanged;

  /// 关闭回调
  final VoidCallback? onClose;

  /// 大小写敏感切换回调
  final ValueChanged<bool>? onCaseSensitiveChanged;

  /// 替换区域显示状态变化回调
  final ValueChanged<bool>? onShowReplaceChanged;

  /// 当前匹配索引（从1开始，0表示无匹配）
  final int currentMatchIndex;

  /// 总匹配数
  final int totalMatchCount;

  /// 是否显示替换区域
  final bool showReplace;

  /// 是否大小写敏感
  final bool caseSensitive;

  /// 是否支持替换功能（只读标签页不支持替换）
  final bool canReplace;

  /// 查找输入框初始文本
  final String initialFindText;

  /// 替换输入框初始文本
  final String initialReplaceText;

  /// 查找替换栏
  ///
  /// 浮动在编辑器左上角的查找替换面板，支持查找导航、替换、大小写敏感、正则匹配等功能
  const FindReplaceBar({
    super.key,
    this.onFindTextChanged,
    this.onFindNext,
    this.onFindPrevious,
    this.onReplaceCurrent,
    this.onReplaceAll,
    this.onReplaceTextChanged,
    this.onClose,
    this.onCaseSensitiveChanged,
    this.onShowReplaceChanged,
    this.currentMatchIndex = 0,
    this.totalMatchCount = 0,
    this.showReplace = false,
    this.caseSensitive = false,
    this.canReplace = true,
    this.initialFindText = '',
    this.initialReplaceText = '',
  });

  @override
  State<FindReplaceBar> createState() => FindReplaceBarState();
}

class FindReplaceBarState extends State<FindReplaceBar> {
  /// 查找输入控制器
  late final TextEditingController _findController;

  /// 替换输入控制器
  late final TextEditingController _replaceController;

  /// 查找输入框焦点节点
  final FocusNode _findFocusNode = FocusNode();

  /// 替换输入框焦点节点
  final FocusNode _replaceFocusNode = FocusNode();

  /// 是否显示替换区域
  bool _showReplace = false;

  /// 是否大小写敏感
  bool _caseSensitive = false;

  @override
  void initState() {
    super.initState();
    _findController = TextEditingController(text: widget.initialFindText);
    _replaceController = TextEditingController(text: widget.initialReplaceText);
    _showReplace = widget.showReplace;
    _caseSensitive = widget.caseSensitive;

    // 自动聚焦查找输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _findFocusNode.requestFocus();
        // 选中所有文本，方便用户直接输入替换
        _findController.selection = TextSelection(baseOffset: 0, extentOffset: _findController.text.length);
      }
    });
  }

  @override
  void didUpdateWidget(FindReplaceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同步外部状态变化（如 Ctrl+H 展开替换区域）
    if (widget.showReplace != oldWidget.showReplace) {
      _showReplace = widget.showReplace;
    }
    if (widget.caseSensitive != oldWidget.caseSensitive) {
      _caseSensitive = widget.caseSensitive;
    }
    // 同步查找文本变化（如从编辑器选中区域自动填入）
    if (widget.initialFindText != oldWidget.initialFindText && widget.initialFindText != _findController.text) {
      _findController.text = widget.initialFindText;
      _findController.selection = TextSelection.collapsed(offset: widget.initialFindText.length);
    }
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    _replaceFocusNode.dispose();
    super.dispose();
  }

  /// 获取当前查找文本
  String get findText => _findController.text;

  /// 获取当前替换文本
  String get replaceText => _replaceController.text;

  /// 请求聚焦查找输入框
  void requestFindFocus() {
    _findFocusNode.requestFocus();
    _findController.selection = TextSelection.collapsed(offset: _findController.text.length);
  }

  /// 设置查找文本（外部调用，如选中文字后打开查找替换）
  void setFindText(String text) {
    _findController.text = text;
    _findController.selection = TextSelection.collapsed(offset: text.length);
  }

  /// 切换替换区域显示
  void _toggleReplace() {
    setState(() {
      _showReplace = !_showReplace;
    });
    widget.onShowReplaceChanged?.call(_showReplace);
  }

  /// 切换大小写敏感
  void _toggleCaseSensitive() {
    setState(() {
      _caseSensitive = !_caseSensitive;
    });
    widget.onCaseSensitiveChanged?.call(_caseSensitive);
  }

  /// 构建匹配计数文本
  String _buildMatchCountText() {
    if (widget.totalMatchCount == 0 || _findController.text.isEmpty) return '无结果';
    if (widget.currentMatchIndex == 0) return '?/${widget.totalMatchCount}';
    return '${widget.currentMatchIndex}/${widget.totalMatchCount}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 390,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(
          left: BorderSide(color: colorScheme.surface, width: 4),
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1),
          right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(2, 2))],
      ),
      child: CallbackShortcuts(
        bindings: {
          // Escape：关闭查找替换栏
          const SingleActivator(LogicalKeyboardKey.escape): () {
            widget.onClose?.call();
          },
          // Ctrl+H / Cmd+H：切换替换区域展开/收起
          const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
            _toggleReplace();
          },
          const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
            _toggleReplace();
          },
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 查找行
            _buildFindRow(context, colorScheme),
            // 替换行（可展开/收起）
            if (_showReplace) _buildReplaceRow(context, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 构建查找行
  Widget _buildFindRow(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
      child: Row(
        children: [
          // 替换区域展开按钮（不支持替换时隐藏）
          if (widget.canReplace)
            _buildIconButton(
              icon: _showReplace ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              tooltip: _showReplace ? '收起替换' : '展开替换',
              onPressed: _toggleReplace,
              colorScheme: colorScheme,
            ),
          const SizedBox(width: 4),
          // 查找输入框
          Flexible(child: _buildFindInputField(colorScheme)),
          const SizedBox(width: 4),
          // 匹配计数
          _buildMatchCountWidget(colorScheme),
          const SizedBox(width: 4),
          // 查找上一个
          _buildIconButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: '上一个 (Shift+Enter)',
            onPressed: widget.onFindPrevious,
            colorScheme: colorScheme,
          ),
          // 查找下一个
          _buildIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: '下一个 (Enter)',
            onPressed: widget.onFindNext,
            colorScheme: colorScheme,
          ),
          // 关闭按钮
          _buildIconButton(
            icon: Icons.close_rounded,
            tooltip: '关闭 (Escape)',
            onPressed: widget.onClose,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  /// 构建替换行
  Widget _buildReplaceRow(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
      child: Row(
        children: [
          // 占位，与查找行对齐
          const SizedBox(width: 28),
          // 替换输入框
          Flexible(
            child: _buildInputField(
              controller: _replaceController,
              focusNode: _replaceFocusNode,
              hint: '替换',
              colorScheme: colorScheme,
              onChanged: (value) {
                widget.onReplaceTextChanged?.call(value);
              },
            ),
          ),
          const SizedBox(width: 4),
          // 替换当前
          _buildIconButton(
            icon: Icons.find_replace_rounded,
            tooltip: '替换',
            onPressed: widget.onReplaceCurrent,
            colorScheme: colorScheme,
          ),
          // 替换全部
          _buildIconButton(
            icon: Icons.find_replace_outlined,
            tooltip: '替换全部',
            onPressed: widget.onReplaceAll,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  /// 构建输入框
  Widget _buildInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required ColorScheme colorScheme,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    Widget? suffixWidget,
  }) {
    return ImeCursorFixerWrapper(
      controller: controller,
      focusNode: focusNode,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: context.bodySmall?.copyWith(color: colorScheme.onSurface),
        decoration: InputDecoration(
          isDense: true,
          constraints: const BoxConstraints.tightFor(width: 210, height: 32),
          contentPadding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          hintText: hint,
          hintStyle: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          filled: true,
          fillColor: colorScheme.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: colorScheme.primary, width: 1),
          ),
          suffixIcon: suffixWidget,
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }

  /// 构建查找输入框（内嵌大小写按钮）
  Widget _buildFindInputField(ColorScheme colorScheme) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          if (isShift) {
            widget.onFindPrevious?.call();
          } else {
            widget.onFindNext?.call();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _buildInputField(
        controller: _findController,
        focusNode: _findFocusNode,
        hint: '查找',
        colorScheme: colorScheme,
        onChanged: (value) {
          widget.onFindTextChanged?.call(value);
        },
        suffixWidget: _buildCaseSensitiveButton(colorScheme),
      ),
    );
  }

  /// 构建文本框外部的匹配计数组件
  Widget _buildMatchCountWidget(ColorScheme colorScheme) {
    final text = _buildMatchCountText();
    final hasResult = widget.totalMatchCount > 0 && _findController.text.isNotEmpty;
    final alpha = hasResult ? 1.0 : 0.7;
    return SizedBox(
      width: 48,
      child: Center(
        child: Text(text, style: context.bodySmall?.copyWith(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: alpha))),
      ),
    );
  }

  /// 构建文本框内嵌的大小写敏感按钮
  Widget _buildCaseSensitiveButton(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
          tooltip: '区分大小写',
          onPressed: _toggleCaseSensitive,
          icon: Icon(Icons.text_fields_rounded, size: 14),
          padding: EdgeInsets.zero,
          color: _caseSensitive ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          style: IconButton.styleFrom(
            backgroundColor: _caseSensitive ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
          ),
          hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
          highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
        ),
      ),
    );
  }

  /// 构建普通图标按钮
  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
  }) {
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        padding: EdgeInsets.zero,
        color: colorScheme.onSurfaceVariant,
        hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
        highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
      ),
    );
  }
}
