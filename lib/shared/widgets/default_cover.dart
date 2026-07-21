import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';

/// 默认封面生成器
/// 
/// 根据书名生成渐变背景色的默认封面
class DefaultCover {
  DefaultCover._();

  /// 预定义的渐变色组合
  /// 
  /// 每组包含两个颜色，用于生成渐变背景
  static const List<List<Color>> _gradientColors = [
    [Color(0xFF667eea), Color(0xFF764ba2)], // 紫蓝
    [Color(0xFFf093fb), Color(0xFFf5576c)], // 粉红
    [Color(0xFF4facfe), Color(0xFF00f2fe)], // 青蓝
    [Color(0xFF43e97b), Color(0xFF38f9d7)], // 青绿
    [Color(0xFFfa709a), Color(0xFFfee140)], // 橙粉
    [Color(0xFFa8edea), Color(0xFFfed6e3)], // 浅粉青
    [Color(0xFFff9a9e), Color(0xFFfecfef)], // 浅粉
    [Color(0xFFffecd2), Color(0xFFfcb69f)], // 浅橙
    [Color(0xFFa1c4fd), Color(0xFFc2e9fb)], // 浅蓝
    [Color(0xFFd299c2), Color(0xFFfef9d7)], // 浅紫
    [Color(0xFF89f7fe), Color(0xFF66a6ff)], // 天蓝
    [Color(0xFFcd9cf2), Color(0xFFf6f3ff)], // 淡紫
    [Color(0xFFfddb92), Color(0xFFd1fdff)], // 黄青
    [Color(0xFF96fbc4), Color(0xFFf9f586)], // 黄绿
    [Color(0xFFff0844), Color(0xFFffb199)], // 红粉
    [Color(0xFF00c6fb), Color(0xFF005bea)], // 深蓝
  ];

  /// 根据字符串生成渐变色索引
  /// 
  /// 使用简单的 hash 算法，确保相同字符串总是返回相同的索引
  static int _getGradientIndex(String text) {
    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = ((hash << 5) - hash) + text.codeUnitAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
    return hash.abs() % _gradientColors.length;
  }

  /// 根据书名获取渐变色
  static List<Color> getGradientColors(String title) {
    return _gradientColors[_getGradientIndex(title)];
  }

  /// 构建默认封面 Widget
  /// 
  /// [title] 书名
  /// [fontSize] 标题字体大小
  /// [borderRadius] 圆角半径
  /// [dim] 是否添加暗色遮罩（用于暗色模式）
  static Widget build({
    required String title,
    double fontSize = 24,
    double borderRadius = 8,
    bool dim = false,
  }) {
    final colors = getGradientColors(title);

    Widget content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 如果需要变暗，添加遮罩
    if (dim) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.black.withValues(alpha: 0.25),
          BlendMode.darken,
        ),
        child: content,
      );
    }

    return content;
  }

  /// 构建主题感知的默认封面 Widget
  /// 
  /// 自动根据当前主题模式和设置决定是否变暗
  static Widget buildThemed({
    required String title,
    required BuildContext context,
    double fontSize = 24,
    double borderRadius = 8,
  }) {
    final themeProvider = context.watch<ThemeProvider>();
    final settingsService = SettingsService.instance;
    
    // 使用 AnimatedBuilder 监听 SettingsService 的变化
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, child) {
        final shouldDim = themeProvider.themeMode == ThemeMode.dark && 
                          settingsService.dimCoverInDarkMode;
        
        return build(
          title: title,
          fontSize: fontSize,
          borderRadius: borderRadius,
          dim: shouldDim,
        );
      },
    );
  }
}
