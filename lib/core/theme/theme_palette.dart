import 'package:flutter/material.dart';

/// 主题调色板
///
/// 以语义化字段集中承载一套主题所需的全部颜色，是主题构建的唯一数据源。
/// 内置的 [light] / [dark] 两个预设的取值与应用原有硬编码常量完全一致，
/// 因此通过 [ThemeBuilder] 构建出的内置主题与改造前保持零差异。
///
/// 字段按 Material 3 的语义分组组织，其中 [primary]、[secondary]、
/// [scaffoldBackground]、[surface]、[text]、[outline] 等属于“关键色”，
/// 允许用户自定义覆盖；其余字段由关键色派生得到。
class ThemePalette {
  // ================= 基础属性 =================

  /// 主题亮度（亮色 / 暗色）
  final Brightness brightness;

  /// 颜色方案的种子色
  /// 用于 ColorScheme.fromSeed 生成未显式覆盖的调色板槽位
  final Color seedColor;

  // ================= 主要颜色组 =================
  /// 主色调，用于主要按钮、选中状态、顶部应用栏等
  final Color primary;
  /// primary 背景上的内容（文字/图标）
  final Color onPrimary;
  /// 较低强调的主色容器背景
  final Color primaryContainer;
  /// primaryContainer 背景上的内容
  final Color onPrimaryContainer;

  // ================= 次要颜色组 =================
  /// 次要强调色，用于筛选芯片、辅助按钮等
  final Color secondary;
  /// secondary 背景上的内容
  final Color onSecondary;
  /// 次要容器背景
  final Color secondaryContainer;
  /// secondaryContainer 背景上的内容
  final Color onSecondaryContainer;

  // ================= 第三颜色组 =================
  /// 对比强调色/警告色，用于输入框光标、特殊标记、风险提示等
  final Color tertiary;
  /// tertiary 背景上的内容
  final Color onTertiary;
  /// 第三容器背景
  final Color tertiaryContainer;

  // ================= 错误颜色组 =================
  /// 错误色，用于错误提示、删除按钮、表单校验错误等
  final Color error;
  /// error 背景上的内容
  final Color onError;
  /// 错误容器背景
  final Color errorContainer;
  /// errorContainer 背景上的内容
  final Color onErrorContainer;

  // ================= 表面颜色组 =================
  /// 常规表面色（面板、侧边栏、工具栏、标签栏）
  final Color surface;
  /// surface 背景上的主要内容
  final Color onSurface;
  /// 变暗的表面色（如禁用状态背景）
  final Color surfaceDim;
  /// 变亮的表面色（如高亮卡片）
  final Color surfaceBright;
  /// 最低层级容器背景（纸张/书写区）
  final Color surfaceContainerLowest;
  /// 低层级容器背景
  final Color surfaceContainerLow;
  /// 标准容器背景（卡片、编辑器外框）
  final Color surfaceContainer;
  /// 高层级容器背景（弹出菜单）
  final Color surfaceContainerHigh;
  /// 最高层级容器背景（分隔区域）
  final Color surfaceContainerHighest;
  /// surface 变体背景上的内容（次要文字、图标）
  final Color onSurfaceVariant;

  // ================= 轮廓颜色 =================
  /// 可见轮廓色，用于边框、分隔线
  final Color outline;
  /// 更弱的分隔轮廓色，用于列表分隔线
  final Color outlineVariant;

  // ================= 功能颜色 =================
  /// 阴影颜色
  final Color shadow;
  /// 遮罩颜色（模态对话框背景遮罩）
  final Color scrim;

  // ================= 反转颜色 =================
  /// 与普通表面形成强烈对比的区域背景（如 SnackBar）
  final Color inverseSurface;
  /// inverseSurface 背景上的内容
  final Color onInverseSurface;
  /// 在深色背景上使用的主色强调
  final Color inversePrimary;

  // ================= 文字层级 =================
  /// 主要文字颜色
  final Color text;
  /// 链接/次级强调文字
  final Color textSecondary;
  /// 次要文字/图标（明显弱于主要文字）
  final Color textVariant;
  /// 占位符/禁用文字
  final Color textMuted;

  // ================= 页面与交互 =================
  /// 页面主背景色
  final Color scaffoldBackground;
  /// 悬停背景色
  final Color hover;
  /// 选中背景色
  final Color selection;

  // ================= 组件专用色 =================
  /// 卡片底色（ThemeData.cardColor）
  final Color cardColor;
  /// 卡片主题底色（cardTheme.color）
  final Color cardThemeSurface;
  /// 输入框填充色（比所在表面更深，形成内嵌感）
  final Color inputFill;
  /// 按钮禁用背景色
  final Color disabledBackground;
  /// 开关/滑块/进度条的未激活轨道底色
  final Color trackColor;
  /// Chip 标签底色
  final Color chipBackground;
  /// Chip 标签禁用底色
  final Color chipDisabled;
  /// 浮层表面色（对话框、弹出菜单、下拉菜单）
  final Color surfaceMenu;
  /// SnackBar 背景色
  final Color snackBarBackground;
  /// SnackBar 文字色
  final Color snackBarText;
  /// Tooltip 背景色
  final Color tooltipBackground;
  /// Tooltip 边框色（透明表示不绘制边框）
  final Color tooltipBorder;
  /// Tooltip 阴影基础色
  final Color tooltipShadowColor;
  /// Tooltip 阴影不透明度
  final double tooltipShadowAlpha;
  /// 复选框未选中边框色
  final Color checkboxBorder;
  /// 单选按钮未选中颜色
  final Color radioUnselected;

  const ThemePalette({
    required this.brightness,
    required this.seedColor,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.text,
    required this.textSecondary,
    required this.textVariant,
    required this.textMuted,
    required this.scaffoldBackground,
    required this.hover,
    required this.selection,
    required this.cardColor,
    required this.cardThemeSurface,
    required this.inputFill,
    required this.disabledBackground,
    required this.trackColor,
    required this.chipBackground,
    required this.chipDisabled,
    required this.surfaceMenu,
    required this.snackBarBackground,
    required this.snackBarText,
    required this.tooltipBackground,
    required this.tooltipBorder,
    required this.tooltipShadowColor,
    required this.tooltipShadowAlpha,
    required this.checkboxBorder,
    required this.radioUnselected,
  });

  /// 是否支持 Tooltip 边框
  /// 边框色为完全透明时视为不绘制边框，避免引入多余的 1px 布局
  bool get hasTooltipBorder => tooltipBorder.a > 0;

  /// 亮色主题调色板
  ///
  /// 取值与应用原有亮色主题常量逐一对应，保证改造后外观不变
  static const ThemePalette light = ThemePalette(
    brightness: Brightness.light,
    seedColor: Colors.blue,
    // 主要颜色组
    primary: Color(0xFF1F69E0),
    onPrimary: Colors.white,
    primaryContainer: Colors.white70,
    onPrimaryContainer: Color(0xFF333333),
    // 次要颜色组
    secondary: Color(0xFF0066B8),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFEBEBEB),
    onSecondaryContainer: Color(0xFF0451A5),
    // 第三颜色组
    tertiary: Color(0xFFF05B13),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFF0E4D4),
    // 错误颜色组
    error: Color(0xFFE51400),
    onError: Colors.white,
    errorContainer: Color(0xFFFFD4D4),
    onErrorContainer: Color(0xFFA31515),
    // 表面颜色组
    surface: Color(0xFFF7F7F7),
    onSurface: Color(0xFF333333),
    surfaceDim: Color(0xFFF3F3F3),
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF0F0F2),
    surfaceContainer: Color(0xFFF0F0F0),
    surfaceContainerHigh: Color(0xFFF7F7F7),
    surfaceContainerHighest: Color(0xFFE1E2E8),
    onSurfaceVariant: Color(0xFF43474E),
    // 轮廓颜色
    outline: Color(0xFFC3C7CF),
    outlineVariant: Color(0xFFC3C7CF),
    // 功能颜色
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    // 反转颜色
    inverseSurface: Color(0xFF1E1E1E),
    onInverseSurface: Color(0xFFE7E7E7),
    inversePrimary: Color(0xFF1F69E0),
    // 文字层级
    text: Color(0xFF333333),
    textSecondary: Color(0xFF0451A5),
    textVariant: Color(0xFF6E6E6E),
    textMuted: Color(0xFFA0A0A0),
    // 页面与交互
    scaffoldBackground: Color(0xFFF7F7F7),
    hover: Color(0xFFE8E8E8),
    selection: Color(0xFFADD6FF),
    // 组件专用色
    cardColor: Color(0xFFF7F7F7),
    cardThemeSurface: Color.fromARGB(255, 255, 255, 255),
    inputFill: Colors.white,
    disabledBackground: Color(0xFFE8E8E8),
    trackColor: Color(0xFFE8E8E8),
    chipBackground: Color(0xFFE8E8E8),
    chipDisabled: Color(0xFFF3F3F3),
    surfaceMenu: Color(0xFFF7F7F7),
    snackBarBackground: Color(0xFFF9F9F9),
    snackBarText: Color(0xFFD4D4D4),
    tooltipBackground: Color(0xFFF9F9F9),
    tooltipBorder: Colors.transparent,
    tooltipShadowColor: Color(0xFF3C3C3C),
    tooltipShadowAlpha: 0.2,
    checkboxBorder: Color(0xFFC3C7CF),
    radioUnselected: Color(0xFF6E6E6E),
  );

  /// 暗色主题调色板
  ///
  /// 取值与应用原有暗色主题常量逐一对应，保证改造后外观不变
  static const ThemePalette dark = ThemePalette(
    brightness: Brightness.dark,
    seedColor: Color(0xFF4C8DFF),
    // 主要颜色组
    primary: Color(0xFF4C8DFF),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF1B3C6B),
    onPrimaryContainer: Color(0xFFCFE1FF),
    // 次要颜色组
    secondary: Color(0xFF9098AA),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF222427),
    onSecondaryContainer: Color(0xFF7EB8FF),
    // 第三颜色组
    tertiary: Color(0xFFE0A94A),
    onTertiary: Color(0xFF241A05),
    tertiaryContainer: Color(0xFF44330F),
    // 错误颜色组
    error: Color(0xFFF25C5C),
    onError: Colors.white,
    errorContainer: Color(0xFF4A2020),
    onErrorContainer: Color(0xFFFFB4AB),
    // 表面颜色组
    surface: Color(0xFF1E1F22),
    onSurface: Color(0xFFE4E5E9),
    surfaceDim: Color(0xFF222427),
    surfaceBright: Color(0xFF33343A),
    surfaceContainerLowest: Color(0xFF1A1B1D),
    surfaceContainerLow: Color(0xFF1E1F22),
    surfaceContainer: Color(0xFF242528),
    surfaceContainerHigh: Color(0xFF2B2C30),
    surfaceContainerHighest: Color(0xFF33343A),
    onSurfaceVariant: Color(0xFFA0A2AB),
    // 轮廓颜色
    outline: Color(0xFF3A3B41),
    outlineVariant: Color(0xFF2E2F34),
    // 功能颜色
    shadow: Colors.black,
    scrim: Colors.black,
    // 反转颜色
    inverseSurface: Color(0xFFE4E5E9),
    onInverseSurface: Color(0xFF1E1F22),
    inversePrimary: Color(0xFF1F69E0),
    // 文字层级
    text: Color(0xFFE4E5E9),
    textSecondary: Color(0xFF7EB8FF),
    textVariant: Color(0xFFA0A2AB),
    textMuted: Color(0xFF6B6D76),
    // 页面与交互
    scaffoldBackground: Color(0xFF18191B),
    hover: Color(0xFF26272B),
    selection: Color(0xFF2C4A73),
    // 组件专用色
    cardColor: Color(0xFF242528),
    cardThemeSurface: Color(0xFF242528),
    inputFill: Color(0xFF1A1B1D),
    disabledBackground: Color(0xFF242528),
    trackColor: Color(0xFF33343A),
    chipBackground: Color(0xFF242528),
    chipDisabled: Color(0xFF222427),
    surfaceMenu: Color(0xFF2B2C30),
    snackBarBackground: Color(0xF02B2C30),
    snackBarText: Color(0xFFE4E5E9),
    tooltipBackground: Color(0xFF33343A),
    tooltipBorder: Color(0xFF3A3B41),
    tooltipShadowColor: Color(0xFF000000),
    tooltipShadowAlpha: 0.35,
    checkboxBorder: Color(0xFF6B6D76),
    radioUnselected: Color(0xFF6B6D76),
  );

  /// 全部字段的取值集合
  ///
  /// 用于相等性判断与哈希计算，避免逐字段罗列造成遗漏
  List<Object?> get _values => [
        brightness,
        seedColor,
        primary,
        onPrimary,
        primaryContainer,
        onPrimaryContainer,
        secondary,
        onSecondary,
        secondaryContainer,
        onSecondaryContainer,
        tertiary,
        onTertiary,
        tertiaryContainer,
        error,
        onError,
        errorContainer,
        onErrorContainer,
        surface,
        onSurface,
        surfaceDim,
        surfaceBright,
        surfaceContainerLowest,
        surfaceContainerLow,
        surfaceContainer,
        surfaceContainerHigh,
        surfaceContainerHighest,
        onSurfaceVariant,
        outline,
        outlineVariant,
        shadow,
        scrim,
        inverseSurface,
        onInverseSurface,
        inversePrimary,
        text,
        textSecondary,
        textVariant,
        textMuted,
        scaffoldBackground,
        hover,
        selection,
        cardColor,
        cardThemeSurface,
        inputFill,
        disabledBackground,
        trackColor,
        chipBackground,
        chipDisabled,
        surfaceMenu,
        snackBarBackground,
        snackBarText,
        tooltipBackground,
        tooltipBorder,
        tooltipShadowColor,
        tooltipShadowAlpha,
        checkboxBorder,
        radioUnselected,
      ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ThemePalette) return false;
    final a = _values;
    final b = other._values;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_values);
}