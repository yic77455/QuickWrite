import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 工具页面（移动端）
///
/// 作为底部导航的「工具」入口，集中收纳云同步、回收站等辅助功能，
/// 以及帮助、关于等说明类入口。
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  /// 工具项之间的间距
  static const double _itemSpacing = 12;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final homeState = context.read<HomeStateProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        // 页面标题
        _buildPageHeader(context, colorScheme),
        const SizedBox(height: 24),

        // 工具入口竖排列表
        _buildToolTile(
          context,
          icon: HomePageEnum.cloudSync.icon,
          title: HomePageEnum.cloudSync.title,
          subtitle: '通过 WebDAV 备份与恢复创作数据',
          onTap: () => homeState.setPage(HomePageEnum.cloudSync),
        ),
        const SizedBox(height: _itemSpacing),
        _buildToolTile(
          context,
          icon: HomePageEnum.recycle.icon,
          title: HomePageEnum.recycle.title,
          subtitle: '查看并恢复已删除的作品与章节',
          onTap: () => homeState.setPage(HomePageEnum.recycle),
        ),
        const SizedBox(height: _itemSpacing),
        _buildToolTile(
          context,
          icon: Icons.help_outline_rounded,
          title: '帮助',
          subtitle: '使用指南与常见问题解答',
          onTap: () => SnackBarService.show(context, '帮助功能即将上线'),
        ),
        const SizedBox(height: _itemSpacing),
        _buildToolTile(
          context,
          icon: HomePageEnum.about.icon,
          title: HomePageEnum.about.title,
          subtitle: '版本信息、开源许可与问题反馈',
          onTap: () => homeState.setPage(HomePageEnum.about),
        ),
      ],
    );
  }

  /// 构建页面顶部标题区域
  Widget _buildPageHeader(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '工具',
          style: context.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '云同步、回收站与更多实用功能',
          style: context.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  /// 构建单个工具入口项
  ///
  /// 横向排布：左侧图标、中间名称与说明、右侧箭头，整体风格与设置卡片保持一致。
  Widget _buildToolTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 图标容器
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: colorScheme.primary),
              ),
              const SizedBox(width: 14),
              // 名称与说明
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: context.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 进入箭头
              Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
