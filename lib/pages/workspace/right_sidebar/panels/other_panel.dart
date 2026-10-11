import 'package:flutter/material.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/shared/widgets/qw_dropdown.dart';
import '../widgets/right_sidebar_widgets.dart';
import '../widgets/shortcut_dialog.dart';

/// 其他设置面板
/// 
/// 包含其他相关的设置项：自动保存、自动备份、查看快捷键等
class OtherPanel extends StatefulWidget {
  const OtherPanel({super.key});

  @override
  State<OtherPanel> createState() => _OtherPanelState();
}

class _OtherPanelState extends State<OtherPanel> {
  @override
  void initState() {
    super.initState();
    // 监听设置变化
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    // 取消监听设置变化
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// 处理设置变化
  void _onSettingsChanged() {
    if (mounted) {
      setState(() {
        // 重新构建以应用新的设置
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = SettingsService.instance;
    final colorScheme = Theme.of(context).colorScheme;
    
    // 从 SettingsService 读取当前设置值
    final autoSaveEnabled = settingsService.autoSaveEnabled;
    final autoBackupEnabled = settingsService.autoBackupEnabled;
    final backupInterval = settingsService.backupInterval;
    final historyRetentionDays = settingsService.historyRetentionDays;
    final openChapterCursorMode = settingsService.openChapterCursorMode;
    final previewModeEnabled = settingsService.previewModeEnabled;
    
    // 使用 Column 布局，确保内容区域自适应填充剩余空间
    return Container(
      color: colorScheme.surface.withValues(alpha: 0.3),
      child: Column(
        children: [
          // 内容区域使用 Expanded + SingleChildScrollView 防止溢出
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 保存设置区块
                  _buildSaveSettingsSection(context, autoSaveEnabled),
                  
                  const SizedBox(height: 20),
                  
                  // 备份设置区块
                  _buildBackupSettingsSection(context, autoBackupEnabled, backupInterval, historyRetentionDays),
                  
                  const SizedBox(height: 20),
                  
                  // 编辑器行为设置区块
                  _buildEditorBehaviorSection(context, openChapterCursorMode, previewModeEnabled),
                  
                  const SizedBox(height: 20),
                  
                  // 快捷键设置区块
                  _buildShortcutSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建保存设置区块
  Widget _buildSaveSettingsSection(BuildContext context, bool autoSaveEnabled) {
    return SettingsSection(
      title: '保存设置',
      icon: Icons.save_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.auto_mode_outlined,
          label: '自动保存',
          value: autoSaveEnabled,
          onChanged: (value) {
            SettingsService.instance.updateAutoSaveEnabled(value);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建备份设置区块
  Widget _buildBackupSettingsSection(BuildContext context, bool autoBackupEnabled, int backupInterval, int historyRetentionDays) {
    // 滑块值：1~365 对应天数，366 对应永久保留（映射到 historyRetentionDays = 0）
    final sliderValue = historyRetentionDays == 0 ? 366.0 : historyRetentionDays.toDouble();

    return SettingsSection(
      title: '备份设置',
      icon: Icons.backup_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.auto_mode_outlined,
          label: '自动备份',
          value: autoBackupEnabled,
          onChanged: (value) {
            SettingsService.instance.updateAutoBackupEnabled(value);
            if (!value) {
              BackupService.instance.stopAllBackupTimers();
            }
            setState(() {});
          },
        ),
        if (autoBackupEnabled) ...[
          SliderSettingItem(
            icon: Icons.timer_outlined,
            label: '备份间隔',
            value: backupInterval.toDouble(),
            min: 1,
            max: 120,
            divisions: 119,
            unit: ' 分钟',
            decimalPlaces: 0,
            onChanged: (value) {
              SettingsService.instance.updateBackupInterval(value.toInt(), debounce: true);
              BackupService.instance.restartAllBackupTimers();
              setState(() {});
            },
          ),
          _buildRetentionDaysSlider(context, sliderValue),
        ],
      ],
    );
  }

  /// 构建历史记录保存天数滑块
  ///
  /// 滑块范围 1~366，其中 1~365 对应天数，366 对应"永久保留"
  Widget _buildRetentionDaysSlider(BuildContext context, double sliderValue) {
    final colorScheme = Theme.of(context).colorScheme;

    // 显示文本：1~365 显示"X 天"，366 显示"永久"
    final displayText = sliderValue == 366 ? '永久' : '${sliderValue.toInt()} 天';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：图标 + 标签 + 当前数值显示
          Row(
            children: [
              Icon(Icons.history_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                '保存天数',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  displayText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 第二行：滑块控件
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: sliderValue,
              min: 1,
              max: 366,
              divisions: 365,
              onChanged: (value) {
                // 366 映射为 0（永久保留），1~365 映射为对应天数
                final days = value == 366 ? 0 : value.toInt();
                SettingsService.instance.updateHistoryRetentionDays(days, debounce: true);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建编辑器行为设置区块
  Widget _buildEditorBehaviorSection(BuildContext context, String openChapterCursorMode, bool previewModeEnabled) {
    // 打开章节时光标定位模式的选项列表
    const cursorModeItems = [
      DropdownItem(displayText: '默认', value: 'default'),
      DropdownItem(displayText: '定位至章末', value: 'end'),
      DropdownItem(displayText: '上一次编辑', value: 'lastEdit'),
    ];

    return SettingsSection(
      title: '编辑器设置',
      icon: Icons.edit_outlined,
      children: [
        // 标签文字和下拉框分行显示
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标签行：图标 + 文字
              Row(
                children: [
                  Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '打开章节时',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 下拉框独占一行
              CustomDropdown(
                width: double.infinity,
                value: openChapterCursorMode,
                items: cursorModeItems,
                onChanged: (value) {
                  SettingsService.instance.updateOpenChapterCursorMode(value);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        // 预览模式开关
        SwitchSettingItem(
          icon: Icons.visibility_outlined,
          label: '预览模式',
          value: previewModeEnabled,
          onChanged: (value) {
            SettingsService.instance.updatePreviewModeEnabled(value);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建快捷键设置区块
  Widget _buildShortcutSection(BuildContext context) {
    return SettingsSection(
      title: '快捷键',
      icon: Icons.keyboard_outlined,
      children: [
        // 查看快捷键入口（点击打开快捷键列表对话框）
        _buildShortcutEntry(context),
      ],
    );
  }

  /// 构建查看快捷键入口项
  Widget _buildShortcutEntry(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWellSettingItem(
      icon: Icons.info_outlined,
      label: '查看快捷键',
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      trailing: Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.onSurfaceVariant),
      onTap: () => showShortcutDialog(context: context),
    );
  }
}
