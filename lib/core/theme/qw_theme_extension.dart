import 'package:flutter/material.dart';
import 'tab_colors.dart';

/// 应用主题扩展
///
/// 承载无法通过 Material [ColorScheme] 表达的补充配色。
/// 目前仅用于自定义主题注入派生出的标签页配色；内置亮/暗主题不注入该扩展，
/// 从而保证标签页配色沿用原有逻辑、行为保持不变。
@immutable
class QwThemeExtension extends ThemeExtension<QwThemeExtension> {
  /// 标签页配色覆盖（为 null 时回落到按亮度内置的配色）
  final TabColors? tabColors;

  const QwThemeExtension({this.tabColors});

  @override
  QwThemeExtension copyWith({TabColors? tabColors}) {
    return QwThemeExtension(tabColors: tabColors ?? this.tabColors);
  }

  @override
  QwThemeExtension lerp(ThemeExtension<QwThemeExtension>? other, double t) {
    if (other is! QwThemeExtension) return this;
    // 标签页配色为离散值，插值过程中直接取目标值
    return t < 0.5 ? this : other;
  }
}