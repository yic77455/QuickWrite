import 'package:flutter/material.dart';

// 应用页面枚举，定义所有可用的页面
enum HomePageEnum {
  bookshelf(0, '书架'),
  stats(1, '码字统计'),
  recycle(2, '回收站'),
  settings(3, '设置');

  final int pageIndex;  // 页面索引
  final String title;  // 页面标题

  const HomePageEnum(this.pageIndex, this.title);
}

/// 应用状态管理 Provider
/// 
/// 使用 Provider 管理当前选中的页面状态，替代组件内部的 setState
class HomeStateProvider extends ChangeNotifier {
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
}
