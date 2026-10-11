import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import '../utils/shortcut_catalog.dart';
import 'shortcut_entry_tile.dart';

/// 大纲编辑器快捷键列表面板
///
/// 浮动在编辑器右侧的快捷键查阅面板，按功能分组展示全部快捷键。
/// 面板以侧边栏样式呈现：贴右、近全高、左侧投影，作为浮层覆盖在编辑器之上，
/// 不挤压左侧编辑器宽度，也不随内容滚动。
class OutlineShortcutPanel extends StatelessWidget {
  /// 颜色方案
  final ColorScheme colorScheme;

  /// 关闭面板回调
  final VoidCallback onClose;

  const OutlineShortcutPanel({
    super.key,
    required this.colorScheme,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      // 左侧分隔线与投影，营造浮层侧边栏的视觉层次
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildGroupList()),
        ],
      ),
    );
  }

  /// 构建面板头部：图标、标题与关闭按钮
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.keyboard_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('快捷键', style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          _buildCloseButton(),
        ],
      ),
    );
  }

  /// 构建关闭按钮
  Widget _buildCloseButton() {
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onClose,
          borderRadius: BorderRadius.circular(6),
          hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
          child: Icon(Icons.close_rounded, size: 16, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// 构建分组列表
  Widget _buildGroupList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: outlineEditorShortcutGroups.length,
      itemBuilder: (context, index) => _buildGroup(context, outlineEditorShortcutGroups[index]),
    );
  }

  /// 构建单个分组：标题 + 卡片化的条目列表
  Widget _buildGroup(BuildContext context, ShortcutGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              group.title,
              style: context.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < group.entries.length; i++) ...[
                  ShortcutEntryTile(entry: group.entries[i]),
                  if (i < group.entries.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
