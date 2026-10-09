import 'package:flutter/material.dart';
import 'theme_builder.dart';
import 'theme_palette.dart';

/// 亮色主题
///
/// 亮色主题的配色由 [ThemePalette.light] 定义，并通过 [ThemeBuilder] 统一构建。
/// 保留本类是为了维持既有的调用入口，实际构建逻辑集中在 ThemeBuilder 中。
class LightTheme {
  // 全局的中文字体回退链
  static const List<String> fontFallback = ThemeBuilder.fontFallback;

  /// 获取亮色主题数据
  static ThemeData get theme => ThemeBuilder.build(ThemePalette.light);
}