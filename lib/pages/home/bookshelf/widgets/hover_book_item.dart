import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/shared/dialogs/book_detail_dialog.dart';
import 'package:quick_write/shared/dialogs/export_dialog.dart';
import 'package:quick_write/shared/dialogs/new_book_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'workspace_opener.dart';

/// 带悬停动画的小封面组件
/// 
/// 用于右侧网格中的书籍卡片，悬停时有放大和阴影效果
/// 支持批量操作模式下的选中状态
class HoverBookItem extends StatefulWidget {
  final BookModel book;
  final VoidCallback onTap;
  // 是否被选中（批量模式下使用）
  final bool isSelected;
  // 是否处于批量模式
  final bool isBatchMode;
  // 当前选中的分组 ID（用于移动到分组时禁用当前分组）
  final String currentGroupId;
  // 选中状态变化回调（批量模式下使用）
  final VoidCallback? onToggleSelection;
  // 批量删除回调（批量模式下使用）
  final VoidCallback? onBatchDelete;
  // 批量导出回调（批量模式下使用）
  final VoidCallback? onBatchExport;
  // 移动到分组回调（批量模式下使用）
  final void Function(String groupUuid)? onMoveToGroup;

  const HoverBookItem({
    super.key,
    required this.book,
    required this.onTap,
    this.isSelected = false,
    this.isBatchMode = false,
    this.currentGroupId = '',
    this.onToggleSelection,
    this.onBatchDelete,
    this.onBatchExport,
    this.onMoveToGroup,
  });

  @override
  State<HoverBookItem> createState() => _HoverBookItemState();
}

class _HoverBookItemState extends State<HoverBookItem> {
  bool _isHovered = false;

  /// 构建默认封面（无封面或加载失败时显示）
  Widget _buildDefaultCover() {
    return DefaultCover.buildThemed(
      title: widget.book.title,
      context: context,
      fontSize: 18,
      borderRadius: 0,
    );
  }

  /// 构建书籍右键菜单项
  List<ContextMenuItem> _buildMenuItems() {
    // 获取分组列表
    final groups = context.read<BookshelfProvider>().groups;

    // 批量模式下的菜单
    if (widget.isBatchMode) {
      // 已选中：显示取消选择和其他操作
      if (widget.isSelected) {
        return [
          ContextMenuItem(
            labelText: '取消选择',
            icon: Icons.check_box_outline_blank,
            onTap: widget.onToggleSelection,
          ),
          ContextMenuItem.divider(),
          ContextMenuItem(
            labelText: '移动到',
            icon: Icons.folder_outlined,
            children: _buildGroupMenuItems(groups, enabled: true),
          ),
          ContextMenuItem(
            labelText: '导出',
            icon: Icons.upload,
            onTap: widget.onBatchExport,
          ),
          ContextMenuItem.divider(),
          ContextMenuItem(
            labelText: '删除',
            icon: Icons.delete_outline,
            labelColor: const Color.fromARGB(255, 224, 52, 40),
            onTap: widget.onBatchDelete,
          ),
        ];
      }
      
      // 未选中：只显示选择
      return [
        ContextMenuItem(
          labelText: '选择',
          icon: Icons.check_box_outline_blank,
          onTap: widget.onToggleSelection,
        ),
        ContextMenuItem.divider(),
        ContextMenuItem(
          labelText: '移动到',
          icon: Icons.folder_outlined,
          enabled: false,
          children: _buildGroupMenuItems(groups, enabled: false),
        ),
        ContextMenuItem(
          labelText: '导出',
          icon: Icons.upload,
          enabled: false,
          onTap: () {},
        ),
        ContextMenuItem.divider(),
        ContextMenuItem(
          labelText: '删除',
          icon: Icons.delete_outline,
          enabled: false,
          onTap: () {},
        ),
      ];
    }

    // 普通模式下的菜单
    return [
      ContextMenuItem(
        labelText: '打开',
        icon: Icons.open_in_new,
        onTap: () => openWorkspace(context: context, bookId: widget.book.uuid, bookTitle: widget.book.title),
      ),
      ContextMenuItem(
        labelText: '详情',
        icon: Icons.info_outline,
        onTap: () => showBookDetailDialog(context: context, book: widget.book),
      ),
      ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '修改信息',
        icon: Icons.edit,
        onTap: () => showEditBookDialog(context, widget.book),
      ),
      ContextMenuItem(
        labelText: '移动到',
        icon: Icons.folder_outlined,
        children: _buildGroupMenuItems(groups, enabled: true, isSingleBook: true),
      ),
      ContextMenuItem(
        labelText: '导出',
        icon: Icons.upload,
        onTap: () {
          showExportDialog(context: context, books: [widget.book]);
        },
      ),
      ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '删除',
        icon: Icons.delete_outline,
        labelColor: const Color.fromARGB(255, 224, 52, 40),
        onTap: () => _showDeleteConfirmDialog(),
      ),
    ];
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog() {
    // 检查书籍是否在工作台打开
    final isOpenedInWorkspace = MultiWindowService.instance.isWorkspaceWindowOpen(widget.book.uuid);

    if (isOpenedInWorkspace) {
      // 如果书籍已打开，显示提示对话框
      showConfirmDialog(
        context: context,
        title: '无法删除',
        description: '书籍「${widget.book.title}」正在工作台打开中，\n请先关闭工作台窗口后再进行删除操作。',
        type: ConfirmType.warning,
        confirmText: '我知道了',
        icon: Icons.edit_document,
      );
    } else {
      // 如果书籍未打开，显示删除确认对话框
      showConfirmDialog(
        context: context,
        title: '删除书籍',
        description: '书籍「${widget.book.title}」将被移入回收站，\n你可以在回收站中恢复或彻底删除。',
        type: ConfirmType.delete,
        confirmText: '删除',
        cancelText: '取消',
        onConfirm: () {
          context.read<BookshelfProvider>().deleteBook(widget.book);
          // 显示删除成功提示
          SnackBarService.show(context, '作品已移入回收站');
        },
      );
    }
  }

  /// 构建分组菜单项
  List<ContextMenuItem> _buildGroupMenuItems(
    dynamic groups, {
    required bool enabled,
    bool isSingleBook = false,
  }) {
    final items = <ContextMenuItem>[];

    // 判断书籍当前所属分组
    final bookCurrentGroupId = widget.book.groupId;

    // "书架"选项 - 如果书籍当前就在书架，则禁用此选项
    final isInUngrouped = bookCurrentGroupId.isEmpty;
    items.add(ContextMenuItem(
      labelText: '书架',
      enabled: enabled && !isInUngrouped,
      onTap: enabled && !isInUngrouped
          ? () {
              if (isSingleBook) {
                context.read<BookshelfProvider>().moveBooksToGroup(
                  [widget.book.uuid],
                  '',
                );
                // 显示移动成功提示
                SnackBarService.show(context, '已将作品移动到书架');
              } else {
                widget.onMoveToGroup?.call('');
              }
            }
          : null,
    ));

    // 用户创建的分组
    for (final group in groups) {
      // 如果书籍当前就在该分组，则禁用此选项
      final isInThisGroup = bookCurrentGroupId == group.uuid;
      items.add(ContextMenuItem(
        labelText: group.name,
        enabled: enabled && !isInThisGroup,
        onTap: enabled && !isInThisGroup
            ? () {
                if (isSingleBook) {
                  context.read<BookshelfProvider>().moveBooksToGroup(
                    [widget.book.uuid],
                    group.uuid,
                  );
                  // 显示移动成功提示
                  SnackBarService.show(context, '已将作品移动到「${group.name}」');
                } else {
                  widget.onMoveToGroup?.call(group.uuid);
                }
              }
            : null,
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = _buildMenuItems();
    final colorScheme = Theme.of(context).colorScheme;

    // 封面区域（含右键菜单）
    // 封面高度 = 160 * 4 / 3 ≈ 213.33
    final coverArea = ContextMenu(
      menuItems: menuItems,
      child: MouseRegion(
        // 批量模式下禁用悬停效果
        onEnter: widget.isBatchMode ? null : (_) => setState(() => _isHovered = true),
        onExit: widget.isBatchMode ? null : (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            // 批量模式下不显示悬停动画；普通模式下显示悬停效果
            transform: (!widget.isBatchMode && _isHovered)
                ? (Matrix4.identity()
                    ..scaleByDouble(1.02, 1.02, 1.0, 1.0)
                    ..setTranslationRaw(-1.5, -4.0, 0.0))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              // 选中状态：显示蓝色边框
              border: widget.isSelected
                  ? Border.all(color: colorScheme.primary, width: 2)
                  : null,
              boxShadow: widget.isBatchMode
                  ? [
                      // 批量模式下只显示轻微阴影
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // 封面图片
                AspectRatio(
                  // 宽:高 = 3 : 4
                  aspectRatio: 3 / 4,
                  child: widget.book.coverPath.isNotEmpty
                      ? ThemedCoverImage(
                          coverPath: widget.book.coverPath,
                          cacheKey: widget.book.updatedAt.millisecondsSinceEpoch.toString(),
                          errorBuilder: (context, error, stackTrace) =>
                              _buildDefaultCover(),
                        )
                      : _buildDefaultCover(),
                ),
                // 选中状态遮罩和勾选图标
                if (widget.isBatchMode)
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      color: widget.isSelected
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      child: Center(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: widget.isSelected ? 1.0 : 0.0,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // 书名区域（只有文字部分有交互，共享悬停状态）
    final titleArea = Center(
      child: ContextMenu(
        menuItems: menuItems,
        child: MouseRegion(
          onEnter: widget.isBatchMode ? null : (_) => setState(() => _isHovered = true),
          onExit: widget.isBatchMode ? null : (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: context.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                // 批量模式下：选中显示主色，未选中显示普通色
                // 普通模式下：悬停显示主色
                color: widget.isBatchMode
                    ? (widget.isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface)
                    : (_isHovered
                        ? colorScheme.primary
                        : colorScheme.onSurface),
                height: 1.4,
              ) ?? const TextStyle(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              child: Text(widget.book.title, textAlign: TextAlign.center, style: const TextStyle(letterSpacing: 0.5),),
            ),
          ),
        ),
      ),
    );

    return Center(
      child: SizedBox(
        // 小封面锁死 160 宽
        width: 160,
        height: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面：按照 4 : 3 (高:宽) 比例
            coverArea,

            const SizedBox(height: 12),

            // 书名：只有文字部分有交互
            titleArea,
          ],
        ),
      ),
    );
  }
}
