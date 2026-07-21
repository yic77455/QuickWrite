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
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/theme/app_theme.dart';
import 'package:quick_write/pages/workspace/workspace_page.dart';

/// 主应用（书架页面）
class MyWriterApp extends StatelessWidget {
  const MyWriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 MultiProvider 包装应用，注册所有全局状态管理 Provider
    return MultiProvider(
      providers: [
        // 注册窗口状态 Provider，管理窗口的最大化/最小化状态
        ChangeNotifierProvider(create: (_) => WindowProvider()),
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
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            routerConfig: appRouter,
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
  }

  @override
  void dispose() {
    // 清理回调
    MultiWindowService.instance.onThemeChanged = null;
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
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            home: WorkspacePage(bookId: widget.bookId, mainWindowId: widget.mainWindowId),
          );
        },
      ),
    );
  }
}
