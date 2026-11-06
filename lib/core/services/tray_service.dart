import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/app_settings.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/router/router.dart';
import 'package:quick_write/core/services/home_navigation_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/shared/dialogs/close_action_dialog.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘服务
///
/// 负责创建托盘图标与右键菜单，并统一处理主窗口关闭时的行为：
/// 询问用户、退出程序或最小化至托盘
class TrayService with TrayListener {
  // ================= 单例模式 =================

  static final TrayService instance = TrayService._internal();
  TrayService._internal();

  // ================= 常量定义 =================

  /// Windows 托盘图标资源路径（ICO 格式）
  static const String _windowsIconPath = 'assets/icon/tray.ico';

  /// macOS 菜单栏图标资源路径
  ///
  /// macOS 图标只支持位图，且需要透明背景以便系统按模板图取色
  static const String _macOSIconPath = 'assets/icon/tray_macos.png';

  /// 右键菜单项：[显示主窗口]
  static const String _menuKeyShowWindow = 'show_main_window';

  /// 右键菜单项：[退出程序]
  static const String _menuKeyExit = 'exit_app';

  /// macOS 应用退出通道
  ///
  /// 原生层拦截菜单栏退出快捷键后，通过该通道转交 Dart 处理
  static const MethodChannel _macOSLifecycleChannel = MethodChannel(
    'quick_write/app_lifecycle',
  );

  // ================= 状态属性 =================

  /// 是否已启动托盘服务
  bool _started = false;

  /// 当前托盘图标是否已显示
  bool _iconVisible = false;

  /// 是否由托盘菜单发起的退出
  ///
  /// 为 true 时关闭拦截跳过关闭行为的询问，直接退出程序
  bool _exitRequested = false;

  // ================= 初始化与销毁 =================

  /// 启动托盘服务（仅主窗口调用一次）
  Future<void> initialize() async {
    if (_started) return;
    _started = true;

    trayManager.addListener(this);
    // 关闭行为变化时同步托盘的显隐（含多窗口模式的强制行为）
    SettingsService.instance.addListener(_syncIconVisibility);
    await _syncIconVisibility();

    // macOS 的菜单栏退出快捷键不会经过窗口关闭拦截，需要单独接管
    await _initMacOSQuitHandler();
  }

  /// 停止托盘服务并注销事件监听
  Future<void> dispose() async {
    if (!_started) return;
    _started = false;

    SettingsService.instance.removeListener(_syncIconVisibility);
    trayManager.removeListener(this);
    await _destroyIcon();
  }

  // ================= 托盘图标显隐 =================

  /// 按当前关闭行为同步托盘图标的显隐
  ///
  /// 关闭行为为"退出程序"时不会用到托盘，无需显示图标
  Future<void> _syncIconVisibility() async {
    if (SettingsService.instance.effectiveCloseWindowAction ==
        AppSettings.closeActionExit) {
      await _destroyIcon();
    } else {
      await _createIcon();
    }
  }

  /// 创建托盘图标与右键菜单
  Future<void> _createIcon() async {
    if (_iconVisible) return;
    _iconVisible = true;

    await trayManager.setIcon(
      PlatformCapabilities.isMacOS ? _macOSIconPath : _windowsIconPath,
      // macOS 使用模板图，由系统根据菜单栏明暗自动着色
      isTemplate: PlatformCapabilities.isMacOS,
    );
    await trayManager.setToolTip(GlobalConstants.appTitle);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: _menuKeyShowWindow,
            label: '显示主窗口',
            onClick: (_) => showMainWindow(),
          ),
          MenuItem.separator(),
          MenuItem(
            key: _menuKeyExit,
            label: '退出',
            onClick: (_) => requestExit(),
          ),
        ],
      ),
    );
  }

  /// 销毁托盘图标
  Future<void> _destroyIcon() async {
    if (!_iconVisible) return;
    _iconVisible = false;
    await trayManager.destroy();
  }

  // ================= 托盘事件回调 =================

  @override
  void onTrayIconMouseDown() {
    // 左键单击托盘图标时显示并聚焦主窗口
    showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 托盘右键不会自动弹出菜单，需要手动弹出
    trayManager.popUpContextMenu();
  }

  // ================= 窗口显示与退出 =================

  /// 注册 macOS 退出通道
  ///
  /// macOS 菜单栏的退出快捷键由系统直接发起终止，不经过窗口关闭拦截。
  /// 原生层收到终止请求后通知本通道，由 Dart 走正常的退出流程，
  /// 完成子窗口保存确认与退出同步后再结束进程
  Future<void> _initMacOSQuitHandler() async {
    if (!PlatformCapabilities.isMacOS) return;

    _macOSLifecycleChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestQuit':
          await requestExit();
        case 'showMainWindow':
          await showMainWindow();
        case 'openSettings':
          await _openHomePage(HomePageEnum.settings);
        case 'openAbout':
          await _openHomePage(HomePageEnum.about);
      }
    });

    // 告知原生层 Dart 已能处理退出请求，此后退出快捷键才转交 Dart
    try {
      await _macOSLifecycleChannel.invokeMethod('ready');
    } catch (e) {
      debugPrint('注册 macOS 退出通道失败: $e');
    }
  }

  /// 打开主页内的指定页面
  ///
  /// 菜单栏入口可能在工作台等其他路由下触发，先回到主页再切换页面
  Future<void> _openHomePage(HomePageEnum page) async {
    if (appRouter.state.matchedLocation != '/') {
      appRouter.go('/');
      // 等待主页挂载完成后再发出切换请求
      await WidgetsBinding.instance.endOfFrame;
    }
    HomeNavigationService.open(page);
  }

  /// 显示并聚焦主窗口（最小化状态会自动还原）
  Future<void> showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// 请求退出程序
  ///
  /// 先依次关闭所有工作台窗口，其中未保存的内容由各子窗口自行弹窗确认；
  /// 任一子窗口取消关闭时中止退出，全部关闭后再关闭主窗口结束进程
  Future<void> requestExit() async {
    if (!await _closeWorkspacesBeforeExit()) return;

    _exitRequested = true;
    await windowManager.close();
  }

  // ================= 关闭拦截 =================

  /// 退出前关闭所有工作台窗口
  ///
  /// 返回 true 表示工作台窗口已全部关闭（可以继续退出），
  /// false 表示某个子窗口的用户取消了关闭（应中止退出）
  Future<bool> _closeWorkspacesBeforeExit() async {
    if (!MultiWindowService.instance.hasOpenWorkspaceWindows()) return true;

    // 主窗口可能已隐藏至托盘，先显示出来，否则用户看不到子窗口的保存提示
    await windowManager.show();
    return MultiWindowService.instance.closeAllWorkspaces();
  }

  /// 主窗口关闭拦截
  ///
  /// 返回 true 表示继续执行关闭流程（退出程序），
  /// 返回 false 表示已拦截关闭（最小化至托盘），窗口保持打开
  Future<bool> handleCloseIntercept() async {
    // 托盘菜单发起的退出无需再次询问
    if (_exitRequested) {
      _exitRequested = false;
      return true;
    }

    switch (SettingsService.instance.effectiveCloseWindowAction) {
      case AppSettings.closeActionExit:
        return await _closeWorkspacesBeforeExit();
      case AppSettings.closeActionTray:
        await windowManager.hide();
        return false;
    }

    // 未记住选择时弹窗询问用户
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      // 无法弹窗时按退出处理，避免窗口无法关闭
      return await _closeWorkspacesBeforeExit();
    }

    final choice = await showCloseActionDialog(context: context);
    if (choice == null) {
      // 用户取消，保持窗口打开
      return false;
    }
    if (choice.remember) {
      await SettingsService.instance.updateCloseWindowAction(choice.action);
    }
    if (choice.action == AppSettings.closeActionTray) {
      await windowManager.hide();
      return false;
    }
    return await _closeWorkspacesBeforeExit();
  }
}
