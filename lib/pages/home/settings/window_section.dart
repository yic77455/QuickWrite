import 'package:flutter/material.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';

/// 窗口设置分组
///
/// 包含是否在新窗口中打开工作台的开关
class WindowSection extends StatelessWidget {
  const WindowSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = SettingsService.instance;

    return SettingSectionCard(
      title: '窗口',
      children: [
        _buildMultiWindowTile(context, settingsService),
      ],
    );
  }

  /// 构建多窗口设置选项
  Widget _buildMultiWindowTile(BuildContext context, SettingsService settingsService) {
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, _) {
        return SettingTile(
          icon: Icons.open_in_new,
          title: '在新窗口中打开工作台',
          subtitle: '开启后，点击书籍会在新窗口中打开工作台；关闭则在当前窗口中打开',
          trailing: Switch(
            value: settingsService.openWorkspaceInNewWindow,
            onChanged: (value) async {
              // 检查是否有打开的工作台窗口
              if (MultiWindowService.instance.hasOpenWorkspaceWindows()) {
                _showCloseWindowsDialog(context);
                return;
              }
              await settingsService.updateOpenWorkspaceInNewWindow(value);
            },
          ),
        );
      },
    );
  }

  /// 显示需要关闭工作台窗口的提示对话框
  void _showCloseWindowsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('无法修改'),
          content: const Text('请先关闭所有工作台窗口后再修改此设置。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }
}
