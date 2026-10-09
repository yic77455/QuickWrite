import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/pages/home/home_page.dart';
import 'package:quick_write/pages/workspace/workspace_page.dart';

/// 应用根导航器的键
///
/// 供脱离页面上下文弹窗的场景使用（如同步风险确认），不依赖具体页面是否打开
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 全局路由实例
/// 
/// 负责管理应用的路由配置，包括：
/// - 路由表
/// - 处理路由跳转
/// - 注册 Provider，用于管理应用状态
final GoRouter appRouter = GoRouter(
  navigatorKey: appNavigatorKey,
  initialLocation: '/', // 软件启动后的第一个页面路径
  routes: [
    // 路由1：书架页 (根路径)
    GoRoute(
      path: '/',
      builder: (context, state) {
        // 注册应用状态 Provider，管理当前选中的页面
        return ChangeNotifierProvider(
          create: (_) => HomeStateProvider(),
          child: const HomePage(),
        );
      },
    ),

    // 路由2：工作台页 (带有动态参数 :bookId)
    GoRoute(
      // :bookId 是一个动态参数，比如 /workspace/123，那 bookId 就是 123
      path: '/workspace/:bookId',
      builder: (context, state) {
        // 从路由状态(state)中把 bookId 提取出来
        final bookId = state.pathParameters['bookId']!;
        
        // 在当前窗口中打开工作台
        // 设置保存回调：章节保存后自动刷新书架的最近编辑显示
        return WorkspacePage(
          bookId: bookId,
          onBookSaved: () {
            // 通过顶层 MultiProvider 获取 BookshelfProvider 并刷新数据
            context.read<BookshelfProvider>().refresh();
          },
        );
      },
    ),
  ],
  
  // 重定向逻辑：当需要在新窗口打开工作台时，阻止路由跳转
  redirect: (context, state) {
    // 检查是否是要跳转到工作台页面
    if (state.matchedLocation.startsWith('/workspace/')) {
      // 检查是否应该在新窗口中打开
      final openInNewWindow = SettingsService.instance.openWorkspaceInNewWindow;
      
      if (openInNewWindow) {
        // 提取 bookId
        final segments = state.matchedLocation.split('/');
        if (segments.length >= 3) {
          final bookId = segments[2];
          // 在新窗口中打开工作台
          MultiWindowService.instance.openWorkspaceWindow(bookId);
        }
        // 重定向回根路径，阻止页面跳转动画
        return '/';
      }
    }
    // 不需要重定向
    return null;
  },
);
