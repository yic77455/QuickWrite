import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'widgets/widgets.dart';

/// 云同步页面
///
/// 提供 WebDAV 云同步的完整配置界面，包含以下分组：
/// - 服务连接：服务器地址、账号密码等连接信息
/// - 同步设置：自动同步行为与同步范围
/// - 数据同步：同步状态展示与手动同步入口
/// - 云端数据管理：云端数据清理
class CloudSyncPage extends StatelessWidget {
  const CloudSyncPage({super.key});

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
  /// 移动端在标题左侧放置返回按钮，与标题同行展示；
  /// 桌面端仅渲染标题与说明
  Widget _buildPageHeader(BuildContext context, ColorScheme colorScheme) {
    final title = Text(
      '云同步',
      style: context.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        letterSpacing: 0.2,
      ),
    );
    final subtitle = Text(
      '通过 WebDAV 将书籍和应用数据备份到云端，实现多设备间同步',
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
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 8),
        subtitle,
      ],
    );
  }
}
