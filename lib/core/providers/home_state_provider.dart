import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/material_icons.dart';

// 应用页面枚举，定义所有可用的页面及其导航标题、图标
enum HomePageEnum {
  bookshelf(0, '书架', Icons.auto_stories_rounded),
  stats(1, '码字统计', Icons.bar_chart_rounded, navLabel: '统计'),
  recycle(2, '回收站', MaterialIcons.delete),
  cloudSync(3, '云同步', Icons.cloud_outlined),
  settings(4, '设置', Icons.settings_rounded),
  about(5, '关于', Icons.info_outline_rounded),
  tools(6, '工具', Icons.grid_view_rounded);

  final int pageIndex; // 页面索引
  final String title; // 页面标题
  final IconData icon; // 导航中使用的图标
  final String? navLabel; // 底部导航栏中使用的简短标签，为空时使用 title

  const HomePageEnum(this.pageIndex, this.title, this.icon, {this.navLabel});
}

/// 应用状态管理 Provider
/// 
/// 使用 Provider 管理当前选中的页面状态，替代组件内部的 setState
///
/// 成员按平台归属分为两区：上半区为桌面端与移动端共用的页面状态，
/// 下半区为移动端导航专用（底部导航根页面与子页面返回），桌面端不读取其中任何成员。
class HomeStateProvider extends ChangeNotifier {
  // ================= 共用（桌面端 + 移动端） =================

  // 当前选中的页面，默认为书架
  HomePageEnum _currentPage = HomePageEnum.bookshelf;

  // 获取当前页面
  HomePageEnum get currentPage => _currentPage;

  // 获取当前页面的索引
  int get selectedIndex => _currentPage.pageIndex;

  // 设置当前页面
  // 当页面发生变化时，通知所有监听者更新 UI
  void setPage(HomePageEnum page) {
    if (_currentPage != page) {
      // 移动端专用：记录来源根页面，供子页面返回时定位来源（桌面端不依赖此字段）
      if (rootPages.contains(page)) _lastRootPage = page;
      _currentPage = page;
      notifyListeners();  // 通知监听者状态已改变
    }
  }

  // 通过索引设置页面
  // 用于通过数字索引切换页面
  void setPageByIndex(int index) {
    final page = HomePageEnum.values.firstWhere(
      (p) => p.pageIndex == index,
      orElse: () => HomePageEnum.bookshelf,  // 如果找不到对应索引，默认返回书架
    );
    setPage(page);
  }

  // ================= 移动端专用（桌面端不读取） =================

  // 在移动端底部导航中直接占位的根页面
  // 其余页面（云同步、回收站、关于）作为子页面，只能从根页面进入
  static const List<HomePageEnum> rootPages = [
    HomePageEnum.bookshelf,
    HomePageEnum.stats,
    HomePageEnum.tools,
    HomePageEnum.settings,
  ];

  // 最近停留的根页面
  // 子页面不在底部导航中单独占位，停留在其中时的高亮与返回都依据它定位来源页面
  HomePageEnum _lastRootPage = HomePageEnum.bookshelf;

  // 获取最近停留的根页面
  HomePageEnum get lastRootPage => _lastRootPage;

  // 当前页面是否为子页面（非在底部导航中直接占位的页面）
  bool get isSubPage => !rootPages.contains(_currentPage);

  // 返回最近停留的根页面
  // 子页面（云同步、回收站、关于）的返回入口统一走这里，无论从哪个根页面进入都能正确回退
  void backToRootPage() => setPage(_lastRootPage);
}
