import 'package:flutter/material.dart';
import 'theme_builder.dart';
import 'theme_palette.dart';

/// 暗色主题
///
/// 暗色主题的配色由 [ThemePalette.dark] 定义，并通过 [ThemeBuilder] 统一构建。
/// 保留本类是为了维持既有的调用入口，实际构建逻辑集中在 ThemeBuilder 中。
class DarkTheme {
  // 全局的中文字体回退链
  static const List<String> fontFallback = ThemeBuilder.fontFallback;

  /// 获取暗色主题数据
  static ThemeData get theme => ThemeBuilder.build(ThemePalette.dark);
}