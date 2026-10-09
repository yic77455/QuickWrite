import 'package:flutter/material.dart';
import 'theme_palette.dart';

/// 主题构建器
///
/// 根据 [ThemePalette] 生成完整的 [ThemeData]，是亮色、暗色与自定义主题
/// 共用的唯一构建入口。palette 作为唯一颜色来源，使自定义主题只需替换调色板
/// 即可获得协调一致的整套主题，避免在多处重复书写配色逻辑。
class ThemeBuilder {
  // 全局的中文字体回退链
  static const List<String> fontFallback = [
    '微软雅黑',
    'Microsoft YaHei', // Windows 微软雅黑
    'DengXian',        // Windows 等线
    'PingFang SC',     // macOS 苹方
    'Noto Sans CJK SC',// 思源黑体
  ];

  /// 根据调色板构建主题数据
  static ThemeData build(ThemePalette p) {
    return ThemeData(
      useMaterial3: true,
      fontFamilyFallback: fontFallback,

      // ================= 核心颜色方案 =================
      // 参考 Material Design 3 颜色系统：https://m3.material.io/styles/color/system/overview
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.seedColor, // 种子色，用于生成未显式覆盖的调色板槽位
        brightness: p.brightness,

        // ===== 主要颜色组 =====
        primary: p.primary,
        onPrimary: p.onPrimary,
        primaryContainer: p.primaryContainer,
        onPrimaryContainer: p.onPrimaryContainer,

        // ===== 次要颜色组 =====
        secondary: p.secondary,
        onSecondary: p.onSecondary,
        secondaryContainer: p.secondaryContainer,
        onSecondaryContainer: p.onSecondaryContainer,

        // ===== 第三颜色组 =====
        tertiary: p.tertiary,
        onTertiary: p.onTertiary,
        tertiaryContainer: p.tertiaryContainer,

        // ===== 错误颜色组 =====
        error: p.error,
        onError: p.onError,
        errorContainer: p.errorContainer,
        onErrorContainer: p.onErrorContainer,

        // ===== 表面颜色组 =====
        surface: p.surface,
        onSurface: p.onSurface,
        surfaceDim: p.surfaceDim,
        surfaceBright: p.surfaceBright,
        surfaceContainerLowest: p.surfaceContainerLowest,
        surfaceContainerLow: p.surfaceContainerLow,
        surfaceContainer: p.surfaceContainer,
        surfaceContainerHigh: p.surfaceContainerHigh,
        surfaceContainerHighest: p.surfaceContainerHighest,
        onSurfaceVariant: p.onSurfaceVariant,

        // ===== 轮廓颜色 =====
        outline: p.outline,
        outlineVariant: p.outlineVariant,

        // ===== 功能颜色 =====
        shadow: p.shadow,
        scrim: p.scrim,

        // ===== 反转颜色 =====
        inverseSurface: p.inverseSurface,
        onInverseSurface: p.onInverseSurface,
        inversePrimary: p.inversePrimary,
      ),

      // ================= 页面背景色 =================
      scaffoldBackgroundColor: p.scaffoldBackground,

      // ================= 悬停效果 =================
      hoverColor: p.hover,
      focusColor: p.selection,
      highlightColor: p.selection.withAlpha(100),
      splashColor: p.selection.withAlpha(50),

      // ================= AppBar（顶部栏）=================
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false, // 标题左对齐
        iconTheme: IconThemeData(color: p.text),
        titleTextStyle: TextStyle(
          color: p.text,
          fontSize: 13, // 标题字号
          fontWeight: FontWeight.normal,
        ),
      ),

      // ================= 卡片相关 =================
      cardColor: p.cardColor,
      cardTheme: CardThemeData(
        color: p.cardThemeSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // ================= 分隔线 =================
      dividerColor: p.outlineVariant,
      dividerTheme: DividerThemeData(
        color: p.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // ================= 图标主题 =================
      iconTheme: IconThemeData(
        color: p.text,
        size: 16, // 图标大小
      ),

      // ================= 输入框主题 =================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.inputFill, // 输入框背景
        hoverColor: Colors.transparent, // 关闭悬停色
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.primary, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.error, width: 1),
        ),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: p.textVariant, fontSize: 13),
        floatingLabelStyle: TextStyle(color: p.primary, fontSize: 13),
      ),

      // ================= 文本选择主题 =================
      // 用于设置TextField等文本输入控件的选区颜色
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: p.selection, // 选区背景色
        selectionHandleColor: p.primary, // 选区内控点颜色
      ),

      // ================= 按钮主题 =================
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          disabledForegroundColor: p.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.disabledBackground,
          disabledForegroundColor: p.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.disabledBackground,
          disabledForegroundColor: p.textMuted,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          disabledForegroundColor: p.textMuted,
          side: BorderSide(color: p.outline, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      // ================= 图标按钮 =================
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.text,
          disabledForegroundColor: p.textMuted,
          hoverColor: p.hover,
          highlightColor: p.selection,
        ),
      ),

      // ================= 开关 =================
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return p.textVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return p.primary.withAlpha(100);
          }
          return p.trackColor;
        }),
      ),

      // ================= 复选框 =================
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(p.onPrimary),
        side: BorderSide(color: p.checkboxBorder, width: 1),
      ),

      // ================= 单选按钮 =================
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return p.radioUnselected;
        }),
      ),

      // ================= 滑块 =================
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.trackColor,
        thumbColor: p.primary,
        overlayColor: p.primary.withAlpha(40),
        trackHeight: 4,
      ),

      // ================= 进度指示器 =================
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        circularTrackColor: p.trackColor,
        linearTrackColor: p.trackColor,
      ),

      // === Tab 标签页 ===
      tabBarTheme: TabBarThemeData(
        labelColor: p.text,
        unselectedLabelColor: p.textVariant,
        indicatorColor: p.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: p.outlineVariant,
      ),

      // === 底部导航栏 ===
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // === 导航栏 ===
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.selection,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: p.primary);
          }
          return IconThemeData(color: p.textVariant);
        }),
      ),

      // === 导航抽屉 ===
      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      // === 对话框 ===
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceMenu,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: p.outline, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: p.text,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        contentTextStyle: TextStyle(color: p.text, fontSize: 13),
      ),

      // === 底部弹窗 ===
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),

      // === SnackBar 提示 ===
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.snackBarBackground,
        contentTextStyle: TextStyle(
          color: p.snackBarText,
          fontSize: 13,
        ),
        actionTextColor: p.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        behavior: SnackBarBehavior.floating,
      ),

      // === Tooltip 提示 ===
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.tooltipBackground,
          borderRadius: BorderRadius.circular(4),
          border: p.hasTooltipBorder
              ? Border.all(color: p.tooltipBorder, width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: p.tooltipShadowColor.withValues(alpha: p.tooltipShadowAlpha),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
        ),
        textStyle: TextStyle(color: p.text, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // === 弹出菜单 ===
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceMenu,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: p.outline, width: 1),
        ),
        textStyle: TextStyle(color: p.text, fontSize: 13),
      ),

      // === 下拉菜单 ===
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(p.surfaceMenu),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: p.outline, width: 1),
            ),
          ),
        ),
      ),

      // === Chip 标签 ===
      chipTheme: ChipThemeData(
        backgroundColor: p.chipBackground,
        selectedColor: p.selection,
        disabledColor: p.chipDisabled,
        labelStyle: TextStyle(color: p.text, fontSize: 12),
        secondaryLabelStyle: TextStyle(color: p.textVariant),
        side: BorderSide(color: p.outline, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ================= 文字主题 =================
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w300,
          color: p.text,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: p.text,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w300,
          color: p.text,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: p.text,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: p.text,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: p.text,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: p.text,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: p.text,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: p.text,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: p.text,
          height: 1.8,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: p.text,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: p.textVariant,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: p.text,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: p.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: p.textVariant,
        ),
      ),
    );
  }

  /// 私有构造函数，防止实例化
  ThemeBuilder._();
}