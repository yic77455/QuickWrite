import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

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

  /// 书籍更新方法名称（工作台保存章节后通知主窗口刷新书架）
  static const String _methodBookUpdated = 'book_updated';

  /// 聚焦窗口方法名称（主窗口请求子窗口聚焦到前台）
  static const String _methodFocusWindow = 'focus_window';

  /// 工作台就绪方法名称（子窗口初始化完成后通知主窗口）
  static const String _methodWorkspaceReady = 'workspace_ready';

  // ================= 已打开窗口跟踪 =================
  
  /// 已打开的工作台窗口 bookId 集合（仅在主窗口中维护）
  final Set<String> _openedBookIds = {};

  /// 已打开的工作台窗口控制器映射（bookId -> WindowController）
  final Map<String, WindowController> _workspaceWindowControllers = {};

  /// 主窗口ID（在主窗口初始化时设置）
  String? _mainWindowId;

  // ================= 主题变化回调 =================

  /// 主题变化回调（子窗口设置此回调来响应主窗口的主题变化）
  void Function(String themeMode)? onThemeChanged;

  /// 自定义主题配置变化回调（子窗口设置此回调来响应主窗口的自定义主题变化）
  void Function(String configJson)? onThemeConfigChanged;

  /// 书籍更新回调（主窗口设置此回调来响应工作台的书籍更新通知）
  /// 当工作台保存章节后，会调用此回通知书架刷新
  VoidCallback? onBookUpdated;

  /// 工作台就绪回调（子窗口初始化完成后通知主窗口）
  /// 主窗口收到此回调后应关闭加载弹窗
  VoidCallback? onWorkspaceReady;

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
      } else if (call.method == _methodFocusWindow) {
        // 收到主窗口的聚焦请求，使用 window_manager 让自己获得焦点
        debugPrint('收到聚焦请求，激活窗口');
        await windowManager.show();
        await windowManager.focus();
      }
      return null;
    });
    debugPrint('子窗口通信通道已初始化');
  }

  /// 打开工作台窗口
  ///
  /// [bookId] 要打开的书籍ID
  /// 如果该书籍的窗口已存在，则不会创建新窗口
  Future<bool> openWorkspaceWindow(String bookId) async {
    // 检查是否已经打开了该书籍的窗口
    if (_openedBookIds.contains(bookId)) {
      debugPrint('书籍 $bookId 的窗口已存在，发送聚焦请求');
      // 窗口已存在，发送聚焦消息让子窗口自己用 window_manager 聚焦
      final existingController = _workspaceWindowControllers[bookId];
      if (existingController != null) {
        await existingController.invokeMethod(_methodFocusWindow, null);
      }
      return false;
    }

    if (_mainWindowId == null) {
      debugPrint('主窗口ID未初始化，无法创建工作台窗口');
      return false;
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
      return true;
    } catch (e) {
      // 创建失败，移除标记
      _openedBookIds.remove(bookId);
      debugPrint('创建工作台窗口失败: $e');
      return false;
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
