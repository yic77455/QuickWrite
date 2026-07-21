import 'package:flutter/material.dart';
import 'dark_theme.dart';
import 'light_theme.dart';

/// 应用主题
/// 
/// 定义了应用的全局主题，包括颜色方案、字体选择、边框样式等
/// 亮色主题和暗色主题已分离到单独的文件中
class AppTheme {
  // 亮色主题
  static ThemeData get lightTheme => LightTheme.theme;

  // 暗色主题
  static ThemeData get darkTheme => DarkTheme.theme;
}
