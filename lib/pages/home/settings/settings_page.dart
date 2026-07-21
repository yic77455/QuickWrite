import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/home/settings/appearance_section.dart';
import 'package:quick_write/pages/home/settings/data_management_section.dart';
import 'package:quick_write/pages/home/settings/window_section.dart';

/// 全局设置页面
///
/// 包含以下分组：
/// - 外观：主题切换、暗色模式下封面变暗
/// - 窗口：是否在新窗口中打开工作台
/// - 数据管理：数据目录、缓存目录、备份目录、重置统计、清除备份
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
      children: [
        // 页面标题
        _buildPageHeader(context, colorScheme),
        const SizedBox(height: 28),

        // 外观设置分组
        const AppearanceSection(),
        const SizedBox(height: 20),

        // 窗口设置分组
        const WindowSection(),
        const SizedBox(height: 20),

        // 数据管理分组
        const DataManagementSection(),
      ],
    );
  }

  /// 构建页面顶部标题区域
  Widget _buildPageHeader(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '全局设置',
          style: context.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '调整外观、窗口行为和数据存储',
          style: context.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
