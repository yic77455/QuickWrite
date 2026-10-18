import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
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
  // 卡片宽度
  final double width;
  // 卡片高度
  final double height;
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
    this.width = 160,
    this.height = 260,
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
      // 封面文字随卡片宽度等比缩放
      fontSize: 18 * widget.width / 160,
      borderRadius: 0,
    );
  }

  /// 构建书籍右键菜单项
  List<ContextMenuItem> _buildMenuItems() {
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
            children: buildMoveToGroupMenuItems(
              context,
              currentGroupId: widget.book.groupId,
              enabled: true,
              onSelect: (groupUuid, _) => widget.onMoveToGroup?.call(groupUuid),
            ),
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
          children: buildMoveToGroupMenuItems(
            context,
            currentGroupId: widget.book.groupId,
            enabled: false,
            onSelect: (groupUuid, _) => widget.onMoveToGroup?.call(groupUuid),
          ),
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
    return buildSingleBookMenuItems(context, widget.book);
  }

  @override
  Widget build(BuildContext context) {
    // 移动端批量模式下长按不再弹出菜单，卡片点击专用于切换选中状态
    final menuItems = PlatformCapabilities.isMobile && widget.isBatchMode
        ? const <ContextMenuItem>[]
        : _buildMenuItems();
    final colorScheme = Theme.of(context).colorScheme;
    // 封面固定存放在作品目录下，数据库只记录文件名，此处拼接出完整路径
    final coverPath = BookFolderService().coverFilePath(widget.book);

    // 封面区域（含右键菜单）
    // 封面高度由宽度按 3 : 4 的宽高比推算
    // 移动端长按菜单改由书架网格统一处理（长按抬起后原地松手才弹出），
    // 这里关闭内置长按识别器，避免与网格的拖动识别器抢占同一指针
    final coverArea = ContextMenu(
      menuItems: menuItems,
      enableMobileLongPress: false,
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
                  child: coverPath.isNotEmpty
                      ? ThemedCoverImage(
                          coverPath: coverPath,
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
        enableMobileLongPress: false,
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
        // 卡片尺寸由外层网格按可用宽度计算
        width: widget.width,
        height: widget.height,
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

/// 构建普通模式下单本书籍的菜单项
///
/// 桌面端右键菜单与移动端长按抬起后原地松手共用该菜单
List<ContextMenuItem> buildSingleBookMenuItems(
  BuildContext context,
  BookModel book,
) {
  return [
    ContextMenuItem(
      labelText: '打开',
      icon: Icons.open_in_new,
      onTap: () => openWorkspace(
        context: context,
        bookId: book.uuid,
        bookTitle: book.title,
      ),
    ),
    ContextMenuItem(
      labelText: '详情',
      icon: Icons.info_outline,
      onTap: () => showBookDetailDialog(context: context, book: book),
    ),
    ContextMenuItem.divider(),
    ContextMenuItem(
      labelText: '修改信息',
      icon: Icons.edit,
      onTap: () => showEditBookDialog(context, book),
    ),
    ContextMenuItem(
      labelText: '移动到',
      icon: Icons.folder_outlined,
      children: buildMoveToGroupMenuItems(
        context,
        currentGroupId: book.groupId,
        enabled: true,
        onSelect: (groupUuid, groupLabel) {
          context.read<BookshelfProvider>().moveBooksToGroup(
            [book.uuid],
            groupUuid,
          );
          // 显示移动成功提示
          SnackBarService.show(
            context,
            groupUuid.isEmpty ? '已将作品移动到书架' : '已将作品移动到「$groupLabel」',
          );
        },
      ),
    ),
    ContextMenuItem(
      labelText: '导出',
      icon: Icons.upload,
      onTap: () => showExportDialog(context: context, books: [book]),
    ),
    ContextMenuItem.divider(),
    ContextMenuItem(
      labelText: '删除',
      icon: Icons.delete_outline,
      labelColor: const Color.fromARGB(255, 224, 52, 40),
      onTap: () => showDeleteBookConfirmDialog(context, book),
    ),
  ];
}

/// 构建「移动到」子菜单项
///
/// 同时服务单本书籍与批量选择两种场景，具体移动行为由 [onSelect] 决定；
/// 回调参数依次为分组 ID 与分组名称（"书架"对应空 ID）。
/// [currentGroupId] 为书籍当前所属分组，用于禁用无效选项
List<ContextMenuItem> buildMoveToGroupMenuItems(
  BuildContext context, {
  required String currentGroupId,
  required bool enabled,
  required void Function(String groupUuid, String groupLabel) onSelect,
}) {
  // 获取分组列表
  final groups = context.read<BookshelfProvider>().groups;
  final items = <ContextMenuItem>[];

  // "书架"选项 - 如果书籍当前就在书架，则禁用此选项
  final isInUngrouped = currentGroupId.isEmpty;
  items.add(ContextMenuItem(
    labelText: '书架',
    enabled: enabled && !isInUngrouped,
    onTap: enabled && !isInUngrouped ? () => onSelect('', '书架') : null,
  ));

  // 用户创建的分组
  for (final group in groups) {
    // 如果书籍当前就在该分组，则禁用此选项
    final isInThisGroup = currentGroupId == group.uuid;
    items.add(ContextMenuItem(
      labelText: group.name,
      enabled: enabled && !isInThisGroup,
      onTap: enabled && !isInThisGroup
          ? () => onSelect(group.uuid, group.name)
          : null,
    ));
  }

  return items;
}

/// 显示删除书籍的确认对话框
///
/// 检查书籍是否在工作台打开：已打开时仅提示不可删除，否则走移入回收站确认流程
void showDeleteBookConfirmDialog(BuildContext context, BookModel book) {
  // 检查书籍是否在工作台打开
  final isOpenedInWorkspace =
      MultiWindowService.instance.isWorkspaceWindowOpen(book.uuid);

  if (isOpenedInWorkspace) {
    // 如果书籍已打开，显示提示对话框
    showConfirmDialog(
      context: context,
      title: '无法删除',
      description: '书籍「${book.title}」正在工作台打开中，\n请先关闭工作台窗口后再进行删除操作。',
      type: ConfirmType.warning,
      confirmText: '我知道了',
      icon: Icons.edit_document,
    );
  } else {
    // 如果书籍未打开，显示删除确认对话框
    showConfirmDialog(
      context: context,
      title: '删除书籍',
      description: '书籍「${book.title}」将被移入回收站，\n你可以在回收站中恢复或彻底删除。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () {
        context.read<BookshelfProvider>().deleteBook(book);
        // 显示删除成功提示
        SnackBarService.show(context, '作品已移入回收站');
      },
    );
  }
}
