import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_text_field.dart';

/// 显示快捷输入栏符号列表编辑弹窗
///
/// 弹窗内以多行文本承载符号列表，保存后立即作用于快捷输入栏、
/// 标点自动补全与成对符号回车跳出。
Future<void> showQuickInputSymbolsDialog({required BuildContext context}) async {
  await showDialogBase<void>(
    context: context,
    title: '编辑符号列表',
    subtitle: "一行一个符号，用单引号包裹；成对符号形如 '（', closing: '）'",
    titleIcon: Icons.format_quote_rounded,
    width: 520,
    height: 620,
    content: const _QuickInputSymbolsContent(),
  );
}

/// 符号列表编辑弹窗内容
class _QuickInputSymbolsContent extends StatefulWidget {
  const _QuickInputSymbolsContent();

  @override
  State<_QuickInputSymbolsContent> createState() => _QuickInputSymbolsContentState();
}

class _QuickInputSymbolsContentState extends State<_QuickInputSymbolsContent> {
  /// 内容区左右留白
  static const double _horizontalPadding = 24;

  /// 符号列表输入控制器
  late final TextEditingController _controller;

  /// 输入框焦点节点
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: SettingsService.instance.quickInputSymbolsText);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 退出输入框焦点
  void _unfocus() => FocusScope.of(context).unfocus();

  /// 用内置默认符号列表覆写输入内容
  ///
  /// 仅替换输入框文本，仍需点击保存后才会生效
  void _handleRestoreDefault() {
    final String text = PunctuationSymbols.formatSymbolList(PunctuationSymbols.quickInputKeys);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// 保存符号列表
  Future<void> _handleSave() async {
    await SettingsService.instance.updateQuickInputSymbolsText(_controller.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      // 仅保留上下留白，左右留白交由输入区与按钮行分别处理
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
              child: ImeCursorFixerWrapper(
                controller: _controller,
                focusNode: _focusNode,
                child: QwTextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onTapOutside: (_) => _unfocus(),
                  style: context.bodyMedium,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: "每行一个符号，例如：\n'，'\n'（', closing: '）'",
                    hintStyle: context.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 底部按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(_horizontalPadding, 12, _horizontalPadding, 0),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _handleRestoreDefault,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('恢复默认'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _handleSave,
                  style: FilledButton.styleFrom(backgroundColor: colorScheme.primary),
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
