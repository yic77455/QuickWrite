import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口类型枚举
enum WindowType {
  /// 主窗口
  main,
  /// 工作台窗口
  workspace,
}

/// 窗口状态管理 Provider
///
/// 统一管理所有窗口相关的状态和事件监听，包括：
/// - 窗口最大化/最小化状态
/// - 窗口移动和调整大小事件
/// - 自动保存窗口位置、大小和最大化状态到缓存文件
class WindowProvider extends ChangeNotifier with WindowListener {
  // ================= 窗口状态 =================

  // 窗口是否最大化，默认为 false
  bool _isMaximized = false;

  // 窗口是否最小化，默认为 false
  bool _isMinimized = false;

  // 窗口类型，默认为主窗口
  final WindowType _windowType;

  // 工作台窗口的书籍ID（仅工作台窗口需要）
  final String? _bookId;

  // 主窗口的ID（仅工作台窗口需要，用于通信）
  final String? _mainWindowId;

  /// 关闭前回调，如果返回 false，则取消关闭
  Future<bool> Function()? onBeforeClose;

  /// 从最大化恢复时的回调，用于在窗口恢复前调整布局
  Future<void> Function()? onBeforeUnmaximize;

  // 获取窗口最大化状态
  bool get isMaximized => _isMaximized;

  // 获取窗口最小化状态
  bool get isMinimized => _isMinimized;

  // 获取窗口类型
  WindowType get windowType => _windowType;

  // 获取书籍ID
  String? get bookId => _bookId;

  // ================= 防抖相关 =================

  // 防抖用的 Timer，用于延迟保存窗口状态信息，避免频繁写入缓存文件
  Timer? _saveTimer;

  // ================= 构造函数 =================

  // 构造函数
  // [windowType] 窗口类型，默认为主窗口
  // [bookId] 书籍ID（仅工作台窗口需要）
  // [mainWindowId] 主窗口ID（仅工作台窗口需要，用于通信）
  WindowProvider({
    WindowType windowType = WindowType.main,
    String? bookId,
    String? mainWindowId,
  })  : _windowType = windowType,
        _bookId = bookId,
        _mainWindowId = mainWindowId {
    windowManager.addListener(this); // 注册窗口监听器
    // 所有的窗口都需要阻止直接关闭，以便在关闭前执行清理操作并通知主窗口
    windowManager.setPreventClose(true);
    _initWindowState(); // 初始化窗口状态
  }

  // ================= 初始化方法 =================

  // 初始化窗口状态
  // 从系统获取当前窗口的真实状态
  Future<void> _initWindowState() async {
    _isMaximized = await windowManager.isMaximized();
    _isMinimized = await windowManager.isMinimized();
    notifyListeners(); // 通知监听者状态已改变
  }

  // ================= 窗口事件回调 =================

  // 窗口最大化时的回调
  // 当用户点击最大化按钮时，系统会调用此方法
  @override
  void onWindowMaximize() {
    _isMaximized = true;
    notifyListeners(); // 通知监听者状态已改变
    _saveMaximizedState(true); // 保存最大化状态
  }

  // 窗口恢复时的回调
  // 当用户点击恢复按钮或双击标题栏时，系统会调用此方法
  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    notifyListeners(); // 通知监听者状态已改变
    // 恢复时保存完整状态（位置、大小、最大化状态）
    _debounceSave();
    // 延迟到当前 build 帧结束后再调整边栏宽度，避免在 build 阶段调用 notifyListeners 导致报错
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onBeforeUnmaximize?.call();
    });
  }

  // 窗口最小化时的回调
  // 当用户点击最小化按钮时，系统会调用此方法
  @override
  void onWindowMinimize() {
    _isMinimized = true;
    notifyListeners(); // 通知监听者状态已改变
  }

  // 窗口从最小化恢复时的回调
  // 当用户从任务栏恢复窗口时，系统会调用此方法
  @override
  void onWindowRestore() {
    _isMinimized = false;
    notifyListeners(); // 通知监听者状态已改变
  }

  // 窗口关闭时的回调
  // 当用户点击关闭按钮时，系统会调用此方法
  @override
  void onWindowClose() async {
    // 允许通过回调执行清理操作
    if (onBeforeClose != null) {
      final shouldClose = await onBeforeClose!();
      if (!shouldClose) return;
    }

    // 只有工作台窗口需要特殊处理（通知主窗口后再关闭）
    if (_windowType == WindowType.workspace && _bookId != null && _mainWindowId != null) {
      // 异步通知主窗口，使用 try-catch 确保即使通知失败也能正常关闭窗口
      MultiWindowService.instance.notifyWindowClosed(_bookId, _mainWindowId).then((_) {
        // 通知完成后，取消阻止关闭，然后关闭窗口
        return windowManager.setPreventClose(false);
      }).then((_) {
        windowManager.close();
      }).catchError((error) {
        // 即使通知失败，也要确保窗口能够关闭，避免卡死
        debugPrint('通知主窗口关闭事件失败: $error');
        windowManager.setPreventClose(false).then((_) {
          windowManager.close();
        });
      });
    } else {
      // 主窗口，或者不涉及通信的其他窗口，在执行完清理后取消阻止关闭并直接关闭
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  // 窗口调整大小后的回调，用户调整窗口大小时触发
  @override
  void onWindowResized() {
    // 只有非最大化状态时才保存窗口大小
    if (!_isMaximized) {
      _debounceSave();
    }
  }

  // 窗口移动后的回调，用户移动窗口时触发
  @override
  void onWindowMoved() {
    // 只有非最大化状态时才保存窗口位置
    if (!_isMaximized) {
      _debounceSave();
    }
  }

  // ================= 状态保存方法 =================

  // 防抖保存窗口状态
  // 避免频繁保存，只在用户停止操作 500ms 后保存
  void _debounceSave() {
    _saveTimer?.cancel(); // 取消之前的定时器
    _saveTimer = Timer(const Duration(milliseconds: 500), () async {
      await _saveWindowState();
    });
  }

  // 保存最大化状态到缓存文件
  // [isMaximized] 是否最大化
  Future<void> _saveMaximizedState(bool isMaximized) async {
    final cache = WindowCacheService.instance;

    // 根据窗口类型更新对应的缓存数据
    if (_windowType == WindowType.main) {
      await cache.updateMainWindow(isMaximized: isMaximized);
    } else {
      await cache.updateWorkspaceWindow(isMaximized: isMaximized);
    }
  }

  // 保存窗口状态到缓存文件
  // 包括窗口的位置、大小和最大化状态
  Future<void> _saveWindowState() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    final isMaximized = await windowManager.isMaximized();

    final cache = WindowCacheService.instance;

    // 根据窗口类型更新对应的缓存数据
    if (_windowType == WindowType.main) {
      await cache.updateMainWindow(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
        isMaximized: isMaximized,
      );
    } else {
      await cache.updateWorkspaceWindow(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
        isMaximized: isMaximized,
      );
    }
  }

  // ================= 窗口控制方法 =================

  // 最大化窗口
  // 点击最大化按钮时调用
  Future<void> maximize() async {
    await windowManager.maximize();
  }

  // 取消最大化窗口
  // 点击恢复按钮时调用
  Future<void> unmaximize() async {
    // 在窗口恢复前执行回调（如调整边栏宽度），避免恢复后溢出
    if (onBeforeUnmaximize != null) {
      await onBeforeUnmaximize!();
    }
    await windowManager.unmaximize();
  }

  // 最小化窗口
  // 点击最小化按钮时调用
  Future<void> minimize() async {
    await windowManager.minimize();
  }

  // 关闭窗口
  // 点击关闭按钮时调用
  Future<void> close() async {
    await windowManager.close();
  }

  // 销毁 Provider
  // 在 Provider 销毁时自动调用，清理资源，防止内存泄漏
  @override
  void dispose() {
    // 取消可能存在的防抖定时器
    _saveTimer?.cancel();
    // 注销窗口监听器
    windowManager.removeListener(this);
    // 调用父类的 dispose
    super.dispose();
  }
}
