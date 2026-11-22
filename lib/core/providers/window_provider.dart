import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/windows_fullscreen_channel.dart';
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

  // 窗口是否处于系统全屏，用于在尺寸切换期间跳过窗口状态的保存
  bool _isFullScreen = false;

  // 进入全屏前是否处于最大化，用于退出全屏后恢复最大化状态
  bool _maximizedBeforeFullScreen = false;

  // 进入全屏前的置顶状态，用于退出全屏后还原
  bool _alwaysOnTopBeforeFullScreen = false;

  // 本次全屏是否由原生通道进入，退出时需用同一套逻辑还原
  bool _enteredFullScreenNatively = false;

  // 窗口类型，默认为主窗口
  final WindowType _windowType;

  // 工作台窗口的书籍ID（仅工作台窗口需要）
  final String? _bookId;

  // 主窗口的ID（仅工作台窗口需要，用于通信）
  final String? _mainWindowId;

  /// 关闭拦截回调，在 [onBeforeClose] 之前执行
  ///
  /// 返回 true 表示继续执行后续关闭流程，返回 false 表示已拦截关闭（如最小化至托盘），
  /// 窗口保持打开状态
  Future<bool> Function()? onCloseIntercept;

  /// 关闭前回调，如果返回 false，则取消关闭
  Future<bool> Function()? onBeforeClose;

  /// 关闭确认后的回调，用于执行不可取消的收尾操作（如退出同步）
  ///
  /// 与 [onBeforeClose] 分开保存：窗口被多处复用时（如工作台与书架共用一个主窗口），
  /// 各处的关闭守卫只占用 [onBeforeClose]，收尾操作不会相互覆盖
  Future<void> Function()? onCloseConfirmed;

  /// 从最大化恢复时的回调，用于在窗口恢复前调整布局
  Future<void> Function()? onBeforeUnmaximize;

  /// 最大化完成后的回调，用于在窗口最大化后执行焦点恢复等后续处理
  Future<void> Function()? onAfterMaximize;

  /// 从最大化恢复完成后的回调，用于在窗口恢复后执行焦点恢复等后续处理
  Future<void> Function()? onAfterUnmaximize;

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
    // 窗口监听与状态依赖原生窗口，仅在支持原生窗口控制的平台注册
    if (PlatformCapabilities.supportsNativeWindowControl) {
      windowManager.addListener(this); // 注册窗口监听器
      // 所有的窗口都需要阻止直接关闭，以便在关闭前执行清理操作并通知主窗口
      windowManager.setPreventClose(true);
      _initWindowState(); // 初始化窗口状态
    }
  }

  // ================= 初始化方法 =================

  // 初始化窗口状态
  // 从系统获取当前窗口的真实状态
  Future<void> _initWindowState() async {
    _isMaximized = await windowManager.isMaximized();
    _isMinimized = await windowManager.isMinimized();
    _isFullScreen = await windowManager.isFullScreen();
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
    // 最大化完成后执行回调
    // 空闲阶段同步执行，使处理立即生效；build/layout 阶段则延迟到帧结束，避免在 build 中调用 notifyListeners 报错
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      onAfterMaximize?.call();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onAfterMaximize?.call();
      });
    }
  }

  // 窗口恢复时的回调
  // 当用户点击恢复按钮或双击标题栏时，系统会调用此方法
  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    notifyListeners(); // 通知监听者状态已改变
    // 恢复时保存完整状态（位置、大小、最大化状态）
    _debounceSave();
    // 调整边栏宽度以适配恢复后的窗口尺寸，并在恢复完成后执行回调（如焦点恢复）
    // 空闲阶段同步执行，使首帧即生效；build/layout 阶段则延迟到帧结束，避免在 build 中调用 notifyListeners 报错
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      onBeforeUnmaximize?.call();
      onAfterUnmaximize?.call();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onBeforeUnmaximize?.call();
        onAfterUnmaximize?.call();
      });
    }
  }

  // 窗口进入系统全屏时的回调
  @override
  void onWindowEnterFullScreen() {
    _isFullScreen = true;
  }

  // 窗口退出系统全屏时的回调
  @override
  void onWindowLeaveFullScreen() {
    _isFullScreen = false;
    // 保存退出全屏后恢复的窗口位置与大小
    _debounceSave();
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
    // 先执行关闭拦截，决定是退出程序还是最小化至托盘
    if (onCloseIntercept != null) {
      final shouldContinue = await onCloseIntercept!();
      if (!shouldContinue) return;
    }

    // 允许通过回调执行清理操作
    if (onBeforeClose != null) {
      final shouldClose = await onBeforeClose!();
      if (!shouldClose) return;
    }

    // 关闭已确认，执行不可取消的收尾操作
    await onCloseConfirmed?.call();

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
    _saveWindowStateOnChange();
  }

  // 窗口移动后的回调，用户移动窗口时触发
  @override
  void onWindowMoved() {
    _saveWindowStateOnChange();
  }

  // Linux 的 window_manager 只发出 resize / move（进行中）事件，不会发出
  // onWindowResized / onWindowMoved 对应的 resized / moved（插件把后两者
  // 标注为仅 macOS / Windows 支持）。只监听「已完成」事件时，Linux 上拖动
  // 或缩放窗口后缓存永远不会被更新，窗口大小与位置看起来就没有被记住。
  // 这里补上 Linux 分支，Windows / Android 行为保持不变。
  @override
  void onWindowResize() {
    if (!PlatformCapabilities.isLinux) return;
    _saveWindowStateOnChange();
  }

  @override
  void onWindowMove() {
    if (!PlatformCapabilities.isLinux) return;
    _saveWindowStateOnChange();
  }

  // 窗口尺寸或位置变化后安排一次防抖保存
  void _saveWindowStateOnChange() {
    // 最大化或全屏状态下窗口尺寸与位置不是用户设定的值，不保存
    if (_isMaximized || _isFullScreen) return;
    _debounceSave();
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
    // 全屏期间窗口铺满屏幕，其尺寸与位置不代表用户设定的窗口状态，不写入缓存
    if (_isFullScreen) return;

    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    final isMaximized = await windowManager.isMaximized();

    // 最大化尺寸不是用户设定的普通窗口大小，只记录最大化标志
    if (isMaximized) {
      await _saveMaximizedState(true);
      return;
    }

    // Wayland 下 GTK 读不到真实窗口位置（恒为 0,0），写入会覆盖缓存里
    // 原本有效的值；这种会话只更新尺寸与最大化状态，位置交回合成器管理。
    final bool skipPosition = PlatformCapabilities.isLinuxWayland;
    final double? x = skipPosition ? null : position.dx;
    final double? y = skipPosition ? null : position.dy;

    final cache = WindowCacheService.instance;

    // 根据窗口类型更新对应的缓存数据
    if (_windowType == WindowType.main) {
      await cache.updateMainWindow(
        width: size.width,
        height: size.height,
        x: x,
        y: y,
        isMaximized: isMaximized,
      );
    } else {
      await cache.updateWorkspaceWindow(
        width: size.width,
        height: size.height,
        x: x,
        y: y,
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

  // 设置系统全屏状态
  // 进入编辑区全屏时调用，使窗口铺满屏幕并覆盖任务栏
  Future<void> setFullScreen(bool fullscreen) async {
    if (_isFullScreen == fullscreen) return;

    if (fullscreen) {
      await _enterFullScreen();
    } else {
      await _exitFullScreen();
    }
  }

  // 进入系统全屏
  Future<void> _enterFullScreen() async {
    // 先标记全屏，避免切换过程中的尺寸与位置变化被当作普通缩放写入缓存
    _isFullScreen = true;
    // 以系统真实状态为准，避免状态事件丢失时走错分支
    _maximizedBeforeFullScreen = await windowManager.isMaximized();
    _alwaysOnTopBeforeFullScreen = await windowManager.isAlwaysOnTop();

    // 最大化窗口被系统限制在工作区，必须脱离最大化才能覆盖任务栏。
    // 原生通道把「脱离最大化 + 铺满显示器」放进一次调用，中间不产生可合成的帧
    _enteredFullScreenNatively = false;
    if (_maximizedBeforeFullScreen && PlatformCapabilities.isWindows) {
      _enteredFullScreenNatively =
          await WindowsFullScreenChannel.enterFullScreen();
    }

    if (!_enteredFullScreenNatively) {
      if (_maximizedBeforeFullScreen) {
        await windowManager.unmaximize();
        // 退最大化是异步投递的，等系统真正退出后再请求全屏，
        // 否则全屏尺寸会被最大化状态钳制在工作区
        for (int i = 0; i < 10 && await windowManager.isMaximized(); i++) {
          await Future.delayed(const Duration(milliseconds: 8));
        }
      }
      await windowManager.setFullScreen(true);
    }

    // 置顶显示，避免系统任务栏遮挡全屏内容
    await windowManager.setAlwaysOnTop(true);
    // 尺寸切换后立即提交完整帧，避免旧帧被拉伸成文字残影
    WidgetsBinding.instance.rootElement?.renderObject?.markNeedsPaint();
  }

  // 退出系统全屏
  Future<void> _exitFullScreen() async {
    final bool restoreMaximized = _maximizedBeforeFullScreen;
    _maximizedBeforeFullScreen = false;
    // 清除全屏标记，避免恢复后的窗口状态被跳过
    _isFullScreen = false;

    final bool native = _enteredFullScreenNatively;
    _enteredFullScreenNatively = false;
    if (native) {
      await WindowsFullScreenChannel.exitFullScreen();
    } else {
      await windowManager.setFullScreen(false);
    }
    // 还原进入全屏前的置顶状态
    await windowManager.setAlwaysOnTop(_alwaysOnTopBeforeFullScreen);

    // Windows 需同步恢复最大化；GTK 会自行还原 unfullscreen 前的状态
    if (restoreMaximized && PlatformCapabilities.isWindows) {
      if (!native) {
        await windowManager.maximize();
      }
      // 同步最大化不一定发出 SIZE_MAXIMIZED 事件，以系统真实状态为准
      _isMaximized = await windowManager.isMaximized();
      notifyListeners();
    } else {
      _debounceSave();
    }
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
    // 注销窗口监听器（与构造时的注册保持对应，仅支持原生窗口控制的平台注册过）
    if (PlatformCapabilities.supportsNativeWindowControl) {
      windowManager.removeListener(this);
    }
    // 调用父类的 dispose
    super.dispose();
  }
}
