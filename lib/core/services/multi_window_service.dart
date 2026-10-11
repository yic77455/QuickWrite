import 'dart:async';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 打开工作台窗口的结果
enum WorkspaceOpenResult {
  /// 新建了工作台窗口，需等待"工作台就绪"通知
  created,

  /// 窗口已存在，已发送聚焦请求
  focused,

  /// 主窗口未就绪或窗口创建失败
  failed,
}

/// 多窗口服务类
///
/// 负责管理工作台窗口的创建，使用 desktop_multi_window 包实现真正的多窗口支持
/// 使用 WindowMethodChannel 实现窗口间通信
class MultiWindowService {
  // ================= 单例模式 =================
  static final MultiWindowService instance = MultiWindowService._internal();
  MultiWindowService._internal();

  // ================= 窗口类型常量 =================
  
  /// 工作台窗口类型标识
  static const String workspaceWindowType = 'workspace';

  // ================= 方法通道常量 =================

  /// 关闭窗口方法名称
  static const String _methodWindowClosed = 'window_closed';

  /// 主题变化方法名称
  static const String _methodThemeChanged = 'theme_changed';

  /// 自定义主题配置变化方法名称
  static const String _methodThemeConfigChanged = 'theme_config_changed';

  /// 应用界面字体变化方法名称
  static const String _methodAppFontChanged = 'app_font_changed';

  /// 应用界面字号变化方法名称
  static const String _methodAppFontScaleChanged = 'app_font_scale_changed';

  /// 书籍更新方法名称（工作台保存章节后通知主窗口刷新书架）
  static const String _methodBookUpdated = 'book_updated';

  /// 聚焦窗口方法名称（主窗口请求子窗口聚焦到前台）
  static const String _methodFocusWindow = 'focus_window';

  /// 工作台就绪方法名称（子窗口初始化完成后通知主窗口）
  static const String _methodWorkspaceReady = 'workspace_ready';

  /// 请求关闭方法名称（主窗口请求子窗口处理未保存内容并关闭自身）
  static const String _methodRequestClose = 'request_close';

  // ================= 已打开窗口跟踪 =================
  
  /// 已打开的工作台窗口 bookId 集合（仅在主窗口中维护）
  final Set<String> _openedBookIds = {};

  /// 已打开的工作台窗口控制器映射（bookId -> WindowController）
  final Map<String, WindowController> _workspaceWindowControllers = {};

  /// 等待关闭的工作台窗口（bookId -> Completer），收到窗口关闭通知时完成
  final Map<String, Completer<void>> _pendingCloseWaiters = {};

  /// 主窗口ID（在主窗口初始化时设置）
  String? _mainWindowId;

  // ================= 主题变化回调 =================

  /// 主题变化回调（子窗口设置此回调来响应主窗口的主题变化）
  void Function(String themeMode)? onThemeChanged;

  /// 自定义主题配置变化回调（子窗口设置此回调来响应主窗口的自定义主题变化）
  void Function(String configJson)? onThemeConfigChanged;

  /// 应用界面字体变化回调（子窗口设置此回调来响应主窗口的界面字体变化）
  void Function(String fontFamily)? onAppFontChanged;

  /// 应用界面字号变化回调（子窗口设置此回调来响应主窗口的界面字号变化）
  void Function(double scale)? onAppFontScaleChanged;

  /// 书籍更新回调（主窗口设置此回调来响应工作台的书籍更新通知）
  /// 当工作台保存章节后，会调用此回通知书架刷新
  VoidCallback? onBookUpdated;

  /// 工作台就绪回调（子窗口初始化完成后通知主窗口）
  /// 主窗口收到此回调后应关闭加载弹窗
  VoidCallback? onWorkspaceReady;

  /// 关闭请求回调（子窗口设置此回调来处理主窗口的关闭请求）
  /// 返回 true 表示可以关闭，false 表示用户取消了关闭
  Future<bool> Function()? onRequestClose;

  // ================= 窗口创建方法 =================

  /// 初始化方法通道监听（主窗口调用）
  /// 
  /// [windowController] 主窗口的控制器
  Future<void> initMethodChannel(WindowController windowController) async {
    // 保存主窗口ID
    _mainWindowId = windowController.windowId;
    
    await windowController.setWindowMethodHandler((call) async {
      if (call.method == _methodWindowClosed) {
        final bookId = call.arguments as String?;
        if (bookId != null) {
          _openedBookIds.remove(bookId);
          _workspaceWindowControllers.remove(bookId);
          // 完成该窗口的关闭等待，主窗口的退出流程依赖它确认子窗口已关闭
          _pendingCloseWaiters.remove(bookId)?.complete();
          debugPrint('收到窗口关闭事件，bookId: $bookId');
        }
      } else if (call.method == _methodBookUpdated) {
        // 收到工作台的书籍更新通知，触发回调刷新书架
        debugPrint('收到书籍更新事件，准备刷新书架');
        onBookUpdated?.call();
      } else if (call.method == _methodWorkspaceReady) {
        // 收到子窗口的就绪通知，触发回调关闭加载弹窗
        debugPrint('收到工作台就绪事件');
        onWorkspaceReady?.call();
      }
      return null;
    });
    debugPrint('多窗口通信通道已初始化，主窗口ID: $_mainWindowId');
  }

  /// 初始化子窗口的方法通道监听（子窗口调用）
  /// 
  /// [windowController] 子窗口的控制器
  Future<void> initWorkspaceMethodChannel(WindowController windowController) async {
    await windowController.setWindowMethodHandler((call) async {
      if (call.method == _methodThemeChanged) {
        final themeMode = call.arguments as String?;
        if (themeMode != null && onThemeChanged != null) {
          debugPrint('收到主题变化事件: $themeMode');
          onThemeChanged!(themeMode);
        }
      } else if (call.method == _methodThemeConfigChanged) {
        final configJson = call.arguments as String?;
        if (configJson != null && onThemeConfigChanged != null) {
          debugPrint('收到自定义主题配置变化事件');
          onThemeConfigChanged!(configJson);
        }
      } else if (call.method == _methodAppFontChanged) {
        final fontFamily = call.arguments as String?;
        if (fontFamily != null && onAppFontChanged != null) {
          debugPrint('收到界面字体变化事件');
          onAppFontChanged!(fontFamily);
        }
      } else if (call.method == _methodAppFontScaleChanged) {
        final scale = (call.arguments as num?)?.toDouble();
        if (scale != null && onAppFontScaleChanged != null) {
          debugPrint('收到界面字号变化事件');
          onAppFontScaleChanged!(scale);
        }
      } else if (call.method == _methodFocusWindow) {
        // 收到主窗口的聚焦请求，使用 window_manager 让自己获得焦点
        debugPrint('收到聚焦请求，激活窗口');
        await windowManager.show();
        await windowManager.focus();
      } else if (call.method == _methodRequestClose) {
        // 收到主窗口的关闭请求：先由页面处理未保存内容，确认后再关闭自身
        final canClose = await onRequestClose?.call() ?? true;
        if (canClose) {
          // 窗口处于"阻止关闭"状态，此处的关闭会走完整的关闭流程
          await windowManager.close();
        }
        return canClose;
      }
      return null;
    });
    debugPrint('子窗口通信通道已初始化');
  }

  /// 打开工作台窗口
  ///
  /// [bookId] 要打开的书籍ID
  /// 返回本次打开的结果：若该书籍的窗口已存在则只聚焦已有窗口、不创建新窗口
  Future<WorkspaceOpenResult> openWorkspaceWindow(String bookId) async {
    // 检查是否已经打开了该书籍的窗口
    if (_openedBookIds.contains(bookId)) {
      debugPrint('书籍 $bookId 的窗口已存在，发送聚焦请求');
      // 窗口已存在，发送聚焦消息让子窗口自己用 window_manager 聚焦
      final existingController = _workspaceWindowControllers[bookId];
      if (existingController != null) {
        await existingController.invokeMethod(_methodFocusWindow, null);
      }
      return WorkspaceOpenResult.focused;
    }

    if (_mainWindowId == null) {
      debugPrint('主窗口ID未初始化，无法创建工作台窗口');
      return WorkspaceOpenResult.failed;
    }

    try {
      // 标记为已打开
      _openedBookIds.add(bookId);
      
      // 创建新窗口（隐藏状态，避免闪烁）
      final windowController = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true, // 先隐藏，等 Flutter 设置好位置和大小后再显示
          arguments: jsonEncode({
            'type': workspaceWindowType,
            'bookId': bookId,
            'mainWindowId': _mainWindowId,
          }),
        ),
      );
      
      // 保存窗口控制器
      _workspaceWindowControllers[bookId] = windowController;
      
      debugPrint('工作台窗口已创建，bookId: $bookId');
      return WorkspaceOpenResult.created;
    } catch (e) {
      // 创建失败，移除标记
      _openedBookIds.remove(bookId);
      debugPrint('创建工作台窗口失败: $e');
      return WorkspaceOpenResult.failed;
    }
  }

  /// 工作台窗口关闭时调用，通知主窗口
  ///
  /// [bookId] 要关闭的书籍ID
  /// [mainWindowId] 主窗口的ID
  Future<void> notifyWindowClosed(String bookId, String mainWindowId) async {
    try {
      // 向主窗口发送关闭事件
      final mainWindowController = WindowController.fromWindowId(mainWindowId);
      await mainWindowController.invokeMethod(
        _methodWindowClosed,
        bookId,
      );
      debugPrint('已发送窗口关闭事件，bookId: $bookId');
    } catch (e) {
      // 如果主窗口不存在或通信失败，记录错误但不抛出异常
      // 这样调用方可以继续执行关闭操作
      debugPrint('发送窗口关闭事件失败（主窗口可能已关闭）: $e');
    }
  }

  /// 关闭所有工作台窗口
  ///
  /// 依次请求每个工作台窗口关闭并等待其真正关闭后再处理下一个，
  /// 子窗口若有未保存内容会自行弹窗确认。返回 false 表示某个子窗口的用户
  /// 取消了关闭，调用方应中止后续的退出流程
  Future<bool> closeAllWorkspaces() async {
    for (final bookId in List<String>.from(_openedBookIds)) {
      if (!await _requestWorkspaceClose(bookId)) return false;
      await _waitForWorkspaceClosed(bookId);
    }
    return true;
  }

  /// 请求单个工作台窗口关闭，返回是否已确认关闭
  ///
  /// 窗口无法通信时视为已不存在，直接放行，避免退出流程被卡住
  Future<bool> _requestWorkspaceClose(String bookId) async {
    final controller = _workspaceWindowControllers[bookId];
    if (controller == null) return true;

    try {
      // 先把子窗口带到前台，确保它弹出的未保存提示能被用户看到
      await controller.invokeMethod(_methodFocusWindow, null);
      final confirmed = await controller.invokeMethod(_methodRequestClose, null);
      return confirmed == true;
    } catch (e) {
      debugPrint('请求工作台窗口关闭失败（窗口可能已不存在）: $e');
      return true;
    }
  }

  /// 等待工作台窗口关闭完成
  ///
  /// 依赖子窗口关闭时发来的通知；超时则放弃等待，避免退出流程停留过久
  Future<void> _waitForWorkspaceClosed(String bookId) async {
    if (!_openedBookIds.contains(bookId)) return;

    final completer = Completer<void>();
    _pendingCloseWaiters[bookId] = completer;
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('等待工作台窗口关闭超时，bookId: $bookId');
    } finally {
      _pendingCloseWaiters.remove(bookId);
    }
  }

  /// 工作台保存章节后调用，通知主窗口刷新书架数据
  ///
  /// [mainWindowId] 主窗口的ID
  Future<void> notifyBookUpdated(String mainWindowId) async {
    try {
      final mainWindowController = WindowController.fromWindowId(mainWindowId);
      await mainWindowController.invokeMethod(_methodBookUpdated, null);
      debugPrint('已发送书籍更新事件到主窗口');
    } catch (e) {
      // 主窗口可能已关闭，忽略错误
      debugPrint('发送书籍更新事件失败（主窗口可能已关闭）: $e');
    }
  }

  /// 工作台初始化完成后调用，通知主窗口关闭加载弹窗
  ///
  /// [mainWindowId] 主窗口的ID
  Future<void> notifyWorkspaceReady(String mainWindowId) async {
    try {
      final mainWindowController = WindowController.fromWindowId(mainWindowId);
      await mainWindowController.invokeMethod(_methodWorkspaceReady, null);
      debugPrint('已发送工作台就绪事件到主窗口');
    } catch (e) {
      // 主窗口可能已关闭，忽略错误
      debugPrint('发送工作台就绪事件失败（主窗口可能已关闭）: $e');
    }
  }

  /// 广播主题变化到所有子窗口（主窗口调用）
  ///
  /// [themeMode] 新的主题模式
  Future<void> broadcastThemeChange(String themeMode) async {
    // 广播到工作台窗口
    for (final controller in _workspaceWindowControllers.values) {
      try {
        await controller.invokeMethod(_methodThemeChanged, themeMode);
      } catch (e) {
        debugPrint('广播主题变化失败: $e');
      }
    }
    debugPrint('已广播主题变化到 ${_workspaceWindowControllers.length} 个子窗口');
  }

  /// 广播自定义主题配置变化到所有子窗口（主窗口调用）
  ///
  /// [configJson] 主题配置 JSON（含激活主题 ID 与自定义主题列表）
  Future<void> broadcastThemeConfig(String configJson) async {
    for (final controller in _workspaceWindowControllers.values) {
      try {
        await controller.invokeMethod(_methodThemeConfigChanged, configJson);
      } catch (e) {
        debugPrint('广播自定义主题配置失败: $e');
      }
    }
    debugPrint('已广播自定义主题配置到 ${_workspaceWindowControllers.length} 个子窗口');
  }

  /// 广播应用界面字体变化到所有子窗口（主窗口调用）
  ///
  /// [fontFamily] 界面字体名称，空字符串表示跟随系统默认字体
  Future<void> broadcastAppFontChange(String fontFamily) async {
    for (final controller in _workspaceWindowControllers.values) {
      try {
        await controller.invokeMethod(_methodAppFontChanged, fontFamily);
      } catch (e) {
        debugPrint('广播界面字体变化失败: $e');
      }
    }
    debugPrint('已广播界面字体变化到 ${_workspaceWindowControllers.length} 个子窗口');
  }

  /// 广播应用界面字号变化到所有子窗口（主窗口调用）
  ///
  /// [scale] 界面字号缩放倍数，1.0 表示默认大小
  Future<void> broadcastAppFontScaleChange(double scale) async {
    for (final controller in _workspaceWindowControllers.values) {
      try {
        await controller.invokeMethod(_methodAppFontScaleChanged, scale);
      } catch (e) {
        debugPrint('广播界面字号变化失败: $e');
      }
    }
    debugPrint('已广播界面字号变化到 ${_workspaceWindowControllers.length} 个子窗口');
  }

  /// 检查指定书籍的窗口是否已打开
  ///
  /// [bookId] 书籍ID
  bool isWorkspaceWindowOpen(String bookId) {
    return _openedBookIds.contains(bookId);
  }

  /// 检查是否有打开的工作台窗口
  bool hasOpenWorkspaceWindows() {
    return _openedBookIds.isNotEmpty;
  }
}
