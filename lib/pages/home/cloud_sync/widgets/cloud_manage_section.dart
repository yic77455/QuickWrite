import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 云同步 - 云端数据管理分组
///
/// 提供云端同步数据的清理操作
class CloudManageSection extends StatelessWidget {
  const CloudManageSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CloudSyncProvider>();

    return SettingSectionCard(
      title: '云端数据管理',
      children: [
        _buildClearCloudTile(context, provider),
      ],
    );
  }

  /// 清空云端数据：删除云端存储的全部同步数据
  Widget _buildClearCloudTile(
    BuildContext context,
    CloudSyncProvider provider,
  ) {
    return SettingTile(
      icon: Icons.delete_forever_outlined,
      title: '清空云端数据',
      subtitle: '删除云端存储的全部同步数据，不影响本地文件',
      accentColor: Theme.of(context).colorScheme.error,
      enabled: provider.isConnected && !provider.isBusy,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _confirmClearCloudData(context, provider),
    );
  }

  /// 显示清空云端数据的确认对话框
  void _confirmClearCloudData(
    BuildContext context,
    CloudSyncProvider provider,
  ) {
    showConfirmDialog(
      context: context,
      title: '清空云端数据',
      description: '将删除云端存储的全部同步数据，此操作不可恢复，且不影响本地文件。',
      type: ConfirmType.delete,
      confirmText: '清除',
      cancelText: '取消',
      onConfirm: () => _clearCloudData(context, provider),
    );
  }

  /// 执行清空云端数据并提示结果
  Future<void> _clearCloudData(
    BuildContext context,
    CloudSyncProvider provider,
  ) async {
    final result = await provider.clearRemoteData();
    if (!context.mounted) return;
    SnackBarService.show(context, result.message);
  }
}
