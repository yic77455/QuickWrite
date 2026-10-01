import 'package:flutter/material.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 云同步 - 云端数据管理分组
///
/// 提供云端同步数据的清理操作
class CloudManageSection extends StatelessWidget {
  const CloudManageSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingSectionCard(
      title: '云端数据管理',
      children: [
        _buildClearCloudTile(context),
      ],
    );
  }

  /// 清空云端数据：删除云端存储的全部同步数据
  Widget _buildClearCloudTile(BuildContext context) {
    return SettingTile(
      icon: Icons.delete_forever_outlined,
      title: '清空云端数据',
      subtitle: '删除云端存储的全部同步数据，不影响本地文件',
      accentColor: Theme.of(context).colorScheme.error,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _confirmClearCloudData(context),
    );
  }

  /// 显示清空云端数据的确认对话框
  void _confirmClearCloudData(BuildContext context) {
    showConfirmDialog(
      context: context,
      title: '清空云端数据',
      description: '将删除云端存储的全部同步数据，此操作不可恢复，且不影响本地文件。',
      type: ConfirmType.delete,
      confirmText: '清除',
      cancelText: '取消',
      onConfirm: () {
        if (!context.mounted) return;
        SnackBarService.show(context, '云同步功能正在开发中，敬请期待');
      },
    );
  }
}
