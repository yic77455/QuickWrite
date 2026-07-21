import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 目录顶部操作栏
///
/// 包含添加、排序、收起侧边栏、更多操作等按钮
/// 支持普通模式和批量管理模式
class ContentsTopBar extends StatefulWidget {
  /// 是否处于批量管理模式
  final bool isBatchMode;

  /// 是否全选
  final bool isAllSelected;

  /// 全选/取消全选回调
  final VoidCallback onToggleSelectAll;

  /// 退出批量管理模式回调
  final VoidCallback onExitBatchMode;

  /// 添加按钮提示文本
  final String addTooltip;

  /// 添加按钮回调
  final VoidCallback onAdd;

  /// 是否倒序排列
  final bool isReversed;

  /// 切换排序回调
  final VoidCallback onToggleReversed;

  /// 收起侧边栏回调
  final VoidCallback onToggleSidebar;

  /// 更多菜单选项选中回调
  final void Function(String value) onMenuAction;

  /// 自定义菜单项（为空则使用默认的"批量操作"菜单项）
  final List<PopupMenuEntry<String>>? menuItems;

  const ContentsTopBar({
    required this.isBatchMode,
    required this.isAllSelected,
    required this.onToggleSelectAll,
    required this.onExitBatchMode,
    required this.addTooltip,
    required this.onAdd,
    required this.isReversed,
    required this.onToggleReversed,
    required this.onToggleSidebar,
    required this.onMenuAction,
    this.menuItems,
    super.key,
  });

  @override
  State<ContentsTopBar> createState() => _ContentsTopBarState();
}

class _ContentsTopBarState extends State<ContentsTopBar> {
  /// 更多操作按钮的 GlobalKey，用于定位下拉菜单
  final GlobalKey _moreButtonKey = GlobalKey();

  /// 顶部更多操作菜单是否打开
  bool _isTopMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 批量模式下的顶部栏
    if (widget.isBatchMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            // 全选按钮
            GestureDetector(
              onTap: widget.onToggleSelectAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      onPressed: widget.onToggleSelectAll,
                      icon: Icon(
                        widget.isAllSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 16,
                        color: widget.isAllSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 14,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    widget.isAllSelected ? '取消全选' : '全选',
                    style: context.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SmallToolbarButton(
              icon: Icons.close_rounded,
              tooltip: '退出批量管理',
              onPressed: widget.onExitBatchMode,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // 左侧按钮组：添加、排序
          SmallToolbarButton(
            icon: Icons.add_rounded,
            tooltip: widget.addTooltip,
            onPressed: widget.onAdd,
          ),
          const SizedBox(width: 4),
          SmallToolbarButton(
            icon: Icons.sort_rounded,
            tooltip: '正序/倒序',
            onPressed: widget.onToggleReversed,
          ),
          // 弹性空间，将右侧按钮推到最右边
          const Spacer(),
          // 收起侧边栏按钮
          SmallToolbarButton(
            icon: Icons.chevron_left_rounded,
            tooltip: '收起侧边栏',
            onPressed: widget.onToggleSidebar,
          ),
          const SizedBox(width: 4),
          // 右侧按钮：更多操作
          SmallToolbarButton(
            key: _moreButtonKey,
            icon: Icons.more_horiz_rounded,
            tooltip: '更多',
            isMenuOpen: _isTopMenuOpen,
            onPressed: () => _showMoreMenu(context),
          ),
        ],
      ),
    );
  }

  /// 显示更多操作菜单
  void _showMoreMenu(BuildContext context) {
    // 获取更多操作按钮的位置信息
    final RenderBox? button = _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;

    final Offset offset = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    // 标记菜单打开，按钮保持按下状态
    setState(() {
      _isTopMenuOpen = true;
    });

    // 使用自定义菜单项或默认菜单项
    final menuItems = widget.menuItems ?? [
      const PopupMenuItem<String>(
        value: 'batch',
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('批量操作'),
      ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + buttonSize.width - 120,
        offset.dy + buttonSize.height + 4,
        offset.dx + buttonSize.width,
        offset.dy + buttonSize.height,
      ),
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      // 设置菜单内边距以缩小选项与上下边界的间距
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      items: menuItems,
    ).then((value) {
      // 菜单关闭，清除按下状态
      if (mounted) {
        setState(() {
          _isTopMenuOpen = false;
        });
      }
      if (!context.mounted) return;
      if (value != null) {
        widget.onMenuAction(value);
      }
    });
  }
}
