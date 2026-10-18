import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/shared/dialogs/export_dialog.dart';
import 'package:quick_write/shared/dialogs/import_book_dialog.dart';
import 'package:quick_write/shared/dialogs/new_book_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'workspace_opener.dart';
import 'batch_toolbar.dart';
import 'floating_action_group.dart';
import 'group_selector.dart';
import 'hover_book_item.dart';
import 'mobile_batch_bar.dart';
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

  // ================= 移动端长按交互相关状态 =================
  // 移动端长按抬起所需的按住时长，超过该时长才进入拖动/抬起状态
  static const Duration _mobileLongPressDelay = Duration(milliseconds: 500);
  // 长按抬起后仍视为"原地松手"（弹出菜单）的最大位移（逻辑像素）
  // 成功抬起时手指漂移不会超过触摸滑动阈值，这里取略大于该阈值的值；
  // 位移超过它说明用户确实在拖动排序，此时不再弹出菜单
  static const double _mobileLongPressMaxMove = 24;

  // 触摸/左键按下的起点，用于判断长按抬起后是否发生了拖动
  Offset? _primaryPointerDownPosition;
  // 触摸/左键按下后移动的最大距离
  double _primaryPointerMaxMove = 0;
  // 长按抬起时对应的书籍索引，用于确定要弹出哪本书的菜单
  int? _mobileLiftIndex;
  // 长按抬起的位置，作为菜单弹出的锚点
  Offset? _mobileLiftPosition;

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

  /// 当前分组内的书籍是否已全部选中
  bool get _isAllSelected {
    final booksToSelect = _getFilteredBooks();
    return booksToSelect.isNotEmpty &&
        _selectedBookUuids.length == booksToSelect.length;
  }

  /// 切换全选状态：已全选则取消全选，否则全选
  void _toggleSelectAll() {
    if (_isAllSelected) {
      _deselectAll();
    } else {
      _selectAll();
    }
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
  ///
  /// 桌面端使用完整工具栏，移动端宽度有限，改用只保留选中数量与全选切换的精简工具栏
  Widget _buildBatchToolbar() {
    if (PlatformCapabilities.isMobile) {
      return MobileBatchToolbar(
        selectedCount: _selectedBookUuids.length,
        isAllSelected: _isAllSelected,
        onToggleSelectAll: _toggleSelectAll,
        onComplete: _exitBatchMode,
      );
    }

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

  /// 构建移动端批量操作栏（位于网格下方）
  Widget _buildBatchActionBar() {
    return BatchActionBar(
      selectedCount: _selectedBookUuids.length,
      hasSelection: _selectedBookUuids.isNotEmpty,
      onMoveToGroup: _batchMoveToGroup,
      onExport: _batchExport,
      onDelete: _batchDelete,
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

  /// 移动端长按抬起（拖动开始）处理
  ///
  /// 记录抬起的位置与对应书籍索引，并给出轻震动反馈；
  /// 松手时若几乎未移动，[_handleMobileLiftEnd] 会据此弹出右键菜单
  void _handleMobileLiftStart(int index) {
    if (!PlatformCapabilities.isMobile) return;
    // 抬起时的轻震动反馈
    HapticFeedback.mediumImpact();
    _mobileLiftIndex = index;
    _mobileLiftPosition = _primaryPointerDownPosition;
  }

  /// 移动端长按拖动结束处理
  ///
  /// 抬起后原地松手（位移不超过阈值）视为长按弹出菜单；
  /// 若发生了位移则说明用户在拖动排序，不弹出菜单
  void _handleMobileLiftEnd(List<BookModel> books) {
    final liftIndex = _mobileLiftIndex;
    final liftPosition = _mobileLiftPosition;
    _mobileLiftIndex = null;
    _mobileLiftPosition = null;

    if (!PlatformCapabilities.isMobile) return;
    if (liftIndex == null || liftPosition == null) return;
    // 位移超过阈值：说明在拖动排序，不弹菜单
    if (_primaryPointerMaxMove > _mobileLongPressMaxMove) return;
    // 已有菜单显示时不重复弹出
    if (ContextMenu.isMenuShowing()) return;
    if (liftIndex >= books.length) return;

    ContextMenu.showMenuAt(
      context: context,
      position: liftPosition,
      menuItems: buildSingleBookMenuItems(context, books[liftIndex]),
    );
  }

  /// 构建网格区域
  ///
  /// 根据可用宽度解析网格尺寸，生成书籍卡片，并在移动端普通模式叠加悬浮操作按钮组
  Widget _buildGridArea(BuildContext context, List<BookModel> filteredBooks) {
    // 套上 LayoutBuilder 动态算列数
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度解析出列数与卡片尺寸
        // 批量模式下悬浮按钮组已隐藏，无需再为它预留底部空间
        final metrics = _BookGridMetrics.resolve(
          constraints.maxWidth,
          reserveFloatingActions: !_isBatchMode,
        );

        // 根据过滤后的书籍动态生成子组件
        final generatedChildren = filteredBooks.map((book) {
          return HoverBookItem(
            key: ValueKey(book.uuid),
            book: book,
            // 卡片尺寸由网格尺寸解析结果决定
            width: metrics.itemWidth,
            height: metrics.itemHeight,
            // 批量模式下：点击切换选中状态；普通模式下：跳转到工作台
            onTap: _isBatchMode
                ? () => _toggleBookSelection(book.uuid)
                : () => openWorkspace(
                    context: context,
                    bookId: book.uuid,
                    bookTitle: book.title,
                  ),
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

        return Stack(
          fit: StackFit.expand,
          // 不裁剪子级：悬浮按钮组位于网格右边缘，其阴影需要绘制到网格区域之外
          clipBehavior: Clip.none,
          children: [
            // 空白区域的右键菜单
            // 使用 Listener 监听右键点击，通过位置判断是否在书籍卡片上
            // Listener 只处理右键（buttons == 2），左键事件正常传递给 ReorderableBuilder
            // 同时记录触摸/左键的位移，供移动端判断长按抬起后是否发生拖动
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                // 记录右键点击位置
                if (event.buttons == 2) {
                  _emptyAreaTapPosition = event.position;
                  return;
                }
                // 记录触摸/左键按下的起点并清零位移
                _primaryPointerDownPosition = event.position;
                _primaryPointerMaxMove = 0;
              },
              onPointerMove: (event) {
                // 累计相对按下位置的最大位移
                final downPosition = _primaryPointerDownPosition;
                if (downPosition == null) return;
                final distance = (event.position - downPosition).distance;
                if (distance > _primaryPointerMaxMove) {
                  _primaryPointerMaxMove = distance;
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
                  ? _buildGrid(children: generatedChildren, metrics: metrics)
                  // 普通模式：支持拖拽排序
                  : ReorderableBuilder(
                      scrollController: _gridScrollController,
                      // 移动端长按抬起需按住一段时间，避免手指刚落就拖起影响滑动屏幕；
                      // 桌面端保持原有立即拖动行为
                      longPressDelay: PlatformCapabilities.isMobile
                          ? _mobileLongPressDelay
                          : Duration.zero,
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
                      // 移动端长按抬起时记录位置，用于松手后判断是拖动还是弹菜单
                      onDragStarted: _handleMobileLiftStart,
                      // 拖动结束时：原地松手弹菜单，发生拖动则完成排序
                      onDragEnd: (_) => _handleMobileLiftEnd(filteredBooks),
                      onReorder: (ReorderedListFunction reorderedListFunction) {
                        // 使用 context.read 获取 Provider 并调用其方法，不会引起额外重绘
                        // 传入当前分组 ID，用于分组内排序
                        context.read<BookshelfProvider>().reorderBooks(
                          reorderedListFunction,
                          groupId: _currentGroupId == '__all__'
                              ? null
                              : _currentGroupId,
                        );
                      },
                      builder: (children) {
                        return _buildGrid(children: children, metrics: metrics);
                      },
                      children: generatedChildren,
                    ),
            ),

            // 悬浮操作按钮组：移动端普通模式下提供新建、导入、批量操作入口
            if (PlatformCapabilities.isMobile && !_isBatchMode)
              Positioned(right: 0, bottom: 16, child: _buildFloatingActions()),
          ],
        );
      },
    );
  }

  /// 构建书籍网格
  ///
  /// 批量模式与普通模式共用同一套网格参数，保证两种模式下布局保持一致
  Widget _buildGrid({
    required List<Widget> children,
    required _BookGridMetrics metrics,
  }) {
    return GridView(
      key: _gridViewKey,
      controller: _gridScrollController,
      // 右侧内边距由平台策略决定；底部额外预留空间，避免最后一行被悬浮按钮组遮挡
      padding: EdgeInsets.only(
        right: metrics.rightPadding,
        bottom: metrics.bottomPadding,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: metrics.crossAxisCount,
        mainAxisExtent: metrics.mainAxisExtent, // 锁定高度
        crossAxisSpacing: metrics.crossAxisSpacing,
        mainAxisSpacing: 12,
      ),
      children: children,
    );
  }

  /// 构建移动端悬浮操作按钮组
  ///
  /// 移动端书架的悬浮操作入口，操作项从下往上依次为新建、导入、批量操作
  Widget _buildFloatingActions() {
    return FloatingActionGroup(
      actions: [
        FloatingActionItem(
          icon: Icons.add,
          tooltip: '新建作品',
          onPressed: _handleAddBook,
        ),
        FloatingActionItem(
          icon: Icons.download,
          tooltip: '导入书籍',
          onPressed: _handleImportBook,
        ),
        FloatingActionItem(
          icon: Icons.checklist,
          tooltip: '批量操作',
          onPressed: _enterBatchMode,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 根据当前分组过滤书籍
    final filteredBooks = _getFilteredBooks();

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
              : _buildGridArea(context, filteredBooks),
        ),

        // 移动端批量模式：网格下方提供批量操作入口
        if (_isBatchMode && PlatformCapabilities.isMobile)
          _buildBatchActionBar(),
      ],
    );
  }
}

/// 书籍网格的尺寸参数
///
/// 根据可用宽度解析出列数、卡片尺寸与间距，移动端与桌面端采用不同的排布策略
class _BookGridMetrics {
  /// 列数
  final int crossAxisCount;

  /// 单本书卡片宽度
  final double itemWidth;

  /// 单本书卡片高度
  final double itemHeight;

  /// 网格单行高度
  final double mainAxisExtent;

  /// 列间距
  final double crossAxisSpacing;

  /// 网格右侧内边距
  final double rightPadding;

  /// 网格底部预留高度
  final double bottomPadding;

  const _BookGridMetrics({
    required this.crossAxisCount,
    required this.itemWidth,
    required this.itemHeight,
    required this.mainAxisExtent,
    required this.crossAxisSpacing,
    required this.rightPadding,
    required this.bottomPadding,
  });

  // 移动端单本书的理想占位宽度（含列间距）
  static const double _mobileIdealItemWidth = 132;
  // 移动端卡片书名区域高度，可容纳两行书名
  static const double _mobileTitleAreaHeight = 46;
  // 移动端网格底部预留高度，避免最后一行被悬浮按钮组遮挡
  static const double _mobileGridBottomPadding = 88;
  // 移动端列间距
  static const double _mobileCrossAxisSpacing = 12;

  // 桌面端卡片宽度
  static const double _desktopItemWidth = 160;
  // 桌面端卡片高度
  static const double _desktopItemHeight = 260;
  // 桌面端列间距
  static const double _desktopItemGap = 24;
  // 桌面端网格单行高度
  static const double _desktopMainAxisExtent = 280;
  // 桌面端网格右侧内边距，让封面距离滚动条远一点
  static const double _desktopGridRightPadding = 16;

  /// 根据可用宽度解析网格尺寸
  ///
  /// [reserveFloatingActions] 为 true 时移动端会在网格底部预留空间，
  /// 避免最后一行被悬浮按钮组遮挡
  factory _BookGridMetrics.resolve(
    double availableWidth, {
    bool reserveFloatingActions = true,
  }) {
    // 移动端：一行至少放下三本书，并按实际列数均分可用宽度
    if (PlatformCapabilities.isMobile) {
      final crossAxisCount = math.max(
        3,
        (availableWidth / _mobileIdealItemWidth).floor(),
      );
      // 减去列间距后均分，得到单本书卡片宽度
      final itemWidth =
          (availableWidth - _mobileCrossAxisSpacing * (crossAxisCount - 1)) /
          crossAxisCount;
      // 封面按 3:4 比例，再叠加信息区间距与书名区域高度
      final itemHeight = itemWidth * 4 / 3 + 12 + _mobileTitleAreaHeight;

      return _BookGridMetrics(
        crossAxisCount: crossAxisCount,
        itemWidth: itemWidth,
        itemHeight: itemHeight,
        mainAxisExtent: itemHeight,
        crossAxisSpacing: _mobileCrossAxisSpacing,
        // 移动端铺满可用宽度，让三列卡片均分整个区域
        rightPadding: 0,
        bottomPadding:
            reserveFloatingActions ? _mobileGridBottomPadding : 0,
      );
    }

    // 桌面端：按固定卡片宽度与列间距计算列数
    final crossAxisCount = math.max(
      1,
      (availableWidth / (_desktopItemWidth + _desktopItemGap)).floor(),
    );

    return _BookGridMetrics(
      crossAxisCount: crossAxisCount,
      itemWidth: _desktopItemWidth,
      itemHeight: _desktopItemHeight,
      mainAxisExtent: _desktopMainAxisExtent,
      crossAxisSpacing: 0,
      rightPadding: _desktopGridRightPadding,
      bottomPadding: 0,
    );
  }
}
