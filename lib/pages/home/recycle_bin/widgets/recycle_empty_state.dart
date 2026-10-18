import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 回收站空状态组件
///
/// 用于书籍回收站和章节回收站的空状态展示
class RecycleEmptyState extends StatelessWidget {
  /// 图标
  final IconData icon;

  /// 标题
  final String title;

  /// 描述文字
  final String description;

  const RecycleEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isMobile = PlatformCapabilities.isMobile;

    return Center(
      // 移动端收窄左右留白，避免长文本贴边
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: isMobile ? 72 : 120,
              color: colorScheme.primary.withValues(alpha: 0.4),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (isMobile ? context.titleLarge : context.displaySmall)?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: (isMobile ? context.bodyMedium : context.titleLarge)?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
