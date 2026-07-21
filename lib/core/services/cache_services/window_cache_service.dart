import 'package:flutter/material.dart';
import 'package:quick_write/core/models/cache_models/window_settings.dart';
import 'package:quick_write/core/services/cache_services/cache_service.dart';

/// 窗体设置缓存服务
///
/// 专门管理窗体相关的临时性数据，使用独立的缓存文件（window.cache）
/// 
/// 缓存内容包括：
/// - 主窗口：大小、位置、最大化状态
/// - 工作台窗口：大小、位置、最大化状态
/// - 侧边栏：主界面和工作台的展开状态
///
/// 使用方式：
/// ```dart
/// // 初始化（在 main.dart 中）
/// await WindowCacheService.instance.initialize();
///
/// // 读取数据（同步）
/// final size = WindowCacheService.instance.data.mainWindowSize;
///
/// // 更新并保存（异步）
/// await WindowCacheService.instance.updateMainWindow(width: 1200, height: 900);
/// ```
class WindowCacheService extends CacheService<WindowSettingsData> {
  // ================= 单例模式 =================

  static final WindowCacheService instance = WindowCacheService._internal();

  /// 私有构造函数
  WindowCacheService._internal() : super('window');

  // ================= 状态属性 =================

  /// 当前缓存的窗体设置数据（内存中的副本）
  WindowSettingsData _data = WindowSettingsData.defaults;

  /// 获取当前窗体设置数据（只读访问）
  ///
  /// 注意：此方法返回的是内存中的数据，不会触发文件读取
  /// 如果需要从文件重新加载，请调用 load() 方法
  WindowSettingsData get data => _data;

  // ================= 快捷访问属性 =================

  // ================= 主窗口相关 =================

  /// 获取主窗口大小
  Size get mainWindowSize => _data.mainWindowSize;

  /// 获取主窗口位置
  Offset get mainWindowPosition => _data.mainWindowPosition;

  /// 获取主窗口是否最大化
  bool get mainWindowIsMaximized => _data.mainWindowIsMaximized;

  // ================= 工作台窗口相关 =================

  /// 获取工作台窗口大小
  Size get workspaceWindowSize => _data.workspaceWindowSize;

  /// 获取工作台窗口位置
  Offset get workspaceWindowPosition => _data.workspaceWindowPosition;

  /// 获取工作台窗口是否最大化
  bool get workspaceWindowIsMaximized => _data.workspaceWindowIsMaximized;

  // ================= 侧边栏相关 =================

  /// 获取主界面左侧栏是否展开
  bool get homeSidebarExpanded => _data.homeSidebarExpanded;

  /// 获取工作台左侧栏是否展开
  bool get workspaceLeftSidebarExpanded => _data.workspaceLeftSidebarExpanded;

  /// 获取工作台右侧边栏面板类型索引（-1 表示关闭，0+ 对应枚举索引）
  int get workspaceRightSidebarTypeIndex => _data.workspaceRightSidebarTypeIndex;

  /// 获取工作台左侧边栏宽度
  double get workspaceLeftSidebarWidth => _data.workspaceLeftSidebarWidth;

  /// 获取工作台右侧边栏宽度
  double get workspaceRightSidebarWidth => _data.workspaceRightSidebarWidth;

  // ================= 初始化方法 =================

  /// 初始化窗体缓存服务
  ///
  /// 该方法会：
  /// 1. 调用基类的 initialize() 创建缓存目录和文件路径
  /// 2. 尝试从 window.cache 文件加载已有的缓存数据
  /// 3. 如果文件不存在或读取失败，则使用默认值
  @override
  Future<void> initialize() async {
    try {
      // 先初始化基类（创建缓存目录等）
      await super.initialize();

      // 尝试从文件加载数据
      final loadedData = await load();

      if (loadedData != null) {
        _data = loadedData;
        debugPrint('WindowCacheService: 已从缓存文件加载数据');
      } else {
        debugPrint('WindowCacheService: 使用默认值（缓存文件不存在或为空）');
      }
    } catch (e, stackTrace) {
      debugPrint('WindowCacheService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      // 初始化失败时使用默认值，确保应用能正常运行
      _data = WindowSettingsData.defaults;
    }
  }

  // ================= 反序列化实现 =================

  @override
  WindowSettingsData fromJson(Map<String, dynamic> json) {
    return WindowSettingsData.fromJson(json);
  }

  // ================= 更新方法 =================

  /// 更新主窗口设置并保存到缓存文件
  ///
  /// [width] 窗口宽度（可选）
  /// [height] 窗口高度（可选）
  /// [x] 窗口 X 坐标（可选）
  /// [y] 窗口 Y 坐标（可选）
  /// [isMaximized] 是否最大化（可选）
  Future<bool> updateMainWindow({
    double? width,
    double? height,
    double? x,
    double? y,
    bool? isMaximized,
  }) async {
    _data = _data.copyWith(
      mainWindowWidth: width,
      mainWindowHeight: height,
      mainWindowX: x,
      mainWindowY: y,
      mainWindowIsMaximized: isMaximized,
    );

    return await save(_data);
  }

  /// 更新工作台窗口设置并保存到缓存文件
  ///
  /// [width] 窗口宽度（可选）
  /// [height] 窗口高度（可选）
  /// [x] 窗口 X 坐标（可选）
  /// [y] 窗口 Y 坐标（可选）
  /// [isMaximized] 是否最大化（可选）
  Future<bool> updateWorkspaceWindow({
    double? width,
    double? height,
    double? x,
    double? y,
    bool? isMaximized,
  }) async {
    _data = _data.copyWith(
      workspaceWindowWidth: width,
      workspaceWindowHeight: height,
      workspaceWindowX: x,
      workspaceWindowY: y,
      workspaceWindowIsMaximized: isMaximized,
    );

    return await save(_data);
  }

  /// 更新侧边栏状态并保存到缓存文件
  ///
  /// [homeExpanded] 主界面侧边栏是否展开（可选）
  /// [workspaceExpanded] 工作台左侧栏是否展开（可选）
  /// [workspaceRightSidebarTypeIndex] 工作台右侧边栏面板类型索引（-1 表示关闭，0+ 表示枚举索引，可选）
  Future<bool> updateSidebarState({
    bool? homeExpanded,
    bool? workspaceExpanded,
    int? workspaceRightSidebarTypeIndex,
  }) async {
    _data = _data.copyWith(
      homeSidebarExpanded: homeExpanded,
      workspaceLeftSidebarExpanded: workspaceExpanded,
      workspaceRightSidebarTypeIndex: workspaceRightSidebarTypeIndex,
    );

    return await save(_data);
  }

  /// 更新侧边栏宽度并保存到缓存文件
  ///
  /// [leftWidth] 工作台左侧边栏宽度（可选）
  /// [rightWidth] 工作台右侧边栏宽度（可选）
  Future<bool> updateSidebarWidth({
    double? leftWidth,
    double? rightWidth,
  }) async {
    _data = _data.copyWith(
      workspaceLeftSidebarWidth: leftWidth,
      workspaceRightSidebarWidth: rightWidth,
    );

    return await save(_data);
  }
}
