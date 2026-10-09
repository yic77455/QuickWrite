import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 云同步 - 同步设置分组
///
/// 提供自动同步行为配置：
/// - 自动同步开关与执行间隔
/// - 启动、退出时的自动同步开关
class SyncSettingsSection extends StatelessWidget {
  const SyncSettingsSection({super.key});

  /// 自动同步间隔选项（分钟）
  static const List<DropdownItem> _intervalItems = [
    DropdownItem(displayText: '每 10 分钟', value: '10'),
    DropdownItem(displayText: '每 30 分钟', value: '30'),
    DropdownItem(displayText: '每 60 分钟', value: '60'),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CloudSyncProvider>();

    return SettingSectionCard(
      title: '同步设置',
      children: [
        _buildAutoSyncTile(provider),
        _buildIntervalTile(provider),
        _buildStartupTile(provider),
        _buildExitTile(provider),
      ],
    );
  }

  /// 自动同步：开启后按设定间隔自动执行同步
  Widget _buildAutoSyncTile(CloudSyncProvider provider) {
    return SettingTile(
      icon: Icons.sync_outlined,
      title: '自动同步',
      subtitle: '开启后按设定间隔自动将本地变更同步到云端',
      trailing: QwSwitch(
        value: provider.autoSyncEnabled,
        onChanged: (value) => provider.setAutoSyncEnabled(value),
      ),
    );
  }

  /// 同步间隔：自动同步的执行频率，仅在自动同步开启时可用
  Widget _buildIntervalTile(CloudSyncProvider provider) {
    final enabled = provider.autoSyncEnabled;

    return SettingTile(
      icon: Icons.timer_outlined,
      title: '同步间隔',
      subtitle: '两次自动同步之间的时间间隔',
      enabled: enabled,
      trailing: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: CustomDropdown(
            width: 140,
            value: provider.syncIntervalMinutes.toString(),
            items: _intervalItems,
            onChanged: (value) => provider.setSyncIntervalMinutes(int.parse(value)),
          ),
        ),
      ),
    );
  }

  /// 启动时同步：应用启动后自动执行一次同步
  Widget _buildStartupTile(CloudSyncProvider provider) {
    return SettingTile(
      icon: Icons.power_settings_new_outlined,
      title: '启动时同步',
      subtitle: '应用启动后自动拉取云端最新的数据',
      trailing: QwSwitch(
        value: provider.syncOnStartup,
        onChanged: (value) => provider.setSyncOnStartup(value),
      ),
    );
  }

  /// 退出时同步：应用退出前自动执行一次同步
  Widget _buildExitTile(CloudSyncProvider provider) {
    return SettingTile(
      icon: Icons.logout_outlined,
      title: '退出时同步',
      subtitle: '应用退出前自动将本地数据推送到云端',
      trailing: QwSwitch(
        value: provider.syncOnExit,
        onChanged: (value) => provider.setSyncOnExit(value),
      ),
    );
  }
}
