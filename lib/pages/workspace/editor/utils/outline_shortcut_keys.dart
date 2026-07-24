import 'package:flutter/services.dart';
import '../widgets/outline_color_palette.dart';

/// 大纲编辑器快捷键按键映射
///
/// 集中管理标题级别快捷键与颜色快捷键的按键映射关系，
/// 供节点级与编辑器级键盘事件处理器共用，避免映射逻辑散落各处。
class OutlineShortcutKeys {
  OutlineShortcutKeys._();

  // ================= 标题级别 =================

  /// Alt+数字 到标题级别的映射
  ///
  /// 1/2/3 对应 H1/H2/H3，4 对应正文（level 0）。
  /// 其他按键返回 null。
  static int? headingLevelFromKey(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.digit1:
        return 1;
      case LogicalKeyboardKey.digit2:
        return 2;
      case LogicalKeyboardKey.digit3:
        return 3;
      case LogicalKeyboardKey.digit4:
        return 0;
      default:
        return null;
    }
  }

  // ================= 颜色 =================

  /// 字母按键到调色板索引的映射（红橙黄绿青蓝紫，不含灰色）
  ///
  /// 灰色未分配快捷键字母，故不在映射表中。
  static final Map<LogicalKeyboardKey, int> _colorLetterToIndex = {
    LogicalKeyboardKey.keyR: 0, // 红
    LogicalKeyboardKey.keyO: 1, // 橙
    LogicalKeyboardKey.keyY: 2, // 黄
    LogicalKeyboardKey.keyG: 3, // 绿
    LogicalKeyboardKey.keyC: 4, // 青
    LogicalKeyboardKey.keyB: 5, // 蓝
    LogicalKeyboardKey.keyP: 6, // 紫
  };

  /// 判断是否为"默认颜色"按键（D = Default）
  static bool isClearColorKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.keyD;

  /// 判断按键是否为颜色快捷键字母（D 或 R/O/Y/G/C/B/P）
  static bool isColorLetterKey(LogicalKeyboardKey key) =>
      _colorLetterToIndex.containsKey(key) || isClearColorKey(key);

  /// 根据按键获取对应的字体颜色
  ///
  /// 非颜色字母返回 null；D 为清除按键，不返回颜色，
  /// 需通过 [isClearColorKey] 单独判断后调用清除逻辑。
  static Color? foregroundColor(LogicalKeyboardKey key) {
    final index = _colorLetterToIndex[key];
    if (index == null) return null;
    return OutlineColorPalette.colors[index].foreground;
  }

  /// 根据按键获取对应的字底颜色
  ///
  /// 非颜色字母返回 null；D 为清除按键，不返回颜色，
  /// 需通过 [isClearColorKey] 单独判断后调用清除逻辑。
  static Color? backgroundColor(LogicalKeyboardKey key) {
    final index = _colorLetterToIndex[key];
    if (index == null) return null;
    return OutlineColorPalette.colors[index].background;
  }
}
