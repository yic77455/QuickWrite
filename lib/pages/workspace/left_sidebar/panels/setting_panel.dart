import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'package:quick_write/shared/widgets/sortable/sliver_sortable_list.dart';
import 'package:quick_write/shared/dialogs/new_setting_dialog.dart';
import 'package:quick_write/shared/dialogs/export_dialog.dart';
import 'package:quick_write/core/utils/reorder_utils.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/batch_selection_controller.dart';
import 'package:quick_write/core/utils/file_explorer.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import '../widgets/contents_list_widgets.dart';
import '../widgets/contents_top_bar.dart';
import '../widgets/contents_sortable.dart';

/// 设定面板
///
/// 包含大纲、角色设定等设定内容
class SettingPanel extends StatefulWidget {
  const SettingPanel({super.key});

  @override
  State<SettingPanel> createState() => _SettingPanelState();
}

class _SettingPanelState extends State<SettingPanel>
    with AutomaticKeepAliveClientMixin, ContentsSortMixin {
  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 当前标签页ID（用于检测标签页切换）
  String? _currentTabId;

  /// 未分组设定项是否折叠
  bool _isUnassignedCollapsed = false;

  /// 当前书籍UUID（用于检测书籍切换）
  String? _currentBookUuid;

  /// 上次点击的时间戳，用于手动检测双击
  int _lastTapTime = 0;

  /// 上次点击的设定项UUID，用于手动检测双击
  String? _lastTappedItemId;

  /// 当前打开操作菜单的设定项UUID，用于保持按钮按下状态
  String? _menuOpenedItemId;

  /// 当前打开操作菜单的分组 UUID，用于保持按钮按下状态
  String? _menuOpenedGroupUuid;

  /// 当前菜单是否通过下拉按钮打开
  bool _menuOpenedByDropdown = false;

  /// 当前吸顶的分组 UUID（仅当前正在浏览内容的分组会吸顶）
  String? _stickyGroupUuid;

  /// 吸顶标题是否叠加显示（分组标题滚出视口顶部后为 true）
  bool _isStickyHeaderVisible = false;

  /// 分组偏移缓存（在 _buildSettingList 中更新，滚动时查表使用，避免重复计算）
  List<({String uuid, double startOffset, bool isExpanded})> _groupOffsets = [];

  /// 列表布局快照（在 _buildSettingList 中更新，批量模式触摸拖拽时按位置查表命中设定项）
  List<({double startOffset, String? id})> _listSlots = [];

  /// 本次构建的分组索引表，供行构建与吸顶标题复用
  Map<String, SettingGroupModel> _settingGroupIndex = const {};

  /// 本次构建的分组设定项映射
  Map<String, List<SettingItemModel>> _groupItemsByUuid = const {};

  /// 本次构建的设定项对象映射
  Map<String, SettingItemModel> _itemByUuid = const {};

  /// 本次构建的设定项组内序号
  Map<String, int> _itemNumberByUuid = const {};

  /// 折叠吸顶分组后待跳转的滚动偏移（使折叠后的分组标题保持可见）
  double? _pendingScrollOffset;

  /// 是否处于批量管理模式
  bool _isBatchMode = false;

  /// 批量模式下已选中的设定项UUID集合
  final Set<String> _selectedItemIds = {};

  /// 批量模式多选交互控制器（Shift+点击范围选择、鼠标拖拽多选）
  late final BatchSelectionController _selectionController;

  /// 批量模式下"移动"按钮的 GlobalKey，用于定位下拉菜单
  final GlobalKey _moveButtonKey = GlobalKey();

  /// 设定列表滚动视图的 GlobalKey，用于触摸拖拽时按全局坐标换算列表内容坐标
  final GlobalKey _listKey = GlobalKey();

  /// 设定列表是否倒序排列
  bool _isReversed = false;

  /// 设定项固定高度
  static const double _settingItemExtent = 48.0;

  /// 分组标题高度（Container height 40 + vertical margin 4）
  static const double _groupHeaderExtent = 44.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 从缓存加载分组展开状态
    _loadExpandedState();
    // 监听滚动，动态更新吸顶分组
    _scrollController.addListener(_onScroll);
    // 初始化批量多选交互控制器
    _selectionController = BatchSelectionController(
      getSelectedIds: () => _selectedItemIds,
      getFlatDisplayIds: () {
        final provider = context.read<WorkspaceProvider>();
        return _buildFlatDisplayItems(provider.settingItems, provider.settingGroups)
            .map((i) => i.uuid)
            .toList();
      },
      onChanged: () {
        if (mounted) setState(() {});
      },
      // 触摸端无悬停事件，长按拖拽时按指针位置命中设定项
      hitTestId: _hitTestSettingItemAt,
    );
  }

  /// 从缓存加载分组展开状态
  void _loadExpandedState() {
    final provider = context.read<WorkspaceProvider>();
    final bookUuid = provider.currentBook?.uuid;
    if (bookUuid != null) {
      _isUnassignedCollapsed = MiscCacheService.instance.isSettingUnassignedCollapsed(bookUuid);
      _currentBookUuid = bookUuid;
    } else {
      _isUnassignedCollapsed = false;
    }
    // 加载设定排序方式（全局缓存）
    _isReversed = MiscCacheService.instance.isSettingReversed();
    // 同步初始化标签页ID，避免面板重建时误触发滚动
    _currentTabId = provider.currentTab?.id;
  }

  /// 保存未分组折叠状态到缓存
  void _saveUnassignedCollapsedState() {
    final bookUuid = _currentBookUuid;
    if (bookUuid == null) return;
    MiscCacheService.instance.saveSettingUnassignedCollapsed(bookUuid, _isUnassignedCollapsed);
  }

  /// 保存设定排序方式到缓存
  void _saveReversedState() {
    MiscCacheService.instance.saveSettingReversed(_isReversed);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动回调，更新当前吸顶的分组
  void _onScroll() {
    _updateStickyGroup();
  }

  /// 根据当前滚动偏移计算应吸顶的分组
  /// 仅让"当前正在浏览内容的分组"吸顶，其余分组不吸顶
  void _updateStickyGroup() {
    if (!mounted || !_scrollController.hasClients) return;

    // 无分组数据时清除吸顶
    if (_groupOffsets.isEmpty) {
      if (_stickyGroupUuid != null || _isStickyHeaderVisible) {
        setState(() {
          _stickyGroupUuid = null;
          _isStickyHeaderVisible = false;
        });
      }
      return;
    }

    final offset = _scrollController.offset;
    String? newStickyUuid;

    // 查表找到最后一个起始偏移 <= 当前滚动偏移的展开分组
    for (final g in _groupOffsets) {
      if (offset >= g.startOffset && g.isExpanded) {
        newStickyUuid = g.uuid;
      } else if (offset < g.startOffset) {
        break; // 后续分组偏移更大，提前退出
      }
    }

    // 分组标题滚出视口顶部后才需要叠加吸顶标题
    final groupInfo = newStickyUuid == null
        ? null
        : _groupOffsets.where((g) => g.uuid == newStickyUuid).firstOrNull;
    final isHeaderVisible = groupInfo != null && offset > groupInfo.startOffset;

    // 仅在吸顶分组或吸顶标题显隐变化时刷新，避免无谓重建
    if (_stickyGroupUuid != newStickyUuid || _isStickyHeaderVisible != isHeaderVisible) {
      setState(() {
        _stickyGroupUuid = newStickyUuid;
        _isStickyHeaderVisible = isHeaderVisible;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<WorkspaceProvider>(context);

    // 检测书籍切换，重新加载展开状态
    final bookUuid = provider.currentBook?.uuid;
    if (bookUuid != _currentBookUuid) {
      _currentBookUuid = bookUuid;
      if (bookUuid != null) {
        _isUnassignedCollapsed = MiscCacheService.instance.isSettingUnassignedCollapsed(bookUuid);
      } else {
        _isUnassignedCollapsed = false;
      }
    }

    // 检测标签页切换，自动定位到对应设定项
    final tab = provider.currentTab;
    if (tab?.id != _currentTabId) {
      _currentTabId = tab?.id;
      // 延迟一帧确保滚动控制器就绪
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrentSetting();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    // 列表重建后处理待跳转的滚动偏移并重新计算吸顶分组
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 折叠吸顶分组后跳转到该分组起始位置，使分组标题保持可见
      if (_pendingScrollOffset != null && _scrollController.hasClients) {
        _scrollController.jumpTo(_pendingScrollOffset!);
        _pendingScrollOffset = null;
      }
      _updateStickyGroup();
    });

    return Container(
      color: colorScheme.surface.withValues(alpha: 0.3),
      child: Column(
        children: [
          // 顶部操作栏
          _buildTopBar(context),

          // 设定列表
          Expanded(child: _buildSettingList(context)),

          // 批量操作栏
          if (_isBatchMode) _buildBatchActionBar(context),
        ],
      ),
    );
  }

  /// 构建顶部操作栏
  Widget _buildTopBar(BuildContext context) {
    return ContentsTopBar(
      isBatchMode: _isBatchMode,
      isAllSelected: _isAllSelected(),
      onToggleSelectAll: _toggleSelectAll,
      onExitBatchMode: _exitBatchMode,
      addTooltip: '新建设定/分组',
      onAdd: () {
        final provider = context.read<WorkspaceProvider>();
        // 从缓存读取上次选择的分组
        final bookUuid = provider.currentBook?.uuid;
        final lastGroup = bookUuid != null ? MiscCacheService.instance.getLastSelectedSettingGroup(bookUuid) : '';
        _showNewSettingDialog(initialGroupUuid: lastGroup);
      },
      isReversed: _isReversed,
      onToggleReversed: () {
        setState(() {
          _isReversed = !_isReversed;
        });
        _saveReversedState();
        SnackBarService.show(context, _isReversed ? '已切换为倒序' : '已切换为正序');
      },
      onToggleSidebar: () {
        context.read<WorkspaceProvider>().toggleLeftSidebar();
      },
      onMenuAction: (value) {
        if (value == 'batch') {
          _enterBatchMode();
        }
      },
    );
  }

  /// 构建设定列表
  ///
  /// 分组标题与设定项作为同一可拖拽列表中的行，支持设定项跨分组拖拽；
  /// 拖拽分组标题期间折叠所有分组，结束后恢复。
  Widget _buildSettingList(BuildContext context) {
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final rows = buildContentsRows();
    if (rows.isEmpty) {
      return _buildEmptyState(context);
    }

    final listView = CustomScrollView(
      key: _listKey,
      controller: _scrollController,
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: 4)),
        SliverSortableList(
          rowKeys: rows.map((row) => row.key).toList(),
          itemExtentBuilder: (index, _) => rows[index].extent,
          itemBuilder: (context, index) => _buildContentsRow(context, rows, index, workspaceProvider),
          onReorderStart: handleContentsReorderStart,
          onReorder: handleContentsReorder,
          onReorderCompleted: handleContentsReorderCompleted,
          proxyDecorator: _buildReorderProxyDecorator,
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 4)),
      ],
    );

    return _wrapWithSelectionListener(
      _wrapWithStickyHeader(context, listView, workspaceProvider),
    );
  }

  /// 构建目录中的单行
  Widget _buildContentsRow(
    BuildContext context,
    List<ContentsRow> rows,
    int index,
    WorkspaceProvider provider,
  ) {
    final row = rows[index];
    final content = row.isHeader
        ? _buildGroupHeader(context, row.groupUuid, provider)
        : _buildSettingRow(context, row.itemUuid!, provider);

    // 批量模式下禁用拖拽
    if (_isBatchMode) {
      return SizedBox(key: ValueKey(row.key), height: row.extent, child: content);
    }
    return SortableDelayedDragStartListener(
      key: ValueKey(row.key),
      index: index,
      child: SizedBox(height: row.extent, child: content),
    );
  }

  /// 构建设定项行
  Widget _buildSettingRow(BuildContext context, String itemUuid, WorkspaceProvider provider) {
    final item = _itemByUuid[itemUuid];
    if (item == null) return const SizedBox.shrink();

    return _buildSettingItemWidget(
      context,
      item,
      item.groupUuid.isEmpty ? null : item.groupUuid,
      provider.currentTab?.id,
      _itemNumberByUuid[itemUuid] ?? 0,
    );
  }

  /// 构建分组标题
  Widget _buildGroupHeader(BuildContext context, String groupUuid, WorkspaceProvider provider) {
    final isUnassigned = groupUuid.isEmpty;
    final groupItems = _groupItemsByUuid[groupUuid] ?? const <SettingItemModel>[];
    final isExpanded = _isGroupExpanded(groupUuid);
    final groupName = isUnassigned ? '未分组' : provider.getSettingGroupName(groupUuid);

    if (_isBatchMode) {
      return _buildBatchGroupHeader(
        context: context,
        title: groupName,
        icon: Icons.folder_outlined,
        isExpanded: isExpanded,
        groupItems: groupItems,
        onToggleExpand: () => _toggleGroup(groupUuid),
      );
    }

    return GroupHeader(
      title: groupName,
      icon: Icons.folder_outlined,
      itemCount: groupItems.length,
      isExpanded: isExpanded,
      itemCountSuffix: '项',
      onTap: () => _toggleGroup(groupUuid),
      onAddPressed: isUnassigned ? null : () => _showNewSettingDialog(initialGroupUuid: groupUuid),
      addTooltip: '新建设定',
      onMenuPressed: isUnassigned
          ? null
          : (buttonContext) {
              final button = buttonContext.findRenderObject() as RenderBox?;
              if (button == null) return;
              _showGroupMenu(
                buttonContext,
                groupUuid,
                type: ContextMenuType.dropdown,
                position: button.localToGlobal(Offset.zero),
                anchorSize: button.size,
              );
            },
      isMenuOpen: _menuOpenedGroupUuid == groupUuid,
      isButtonPressed: _menuOpenedGroupUuid == groupUuid && _menuOpenedByDropdown,
      menuTooltip: '更多',
      onSecondaryTapDown: isUnassigned
          ? null
          : (details) {
              _showGroupMenu(
                context,
                groupUuid,
                type: ContextMenuType.contextMenu,
                position: details.globalPosition,
              );
            },
    );
  }

  /// 为列表叠加吸顶的分组标题
  ///
  /// 标题与设定项同属一个可拖拽列表，无法再使用吸顶 sliver，
  /// 因此在列表上方叠加当前分组的标题，并转发滚动事件以保留可滚动性。
  Widget _wrapWithStickyHeader(
    BuildContext context,
    Widget listView,
    WorkspaceProvider provider,
  ) {
    final stickyHeader = _buildStickyHeaderOverlay(context, provider);
    return Stack(
      children: [
        listView,
        if (stickyHeader != null) Positioned(top: 0, left: 0, right: 0, child: stickyHeader),
      ],
    );
  }

  /// 构建吸顶标题，无需吸顶时返回 null
  Widget? _buildStickyHeaderOverlay(BuildContext context, WorkspaceProvider provider) {
    if (!_isStickyHeaderVisible) return null;

    final groupUuid = _stickyGroupUuid;
    if (groupUuid == null || !_scrollController.hasClients) return null;

    final groupInfo = _groupOffsets.where((g) => g.uuid == groupUuid).firstOrNull;
    if (groupInfo == null || !groupInfo.isExpanded) return null;

    // 标题仍完整位于视口内时由列表自身显示
    if (groupInfo.startOffset - _scrollController.offset >= 0) return null;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Listener(
        onPointerMove: _forwardStickyScroll,
        onPointerSignal: _forwardStickyPointerSignal,
        child: _buildGroupHeader(context, groupUuid, provider),
      ),
    );
  }

  /// 在吸顶标题上拖动时把位移转交给列表滚动
  void _forwardStickyScroll(PointerMoveEvent event) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels - event.delta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.01) return;
    _scrollController.jumpTo(target);
  }

  /// 在吸顶标题上滚动滚轮时驱动列表滚动
  void _forwardStickyPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + event.scrollDelta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  // ================= 目录拖拽排序 =================

  @override
  bool get contentsReversed => _isReversed;

  /// 构建当前显示顺序的目录行
  ///
  /// 同时刷新分组偏移、批量命中表与设定项序号缓存，供吸顶、批量选择与行构建复用。
  @override
  List<ContentsRow> buildContentsRows() {
    final provider = context.read<WorkspaceProvider>();
    final items = provider.settingItems;
    final groups = provider.settingGroups;

    _settingGroupIndex = {for (final group in groups) group.uuid: group};
    _itemByUuid = {for (final item in items) item.uuid: item};
    _itemNumberByUuid = {};

    final rows = <ContentsRow>[];
    final groupOffsets = <({String uuid, double startOffset, bool isExpanded})>[];
    final listSlots = <({double startOffset, String? id})>[];
    double offset = 4; // 顶部 padding

    // 无分组时按设定项顺序平铺
    if (groups.isEmpty) {
      final displayItems = _isReversed ? items.reversed.toList() : items;
      for (var i = 0; i < displayItems.length; i++) {
        final item = displayItems[i];
        _itemNumberByUuid[item.uuid] = i + 1;
        listSlots.add((startOffset: offset, id: item.uuid));
        rows.add(ContentsRow(
          key: 'i:${item.uuid}',
          groupUuid: '',
          extent: _settingItemExtent,
          itemUuid: item.uuid,
        ));
        offset += _settingItemExtent;
      }
    } else {
      final groupGroups = _groupSettingItemsByGroup(items, groups);
      final groupEntries = groupGroups.entries.toList();
      final assignedEntries = groupEntries.where((e) => e.key.isNotEmpty).toList();
      final unassignedEntry = groupEntries.where((e) => e.key.isEmpty).firstOrNull;

      // 构建显示顺序的分组条目（倒序时反转，未分组始终在最后）
      final displayEntries = <MapEntry<String, List<SettingItemModel>>>[];
      if (_isReversed) {
        displayEntries.addAll(assignedEntries.reversed);
      } else {
        displayEntries.addAll(assignedEntries);
      }
      if (unassignedEntry != null) {
        displayEntries.add(unassignedEntry);
      }

      _groupItemsByUuid = {for (final entry in groupGroups.entries) entry.key: entry.value};
      // 组内序号按数据顺序编号，不随倒序变化
      for (final entry in groupGroups.entries) {
        for (var i = 0; i < entry.value.length; i++) {
          _itemNumberByUuid[entry.value[i].uuid] = i + 1;
        }
      }

      for (final entry in displayEntries) {
        final groupUuid = entry.key;
        final groupItems = entry.value;
        final isUnassigned = groupUuid.isEmpty;

        // 跳过没有设定项的未分组
        if (isUnassigned && groupItems.isEmpty) continue;

        final isExpanded = _isGroupExpanded(groupUuid);
        groupOffsets.add((uuid: groupUuid, startOffset: offset, isExpanded: isExpanded));
        listSlots.add((startOffset: offset, id: null));
        rows.add(ContentsRow(
          key: 'h:$groupUuid',
          groupUuid: groupUuid,
          extent: _groupHeaderExtent,
        ));
        offset += _groupHeaderExtent;

        if (!isExpanded) continue;

        final displayGroupItems = _isReversed ? groupItems.reversed.toList() : groupItems;
        for (final item in displayGroupItems) {
          listSlots.add((startOffset: offset, id: item.uuid));
          rows.add(ContentsRow(
            key: 'i:${item.uuid}',
            groupUuid: groupUuid,
            extent: _settingItemExtent,
            itemUuid: item.uuid,
          ));
          offset += _settingItemExtent;
        }
      }
    }

    _groupOffsets = groupOffsets;
    _listSlots = listSlots;
    return rows;
  }

  /// 获取指定分组的展开状态
  ///
  /// 未分组的折叠状态由本地 [_isUnassignedCollapsed] 维护；
  /// 拖拽分组标题期间所有分组统一折叠，使各分组标题在列表中相邻。
  bool _isGroupExpanded(String groupUuid) {
    if (isHeaderSorting) return false;
    if (groupUuid.isEmpty) return !_isUnassignedCollapsed;
    return _settingGroupIndex[groupUuid]?.isExpanded ?? true;
  }

  @override
  void applyContentsHeaderReorder({required int oldDataIndex, required int newDataIndex}) {
    context.read<WorkspaceProvider>().reorderSettingGroups(oldDataIndex, newDataIndex);
  }

  @override
  void applyContentsItemReorder({
    required ContentsRow row,
    required String targetGroupUuid,
    required int position,
    required int oldIndexInGroup,
    required bool sameGroup,
  }) {
    final provider = context.read<WorkspaceProvider>();
    final itemUuid = row.itemUuid!;
    // 目标分组的设定项总数（包含折叠分组中未显示的行）
    final targetCount = provider.settingItems.where((i) => i.groupUuid == targetGroupUuid).length;

    if (sameGroup) {
      final rawNew = rawReorderIndex(oldIndexInGroup, position);
      final indices = mapReorderIndices(
        displayOldIndex: oldIndexInGroup,
        displayNewIndex: rawNew,
        length: targetCount,
        reversed: _isReversed,
      );
      provider.reorderSettingItemsInGroup(targetGroupUuid, indices.dataOldIndex, indices.dataNewIndex);
      return;
    }

    // 跨分组：先移动归属，再按目标位置调整组内顺序
    () async {
      final moved = await provider.moveSettingItemToGroup(
        itemUuid: itemUuid,
        targetGroupUuid: targetGroupUuid,
      );
      if (!moved) return;

      // 移动后条目落在目标分组数据顺序末尾，在显示顺序中位于首端或末端
      final displayIndexAfterMove = _isReversed ? 0 : targetCount;
      final rawNew = rawReorderIndex(displayIndexAfterMove, position);
      final indices = mapReorderIndices(
        displayOldIndex: displayIndexAfterMove,
        displayNewIndex: rawNew,
        length: targetCount + 1,
        reversed: _isReversed,
      );
      await provider.reorderSettingItemsInGroup(targetGroupUuid, indices.dataOldIndex, indices.dataNewIndex);
    }();
  }

  /// 按全局坐标命中设定项，返回命中设定项的UUID
  ///
  /// 命中分组标题或列表之外区域时返回 null。
  /// 触摸端没有悬停事件，批量模式长按拖拽多选时以此定位指针下方的设定项。
  String? _hitTestSettingItemAt(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !_scrollController.hasClients) return null;

    final localY = listBox.globalToLocal(globalPosition).dy;
    if (localY < 0 || localY > listBox.size.height) return null;

    // 转换为与滚动无关的列表内容坐标
    final contentY = localY + _scrollController.offset;

    String? hitId;
    for (final slot in _listSlots) {
      if (contentY >= slot.startOffset) {
        hitId = slot.id;
      } else {
        break;
      }
    }
    return hitId;
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('暂无设定', style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '点击上方 + 添加设定',
            style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 构建拖拽时的装饰器
  /// 为拖拽中的元素添加缩放、阴影等视觉反馈效果
  Widget _buildReorderProxyDecorator(Widget child, int index, Animation<double> animation) {
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        // 拖拽时代理元素渲染在 Overlay 中，无法触发侧边栏滚动，
        // 因此在代理元素上捕获滚轮事件并手动驱动滚动
        if (event is PointerScrollEvent && _scrollController.hasClients) {
          final double maxScroll = _scrollController.position.maxScrollExtent;
          final double newOffset = (_scrollController.offset + event.scrollDelta.dy)
              .clamp(0.0, maxScroll);
          _scrollController.jumpTo(newOffset);
        }
      },
      child: AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, Widget? child) {
          // 根据动画进度计算曲线插值
          final double animValue = Curves.easeInOut.transform(animation.value);
          // 拖拽时增加阴影高度
          final double elevation = lerpDouble(0, 6, animValue)!;
          // 拖拽时略微放大元素
          final double scale = lerpDouble(1, 1.02, animValue)!;

          return Transform.scale(
            scale: scale,
            child: Material(
              elevation: elevation,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
              child: child,
            ),
          );
        },
        child: child,
      ),
    );
  }

  /// 将设定项按分组分组
  Map<String, List<SettingItemModel>> _groupSettingItemsByGroup(
    List<SettingItemModel> items,
    List<SettingGroupModel> allGroups,
  ) {
    final groups = <String, List<SettingItemModel>>{};

    // 先添加所有分组（key 为分组 UUID）
    for (final group in allGroups) {
      groups.putIfAbsent(group.uuid, () => []);
    }

    // 再将设定项归入对应分组
    for (final item in items) {
      final groupUuid = item.groupUuid;
      groups.putIfAbsent(groupUuid, () => []).add(item);
    }

    return groups;
  }

  /// 构建当前显示顺序的扁平化设定项列表（跨分组，仅包含展开分组中的设定项）
  /// 用于 Shift+点击范围选择时计算设定项在可视列表中的位置
  List<SettingItemModel> _buildFlatDisplayItems(List<SettingItemModel> items, List<SettingGroupModel> groups) {
    // 无分组时直接返回（考虑倒序）
    if (groups.isEmpty) {
      return _isReversed ? items.reversed.toList() : items;
    }

    // 有分组时，按显示顺序拼接所有展开分组的设定项
    final groupGroups = _groupSettingItemsByGroup(items, groups);
    final groupEntries = groupGroups.entries.toList();
    final assignedEntries = groupEntries.where((e) => e.key.isNotEmpty).toList();
    final unassignedEntry = groupEntries.where((e) => e.key.isEmpty).firstOrNull;

    // 构建显示顺序的分组条目（倒序时反转分组顺序，未分组始终在最后）
    final displayEntries = <MapEntry<String, List<SettingItemModel>>>[];
    if (_isReversed) {
      displayEntries.addAll(assignedEntries.reversed);
    } else {
      displayEntries.addAll(assignedEntries);
    }
    if (unassignedEntry != null) {
      displayEntries.add(unassignedEntry);
    }

    // 拼接所有展开分组的设定项
    final flatItems = <SettingItemModel>[];
    for (final entry in displayEntries) {
      final groupUuid = entry.key;
      final groupItems = entry.value;
      final isUnassigned = groupUuid.isEmpty;

      // 跳过没有设定项的未分组
      if (isUnassigned && groupItems.isEmpty) continue;

      // 跳过折叠的分组（不在可视列表中）
      final isExpanded = isUnassigned
          ? !_isUnassignedCollapsed
          : (groups.where((g) => g.uuid == groupUuid).firstOrNull?.isExpanded ?? true);
      if (!isExpanded) continue;

      // 组内设定项按倒序设置反转
      if (_isReversed) {
        flatItems.addAll(groupItems.reversed);
      } else {
        flatItems.addAll(groupItems);
      }
    }
    return flatItems;
  }

  /// 包装列表以监听拖拽多选的指针移动和抬起事件
  /// 仅在批量模式下启用监听，避免影响普通模式下的滚动与手势
  Widget _wrapWithSelectionListener(Widget child) {
    if (!_isBatchMode) return child;
    return Listener(
      onPointerMove: _selectionController.onPointerMove,
      onPointerUp: (_) => _selectionController.onPointerUp(),
      onPointerCancel: (_) => _selectionController.onPointerUp(),
      child: child,
    );
  }

  /// 构建设定项
  /// [groupUuid] 所属分组 UUID，null 表示无分组
  /// [itemIndex] 组内序号（从1开始）
  Widget _buildSettingItemWidget(
    BuildContext context,
    SettingItemModel item,
    String? groupUuid,
    String? selectedId,
    int itemIndex,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    // 判断当前设定项是否被选中
    final isSelected = _isBatchMode ? _selectedItemIds.contains(item.uuid) : selectedId == item.uuid;
    final isPressed = _menuOpenedItemId == item.uuid;

    // 批量模式下：右侧用复选框替换"更多操作"按钮，并包裹指针监听以支持拖拽多选
    if (_isBatchMode) {
      return Listener(
        onPointerDown: (event) => _selectionController.onItemPointerDown(item.uuid, event),
        child: MouseRegion(
          onEnter: (_) => _selectionController.onItemPointerEnter(item.uuid),
          child: ListItem(
            leftIndent: 30,
            leading: Icon(
              Icons.summarize_outlined,
              size: 18,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            title: item.title,
            isSelected: isSelected,
            onTap: () => _selectionController.onItemTap(item.uuid),
            trailing: _buildSelectableCheckbox(
              context: context,
              id: item.uuid,
              isSelected: isSelected,
            ),
          ),
        ),
      );
    }

    return ListItem(
      leftIndent: 30,
      leading: Icon(
        Icons.summarize_outlined,
        size: 18,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: item.title,
      isSelected: isSelected,
      isPressed: isPressed,
      onTap: () => _openSetting(context, item),
      onSecondaryTapDown: (details) {
        _showItemMenu(this.context, item, type: ContextMenuType.contextMenu, position: details.globalPosition);
      },
      trailing: SizedBox(
        width: 28,
        height: 28,
        child: Builder(
          builder: (buttonContext) {
            // 菜单打开时按钮保持按下状态
            final isMenuOpen = _menuOpenedItemId == item.uuid;
            return Material(
              color: isMenuOpen ? colorScheme.onSurfaceVariant.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              animationDuration: Duration.zero,
              child: InkWell(
                onTap: () => _showItemMenu(
                  buttonContext,
                  item,
                  type: ContextMenuType.dropdown,
                  position: buttonContext.findRenderObject() != null
                      ? (buttonContext.findRenderObject() as RenderBox).localToGlobal(Offset.zero)
                      : Offset.zero,
                  anchorSize: buttonContext.findRenderObject() != null
                      ? (buttonContext.findRenderObject() as RenderBox).size
                      : Size.zero,
                ),
                hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
                highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                splashColor: Colors.transparent,
                borderRadius: BorderRadius.circular(28),
                child: Center(
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建复选框图标（批量模式使用）
  Widget _buildCheckboxIcon({
    required BuildContext context,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: onTap,
            hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
            highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
            splashColor: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建批量模式下可拖拽选择的复选框
  ///
  /// 点击复选框切换该项选中状态；
  /// 触摸端在复选框区域直接纵向拖拽即可进入连续选择，
  /// 拖拽起点所在项的状态决定本次拖拽的目标状态（选中或取消选中），
  /// 指针途经的项由列表容器按坐标命中后统一应用。
  /// 桌面端以鼠标拖拽选择，无需该手势入口。
  Widget _buildSelectableCheckbox({
    required BuildContext context,
    required String id,
    required bool isSelected,
  }) {
    final checkbox = _buildCheckboxIcon(
      context: context,
      isSelected: isSelected,
      onTap: () => _selectionController.onItemTap(id),
    );

    if (PlatformCapabilities.supportsHover) return checkbox;

    return GestureDetector(
      onVerticalDragStart: (_) => _selectionController.onCheckboxDragStart(id),
      onVerticalDragEnd: (_) => _selectionController.onPointerUp(),
      onVerticalDragCancel: _selectionController.onPointerUp,
      child: checkbox,
    );
  }

  /// 显示新建设定/分组对话框
  void _showNewSettingDialog({String initialGroupUuid = ''}) {
    final provider = context.read<WorkspaceProvider>();
    showNewSettingDialog(
      context: context,
      workspaceProvider: provider,
      groups: provider.settingGroups,
      initialGroupUuid: initialGroupUuid,
      onCreated: (settingItem) {
        // 创建成功后打开设定项，并在内容加载完成后聚焦第一个节点
        provider.openTab(EditorTab(
          id: settingItem.uuid,
          title: settingItem.title,
          type: EditorTabType.settings,
          autoFocusFirstNode: true,
        ));
      },
    );
  }

  /// 显示分组操作菜单
  void _showGroupMenu(
    BuildContext menuContext,
    String groupUuid, {
    required ContextMenuType type,
    Offset? position,
    Size? anchorSize,
  }) {
    final provider = context.read<WorkspaceProvider>();
    final group = provider.settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    if (group == null) return;

    final items = _buildGroupMenuItems(groupUuid, group.name, includeAddItem: type == ContextMenuType.contextMenu);

    setState(() {
      _menuOpenedGroupUuid = groupUuid;
      _menuOpenedByDropdown = type == ContextMenuType.dropdown;
    });

    ContextMenu.showMenuAt(
      context: menuContext,
      position: position ?? Offset.zero,
      type: type,
      anchorSize: anchorSize,
      showIcons: false,
      fontSize: 13,
      itemPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      consumeOutsideClicks: true,
      onDismissed: () {
        if (mounted && _menuOpenedGroupUuid != null) {
          setState(() {
            _menuOpenedGroupUuid = null;
            _menuOpenedByDropdown = false;
          });
        }
      },
      menuItems: items,
    );
  }

  /// 构建分组菜单项
  List<ContextMenuItem> _buildGroupMenuItems(String groupUuid, String groupName, {bool includeAddItem = false}) {
    final theme = Theme.of(context);
    final provider = context.read<WorkspaceProvider>();
    final items = <ContextMenuItem>[];

    if (includeAddItem) {
      items.add(ContextMenuItem(
        labelText: '新建设定',
        onTap: () => _showNewSettingDialog(initialGroupUuid: groupUuid),
      ));
      items.add(const ContextMenuItem.divider());
    }

    items.addAll([
      ContextMenuItem(
        labelText: '重命名',
        onTap: () {
          showInputDialog(
            context: context,
            title: '重命名分组',
            hintText: '请输入分组名称',
            initialValue: groupName,
            confirmText: '确定',
            cancelText: '取消',
            onConfirm: (newName) async {
              if (newName == groupName) return null;
              final success = await provider.renameSettingGroup(groupUuid: groupUuid, newName: newName);
              return success ? null : '已存在同名分组';
            },
          );
        },
      ),
      ContextMenuItem(labelText: '导出', onTap: () {
        _handleGroupExport(groupUuid, groupName);
      }),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '删除',
        labelColor: theme.colorScheme.error,
        onTap: () => _confirmDeleteGroup(groupUuid, groupName),
      ),
    ]);

    return items;
  }

  /// 确认删除分组
  void _confirmDeleteGroup(String groupUuid, String groupName) {
    final provider = context.read<WorkspaceProvider>();
    final groupItems = provider.settingItems.where((i) => i.groupUuid == groupUuid).toList();

    showConfirmDialog(
      context: context,
      title: '删除分组',
      description: groupItems.isNotEmpty
          ? '分组「$groupName」将被永久删除，其中的 ${groupItems.length} 个设定项将被移入回收站。'
          : '空分组「$groupName」将被永久删除，\n此操作无法撤销。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(
          context: context,
          message: '正在删除分组，请稍候...',
        );
        try {
          final success = await provider.deleteSettingGroup(groupUuid: groupUuid);
          if (!mounted) return;
          if (success) {
            SnackBarService.show(
              context,
              groupItems.isEmpty
                  ? '分组「$groupName」已删除'
                  : '分组「$groupName」已删除，${groupItems.length} 个设定项已移入回收站',
            );
          }
        } finally {
          dismissLoading();
        }
      },
    );
  }

  /// 处理分组导出
  void _handleGroupExport(String groupUuid, String groupName) {
    final provider = context.read<WorkspaceProvider>();
    final groupItems = provider.settingItems
        .where((i) => i.groupUuid == groupUuid)
        .toList();

    if (groupItems.isEmpty) {
      SnackBarService.show(context, '该分组下没有设定项可导出');
      return;
    }

    showExportDialog(
      context: context,
      mode: ExportMode.settingGroup,
      settingItems: groupItems,
      bookTitle: provider.bookTitle,
      groupName: groupName,
    );
  }

  /// 处理单个设定项导出
  void _handleSettingItemExport(SettingItemModel item) {
    final provider = context.read<WorkspaceProvider>();

    showExportDialog(
      context: context,
      mode: ExportMode.setting,
      settingItems: [item],
      bookTitle: provider.bookTitle,
    );
  }

  /// 显示设定项操作菜单
  void _showItemMenu(
    BuildContext menuContext,
    SettingItemModel item, {
    required ContextMenuType type,
    Offset? position,
    Size? anchorSize,
  }) {
    setState(() {
      _menuOpenedItemId = item.uuid;
      _menuOpenedByDropdown = type == ContextMenuType.dropdown;
    });

    ContextMenu.showMenuAt(
      context: menuContext,
      position: position ?? Offset.zero,
      type: type,
      anchorSize: anchorSize,
      showIcons: false,
      fontSize: 13,
      itemPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      consumeOutsideClicks: true,
      onDismissed: () {
        if (mounted && _menuOpenedItemId != null) {
          setState(() {
            _menuOpenedItemId = null;
            _menuOpenedByDropdown = false;
          });
        }
      },
      menuItems: _buildItemMenuItems(item),
    );
  }

  /// 构建设定项菜单项
  List<ContextMenuItem> _buildItemMenuItems(SettingItemModel item) {
    final provider = context.read<WorkspaceProvider>();
    final hasGroups = provider.settingGroups.isNotEmpty;
    final theme = Theme.of(context);

    // 构建移动至子菜单项
    List<ContextMenuItem> moveToChildren = [];
    if (hasGroups) {
      final groups = provider.settingGroups;
      final currentGroupUuid = item.groupUuid;
      final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);

      for (final group in groups) {
        if (group.uuid == currentGroupUuid) {
          // 当前分组：打钩 + 灰色不可选
          moveToChildren.add(
            ContextMenuItem(
              label: Row(
                children: [
                  Icon(Icons.check, size: 16, color: disabledColor),
                  const SizedBox(width: 8),
                  Text(group.name, style: TextStyle(color: disabledColor)),
                ],
              ),
              enabled: false,
            ),
          );
        } else {
          // 其他分组：占位 + 可选
          moveToChildren.add(
            ContextMenuItem(
              label: Row(children: [const SizedBox(width: 24), Text(group.name), const SizedBox(width: 24)]),
              onTap: () => provider.moveSettingItemToGroup(itemUuid: item.uuid, targetGroupUuid: group.uuid),
            ),
          );
        }
      }

      // 如果设定项当前在分组中，添加"未分组"选项
      if (currentGroupUuid.isNotEmpty) {
        moveToChildren.add(const ContextMenuItem.divider());
        moveToChildren.add(
          ContextMenuItem(
            label: Row(children: [const SizedBox(width: 24), Text('未分组')]),
            onTap: () => provider.moveSettingItemToGroup(itemUuid: item.uuid, targetGroupUuid: ''),
          ),
        );
      }
    }

    return [
      ContextMenuItem(
        labelText: '打开',
        onTap: () => provider.openTab(EditorTab(id: item.uuid, title: item.title, type: EditorTabType.settings)),
      ),
      ContextMenuItem(
        labelText: '重命名',
        onTap: () {
          showInputDialog(
            context: context,
            title: '重命名设定',
            hintText: '请输入设定标题',
            initialValue: item.title,
            confirmText: '确定',
            cancelText: '取消',
            onConfirm: (newTitle) async {
              if (newTitle == item.title) return null;
              final success = await provider.renameSettingItem(itemUuid: item.uuid, newTitle: newTitle);
              return success ? null : '已存在同名设定';
            },
          );
        },
      ),
      ContextMenuItem(labelText: '移动至', enabled: hasGroups, children: hasGroups ? moveToChildren : null),
      const ContextMenuItem.divider(),
      // "在文件资源管理器中显示"依赖桌面端文件管理器能力，移动端不提供
      if (PlatformCapabilities.supportsFileManagerReveal)
        ContextMenuItem(
          labelText: '在文件资源管理器中显示',
          onTap: () => FileExplorer.revealAll([provider.getSettingItemFilePath(item)]),
        ),
      ContextMenuItem(
        labelText: '导出设定',
        onTap: () {
          _handleSettingItemExport(item);
        },
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '删除',
        labelColor: theme.colorScheme.error,
        onTap: () {
          showConfirmDialog(
            context: context,
            title: '删除设定',
            description: '设定「${item.title}」将被移入回收站，\n你可以在回收站中恢复。',
            type: ConfirmType.delete,
            confirmText: '删除',
            cancelText: '取消',
            onConfirm: () async {
              final success = await provider.deleteSettingItem(itemUuid: item.uuid);
              if (!mounted) return;
              if (success) {
                SnackBarService.show(context, '设定「${item.title}」已移入回收站');
              }
            },
          );
        },
      ),
    ];
  }

  /// 切换分组展开/折叠
  /// [groupUuid] 为空字符串表示切换未分组
  void _toggleGroup(String groupUuid) {
    final isUnassigned = groupUuid.isEmpty;
    final provider = context.read<WorkspaceProvider>();

    // 判断当前是否为展开状态
    final isCurrentlyExpanded = isUnassigned
        ? !_isUnassignedCollapsed
        : (provider.settingGroups.where((g) => g.uuid == groupUuid).firstOrNull?.isExpanded ?? true);

    // 折叠当前吸顶分组时，记录其起始偏移，折叠后跳转到此位置使分组标题保持可见
    if (isCurrentlyExpanded && _stickyGroupUuid == groupUuid) {
      final groupInfo = _groupOffsets.where((g) => g.uuid == groupUuid).firstOrNull;
      if (groupInfo != null) {
        _pendingScrollOffset = groupInfo.startOffset;
      }
    }

    if (groupUuid.isEmpty) {
      // 切换未分组的折叠状态
      setState(() {
        _isUnassignedCollapsed = !_isUnassignedCollapsed;
      });
      _saveUnassignedCollapsedState();
    } else {
      // 切换分组的展开状态（通过 Provider 写入数据库）
      provider.toggleSettingGroupExpanded(groupUuid: groupUuid);
    }
  }

  /// 打开设定项
  /// 单击以预览模式打开，双击以固定模式打开
  void _openSetting(BuildContext context, SettingItemModel item) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTap = _lastTappedItemId == item.uuid && now - _lastTapTime < GlobalConstants.doubleTapThreshold;

    _lastTapTime = now;
    _lastTappedItemId = item.uuid;

    final workspaceProvider = context.read<WorkspaceProvider>();

    if (isDoubleTap) {
      // 双击：将已打开的预览标签页转为固定状态
      workspaceProvider.pinTab(item.uuid);
    } else {
      // 单击：以预览模式打开
      workspaceProvider.openTab(
        EditorTab(id: item.uuid, title: item.title, type: EditorTabType.settings, isPreview: true),
        isPreview: true,
      );
    }

    // 移动端打开设定项后关闭左侧抽屉，避免抽屉遮挡编辑区
    if (PlatformCapabilities.isMobile) {
      Scaffold.maybeOf(context)?.closeDrawer();
    }
  }

  /// 切换标签页时滚动到对应设定项
  void _scrollToCurrentSetting() {
    final provider = context.read<WorkspaceProvider>();
    final tab = provider.currentTab;
    if (tab == null) return;

    // 仅处理设定类标签页
    if (tab.type != EditorTabType.settings) {
      return;
    }

    final settingItems = provider.settingItems;
    final settingGroups = provider.settingGroups;

    // 查找设定项
    final targetItem = settingItems.where((i) => i.uuid == tab.id).firstOrNull;
    if (targetItem == null) return;

    final groupUuid = targetItem.groupUuid;
    final hasGroups = settingGroups.isNotEmpty;

    // 无分组时直接滚动
    if (!hasGroups) {
      _scrollToSettingItemOffset(settingItems, targetItem.uuid, settingGroups);
      return;
    }

    // 有分组时，确保设定项所在分组已展开
    final isUnassigned = groupUuid.isEmpty;
    final isExpanded = isUnassigned
        ? !_isUnassignedCollapsed
        : (settingGroups.where((g) => g.uuid == groupUuid).firstOrNull?.isExpanded ?? true);

    if (!isExpanded) {
      if (isUnassigned) {
        setState(() {
          _isUnassignedCollapsed = false;
        });
        _saveUnassignedCollapsedState();
      } else {
        provider.toggleSettingGroupExpanded(groupUuid: groupUuid);
      }
      // 展开后需要等下一帧再滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSettingItemOffset(settingItems, targetItem.uuid, settingGroups);
      });
    } else {
      _scrollToSettingItemOffset(settingItems, targetItem.uuid, settingGroups);
    }
  }

  /// 计算并滚动到指定设定项的偏移位置
  void _scrollToSettingItemOffset(List<SettingItemModel> items, String targetUuid, List<SettingGroupModel> groups) {
    // 延迟一帧确保布局完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final provider = context.read<WorkspaceProvider>();
      final currentGroups = provider.settingGroups;
      final currentItems = provider.settingItems;
      final hasGroups = currentGroups.isNotEmpty;

      // 无分组时直接计算偏移
      if (!hasGroups) {
        final index = currentItems.indexWhere((i) => i.uuid == targetUuid);
        if (index == -1) return;
        // 倒序时，显示位置与原始位置相反
        final displayIndex = _isReversed ? currentItems.length - 1 - index : index;
        final targetOffset = 4.0 + displayIndex * _settingItemExtent;
        final totalContentHeight = 8.0 + currentItems.length * _settingItemExtent;
        final viewportHeight = _scrollController.position.viewportDimension;
        final calculatedMaxScroll = (totalContentHeight - viewportHeight).clamp(0.0, double.infinity);
        final currentOffset = _scrollController.offset;
        final jumpTarget = (targetOffset - viewportHeight / 3).clamp(0.0, calculatedMaxScroll);
        // 目标项完全在可视区域内，无需跳转
        if (targetOffset >= currentOffset && targetOffset + _settingItemExtent <= currentOffset + viewportHeight) return;
        _scrollController.jumpTo(jumpTarget);
        return;
      }

      // 有分组时按分组计算偏移
      final groupGroups = _groupSettingItemsByGroup(currentItems, currentGroups);

      // 构建显示用的分组遍历顺序（与 _buildSettingList 保持一致）
      final groupEntries = groupGroups.entries.toList();
      final assignedEntries = groupEntries.where((e) => e.key.isNotEmpty).toList();
      final unassignedEntry = groupEntries.where((e) => e.key.isEmpty).firstOrNull;
      final displayEntries = <MapEntry<String, List<SettingItemModel>>>[];
      if (_isReversed) {
        displayEntries.addAll(assignedEntries.reversed);
      } else {
        displayEntries.addAll(assignedEntries);
      }
      if (unassignedEntry != null) {
        displayEntries.add(unassignedEntry);
      }

      // 计算目标设定项的偏移位置
      double targetOffset = 4; // 顶部 padding
      bool found = false;

      for (final entry in displayEntries) {
        final groupUuid = entry.key;
        final groupItems = entry.value;
        final isUnassigned = groupUuid.isEmpty;

        final isExpanded = isUnassigned
            ? !_isUnassignedCollapsed
            : (currentGroups.where((g) => g.uuid == groupUuid).firstOrNull?.isExpanded ?? true);

        // 分组标题高度
        targetOffset += _groupHeaderExtent;

        if (isExpanded) {
          final indexInGroup = groupItems.indexWhere((i) => i.uuid == targetUuid);
          if (indexInGroup != -1) {
            // 倒序时，组内显示位置与原始位置相反
            final displayIndexInGroup = _isReversed ? groupItems.length - 1 - indexInGroup : indexInGroup;
            targetOffset += displayIndexInGroup * _settingItemExtent;
            found = true;
            break;
          }
          targetOffset += groupItems.length * _settingItemExtent;
        }
      }

      if (!found || !_scrollController.hasClients) return;

      // 自行计算总内容高度（不依赖布局的 maxScrollExtent）
      double totalContentHeight = 8; // 上下 padding
      for (final entry in displayEntries) {
        final groupUuid = entry.key;
        final groupItems = entry.value;
        final isUnassigned = groupUuid.isEmpty;

        final isExpanded = isUnassigned
            ? !_isUnassignedCollapsed
            : (currentGroups.where((g) => g.uuid == groupUuid).firstOrNull?.isExpanded ?? true);

        totalContentHeight += _groupHeaderExtent;
        if (isExpanded) totalContentHeight += groupItems.length * _settingItemExtent;
      }

      final viewportHeight = _scrollController.position.viewportDimension;
      final calculatedMaxScroll = (totalContentHeight - viewportHeight).clamp(0.0, double.infinity);
      final currentOffset = _scrollController.offset;
      final jumpTarget = (targetOffset - viewportHeight / 3).clamp(0.0, calculatedMaxScroll);
      // 目标项完全在可视区域内，无需跳转
      if (targetOffset >= currentOffset && targetOffset + _settingItemExtent <= currentOffset + viewportHeight) return;
      _scrollController.jumpTo(jumpTarget);
    });
  }

  // ================= 批量管理模式 =================

  /// 进入批量管理模式
  void _enterBatchMode() {
    setState(() {
      _isBatchMode = true;
      _selectedItemIds.clear();
    });
    _selectionController.reset();
  }

  /// 退出批量管理模式
  void _exitBatchMode() {
    setState(() {
      _isBatchMode = false;
      _selectedItemIds.clear();
    });
    _selectionController.reset();
  }

  /// 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      final allItems = context.read<WorkspaceProvider>().settingItems;
      if (_selectedItemIds.length == allItems.length) {
        _selectedItemIds.clear();
      } else {
        _selectedItemIds.clear();
        _selectedItemIds.addAll(allItems.map((item) => item.uuid));
      }
    });
  }

  /// 切换分组下所有设定项的选中状态
  void _toggleGroupItemsSelection(List<SettingItemModel> groupItems) {
    setState(() {
      final groupUuids = groupItems.map((i) => i.uuid).toSet();
      final allSelected = groupUuids.every((id) => _selectedItemIds.contains(id));
      if (allSelected) {
        _selectedItemIds.removeAll(groupUuids);
      } else {
        _selectedItemIds.addAll(groupUuids);
      }
    });
  }

  /// 判断是否全选
  bool _isAllSelected() {
    final allItems = context.read<WorkspaceProvider>().settingItems;
    return allItems.isNotEmpty && _selectedItemIds.length == allItems.length;
  }

  /// 构建批量模式下的分组标题
  Widget _buildBatchGroupHeader({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isExpanded,
    required List<SettingItemModel> groupItems,
    required VoidCallback onToggleExpand,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final groupUuids = groupItems.map((i) => i.uuid).toSet();
    final allSelected = groupUuids.isNotEmpty && groupUuids.every((id) => _selectedItemIds.contains(id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggleExpand,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isExpanded ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // 展开/折叠图标
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                // 分组图标
                Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                // 分组名称
                Expanded(
                  child: Text(
                    title,
                    style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                // 右侧复选框
                _buildCheckboxIcon(
                  context: context,
                  isSelected: allSelected,
                  onTap: () => _toggleGroupItemsSelection(groupItems),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建批量操作底部操作栏
  Widget _buildBatchActionBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSelection = _selectedItemIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 已选择数量
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text.rich(
                TextSpan(
                  text: '已选择 ',
                  style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: '${_selectedItemIds.length}',
                      style: context.bodySmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: ' 项',
                      style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 操作按钮
          Row(
            children: [
              // 左侧：移动、导出（带外边框）
              OutlinedButton(
                key: _moveButtonKey,
                onPressed: hasSelection ? _handleBatchMoveToGroup : null,
                style: OutlinedButton.styleFrom(minimumSize: const Size(66, 38)),
                child: const Text('移动'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: hasSelection ? _handleBatchExport : null,
                style: OutlinedButton.styleFrom(minimumSize: const Size(66, 38)),
                child: const Text('导出'),
              ),
              const Spacer(),
              // 右侧：删除（无边框）
              TextButton(
                onPressed: hasSelection ? _handleBatchDelete : null,
                style: TextButton.styleFrom(foregroundColor: colorScheme.error, minimumSize: const Size(66, 38)),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 处理批量导出
  void _handleBatchExport() {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final selectedItems = workspaceProvider.settingItems
        .where((i) => _selectedItemIds.contains(i.uuid))
        .toList();

    if (selectedItems.isEmpty) return;

    showExportDialog(
      context: context,
      mode: ExportMode.setting,
      settingItems: selectedItems,
      bookTitle: workspaceProvider.bookTitle,
    );
  }

  /// 处理批量移动到分组
  void _handleBatchMoveToGroup() {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final groups = workspaceProvider.settingGroups;

    // 没有分组时无法移动
    if (groups.isEmpty) return;

    // 构建分组选择菜单项
    final menuItems = <ContextMenuItem>[];

    // 添加各分组选项
    for (final group in groups) {
      menuItems.add(ContextMenuItem(labelText: group.name, onTap: () => _performBatchMove(group.uuid)));
    }

    // 添加分隔线
    menuItems.add(const ContextMenuItem.divider());

    // 添加"未分组"选项
    menuItems.add(ContextMenuItem(labelText: '未分组', onTap: () => _performBatchMove('')));

    // 获取"移动"按钮的位置，菜单显示在按钮上方
    final buttonContext = _moveButtonKey.currentContext;
    if (buttonContext == null) return;
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    ContextMenu.showMenuAt(
      context: context,
      position: Offset(buttonPosition.dx, buttonPosition.dy - 4),
      anchorSize: buttonSize,
      type: ContextMenuType.dropdown,
      showIcons: false,
      fontSize: 13,
      itemPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      consumeOutsideClicks: true,
      menuItems: menuItems,
    );
  }

  /// 执行批量移动
  Future<void> _performBatchMove(String targetGroupUuid) async {
    final workspaceProvider = context.read<WorkspaceProvider>();

    final count = await workspaceProvider.batchMoveSettingItemsToGroup(
      itemUuids: _selectedItemIds.toList(),
      targetGroupUuid: targetGroupUuid,
    );

    if (!mounted) return;

    if (count > 0) {
      final groupName = targetGroupUuid.isEmpty ? '未分组' : workspaceProvider.getSettingGroupName(targetGroupUuid);
      SnackBarService.show(context, '已移动 $count 个设定项至「$groupName」');
      _exitBatchMode();
    } else {
      SnackBarService.show(context, '移动失败，目标分组下可能存在同名设定项');
    }
  }

  /// 处理批量删除
  void _handleBatchDelete() {
    final count = _selectedItemIds.length;

    showConfirmDialog(
      context: context,
      title: '批量删除设定',
      description: '确定要删除选中的 $count 个设定项吗？\n删除后可在回收站中恢复。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(
          context: context,
          message: '正在删除 $count 个设定项，请稍候...',
        );
        try {
          final deletedCount = await context.read<WorkspaceProvider>().batchDeleteSettingItems(
            itemUuids: _selectedItemIds.toList(),
          );
          if (!mounted) return;
          if (deletedCount > 0) {
            SnackBarService.show(context, '已删除 $deletedCount 个设定项');
            _exitBatchMode();
          }
        } finally {
          dismissLoading();
        }
      },
    );
  }
}
