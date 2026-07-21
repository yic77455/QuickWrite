import 'dart:io';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/utils/chapter_number_utils.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/dialogs/new_chapter_dialog.dart';
import 'package:quick_write/shared/dialogs/export_dialog.dart';
import 'package:quick_write/core/utils/batch_selection_controller.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import '../widgets/contents_list_widgets.dart';
import '../widgets/contents_top_bar.dart';


/// 章节目录面板
///
/// 显示书籍的章节列表，支持分卷
class ChapterPanel extends StatefulWidget {
  const ChapterPanel({super.key});

  @override
  State<ChapterPanel> createState() => _ChapterPanelState();
}

class _ChapterPanelState extends State<ChapterPanel> with AutomaticKeepAliveClientMixin {
  /// 未分卷组是否折叠
  bool _isUnassignedCollapsed = false;

  /// 章节列表是否倒序排列
  bool _isChapterReversed = false;

  /// 上次点击的时间戳，用于手动检测双击
  int _lastTapTime = 0;

  /// 上次点击的章节ID，用于手动检测双击
  String? _lastTappedChapterId;

  /// 当前打开操作菜单的章节ID，用于保持按钮按下状态
  String? _menuOpenedChapterId;

  /// 当前打开操作菜单的分卷 UUID，用于保持按钮按下状态
  String? _menuOpenedVolumeUuid;

  /// 当前菜单是否通过下拉按钮打开（区分右键菜单，右键时按钮不显示按下状态）
  bool _menuOpenedByDropdown = false;

  /// 当前吸顶的分卷 UUID（仅当前正在浏览内容的分组会吸顶）
  String? _stickyVolumeUuid;

  /// 分组偏移缓存（在 _buildChapterList 中更新，滚动时查表使用，避免重复计算）
  List<({String uuid, double startOffset, bool isExpanded})> _groupOffsets = [];

  /// 折叠吸顶分组后待跳转的滚动偏移（使折叠后的分组标题保持可见）
  double? _pendingScrollOffset;

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 当前标签页ID（用于检测标签页切换）
  String? _currentTabId;

  /// 当前书籍UUID（用于检测书籍切换）
  String? _currentBookUuid;

  /// 是否处于批量管理模式
  bool _isBatchMode = false;

  /// 批量模式下已选中的章节UUID集合
  final Set<String> _selectedChapterIds = {};

  /// 批量模式多选交互控制器（Shift+点击范围选择、鼠标拖拽多选）
  late final BatchSelectionController _selectionController;

  /// 批量模式下"移动"按钮的 GlobalKey，用于定位下拉菜单
  final GlobalKey _moveButtonKey = GlobalKey();

  /// 章节项固定高度
  static const double _chapterItemExtent = 56.0;

  /// 分组标题高度（Container height 40 + vertical margin 4）
  static const double _groupHeaderExtent = 44.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 从缓存加载展开状态并初始化标签页ID
    _loadExpandedState();
    // 监听滚动，动态更新吸顶分组
    _scrollController.addListener(_onScroll);
    // 初始化批量多选交互控制器
    _selectionController = BatchSelectionController(
      getSelectedIds: () => _selectedChapterIds,
      getFlatDisplayIds: () {
        final provider = context.read<WorkspaceProvider>();
        return _buildFlatDisplayChapters(provider.chapters, provider.volumes)
            .map((c) => c.uuid)
            .toList();
      },
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动回调，更新当前吸顶的分卷
  void _onScroll() {
    _updateStickyVolume();
  }

  /// 根据当前滚动偏移计算应吸顶的分卷
  /// 仅让"当前正在浏览内容的分组"吸顶，其余分组不吸顶
  void _updateStickyVolume() {
    if (!mounted || !_scrollController.hasClients) return;

    // 无分组数据时清除吸顶
    if (_groupOffsets.isEmpty) {
      if (_stickyVolumeUuid != null) {
        setState(() => _stickyVolumeUuid = null);
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

    // 仅在吸顶分组变化时刷新，避免无谓重建
    if (_stickyVolumeUuid != newStickyUuid) {
      setState(() => _stickyVolumeUuid = newStickyUuid);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<WorkspaceProvider>(context);

    // 检测书籍切换，重新加载未分卷组的折叠状态
    final bookUuid = provider.currentBook?.uuid;
    if (bookUuid != _currentBookUuid) {
      _currentBookUuid = bookUuid;
      if (bookUuid != null) {
        _isUnassignedCollapsed = MiscCacheService.instance.isUnassignedCollapsed(bookUuid);
      } else {
        _isUnassignedCollapsed = false;
      }
    }

    // 检测标签页切换，自动定位到对应章节
    final tab = provider.currentTab;
    if (tab?.id != _currentTabId) {
      _currentTabId = tab?.id;
      // 延迟一帧确保列表重建完成
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrentChapter();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final chapters = workspaceProvider.chapters;

    // 列表重建后处理待跳转的滚动偏移并重新计算吸顶分组
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 折叠吸顶分组后跳转到该分组起始位置，使分组标题保持可见
      if (_pendingScrollOffset != null && _scrollController.hasClients) {
        _scrollController.jumpTo(_pendingScrollOffset!);
        _pendingScrollOffset = null;
      }
      _updateStickyVolume();
    });

    return Container(
      color: colorScheme.surface.withValues(alpha: 0.3),
      child: Column(
        children: [
          // 顶部操作栏
          _buildTopBar(context),

          // 章节列表
          Expanded(child: _buildChapterList(context, chapters, workspaceProvider)),

          // 批量操作栏
          if (_isBatchMode) _buildBatchActionBar(context, chapters),
        ],
      ),
    );
  }

  /// 构建顶部操作栏
  Widget _buildTopBar(BuildContext context) {
    return ContentsTopBar(
      isBatchMode: _isBatchMode,
      isAllSelected: _isAllSelected(context),
      onToggleSelectAll: () {
        final provider = context.read<WorkspaceProvider>();
        _toggleSelectAll(provider.chapters);
      },
      onExitBatchMode: _exitBatchMode,
      addTooltip: '新建章节/分卷',
      onAdd: () {
        final provider = context.read<WorkspaceProvider>();
        // 从缓存读取上次选择的分卷
        final bookUuid = provider.currentBook?.uuid;
        final lastVolume = bookUuid != null ? MiscCacheService.instance.getLastSelectedVolume(bookUuid) : '';
        showNewChapterDialog(
          context: context,
          workspaceProvider: provider,
          volumes: provider.volumes,
          initialVolumeUuid: lastVolume,
          onCreated: (chapter) {
            // 创建成功后打开章节
            provider.openTab(EditorTab(id: chapter.uuid, title: chapter.title, type: EditorTabType.chapter));
          },
        );
      },
      isReversed: _isChapterReversed,
      onToggleReversed: () {
        setState(() {
          _isChapterReversed = !_isChapterReversed;
        });
        _saveChapterReversedState();
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

  /// 构建章节列表
  Widget _buildChapterList(BuildContext context, List<ChapterModel> chapters, WorkspaceProvider workspaceProvider) {
    // 获取当前选中的章节ID
    final selectedChapterId = workspaceProvider.currentTab?.id;
    final volumes = workspaceProvider.volumes;
    final hasVolumes = volumes.isNotEmpty;

    // 无分卷且无章节时，显示空状态
    if (!hasVolumes && chapters.isEmpty) {
      return _buildEmptyState(context);
    }

    // 构建章节原始序号映射（序号跟随章节，不受倒序影响）
    final chapterOriginalIndex = <String, int>{};

    // 无分卷时，直接显示章节列表
    if (!hasVolumes) {
      for (var i = 0; i < chapters.length; i++) {
        chapterOriginalIndex[chapters[i].uuid] = i + 1;
      }
      // 倒序时反转显示列表
      final displayChapters = _isChapterReversed ? chapters.reversed.toList() : chapters;
      return _wrapWithSelectionListener(CustomScrollView(
        controller: _scrollController,
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(top: 4)),
          SliverReorderableList(
            itemExtent: _chapterItemExtent,
            itemCount: displayChapters.length,
            onReorder: (int oldIndex, int newIndex) {
              context.read<WorkspaceProvider>().reorderChaptersInVolume('', oldIndex, newIndex);
            },
            proxyDecorator: _buildReorderProxyDecorator,
            itemBuilder: (context, index) {
              final chapter = displayChapters[index];
              // 批量模式下禁用拖拽
              if (_isBatchMode) {
                return SizedBox(
                  key: ValueKey(chapter.uuid),
                  height: _chapterItemExtent,
                  child: _buildChapterItem(context, chapter, chapterOriginalIndex[chapter.uuid]!, selectedChapterId, false),
                );
              }
              return ReorderableDelayedDragStartListener(
                key: ValueKey(chapter.uuid),
                index: index,
                child: _buildChapterItem(context, chapter, chapterOriginalIndex[chapter.uuid]!, selectedChapterId, false),
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 4)),
        ],
      ));
    }

    // 有分卷时，按分卷分组显示
    final volumeGroups = _groupChaptersByVolume(chapters, volumes);

    // 构建卷内章节原始序号映射
    for (final entry in volumeGroups.entries) {
      final volumeChapters = entry.value;
      for (var i = 0; i < volumeChapters.length; i++) {
        chapterOriginalIndex[volumeChapters[i].uuid] = i + 1;
      }
    }

    // 构建显示用的分卷条目列表，倒序时反转分卷顺序（未分卷始终在最后）
    final volumeEntries = volumeGroups.entries.toList();
    final assignedEntries = volumeEntries.where((e) => e.key.isNotEmpty).toList();
    final unassignedEntry = volumeEntries.where((e) => e.key.isEmpty).firstOrNull;
    final displayEntries = <MapEntry<String, List<ChapterModel>>>[];
    if (_isChapterReversed) {
      displayEntries.addAll(assignedEntries.reversed);
    } else {
      displayEntries.addAll(assignedEntries);
    }
    if (unassignedEntry != null) {
      displayEntries.add(unassignedEntry);
    }

    // 构建 Sliver 列表
    final slivers = <Widget>[];

    // 添加顶部 padding
    slivers.add(const SliverPadding(padding: EdgeInsets.only(top: 4)));

    // 初始化分组偏移缓存，用于滚动时快速查表计算吸顶分组
    _groupOffsets = [];
    double currentOffset = 4; // 顶部 padding

    for (final entry in displayEntries) {
      final volumeUuid = entry.key;
      final volumeChapters = entry.value;
      final isUnassigned = volumeUuid.isEmpty;

      // 跳过没有章节的未分卷组
      if (isUnassigned && volumeChapters.isEmpty) continue;

      // 未分卷组使用特殊键追踪折叠状态：存在于集合中表示折叠，不存在表示展开
      final isExpanded = isUnassigned
          ? !_isUnassignedCollapsed
          : (workspaceProvider.volumes.where((v) => v.uuid == volumeUuid).firstOrNull?.isExpanded ?? true);

      // 记录该分组的偏移信息（供滚动监听查表使用）
      _groupOffsets.add((uuid: volumeUuid, startOffset: currentOffset, isExpanded: isExpanded));

      // 获取分卷名称
      final volumeName = isUnassigned ? '' : workspaceProvider.getVolumeName(volumeUuid);

      // 构建分组标题组件
      final headerWidget = _isBatchMode
          ? _buildBatchGroupHeader(
              context: context,
              title: isUnassigned ? '未分卷' : volumeName,
              icon: Icons.folder_outlined,
              isExpanded: isExpanded,
              volumeChapters: volumeChapters,
              onToggleExpand: () => _toggleVolume(isUnassigned ? '' : volumeUuid),
            )
          : GroupHeader(
              title: isUnassigned ? '未分卷' : volumeName,
              icon: Icons.folder_outlined,
              itemCount: volumeChapters.length,
              isExpanded: isExpanded,
              itemCountSuffix: ' 章',
              onTap: () => _toggleVolume(isUnassigned ? '' : volumeUuid),
              onAddPressed: isUnassigned ? null : () => _showAddChapterToVolumeDialog(volumeUuid),
              addTooltip: '新建章节',
              onMenuPressed: isUnassigned
                  ? null
                  : (buttonContext) {
                      final button = buttonContext.findRenderObject() as RenderBox?;
                      if (button == null) return;
                      _showVolumeMenu(
                        buttonContext,
                        volumeUuid,
                        type: ContextMenuType.dropdown,
                        position: button.localToGlobal(Offset.zero),
                        anchorSize: button.size,
                      );
                    },
              isMenuOpen: _menuOpenedVolumeUuid == volumeUuid,
              isButtonPressed: _menuOpenedVolumeUuid == volumeUuid && _menuOpenedByDropdown,
              menuTooltip: '更多',
              onSecondaryTapDown: isUnassigned
                  ? null
                  : (details) {
                      _showVolumeMenu(
                        context,
                        volumeUuid,
                        type: ContextMenuType.contextMenu,
                        position: details.globalPosition,
                      );
                    },
            );

      // 只有当前吸顶的分组才 pinned，其余分组（含展开的）均不吸顶
      final shouldPin = isExpanded && _stickyVolumeUuid == volumeUuid;

      slivers.add(
        shouldPin
            ? SliverPersistentHeader(
                pinned: true,
                delegate: StickyGroupHeaderDelegate(
                  height: _groupHeaderExtent,
                  child: headerWidget,
                ),
              )
            : SliverToBoxAdapter(child: headerWidget),
      );

      // 展开时显示章节列表
      if (isExpanded) {
        // 倒序时反转卷内章节显示列表
        final displayVolumeChapters = _isChapterReversed ? volumeChapters.reversed.toList() : volumeChapters;
        slivers.add(
          SliverReorderableList(
            itemExtent: _chapterItemExtent,
            itemCount: displayVolumeChapters.length,
            onReorder: (int oldIndex, int newIndex) {
              context.read<WorkspaceProvider>().reorderChaptersInVolume(volumeUuid, oldIndex, newIndex);
            },
            proxyDecorator: _buildReorderProxyDecorator,
            itemBuilder: (context, index) {
              final chapter = displayVolumeChapters[index];
              // 批量模式下禁用拖拽
              if (_isBatchMode) {
                return SizedBox(
                  key: ValueKey(chapter.uuid),
                  height: _chapterItemExtent,
                  child: _buildChapterItem(context, chapter, chapterOriginalIndex[chapter.uuid]!, selectedChapterId, true),
                );
              }
              return ReorderableDelayedDragStartListener(
                key: ValueKey(chapter.uuid),
                index: index,
                child: _buildChapterItem(context, chapter, chapterOriginalIndex[chapter.uuid]!, selectedChapterId, true),
              );
            },
          ),
        );
      }

      // 累加当前分组的偏移量（标题高度 + 展开时的列表高度）
      currentOffset += _groupHeaderExtent;
      if (isExpanded) {
        currentOffset += volumeChapters.length * _chapterItemExtent;
      }
    }

    // 添加底部 padding
    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 4)));

    return _wrapWithSelectionListener(CustomScrollView(controller: _scrollController, slivers: slivers));
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

  /// 构建空状态提示
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 48, color: colorScheme.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text('暂无章节', style: context.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            '点击上方 + 添加章节',
            style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  /// 构建单个章节项
  /// [volumeIndex] 卷内序号（从1开始）
  /// [hasVolume] 表示是否属于某个分卷
  Widget _buildChapterItem(
    BuildContext context,
    ChapterModel chapter,
    int volumeIndex,
    String? selectedChapterId,
    bool hasVolume,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    // 判断当前章节是否被选中
    final isSelected = _isBatchMode ? _selectedChapterIds.contains(chapter.uuid) : selectedChapterId == chapter.uuid;
    final isPressed = _menuOpenedChapterId == chapter.uuid;

    // 批量模式下：右侧用复选框替换"更多操作"按钮
    // 外层 Listener + MouseRegion 用于支持鼠标拖拽多选
    if (_isBatchMode) {
      return Listener(
        onPointerDown: (event) => _selectionController.onItemPointerDown(chapter.uuid, event),
        child: MouseRegion(
          onEnter: (_) => _selectionController.onItemPointerEnter(chapter.uuid),
          child: ListItem(
            indexText: '$volumeIndex',
            title: chapter.title,
            subtitle: '${chapter.wordCount}字',
            isSelected: isSelected,
            leftIndent: hasVolume ? 16 : 8,
            onTap: () => _selectionController.onItemTap(chapter.uuid),
            trailing: _buildCheckboxIcon(
              context: context,
              isSelected: isSelected,
              onTap: () => _selectionController.onItemTap(chapter.uuid),
            ),
          ),
        ),
      );
    }

    return ListItem(
      indexText: '$volumeIndex',
      title: chapter.title,
      subtitle: '${chapter.wordCount}字',
      isSelected: isSelected,
      isPressed: isPressed,
      leftIndent: hasVolume ? 16 : 8,
      onTap: () => _openChapter(context, chapter),
      onSecondaryTapDown: (details) {
        _showChapterMenu(
          this.context,
          chapter,
          type: ContextMenuType.contextMenu,
          position: details.globalPosition,
        );
      },
      trailing: SizedBox(
        width: 28,
        height: 28,
        child: Builder(
          builder: (buttonContext) {
            // 菜单通过按钮打开时，按钮保持按下状态
            final isMenuOpen = _menuOpenedChapterId == chapter.uuid && _menuOpenedByDropdown;
            return Material(
              color: isMenuOpen ? colorScheme.onSurfaceVariant.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              animationDuration: Duration.zero,
              child: InkWell(
                onTap: () {
                  final button = buttonContext.findRenderObject() as RenderBox?;
                  if (button == null) return;
                  _showChapterMenu(
                    buttonContext,
                    chapter,
                    type: ContextMenuType.dropdown,
                    position: button.localToGlobal(Offset.zero),
                    anchorSize: button.size,
                  );
                },
                hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
                highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                splashColor: Colors.transparent,
                borderRadius: BorderRadius.circular(28),
                child: Center(
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 16,
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

  /// 从缓存加载未分卷组的折叠状态
  void _loadExpandedState() {
    final provider = context.read<WorkspaceProvider>();
    final bookUuid = provider.currentBook?.uuid;
    if (bookUuid != null) {
      _isUnassignedCollapsed = MiscCacheService.instance.isUnassignedCollapsed(bookUuid);
      _currentBookUuid = bookUuid;
    }
    // 加载章节排序方式（全局缓存）
    _isChapterReversed = MiscCacheService.instance.isChapterReversed();
    // 同步初始化标签页ID，避免面板重建时误触发滚动
    _currentTabId = provider.currentTab?.id;
  }

  /// 保存未分卷组的折叠状态到缓存
  void _saveUnassignedCollapsedState() {
    final bookUuid = _currentBookUuid;
    if (bookUuid == null) return;
    MiscCacheService.instance.saveUnassignedCollapsed(bookUuid, _isUnassignedCollapsed);
  }

  /// 保存章节列表排序方式到缓存
  void _saveChapterReversedState() {
    MiscCacheService.instance.saveChapterReversed(_isChapterReversed);
  }

  /// 将章节按分卷分组
  Map<String, List<ChapterModel>> _groupChaptersByVolume(List<ChapterModel> chapters, List<VolumeModel> allVolumes) {
    final groups = <String, List<ChapterModel>>{};

    // 先添加所有分卷（key 为分卷 UUID）
    for (final volume in allVolumes) {
      groups.putIfAbsent(volume.uuid, () => []);
    }

    // 再将章节归入对应分卷
    for (final chapter in chapters) {
      final volumeUuid = chapter.volumeUuid;
      groups.putIfAbsent(volumeUuid, () => []).add(chapter);
    }

    return groups;
  }

  /// 构建当前显示顺序的扁平化章节列表（跨分卷，仅包含展开分卷中的章节）
  /// 用于 Shift+点击范围选择时计算章节在可视列表中的位置
  List<ChapterModel> _buildFlatDisplayChapters(List<ChapterModel> chapters, List<VolumeModel> volumes) {
    // 无分卷时直接返回（考虑倒序）
    if (volumes.isEmpty) {
      return _isChapterReversed ? chapters.reversed.toList() : chapters;
    }

    // 有分卷时，按显示顺序拼接所有展开分卷的章节
    final volumeGroups = _groupChaptersByVolume(chapters, volumes);
    final volumeEntries = volumeGroups.entries.toList();
    final assignedEntries = volumeEntries.where((e) => e.key.isNotEmpty).toList();
    final unassignedEntry = volumeEntries.where((e) => e.key.isEmpty).firstOrNull;

    // 构建显示顺序的分卷条目（倒序时反转分卷顺序，未分卷始终在最后）
    final displayEntries = <MapEntry<String, List<ChapterModel>>>[];
    if (_isChapterReversed) {
      displayEntries.addAll(assignedEntries.reversed);
    } else {
      displayEntries.addAll(assignedEntries);
    }
    if (unassignedEntry != null) {
      displayEntries.add(unassignedEntry);
    }

    // 拼接所有展开分卷的章节
    final flatChapters = <ChapterModel>[];
    for (final entry in displayEntries) {
      final volumeUuid = entry.key;
      final volumeChapters = entry.value;
      final isUnassigned = volumeUuid.isEmpty;

      // 跳过没有章节的未分卷组
      if (isUnassigned && volumeChapters.isEmpty) continue;

      // 跳过折叠的分卷（不在可视列表中）
      final isExpanded = isUnassigned
          ? !_isUnassignedCollapsed
          : (volumes.where((v) => v.uuid == volumeUuid).firstOrNull?.isExpanded ?? true);
      if (!isExpanded) continue;

      // 卷内章节按倒序设置反转
      if (_isChapterReversed) {
        flatChapters.addAll(volumeChapters.reversed);
      } else {
        flatChapters.addAll(volumeChapters);
      }
    }
    return flatChapters;
  }

  /// 切换分卷展开/折叠
  /// [volumeUuid] 为空字符串表示切换未分卷组
  void _toggleVolume(String volumeUuid) {
    final isUnassigned = volumeUuid.isEmpty;
    final provider = context.read<WorkspaceProvider>();

    // 判断当前是否为展开状态
    final isCurrentlyExpanded = isUnassigned
        ? !_isUnassignedCollapsed
        : (provider.volumes.where((v) => v.uuid == volumeUuid).firstOrNull?.isExpanded ?? true);

    // 折叠当前吸顶分组时，记录其起始偏移，折叠后跳转到此位置使分组标题保持可见
    if (isCurrentlyExpanded && _stickyVolumeUuid == volumeUuid) {
      final groupInfo = _groupOffsets.where((g) => g.uuid == volumeUuid).firstOrNull;
      if (groupInfo != null) {
        _pendingScrollOffset = groupInfo.startOffset;
      }
    }

    if (volumeUuid.isEmpty) {
      // 切换未分卷组的折叠状态
      setState(() {
        _isUnassignedCollapsed = !_isUnassignedCollapsed;
      });
      _saveUnassignedCollapsedState();
    } else {
      // 切换分卷的展开状态（通过 Provider 写入数据库）
      provider.toggleVolumeExpanded(volumeUuid: volumeUuid);
    }
  }

  /// 构建分卷菜单项
  ///
  /// [includeAddChapter] 为 true 时在菜单顶部添加"新建章节"选项（右键菜单场景）
  List<ContextMenuItem> _buildVolumeMenuItems(String volumeUuid, {bool includeAddChapter = false}) {
    final theme = Theme.of(context);
    final items = <ContextMenuItem>[];

    if (includeAddChapter) {
      items.add(ContextMenuItem(
        labelText: '新建章节',
        onTap: () => _showAddChapterToVolumeDialog(volumeUuid),
      ));
      items.add(const ContextMenuItem.divider());
    }

    items.addAll([
      ContextMenuItem(labelText: '重命名', onTap: () => _handleVolumeMenuAction('rename', volumeUuid)),
      ContextMenuItem(labelText: '导出', onTap: () => _handleVolumeMenuAction('export', volumeUuid)),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '删除',
        labelColor: theme.colorScheme.error,
        onTap: () => _handleVolumeMenuAction('delete', volumeUuid),
      ),
    ]);

    return items;
  }

  /// 显示分卷操作菜单
  void _showVolumeMenu(
    BuildContext menuContext,
    String volumeUuid, {
    required ContextMenuType type,
    Offset? position,
    Size? anchorSize,
  }) {
    final items = _buildVolumeMenuItems(volumeUuid, includeAddChapter: type == ContextMenuType.contextMenu);

    setState(() {
      _menuOpenedVolumeUuid = volumeUuid;
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
        if (mounted && _menuOpenedVolumeUuid != null) {
          setState(() {
            _menuOpenedVolumeUuid = null;
            _menuOpenedByDropdown = false;
          });
        }
      },
      menuItems: items,
    );
  }

  /// 处理分卷菜单操作
  Future<void> _handleVolumeMenuAction(String action, String volumeUuid) async {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final volumeName = workspaceProvider.getVolumeName(volumeUuid);

    switch (action) {
      case 'rename':
        showInputDialog(
          context: context,
          title: '重命名分卷',
          hintText: '请输入分卷名称',
          initialValue: volumeName,
          confirmText: '确定',
          cancelText: '取消',
          onConfirm: (newName) async {
            if (newName == volumeName) return null;
            final success = await workspaceProvider.renameVolume(volumeUuid: volumeUuid, newName: newName);
            return success ? null : '已存在同名分卷';
          },
        );
        break;
      case 'export':
        // 导出分卷
        final volumeChapters = workspaceProvider.chapters
            .where((c) => c.volumeUuid == volumeUuid)
            .toList();
        showExportDialog(
          context: context,
          mode: ExportMode.volume,
          volumeName: volumeName,
          chapters: volumeChapters,
          bookTitle: workspaceProvider.bookTitle,
        );
        break;
      case 'delete':
        final volumeChapters = workspaceProvider.chapters.where((c) => c.volumeUuid == volumeUuid).toList();
        showConfirmDialog(
          context: context,
          title: '删除分卷',
          description: '分卷「$volumeName」将被永久删除，其中的 ${volumeChapters.length} 个章节将被移入回收站。',
          type: ConfirmType.delete,
          confirmText: '删除',
          cancelText: '取消',
          onConfirm: () async {
            final dismissLoading = showLoadingDialog(
              context: context,
              message: '正在删除分卷，请稍候...',
            );
            try {
              await workspaceProvider.deleteVolume(volumeUuid: volumeUuid);
            } finally {
              dismissLoading();
            }
          },
        );
        break;
    }
  }

  /// 显示在指定分卷下新建章节的输入弹窗
  void _showAddChapterToVolumeDialog(String volumeUuid) {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final volumeName = workspaceProvider.getVolumeName(volumeUuid);
    // 根据该分卷的最新章节自动生成序号
    final initialTitle = ChapterNumberUtils.generateNextForVolume(workspaceProvider.chapters, volumeUuid);
    showInputDialog(
      context: context,
      title: '新建章节',
      hintText: '请输入章节名称',
      subtitle: '新建至"$volumeName"',
      initialValue: initialTitle,
      confirmText: '创建',
      cancelText: '取消',
      onConfirm: (title) async {
        if (title.trim().isEmpty) return '章节名称不能为空';
        final chapter = await workspaceProvider.addChapter(title: title.trim(), volumeUuid: volumeUuid);
        if (chapter == null) return '章节创建失败';
        // 创建成功，更新分卷选择记忆
        final bookUuid = workspaceProvider.currentBook?.uuid;
        if (bookUuid != null) {
          MiscCacheService.instance.saveLastSelectedVolume(bookUuid, volumeUuid);
        }
        // 打开新建的章节
        workspaceProvider.openTab(EditorTab(id: chapter.uuid, title: chapter.title, type: EditorTabType.chapter));
        return null;
      },
    );
  }

  /// 打开章节
  /// 单击以预览模式打开，双击以固定模式打开
  void _openChapter(BuildContext context, ChapterModel chapter) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTap = _lastTappedChapterId == chapter.uuid && now - _lastTapTime < GlobalConstants.doubleTapThreshold;

    _lastTapTime = now;
    _lastTappedChapterId = chapter.uuid;

    final workspaceProvider = context.read<WorkspaceProvider>();

    if (isDoubleTap) {
      // 双击：将已打开的预览标签页转为固定状态
      workspaceProvider.pinTab(chapter.uuid);
    } else {
      // 单击：以预览模式打开
      workspaceProvider.openTab(
        EditorTab(id: chapter.uuid, title: chapter.title, type: EditorTabType.chapter, isPreview: true),
        isPreview: true,
      );
    }
  }

  /// 构建章节菜单项
  List<ContextMenuItem> _buildChapterMenuItems(ChapterModel chapter) {
    final provider = context.read<WorkspaceProvider>();
    final hasVolumes = provider.volumes.isNotEmpty;
    final theme = Theme.of(context);

    // 构建移动至子菜单项
    List<ContextMenuItem> moveToChildren = [];
    if (hasVolumes) {
      final volumes = provider.volumes;
      final currentVolumeUuid = chapter.volumeUuid;
      final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);

      for (final volume in volumes) {
        if (volume.uuid == currentVolumeUuid) {
          // 当前分卷：打钩 + 灰色不可选
          moveToChildren.add(
            ContextMenuItem(
              label: Row(
                children: [
                  Icon(Icons.check, size: 16, color: disabledColor),
                  const SizedBox(width: 8),
                  Text(volume.name, style: TextStyle(color: disabledColor)),
                ],
              ),
              enabled: false,
            ),
          );
        } else {
          // 其他分卷：占位 + 可选
          moveToChildren.add(
            ContextMenuItem(
              label: Row(children: [const SizedBox(width: 24), Text(volume.name), const SizedBox(width: 24)]),
              onTap: () => provider.moveChapterToVolume(chapterUuid: chapter.uuid, targetVolumeUuid: volume.uuid),
            ),
          );
        }
      }

      // 如果章节当前在分卷中，添加"未分卷"选项
      if (currentVolumeUuid.isNotEmpty) {
        moveToChildren.add(const ContextMenuItem.divider());
        moveToChildren.add(
          ContextMenuItem(
            label: Row(children: [const SizedBox(width: 24), Text('未分卷')]),
            onTap: () => provider.moveChapterToVolume(chapterUuid: chapter.uuid, targetVolumeUuid: ''),
          ),
        );
      }
    }

    return [
      ContextMenuItem(
        labelText: '打开',
        onTap: () => provider.openTab(EditorTab(id: chapter.uuid, title: chapter.title, type: EditorTabType.chapter)),
      ),
      ContextMenuItem(
        labelText: '重命名',
        onTap: () {
          final workspaceProvider = provider;
          showInputDialog(
            context: context,
            title: '重命名章节',
            hintText: '请输入章节标题',
            initialValue: chapter.title,
            confirmText: '确定',
            cancelText: '取消',
            onConfirm: (newTitle) async {
              if (newTitle == chapter.title) return null;
              final success = await workspaceProvider.renameChapter(chapterUuid: chapter.uuid, newTitle: newTitle);
              return success ? null : '已存在同名章节';
            },
          );
        },
      ),
      ContextMenuItem(labelText: '移动至', enabled: hasVolumes, children: hasVolumes ? moveToChildren : null),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '在文件资源管理器中显示',
        onTap: () async {
          final filePath = provider.getChapterFilePath(chapter);
          final file = File(filePath);
          if (await file.exists()) {
            Process.run('explorer', ['/select,', filePath]);
          } else {
            final dir = file.parent;
            if (await dir.exists()) {
              Process.run('explorer', [dir.path]);
            }
          }
        },
      ),
      ContextMenuItem(
        labelText: '导出本章',
        onTap: () {
          showExportDialog(
            context: context,
            mode: ExportMode.chapter,
            chapters: [chapter],
            bookTitle: provider.bookTitle,
          );
        },
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        labelText: '删除',
        labelColor: theme.colorScheme.error,
        onTap: () {
          showConfirmDialog(
            context: context,
            title: '删除章节',
            description: '章节「${chapter.title}」将被移入回收站，\n你可以在回收站中恢复。',
            type: ConfirmType.delete,
            confirmText: '删除',
            cancelText: '取消',
            onConfirm: () async {
              await provider.deleteChapter(chapterUuid: chapter.uuid);
            },
          );
        },
      ),
    ];
  }

  /// 显示章节操作菜单
  void _showChapterMenu(
    BuildContext menuContext,
    ChapterModel chapter, {
    required ContextMenuType type,
    Offset? position,
    Size? anchorSize,
  }) {
    setState(() {
      _menuOpenedChapterId = chapter.uuid;
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
        if (mounted && _menuOpenedChapterId != null) {
          setState(() {
            _menuOpenedChapterId = null;
            _menuOpenedByDropdown = false;
          });
        }
      },
      menuItems: _buildChapterMenuItems(chapter),
    );
  }

  /// 切换标签页时滚动到对应章节
  Future<void> _scrollToCurrentChapter() async {
    final provider = context.read<WorkspaceProvider>();
    final tab = provider.currentTab;
    if (tab == null) return;

    final chapters = provider.chapters;
    ChapterModel? targetChapter;

    if (tab.type == EditorTabType.chapter) {
      // 章节标签页：根据UUID查找
      targetChapter = chapters.where((c) => c.uuid == tab.id).firstOrNull;
    } else if (tab.type == EditorTabType.backupPreview) {
      // 备份预览标签页：根据原始章节标题查找
      final chapterTitle = tab.originalChapterTitle;
      if (chapterTitle != null) {
        targetChapter = chapters.where((c) => c.title == chapterTitle).firstOrNull;
      }
    }

    if (targetChapter == null) return;

    final volumeUuid = targetChapter.volumeUuid;
    final volumes = provider.volumes;
    final hasVolumes = volumes.isNotEmpty;

    // 无分卷时直接滚动
    if (!hasVolumes) {
      _scrollToChapterOffset(chapters, targetChapter.uuid, volumes);
      return;
    }

    // 有分卷时，确保章节所在分组已展开
    final isUnassigned = volumeUuid.isEmpty;
    final isExpanded = isUnassigned
        ? !_isUnassignedCollapsed
        : (volumes.where((v) => v.uuid == volumeUuid).firstOrNull?.isExpanded ?? true);

    if (!isExpanded) {
      if (isUnassigned) {
        // 未分卷组：展开
        setState(() {
          _isUnassignedCollapsed = false;
        });
        _saveUnassignedCollapsedState();
      } else {
        // 分卷组：展开
        await provider.toggleVolumeExpanded(volumeUuid: volumeUuid);
      }
      // 展开后需要等下一帧再滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToChapterOffset(chapters, targetChapter!.uuid, volumes);
      });
    } else {
      _scrollToChapterOffset(chapters, targetChapter.uuid, volumes);
    }
  }

  /// 计算并滚动到指定章节的偏移位置
  void _scrollToChapterOffset(List<ChapterModel> chapters, String chapterId, List<VolumeModel> volumes) {
    // 延迟一帧确保布局完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final hasVolumes = volumes.isNotEmpty;

      // 无分卷时，直接计算偏移
      if (!hasVolumes) {
        final index = chapters.indexWhere((c) => c.uuid == chapterId);
        if (index == -1) return;
        // 倒序时，显示位置与原始位置相反
        final displayIndex = _isChapterReversed ? chapters.length - 1 - index : index;
        final targetOffset = 4.0 + displayIndex * _chapterItemExtent;
        final totalContentHeight = 8.0 + chapters.length * _chapterItemExtent;
        final viewportHeight = _scrollController.position.viewportDimension;
        final calculatedMaxScroll = (totalContentHeight - viewportHeight).clamp(0.0, double.infinity);
        final currentOffset = _scrollController.offset;
        final jumpTarget = (targetOffset - viewportHeight / 3).clamp(0.0, calculatedMaxScroll);
        // 目标项完全在可视区域内，无需跳转
        if (targetOffset >= currentOffset && targetOffset + _chapterItemExtent <= currentOffset + viewportHeight) return;
        _scrollController.jumpTo(jumpTarget);
        return;
      }

      // 有分卷时，按分组计算偏移
      final volumeGroups = _groupChaptersByVolume(chapters, volumes);

      // 构建显示用的分卷遍历顺序（与 _buildChapterList 保持一致）
      final volumeEntries = volumeGroups.entries.toList();
      final assignedEntries = volumeEntries.where((e) => e.key.isNotEmpty).toList();
      final unassignedEntry = volumeEntries.where((e) => e.key.isEmpty).firstOrNull;
      final displayEntries = <MapEntry<String, List<ChapterModel>>>[];
      if (_isChapterReversed) {
        displayEntries.addAll(assignedEntries.reversed);
      } else {
        displayEntries.addAll(assignedEntries);
      }
      if (unassignedEntry != null) {
        displayEntries.add(unassignedEntry);
      }

      // 计算目标章节的偏移位置
      double targetOffset = 4; // 顶部 padding
      bool found = false;

      for (final entry in displayEntries) {
        final volumeUuid = entry.key;
        final volumeChapters = entry.value;
        final isUnassigned = volumeUuid.isEmpty;

        // 跳过没有章节的未分卷组
        if (isUnassigned && volumeChapters.isEmpty) continue;

        final isExpanded = isUnassigned
            ? !_isUnassignedCollapsed
            : (volumes.where((v) => v.uuid == volumeUuid).firstOrNull?.isExpanded ?? true);

        // 分组标题高度
        targetOffset += _groupHeaderExtent;

        if (isExpanded) {
          final indexInVolume = volumeChapters.indexWhere((c) => c.uuid == chapterId);
          if (indexInVolume != -1) {
            // 倒序时，卷内显示位置与原始位置相反
            final displayIndexInVolume = _isChapterReversed ? volumeChapters.length - 1 - indexInVolume : indexInVolume;
            targetOffset += displayIndexInVolume * _chapterItemExtent;
            found = true;
            break;
          }
          targetOffset += volumeChapters.length * _chapterItemExtent;
        }
      }

      if (!found || !_scrollController.hasClients) return;

      // 自行计算总内容高度（不依赖布局的 maxScrollExtent）
      double totalContentHeight = 8; // 上下 padding
      for (final entry in displayEntries) {
        final volumeUuid = entry.key;
        final volumeChapters = entry.value;
        final isUnassigned = volumeUuid.isEmpty;
        if (isUnassigned && volumeChapters.isEmpty) continue;

        final isExpanded = isUnassigned
            ? !_isUnassignedCollapsed
            : (volumes.where((v) => v.uuid == volumeUuid).firstOrNull?.isExpanded ?? true);

        totalContentHeight += _groupHeaderExtent;
        if (isExpanded) totalContentHeight += volumeChapters.length * _chapterItemExtent;
      }

      final viewportHeight = _scrollController.position.viewportDimension;
      final calculatedMaxScroll = (totalContentHeight - viewportHeight).clamp(0.0, double.infinity);
      final currentOffset = _scrollController.offset;
      final jumpTarget = (targetOffset - viewportHeight / 3).clamp(0.0, calculatedMaxScroll);
      // 目标项完全在可视区域内，无需跳转
      if (targetOffset >= currentOffset && targetOffset + _chapterItemExtent <= currentOffset + viewportHeight) return;
      _scrollController.jumpTo(jumpTarget);
    });
  }

  // ================= 批量管理模式 =================

  /// 进入批量管理模式
  void _enterBatchMode() {
    setState(() {
      _isBatchMode = true;
      _selectedChapterIds.clear();
    });
    _selectionController.reset();
  }

  /// 退出批量管理模式
  void _exitBatchMode() {
    setState(() {
      _isBatchMode = false;
      _selectedChapterIds.clear();
    });
    _selectionController.reset();
  }

  /// 全选/取消全选
  void _toggleSelectAll(List<ChapterModel> chapters) {
    setState(() {
      if (_selectedChapterIds.length == chapters.length) {
        // 已全选，取消全选
        _selectedChapterIds.clear();
      } else {
        // 未全选，全选
        _selectedChapterIds.clear();
        _selectedChapterIds.addAll(chapters.map((c) => c.uuid));
      }
    });
  }

  /// 切换分卷下所有章节的选中状态
  void _toggleVolumeChaptersSelection(List<ChapterModel> volumeChapters) {
    setState(() {
      final volumeUuids = volumeChapters.map((c) => c.uuid).toSet();
      final allSelected = volumeUuids.every((id) => _selectedChapterIds.contains(id));
      if (allSelected) {
        // 已全选，取消选中该分卷下的所有章节
        _selectedChapterIds.removeAll(volumeUuids);
      } else {
        // 未全选，选中该分卷下的所有章节
        _selectedChapterIds.addAll(volumeUuids);
      }
    });
  }

  /// 判断是否全选
  bool _isAllSelected(BuildContext context) {
    final provider = context.read<WorkspaceProvider>();
    final chapters = provider.chapters;
    return chapters.isNotEmpty && _selectedChapterIds.length == chapters.length;
  }

  /// 构建批量模式下的分卷标题
  /// 点击标题区域展开/折叠分卷，点击右侧复选框选中/取消该分卷下所有章节
  Widget _buildBatchGroupHeader({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isExpanded,
    required List<ChapterModel> volumeChapters,
    required VoidCallback onToggleExpand,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final volumeUuids = volumeChapters.map((c) => c.uuid).toSet();
    final allSelected = volumeUuids.isNotEmpty && volumeUuids.every((id) => _selectedChapterIds.contains(id));

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
              color: isExpanded
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // 展开/折叠图标
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                // 分卷图标
                Icon(
                  icon,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                // 分卷名称
                Expanded(
                  child: Text(
                    title,
                    style: context.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                // 右侧复选框（替换原来的"xx章"）
                _buildCheckboxIcon(
                  context: context,
                  isSelected: allSelected,
                  onTap: () => _toggleVolumeChaptersSelection(volumeChapters),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建带悬停效果的复选框图标
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

  /// 构建批量操作底部操作栏
  Widget _buildBatchActionBar(BuildContext context, List<ChapterModel> chapters) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSelection = _selectedChapterIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
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
                  style: context.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    TextSpan(
                      text: '${_selectedChapterIds.length}',
                      style: context.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' 项',
                      style: context.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
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
                onPressed: hasSelection ? _handleBatchMoveToVolume : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(66, 38),
                ),
                child: const Text('移动'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: hasSelection ? _handleBatchExport : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(66, 38),
                ),
                child: const Text('导出'),
              ),
              const Spacer(),
              // 右侧：删除（无边框）
              TextButton(
                onPressed: hasSelection ? _handleBatchDelete : null,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  minimumSize: const Size(66, 38),
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 处理批量导出
  Future<void> _handleBatchExport() async {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final selectedChapters = workspaceProvider.chapters
        .where((c) => _selectedChapterIds.contains(c.uuid))
        .toList();

    if (selectedChapters.isEmpty) return;

    showExportDialog(
      context: context,
      mode: ExportMode.chapter,
      chapters: selectedChapters,
      bookTitle: workspaceProvider.bookTitle,
    );
  }

  /// 处理批量移动到分卷
  void _handleBatchMoveToVolume() {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final volumes = workspaceProvider.volumes;

    // 没有分卷时无法移动
    if (volumes.isEmpty) return;

    // 构建分卷选择菜单项
    final menuItems = <ContextMenuItem>[];

    // 添加各分卷选项
    for (final volume in volumes) {
      menuItems.add(ContextMenuItem(
        labelText: volume.name,
        onTap: () => _performBatchMove(volume.uuid),
      ));
    }

    // 添加分隔线
    menuItems.add(const ContextMenuItem.divider());

    // 添加"未分卷"选项（放在最后）
    menuItems.add(ContextMenuItem(
      labelText: '未分卷',
      onTap: () => _performBatchMove(''),
    ));

    // 获取"移动"按钮的位置，菜单显示在按钮上方
    final buttonContext = _moveButtonKey.currentContext;
    if (buttonContext == null) return;
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    ContextMenu.showMenuAt(
      context: context,
      position: Offset(
        buttonPosition.dx,
        buttonPosition.dy - 4,
      ),
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
  Future<void> _performBatchMove(String targetVolumeUuid) async {
    final workspaceProvider = context.read<WorkspaceProvider>();

    final count = await workspaceProvider.batchMoveChaptersToVolume(
      chapterUuids: _selectedChapterIds.toList(),
      targetVolumeUuid: targetVolumeUuid,
    );

    if (!mounted) return;

    if (count > 0) {
      final volumeName = targetVolumeUuid.isEmpty ? '未分卷' : workspaceProvider.getVolumeName(targetVolumeUuid);
      SnackBarService.show(context, '已移动 $count 个章节至「$volumeName」');
      _exitBatchMode();
    } else {
      SnackBarService.show(context, '移动失败，目标分卷下可能存在同名章节');
    }
  }

  /// 处理批量删除
  void _handleBatchDelete() {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final count = _selectedChapterIds.length;

    showConfirmDialog(
      context: context,
      title: '批量删除章节',
      description: '确定要删除选中的 $count 个章节吗？\n删除后可在回收站中恢复。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        final dismissLoading = showLoadingDialog(
          context: context,
          message: '正在删除 $count 个章节，请稍候...',
        );
        try {
          final deletedCount = await workspaceProvider.batchDeleteChapters(
            chapterUuids: _selectedChapterIds.toList(),
          );
          if (!mounted) return;
          if (deletedCount > 0) {
            SnackBarService.show(context, '已删除 $deletedCount 个章节');
            _exitBatchMode();
          }
        } finally {
          dismissLoading();
        }
      },
    );
  }
}
