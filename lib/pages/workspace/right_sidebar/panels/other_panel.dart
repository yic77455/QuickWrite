import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/shared/widgets/qw_dropdown.dart';
import '../widgets/right_sidebar_widgets.dart';
import '../widgets/shortcut_dialog.dart';

/// 其他设置面板的区块范围
///
/// 移动端「备份设置」与「其他」两个入口共用同一面板，各自只展示对应区块：
/// 「备份设置」仅展示备份设置，「其他」仅展示编辑器设置；桌面端展示全部区块
enum OtherPanelScope {
  /// 展示全部区块（桌面端）
  all,

  /// 仅展示备份设置区块
  backup,

  /// 仅展示编辑器设置区块
  editor,
}

/// 其他设置面板
/// 
/// 包含其他相关的设置项：自动保存、自动备份、查看快捷键等
/// [scope] 决定展示的区块范围，供移动端按入口拆分区块
class OtherPanel extends StatefulWidget {
  /// 区块展示范围
  final OtherPanelScope scope;

  const OtherPanel({super.key, this.scope = OtherPanelScope.all});

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
    final quickInputBarEnabled = settingsService.quickInputBarEnabled;
    final punctuationAutoCompleteEnabled = settingsService.punctuationAutoCompleteEnabled;
    final wordCountFloatingEnabled = settingsService.wordCountFloatingEnabled;
    final wordCountFloatingPosition = settingsService.wordCountFloatingPosition;
    final wordCountFloatingSpeedEnabled = settingsService.wordCountFloatingSpeedEnabled;
    
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
                  // 保存设置区块（移动端自动保存常开，不提供该设置项）
                  if (!PlatformCapabilities.isMobile) ...[
                    _buildSaveSettingsSection(context, autoSaveEnabled),

                    const SizedBox(height: 20),
                  ],
                  
                  // 备份设置区块（「其他」入口下隐藏）
                  if (widget.scope != OtherPanelScope.editor)
                    _buildBackupSettingsSection(context, autoBackupEnabled, backupInterval, historyRetentionDays),

                  // 两区块同时展示时的间距
                  if (widget.scope == OtherPanelScope.all)
                    const SizedBox(height: 20),

                  // 编辑器行为设置区块（「备份设置」入口下隐藏）
                  if (widget.scope != OtherPanelScope.backup)
                    _buildEditorBehaviorSection(context, openChapterCursorMode, previewModeEnabled),

                  // 快捷输入设置区块（移动端专属，「备份设置」入口下隐藏）
                  if (PlatformCapabilities.isMobile && widget.scope != OtherPanelScope.backup) ...[
                    const SizedBox(height: 20),
                    _buildQuickInputSection(context, quickInputBarEnabled, punctuationAutoCompleteEnabled),
                  ],

                  // 字数浮窗设置区块（移动端专属，「备份设置」入口下隐藏）
                  if (PlatformCapabilities.isMobile && widget.scope != OtherPanelScope.backup) ...[
                    const SizedBox(height: 20),
                    _buildWordCountFloatingSection(context, wordCountFloatingEnabled, wordCountFloatingPosition, wordCountFloatingSpeedEnabled),
                  ],

                  // 快捷键设置区块（移动端没有物理键盘，不适用）
                  if (PlatformCapabilities.supportsKeyboardShortcuts) ...[
                    const SizedBox(height: 20),
                    _buildShortcutSection(context),
                  ],
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
          icon: MaterialIcons.save_clock,
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
        // 预览模式开关（移动端不提供预览模式，隐藏此项）
        if (!PlatformCapabilities.isMobile)
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

  /// 构建快捷输入设置区块（移动端专属）
  ///
  /// 管理键盘上方的快捷输入栏及其标点自动补全行为
  Widget _buildQuickInputSection(BuildContext context, bool quickInputBarEnabled, bool punctuationAutoCompleteEnabled) {
    return SettingsSection(
      title: '快捷输入',
      icon: Icons.bolt_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.keyboard_alt_outlined,
          label: '快捷输入栏',
          value: quickInputBarEnabled,
          onChanged: (value) {
            SettingsService.instance.updateQuickInputBarEnabled(value);
            setState(() {});
          },
        ),
        SwitchSettingItem(
          icon: Icons.auto_fix_high_outlined,
          label: '标点自动补全',
          value: punctuationAutoCompleteEnabled,
          onChanged: (value) {
            SettingsService.instance.updatePunctuationAutoCompleteEnabled(value);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建字数浮窗设置区块（移动端专属）
  ///
  /// 管理叠加在编辑器上的字数浮窗：开关、显示位置与码字速度开关
  Widget _buildWordCountFloatingSection(BuildContext context, bool enabled, String position, bool speedEnabled) {
    // 浮窗显示位置选项
    const positionItems = [
      DropdownItem(displayText: '左上', value: 'topLeft'),
      DropdownItem(displayText: '右上', value: 'topRight'),
      DropdownItem(displayText: '左下', value: 'bottomLeft'),
      DropdownItem(displayText: '右下', value: 'bottomRight'),
    ];

    return SettingsSection(
      title: '字数浮窗',
      icon: Icons.picture_in_picture_alt_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.visibility_outlined,
          label: '开启',
          value: enabled,
          onChanged: (value) {
            SettingsService.instance.updateWordCountFloatingEnabled(value);
            setState(() {});
          },
        ),
        // 显示位置与码字速度在浮窗开启后才可配置
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标签行：图标 + 文字
                Row(
                  children: [
                    Icon(
                      Icons.pin_drop_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '显示位置',
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
                  value: position,
                  items: positionItems,
                  onChanged: (value) {
                    SettingsService.instance.updateWordCountFloatingPosition(value);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          SwitchSettingItem(
            icon: Icons.speed_outlined,
            label: '码字速度',
            value: speedEnabled,
            onChanged: (value) {
              SettingsService.instance.updateWordCountFloatingSpeedEnabled(value);
              setState(() {});
            },
          ),
        ],
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
