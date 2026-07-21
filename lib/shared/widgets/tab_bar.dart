import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/theme/tab_colors.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/context_menu.dart';
import 'package:quick_write/shared/widgets/toolbar_button.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

// ============================================================
// 标签页组件模块
// ============================================================

// ============================================================
// 1. HoverableTabButton - 带修改标记的标签页按钮
// ============================================================

/// 标签页按钮
///
/// 根据标签页的修改状态显示不同的内容：
/// - 已修改时：优先显示修改标记（圆点），悬停在按钮上时变成关闭按钮
/// - 未修改时：标签页悬停或按钮悬停时显示关闭按钮，否则显示空白占位
class HoverableTabButton extends StatefulWidget {
  /// 是否已修改
  final bool isModified;

  /// 是否选中
  final bool isSelected;

  /// 整个标签页是否被悬停
  final bool isTabHovered;

  /// 正常状态颜色
  final Color normalColor;

  /// 悬停状态颜色（关闭按钮悬停时的背景色）
  final Color hoverColor;

  /// 关闭回调
  final VoidCallback onClose;

  const HoverableTabButton({
    super.key,
    required this.isModified,
    required this.isSelected,
    required this.isTabHovered,
    required this.normalColor,
    required this.hoverColor,
    required this.onClose,
  });

  @override
  State<HoverableTabButton> createState() => _HoverableTabButtonState();
}

class _HoverableTabButtonState extends State<HoverableTabButton> {
  /// 按钮是否被悬停
  bool _isButtonHovered = false;

  @override
  Widget build(BuildContext context) {
    // 判断是否应该显示关闭按钮
    // 1. 选中的标签页始终显示关闭按钮
    // 2. 按钮本身被悬停时显示关闭按钮
    // 3. 非选中标签页被悬停且未修改时显示关闭按钮
    final shouldShowClose =
        widget.isSelected || _isButtonHovered || (!widget.isSelected && widget.isTabHovered && !widget.isModified);

    if (widget.isModified && !_isButtonHovered) {
      // 已修改状态：优先显示修改标记，只有按钮悬停时才变成关闭按钮
      return _buildModifiedMark();
    } else if (shouldShowClose) {
      // 需要显示关闭按钮
      return _buildCloseButton();
    } else {
      // 其他情况显示空白占位
      return _buildPlaceholder();
    }
  }

  /// 构建修改标记（圆点）
  Widget _buildModifiedMark() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isButtonHovered = true),
      onExit: (_) => setState(() => _isButtonHovered = false),
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(Icons.circle, size: 8, color: widget.normalColor),
        ),
      ),
    );
  }

  /// 构建关闭按钮
  Widget _buildCloseButton() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isButtonHovered = true),
      onExit: (_) => setState(() => _isButtonHovered = false),
      child: GestureDetector(
        onTap: widget.onClose,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.close, size: 12, color: widget.normalColor),
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: _isButtonHovered ? 16 : 0,
                height: _isButtonHovered ? 16 : 0,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.hoverColor.withAlpha(25)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建空白占位
  Widget _buildPlaceholder() {
    return const SizedBox(width: 24);
  }
}

// ============================================================
// 2. TabItem - 单个标签页项
// ============================================================

/// 标签页项组件
///
/// 显示单个标签页，包括：
/// - 标签页选中状态、悬停样式
/// - 修改标记显示
///
/// 配色方案说明：
/// - 选中状态：使用主色调高亮，顶部有明显的彩色指示条
/// - 未选中状态：使用柔和的灰色，视觉上退居次要位置
/// - 悬停状态：背景色微变，提供交互反馈
class TabItem extends StatefulWidget {
  /// 标签页数据
  final EditorTab tab;

  /// 标签页索引
  final int index;

  /// 是否选中
  final bool isSelected;

  /// 工作区提供者
  final WorkspaceProvider provider;

  /// 用于获取标签页位置和大小的全局键
  final GlobalKey tabKey;

  const TabItem({
    super.key,
    required this.tab,
    required this.index,
    required this.isSelected,
    required this.provider,
    required this.tabKey,
  });

  @override
  State<TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<TabItem> {
  /// 标签页是否被悬停
  bool _isHovered = false;

  /// 上次点击的时间戳，用于手动检测双击
  int _lastTapTime = 0;

  @override
  Widget build(BuildContext context) {
    // 从主题获取标签页配色方案
    final colors = TabColors.of(context);

    // 根据状态确定当前使用的颜色
    final bgColor = widget.isSelected ? colors.selectedBg : (_isHovered ? colors.hoverBg : colors.unselectedBg);

    final fgColor = widget.isSelected ? colors.selectedFg : (_isHovered ? colors.hoverFg : colors.unselectedFg);

    final borderColor = widget.isSelected ? colors.selectedBorder : colors.unselectedBorder;

    final indicatorColor = widget.isSelected ? colors.selectedIndicator : Colors.transparent;

    return ContextMenu(
      getMenuItems: () => _buildContextMenuItems(),
      showIcons: false,
      fontSize: 13,
      itemPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      child: MouseRegion(
        key: widget.tabKey,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Listener(
          onPointerDown: (event) {
            // 监听鼠标中键（滚轮）按下事件
            if (event.buttons == kMiddleMouseButton) {
              widget.provider.closeTab(widget.tab.id);
            }
          },
          child: GestureDetector(
            onTap: () {
              // 手动检测双击：两次点击间隔小于阈值视为双击
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastTapTime < GlobalConstants.doubleTapThreshold) {
                // 双击：如果是预览模式，退出预览模式转为固定状态
                if (widget.tab.isPreview) {
                  widget.provider.pinTab(widget.tab.id);
                }
                _lastTapTime = 0;
              } else {
                // 单击：切换到该标签页
                _lastTapTime = now;
                widget.provider.switchToTab(widget.index);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minWidth: 10, maxWidth: 200),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  top: BorderSide(color: indicatorColor, width: 2),
                  right: BorderSide(color: borderColor, width: 1),
                  bottom: BorderSide(color: widget.isSelected ? bgColor : borderColor, width: 1),
                ),
              ),
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 图标
                  Icon(widget.tab.icon ?? widget.tab.defaultIcon, size: 16, color: fgColor),
                  const SizedBox(width: 6),
                  
                  // 预览模式指示器（小圆点）
                  if (widget.tab.isPreview) ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: fgColor.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  // 标题（鼠标悬停显示完整章节名）
                  Flexible(
                    child: CursorTooltipTarget(
                      tooltipContent: Text(widget.tab.title),
                      child: Transform(
                        transform: widget.tab.isPreview ? Matrix4.skewX(-0.2) : Matrix4.identity(), 
                        child: Text(
                          widget.tab.title,
                          style: context.titleSmall?.copyWith(
                            color: fgColor,
                            fontWeight: widget.isSelected ? FontWeight.w500 : FontWeight.normal,
                            fontSize: widget.tab.isPreview ? (context.titleSmall?.fontSize ?? 14) - 1 : null,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  // 修改标记或关闭按钮
                  HoverableTabButton(
                    key: ValueKey('${widget.tab.id}_${widget.tab.isModified}'),
                    isModified: widget.tab.isModified,
                    isSelected: widget.isSelected,
                    isTabHovered: _isHovered,
                    normalColor: widget.isSelected ? colors.selectedFg : colors.modifiedMark,
                    hoverColor: colors.closeHoverBg,
                    onClose: () => widget.provider.closeTab(widget.tab.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建右键菜单项列表
  List<ContextMenuItem> _buildContextMenuItems() {
    final provider = widget.provider;
    final tab = widget.tab;
    final tabIndex = provider.openedTabs.indexOf(tab);
    final hasRightTabs = tabIndex < provider.openedTabs.length - 1;
    final hasOtherTabs = provider.openedTabs.length > 1;
    final hasSavedTabs = provider.openedTabs.any((t) => !t.isModified);
    final tabFilePath = provider.getTabFilePath(tab);

    return [
      // 关闭
      ContextMenuItem(labelText: '关闭', icon: Icons.close, onTap: () => provider.closeTab(tab.id)),
      // 关闭其他
      ContextMenuItem(
        labelText: '关闭其他',
        icon: Icons.tab_unselected,
        enabled: hasOtherTabs,
        onTap: () => _handleCloseOtherTabs(provider, tab),
      ),
      // 关闭右侧标签页
      ContextMenuItem(
        labelText: '关闭右侧标签页',
        icon: Icons.arrow_right_alt,
        enabled: hasRightTabs,
        onTap: () => _handleCloseRightTabs(provider, tab),
      ),
      // 关闭已保存
      ContextMenuItem(
        labelText: '关闭已保存',
        icon: Icons.check_circle_outline,
        enabled: hasSavedTabs,
        onTap: () => provider.closeSavedTabs(),
      ),
      // 全部关闭
      ContextMenuItem(labelText: '全部关闭', icon: Icons.layers_clear, onTap: () => _handleCloseAllTabs(provider)),
      const ContextMenuItem.divider(),
      // 在文件资源管理器中显示
      ContextMenuItem(
        labelText: '在文件资源管理器中显示',
        icon: Icons.folder_open,
        enabled: tabFilePath != null,
        onTap: () => _handleShowInExplorer(tabFilePath!),
      ),
      // 固定（仅预览模式可用）
      ContextMenuItem(
        labelText: '固定',
        icon: Icons.push_pin_outlined,
        enabled: tab.isPreview,
        onTap: () => provider.pinTab(tab.id),
      ),
    ];
  }

  /// 处理关闭其他标签页
  void _handleCloseOtherTabs(WorkspaceProvider provider, EditorTab tab) {
    final otherTabs = provider.openedTabs.where((t) => t.id != tab.id).toList();
    final unsavedCount = otherTabs.where((t) => t.isModified).length;

    if (unsavedCount > 0) {
      showConfirmDialog(
        context: context,
        title: '关闭其他标签',
        description: '有 $unsavedCount 个未保存的标签页，关闭后将丢失未保存的内容，是否继续？',
        type: ConfirmType.warning,
        confirmText: '继续关闭',
        cancelText: '取消',
        onConfirm: () => provider.closeOtherTabs(tab.id),
      );
    } else {
      provider.closeOtherTabs(tab.id);
    }
  }

  /// 处理关闭右侧标签页
  void _handleCloseRightTabs(WorkspaceProvider provider, EditorTab tab) {
    final tabIndex = provider.openedTabs.indexOf(tab);
    final rightTabs = provider.openedTabs.sublist(tabIndex + 1);
    final unsavedCount = rightTabs.where((t) => t.isModified).length;

    if (unsavedCount > 0) {
      showConfirmDialog(
        context: context,
        title: '关闭右侧标签页',
        description: '有 $unsavedCount 个未保存的标签页，关闭后将丢失未保存的内容，是否继续？',
        type: ConfirmType.warning,
        confirmText: '继续关闭',
        cancelText: '取消',
        onConfirm: () => provider.closeRightTabs(tab.id),
      );
    } else {
      provider.closeRightTabs(tab.id);
    }
  }

  /// 处理关闭所有标签页
  void _handleCloseAllTabs(WorkspaceProvider provider) {
    if (provider.hasUnsavedTabs()) {
      showConfirmDialog(
        context: context,
        title: '关闭所有标签',
        description: '有 ${provider.unsavedTabsCount()} 个未保存的标签页，关闭后将丢失未保存的内容，是否继续？',
        type: ConfirmType.warning,
        confirmText: '继续关闭',
        cancelText: '取消',
        onConfirm: () => provider.closeAllTabs(),
      );
    } else {
      provider.closeAllTabs();
    }
  }

  /// 在文件资源管理器中显示
  Future<void> _handleShowInExplorer(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      Process.run('explorer', ['/select,', filePath]);
    } else {
      final dir = file.parent;
      if (await dir.exists()) {
        Process.run('explorer', [dir.path]);
      }
    }
  }
}

// ============================================================
// 3. TabBarWidget - 标签栏整体布局
// ============================================================

/// 标签栏组件
///
/// 显示多个标签页的列表，包括：
/// - 标签页水平滚动
/// - 标签页拖拽排序
/// - 关闭所有标签页按钮
/// - 悬浮时显示横向滚动条
/// - 鼠标滚轮直接横向滚动（无需按住shift）
class TabBarWidget extends StatefulWidget {
  /// 工作区提供者
  final WorkspaceProvider provider;

  /// 显示关闭所有标签页按钮
  final bool showCloseAllButton;

  const TabBarWidget({super.key, required this.provider, this.showCloseAllButton = true});

  @override
  State<TabBarWidget> createState() => _TabBarWidgetState();
}

class _TabBarWidgetState extends State<TabBarWidget> {
  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 标签栏是否被悬停
  bool _isHovered = false;

  /// 标签页的 GlobalKey 映射表（标签页ID -> GlobalKey）
  final Map<String, GlobalKey> _tabKeys = {};

  /// 标签页的实际宽度映射表（标签页ID -> 宽度）
  final Map<String, double> _tabWidths = {};

  /// 上一次选中的标签页索引，用于检测切换
  int _lastSelectedIndex = -1;

  /// 更多操作菜单是否打开
  bool _isMenuOpen = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 获取或创建标签页的 GlobalKey
  GlobalKey _getTabKey(String tabId) {
    return _tabKeys.putIfAbsent(tabId, () => GlobalKey());
  }

  /// 记录标签页的实际宽度
  void _recordTabWidth(String tabId, double width) {
    _tabWidths[tabId] = width;
  }

  /// 计算指定索引标签页的精确位置（基于已记录的宽度）
  /// 返回 (left, right) 或 null（如果无法计算）
  (double, double)? _calculateTabPosition(int index) {
    double left = 0;
    for (int i = 0; i < index; i++) {
      final tabId = widget.provider.openedTabs[i].id;
      final width = _tabWidths[tabId];
      if (width == null) return null;
      left += width;
    }
    final targetTabId = widget.provider.openedTabs[index].id;
    final targetWidth = _tabWidths[targetTabId];
    if (targetWidth == null) return null;
    return (left, left + targetWidth);
  }

  /// 滚动到指定索引的标签页，确保其完整可见
  void _scrollToTab(int index) {
    if (!_scrollController.hasClients) return;
    if (index < 0 || index >= widget.provider.openedTabs.length) return;

    // 获取滚动容器的 RenderBox
    final RenderBox? scrollViewRenderBox =
        _scrollController.position.context.storageContext.findRenderObject() as RenderBox?;
    if (scrollViewRenderBox == null) return;

    final scrollViewWidth = scrollViewRenderBox.size.width;
    final tab = widget.provider.openedTabs[index];
    final tabKey = _tabKeys[tab.id];

    // 尝试获取标签页的 RenderBox
    final RenderBox? tabRenderBox = tabKey?.currentContext?.findRenderObject() as RenderBox?;

    double targetOffset;

    if (tabRenderBox != null) {
      // 标签页可见，记录其实际宽度
      final tabWidth = tabRenderBox.size.width;
      _recordTabWidth(tab.id, tabWidth);

      // 使用精确计算
      final tabOffset = tabRenderBox.localToGlobal(Offset.zero);
      final scrollViewOffset = scrollViewRenderBox.localToGlobal(Offset.zero);

      final tabLeft = tabOffset.dx - scrollViewOffset.dx;
      final tabRight = tabLeft + tabWidth;

      if (tabLeft < 0) {
        // 左侧被遮挡，向左滚动
        targetOffset = _scrollController.offset + tabLeft;
      } else if (tabRight > scrollViewWidth) {
        // 右侧被遮挡，向右滚动
        targetOffset = _scrollController.offset + (tabRight - scrollViewWidth);
      } else {
        // 标签页已完整可见，无需滚动
        return;
      }
    } else {
      // 标签页不可见，尝试使用已记录的宽度计算位置
      final position = _calculateTabPosition(index);
      if (position == null) {
        // 无法计算（新标签页宽度未知），使用最小宽度估算
        // 这样估算位置一定比实际位置更靠左，滚动后标签页一定完全可见
        // 精确调整时只需要向右微调，不会有回弹感
        const minWidth = 10.0;
        double estimatedLeft = 0;
        for (int i = 0; i < index; i++) {
          final tabId = widget.provider.openedTabs[i].id;
          estimatedLeft += _tabWidths[tabId] ?? 200.0;
        }
        final estimatedRight = estimatedLeft + minWidth;
        // 滚动到让估算的右边界对齐可见区域右边界
        targetOffset = estimatedRight - scrollViewWidth;
      } else {
        final (tabLeft, tabRight) = position;
        final visibleLeft = _scrollController.offset;
        final visibleRight = visibleLeft + scrollViewWidth;

        if (tabRight > visibleRight) {
          // 标签页在右侧不可见区域，滚动到使其右边界对齐可见区域右边界
          targetOffset = tabRight - scrollViewWidth;
        } else if (tabLeft < visibleLeft) {
          // 标签页在左侧不可见区域，滚动到使其左边界对齐可见区域左边界
          targetOffset = tabLeft;
        } else {
          return;
        }
      }
    }

    // 确保滚动位置在有效范围内
    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;
    targetOffset = targetOffset.clamp(minScroll, maxScroll);

    // 执行滚动（直接跳转，不使用动画）
    _scrollController.jumpTo(targetOffset);

    // 如果之前无法获取 RenderBox，滚动后需要再次检查
    if (tabRenderBox == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTab(index);
      });
    }
  }

  /// 处理鼠标滚轮事件，实现横向滚动
  void _handleScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // 获取滚轮滚动的距离，并增加滚动速度
      final scrollDelta = event.scrollDelta.dy * 1.5;

      // 如果滚动控制器有客户端，则进行横向滚动
      if (_scrollController.hasClients) {
        // 计算新的滚动位置（反向滚动，更符合直觉）
        final newOffset = _scrollController.offset + scrollDelta;

        // 确保滚动位置在有效范围内
        final maxScroll = _scrollController.position.maxScrollExtent;
        final minScroll = _scrollController.position.minScrollExtent;
        final clampedOffset = newOffset.clamp(minScroll, maxScroll);

        // 执行滚动动画
        _scrollController.animateTo(clampedOffset, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 从 AppTheme 获取标签页颜色配置
    final colorScheme = Theme.of(context).colorScheme;

    // 检测标签页切换，在帧结束后滚动到选中的标签页
    final currentIndex = widget.provider.currentTabIndex;
    if (currentIndex != _lastSelectedIndex) {
      _lastSelectedIndex = currentIndex;
      // 使用 addPostFrameCallback 确保在当前帧构建完成后再滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (currentIndex >= 0) {
          _scrollToTab(currentIndex);
        }
      });
    }

    return Container(
      height: 35,
      color: colorScheme.surface,
      child: MouseRegion(
        // 监听鼠标进入和退出，控制滚动条显示
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Row(
          children: [
            // 标签页列表（支持拖拽排序和横向滚动）
            Expanded(
              child: Listener(
                // 监听鼠标滚轮事件
                onPointerSignal: _handleScroll,
                child: ScrollbarTheme(
                  data: ScrollbarThemeData(
                    crossAxisMargin: 0, // 滚动条距离底部的距离
                  ),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: _isHovered, // 只在悬浮时显示滚动条
                    thickness: 3, // 滚动条厚度
                    radius: const Radius.circular(3), // 滚动条圆角
                    child: ReorderableListView.builder(
                      scrollController: _scrollController,
                      buildDefaultDragHandles: false,
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.provider.openedTabs.length,
                      onReorder: (oldIndex, newIndex) {
                        widget.provider.reorderTabs(oldIndex, newIndex);
                      },
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            return Material(
                              elevation: 6.0,
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              child: child,
                            );
                          },
                          child: child,
                        );
                      },
                      itemBuilder: (context, index) {
                        final tab = widget.provider.openedTabs[index];
                        final isSelected = widget.provider.currentTabIndex == index;

                        return ReorderableDragStartListener(
                          key: ValueKey(tab.id),
                          index: index,
                          child: TabItem(
                            tab: tab,
                            index: index,
                            isSelected: isSelected,
                            provider: widget.provider,
                            tabKey: _getTabKey(tab.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            // 右侧操作按钮区域
            if (widget.showCloseAllButton && widget.provider.hasOpenedTabs)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SmallToolbarButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: '更多',
                  isMenuOpen: _isMenuOpen,
                  onPressed: () => _showMoreMenu(context, widget.provider),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 显示更多操作菜单
  void _showMoreMenu(BuildContext context, WorkspaceProvider provider) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    // 标记菜单打开，按钮保持按下状态
    setState(() {
      _isMenuOpen = true;
    });

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
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      items: [
        PopupMenuItem<String>(
          value: 'close_all',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('全部关闭'),
        ),
        PopupMenuItem<String>(
          value: 'close_saved',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('关闭已保存'),
        ),
        PopupMenuItem<String>(
          value: 'close_others',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          enabled: provider.openedTabs.length > 1,
          child: Text('关闭其他'),
        ),
      ],
    ).then((value) {
      // 菜单关闭，清除按下状态
      if (mounted) {
        setState(() {
          _isMenuOpen = false;
        });
      }
      if (!context.mounted) return;
      if (value == 'close_all') {
        _handleCloseAllTabs(context, provider);
      } else if (value == 'close_others' && provider.currentTab != null) {
        _handleCloseOtherTabs(context, provider);
      } else if (value == 'close_saved') {
        provider.closeSavedTabs();
      }
    });
  }

  /// 处理关闭所有标签页
  void _handleCloseAllTabs(BuildContext context, WorkspaceProvider provider) {
    if (provider.hasUnsavedTabs()) {
      showConfirmDialog(
        context: context,
        title: '关闭所有标签',
        description: '有 ${provider.unsavedTabsCount()} 个未保存的标签页，关闭后将丢失未保存的内容，是否继续？',
        type: ConfirmType.warning,
        confirmText: '继续关闭',
        cancelText: '取消',
        onConfirm: () => provider.closeAllTabs(),
      );
    } else {
      provider.closeAllTabs();
    }
  }

  /// 处理关闭其他标签页
  void _handleCloseOtherTabs(BuildContext context, WorkspaceProvider provider) {
    final currentTab = provider.currentTab;
    if (currentTab == null) return;

    final otherTabs = provider.openedTabs.where((t) => t.id != currentTab.id).toList();
    final unsavedCount = otherTabs.where((t) => t.isModified).length;

    if (unsavedCount > 0) {
      showConfirmDialog(
        context: context,
        title: '关闭其他标签',
        description: '有 $unsavedCount 个未保存的标签页，关闭后将丢失未保存的内容，是否继续？',
        type: ConfirmType.warning,
        confirmText: '继续关闭',
        cancelText: '取消',
        onConfirm: () => provider.closeOtherTabs(currentTab.id),
      );
    } else {
      provider.closeOtherTabs(currentTab.id);
    }
  }
}
