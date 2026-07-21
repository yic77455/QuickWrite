import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/shared/dialogs/export_dialog.dart';
import 'package:quick_write/shared/dialogs/import_book_dialog.dart';
import 'package:quick_write/shared/dialogs/new_book_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'workspace_opener.dart';
import 'batch_toolbar.dart';
import 'group_selector.dart';
import 'hover_book_item.dart';
import 'normal_toolbar.dart';

/// 右侧书籍网格组件
///
/// 展示所有书籍的网格列表，支持拖拽排序、右键菜单和批量操作
class AllBooksGrid extends StatefulWidget {
  final List<BookModel> books;
  final bool isReady;

  const AllBooksGrid({super.key, required this.books, required this.isReady});

  @override
  State<AllBooksGrid> createState() => _AllBooksGridState();
}

class _AllBooksGridState extends State<AllBooksGrid> {
  // 网格的控制器
  final ScrollController _gridScrollController = ScrollController();
  // 网格的 GlobalKey
  final GlobalKey _gridViewKey = GlobalKey();
  // 空白区域右键点击的位置
  Offset? _emptyAreaTapPosition;

  // ================= 批量操作相关状态 =================
  // 是否处于批量操作模式
  bool _isBatchMode = false;
  // 选中的书籍 UUID 集合
  final Set<String> _selectedBookUuids = {};
  // 当前选中的分组 ID
  // - 空字符串 '' 表示"书架（未分组）"
  // - '__all__' 表示"全部作品"
  // - 其他为分组 UUID
  String _currentGroupId = MiscCacheService.instance.getSelectedGroupId();

  @override
  void initState() {
    super.initState();
    // 验证缓存的分组 ID 是否仍然有效（分组可能已被删除）
    _validateCurrentGroupId();
  }

  /// 验证当前分组 ID 是否有效，无效则回退到默认值
  void _validateCurrentGroupId() {
    // 空字符串和 '__all__' 始终有效
    if (_currentGroupId.isEmpty || _currentGroupId == '__all__') return;

    // 检查分组是否存在
    final provider = context.read<BookshelfProvider>();
    final group = provider.getGroupByUuid(_currentGroupId);
    if (group == null) {
      // 分组已被删除，回退到默认值
      _currentGroupId = '';
      MiscCacheService.instance.saveSelectedGroupId('');
    }
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  /// 进入批量操作模式
  void _enterBatchMode() {
    setState(() {
      _isBatchMode = true;
      _selectedBookUuids.clear();
    });
  }

  /// 退出批量操作模式
  void _exitBatchMode() {
    setState(() {
      _isBatchMode = false;
      _selectedBookUuids.clear();
    });
  }

  /// 切换书籍选中状态
  void _toggleBookSelection(String uuid) {
    setState(() {
      if (_selectedBookUuids.contains(uuid)) {
        _selectedBookUuids.remove(uuid);
      } else {
        _selectedBookUuids.add(uuid);
      }
    });
  }

  /// 全选（选中当前分组内的所有书籍）
  void _selectAll() {
    setState(() {
      _selectedBookUuids.clear();
      final booksToSelect = _getFilteredBooks();
      _selectedBookUuids.addAll(booksToSelect.map((book) => book.uuid));
    });
  }

  /// 根据当前分组获取过滤后的书籍列表
  List<BookModel> _getFilteredBooks() {
    if (_currentGroupId == '__all__') {
      // 全部作品：显示所有书籍
      return widget.books;
    } else if (_currentGroupId.isEmpty) {
      // 书架（未分组）：显示未分组的书籍
      return widget.books.where((book) => book.groupId.isEmpty).toList();
    } else {
      // 指定分组：显示该分组的书籍
      return widget.books.where((book) => book.groupId == _currentGroupId).toList();
    }
  }

  /// 取消全选
  void _deselectAll() {
    setState(() {
      _selectedBookUuids.clear();
    });
  }

  /// 批量删除
  void _batchDelete() {
    if (_selectedBookUuids.isEmpty) return;

    // 获取选中的书籍列表
    final selectedBooks = widget.books
        .where((book) => _selectedBookUuids.contains(book.uuid))
        .toList();

    // 检查是否有书籍在工作台打开
    final openedBooks = selectedBooks
        .where((book) => MultiWindowService.instance.isWorkspaceWindowOpen(book.uuid))
        .toList();

    if (openedBooks.isNotEmpty) {
      // 有书籍在工作台打开，显示警告
      final bookNames = openedBooks.map((b) => b.title).take(3).join('、');
      final moreCount = openedBooks.length > 3 ? '等${openedBooks.length}本' : '';
      showConfirmDialog(
        context: context,
        title: '无法删除',
        description: '书籍「$bookNames」$moreCount正在工作台打开中，\n请先关闭工作台窗口后再进行删除操作。',
        type: ConfirmType.warning,
        confirmText: '我知道了',
        icon: Icons.edit_document,
      );
      return;
    }

    // 显示删除确认对话框
    showConfirmDialog(
      context: context,
      title: '批量删除',
      description: '确定要删除选中的 ${selectedBooks.length} 本书籍吗？\n书籍将被移入回收站，你可以在回收站中恢复。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () {
        // 使用批量删除方法，避免唯一索引冲突
        context.read<BookshelfProvider>().deleteBooks(selectedBooks);
        _exitBatchMode();
        // 显示删除成功提示
        SnackBarService.show(context, '已将 ${selectedBooks.length} 本作品移入回收站');
      },
    );
  }

  /// 批量移动到分组
  void _batchMoveToGroup() {
    if (_selectedBookUuids.isEmpty) return;

    final groups = context.read<BookshelfProvider>().groups;
    if (groups.isEmpty) {
      SnackBarService.show(context, '请先创建分组');
      return;
    }

    // 构建选择项
    final items = [
      const SelectItem(label: '书架', value: '', icon: Icons.apps),
      ...groups.map((g) => SelectItem(
        label: g.name,
        value: g.uuid,
        icon: Icons.folder_outlined,
      )),
    ];

    showSelectDialog(
      context: context,
      title: '移动到分组',
      items: items,
      onSelected: (groupId) {
        // 保存数量，因为 _exitBatchMode 会清空选中列表
        final count = _selectedBookUuids.length;
        context.read<BookshelfProvider>().moveBooksToGroup(
          _selectedBookUuids.toList(),
          groupId,
        );
        _exitBatchMode();
        // 显示移动成功提示
        SnackBarService.show(context, '已将 $count 本作品移动到分组');
      },
    );
  }

  /// 批量导出
  void _batchExport() {
    if (_selectedBookUuids.isEmpty) return;

    // 获取选中的书籍列表
    final selectedBooks = widget.books
        .where((book) => _selectedBookUuids.contains(book.uuid))
        .toList();

    showExportDialog(context: context, books: selectedBooks);
  }

  /// 处理新建书籍
  Future<void> _handleAddBook() async {
    await showNewBookDialog(context);
  }

  /// 处理导入书籍
  Future<void> _handleImportBook() async {
    await showImportBookDialog(context);
  }

  /// 构建空白区域右键菜单项
  List<ContextMenuItem> _buildEmptyAreaMenuItems() {
    // 批量模式下的菜单
    if (_isBatchMode) {
      return [
        ContextMenuItem(
          labelText: '全选',
          icon: Icons.select_all,
          onTap: _selectAll,
        ),
        ContextMenuItem(
          labelText: '取消全选',
          icon: Icons.deselect,
          onTap: _deselectAll,
        ),
        ContextMenuItem.divider(),
        ContextMenuItem(
          labelText: '退出批量模式',
          icon: Icons.close,
          onTap: _exitBatchMode,
        ),
      ];
    }

    // 普通模式下的菜单
    return [
      ContextMenuItem(
        labelText: '新建作品',
        icon: Icons.add,
        onTap: _handleAddBook,
      ),
      ContextMenuItem(
        labelText: '导入书籍',
        icon: Icons.download,
        onTap: _handleImportBook,
      ),
      ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '批量操作',
        icon: Icons.checklist,
        onTap: _enterBatchMode,
      ),
      ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '刷新书架',
        icon: Icons.refresh,
        onTap: () {
          context.read<BookshelfProvider>().refresh();
          SnackBarService.show(context, '书架已刷新');
        },
      ),
    ];
  }

  /// 构建批量操作工具栏
  Widget _buildBatchToolbar() {
    return BatchToolbar(
      selectedCount: _selectedBookUuids.length,
      hasSelection: _selectedBookUuids.isNotEmpty,
      onSelectAll: _selectAll,
      onDeselectAll: _deselectAll,
      onMoveToGroup: _batchMoveToGroup,
      onExport: _batchExport,
      onDelete: _batchDelete,
      onComplete: _exitBatchMode,
    );
  }

  /// 构建普通工具栏
  Widget _buildNormalToolbar() {
    return NormalToolbar(
      groupSelector: GroupSelector(
        selectedGroupId: _currentGroupId,
        onGroupChanged: (groupId) {
          setState(() => _currentGroupId = groupId);
          // 记忆分组选择
          MiscCacheService.instance.saveSelectedGroupId(groupId);
        },
      ),
      onEnterBatchMode: _enterBatchMode,
      onImportBook: _handleImportBook,
      onAddBook: _handleAddBook,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 根据当前分组过滤书籍
    final filteredBooks = _getFilteredBooks();

    // 根据过滤后的书籍动态生成子组件
    final generatedChildren = filteredBooks.map((book) {
      return HoverBookItem(
        key: ValueKey(book.uuid),
        book: book,
        // 批量模式下：点击切换选中状态；普通模式下：跳转到工作台
        onTap: _isBatchMode
            ? () => _toggleBookSelection(book.uuid)
            : () => openWorkspace(context: context, bookId: book.uuid, bookTitle: book.title),
        // 选中状态
        isSelected: _isBatchMode && _selectedBookUuids.contains(book.uuid),
        // 是否处于批量模式
        isBatchMode: _isBatchMode,
        // 当前分组 ID（用于移动到分组时禁用当前分组）
        currentGroupId: _currentGroupId,
        // 选中状态切换回调（右键菜单使用）
        onToggleSelection: () => _toggleBookSelection(book.uuid),
        // 批量删除回调（右键菜单使用）
        onBatchDelete: _batchDelete,
        // 批量导出回调（右键菜单使用）
        onBatchExport: _batchExport,
        // 移动到分组回调（右键菜单使用）
        onMoveToGroup: (groupUuid) {
          // 保存数量，因为 _exitBatchMode 会清空选中列表
          final count = _selectedBookUuids.length;
          context.read<BookshelfProvider>().moveBooksToGroup(
            _selectedBookUuids.toList(),
            groupUuid,
          );
          _exitBatchMode();
          // 显示移动成功提示
          SnackBarService.show(context, '已将 $count 本作品移动到分组');
        },
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏和操作按钮
        _isBatchMode ? _buildBatchToolbar() : _buildNormalToolbar(),
        const SizedBox(height: 24),

        // 网格区域
        Expanded(
          // 如果首帧没画完，先显示一个透明占位
          // 只有等窗口尺寸完全稳定（isReady == true），才初始化插件
          child: !widget.isReady
              ? const SizedBox.shrink()
              // 套上 LayoutBuilder 动态算列数
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // 算法：可用总宽度 / (书本固定宽度 160 + 列间距 24)
                    int crossAxisCount = (constraints.maxWidth / (160 + 24))
                        .floor();
                    if (crossAxisCount < 1) crossAxisCount = 1;

                    // 空白区域的右键菜单
                    // 使用 Listener 监听右键点击，通过位置判断是否在书籍卡片上
                    // Listener 只处理右键（buttons == 2），左键事件正常传递给 ReorderableBuilder
                    return Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        // 记录右键点击位置
                        if (event.buttons == 2) {
                          _emptyAreaTapPosition = event.position;
                        }
                      },
                      onPointerUp: (event) {
                        // 右键抬起时，如果没有菜单显示，说明点击的是空白区域
                        if (_emptyAreaTapPosition != null &&
                            !ContextMenu.isMenuShowing()) {
                          // 显示空白区域菜单
                          ContextMenu.showMenuAt(
                            context: context,
                            position: _emptyAreaTapPosition!,
                            menuItems: _buildEmptyAreaMenuItems(),
                          );
                        }
                        _emptyAreaTapPosition = null;
                      },
                      child: _isBatchMode
                          // 批量模式下：禁用拖拽，使用普通 GridView
                          ? GridView(
                              key: _gridViewKey,
                              controller: _gridScrollController,
                              // 右侧内边距，让封面距离滚动条远一点
                              padding: const EdgeInsets.only(right: 16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisExtent: 280, // 锁定高度
                                    crossAxisSpacing: 0,
                                    mainAxisSpacing: 12,
                                  ),
                              children: generatedChildren,
                            )
                          // 普通模式：支持拖拽排序
                          : ReorderableBuilder(
                              scrollController: _gridScrollController,
                              longPressDelay: Duration.zero,
                              // 接管被拖起时的反馈样式
                              dragChildBoxDecoration: BoxDecoration(
                                // 保持和卡片一样的圆角
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 50,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              onReorder:
                                  (
                                    ReorderedListFunction reorderedListFunction,
                                  ) {
                                    // 使用 context.read 获取 Provider 并调用其方法，不会引起额外重绘
                                    // 传入当前分组 ID，用于分组内排序
                                    context
                                        .read<BookshelfProvider>()
                                        .reorderBooks(
                                          reorderedListFunction,
                                          groupId: _currentGroupId == '__all__' 
                                              ? null 
                                              : _currentGroupId,
                                        );
                                  },
                              builder: (children) {
                                return GridView(
                                  key: _gridViewKey,
                                  controller: _gridScrollController,
                                  // 右侧内边距，让封面距离滚动条远一点
                                  padding: const EdgeInsets.only(right: 16),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        mainAxisExtent: 280, // 锁定高度
                                        crossAxisSpacing: 0,
                                        mainAxisSpacing: 12,
                                      ),
                                  children: children,
                                );
                              },
                              children: generatedChildren,
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
