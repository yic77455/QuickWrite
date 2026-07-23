import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 外观设置分组
///
/// 包含主题模式切换和暗色模式下封面变暗选项
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settingsService = SettingsService.instance;

    return SettingSectionCard(
      title: '外观',
      children: [
        _buildThemeTile(context, themeProvider),
        _buildDimCoverTile(context, settingsService),
      ],
    );
  }

  /// 构建主题切换选项
  Widget _buildThemeTile(BuildContext context, ThemeProvider themeProvider) {
    String themeName;
    IconData themeIcon;

    switch (themeProvider.themeMode) {
      case ThemeMode.light:
        themeName = '浅色模式';
        themeIcon = Icons.light_mode;
        break;
      case ThemeMode.dark:
        themeName = '深色模式';
        themeIcon = Icons.dark_mode;
        break;
      case ThemeMode.system:
        themeName = '跟随系统';
        themeIcon = Icons.settings_suggest;
        break;
    }

    return SettingTile(
      icon: themeIcon,
      title: '主题模式',
      subtitle: themeName,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showThemeDialog(context, themeProvider),
    );
  }

  /// 构建暗色模式封面变暗选项
  Widget _buildDimCoverTile(BuildContext context, SettingsService settingsService) {
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, _) {
        return SettingTile(
          icon: Icons.dark_mode_outlined,
          title: '暗色模式下封面变暗',
          subtitle: '开启后，暗色模式下封面图片会添加遮罩，减少对眼睛的刺激',
          trailing: QwSwitch(
            value: settingsService.dimCoverInDarkMode,
            onChanged: (value) async {
              await settingsService.updateDimCoverInDarkMode(value);
            },
          ),
        );
      },
    );
  }

  /// 显示主题选择对话框
  void _showThemeDialog(BuildContext context, ThemeProvider themeProvider) {
    showDialogBase(
      context: context,
      title: '选择主题',
      width: 380,
      height: 200,
      adaptiveHeight: true,
      borderRadius: 18,
      titleFontSize: 15,
      content: _ThemePickerContent(
        currentMode: themeProvider.themeMode,
        onSelected: (mode) => themeProvider.setThemeMode(mode),
      ),
    );
  }
}

/// 主题选择对话框的内容区域
///
/// 以三列卡片形式展示主题选项，点击卡片即应用并关闭
class _ThemePickerContent extends StatelessWidget {
  /// 当前主题模式
  final ThemeMode currentMode;

  /// 选择主题回调
  final void Function(ThemeMode) onSelected;

  const _ThemePickerContent({
    required this.currentMode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Row(
        children: [
          Expanded(
            child: _ThemeCard(
              mode: ThemeMode.system,
              label: '跟随系统',
              icon: Icons.settings_suggest,
              selected: currentMode == ThemeMode.system,
              onSelected: onSelected,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ThemeCard(
              mode: ThemeMode.light,
              label: '浅色',
              icon: Icons.light_mode,
              selected: currentMode == ThemeMode.light,
              onSelected: onSelected,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ThemeCard(
              mode: ThemeMode.dark,
              label: '深色',
              icon: Icons.dark_mode,
              selected: currentMode == ThemeMode.dark,
              onSelected: onSelected,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个主题卡片
///
/// 选中时显示主色边框、主色图标背景和加粗的主色文字
class _ThemeCard extends StatelessWidget {
  /// 该卡片对应的主题模式
  final ThemeMode mode;

  /// 卡片显示名称
  final String label;

  /// 卡片图标
  final IconData icon;

  /// 是否选中
  final bool selected;

  /// 选中回调
  final void Function(ThemeMode) onSelected;

  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardColor = selected
        ? colorScheme.primary.withValues(alpha: 0.08)
        : Colors.transparent;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.5);
    final iconBgColor = selected
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final iconColor = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    final textColor = selected ? colorScheme.primary : colorScheme.onSurface;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          onSelected(mode);
          Navigator.of(context).pop();
        },
        borderRadius: BorderRadius.circular(14),
        hoverColor: colorScheme.primary.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标圆形容器
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(height: 10),
              // 主题名称
              Text(
                label,
                style: context.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
