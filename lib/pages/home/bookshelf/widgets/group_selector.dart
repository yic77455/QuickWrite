import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/group.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/dialogs/group_manage_dialog.dart';
import 'package:quick_write/shared/dialogs/new_group_dialog.dart';

/// 分组选择器组件
///
/// 显示当前选中的分组名称，点击可展开下拉菜单切换分组
/// 支持新建分组和管理分组功能
///
/// 分组 ID 约定：
/// - 空字符串 '' 表示"书架（未分组）"，即未分组的书籍
/// - '__all__' 表示"全部作品"
/// - 其他为用户创建的分组的 UUID
class GroupSelector extends StatelessWidget {
  /// 当前选中的分组 UUID
  /// - 空字符串 '' 表示"书架（未分组）"
  /// - '__all__' 表示"全部作品"
  /// - 其他为分组 UUID
  final String selectedGroupId;

  /// 分组切换回调
  final ValueChanged<String> onGroupChanged;

  const GroupSelector({
    super.key,
    required this.selectedGroupId,
    required this.onGroupChanged,
  });

  /// 获取显示名称
  String _getDisplayName(BookshelfProvider provider) {
    if (selectedGroupId.isEmpty) {
      return '书架';
    } else if (selectedGroupId == '__all__') {
      return '全部作品';
    } else {
      final group = provider.getGroupByUuid(selectedGroupId);
      return group?.name ?? '书架';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BookshelfProvider>(
      builder: (context, provider, child) {
        final groups = provider.groups;
        final displayName = _getDisplayName(provider);

        return MenuAnchor(
          alignmentOffset: const Offset(0, 8),
          style: MenuStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            elevation: WidgetStateProperty.all(8),
            minimumSize: WidgetStateProperty.all(const Size(200, 0)),
          ),
          menuChildren: _buildMenuChildren(context, groups),
          builder: (context, controller, child) {
            return InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: context.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more,
                      size: 24,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 构建菜单子项
  List<Widget> _buildMenuChildren(
    BuildContext context,
    List<GroupModel> groups,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[];

    // 书架（未分组）- 默认选项
    children.add(
      _buildMenuItem(
        context: context,
        label: '书架',
        icon: Icons.shelves,
        isSelected: selectedGroupId.isEmpty,
        onTap: () => onGroupChanged(''),
      ),
    );

    // 用户创建的分组
    for (final group in groups) {
      children.add(
        _buildMenuItem(
          context: context,
          label: group.name,
          icon: Icons.folder_outlined,
          isSelected: selectedGroupId == group.uuid,
          onTap: () => onGroupChanged(group.uuid),
        ),
      );
    }

    // 分隔线
    children.add(
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Divider(height: 1),
      ),
    );

    // 全部作品
    children.add(
      _buildMenuItem(
        context: context,
        label: '全部作品',
        icon: Icons.apps,
        isSelected: selectedGroupId == '__all__',
        onTap: () => onGroupChanged('__all__'),
      ),
    );

    // 分隔线
    children.add(
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Divider(height: 1),
      ),
    );

    // 新建分组
    children.add(
      _buildMenuItem(
        context: context,
        label: '新建分组',
        icon: Icons.add,
        color: colorScheme.primary,
        onTap: () => showNewGroupDialog(context: context),
      ),
    );

    // 管理分组
    children.add(
      _buildMenuItem(
        context: context,
        label: '管理分组',
        icon: Icons.settings_outlined,
        onTap: () => showGroupManageDialog(context),
      ),
    );

    return children;
  }

  /// 构建单个菜单项
  Widget _buildMenuItem({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isSelected = false,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = color ?? colorScheme.onSurface;

    return MenuItemButton(
      style: MenuItemButton.styleFrom(minimumSize: const Size(200, 60)),
      leadingIcon: Icon(icon, size: 20, color: textColor),
      trailingIcon: isSelected
          ? Icon(Icons.check, size: 18, color: colorScheme.primary)
          : null,
      onPressed: onTap,
      child: Text(label, style: context.bodyMedium?.copyWith(color: textColor)),
    );
  }
}
