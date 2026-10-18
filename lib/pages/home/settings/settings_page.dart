import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/home/settings/appearance_section.dart';
import 'package:quick_write/pages/home/settings/data_management_section.dart';
import 'package:quick_write/pages/home/settings/more_section.dart';
import 'package:quick_write/pages/home/settings/startup_section.dart';
import 'package:quick_write/pages/home/settings/update_section.dart';
import 'package:quick_write/pages/home/settings/window_section.dart';

/// 全局设置页面
///
/// 包含以下分组：
/// - 外观：主题切换、暗色模式下封面变暗
/// - 窗口：是否在新窗口中打开工作台（仅桌面端显示）
/// - 启动与恢复：启动时打开上次编辑的作品、打开作品时恢复标签页
/// - 更新：启动时是否自动检查更新
/// - 数据管理：数据目录、缓存目录、备份目录、重置统计、清除备份
/// - 更多：关于入口（仅移动端显示）
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 左右边距：移动端屏幕较窄，收窄留白以提升内容占比
    final double horizontalPadding = PlatformCapabilities.isMobile ? 20 : 32;
    final double topPadding = PlatformCapabilities.isMobile ? 16 : 32;

    return ListView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, topPadding, horizontalPadding, 40),
      children: [
        // 页面标题
        _buildPageHeader(context, colorScheme),
        const SizedBox(height: 28),

        // 外观设置分组
        const AppearanceSection(),
        const SizedBox(height: 20),

        // 窗口设置分组
        // 窗口行为依赖桌面端窗口系统（多窗口、关闭行为、托盘），移动端不适用
        if (PlatformCapabilities.supportsNativeWindowControl) ...[
          const WindowSection(),
          const SizedBox(height: 20),
        ],

        // 启动与恢复设置分组
        const StartupSection(),
        const SizedBox(height: 20),

        // 更新设置分组
        const UpdateSection(),
        const SizedBox(height: 20),

        // 数据管理分组
        const DataManagementSection(),

        // 更多入口分组
        // 移动端没有固定侧边栏，关于页面在此提供入口
        if (PlatformCapabilities.isMobile) ...[
          const SizedBox(height: 20),
          const MoreSection(),
        ],
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
