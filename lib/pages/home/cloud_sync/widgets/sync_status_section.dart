import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 云同步 - 数据同步分组
///
/// 展示当前连接状态与上次同步时间，提供手动同步入口
class SyncStatusSection extends StatelessWidget {
  const SyncStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CloudSyncProvider>();

    return SettingSectionCard(
      title: '数据同步',
      children: [
        _buildStatusTile(context, provider),
        _buildLastSyncTile(provider),
        _buildSyncActionRow(context, provider),
      ],
    );
  }

  /// 连接状态：展示当前云服务的连接情况
  Widget _buildStatusTile(BuildContext context, CloudSyncProvider provider) {
    return SettingTile(
      icon: provider.isConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
      title: provider.isConnected ? '已连接' : '未连接',
      subtitle: provider.isConnected ? '数据将按照同步设置自动执行同步' : '请先在服务连接中完成配置并建立连接',
      accentColor: provider.isConnected ? null : Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  /// 上次同步时间：展示最近一次同步的完成时间
  Widget _buildLastSyncTile(CloudSyncProvider provider) {
    final lastSyncTime = provider.lastSyncTime;

    return SettingTile(
      icon: Icons.schedule_outlined,
      title: '上次同步',
      subtitle: lastSyncTime != null ? _formatTime(lastSyncTime) : '尚未同步过',
    );
  }

  /// 底部操作按钮行：手动触发一次同步
  Widget _buildSyncActionRow(BuildContext context, CloudSyncProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: provider.isConnected ? () => _syncNow(context) : null,
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('立即同步'),
          ),
        ],
      ),
    );
  }

  /// 格式化同步时间的显示文本
  String _formatTime(DateTime time) {
    return '${time.year}-'
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  /// 立即同步：手动执行一次完整的同步流程
  void _syncNow(BuildContext context) {
    SnackBarService.show(context, '云同步功能正在开发中，敬请期待');
  }
}
