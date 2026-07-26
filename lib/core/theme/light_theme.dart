import 'package:flutter/material.dart';

/// 亮色主题
///
/// 定义了应用的亮色主题，包括颜色方案、字体选择、边框样式等
class LightTheme {
  // 定义一个全局的中文字体回退链
  static const List<String> fontFallback = [
    '微软雅黑',
    'Microsoft YaHei', // Windows 微软雅黑
    'DengXian',        // Windows 等线
    'PingFang SC',     // macOS 苹方
    'Noto Sans CJK SC',// 思源黑体
  ];

  /// 获取亮色主题数据
  static ThemeData get theme {
    // 亮色主题核心颜色定义
    const Color lightBackground = Color(0xFFF7F7F7); // 主背景色
    const Color lightSidebar = Color(0xFFF7F7F7); // 侧边栏
    const Color lightPrimary = Color(0xFF1F69E0); // 主色调（蓝）
    const Color lightText = Color(0xFF333333); // 主要文字颜色
    const Color lightTextSecondary = Color(0xFF0451A5); // 次要文字颜色（链接色）
    const Color lightBorder = Color(0xFFC3C7CF); // 边框/分隔线
    const Color lightHover = Color(0xFFE8E8E8); // 悬停背景色
    const Color lightSelection = Color(0xFFADD6FF); // 选中背景色
    const Color lightAccent = Color(0xFF0066B8); // 强调色

    return ThemeData(
      useMaterial3: true,
      fontFamilyFallback: fontFallback,

      // ================= 核心颜色方案 =================
      // 参考 Material Design 3 颜色系统：https://m3.material.io/styles/color/system/overview
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue, // 种子色，用于生成完整的调色板
        brightness: Brightness.light,

        // ===== 主要颜色组 =====
        // 用于最重要的组件：主要按钮、FAB、选中状态、顶部应用栏等
        primary: lightPrimary,  
        onPrimary: Colors.white, // primary 背景上的内容（文字/图标）
        primaryContainer: Colors.white70, // 较低强调的容器背景（如填充按钮的容器）
        onPrimaryContainer: lightText, // primaryContainer 背景上的内容

        // ===== 次要颜色组 =====
        // 用于较少强调的组件：筛选芯片、辅助按钮等
        secondary: lightAccent,
        onSecondary: Colors.white, // secondary 背景上的内容
        secondaryContainer: const Color(0xFFEBEBEB), // 次要容器背景
        onSecondaryContainer: lightTextSecondary, // secondaryContainer 背景上的内容

        // ===== 第三颜色组 =====
        // 用于对比强调点：输入框光标、特殊标记、进度条等
        tertiary: const Color(0xFFF05B13),
        onTertiary: Colors.white, // tertiary 背景上的内容
        tertiaryContainer: const Color(0xFFF0E4D4), // 第三容器背景

        // ===== 错误颜色组 =====
        // 用于错误状态：错误提示文本、删除按钮、表单验证错误等
        error: const Color(0xFFE51400),
        onError: Colors.white, // error 背景上的内容
        errorContainer: const Color(0xFFFFD4D4), // 错误容器背景（如错误提示卡片）
        onErrorContainer: const Color(0xFFA31515), // errorContainer 背景上的内容
        // ===== 表面颜色组 =====
        // 用于组件背景：卡片、对话框、菜单、侧边栏等
        surface: lightSidebar,
        onSurface: lightText, // surface 背景上的主要内容
        surfaceDim: const Color(0xFFF3F3F3), // 变暗的表面色（如禁用状态背景）
        surfaceBright: Colors.white, // 变亮的表面色（如高亮卡片）
        surfaceContainerLowest: Colors.white, // 最低对比度容器背景
        surfaceContainerLow: const Color(0xFFF0F0F2), // 低对比度容器背景（如侧边栏）
        surfaceContainer: const Color(0xFFF0F0F0), // 标准容器背景（如卡片）
        surfaceContainerHigh: const Color(0xFFF7F7F7), // 高对比度容器背景（如弹出菜单）
        surfaceContainerHighest: const Color(0xFFE1E2E8), // 最高对比度容器背景（如分隔区域）
        onSurfaceVariant: const Color(0xFF43474E), // surface 变体背景上的内容（次要文字、图标）
        // ===== 轮廓颜色 =====
        outline: lightBorder, // 用于边框、分隔线等可见轮廓
        outlineVariant: lightBorder, // 用于更弱的分隔（如列表分隔线）
        // ===== 功能颜色 =====
        shadow: const Color(0xFF000000), // 阴影颜色
        scrim: const Color(0xFF000000), // 遮罩颜色（如模态对话框背景遮罩）
        // ===== 反转颜色 =====
        // 用于需要与普通表面形成强烈对比的区域（如 SnackBar）
        inverseSurface: const Color(0xFF1E1E1E),
        onInverseSurface: const Color(0xFFE7E7E7), // inverseSurface 背景上的内容
        inversePrimary: lightPrimary, // 在深色背景上使用的主色强调
      ),

      // ================= 页面背景色 =================
      scaffoldBackgroundColor: lightBackground,

      // ================= 悬停效果 =================
      hoverColor: lightHover,
      focusColor: lightSelection,
      highlightColor: lightSelection.withAlpha(100),
      splashColor: lightSelection.withAlpha(50),

      // ================= AppBar（顶部栏）=================
      appBarTheme: const AppBarTheme(
        backgroundColor: lightSidebar,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false, // 标题左对齐
        iconTheme: IconThemeData(color: lightText),
        titleTextStyle: TextStyle(
          color: lightText,
          fontSize: 13, // 标题字号
          fontWeight: FontWeight.normal,
        ),
      ),

      // ================= 卡片相关 =================
      cardColor: lightSidebar,
      cardTheme: const CardThemeData(
        color: Color.fromARGB(255, 255, 255, 255),
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          // side: BorderSide(color: lightBorder, width: 1),
        ),
      ),

      // ================= 分隔线 =================
      dividerColor: lightBorder,
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
        space: 1,
      ),

      // ================= 图标主题 =================
      iconTheme: const IconThemeData(
        color: lightText,
        size: 16, // 图标大小
      ),

      // ================= 输入框主题 =================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white, // 输入框背景
        hoverColor: Colors.transparent, // 关闭悬停色
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightPrimary, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE51400), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE51400), width: 1),
        ),
        hintStyle: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 13),
        labelStyle: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 13),
        floatingLabelStyle: const TextStyle(color: lightPrimary, fontSize: 13),
      ),

      // ================= 文本选择主题 =================
      // 用于设置TextField等文本输入控件的选区颜色
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: lightSelection, // 选区背景色
        selectionHandleColor: lightPrimary, // 选区内控点颜色
      ),

      // ================= 按钮主题 =================
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightPrimary,
          disabledForegroundColor: const Color(0xFFA0A0A0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lightPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE8E8E8),
          disabledForegroundColor: const Color(0xFFA0A0A0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE8E8E8),
          disabledForegroundColor: const Color(0xFFA0A0A0),
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
          foregroundColor: lightPrimary,
          disabledForegroundColor: const Color(0xFFA0A0A0),
          side: const BorderSide(color: lightBorder, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      // ================= 图标按钮 =================
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: lightText,
          disabledForegroundColor: const Color(0xFFA0A0A0),
          hoverColor: lightHover,
          highlightColor: lightSelection,
        ),
      ),

      // ================= 开关 =================
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightPrimary;
          return const Color(0xFF6E6E6E);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return lightPrimary.withAlpha(100);
          }
          return const Color(0xFFE8E8E8);
        }),
      ),

      // ================= 复选框 =================
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightPrimary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: lightBorder, width: 1),
      ),

      // ================= 单选按钮 =================
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightPrimary;
          return const Color(0xFF6E6E6E);
        }),
      ),

      // ================= 滑块 =================
      sliderTheme: SliderThemeData(
        activeTrackColor: lightPrimary,
        inactiveTrackColor: const Color(0xFFE8E8E8),
        thumbColor: lightPrimary,
        overlayColor: lightPrimary.withAlpha(40),
        trackHeight: 4,
      ),

      // ================= 进度指示器 =================
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: lightPrimary,
        circularTrackColor: Color(0xFFE8E8E8),
        linearTrackColor: Color(0xFFE8E8E8),
      ),

      // === Tab 标签页 ===
      tabBarTheme: const TabBarThemeData(
        labelColor: lightText,
        unselectedLabelColor: Color(0xFF6E6E6E),
        indicatorColor: lightPrimary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: lightBorder,
      ),

      // === 底部导航栏 ===
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightSidebar,
        selectedItemColor: lightPrimary,
        unselectedItemColor: Color(0xFF6E6E6E),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // === 导航栏 ===
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSidebar,
        indicatorColor: lightSelection,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: lightPrimary);
          }
          return const IconThemeData(color: Color(0xFF6E6E6E));
        }),
      ),

      // === 导航抽屉 ===
      drawerTheme: DrawerThemeData(
        backgroundColor: lightSidebar,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      // === 对话框 ===
      dialogTheme: const DialogThemeData(
        backgroundColor: lightBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: lightBorder, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: lightText,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        contentTextStyle: TextStyle(color: lightText, fontSize: 13),
      ),

      // === 底部弹窗 ===
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),

      // === SnackBar 提示 ===
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFFF9F9F9),
        contentTextStyle: const TextStyle(
          color: Color(0xFFD4D4D4),
          fontSize: 13,
        ),
        actionTextColor: lightPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        behavior: SnackBarBehavior.floating,
      ),

      // === Tooltip 提示 ===
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(4),
          // border: Border.all(color: const Color(0xFF3C3C3C), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3C3C3C).withValues(alpha: 0.2),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
        ),
        textStyle: const TextStyle(color: lightText, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // === 弹出菜单 ===
      popupMenuTheme: PopupMenuThemeData(
        color: lightBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
        textStyle: const TextStyle(color: lightText, fontSize: 13),
      ),

      // === 下拉菜单 ===
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(lightBackground),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: lightBorder, width: 1),
            ),
          ),
        ),
      ),

      // === Chip 标签 ===
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE8E8E8),
        selectedColor: lightSelection,
        disabledColor: const Color(0xFFF3F3F3),
        labelStyle: const TextStyle(color: lightText, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF6E6E6E)),
        side: const BorderSide(color: lightBorder, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ================= 文字主题 =================
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w300,
          color: lightText,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: lightText,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w300,
          color: lightText,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: lightText,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: lightText,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: lightText,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: lightText,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: lightText,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: lightText,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: lightText,
          height: 1.8,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: lightText,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFF6E6E6E),
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: lightText,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: lightTextSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF6E6E6E),
        ),
      ),
    );
  }
}
