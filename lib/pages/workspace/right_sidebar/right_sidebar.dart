import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'widgets/tools_display_settings.dart';
import 'panels/layout_panel.dart';
import 'panels/typeset_panel.dart';
import 'panels/other_panel.dart';
import 'panels/search_panel.dart';
import 'panels/history_panel.dart';
import 'panels/tools_panel.dart';

/// 工作台右侧边栏
///
/// 作为设置和一些功能的扩展区，使用紧凑卡片样式，通过色差形成分界
class RightSidebar extends StatefulWidget {
  const RightSidebar({super.key});

  @override
  State<RightSidebar> createState() => _RightSidebarState();
}

class _RightSidebarState extends State<RightSidebar>
    with SingleTickerProviderStateMixin {
  // 展开动画控制器
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  // 记录上一次的展开状态，用于判断是否需要播放动画
  bool _lastExpanded = false;

  // 标记是否已完成首次状态同步
  // 首次直接跳到目标值以跳过动画，避免工作台初始化时动画与数据加载竞争导致卡顿
  bool _isFirstSync = true;

  // 工具面板可见区块的显示顺序列表（元素为 ToolsSection 的 id）
  // 由标题栏"显示设置"下拉菜单配置，并传给 ToolsPanel 渲染
  List<String> _toolsSectionOrder = const ['bookInfo', 'stats'];

  // 显示设置下拉菜单控制器
  final MenuController _displaySettingsMenuController = MenuController();

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    _toolsSectionOrder = MiscCacheService.instance.getToolsSectionOrder();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isExpanded = context.watch<WorkspaceProvider>().isRightSidebarExpanded;

    // 首次同步：直接将动画控制器跳到目标值，不播放动画
    if (_isFirstSync) {
      _isFirstSync = false;
      _lastExpanded = isExpanded;
      _expandController.value = isExpanded ? 1.0 : 0.0;
      return;
    }

    // 仅在展开状态变化时播放动画
    if (isExpanded != _lastExpanded) {
      _lastExpanded = isExpanded;
      if (isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    }
  }
  
  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final isExpanded = workspaceProvider.isRightSidebarExpanded;
    final width = workspaceProvider.rightSidebarWidth;

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        // 使用动画值来控制可见性和边距
        final animationValue = _expandAnimation.value;
        final currentWidth = isExpanded ? width : 0.0;
        final effectiveWidth = currentWidth * animationValue;
        
        return Container(
          width: effectiveWidth,
          margin: EdgeInsets.only(
            right: 2 * animationValue,
            top: 2 * animationValue,
            bottom: 2 * animationValue,
          ),
          // 使用 ClipRect 和 OverflowBox 避免动画过程中的宽度挤压导致溢出错误
          child: animationValue > 0 
              ? ClipRect(
                  child: OverflowBox(
                    minWidth: width,
                    maxWidth: width,
                    alignment: Alignment.centerRight, // 右侧边栏内容向右对齐，左侧裁剪
                    child: child,
                  ),
                ) 
              : const SizedBox.shrink(),
        );
      },
      child: _buildExpandedSidebar(context),
    );
  }

  /// 构建展开状态的右侧边栏
  Widget _buildExpandedSidebar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final workspaceProvider = context.watch<WorkspaceProvider>();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // 顶部标题栏
          _buildHeader(context, workspaceProvider),

          // 分隔线
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),

          // 内容区域
          Expanded(child: _buildContent(context, workspaceProvider)),
        ],
      ),
    );
  }

  /// 构建顶部标题栏
  /// 使用 Row + Expanded 实现自适应布局，随侧边栏宽度变化
  Widget _buildHeader(BuildContext context, WorkspaceProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final sidebarType = provider.rightSidebarType;
    final showResetButton = sidebarType != RightSidebarType.search &&
        sidebarType != RightSidebarType.history &&
        sidebarType != RightSidebarType.tools;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      // 直接使用 Row，自动填充父容器宽度，实现自适应
      child: Row(
        children: [
          // 标题文字
          Text(
            _getSidebarTitle(provider.rightSidebarType),
            style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          // 重置按钮（恢复当前页面的默认设置），搜索面板和历史版本面板不显示
          if (showResetButton)
            CursorTooltipTarget(
              tooltipContent: const Text('恢复默认设置'),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _resetCurrentPanelSettings(provider),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

          // 弹性空间，将关闭按钮推到右侧
          const Spacer(),

          // 显示设置按钮（仅工具面板显示），点击展开下拉菜单配置区块显示与顺序
          if (sidebarType == RightSidebarType.tools)...[
            _buildDisplaySettingsButton(context),
            const SizedBox(width: 8),
            Container(
              width: 2,
              height: 16,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 4),
          ],
            

          // 关闭按钮
          CursorTooltipTarget(
            tooltipContent: const Text('关闭侧边栏'),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  provider.closeRightSidebar();
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建显示设置按钮及其下拉菜单
  ///
  /// 点击图标按钮展开 [ToolsDisplaySettings] 菜单，配置书籍信息与码字统计
  /// 两个区块的显示开关及顺序。
  Widget _buildDisplaySettingsButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      controller: _displaySettingsMenuController,
      alignmentOffset: const Offset(-192, 6),
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(colorScheme.surface),
        elevation: WidgetStateProperty.all(3),
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        ToolsDisplaySettings(
          sectionOrder: _toolsSectionOrder,
          onOrderChanged: _onToolsSectionOrderChanged,
        ),
      ],
      builder: (context, controller, child) {
        return CursorTooltipTarget(
          tooltipContent: const Text('显示设置'),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 显示设置变化回调
  ///
  /// 更新本地顺序状态以即时重渲染工具面板，并持久化到缓存
  void _onToolsSectionOrderChanged(List<String> order) {
    setState(() {
      _toolsSectionOrder = order;
    });
    MiscCacheService.instance.saveToolsSectionOrder(order);
  }

  /// 根据右侧边栏类型获取标题
  String _getSidebarTitle(RightSidebarType type) {
    switch (type) {
      case RightSidebarType.layout:
        return '布局设置';
      case RightSidebarType.typeset:
        return '排版设置';
      case RightSidebarType.other:
        return '其他设置';
      case RightSidebarType.search:
        return '全文搜索';
      case RightSidebarType.history:
        return '历史版本';
      case RightSidebarType.tools:
        return '工具';
    }
  }

  /// 构建内容区域
  /// 根据右侧边栏类型显示不同的设置面板（布局设置、排版设置、其他设置、全文搜索、历史版本）
  Widget _buildContent(BuildContext context, WorkspaceProvider provider) {
    // 根据右侧边栏类型显示不同的设置面板
    switch (provider.rightSidebarType) {
      case RightSidebarType.layout:
        // 布局设置面板：显示章节标题、页边距、页面视图等设置
        return const LayoutPanel();
      case RightSidebarType.typeset:
        // 排版设置面板：字间距、行间距、首行缩进等设置
        return const TypesetPanel();
      case RightSidebarType.other:
        // 其他设置面板：自动保存、自动备份、查看快捷键等
        return const OtherPanel();
      case RightSidebarType.search:
        // 全文搜索面板：跨章节搜索关键词
        return const SearchPanel();
      case RightSidebarType.history:
        // 历史版本面板：查看、删除和恢复章节备份
        return const HistoryPanel();
      case RightSidebarType.tools:
        // 工具面板：随机取名等快捷工具和按配置顺序展示的可见区块
        return ToolsPanel(sectionOrder: _toolsSectionOrder);
    }
  }

  /// 重置当前面板的设置为默认值
  /// 通过 SettingsService 重置并持久化到配置文件
  void _resetCurrentPanelSettings(WorkspaceProvider provider) {
    switch (provider.rightSidebarType) {
      case RightSidebarType.layout:
        // 调用 SettingsService 重置布局设置
        SettingsService.instance.resetLayoutSettings();
        break;
      case RightSidebarType.typeset:
        // 调用 SettingsService 重置排版设置
        SettingsService.instance.resetTypesetSettings();
        break;
      case RightSidebarType.other:
        // 调用 SettingsService 重置其他设置
        SettingsService.instance.resetOtherSettings();
        break;
      case RightSidebarType.search:
        // 全文搜索面板无需重置
        break;
      case RightSidebarType.history:
        // 历史版本面板无需重置
        break;
      case RightSidebarType.tools:
        // 工具面板无需重置
        break;
    }
  }
}
