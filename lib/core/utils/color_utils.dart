import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';

/// 颜色工具类
///
/// 提供十六进制颜色字符串与 Color 对象之间的相互转换，以及从主题获取默认颜色
class ColorUtils {
  /// 将十六进制颜色字符串解析为 Color 对象
  ///
  /// 支持格式：#RRGGBB 或 #RRGGBBAA
  /// 解析失败时返回黑色
  static Color parseHex(String hexColor) {
    final String colorStr = hexColor.replaceAll('#', '');
    if (colorStr.length == 6) {
      return Color(int.parse('FF$colorStr', radix: 16));
    } else if (colorStr.length == 8) {
      return Color(int.parse(colorStr, radix: 16));
    }
    return Colors.black;
  }

  /// 将 Color 对象转换为十六进制颜色字符串（#RRGGBB 格式）
  static String toHex(Color color) {
    return '#${((color.r * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${((color.g * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${((color.b * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  /// 从主题获取默认的正文字体颜色
  static Color getDefaultFontColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// 从主题获取默认的标题字体颜色
  static Color getDefaultTitleColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// 解析颜色，如果 hexColor 为 null 则从主题获取默认颜色
  static Color parseHexOrGetDefault(String? hexColor, BuildContext context, {bool isTitle = false}) {
    if (hexColor != null) {
      return parseHex(hexColor);
    }
    return isTitle ? getDefaultTitleColor(context) : getDefaultFontColor(context);
  }

  /// 根据当前主题亮度获取正文字体颜色
  ///
  /// 自动判断亮色/暗色主题，从 SettingsService 读取对应主题的颜色配置
  /// 未设置时回退到主题默认颜色
  static Color getFontColorForTheme(BuildContext context) {
    return parseHexOrGetDefault(getFontColorHexForTheme(context), context);
  }

  /// 根据当前主题亮度获取章节标题颜色
  ///
  /// 自动判断亮色/暗色主题，从 SettingsService 读取对应主题的颜色配置
  /// 未设置时回退到主题默认颜色
  static Color getChapterTitleColorForTheme(BuildContext context) {
    return parseHexOrGetDefault(getChapterTitleColorHexForTheme(context), context, isTitle: true);
  }

  /// 获取当前主题亮度下正文字体颜色的原始 HEX 字符串
  static String? getFontColorHexForTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? SettingsService.instance.fontColorDark
        : SettingsService.instance.fontColorLight;
  }

  /// 获取当前主题亮度下章节标题颜色的原始 HEX 字符串
  static String? getChapterTitleColorHexForTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? SettingsService.instance.chapterTitleColorDark
        : SettingsService.instance.chapterTitleColorLight;
  }

  /// 更新当前主题亮度下的正文字体颜色
  static Future<void> updateFontColorForTheme(BuildContext context, String colorHex) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      await SettingsService.instance.updateFontColorDark(colorHex);
    } else {
      await SettingsService.instance.updateFontColorLight(colorHex);
    }
  }

  /// 更新当前主题亮度下的章节标题颜色
  static Future<void> updateChapterTitleColorForTheme(BuildContext context, String colorHex) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      await SettingsService.instance.updateChapterTitleColorDark(colorHex);
    } else {
      await SettingsService.instance.updateChapterTitleColorLight(colorHex);
    }
  }

  /// 安全解析十六进制颜色字符串
  ///
  /// 支持格式：#RRGGBB 或 #RRGGBBAA
  /// 解析失败或字符串不完整时返回 null
  static Color? tryParseHex(String hexColor) {
    final String colorStr = hexColor.replaceAll('#', '');
    if (colorStr.length == 6) {
      return Color(int.parse('FF$colorStr', radix: 16));
    } else if (colorStr.length == 8) {
      return Color(int.parse(colorStr, radix: 16));
    }
    return null;
  }

  /// 私有构造函数，防止实例化
  ColorUtils._();

  /// 对话高亮默认颜色（亮色主题）
  static const Color _defaultDialogueHighlightColorLight = Color(0xFFB8560F);

  /// 对话高亮默认颜色（暗色主题）
  static const Color _defaultDialogueHighlightColorDark = Color(0xFFE8A050);

  /// 根据当前主题亮度获取对话高亮颜色
  ///
  /// 自动判断亮色/暗色主题，从 SettingsService 读取对应主题的颜色配置
  /// 未设置时回退到默认颜色
  static Color getDialogueHighlightColorForTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hexColor = isDark
        ? SettingsService.instance.dialogueHighlightColorDark
        : SettingsService.instance.dialogueHighlightColorLight;
    if (hexColor != null) {
      return parseHex(hexColor);
    }
    return isDark ? _defaultDialogueHighlightColorDark : _defaultDialogueHighlightColorLight;
  }

  /// 获取当前主题亮度下对话高亮颜色的原始 HEX 字符串
  static String? getDialogueHighlightColorHexForTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? SettingsService.instance.dialogueHighlightColorDark
        : SettingsService.instance.dialogueHighlightColorLight;
  }

  /// 更新当前主题亮度下的对话高亮颜色
  static Future<void> updateDialogueHighlightColorForTheme(BuildContext context, String? colorHex) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      await SettingsService.instance.updateDialogueHighlightColorDark(colorHex);
    } else {
      await SettingsService.instance.updateDialogueHighlightColorLight(colorHex);
    }
  }
}
