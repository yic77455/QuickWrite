import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/url_opener.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'widgets/widgets.dart';

/// 云同步页面
///
/// 提供云端同步的完整配置界面，支持 WebDAV 与 S3 两种协议，包含以下分组：
/// - 服务连接：协议选择与连接参数
/// - 同步设置：自动同步行为与同步范围
/// - 数据同步：同步状态展示与手动同步入口
/// - 云端数据管理：云端数据清理
class CloudSyncPage extends StatelessWidget {
  const CloudSyncPage({super.key});

  /// 帮助地址
  static const String _helpUrl = 'https://www.bilibili.com/video/BV1rT4G6gEmd';

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

        // 同步待确认提示：同步被风险预检暂停时置顶说明原因
        const SyncRiskBanner(),

        // 服务连接分组
        const ConnectionSection(),
        const SizedBox(height: 20),

        // 同步设置分组
        const SyncSettingsSection(),
        const SizedBox(height: 20),

        // 数据同步分组
        const SyncStatusSection(),
        const SizedBox(height: 20),

        // 云端数据管理分组
        const CloudManageSection(),
      ],
    );
  }

  /// 构建页面顶部标题区域
  ///
  /// 移动端在标题左侧放置返回按钮、右侧提供配置教程入口；
  /// 桌面端在标题旁提供配置教程入口，下方保留说明文字
  Widget _buildPageHeader(BuildContext context, ColorScheme colorScheme) {
    final title = Text(
      '云同步',
      style: context.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        letterSpacing: 0.2,
      ),
    );
    final subtitle = Text(
      '通过 WebDAV 或 S3 将书籍和应用数据备份到云端，实现多设备间同步',
      style: context.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );

    // 移动端：返回进入云同步前的「工具」页面
    if (PlatformCapabilities.isMobile) {
      return MobilePageHeader(
        title: title,
        subtitle: subtitle,
        onBack: () =>
            context.read<HomeStateProvider>().setPage(HomePageEnum.tools),
        actions: [
          _buildHelpButton(context, iconSize: 20, offset: const Offset(0, -1)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            title,
            const SizedBox(width: 8),
            _buildHelpButton(context),
          ],
        ),
        const SizedBox(height: 8),
        subtitle,
      ],
    );
  }

  /// 构建帮助按钮，点击后打开配置教程视频
  Widget _buildHelpButton(
    BuildContext context, {
    double iconSize = 18,
    Offset offset = const Offset(-6, 1),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Transform.translate(
      offset: offset,
      child: CursorTooltipTarget(
        showTooltip: true,
        tooltipContent: Text('配置教程', style: context.bodySmall),
        child: IconButton(
          icon: const Icon(Icons.help_outline),
          iconSize: iconSize,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          color: colorScheme.onSurfaceVariant,
          onPressed: () => _openHelp(context),
        ),
      ),
    );
  }

  /// 在系统浏览器中打开配置教程
  Future<void> _openHelp(BuildContext context) async {
    final success = await UrlOpener.open(_helpUrl);
    if (!context.mounted) return;
    SnackBarService.show(context, success ? '已在浏览器中打开配置教程' : '打开配置教程失败');
  }
}
