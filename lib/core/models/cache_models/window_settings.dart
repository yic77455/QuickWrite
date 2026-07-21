import 'package:flutter/material.dart';

/// 窗体设置数据模型
///
/// 纯数据类，用于存储窗体相关的临时性数据
/// 包括：窗口大小、位置、最大化状态、侧边栏状态等
/// 
/// 该类与主配置文件（settings.json）完全分离，通过独立的缓存文件（window.cache）持久化
class WindowSettingsData {
  // ================= 主窗口设置 =================

  /// 主窗口宽度（单位：像素）
  final double mainWindowWidth;

  /// 主窗口高度（单位：像素）
  final double mainWindowHeight;

  /// 主窗口左上角 X 坐标（单位：像素）
  final double mainWindowX;

  /// 主窗口左上角 Y 坐标（单位：像素）
  final double mainWindowY;

  /// 主窗口是否最大化
  final bool mainWindowIsMaximized;

  // ================= 工作台窗口设置 =================

  /// 工作台窗口宽度（单位：像素）
  final double workspaceWindowWidth;

  /// 工作台窗口高度（单位：像素）
  final double workspaceWindowHeight;

  /// 工作台窗口左上角 X 坐标（单位：像素）
  final double workspaceWindowX;

  /// 工作台窗口左上角 Y 坐标（单位：像素）
  final double workspaceWindowY;

  /// 工作台窗口是否最大化
  final bool workspaceWindowIsMaximized;

  // ================= 侧边栏状态 =================

  /// 主界面左侧栏是否展开
  final bool homeSidebarExpanded;

  /// 工作台左侧栏是否展开
  final bool workspaceLeftSidebarExpanded;

  /// 工作台左侧边栏宽度（单位：像素）
  final double workspaceLeftSidebarWidth;

  /// 工作台右侧边栏面板类型索引（-1 表示关闭，0+ 对应 RightSidebarType 枚举索引）
  final int workspaceRightSidebarTypeIndex;

  /// 工作台右侧边栏宽度（单位：像素）
  final double workspaceRightSidebarWidth;

  // ================= 默认值常量 =================

  /// 默认窗体设置（首次启动时使用）
  static const WindowSettingsData defaults = WindowSettingsData();

  // ================= 构造函数 =================

  const WindowSettingsData({
    this.mainWindowWidth = 1200.0,
    this.mainWindowHeight = 900.0,
    this.mainWindowX = 100.0,
    this.mainWindowY = 100.0,
    this.mainWindowIsMaximized = false,
    this.workspaceWindowWidth = 1200.0,
    this.workspaceWindowHeight = 900.0,
    this.workspaceWindowX = 100.0,
    this.workspaceWindowY = 100.0,
    this.workspaceWindowIsMaximized = false,
    this.homeSidebarExpanded = false,
    this.workspaceLeftSidebarExpanded = true,
    this.workspaceLeftSidebarWidth = 250.0,
    this.workspaceRightSidebarTypeIndex = -1,
    this.workspaceRightSidebarWidth = 280.0,
  });

  // ================= JSON 序列化 =================

  /// 从 JSON Map 创建实例
  factory WindowSettingsData.fromJson(Map<String, dynamic> json) {
    return WindowSettingsData(
      mainWindowWidth: (json['mainWindowWidth'] as num?)?.toDouble() ?? defaults.mainWindowWidth,
      mainWindowHeight: (json['mainWindowHeight'] as num?)?.toDouble() ?? defaults.mainWindowHeight,
      mainWindowX: (json['mainWindowX'] as num?)?.toDouble() ?? defaults.mainWindowX,
      mainWindowY: (json['mainWindowY'] as num?)?.toDouble() ?? defaults.mainWindowY,
      mainWindowIsMaximized: json['mainWindowIsMaximized'] as bool? ?? defaults.mainWindowIsMaximized,
      workspaceWindowWidth: (json['workspaceWindowWidth'] as num?)?.toDouble() ?? defaults.workspaceWindowWidth,
      workspaceWindowHeight: (json['workspaceWindowHeight'] as num?)?.toDouble() ?? defaults.workspaceWindowHeight,
      workspaceWindowX: (json['workspaceWindowX'] as num?)?.toDouble() ?? defaults.workspaceWindowX,
      workspaceWindowY: (json['workspaceWindowY'] as num?)?.toDouble() ?? defaults.workspaceWindowY,
      workspaceWindowIsMaximized: json['workspaceWindowIsMaximized'] as bool? ?? defaults.workspaceWindowIsMaximized,
      homeSidebarExpanded: json['homeSidebarExpanded'] as bool? ?? defaults.homeSidebarExpanded,
      workspaceLeftSidebarExpanded: json['workspaceLeftSidebarExpanded'] as bool? ?? defaults.workspaceLeftSidebarExpanded,
      workspaceLeftSidebarWidth: (json['workspaceLeftSidebarWidth'] as num?)?.toDouble() ?? defaults.workspaceLeftSidebarWidth,
      workspaceRightSidebarTypeIndex: (json['workspaceRightSidebarTypeIndex'] as num?)?.toInt() ?? defaults.workspaceRightSidebarTypeIndex,
      workspaceRightSidebarWidth: (json['workspaceRightSidebarWidth'] as num?)?.toDouble() ?? defaults.workspaceRightSidebarWidth,
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'mainWindowWidth': mainWindowWidth,
      'mainWindowHeight': mainWindowHeight,
      'mainWindowX': mainWindowX,
      'mainWindowY': mainWindowY,
      'mainWindowIsMaximized': mainWindowIsMaximized,
      'workspaceWindowWidth': workspaceWindowWidth,
      'workspaceWindowHeight': workspaceWindowHeight,
      'workspaceWindowX': workspaceWindowX,
      'workspaceWindowY': workspaceWindowY,
      'workspaceWindowIsMaximized': workspaceWindowIsMaximized,
      'homeSidebarExpanded': homeSidebarExpanded,
      'workspaceLeftSidebarExpanded': workspaceLeftSidebarExpanded,
      'workspaceLeftSidebarWidth': workspaceLeftSidebarWidth,
      'workspaceRightSidebarTypeIndex': workspaceRightSidebarTypeIndex,
      'workspaceRightSidebarWidth': workspaceRightSidebarWidth,
    };
  }

  // ================= 辅助方法 =================

  /// 创建副本，用于更新部分字段
  WindowSettingsData copyWith({
    double? mainWindowWidth,
    double? mainWindowHeight,
    double? mainWindowX,
    double? mainWindowY,
    bool? mainWindowIsMaximized,
    double? workspaceWindowWidth,
    double? workspaceWindowHeight,
    double? workspaceWindowX,
    double? workspaceWindowY,
    bool? workspaceWindowIsMaximized,
    bool? homeSidebarExpanded,
    bool? workspaceLeftSidebarExpanded,
    double? workspaceLeftSidebarWidth,
    int? workspaceRightSidebarTypeIndex,
    double? workspaceRightSidebarWidth,
  }) {
    return WindowSettingsData(
      mainWindowWidth: mainWindowWidth ?? this.mainWindowWidth,
      mainWindowHeight: mainWindowHeight ?? this.mainWindowHeight,
      mainWindowX: mainWindowX ?? this.mainWindowX,
      mainWindowY: mainWindowY ?? this.mainWindowY,
      mainWindowIsMaximized: mainWindowIsMaximized ?? this.mainWindowIsMaximized,
      workspaceWindowWidth: workspaceWindowWidth ?? this.workspaceWindowWidth,
      workspaceWindowHeight: workspaceWindowHeight ?? this.workspaceWindowHeight,
      workspaceWindowX: workspaceWindowX ?? this.workspaceWindowX,
      workspaceWindowY: workspaceWindowY ?? this.workspaceWindowY,
      workspaceWindowIsMaximized: workspaceWindowIsMaximized ?? this.workspaceWindowIsMaximized,
      homeSidebarExpanded: homeSidebarExpanded ?? this.homeSidebarExpanded,
      workspaceLeftSidebarExpanded: workspaceLeftSidebarExpanded ?? this.workspaceLeftSidebarExpanded,
      workspaceLeftSidebarWidth: workspaceLeftSidebarWidth ?? this.workspaceLeftSidebarWidth,
      workspaceRightSidebarTypeIndex: workspaceRightSidebarTypeIndex ?? this.workspaceRightSidebarTypeIndex,
      workspaceRightSidebarWidth: workspaceRightSidebarWidth ?? this.workspaceRightSidebarWidth,
    );
  }

  // ================= 快捷访问属性 =================

  /// 获取主窗口大小
  Size get mainWindowSize => Size(mainWindowWidth, mainWindowHeight);

  /// 获取主窗口位置
  Offset get mainWindowPosition => Offset(mainWindowX, mainWindowY);

  /// 获取工作台窗口大小
  Size get workspaceWindowSize => Size(workspaceWindowWidth, workspaceWindowHeight);

  /// 获取工作台窗口位置
  Offset get workspaceWindowPosition => Offset(workspaceWindowX, workspaceWindowY);

  @override
  String toString() {
    return 'WindowSettingsData('
        'mainWindow: ${mainWindowWidth}x$mainWindowHeight at ($mainWindowX, $mainWindowY), '
        'maximized: $mainWindowIsMaximized, '
        'workspaceWindow: ${workspaceWindowWidth}x$workspaceWindowHeight at ($workspaceWindowX, $workspaceWindowY), '
        'maximized: $workspaceWindowIsMaximized, '
        'homeSidebar: $homeSidebarExpanded, '
        'workspaceSidebar: $workspaceLeftSidebarExpanded, '
        'workspaceLeftSidebarWidth: $workspaceLeftSidebarWidth, '
        'workspaceRightSidebarTypeIndex: $workspaceRightSidebarTypeIndex, '
        'workspaceRightSidebarWidth: $workspaceRightSidebarWidth'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WindowSettingsData &&
           other.mainWindowWidth == mainWindowWidth &&
           other.mainWindowHeight == mainWindowHeight &&
           other.mainWindowX == mainWindowX &&
           other.mainWindowY == mainWindowY &&
           other.mainWindowIsMaximized == mainWindowIsMaximized &&
           other.workspaceWindowWidth == workspaceWindowWidth &&
           other.workspaceWindowHeight == workspaceWindowHeight &&
           other.workspaceWindowX == workspaceWindowX &&
           other.workspaceWindowY == workspaceWindowY &&
           other.workspaceWindowIsMaximized == workspaceWindowIsMaximized &&
           other.homeSidebarExpanded == homeSidebarExpanded &&
           other.workspaceLeftSidebarExpanded == workspaceLeftSidebarExpanded &&
           other.workspaceLeftSidebarWidth == workspaceLeftSidebarWidth &&
           other.workspaceRightSidebarTypeIndex == workspaceRightSidebarTypeIndex &&
           other.workspaceRightSidebarWidth == workspaceRightSidebarWidth;
  }

  @override
  int get hashCode {
    return Object.hash(
      mainWindowWidth,
      mainWindowHeight,
      mainWindowX,
      mainWindowY,
      mainWindowIsMaximized,
      workspaceWindowWidth,
      workspaceWindowHeight,
      workspaceWindowX,
      workspaceWindowY,
      workspaceWindowIsMaximized,
      homeSidebarExpanded,
      workspaceLeftSidebarExpanded,
      workspaceLeftSidebarWidth,
      workspaceRightSidebarTypeIndex,
      workspaceRightSidebarWidth,
    );
  }
}
