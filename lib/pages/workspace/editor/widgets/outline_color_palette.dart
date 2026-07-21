import 'dart:ui' show Color;

/// 大纲编辑器颜色调色板
///
/// 提供八种颜色（红橙黄绿青蓝紫灰），每种颜色包含：
/// - [foreground]：字体颜色用色（较深，保证在浅色背景上可读）
/// - [background]：字底颜色用色（较浅，保证深色字体在上可读）
///
/// 任意字体色与字底色搭配时，前景色均深于同色系背景色，确保可读性。
/// 蓝色字底色特意采用青蓝色调（Light Blue 100），与浅色主题的选区背景色
/// （纯蓝色 `#ADD6FF`）做出视觉区分。
class OutlineColorPalette {
  OutlineColorPalette._();

  /// 单个颜色项
  static const List<({Color foreground, Color background, String name})> colors = [
    (foreground: Color(0xFFD32F2F), background: Color(0xFFFFCDD2), name: '红色'),
    (foreground: Color(0xFFE65100), background: Color(0xFFFFE0B2), name: '橙色'),
    (foreground: Color(0xFFF57F17), background: Color(0xFFFFF9C4), name: '黄色'),
    (foreground: Color(0xFF2E7D32), background: Color(0xFFC8E6C9), name: '绿色'),
    (foreground: Color(0xFF00838F), background: Color(0xFFB2EBF2), name: '青色'),
    // 蓝色字底用 Light Blue 100（带青调），与选区色 #ADD6FF 区分
    (foreground: Color(0xFF1565C0), background: Color(0xFFB3E5FC), name: '蓝色'),
    (foreground: Color(0xFF6A1B9A), background: Color(0xFFE1BEE7), name: '紫色'),
    // 灰色：前景用 Gray 700，背景用 Gray 300
    (foreground: Color(0xFF616161), background: Color(0xFFE0E0E0), name: '灰色'),
  ];
}
