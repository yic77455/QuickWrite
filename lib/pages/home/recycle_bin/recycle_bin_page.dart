import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/providers/recycle_bin_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'widgets/widgets.dart';

/// 回收站页面
///
/// 提供书籍回收站和章节回收站两个视图，通过顶部 Tab 切换
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  /// 当前选中的回收站视图（0=书籍回收站，1=章节回收站）
  int _currentTab = 0;

  /// 书籍回收站中选中的记录 UUID 集合
  final Set<String> _selectedBookUuids = {};

  /// 章节回收站中选中的记录 UUID 集合
  final Set<String> _selectedItemUuids = {};

  /// 记录上一次的页面索引，用于判断是否切换到了回收站
  int _lastSelectedIndex = -1;

  @override
  void initState() {
    super.initState();
    // 页面初始化时刷新数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  /// 切换 Tab
  void _switchTab(int index) {
    if (_currentTab == index) return;
    setState(() {
      _currentTab = index;
      // 切换 Tab 时清空当前选中状态，避免跨视图混淆
      _selectedBookUuids.clear();
      _selectedItemUuids.clear();
    });
  }

  /// 刷新回收站数据
  Future<void> _refreshData() async {
    if (!mounted) return;
    await context.read<RecycleBinProvider>().refresh();
  }

  /// 获取当前 Tab 的选中数量
  int get _currentSelectedCount =>
      _currentTab == 0 ? _selectedBookUuids.length : _selectedItemUuids.length;

  /// 获取当前 Tab 是否有选中项
  bool get _hasSelection => _currentSelectedCount > 0;

  // ================= 选中状态管理 =================

  /// 全选当前视图的所有项
  void _selectAll() {
    final provider = context.read<RecycleBinProvider>();
    setState(() {
      if (_currentTab == 0) {
        _selectedBookUuids.clear();
        _selectedBookUuids.addAll(provider.recycledBooks.map((b) => b.uuid));
      } else {
        _selectedItemUuids.clear();
        _selectedItemUuids.addAll(provider.recycledItems.map((i) => i.uuid));
      }
    });
  }

  /// 取消全选
  void _deselectAll() {
    setState(() {
      if (_currentTab == 0) {
        _selectedBookUuids.clear();
      } else {
        _selectedItemUuids.clear();
      }
    });
  }

  /// 切换单个选中状态
  void _toggleSelection(String uuid) {
    setState(() {
      final selectedSet = _currentTab == 0 ? _selectedBookUuids : _selectedItemUuids;
      if (selectedSet.contains(uuid)) {
        selectedSet.remove(uuid);
      } else {
        selectedSet.add(uuid);
      }
    });
  }

  // ================= 批量操作 =================

  /// 批量恢复
  Future<void> _restoreSelected() async {
    if (!_hasSelection) return;

    if (_currentTab == 0) {
      await _restoreSelectedBooks();
    } else {
      await _restoreSelectedItems();
    }
  }

  /// 批量恢复书籍
  Future<void> _restoreSelectedBooks() async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final bookshelfProvider = context.read<BookshelfProvider>();
    final selectedBooks = recycleBinProvider.recycledBooks
        .where((b) => _selectedBookUuids.contains(b.uuid))
        .toList();

    showConfirmDialog(
      context: context,
      title: '恢复书籍',
      description: '确定要恢复选中的 ${selectedBooks.length} 本书籍吗？',
      type: ConfirmType.info,
      confirmText: '恢复',
      cancelText: '取消',
      icon: Icons.restore,
      onConfirm: () async {
        int successCount = 0;
        for (final book in selectedBooks) {
          final success = await bookshelfProvider.restoreFromRecycleBin(book);
          if (success) {
            successCount++;
          }
        }
        await recycleBinProvider.refresh();
        _deselectAll();
        if (mounted) {
          SnackBarService.show(context, '已恢复 $successCount 本作品');
        }
      },
    );
  }

  /// 批量恢复章节/设定项
  Future<void> _restoreSelectedItems() async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final bookshelfProvider = context.read<BookshelfProvider>();
    final selectedItems = recycleBinProvider.recycledItems
        .where((i) => _selectedItemUuids.contains(i.uuid))
        .toList();

    // 收集所有涉及的书籍 UUID，一次性查询
    final bookUuids = selectedItems.map((i) => i.bookUuid).toSet();
    final existingBooks = <String, BookModel>{};
    for (final bookUuid in bookUuids) {
      final book = bookshelfProvider.books.where((b) => b.uuid == bookUuid).firstOrNull;
      if (book != null) {
        existingBooks[bookUuid] = book;
      }
    }

    final restorableCount = selectedItems
        .where((i) => existingBooks.containsKey(i.bookUuid))
        .length;
    final unRestorableCount = selectedItems.length - restorableCount;

    String description = '确定要恢复选中的 ${selectedItems.length} 个项目吗？';
    if (unRestorableCount > 0) {
      description += '\n其中 $unRestorableCount 个项目所属书籍已被删除，无法恢复。';
    }

    showConfirmDialog(
      context: context,
      title: '恢复项目',
      description: description,
      type: ConfirmType.info,
      confirmText: '恢复',
      cancelText: '取消',
      icon: Icons.restore,
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(
          context: context,
          message: '正在恢复 ${selectedItems.length} 个项目，请稍候...',
        );
        try {
          // 过滤出可恢复的项（原书籍存在）
          final restorableItems = selectedItems
              .where((i) => existingBooks.containsKey(i.bookUuid))
              .toList();
          final unRestorableCount = selectedItems.length - restorableItems.length;

          // 按类型分组
          final chapterItems = restorableItems.where((i) => i.isChapter).toList();
          final settingItems = restorableItems.where((i) => i.isSetting).toList();

          // 按书籍收集现有数据（每个 bookUuid 只查询一次）
          final existingChaptersByBook = <String, List<ChapterModel>>{};
          final existingVolumesByBook = <String, List<VolumeModel>>{};
          for (final item in chapterItems) {
            if (!existingChaptersByBook.containsKey(item.bookUuid)) {
              existingChaptersByBook[item.bookUuid] =
                  await recycleBinProvider.getBookChapters(item.bookUuid);
              existingVolumesByBook[item.bookUuid] =
                  await recycleBinProvider.getBookVolumes(item.bookUuid);
            }
          }

          final existingItemsByBook = <String, List<SettingItemModel>>{};
          final existingGroupsByBook = <String, List<SettingGroupModel>>{};
          for (final item in settingItems) {
            if (!existingItemsByBook.containsKey(item.bookUuid)) {
              existingItemsByBook[item.bookUuid] =
                  await recycleBinProvider.getBookSettingItems(item.bookUuid);
              existingGroupsByBook[item.bookUuid] =
                  await recycleBinProvider.getBookSettingGroups(item.bookUuid);
            }
          }

          int successCount = 0;
          int failCount = unRestorableCount;

          // 批量恢复章节
          if (chapterItems.isNotEmpty) {
            final result = await recycleBinProvider.restoreChaptersFromRecycleBatch(
              items: chapterItems,
              books: existingBooks,
              existingChaptersByBook: existingChaptersByBook,
              existingVolumesByBook: existingVolumesByBook,
            );
            successCount += result.success;
            failCount += result.fail;
          }

          // 批量恢复设定项
          if (settingItems.isNotEmpty) {
            final result = await recycleBinProvider.restoreSettingItemsFromRecycleBatch(
              items: settingItems,
              books: existingBooks,
              existingItemsByBook: existingItemsByBook,
              existingGroupsByBook: existingGroupsByBook,
            );
            successCount += result.success;
            failCount += result.fail;
          }

          await recycleBinProvider.refreshItems();
          _deselectAll();
          if (mounted) {
            String message = '已恢复 $successCount 个项目';
            if (failCount > 0) {
              message += '，$failCount 个失败';
            }
            SnackBarService.show(context, message);
          }
        } finally {
          dismissLoading();
        }
      },
    );
  }

  /// 批量彻底删除
  Future<void> _deleteSelectedPermanently() async {
    if (!_hasSelection) return;

    if (_currentTab == 0) {
      await _deleteSelectedBooksPermanently();
    } else {
      await _deleteSelectedItemsPermanently();
    }
  }

  /// 批量彻底删除书籍
  Future<void> _deleteSelectedBooksPermanently() async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final selectedBooks = recycleBinProvider.recycledBooks
        .where((b) => _selectedBookUuids.contains(b.uuid))
        .toList();

    showConfirmDialog(
      context: context,
      title: '彻底删除',
      description: '确定要彻底删除选中的 ${selectedBooks.length} 本书籍吗？\n此操作无法撤销，文件将被永久删除。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(context: context, message: '正在删除，请稍候...');
        try {
          await recycleBinProvider.deletePermanentlyBatch(selectedBooks);
        } finally {
          dismissLoading();
        }
        _deselectAll();
        if (mounted) {
          SnackBarService.show(context, '已彻底删除 ${selectedBooks.length} 本作品');
        }
      },
    );
  }

  /// 批量彻底删除章节/设定项
  Future<void> _deleteSelectedItemsPermanently() async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final selectedItems = recycleBinProvider.recycledItems
        .where((i) => _selectedItemUuids.contains(i.uuid))
        .toList();

    showConfirmDialog(
      context: context,
      title: '彻底删除',
      description: '确定要彻底删除选中的 ${selectedItems.length} 个项目吗？\n此操作无法撤销，文件将被永久删除。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(
          context: context,
          message: '正在彻底删除 ${selectedItems.length} 个项目，请稍候...',
        );
        try {
          await recycleBinProvider.deleteItemsPermanentlyBatch(selectedItems);
          _deselectAll();
          if (mounted) {
            SnackBarService.show(context, '已彻底删除 ${selectedItems.length} 个项目');
          }
        } finally {
          dismissLoading();
        }
      },
    );
  }

  /// 清空回收站
  Future<void> _emptyRecycleBin() async {
    final recycleBinProvider = context.read<RecycleBinProvider>();

    if (_currentTab == 0) {
      if (recycleBinProvider.isBooksEmpty) {
        SnackBarService.show(context, '书籍回收站是空的');
        return;
      }
      await _emptyBooksRecycleBin(recycleBinProvider);
    } else {
      if (recycleBinProvider.isItemsEmpty) {
        SnackBarService.show(context, '章节回收站是空的');
        return;
      }
      await _emptyItemsRecycleBin(recycleBinProvider);
    }
  }

  /// 清空书籍回收站
  Future<void> _emptyBooksRecycleBin(RecycleBinProvider provider) async {
    final count = provider.recycledBooksCount;
    showConfirmDialog(
      context: context,
      title: '清空书籍回收站',
      description: '确定要清空书籍回收站吗？\n此操作将永久删除所有书籍，无法撤销。',
      type: ConfirmType.delete,
      confirmText: '清空',
      cancelText: '取消',
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(context: context, message: '正在清空回收站，请稍候...');
        try {
          await provider.emptyRecycleBin();
        } finally {
          dismissLoading();
        }
        _deselectAll();
        if (mounted) {
          SnackBarService.show(context, '已清空书籍回收站，共删除 $count 本作品');
        }
      },
    );
  }

  /// 清空章节回收站
  Future<void> _emptyItemsRecycleBin(RecycleBinProvider provider) async {
    final count = provider.recycledItemsCount;
    showConfirmDialog(
      context: context,
      title: '清空章节回收站',
      description: '确定要清空章节回收站吗？\n此操作将永久删除所有章节和设定项，无法撤销。',
      type: ConfirmType.delete,
      confirmText: '清空',
      cancelText: '取消',
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(context: context, message: '正在清空回收站，请稍候...');
        try {
          await provider.emptyItemsRecycleBin();
        } finally {
          dismissLoading();
        }
        _deselectAll();
        if (mounted) {
          SnackBarService.show(context, '已清空章节回收站，共删除 $count 个项目');
        }
      },
    );
  }

  // ================= 单项操作 =================

  /// 恢复单个书籍
  Future<void> _restoreSingleBook(String uuid) async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final bookshelfProvider = context.read<BookshelfProvider>();
    final book = recycleBinProvider.getRecycledBookByUuid(uuid);
    if (book == null) return;

    showConfirmDialog(
      context: context,
      title: '恢复书籍',
      description: '确定要恢复「${book.title}」吗？\n书籍将恢复到书架最前面。',
      type: ConfirmType.info,
      confirmText: '恢复',
      cancelText: '取消',
      icon: Icons.restore,
      onConfirm: () async {
        final success = await bookshelfProvider.restoreFromRecycleBin(book);
        if (success) {
          await recycleBinProvider.refresh();
          // 从选中集合中移除已恢复的项目，同步全选复选框和选中计数
          setState(() {
            _selectedBookUuids.remove(uuid);
          });
          if (mounted) {
            SnackBarService.show(context, '「${book.title}」已恢复');
          }
        }
      },
    );
  }

  /// 彻底删除单个书籍
  Future<void> _deleteSingleBookPermanently(String uuid) async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final book = recycleBinProvider.getRecycledBookByUuid(uuid);
    if (book == null) return;

    showConfirmDialog(
      context: context,
      title: '彻底删除',
      description: '确定要彻底删除「${book.title}」吗？\n此操作无法撤销，文件将被永久删除。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        await recycleBinProvider.deletePermanently(book);
        // 从选中集合中移除已删除的项目，同步全选复选框和选中计数
        setState(() {
          _selectedBookUuids.remove(uuid);
        });
        if (mounted) {
          SnackBarService.show(context, '「${book.title}」已彻底删除');
        }
      },
    );
  }

  /// 恢复单个章节/设定项
  Future<void> _restoreSingleItem(String uuid) async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final bookshelfProvider = context.read<BookshelfProvider>();
    final item = recycleBinProvider.getRecycledItemByUuid(uuid);
    if (item == null) return;

    // 检查原书籍是否存在
    final book = bookshelfProvider.books.where((b) => b.uuid == item.bookUuid).firstOrNull;
    if (book == null) {
      SnackBarService.show(context, '原书籍「${item.bookTitle}」已被删除，无法恢复');
      return;
    }

    final typeText = item.isChapter ? '章节' : '设定';
    showConfirmDialog(
      context: context,
      title: '恢复$typeText',
      description: '确定要恢复$typeText「${item.title}」吗？\n将恢复到「${item.bookTitle}」末尾。',
      type: ConfirmType.info,
      confirmText: '恢复',
      cancelText: '取消',
      icon: Icons.restore,
      onConfirm: () async {
        bool success = false;
        if (item.isChapter) {
          final chapters = await recycleBinProvider.getBookChapters(item.bookUuid);
          final volumes = await recycleBinProvider.getBookVolumes(item.bookUuid);
          final restored = await recycleBinProvider.restoreChapterFromRecycle(
            item: item,
            book: book,
            existingChapters: chapters,
            volumes: volumes,
          );
          success = restored != null;
        } else {
          final items = await recycleBinProvider.getBookSettingItems(item.bookUuid);
          final groups = await recycleBinProvider.getBookSettingGroups(item.bookUuid);
          final restored = await recycleBinProvider.restoreSettingItemFromRecycle(
            item: item,
            book: book,
            existingItems: items,
            groups: groups,
          );
          success = restored != null;
        }
        if (success) {
          // 从选中集合中移除已恢复的项目，同步全选复选框和选中计数
          setState(() {
            _selectedItemUuids.remove(uuid);
          });
          if (mounted) {
            SnackBarService.show(context, '「${item.title}」已恢复');
          }
        }
      },
    );
  }

  /// 彻底删除单个章节/设定项
  Future<void> _deleteSingleItemPermanently(String uuid) async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final item = recycleBinProvider.getRecycledItemByUuid(uuid);
    if (item == null) return;

    final typeText = item.isChapter ? '章节' : '设定';
    showConfirmDialog(
      context: context,
      title: '彻底删除',
      description: '确定要彻底删除$typeText「${item.title}」吗？\n此操作无法撤销，文件将被永久删除。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        await recycleBinProvider.deleteItemPermanently(item);
        // 从选中集合中移除已删除的项目，同步全选复选框和选中计数
        setState(() {
          _selectedItemUuids.remove(uuid);
        });
        if (mounted) {
          SnackBarService.show(context, '「${item.title}」已彻底删除');
        }
      },
    );
  }

  // ================= 构建界面 =================

  @override
  Widget build(BuildContext context) {
    // 监听页面切换，当切换到回收站时刷新数据
    final selectedIndex = context.watch<HomeStateProvider>().selectedIndex;
    // 回收站页面的索引是 2
    if (selectedIndex == 2 && _lastSelectedIndex != 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshData();
      });
    }
    _lastSelectedIndex = selectedIndex;

    return Consumer<RecycleBinProvider>(
      builder: (context, provider, child) {
        // 如果还在初始化，显示加载中
        if (!provider.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        return Column(
          children: [
            // 顶部：Tab 切换栏
            _buildTabBar(context),
            // 工具栏（仅在对应视图有数据时显示）
            if ((_currentTab == 0 && !provider.isBooksEmpty) ||
                (_currentTab == 1 && !provider.isItemsEmpty))
              RecycleBinToolbar(
                selectedCount: _currentSelectedCount,
                totalCount: _currentTab == 0
                    ? provider.recycledBooksCount
                    : provider.recycledItemsCount,
                hasSelection: _hasSelection,
                onSelectAll: _selectAll,
                onDeselectAll: _deselectAll,
                onRestore: _restoreSelected,
                onDelete: _deleteSelectedPermanently,
                onEmpty: _emptyRecycleBin,
                emptyLabel: _currentTab == 0 ? '清空书籍回收站' : '清空章节回收站',
              ),
            // 内容区域
            Expanded(
              child: _currentTab == 0
                  ? BookRecycleView(
                      recycledBooks: provider.recycledBooks,
                      selectedUuids: _selectedBookUuids,
                      onToggleSelection: _toggleSelection,
                      onRestore: _restoreSingleBook,
                      onDelete: _deleteSingleBookPermanently,
                    )
                  : ItemRecycleView(
                      recycledItems: provider.recycledItems,
                      existingBookUuids: context
                          .watch<BookshelfProvider>()
                          .books
                          .map((b) => b.uuid)
                          .toSet(),
                      selectedUuids: _selectedItemUuids,
                      onToggleSelection: _toggleSelection,
                      onRestore: _restoreSingleItem,
                      onDelete: _deleteSingleItemPermanently,
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 构建顶部 Tab 切换栏
  Widget _buildTabBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = context.read<RecycleBinProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Row(
        children: [
          // 左侧：Tab 切换
          SizedBox(
            width: 280,
            child: SegmentedControl(
              labels: [
                '书籍回收站 (${provider.recycledBooksCount})',
                '章节回收站 (${provider.recycledItemsCount})',
              ],
              selectedIndex: _currentTab,
              onChanged: _switchTab,
            ),
          ),
          const SizedBox(width: 16),
          // 右侧：说明文字
          Expanded(
            child: Text(
              _currentTab == 0
                  ? '删除的作品会在这里保留，可随时恢复'
                  : '删除的章节和设定项会在这里保留，可随时恢复',
              style: context.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
