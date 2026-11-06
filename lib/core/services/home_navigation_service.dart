import 'package:flutter/foundation.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';

/// 主页内页面切换请求
///
/// 菜单栏等脱离页面上下文的位置无法直接访问页面级的 [HomeStateProvider]，
/// 通过该通知器把切换请求转交给主页处理
class HomeNavigationService {
  HomeNavigationService._();

  /// 待处理的页面切换请求，由主页监听并消费
  static final ValueNotifier<HomePageEnum?> request =
      ValueNotifier<HomePageEnum?>(null);

  /// 请求打开指定页面
  static void open(HomePageEnum page) {
    request.value = page;
  }

  /// 取出并清空待处理请求
  static HomePageEnum? consume() {
    final HomePageEnum? page = request.value;
    request.value = null;
    return page;
  }
}
