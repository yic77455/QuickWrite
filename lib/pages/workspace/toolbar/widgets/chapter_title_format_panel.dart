import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/shared/dialogs/color_picker_dialog.dart';

/// 章节标题格式设置面板
///
/// 作为顶部工具栏"更多格式"下拉菜单的内容，
/// 提供章节标题字体大小、章节标题颜色及恢复默认设置的快捷操作
class ChapterTitleFormatPanel extends StatefulWidget {
  /// 关闭外层菜单的回调
  final VoidCallback onCloseMenu;

  const ChapterTitleFormatPanel({
    super.key,
    required this.onCloseMenu,
  });

  @override
  State<ChapterTitleFormatPanel> createState() => _ChapterTitleFormatPanelState();
}

class _ChapterTitleFormatPanelState extends State<ChapterTitleFormatPanel> {
  // 面板固定宽度，确保滑块和文字有足够空间
  static const double _panelWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = SettingsService.instance;

    return Container(
      width: _panelWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 章节标题字体大小标签行
          _buildFontSizeLabelRow(context, settings, colorScheme),
          const SizedBox(height: 6),
          // 字体大小滑块（Slider 自带手指样式）
          _buildFontSizeSlider(context, settings, colorScheme),
          // 分隔线
          _buildDivider(colorScheme),
          // 章节标题颜色选择行
          _buildColorRow(context, colorScheme),
          _buildDivider(colorScheme),
          // 恢复默认设置入口
          _buildResetRow(context, colorScheme),
        ],
      ),
    );
  }

  /// 构建章节标题字体大小标签行（图标 + 标签 + 当前数值）
  Widget _buildFontSizeLabelRow(
    BuildContext context,
    SettingsService settings,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Icon(Icons.text_fields_outlined, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(
          '标题字体大小',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
        ),
        const Spacer(),
        // 当前数值标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${settings.chapterTitleFontSize.toStringAsFixed(1)}px',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }

  /// 构建字体大小滑块
  Widget _buildFontSizeSlider(
    BuildContext context,
    SettingsService settings,
    ColorScheme colorScheme,
  ) {
    return SliderTheme(
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
        value: settings.chapterTitleFontSize,
        min: 12.0,
        max: 48.0,
        divisions: 36,
        onChanged: (value) {
          settings.updateChapterTitleFontSize(value, debounce: true);
          setState(() {});
        },
      ),
    );
  }

  /// 构建章节标题颜色选择行（图标 + 标签 + 颜色指示器）
  /// 仅此行的可点击区域显示手指样式
  Widget _buildColorRow(BuildContext context, ColorScheme colorScheme) {
    return InkWell(
      onTap: () => _showColorPicker(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.color_lens_outlined, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(
              '标题颜色',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
            ),
            const Spacer(),
            // 颜色指示器
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: ColorUtils.getChapterTitleColorForTheme(context),
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建恢复默认设置入口
  /// 仅用于恢复章节标题字体大小和颜色
  Widget _buildResetRow(BuildContext context, ColorScheme colorScheme) {
    return InkWell(
      onTap: () => _resetToDefaults(),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.refresh_rounded, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(
              '恢复默认设置',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建分隔线
  Widget _buildDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
    );
  }

  /// 打开颜色选择器对话框
  /// 先关闭外层菜单，再弹出颜色选择器
  void _showColorPicker(BuildContext context) {
    widget.onCloseMenu();
    ColorPickerDialog.show(
      context: context,
      title: '选择章节标题颜色',
      initialColorHex: ColorUtils.getChapterTitleColorHexForTheme(context),
      onColorSelected: (colorHex) {
        ColorUtils.updateChapterTitleColorForTheme(context, colorHex);
        setState(() {});
      },
    );
  }

  /// 恢复章节标题字体大小和颜色为默认值
  void _resetToDefaults() {
    SettingsService.instance.resetChapterTitleFormatSettings();
    setState(() {});
  }
}
