import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import '../../editor/utils/shortcut_catalog.dart';
import '../../editor/widgets/shortcut_entry_tile.dart';
import 'right_sidebar_widgets.dart';

/// 显示快捷键列表对话框
///
/// 左右两列分别展示正文编辑器与大纲编辑器的快捷键，两列各自独立滚动。
Future<void> showShortcutDialog({required BuildContext context}) {
  return showDialogBase(
    context: context,
    title: '快捷键',
    width: 680,
    height: 500,
    content: const _ShortcutDialogContent(),
  );
}

/// 快捷键列表对话框内容
///
/// 左列为扁平列表的正文编辑器快捷键，右列为按功能分组的大纲编辑器快捷键。
class _ShortcutDialogContent extends StatelessWidget {
  const _ShortcutDialogContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左列：正文编辑器快捷键
          Expanded(
            child: _buildColumn(
              context,
              title: '正文编辑器',
              icon: Icons.edit_note_rounded,
              list: SingleChildScrollView(child: _buildEntryCard(context, bodyEditorShortcuts)),
            ),
          ),
          const SizedBox(width: 16),
          // 右列：大纲编辑器快捷键
          Expanded(
            child: _buildColumn(
              context,
              title: '大纲编辑器',
              icon: Icons.account_tree_outlined,
              list: _buildOutlineList(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个编辑器列：列标题 + 撑满剩余高度的快捷键列表
  Widget _buildColumn(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget list,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: list),
      ],
    );
  }

  /// 构建正文编辑器条目卡片
  Widget _buildEntryCard(BuildContext context, List<ShortcutEntry> entries) {
    return _buildCard(context, [
      for (int i = 0; i < entries.length; i++) ...[
        ShortcutEntryTile(entry: entries[i]),
        if (i < entries.length - 1) const SettingDivider(),
      ],
    ]);
  }

  /// 构建大纲编辑器分组列表：按功能分组，每组标题 + 卡片化的条目
  Widget _buildOutlineList(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in outlineEditorShortcutGroups)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 分组标题
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      group.title,
                      style: context.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildEntryCard(context, group.entries),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 构建条目卡片容器（圆角背景 + 边框）
  Widget _buildCard(BuildContext context, List<Widget> children) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(children: children),
    );
  }
}
