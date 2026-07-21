import 'package:flutter/material.dart';

/// 暗色主题
/// 
/// 定义了应用的暗色主题，包括颜色方案、字体选择、边框样式等
class DarkTheme {
  // 定义一个全局的中文字体回退链
  static const List<String> fontFallback = [
    '微软雅黑',
    'Microsoft YaHei', // Windows 微软雅黑
    'DengXian',        // Windows 等线
    'PingFang SC',     // macOS 苹方
    'Noto Sans CJK SC',// 思源黑体
  ];

  /// 获取暗色主题数据
  static ThemeData get theme {
    // 暗色主题核心颜色定义
    const Color darkBackground = Color(0xFF222222); // 主背景色
    const Color darkSidebar = Color(0xFF222222); // 侧边栏/面板背景
    const Color darkPrimary = Color(0xFF007ACC); // 主色调
    const Color darkText = Color(0xFFD4D4D4); // 主要文字颜色
    const Color darkTextSecondary = Color(0xFF9CDCFE); // 次要文字颜色
    const Color darkBorder = Color(0xFF3A3A3A); // 边框/分隔线
    const Color darkHover = Color(0xFF2A2D2E); // 悬停背景色
    const Color darkSelection = Color(0xFF264F78); // 选中背景色
    const Color darkAccent = Color(0xFF808080); // 强调色

    return ThemeData(
      useMaterial3: true,
      fontFamilyFallback: fontFallback,

      // ================= 核心颜色方案 =================
      // 参考 Material Design 3 颜色系统：https://m3.material.io/styles/color/system/overview
      colorScheme: ColorScheme.fromSeed(
        seedColor: darkPrimary, // 种子色，用于生成完整的调色板
        brightness: Brightness.dark,

        // ===== 主要颜色组 =====
        // 用于最重要的组件：主要按钮、FAB、选中状态、顶部应用栏等
        primary: Colors.white,
        onPrimary: Colors.white, // primary 背景上的内容（文字/图标）
        primaryContainer: darkAccent, // 较低强调的容器背景（如填充按钮的容器）
        onPrimaryContainer: darkText, // primaryContainer 背景上的内容

        // ===== 次要颜色组 =====
        // 用于较少强调的组件：筛选芯片、辅助按钮等
        secondary: darkAccent,
        onSecondary: Colors.white, // secondary 背景上的内容
        secondaryContainer: const Color(0xFF2D2D2D), // 次要容器背景
        onSecondaryContainer: darkTextSecondary, // secondaryContainer 背景上的内容

        // ===== 第三颜色组 =====
        // 用于对比强调点：输入框光标、特殊标记、进度条等
        tertiary: const Color(0xFFC586C0),
        onTertiary: Colors.white, // tertiary 背景上的内容

        // ===== 错误颜色组 =====
        // 用于错误状态：错误提示文本、删除按钮、表单验证错误等
        error: const Color(0xFFF14C4C),
        onError: Colors.white, // error 背景上的内容
        errorContainer: const Color(0xFF5A1D1D), // 错误容器背景（如错误提示卡片）
        onErrorContainer: const Color(0xFFF48771), // errorContainer 背景上的内容

        // ===== 表面颜色组 =====
        // 用于组件背景：卡片、对话框、菜单、侧边栏等
        surface: darkSidebar,
        onSurface: darkText, // surface 背景上的主要内容
        surfaceDim: const Color(0xFF151517), // 变暗的表面色（如禁用状态背景）
        surfaceBright: const Color(0xFF2D2D2D), // 变亮的表面色（如高亮卡片）
        surfaceContainerLowest: const Color(0xFF191A1B), // 最低对比度容器背景
        surfaceContainerLow: const Color(0xFF1A1B1D), // 低对比度容器背景（如侧边栏）
        surfaceContainer: const Color(0xFF252526), // 标准容器背景（如卡片）
        surfaceContainerHigh: const Color(0xFF2D2D2D), // 高对比度容器背景（如弹出菜单）
        surfaceContainerHighest: const Color(0xFF151517), // 最高对比度容器背景（如分隔区域）
        onSurfaceVariant: const Color(0xFFDFDFDF), // surface 变体背景上的内容（次要文字、图标）

        // ===== 轮廓颜色 =====
        outline: darkBorder, // 用于边框、分隔线等可见轮廓
        outlineVariant: const Color(0xFF2D2D2D), // 用于更弱的分隔（如列表分隔线）

        // ===== 功能颜色 =====
        shadow: Colors.black, // 阴影颜色
        scrim: const Color(0xFF000000), // 遮罩颜色（如模态对话框背景遮罩）

        // ===== 反转颜色 =====
        // 用于需要与普通表面形成强烈对比的区域（如 SnackBar）
        inverseSurface: const Color(0xFFCCCCCC),
        onInverseSurface: const Color(0xFF1E1E1E), // inverseSurface 背景上的内容
        inversePrimary: darkPrimary, // 在深色背景上使用的主色强调
      ),

      // ================= 页面背景色 =================
      scaffoldBackgroundColor: darkBackground,

      // ================= 悬停效果 =================
      hoverColor: darkHover,
      focusColor: darkSelection,
      highlightColor: darkSelection.withAlpha(100),
      splashColor: darkSelection.withAlpha(50),
      
      // ================= AppBar（顶部栏）=================
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground, // 侧边栏背景色
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false, // 标题左对齐
        iconTheme: IconThemeData(color: darkText),
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 13, // 标题字号
          fontWeight: FontWeight.normal,
        ),
      ),

      // ================= 卡片相关 =================
      cardColor: darkSidebar,
      cardTheme: const CardThemeData(
        color: Color(0xFF252526),
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          // side: BorderSide(color: darkBorder, width: 1),
        ),
      ),

      // ================= 分隔线 =================
      dividerColor: darkBorder,
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),

      // ================= 图标主题 =================
      iconTheme: const IconThemeData(
        color: darkText,
        size: 16, // 图标大小
      ),

      // ================= 输入框主题 =================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF1A1B1D), // 输入框背景
        hoverColor: Colors.transparent, // 关闭悬停色
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: darkBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: darkBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: darkPrimary, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFF14C4C), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFF14C4C), width: 1),
        ),
        hintStyle: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 13),
        labelStyle: const TextStyle(color: Color(0xFF808080), fontSize: 13),
        floatingLabelStyle: const TextStyle(color: darkPrimary, fontSize: 13),
      ),

      // ================= 文本选择主题 =================
      // 用于设置TextField等文本输入控件的选区颜色
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: darkSelection, // 选区背景色
        selectionHandleColor: darkPrimary, // 选区内控点颜色
      ),

      // ================= 按钮主题 =================
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
          disabledForegroundColor: const Color(0xFF6E6E6E),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF2D2D2D),
          disabledForegroundColor: const Color(0xFF6E6E6E),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF2D2D2D),
          disabledForegroundColor: const Color(0xFF6E6E6E),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          disabledForegroundColor: const Color(0xFF6E6E6E),
          side: const BorderSide(color: darkBorder, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),

      // ================= 图标按钮 =================
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: darkText,
          disabledForegroundColor: const Color(0xFF6E6E6E),
          hoverColor: darkHover,
          highlightColor: darkSelection,
        ),
      ),

      // ================= 开关 =================
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkPrimary;
          return const Color(0xFF808080);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return darkPrimary.withAlpha(100);
          }
          return const Color(0xFF3A3A3A);
        }),
      ),

      // ================= 复选框 =================
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkPrimary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: Colors.white30, width: 1),
      ),

      // ================= 单选按钮 =================
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkPrimary;
          return const Color(0xFF808080);
        }),
      ),

      // ================= 滑块 =================
      sliderTheme: SliderThemeData(
        activeTrackColor: darkPrimary,
        inactiveTrackColor: const Color(0xFF3A3A3A),
        thumbColor: darkPrimary,
        overlayColor: darkPrimary.withAlpha(40),
        trackHeight: 4,
      ),

      // ================= 进度指示器 =================
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkPrimary,
        circularTrackColor: Color(0xFF3A3A3A),
        linearTrackColor: Color(0xFF3A3A3A),
      ),

      // === Tab 标签页 ===
      tabBarTheme: const TabBarThemeData(
        labelColor: darkText,
        unselectedLabelColor: Color(0xFF808080),
        indicatorColor: darkPrimary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: darkBorder,
      ),

      // === 底部导航栏 ===
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSidebar,
        selectedItemColor: darkPrimary,
        unselectedItemColor: Color(0xFF808080),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // === 导航栏 ===
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSidebar,
        indicatorColor: darkSelection,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkPrimary);
          }
          return const IconThemeData(color: Color(0xFF808080));
        }),
      ),

      // === 导航抽屉 ===
      drawerTheme: DrawerThemeData(
        backgroundColor: darkSidebar,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      // === 对话框 ===
      dialogTheme: const DialogThemeData(
        backgroundColor: darkBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: darkBorder, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        contentTextStyle: TextStyle(color: darkText, fontSize: 13),
      ),

      // === 底部弹窗 ===
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),

      // === SnackBar 提示 ===
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xE6303030),
        contentTextStyle: const TextStyle(
          color: Color(0xFFD4D4D4),
          fontSize: 13,
        ),
        actionTextColor: darkPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // === Tooltip 提示 ===
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF252526),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF454545), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.3),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
        ),
        textStyle: const TextStyle(color: darkText, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // === 弹出菜单 ===
      popupMenuTheme: PopupMenuThemeData(
        color: darkBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        textStyle: const TextStyle(color: darkText, fontSize: 13),
      ),

      // === 下拉菜单 ===
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(darkBackground),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: darkBorder, width: 1),
            ),
          ),
        ),
      ),

      // === Chip 标签 ===
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2D2D2D),
        selectedColor: darkSelection,
        disabledColor: const Color(0xFF1E1E1E),
        labelStyle: const TextStyle(color: darkText, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF808080)),
        side: const BorderSide(color: darkBorder, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ================= 文字主题 =================
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w300,
          color: darkText,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: darkText,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w300,
          color: darkText,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: darkText,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: darkText,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: darkText,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: darkText,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: darkText,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: darkText,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: darkText,
          height: 1.8,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: darkText,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFF808080),
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: darkText,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: darkTextSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF808080),
        ),
      ),
    );
  }
}
