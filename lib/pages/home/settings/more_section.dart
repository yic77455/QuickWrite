import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/home_state_provider.dart';
import 'package:quick_write/core/providers/update_provider.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';

/// 更多入口分组（移动端）
///
/// 移动端没有固定侧边栏，关于页面在此提供入口，
/// 云同步、回收站等工具类入口收纳在底部导航的「工具」页中。
class MoreSection extends StatelessWidget {
  const MoreSection({super.key});

  @override
  Widget build(BuildContext context) {
    final homeState = context.read<HomeStateProvider>();

    return SettingSectionCard(
      title: '更多',
      children: [
        _buildEntry(
          context,
          HomePageEnum.about,
          subtitle: '版本信息、开源许可与问题反馈',
          onTap: () => homeState.setPage(HomePageEnum.about),
          // 启动检查发现有新版本时显示红点，提醒用户前往关于页查看
          showUpdateDot: context.watch<UpdateProvider>().hasUpdate,
        ),
      ],
    );
  }

  /// 构建单个入口项
  ///
  /// 图标与名称直接取自页面枚举，保证与侧边栏中的展示保持一致。
  Widget _buildEntry(
    BuildContext context,
    HomePageEnum page, {
    required String subtitle,
    required VoidCallback onTap,
    bool showUpdateDot = false,
  }) {
    return SettingTile(
      icon: page.icon,
      title: page.title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 红点置于箭头前，提示该入口内存在可用更新
          if (showUpdateDot) ...[
            _buildUpdateDot(context),
            const SizedBox(width: 10),
          ],
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  /// 提示存在可用更新的红色圆点
  Widget _buildUpdateDot(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        shape: BoxShape.circle,
      ),
    );
  }
}
