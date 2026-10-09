import 'package:flutter/material.dart';
import 'qw_theme_extension.dart';
import 'theme_palette.dart';

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
  /// 采用深色背景配合亮色文字，选中标签与编辑器书写区同色以保持视觉连贯
  static const TabColors dark = TabColors(
    // 选中状态颜色
    selectedBg: Color(0xFF242528), // 抬升表面色，与编辑器外框同色
    selectedFg: Color(0xFFE4E5E9), // 主要文字色，清晰可读
    selectedIndicator: Color(0xFF4C8DFF), // 主色调指示条
    selectedBorder: Color(0xFF2E2F34), // 弱边框色
    // 未选中状态颜色
    unselectedBg: Color(0xFF1A1B1D), // 比标签栏更深的凹陷底色
    unselectedFg: Color(0xFFA0A2AB), // 次要文字色，不抢眼
    unselectedBorder: Color(0xFF2E2F34), // 弱边框色
    // 悬停状态颜色
    hoverBg: Color(0xFF212226), // 悬停背景
    hoverFg: Color(0xFFE4E5E9), // 悬停文字
    // 修改标记颜色
    modifiedMark: Color(0xFF8A8C95), // 灰色修改标记圆点
    // 关闭按钮悬停背景
    closeHoverBg: Color(0xFF4A4C54),
  );

  /// 根据主题亮度获取对应的配色方案
  /// 
  /// [brightness] 主题亮度（亮色/暗色）
  /// 返回对应的标签页配色方案
  static TabColors fromBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  /// 根据调色板派生标签页配色
  ///
  /// 供自定义主题使用，保证标签页配色与自定义配色整体协调
  static TabColors fromPalette(ThemePalette palette) {
    return TabColors(
      selectedBg: palette.surfaceContainer,
      selectedFg: palette.primary,
      selectedIndicator: palette.primary,
      selectedBorder: palette.outlineVariant,
      unselectedBg: palette.surfaceContainerLowest,
      unselectedFg: palette.textVariant,
      unselectedBorder: palette.outlineVariant,
      hoverBg: palette.hover,
      hoverFg: palette.text,
      modifiedMark: palette.textVariant,
      closeHoverBg: palette.textMuted,
    );
  }

  /// 从 BuildContext 获取配色方案
  ///
  /// 优先使用自定义主题注入的配色；内置主题未注入该覆盖时，
  /// 按当前主题亮度回落到原有配色，行为保持不变
  static TabColors of(BuildContext context) {
    final theme = Theme.of(context);
    final override = theme.extension<QwThemeExtension>()?.tabColors;
    if (override != null) return override;
    return fromBrightness(theme.brightness);
  }
}
