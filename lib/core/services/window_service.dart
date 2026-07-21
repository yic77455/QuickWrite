import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口服务类
///
/// 负责窗口的初始化配置，包括：
/// - 设置窗口大小、位置、最大化状态
/// - 配置窗口属性（标题栏、背景等）
/// - 显示窗口
/// - 首次启动时计算并保存居中位置
///
/// 窗口事件监听和状态管理已移至 WindowProvider 统一处理
class WindowService {
  // ================= 单例模式 =================
  static final WindowService instance = WindowService._internal();
  WindowService._internal();

  // ================= 初始化方法 =================

  /// 初始化主窗口
  ///
  /// - 缓存文件不存在时：窗口居中显示，根据屏幕分辨率计算初始大小，保存到缓存文件
  /// - 缓存文件存在时：从缓存文件恢复上次保存的窗口位置、大小和最大化状态
  Future<void> initializeMainWindow() async {
    // 确保窗口管理器已初始化
    await windowManager.ensureInitialized();

    // 获取窗体缓存服务实例
    final cache = WindowCacheService.instance;

    // 根据缓存文件是否存在决定使用哪种初始化策略
    // 注意：这里不依赖 SettingsService.isFirstLaunch，因为缓存文件可能被单独删除
    final bool hasCacheData = await cache.exists();

    // 配置窗口属性
    final WindowOptions windowOptions = WindowOptions(
      size: hasCacheData ? cache.mainWindowSize : await _getWindowSize(),
      minimumSize: const Size(1000, 700),
      center: !hasCacheData, // 无缓存时居中显示
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: GlobalConstants.appTitle,
    );

    // 应用窗口配置并显示
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 有缓存数据时，从缓存设置窗口位置
      if (hasCacheData) {
        await windowManager.setPosition(cache.mainWindowPosition);
      }
      await windowManager.show();
      await windowManager.focus();

      // 无缓存数据时，保存当前居中位置到缓存文件
      if (!hasCacheData) {
        await _saveInitialWindowPosition();
      }

      // 如果上次退出时窗口是最大化的，则恢复最大化状态
      if (cache.mainWindowIsMaximized) {
        await windowManager.maximize();
      }
    });
  }

  /// 初始化工作台窗口
  ///
  /// 从缓存文件恢复上次保存的窗口位置、大小和最大化状态
  Future<void> initializeWorkspaceWindow() async {
    await windowManager.ensureInitialized();
    
    // 获取窗体缓存服务实例
    final cache = WindowCacheService.instance;
    
    final WindowOptions windowOptions = WindowOptions(
      size: cache.workspaceWindowSize,
      minimumSize: const Size(1000, 700),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: '${GlobalConstants.appTitle} - 工作台',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 从缓存设置工作台窗口位置
      await windowManager.setPosition(cache.workspaceWindowPosition);
      await windowManager.show();
      await windowManager.focus();
      
      // 如果上次退出时窗口是最大化的，则恢复最大化状态
      if (cache.workspaceWindowIsMaximized) {
        await windowManager.maximize();
      }
    });
  }

  /// 保存首次启动时的窗口居中位置到缓存文件
  Future<void> _saveInitialWindowPosition() async {
    // 获取窗体缓存服务实例
    final cache = WindowCacheService.instance;
    
    // 获取窗口大小和位置
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();

    // 更新窗体设置缓存（主窗口和工作台窗口使用相同的初始位置，工作台稍微偏移）
    await cache.updateMainWindow(
      width: size.width,
      height: size.height,
      x: position.dx,
      y: position.dy,
    );
    await cache.updateWorkspaceWindow(
      width: size.width,
      height: size.height,
      x: position.dx + 30,
      y: position.dy + 30,
    );
  }

  /// 根据屏幕分辨率计算默认窗口大小
  Future<Size> _getWindowSize() async {
    // 获取屏幕分辨率
    final Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
    
    Size initialWindowSize;
    
    // 如果屏幕宽度大于1400，高度大于等于900，就将窗口大小设置为1200*900，否则就动态调整窗口大小
    if (primaryDisplay.size.width >= 1400 && primaryDisplay.size.height >= 900) {
      initialWindowSize = const Size(1200, 900);
    }
    else if (primaryDisplay.size.width > primaryDisplay.size.height * 1.35) {
      // 如果屏幕长宽比>1.35，就取高度做计算，取屏幕高度*1.35为窗口宽度，取屏幕高度的90%为窗口高度
      initialWindowSize = Size(primaryDisplay.size.height * 1.35, primaryDisplay.size.height * 0.9);
    }
    else {
      // 否则，就取宽度做计算
      initialWindowSize = Size(primaryDisplay.size.width, primaryDisplay.size.width / 1.5);
    }
    return initialWindowSize;
  }
}
