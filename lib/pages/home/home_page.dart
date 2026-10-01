import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/core/providers/recycle_bin_provider.dart';
import 'package:quick_write/core/providers/home_sidebar_provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/pages/home/bookshelf/bookshelf.dart';
import 'package:quick_write/pages/home/cloud_sync/cloud_sync_page.dart';
import 'package:quick_write/pages/home/recycle_bin/recycle_bin_page.dart';
import 'package:quick_write/pages/home/settings/settings_page.dart';
import 'package:quick_write/pages/home/statistics/stats_page.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'sidebar/sidebar.dart';

/// 主页面
class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
          // 右侧主区域，Expanded 极其重要：它约束了右侧区域的宽度，防止内部组件引发无限尺寸错误，狗日的溢出错误卡了我两个多小时
          Expanded(
            child: Scaffold(
              // 标题栏放在内部 Scaffold 中，给侧边栏让出左侧空间
              appBar: _homeTitleBar(context),
              // 根据选中索引，显示右侧内容
              body: _buildMainContent(context),
            ),
          ),
        ],
      ),
    );
  }

  // 右侧内容
  // 使用 Provider 获取当前选中的页面索引
  Widget _buildMainContent(BuildContext context) {
    // 使用 context.watch 监听 HomeStateProvider 的变化
    // 当 selectedIndex 改变时，会自动重新构建此组件
    final selectedIndex = context.watch<HomeStateProvider>().selectedIndex;

    return IndexedStack(
      index: selectedIndex,
      children: [
        // Index 0: 书架
        // 注册书架 Provider，管理书籍列表
        const BookshelfPage(),

        // Index 1: 码字统计（Provider 已在 app 级别注册，便于书架页面更新时自动刷新）
        const StatsPage(),

        // Index 2: 回收站
        // 注册回收站 Provider，管理回收站数据
        ChangeNotifierProvider(create: (context) => RecycleBinProvider(), child: const RecycleBinPage()),

        // Index 3: 云同步
        // 注册云同步 Provider，管理连接状态与同步设置
        ChangeNotifierProvider(create: (context) => CloudSyncProvider(), child: const CloudSyncPage()),

        // Index 4: 全局设置
        const SettingsPage(),
      ],
    );
  }

  // 标题栏
  PreferredSizeWidget _homeTitleBar(BuildContext context) {
    // 使用 context.watch 监听 ThemeProvider 的变化
    final themeProvider = context.watch<ThemeProvider>();
    return AppTitleBar(
      height: 40,
      actions: [
        SizedBox(
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
        ),
      ],
    );
  }
}
