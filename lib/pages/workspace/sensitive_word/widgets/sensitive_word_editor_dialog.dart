import 'package:flutter/material.dart';
import 'package:quick_write/core/services/workspace/sensitive_word_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_text_field.dart';

/// 显示敏感词词库编辑弹窗
///
/// 弹窗内以多行文本承载全部词条，保存后写入书籍根目录并参与云同步。
/// 返回 true 表示词库已保存，用户取消时返回 false。
Future<bool> showSensitiveWordEditorDialog({
  required BuildContext context,
  required SensitiveWordService service,
}) async {
  final result = await showDialogBase<bool>(
    context: context,
    title: '编辑敏感词库',
    subtitle: '词条以换行、空格或逗号分隔',
    titleIcon: Icons.edit_note_rounded,
    width: 520,
    height: 620,
    content: _SensitiveWordEditorContent(service: service),
  );
  return result ?? false;
}

/// 敏感词词库编辑弹窗内容
class _SensitiveWordEditorContent extends StatefulWidget {
  /// 敏感词服务（用于读取与保存词库）
  final SensitiveWordService service;

  const _SensitiveWordEditorContent({required this.service});

  @override
  State<_SensitiveWordEditorContent> createState() =>
      _SensitiveWordEditorContentState();
}

class _SensitiveWordEditorContentState
    extends State<_SensitiveWordEditorContent> {
  /// 内容区左右留白
  static const double _horizontalPadding = 24;

  /// 词条输入控制器（以换行分隔现有词条）
  late final TextEditingController _controller;

  /// 词条输入框焦点节点
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.service.words.join('\n'));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 退出输入框焦点
  void _unfocus() => FocusScope.of(context).unfocus();

  /// 解析输入内容
  ///
  /// 支持以换行、空格、逗号、顿号分隔，自动去除空白并去重。
  List<String> _parseWords(String raw) {
    final tokens = raw.split(RegExp(r'[\s,，、]+'));
    final result = <String>[];
    for (final token in tokens) {
      final value = token.trim();
      if (value.isNotEmpty && !result.contains(value)) {
        result.add(value);
      }
    }
    return result;
  }

  /// 保存词库
  Future<void> _handleSave() async {
    final words = _parseWords(_controller.text);
    await widget.service.replaceAll(words);
    if (!mounted) return;
    Navigator.of(context).pop(true);
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
              padding: const EdgeInsets.symmetric(
                horizontal: _horizontalPadding,
              ),
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
                    hintText: '每行一个词条，也可用空格或逗号分隔',
                    hintStyle: context.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                    filled: true,
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
            padding: const EdgeInsets.fromLTRB(
              _horizontalPadding,
              12,
              _horizontalPadding,
              0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _handleSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                  ),
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
