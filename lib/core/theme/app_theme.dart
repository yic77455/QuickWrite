import 'package:flutter/material.dart';
import 'custom_theme.dart';
import 'dark_theme.dart';
import 'light_theme.dart';
import 'palette_deriver.dart';
import 'qw_theme_extension.dart';
import 'tab_colors.dart';
import 'theme_builder.dart';
import 'theme_palette.dart';

/// 应用主题
/// 
/// 定义了应用的全局主题，包括颜色方案、字体选择、边框样式等
/// 亮色主题和暗色主题已分离到单独的文件中
class AppTheme {
  // 亮色主题
  static ThemeData get lightTheme => LightTheme.theme;

  // 暗色主题
  static ThemeData get darkTheme => DarkTheme.theme;

  /// 根据自定义主题与亮度构建主题数据
  ///
  /// 以对应亮度的内置调色板为基底，叠加用户关键色派生后构建整套主题，
  /// 并注入派生出的标签页配色，使自定义配色同样覆盖标签页。
  static ThemeData buildCustom(CustomTheme theme, Brightness brightness) {
    final base = brightness == Brightness.dark ? ThemePalette.dark : ThemePalette.light;
    final keyColors = brightness == Brightness.dark ? theme.dark : theme.light;
    final palette = PaletteDeriver.derive(base, keyColors);
    return ThemeBuilder.build(palette).copyWith(
      extensions: [QwThemeExtension(tabColors: TabColors.fromPalette(palette))],
    );
  }
}