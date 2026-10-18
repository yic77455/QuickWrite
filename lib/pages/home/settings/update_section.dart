import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/update_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 更新设置分组
///
/// 控制应用的更新检查方式：开启为自动检查，关闭为手动检查。
/// 手动模式下启动时不再自动检查更新，也不显示红点提醒。
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = SettingsService.instance;

    return SettingSectionCard(
      title: '更新',
      children: [_buildAutoCheckTile(context, settingsService)],
    );
  }

  /// 构建"自动检查更新"设置项
  Widget _buildAutoCheckTile(BuildContext context, SettingsService settingsService) {
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, _) {
        return SettingTile(
          icon: Icons.update_rounded,
          title: '自动检查更新',
          subtitle: '开启后启动时自动检查新版本；关闭后仅可在关于页手动检查，且不显示更新红点',
          trailing: QwSwitch(
            value: settingsService.autoCheckUpdate,
            onChanged: (value) {
              settingsService.updateAutoCheckUpdate(value);
              // 按新设置立即刷新更新状态：开启时检查一次，关闭时清除红点
              context.read<UpdateProvider>().applyAutoCheckSetting(value);
            },
          ),
        );
      },
    );
  }
}
