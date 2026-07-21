import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/group.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示分组管理对话框
/// 
/// - 重命名分组
/// - 删除分组
Future<void> showGroupManageDialog(BuildContext context) {
  return showDialogBase(
    context: context,
    title: '管理分组',
    width: 420,
    height: 380,
    content: const _GroupManageContent(),
  );
}

/// 分组管理内容
class _GroupManageContent extends StatefulWidget {
  const _GroupManageContent();

  @override
  State<_GroupManageContent> createState() => _GroupManageContentState();
}

class _GroupManageContentState extends State<_GroupManageContent> {
  @override
  Widget build(BuildContext context) {
    final groups = context.watch<BookshelfProvider>().groups;

    if (groups.isEmpty) {
      return const Center(
        child: Text('暂无分组，请先创建一个分组'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        itemCount: groups.length,
        onReorder: (oldIndex, newIndex) => _onReorder(groups, oldIndex, newIndex),
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final animValue = Curves.easeInOut.transform(animation.value);
              final elevation = 1 + animValue * 8;
              return Material(
                elevation: elevation,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: child,
              );
            },
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final group = groups[index];
          return _GroupItem(
            key: ValueKey(group.uuid),
            group: group,
            index: index,
            onRename: () => _showRenameDialog(group),
            onDelete: () => _showDeleteConfirmDialog(group),
          );
        },
      ),
    );
  }

  /// 处理拖拽排序
  void _onReorder(List<GroupModel> groups, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final newGroups = List<GroupModel>.from(groups);
    final item = newGroups.removeAt(oldIndex);
    newGroups.insert(newIndex, item);
    context.read<BookshelfProvider>().reorderGroups(newGroups);
  }

  /// 显示重命名对话框
  void _showRenameDialog(GroupModel group) {
    showInputDialog(
      context: context,
      title: '重命名分组',
      hintText: '请输入分组名称',
      initialValue: group.name,
      confirmText: '确定',
      cancelText: '取消',
      onConfirm: (newName) async {
        if (newName == group.name) return null; // 名称未变
        final result = await context.read<BookshelfProvider>().renameGroup(
          groupUuid: group.uuid,
          newName: newName,
        );
        return result == 1 ? '分组名已存在' : null;
      },
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog(GroupModel group) {
    showConfirmDialog(
      context: context,
      title: '删除分组',
      description: '分组「${group.name}」将被删除，其中的书籍将移至书架。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      icon: Icons.folder_delete_outlined,
      onConfirm: () {
        context.read<BookshelfProvider>().deleteGroup(group.uuid);
        // 显示删除成功提示
        SnackBarService.show(context, '分组已删除');
      },
    );
  }
}

/// 分组列表项
class _GroupItem extends StatelessWidget {
  final GroupModel group;
  final int index;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _GroupItem({
    super.key,
    required this.group,
    required this.index,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 18, 8),
        child: Row(
          children: [
            // 拖拽手柄
            ReorderableDragStartListener(
              index: index,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.drag_handle,
                  size: 20,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 分组图标
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.folder_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            // 分组名称
            Expanded(
              child: Text(
                group.name,
                style: context.titleLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 操作按钮区域
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CursorTooltipTarget(
                  tooltipContent: const Text('重命名'),
                  child: IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    onPressed: onRename,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                ),
                CursorTooltipTarget(
                  tooltipContent: const Text('删除'),
                  child: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: colorScheme.error.withValues(alpha: 0.8),
                    ),
                    onPressed: onDelete,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
