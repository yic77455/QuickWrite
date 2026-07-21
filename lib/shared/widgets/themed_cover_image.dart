import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';

/// 封面图片组件
/// 
/// 根据当前主题模式和设置，自动决定是否为封面添加暗色遮罩：
/// - 暗色模式 + 开启设置：添加暗色遮罩
/// - 亮色模式 或 关闭设置：不添加遮罩
class ThemedCoverImage extends StatelessWidget {
  /// 封面图片路径
  final String coverPath;
  
  /// 图片填充模式
  final BoxFit fit;
  
  /// 图片加载失败时的回调
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  
  /// 用于强制刷新图片的键值（如时间戳）
  final String? cacheKey;

  const ThemedCoverImage({
    super.key,
    required this.coverPath,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settingsService = SettingsService.instance;
    
    // 使用 AnimatedBuilder 监听 SettingsService 的变化
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, child) {
        // 判断是否需要添加暗色遮罩
        final shouldDimCover = themeProvider.themeMode == ThemeMode.dark && 
                               settingsService.dimCoverInDarkMode;
        
        Widget imageWidget;
        
        if (coverPath.isEmpty) {
          // 如果没有封面路径，返回空占位
          imageWidget = const SizedBox.expand();
        } else {
          // 构建图片组件
          imageWidget = Image(
            key: cacheKey != null ? ValueKey('${coverPath}_$cacheKey') : ValueKey(coverPath),
            image: FileImage(File(coverPath)),
            fit: fit,
            errorBuilder: errorBuilder,
          );
        }
        
        // 如果需要暗色遮罩，用 ColorFiltered 包裹
        if (shouldDimCover) {
          return ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.25),
              BlendMode.darken,
            ),
            child: imageWidget,
          );
        }
        
        return imageWidget;
      },
    );
  }
}
