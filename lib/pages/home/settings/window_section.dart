import 'package:flutter/material.dart';
import 'package:quick_write/core/models/app_settings.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 窗口设置分组
///
/// 包含是否在新窗口中打开工作台，以及关闭主窗口时的行为
class WindowSection extends StatelessWidget {
  const WindowSection({super.key});

  /// 关闭行为选项的取值（与分段控件选项一一对应）
  static const List<String> _closeActionValues = [
    AppSettings.closeActionAsk,
    AppSettings.closeActionExit,
    AppSettings.closeActionTray,
  ];

  /// 关闭行为选项的显示文字（与 [_closeActionValues] 一一对应）
  static const List<String> _closeActionLabels = ['每次询问', '退出程序', '最小化至托盘'];

  @override
  Widget build(BuildContext context) {
    final settingsService = SettingsService.instance;

    return SettingSectionCard(
      title: '窗口',
      children: [
        _buildMultiWindowTile(context, settingsService),
        _buildCloseActionTile(context, settingsService),
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
          trailing: QwSwitch(
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

  /// 构建关闭主窗口行为设置选项
  Widget _buildCloseActionTile(BuildContext context, SettingsService settingsService) {
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, _) {
        // 多窗口模式下多个窗口同属一个进程，关闭主窗口会退出整个程序，
        // 因此关闭行为固定为"最小化至托盘"，不允许用户修改
        final locked = settingsService.isMultiWindowMode;

        return SettingTile(
          icon: Icons.power_settings_new,
          title: '关闭主窗口时',
          subtitle: locked
              ? '多窗口模式下固定为"最小化至托盘"'
              : '设置点击关闭按钮时的处理方式，设置为退出程序时将禁用托盘图标',
          trailing: SizedBox(
            width: 280,
            child: SegmentedControl(
              labels: _closeActionLabels,
              selectedIndex: _closeActionIndex(settingsService.effectiveCloseWindowAction),
              disabled: locked,
              onChanged: (index) =>
                  settingsService.updateCloseWindowAction(_closeActionValues[index]),
            ),
          ),
        );
      },
    );
  }

  /// 获取关闭行为在分段控件中的索引
  int _closeActionIndex(String action) {
    final index = _closeActionValues.indexOf(action);
    return index < 0 ? 0 : index;
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
