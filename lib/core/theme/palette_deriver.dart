import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'custom_theme.dart';
import 'theme_palette.dart';

/// 主题调色板派生器
///
/// 将用户自定义的关键色叠加到基底调色板上，推导出完整的 [ThemePalette]：
/// - 未覆盖的关键色：连同其派生色一律沿用基底原值；
/// - 已覆盖的关键色：以基底内部的相对亮度差为参照，把锚点迁移到新颜色上，
///   使派生色始终与关键色保持原有的层级关系与色调一致性。
///
/// 由此保证 [derive] 在无任何覆盖时逐字段等于基底，即内置主题零变化。
class PaletteDeriver {
  /// 将关键色叠加到基底调色板，得到最终调色板
  static ThemePalette derive(ThemePalette base, KeyColors overrides) {
    // ================= 解析各锚点颜色 =================
    final background = _anchor(overrides.background, base.scaffoldBackground);
    final surface = _anchor(overrides.surface, base.surface);
    final primary = _anchor(overrides.primary, base.primary);
    final accent = _anchor(overrides.accent, base.secondary);
    final text = _anchor(overrides.text, base.text);
    final textSecondary = _anchor(overrides.textSecondary, base.textSecondary);
    final border = _anchor(overrides.border, base.outline);
    final hover = _anchor(overrides.hover, base.hover);
    final selection = _anchor(overrides.selection, base.selection);
    final error = _anchor(overrides.error, base.error);

    // ================= 关键色及其派生色 =================
    // 背景锚点
    final surfaceDim = _shift(base.scaffoldBackground, base.surfaceDim, background);
    final surfaceContainerLowest =
        _shift(base.scaffoldBackground, base.surfaceContainerLowest, background);

    // 表面锚点
    final surfaceBright = _shift(base.surface, base.surfaceBright, surface);
    final surfaceContainerLow = _shift(base.surface, base.surfaceContainerLow, surface);
    final surfaceContainer = _shift(base.surface, base.surfaceContainer, surface);
    final surfaceContainerHigh = _shift(base.surface, base.surfaceContainerHigh, surface);
    final surfaceContainerHighest = _shift(base.surface, base.surfaceContainerHighest, surface);
    final cardColor = _shift(base.surface, base.cardColor, surface);
    final cardThemeSurface = _shift(base.surface, base.cardThemeSurface, surface);
    final inputFill = _shift(base.surface, base.inputFill, surface);
    final disabledBackground = _shift(base.surface, base.disabledBackground, surface);
    final trackColor = _shift(base.surface, base.trackColor, surface);
    final chipBackground = _shift(base.surface, base.chipBackground, surface);
    final chipDisabled = _shift(base.surface, base.chipDisabled, surface);
    final surfaceMenu = _shift(base.surface, base.surfaceMenu, surface);
    final snackBarBackground = _shift(base.surface, base.snackBarBackground, surface);
    final tooltipBackground = _shift(base.surface, base.tooltipBackground, surface);

    // 主色锚点
    final primaryContainer = _shift(base.primary, base.primaryContainer, primary);
    final primaryChanged = primary != base.primary;
    // 未覆盖主色时，前景色沿用基底原值，避免无谓的取整差异
    final onPrimary = primaryChanged ? _onColor(primary) : base.onPrimary;
    final onPrimaryContainer =
        primaryChanged ? _onColor(primaryContainer) : base.onPrimaryContainer;
    final inversePrimary = primaryChanged ? primary : base.inversePrimary;

    // 强调色锚点
    final accentChanged = accent != base.secondary;
    final onSecondary = accentChanged ? _onColor(accent) : base.onSecondary;

    // 文字锚点
    final textVariant = _shift(base.text, base.textVariant, text);
    final textMuted = _shift(base.text, base.textMuted, text);
    final onSurfaceVariant = _shift(base.text, base.onSurfaceVariant, text);

    // 边框锚点
    final outlineVariant = _shift(base.outline, base.outlineVariant, border);
    final checkboxBorder = _shift(base.outline, base.checkboxBorder, border);
    final tooltipBorder = base.hasTooltipBorder ? border : base.tooltipBorder;

    // 错误锚点
    final errorContainer = _shift(base.error, base.errorContainer, error);
    final onErrorContainer =
        error != base.error ? _onColor(errorContainer) : base.onErrorContainer;

    return ThemePalette(
      brightness: base.brightness,
      seedColor: base.seedColor,

      // 主要颜色组
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,

      // 次要颜色组
      secondary: accent,
      onSecondary: onSecondary,
      secondaryContainer: base.secondaryContainer,
      onSecondaryContainer: textSecondary,

      // 第三颜色组
      tertiary: base.tertiary,
      onTertiary: base.onTertiary,
      tertiaryContainer: base.tertiaryContainer,

      // 错误颜色组
      error: error,
      onError: base.onError,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,

      // 表面颜色组
      surface: surface,
      onSurface: text,
      surfaceDim: surfaceDim,
      surfaceBright: surfaceBright,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      onSurfaceVariant: onSurfaceVariant,

      // 轮廓颜色
      outline: border,
      outlineVariant: outlineVariant,

      // 功能颜色
      shadow: base.shadow,
      scrim: base.scrim,

      // 反转颜色
      inverseSurface: base.inverseSurface,
      onInverseSurface: base.onInverseSurface,
      inversePrimary: inversePrimary,

      // 文字层级
      text: text,
      textSecondary: textSecondary,
      textVariant: textVariant,
      textMuted: textMuted,

      // 页面与交互
      scaffoldBackground: background,
      hover: hover,
      selection: selection,

      // 组件专用色
      cardColor: cardColor,
      cardThemeSurface: cardThemeSurface,
      inputFill: inputFill,
      disabledBackground: disabledBackground,
      trackColor: trackColor,
      chipBackground: chipBackground,
      chipDisabled: chipDisabled,
      surfaceMenu: surfaceMenu,
      snackBarBackground: snackBarBackground,
      snackBarText: base.snackBarText,
      tooltipBackground: tooltipBackground,
      tooltipBorder: tooltipBorder,
      tooltipShadowColor: base.tooltipShadowColor,
      tooltipShadowAlpha: base.tooltipShadowAlpha,
      checkboxBorder: checkboxBorder,
      radioUnselected: base.radioUnselected,
    );
  }

  /// 解析关键色：未提供时沿用基底锚点颜色
  static Color _anchor(String? hex, Color baseAnchor) {
    if (hex == null) return baseAnchor;
    return ColorUtils.parseHex(hex);
  }

  /// 以基底内部的相对亮度差为参照，把 [baseFrom] → [baseTo] 的关系迁移到 [newFrom] 上
  ///
  /// [newFrom] 与 [baseFrom] 相同时直接返回 [baseTo]，确保未覆盖的关键色逐位保持不变。
  static Color _shift(Color baseFrom, Color baseTo, Color newFrom) {
    if (newFrom == baseFrom) return baseTo;
    final fromHsl = HSLColor.fromColor(baseFrom);
    final toHsl = HSLColor.fromColor(baseTo);
    final newHsl = HSLColor.fromColor(newFrom);
    // 保持基底中两者之间的相对亮度差，色相与饱和度继承新锚点
    final delta = toHsl.lightness - fromHsl.lightness;
    final lightness = (newHsl.lightness + delta).clamp(0.0, 1.0);
    return newHsl
        .withLightness(lightness)
        .withAlpha(toHsl.alpha)
        .toColor();
  }

  /// 根据背景色的明暗选择对比度合适的前景色（近白或近深）
  static Color _onColor(Color background) {
    return background.computeLuminance() > 0.5
        ? const Color(0xFF1A1A1A)
        : Colors.white;
  }

  /// 私有构造函数，防止实例化
  PaletteDeriver._();
}