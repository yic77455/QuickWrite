import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 启动与恢复设置分组
///
/// 包含启动时自动打开上次编辑的作品、打开作品时恢复上次标签页两个开关
class StartupSection extends StatelessWidget {
  const StartupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = SettingsService.instance;

    return SettingSectionCard(
      title: '启动与恢复',
      children: [
        _buildAutoOpenTile(settingsService),
        _buildRestoreTabsTile(settingsService),
      ],
    );
  }

  /// 构建"启动时自动打开上一次编辑的作品"设置项
  Widget _buildAutoOpenTile(SettingsService settingsService) {
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, _) {
        return SettingTile(
          icon: Icons.restart_alt,
          title: '启动时打开上次编辑的作品',
          subtitle: '开启后，软件启动时自动打开最近编辑过的作品',
          trailing: QwSwitch(
            value: settingsService.autoOpenLastWorkOnStartup,
            onChanged: (value) {
              settingsService.updateAutoOpenLastWorkOnStartup(value);
            },
          ),
        );
      },
    );
  }

  /// 构建"打开作品时恢复上一次退出时的标签页"设置项
  Widget _buildRestoreTabsTile(SettingsService settingsService) {
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, _) {
        return SettingTile(
          icon: Icons.tab_unselected,
          title: '打开作品时恢复标签页',
          subtitle: '开启后，打开作品时恢复上次退出时打开的标签页',
          trailing: QwSwitch(
            value: settingsService.restoreTabsOnOpenWork,
            onChanged: (value) {
              settingsService.updateRestoreTabsOnOpenWork(value);
            },
          ),
        );
      },
    );
  }
}