import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/dialogs/color_picker_dialog.dart';
import 'package:quick_write/shared/widgets/segmented_control.dart';
import '../widgets/right_sidebar_widgets.dart';

/// 排版设置面板
/// 
/// 包含文字排版相关的设置项：字间距、行间距、首行缩进、自动空行、行间线条等
class TypesetPanel extends StatefulWidget {
  const TypesetPanel({super.key});

  @override
  State<TypesetPanel> createState() => _TypesetPanelState();
}

class _TypesetPanelState extends State<TypesetPanel> {
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
    // 检查组件是否仍然挂载，防止在组件销毁后调用setState()
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
    final letterSpacing = settingsService.letterSpacing;
    final lineHeight = settingsService.lineHeight;
    final isFirstLineIndentEnabled = settingsService.isFirstLineIndentEnabled;
    final autoLineBreak = settingsService.autoLineBreak;
    final showLineSeparator = settingsService.showLineSeparator;
    final lineSeparatorStyle = settingsService.lineSeparatorStyle;
    final lineSeparatorOpacity = settingsService.lineSeparatorOpacity;
    final dialogueHighlightEnabled = settingsService.dialogueHighlightEnabled;
    
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
                  // 文字间距设置区块
                  _buildTextSpacingSection(context, letterSpacing, lineHeight),
                  
                  const SizedBox(height: 20),
                  
                  // 段落格式设置区块
                  _buildParagraphFormatSection(context, isFirstLineIndentEnabled, autoLineBreak),
                  
                  const SizedBox(height: 20),
                  
                  // 显示效果设置区块
                  _buildDisplayEffectSection(context, showLineSeparator, lineSeparatorStyle, lineSeparatorOpacity),
                  
                  const SizedBox(height: 20),
                  
                  // 对话高亮设置区块
                  _buildDialogueHighlightSection(context, dialogueHighlightEnabled),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建文字间距设置区块
  Widget _buildTextSpacingSection(BuildContext context, double letterSpacing, double lineHeight) {
    return SettingsSection(
      title: '文字间距',
      icon: Icons.text_fields_outlined,
      children: [
        SliderSettingItem(
          icon: Icons.space_bar_rounded,
          label: '字间距',
          value: letterSpacing,
          min: -2,
          max: 10,
          divisions: 120,
          unit: 'px',
          onChanged: (value) {
            SettingsService.instance.updateLetterSpacing(value, debounce: true);
            setState(() {});
          },
        ),
        const SettingDivider(),
        SliderSettingItem(
          icon: Icons.format_line_spacing_rounded,
          label: '行间距',
          value: lineHeight,
          min: 1.0,
          max: 3.0,
          divisions: 20,
          unit: '倍',
          onChanged: (value) {
            SettingsService.instance.updateLineHeight(value, debounce: true);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建段落格式设置区块
  Widget _buildParagraphFormatSection(BuildContext context, bool isFirstLineIndentEnabled, bool autoLineBreak) {
    return SettingsSection(
      title: '段落格式',
      icon: Icons.format_align_left_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.format_indent_increase_rounded,
          label: '首行缩进',
          value: isFirstLineIndentEnabled,
          onChanged: (value) {
            SettingsService.instance.updateIsFirstLineIndentEnabled(value);
            setState(() {});
          },
        ),
        
        const SettingDivider(),
        SwitchSettingItem(
          icon: Icons.vertical_align_center_outlined,
          label: '自动空行',
          value: autoLineBreak,
          onChanged: (value) {
            SettingsService.instance.updateAutoLineBreak(value);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建显示效果设置区块
  Widget _buildDisplayEffectSection(BuildContext context, bool showLineSeparator, String lineSeparatorStyle, double lineSeparatorOpacity) {
    return SettingsSection(
      title: '显示效果',
      icon: Icons.visibility_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.density_small,
          label: '行间线条',
          value: showLineSeparator,
          onChanged: (value) {
            SettingsService.instance.updateShowLineSeparator(value);
            setState(() {});
          },
        ),
        // 仅在行间线开启时显示样式和不透明度选项
        if (showLineSeparator) ...[
          const SettingDivider(),
          _buildLineSeparatorStyleItem(context, lineSeparatorStyle),
          const SettingDivider(),
          SliderSettingItem(
            icon: Icons.opacity_outlined,
            label: '不透明度',
            value: lineSeparatorOpacity,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            unit: '',
            onChanged: (value) {
              SettingsService.instance.updateLineSeparatorOpacity(value, debounce: true);
              setState(() {});
            },
          ),
        ],
      ],
    );
  }

  /// 构建行间线样式选择控件（实线 / 虚线）
  Widget _buildLineSeparatorStyleItem(BuildContext context, String currentStyle) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：标签
          Row(
            children: [
              Icon(Icons.horizontal_rule, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                '线条样式',
                style: context.titleSmall?.copyWith(color: colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：分段选择器
          SegmentedControl(
            labels: const ['虚线', '实线'],
            selectedIndex: currentStyle == 'solid' ? 1 : 0,
            onChanged: (index) {
              SettingsService.instance.updateLineSeparatorStyle(index == 0 ? 'dashed' : 'solid');
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  /// 构建对话高亮设置区块
  Widget _buildDialogueHighlightSection(BuildContext context, bool dialogueHighlightEnabled) {
    return SettingsSection(
      title: '高亮设置',
      icon: Icons.chat_bubble_outline_rounded,
      children: [
        SwitchSettingItem(
          icon: Icons.format_quote_rounded,
          label: '对话高亮',
          value: dialogueHighlightEnabled,
          onChanged: (value) {
            SettingsService.instance.updateDialogueHighlightEnabled(value);
            setState(() {});
          },
        ),
        // 仅在对话高亮开启时显示颜色选项
        if (dialogueHighlightEnabled) ...[
          const SettingDivider(),
          _buildDialogueHighlightColorItem(context),
        ],
      ],
    );
  }

  /// 构建对话高亮颜色选择项
  Widget _buildDialogueHighlightColorItem(BuildContext context) {
    return SettingItem(
      icon: Icons.color_lens_outlined,
      label: '高亮颜色',
      trailing: ColorIndicator(color: ColorUtils.getDialogueHighlightColorForTheme(context)),
      onTap: () => _showDialogueHighlightColorPicker(context),
    );
  }

  /// 显示对话高亮颜色选择器对话框
  void _showDialogueHighlightColorPicker(BuildContext context) {
    ColorPickerDialog.show(
      context: context,
      title: '选择对话高亮颜色',
      initialColorHex: ColorUtils.getDialogueHighlightColorHexForTheme(context),
      onColorSelected: (colorHex) {
        ColorUtils.updateDialogueHighlightColorForTheme(context, colorHex);
        setState(() {});
      },
    );
  }
}
