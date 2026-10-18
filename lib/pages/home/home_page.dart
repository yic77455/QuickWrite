import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/core/providers/recycle_bin_provider.dart';
import 'package:quick_write/core/providers/home_sidebar_provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/core/providers/update_provider.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/pages/home/about/about_page.dart';
import 'package:quick_write/pages/home/bookshelf/bookshelf.dart';
import 'package:quick_write/pages/home/cloud_sync/cloud_sync_page.dart';
import 'package:quick_write/pages/home/recycle_bin/recycle_bin_page.dart';
import 'package:quick_write/pages/home/settings/settings_page.dart';
import 'package:quick_write/pages/home/statistics/stats_page.dart';
import 'package:quick_write/pages/home/tools/tools_page.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'sidebar/sidebar.dart';

/// 主页面
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 云同步 Provider 提升到主页面层级，使侧边栏的待确认角标与云同步页面共享同一状态
    return ChangeNotifierProvider(
      create: (context) => CloudSyncProvider(),
      // 移动端采用底部导航栏，桌面端保留固定侧边栏
      child: PlatformCapabilities.isMobile
          ? const _CompactHomeShell()
          : const _DesktopHomeShell(),
    );
  }
}

// ---------------------------------------------------------
// 桌面与移动端共用的构件
// ---------------------------------------------------------

/// 构建主页面的页面列表
///
/// 索引顺序与 HomePageEnum.pageIndex 保持一致
List<Widget> _buildHomePages() {
  return [
    // Index 0: 书架
    // 注册书架 Provider，管理书籍列表
    const BookshelfPage(),

    // Index 1: 码字统计（Provider 已在 app 级别注册，便于书架页面更新时自动刷新）
    const StatsPage(),

    // Index 2: 回收站
    // 注册回收站 Provider，管理回收站数据
    ChangeNotifierProvider(create: (context) => RecycleBinProvider(), child: const RecycleBinPage()),

    // Index 3: 云同步（Provider 已在主页面层级注册，侧边栏的待确认角标需要共用）
    const CloudSyncPage(),

    // Index 4: 全局设置
    const SettingsPage(),

    // Index 5: 关于
    const AboutPage(),

    // Index 6: 工具（仅移动端底部导航使用）
    const ToolsPage(),
  ];
}

// 标题栏右侧的主题切换按钮
Widget _buildThemeToggle(BuildContext context) {
  // 使用 context.watch 监听 ThemeProvider 的变化
  final themeProvider = context.watch<ThemeProvider>();
  return SizedBox(
    width: 32,
    height: 32,
    child: IconButton(
      icon: Icon(
        themeProvider.themeMode == ThemeMode.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
      ),
      onPressed: () => themeProvider.setThemeMode(
        themeProvider.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      ),
    ),
  );
}

// ---------------------------------------------------------
// 桌面端外壳：固定侧边栏 + 内容区
// ---------------------------------------------------------

// 右侧内容
// 使用 Provider 获取当前选中的页面索引，并以 IndexedStack 保留各页面状态
Widget _buildDesktopHomeContent(BuildContext context) {
  // 使用 context.watch 监听 HomeStateProvider 的变化
  // 当 selectedIndex 改变时，会自动重新构建此组件
  final selectedIndex = context.watch<HomeStateProvider>().selectedIndex;

  return IndexedStack(index: selectedIndex, children: _buildHomePages());
}

class _DesktopHomeShell extends StatelessWidget {
  const _DesktopHomeShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 最外层放弃用 appBar，直接用 Row 铺满全屏，解决之前的溢出问题
      body: Row(
        children: [
          // 左侧侧边栏
          // 不再需要传递 selectedIndex 和 onIndexChanged，状态由 Provider 管理
          // 注册侧边栏状态 Provider，管理侧边栏的展开/收起状态
          ChangeNotifierProvider(create: (context) => HomeSidebarProvider(), child: const SidebarWidget()),
          // 右侧主区域，Expanded 极其重要：它约束了右侧区域的宽度，防止内部组件引发无限尺寸错误
          Expanded(
            child: Scaffold(
              // 标题栏放在内部 Scaffold 中，给侧边栏让出左侧空间
              appBar: AppTitleBar(height: 40, actions: [_buildThemeToggle(context)]),
              // 根据选中索引，显示右侧内容
              body: _buildDesktopHomeContent(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// 移动端外壳：底部导航栏 + 左侧抽屉 + 内容区
// ---------------------------------------------------------

class _CompactHomeShell extends StatefulWidget {
  const _CompactHomeShell();

  @override
  State<_CompactHomeShell> createState() => _CompactHomeShellState();
}

class _CompactHomeShellState extends State<_CompactHomeShell> {
  /// 子页面的索引集合
  ///
  /// 不在底部导航中占位的页面（云同步、回收站、关于）作为子页面，
  /// 进入与返回它们时播放滑动动效
  static final Set<int> _subPageIndices = HomePageEnum.values
      .where((page) => !HomeStateProvider.rootPages.contains(page))
      .map((page) => page.pageIndex)
      .toSet();

  /// 连续两次返回的间隔阈值，超过该时长则重新开始计数
  static const Duration _backExitInterval = Duration(seconds: 2);

  /// 上一次按下返回键的时间，用于判断是否退出应用
  DateTime? _lastBackPressedAt;

  /// 处理系统返回操作
  ///
  /// 停留在子页面时返回其来源的根页面；处于底部导航页面时，
  /// 首次返回给出提示，在 [_backExitInterval] 内再次返回则退出应用。
  void _handlePop(bool didPop, HomeStateProvider homeState) {
    if (didPop) return;

    // 子页面：返回来源的根页面
    if (homeState.isSubPage) {
      homeState.backToRootPage();
      return;
    }

    // 底部导航页面：首次返回提示用户，短时间内再次返回则退出应用
    final now = DateTime.now();
    final lastPressedAt = _lastBackPressedAt;
    if (lastPressedAt == null || now.difference(lastPressedAt) > _backExitInterval) {
      _lastBackPressedAt = now;
      SnackBarService.show(context, '再按一次退出应用');
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final homeState = context.watch<HomeStateProvider>();

    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // 系统栏样式：状态栏与系统导航栏均为透明，让应用界面延伸到系统栏后方，
    // 图标颜色随主题明暗切换
    final SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: theme.brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    // 返回键处理：停留在子页面时返回其来源页面，处于底部导航页面时连续两次返回退出应用
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => _handlePop(didPop, homeState),
        child: Scaffold(
          // 不设置 AppBar：页面标题由各页面内部展示，顶部空间全部留给内容
          // 各页面自身未处理状态栏内边距，此处统一避开顶部安全区
          // 内容区：底部导航页面之间切换无动效，进入或返回子页面时播放滑动动效
          body: SafeArea(
            child: MobilePageStack(
              index: homeState.selectedIndex,
              subPageIndices: _subPageIndices,
              children: _buildHomePages(),
            ),
          ),
          bottomNavigationBar: _CompactBottomBar(
            pages: HomeStateProvider.rootPages,
            selectedIndex: _primaryIndexOf(homeState),
            onSelected: (index) => homeState.setPage(HomeStateProvider.rootPages[index]),
          ),
        ),
      ),
    );
  }

  /// 计算底部导航栏的选中项索引
  ///
  /// 子页面停留期间底部导航高亮其来源的根页面以便点击返回；
  /// 其余页面返回其在底部导航中的位置。
  int _primaryIndexOf(HomeStateProvider homeState) {
    final rootPages = HomeStateProvider.rootPages;
    if (homeState.isSubPage) return rootPages.indexOf(homeState.lastRootPage);
    return rootPages.indexOf(homeState.currentPage);
  }
}

// ---------------------------------------------------------
// 移动端底部导航栏
// ---------------------------------------------------------

/// 移动端底部导航栏
///
/// 与 Material 自带的 NavigationBar 不同，它不使用选中指示胶囊，
/// 仅通过图标与文字的高亮表现当前页面。
class _CompactBottomBar extends StatelessWidget {
  const _CompactBottomBar({required this.pages, required this.selectedIndex, required this.onSelected});

  /// 需要展示的页面
  final List<HomePageEnum> pages;

  /// 当前选中项索引
  final int selectedIndex;

  /// 选中某项时的回调
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 启动检查发现有新版本时，在设置项图标上叠加红点提示
    final bool hasUpdate = context.watch<UpdateProvider>().hasUpdate;

    return Material(
      // 复用全局导航栏主题的背景色，保持与整体风格一致
      color: theme.navigationBarTheme.backgroundColor ?? theme.colorScheme.surface,
      // 避开系统底部导航栏/手势条，避免导航项被遮挡
      child: SafeArea(
        top: false,
        child: SizedBox(
          // 底部导航栏高度
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < pages.length; i++)
                Expanded(
                  child: _buildItem(
                    context,
                    i,
                    // 仅设置项需要承载「有更新」提示
                    showBadge: hasUpdate && pages[i] == HomePageEnum.settings,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单个导航项
  ///
  /// 选中项以主题主色高亮图标与文字，未选中项使用次级文字色。
  Widget _buildItem(BuildContext context, int index, {bool showBadge = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isSelected = index == selectedIndex;
    final Color color = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () => onSelected(index),
      // 关闭水波纹与按压高亮，点击时不再出现矩形动效
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 角标仅在需要提示时显示，用于提醒用户存在可用更新
          Badge(
            isLabelVisible: showBadge,
            smallSize: 8,
            child: Icon(pages[index].icon, size: 24, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            // 统计等较长名称在底部导航栏使用简短标签
            pages[index].navLabel ?? pages[index].title,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}