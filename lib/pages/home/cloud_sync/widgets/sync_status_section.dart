import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
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
    final progressTile = _buildProgressTile(provider);
    final pendingRiskTile = _buildPendingRiskTile(context, provider);

    return SettingSectionCard(
      title: '数据同步',
      children: [
        _buildStatusTile(context, provider),
        _buildLastSyncTile(provider),
        // ignore: use_null_aware_elements
        if (progressTile != null) progressTile,
        // ignore: use_null_aware_elements
        if (pendingRiskTile != null) pendingRiskTile,
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

  /// 同步进度：仅在同步过程中展示，位于状态与操作之间
  Widget? _buildProgressTile(CloudSyncProvider provider) {
    final progress = provider.syncProgress;
    if (progress == null) return null;

    return SettingTile(
      icon: Icons.sync_outlined,
      title: '正在同步',
      subtitle: '已处理 ${progress.done} / ${progress.total} 个文件',
      trailing: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  /// 待确认提示：同步因风险较高被暂停时展示，提示用户手动确认后继续
  ///
  /// 右侧以红点标记异常状态，与侧边栏的云同步角标呼应；点击该行可直接重新发起同步
  Widget? _buildPendingRiskTile(
    BuildContext context,
    CloudSyncProvider provider,
  ) {
    final risk = provider.pendingRisk;
    if (risk == null) return null;

    final colorScheme = Theme.of(context).colorScheme;

    return SettingTile(
      icon: Icons.report_problem_outlined,
      title: '同步待确认',
      subtitle: risk.reason ?? '本次同步改动较大，确认后才能执行',
      accentColor: colorScheme.tertiary,
      trailing: Badge(
        smallSize: 10,
        backgroundColor: colorScheme.error,
      ),
      onTap: provider.isBusy ? null : () => _syncNow(context),
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
            onPressed: provider.isConnected && !provider.isBusy
                ? () => _syncNow(context)
                : null,
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
  Future<void> _syncNow(BuildContext context) async {
    final bookshelf = context.read<BookshelfProvider>();
    final result = await context.read<CloudSyncProvider>().syncNow();
    if (!context.mounted) return;

    // 同步会直接改写数据库，需重新加载书架内存数据才能反映到界面
    await bookshelf.refresh();
    if (!context.mounted) return;

    SnackBarService.show(context, result.message);
  }
}
