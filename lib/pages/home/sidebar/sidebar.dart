import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:window_manager/window_manager.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/providers/home_sidebar_provider.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 侧边栏组件
///
/// - 展开/折叠
/// - 导航栏
/// - 状态栏
/// - 设置
class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  // ---------------------------------------------------------
  // 侧边栏
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // 使用 context.watch 监听 SidebarProvider 和 HomeStateProvider 的变化
    // 当状态改变时，会自动重新构建此组件
    final sidebarProvider = context.watch<HomeSidebarProvider>();
    final homeStateProvider = context.watch<HomeStateProvider>();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeInOut,
      width: sidebarProvider.isExpanded ? 200 : 64, // 展开宽200，折叠宽64
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
            child: _buildLogo(context, sidebarProvider),
          ),

          // 中间导航区 (使用 Expanded 包裹 ListView，防止无限高度溢出报错)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavItem(
                  context,
                  sidebarProvider,
                  homeStateProvider,
                  0,
                  Icons.auto_stories_rounded,
                  '书架',
                ),
                _buildNavItem(
                  context,
                  sidebarProvider,
                  homeStateProvider,
                  1,
                  Icons.bar_chart_rounded,
                  '码字统计',
                ),
                _buildNavItem(
                  context,
                  sidebarProvider,
                  homeStateProvider,
                  2,
                  Icons.delete_outline_rounded,
                  '回收站',
                ),
              ],
            ),
          ),

          // 底部固定区域：云同步与设置
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _buildNavItem(
                  context,
                  sidebarProvider,
                  homeStateProvider,
                  3,
                  Icons.cloud_outlined,
                  '云同步',
                  // 存在待用户确认的高风险同步时显示角标，提醒用户前往处理
                  showBadge: context.watch<CloudSyncProvider>().pendingRisk != null,
                ),
                _buildNavItem(
                  context,
                  sidebarProvider,
                  homeStateProvider,
                  4,
                  Icons.settings_rounded,
                  '设置',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // LOGO区域
  // ---------------------------------------------------------
  Widget _buildLogo(BuildContext context, HomeSidebarProvider sidebarProvider) {
    return Container(
      height: 48,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          // LOGO按钮区域（MouseRegion在外层，避免与InkWell嵌套冲突）
          MouseRegion(
            // 使用 Provider 的方法更新悬停状态，而不是 setState
            onEnter: (_) => sidebarProvider.setLogoHovered(true),
            onExit: (_) => sidebarProvider.setLogoHovered(false),
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                hoverColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                onTap: () {
                  // 使用 Provider 的方法切换展开状态，而不是 setState
                  sidebarProvider.toggleExpanded();
                },
                child: SizedBox(
                  width: 48,
                  height: 48,
                  // 根据悬停状态和展开状态显示不同图标
                  child: Icon(
                    sidebarProvider.isLogoHovered
                        ? (sidebarProvider.isExpanded
                              ? Icons.keyboard_double_arrow_left_rounded
                              : Icons.keyboard_double_arrow_right_rounded)
                        : Icons.ac_unit_rounded,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          if (sidebarProvider.isExpanded)
            Expanded(
              child: DragToMoveArea(
                // 加入 DragToMoveArea，让LOGO的文字区域也能拖动窗口，再套个OverflowBox，解决文字超出宽度时的闪烁问题
                child: OverflowBox(
                  maxWidth: 200,
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      GlobalConstants.appTitle,
                      style: context.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // 单个导航菜单项
  // ---------------------------------------------------------
  Widget _buildNavItem(
    BuildContext context,
    HomeSidebarProvider sidebarProvider,
    HomeStateProvider homeStateProvider,
    int index,
    IconData icon,
    String title, {
    bool showBadge = false,
  }) {
    // 使用 Provider 获取当前选中的页面索引
    final isSelected = homeStateProvider.selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;

    // 使用 TooltipTarget 包裹，在导航栏收起状态时显示带箭头的提示框
    return TooltipTarget(
      showTooltip: !sidebarProvider.isExpanded, // 仅在收起状态显示提示
      direction: TooltipDirection.right, // 提示框显示在右侧
      tooltipContent: Text(
        title,
        style: context.bodySmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Material(
          color: Colors.transparent,
          // 圆角高亮背景
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            hoverColor: colorScheme.primary.withValues(alpha: 0.1),
            onTap: () {
              // 使用 Provider 的方法设置页面，而不是调用父组件的回调函数
              homeStateProvider.setPageByIndex(index);
            },
            child: Container(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              height: 48,
              child: _buildSidebarItem(
                context: context,
                icon: icon,
                title: title,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                isExpanded: sidebarProvider.isExpanded,
                showBadge: showBadge,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 防止文字展开时溢出报错的底层 Row
  // ---------------------------------------------------------
  Widget _buildSidebarItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    Color? color,
    required bool isExpanded,
    bool showBadge = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48, // 固定宽度的图标区 (64 - 16 padding = 48)
          child: Center(
            // 角标用于提示存在待用户确认的内容，需要提醒时才显示
            child: Badge(
              isLabelVisible: showBadge,
              smallSize: 8,
              child: Icon(icon, color: color, size: isExpanded ? 20 : 24),
            ),
          ),
        ),
        // 文字区域 (使用 SingleChildScrollView + NeverScrollableScrollPhysics 解决动画溢出报错)
        if (isExpanded)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(), // 禁止手动滑动
              child: Transform.translate(
                offset: const Offset(0, -1.4), // 微调文字位置，负值向上，正值向下
                child: Text(
                  title,
                  style: context.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
