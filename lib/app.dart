import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/providers/writing_stats_provider.dart';
import 'package:quick_write/core/router/router.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/tray_service.dart';
import 'package:quick_write/pages/workspace/workspace_page.dart';
import 'package:window_manager/window_manager.dart';

/// 主窗口关闭后的收尾：先把窗口藏起来，在后台完成退出同步
///
/// 隐藏窗口后同步在后台静默进行，界面不再占用桌面；同步结束后
/// 窗口流程才真正关闭应用，因此用户感受不到等待过程
Future<void> _handleMainWindowExit() async {
  if (!CloudSyncService.instance.willSyncOnExit) return;

  await windowManager.hide();
  await CloudSyncService.instance.handleAppExit();
}

/// 将应用内容包裹在按界面字号缩放的 MediaQuery 中
///
/// [scale] 界面字号缩放倍数，1.0 表示默认大小；
/// 编辑器内容会在其所在位置排除该缩放，从而保持独立的字体大小设置
Widget _wrapWithAppFontScale(BuildContext context, Widget? child, double scale) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child ?? const SizedBox.shrink(),
  );
}

/// 主应用（书架页面）
class MyWriterApp extends StatelessWidget {
  const MyWriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 MultiProvider 包装应用，注册所有全局状态管理 Provider
    return MultiProvider(
      providers: [
        // 注册窗口状态 Provider，管理窗口的最大化/最小化状态
        // 主窗口界面不直接读取该 Provider，需立即创建才能注册窗口监听并拦截关闭
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => WindowProvider()
            // 关闭拦截：按设置决定退出程序还是最小化至托盘
            ..onCloseIntercept = TrayService.instance.handleCloseIntercept
            // 关闭确认后先隐藏窗口，在后台完成退出同步
            ..onCloseConfirmed = _handleMainWindowExit,
        ),
        // 注册主题状态 Provider，管理应用的主题模式
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        // 注册书架 Provider，管理书籍列表
        ChangeNotifierProvider(create: (_) => BookshelfProvider()),
        // 注册码字统计 Provider，管理统计数据与筛选状态
        ChangeNotifierProvider(create: (_) => WritingStatsProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp.router(
            // 本地化代理
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // 支持的语言
            supportedLocales: [
              const Locale('zh', 'CN'), // 简体中文
            ],
            // 强制中文
            locale: const Locale('zh', 'CN'),
            title: GlobalConstants.appTitle,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            routerConfig: appRouter,
            // 应用界面字号缩放：包裹整个界面，使界面文字按设定倍数显示
            builder: (context, child) =>
                _wrapWithAppFontScale(context, child, themeProvider.appFontScale),
          );
        },
      ),
    );
  }
}

/// 工作台应用（独立窗口）
class WorkspaceApp extends StatefulWidget {
  final String bookId;
  final String? mainWindowId;

  const WorkspaceApp({super.key, required this.bookId, this.mainWindowId});

  @override
  State<WorkspaceApp> createState() => _WorkspaceAppState();
}

class _WorkspaceAppState extends State<WorkspaceApp> {
  // 主题 Provider
  ThemeProvider? _themeProvider;

  @override
  void initState() {
    super.initState();
    _initWindowChannel();
  }

  /// 初始化窗口通信通道
  Future<void> _initWindowChannel() async {
    final windowController = await WindowController.fromCurrentEngine();
    await MultiWindowService.instance.initWorkspaceMethodChannel(
      windowController,
    );

    // 设置主题变化回调
    MultiWindowService.instance.onThemeChanged = (themeModeName) {
      if (_themeProvider != null) {
        _themeProvider!.updateThemeFromMain(themeModeName);
      }
    };

    // 设置自定义主题配置变化回调
    MultiWindowService.instance.onThemeConfigChanged = (configJson) {
      if (_themeProvider != null) {
        _themeProvider!.updateThemeConfigFromMain(configJson);
      }
    };

    // 设置界面字体变化回调
    MultiWindowService.instance.onAppFontChanged = (fontFamily) {
      if (_themeProvider != null) {
        _themeProvider!.updateAppFontFromMain(fontFamily);
      }
    };

    // 设置界面字号变化回调
    MultiWindowService.instance.onAppFontScaleChanged = (scale) {
      if (_themeProvider != null) {
        _themeProvider!.updateAppFontScaleFromMain(scale);
      }
    };
  }

  @override
  void dispose() {
    // 清理回调
    MultiWindowService.instance.onThemeChanged = null;
    MultiWindowService.instance.onThemeConfigChanged = null;
    MultiWindowService.instance.onAppFontChanged = null;
    MultiWindowService.instance.onAppFontScaleChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 注册窗口状态 Provider，指定为工作台窗口类型，并传入书籍ID和主窗口ID
        ChangeNotifierProvider(
          create: (_) => WindowProvider(
            windowType: WindowType.workspace,
            bookId: widget.bookId,
            mainWindowId: widget.mainWindowId,
          ),
        ),
        // 注册主题状态 Provider，管理应用的主题模式
        ChangeNotifierProvider(
          create: (context) {
            _themeProvider = ThemeProvider();
            return _themeProvider!;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: '${GlobalConstants.appTitle} - 工作台',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            home: WorkspacePage(bookId: widget.bookId, mainWindowId: widget.mainWindowId),
            // 应用界面字号缩放：包裹整个界面，使界面文字按设定倍数显示
            builder: (context, child) =>
                _wrapWithAppFontScale(context, child, themeProvider.appFontScale),
          );
        },
      ),
    );
  }
}
