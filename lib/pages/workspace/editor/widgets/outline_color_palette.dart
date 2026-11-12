import 'package:flutter/material.dart';

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

  /// 按主题明暗调整颜色亮度，使其作为文字色时在对应背景上保持可读
  ///
  /// 颜色自身不变色相与明暗倾向，只把亮度过低/过高的颜色拉回可读区间：
  /// 暗色主题下提亮，浅色主题下压暗。
  static Color readableTextColor(Color color, Brightness brightness) {
    final HSLColor hsl = HSLColor.fromColor(color);
    if (brightness == Brightness.dark) {
      return hsl
          .withLightness(hsl.lightness.clamp(0.62, 0.78).toDouble())
          .withSaturation(hsl.saturation.clamp(0.45, 0.9).toDouble())
          .toColor();
    }
    return hsl.withLightness(hsl.lightness.clamp(0.28, 0.46).toDouble()).toColor();
  }

  /// 构建带颜色指示条的菜单图标
  ///
  /// 在图标底部叠加一条固定颜色的指示条，用于字体颜色、字底颜色等菜单项；
  /// [iconColor] 为当前图标颜色（含悬停/禁用状态），与普通菜单项保持一致。
  static Widget buildColorBarIcon(IconData icon, Color iconColor, Color indicatorColor) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor),
          // 颜色指示条，叠加在图标底部
          Positioned(
            bottom: -1,
            child: Container(width: 16, height: 4, decoration: BoxDecoration(color: indicatorColor)),
          ),
        ],
      ),
    );
  }

  /// 构建颜色色块菜单图标
  ///
  /// 以 18×18 的圆角填充色块直观表示该选项对应的颜色。
  static Widget buildColorSwatchIcon(Color swatchColor) {
    return SizedBox(
      width: 18,
      height: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: swatchColor,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.black12, width: 0.5),
        ),
      ),
    );
  }
}
