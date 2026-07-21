import 'package:flutter/material.dart';

/// 标签页配色方案
/// 
/// 封装了标签页在不同状态下的所有颜色配置
/// 包括选中、未选中、悬停等状态的背景色、前景色、边框色等
class TabColors {
  /// 选中状态背景色
  final Color selectedBg;

  /// 选中状态前景色（文字、图标）
  final Color selectedFg;

  /// 选中状态顶部指示条颜色
  final Color selectedIndicator;

  /// 选中状态边框颜色
  final Color selectedBorder;

  /// 未选中状态背景色
  final Color unselectedBg;

  /// 未选中状态前景色
  final Color unselectedFg;

  /// 未选中状态边框颜色
  final Color unselectedBorder;

  /// 悬停状态背景色
  final Color hoverBg;

  /// 悬停状态前景色
  final Color hoverFg;

  /// 修改标记颜色（圆点）
  final Color modifiedMark;

  /// 关闭按钮悬停背景色
  final Color closeHoverBg;

  const TabColors({
    required this.selectedBg,
    required this.selectedFg,
    required this.selectedIndicator,
    required this.selectedBorder,
    required this.unselectedBg,
    required this.unselectedFg,
    required this.unselectedBorder,
    required this.hoverBg,
    required this.hoverFg,
    required this.modifiedMark,
    required this.closeHoverBg,
  });

  /// 亮色主题配色
  /// 
  /// 采用清爽的白色背景配合主色调蓝色
  /// 选中标签突出显示，未选中标签保持低调
  static const TabColors light = TabColors(
    // 选中状态颜色
    selectedBg: Color(0xFFFFFFFF), // 纯白背景
    selectedFg: Color(0xFF1F69E0), // 主色调文字
    selectedIndicator: Color(0xFF1F69E0), // 主色调指示条
    selectedBorder: Color(0xFFE0E0E0), // 浅灰边框
    // 未选中状态颜色
    unselectedBg: Color(0xFFF3F3F3), // 浅灰背景
    unselectedFg: Color(0xFF6E6E6E), // 灰色文字
    unselectedBorder: Color(0xFFE0E0E0), // 边框色
    // 悬停状态颜色
    hoverBg: Color(0xFFE8E8E8), // 悬停背景
    hoverFg: Color(0xFF4A4A4A), // 悬停文字
    // 修改标记颜色
    modifiedMark: Color(0xFF9E9E9E), // 灰色修改标记圆点
    // 关闭按钮悬停背景
    closeHoverBg: Color(0xFF666666),
  );

  /// 暗色主题配色
  /// 
  /// 采用深色背景配合亮色文字
  static const TabColors dark = TabColors(
    // 选中状态颜色
    selectedBg: Color(0xFF2D2D2D), // 深灰背景，与编辑器区分
    selectedFg: Color(0xFFE8E8E8), // 亮白文字，清晰可读
    selectedIndicator: Color(0xFF007ACC), // 蓝色指示条
    selectedBorder: Color(0xFF3A3A3A), // 边框色
    // 未选中状态颜色
    unselectedBg: Color(0xFF1E1E1E), // 与侧边栏同色
    unselectedFg: Color(0xFF858585), // 中灰文字，不抢眼
    unselectedBorder: Color(0xFF2D2D2D), // 较暗边框
    // 悬停状态颜色
    hoverBg: Color(0xFF2A2D2E), // 悬停背景
    hoverFg: Color(0xFFCCCCCC), // 悬停文字
    // 修改标记颜色
    modifiedMark: Color(0xFF787878), // 灰色修改标记圆点
    // 关闭按钮悬停背景
    closeHoverBg: Color(0xFFAAAAAA),
  );

  /// 根据主题亮度获取对应的配色方案
  /// 
  /// [brightness] 主题亮度（亮色/暗色）
  /// 返回对应的标签页配色方案
  static TabColors fromBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  /// 从 BuildContext 获取配色方案
  /// 
  /// 自动根据当前主题选择合适的配色
  static TabColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return fromBrightness(brightness);
  }
}
