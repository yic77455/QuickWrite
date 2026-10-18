import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:window_manager/window_manager.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/providers/home_sidebar_provider.dart';
import 'package:quick_write/core/providers/update_provider.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 侧边栏组件
///
/// 桌面端的固定侧边栏，可展开/折叠，承载全部主页面入口
class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 context.watch 监听 SidebarProvider 和 HomeStateProvider 的变化
    // 当状态改变时，会自动重新构建此组件
    final sidebarProvider = context.watch<HomeSidebarProvider>();
    final homeStateProvider = context.watch<HomeStateProvider>();
    final bool isExpanded = sidebarProvider.isExpanded;

    return _buildContainer(
      context,
      width: isExpanded ? 200 : 64, // 展开宽200，折叠宽64
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
              _buildNavItem(context, homeStateProvider, HomePageEnum.bookshelf, isExpanded: isExpanded),
              _buildNavItem(context, homeStateProvider, HomePageEnum.stats, isExpanded: isExpanded),
              _buildNavItem(context, homeStateProvider, HomePageEnum.recycle, isExpanded: isExpanded),
              _buildNavItem(
                context,
                homeStateProvider,
                HomePageEnum.about,
                isExpanded: isExpanded,
                // 启动检查发现有新版本时显示角标，提醒用户前往关于页查看
                showBadge: context.watch<UpdateProvider>().hasUpdate,
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
                homeStateProvider,
                HomePageEnum.cloudSync,
                isExpanded: isExpanded,
                // 存在待用户确认的高风险同步时显示角标，提醒用户前往处理
                showBadge: context.watch<CloudSyncProvider>().pendingRisk != null,
              ),
              _buildNavItem(context, homeStateProvider, HomePageEnum.settings, isExpanded: isExpanded),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // 侧边栏外框
  // ---------------------------------------------------------

  Widget _buildContainer(
    BuildContext context, {
    required double width,
    required List<Widget> children,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeInOut,
      width: width,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  // ---------------------------------------------------------
  // LOGO区域
  // ---------------------------------------------------------

  /// 桌面端 LOGO 区域：点击图标可展开/折叠侧边栏
  Widget _buildLogo(BuildContext context, HomeSidebarProvider sidebarProvider) {
    // LOGO 文字区域
    final Widget titleArea = _buildTitleArea(context);

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
                  // Center 提供松约束，避免图片被外层紧约束拉伸到 48
                  child: Center(
                    // 悬停时显示展开/折叠箭头，默认显示应用图标
                    child: sidebarProvider.isLogoHovered
                        ? Icon(
                            sidebarProvider.isExpanded
                                ? Icons.keyboard_double_arrow_left_rounded
                                : Icons.keyboard_double_arrow_right_rounded,
                            size: 24,
                          )
                        : _buildAppIcon(context),
                  ),
                ),
              ),
            ),
          ),
          if (sidebarProvider.isExpanded)
            Expanded(
              // 桌面端允许拖动该文字区域移动窗口，其他平台仅为普通文字
              child: PlatformCapabilities.supportsNativeWindowControl
                  ? DragToMoveArea(child: titleArea)
                  : titleArea,
            ),
        ],
      ),
    );
  }

  /// LOGO 文字区域：套 OverflowBox 解决文字超出宽度时的闪烁问题
  Widget _buildTitleArea(BuildContext context) {
    return OverflowBox(
      maxWidth: 200,
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          GlobalConstants.appTitle,
          style: context.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// 应用图标：浅色模式使用 icon1，深色模式使用 icon2
  Widget _buildAppIcon(BuildContext context) {
    return Image.asset(
      Theme.of(context).brightness == Brightness.dark
          ? 'assets/icon/icon2.png'
          : 'assets/icon/icon1.png',
      width: 36,
      height: 36,
      fit: BoxFit.contain, // 保持比例，避免拉伸变形
    );
  }

  // ---------------------------------------------------------
  // 单个导航菜单项
  // ---------------------------------------------------------
  Widget _buildNavItem(
    BuildContext context,
    HomeStateProvider homeStateProvider,
    HomePageEnum page, {
    required bool isExpanded,
    bool showBadge = false,
  }) {
    final isSelected = homeStateProvider.currentPage == page;
    final colorScheme = Theme.of(context).colorScheme;

    // 使用 TooltipTarget 包裹，在导航栏收起状态时显示带箭头的提示框
    return TooltipTarget(
      showTooltip: !isExpanded, // 仅在收起状态显示提示
      direction: TooltipDirection.right, // 提示框显示在右侧
      tooltipContent: Text(
        page.title,
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
              homeStateProvider.setPage(page);
            },
            child: Container(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              height: 48,
              child: _buildSidebarItem(
                context: context,
                icon: page.icon,
                title: page.title,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                isExpanded: isExpanded,
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