import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/shared/widgets/segmented_control.dart';

/// 大纲编辑器布局设置卡片
///
/// 由大纲编辑器顶部工具栏的齿轮入口在工具栏下方弹出，
/// 集中提供大纲编辑器的顶边距、左右边距、底边距、节点间距与页面视图设置。
/// 卡片宽度、圆角、内边距与分组标签样式与顶部操作栏的下弹卡片保持一致
class OutlineEditorSettingsCard extends StatelessWidget {
  /// 卡片最大宽度
  static const double maxWidth = 240;

  /// 卡片与屏幕左右边缘的最小留白
  static const double screenMargin = 16;

  /// 卡片与齿轮按钮之间的垂直间距
  static const double anchorGap = 8;

  /// 卡片与编辑器左边缘之间的间距
  static const double editorGap = 12;

  /// 卡片内容的内边距
  static const double _padding = 16;

  /// 设置项之间的间距
  static const double _rowSpacing = 10;

  /// 分组标签与设置项之间的间距
  static const double _labelSpacing = 12;

  /// 页面视图模式取值，与分段选择器的选项顺序一一对应
  static const List<String> _pageViewModes = ['adaptive', 'default', 'paper'];

  const OutlineEditorSettingsCard({super.key});

  /// 在锚点按钮下方弹出设置卡片
  ///
  /// [anchorRect] 为齿轮按钮在屏幕坐标系中的矩形，用于确定卡片的上边缘；
  /// [editorLeft] 为编辑器左边缘的屏幕横坐标，卡片与其保持固定间距。
  /// 卡片以透明遮罩的弹窗承载，点击卡片之外的区域仅关闭卡片，
  /// 并拦截该次点击，避免误触浮层下方的编辑器
  static Future<void> show({
    required BuildContext context,
    required Rect anchorRect,
    required double editorLeft,
  }) {
    final screenSize = MediaQuery.sizeOf(context);
    final cardWidth = math.min(maxWidth, screenSize.width - screenMargin * 2);

    // 卡片左边缘与编辑器左边缘保持固定间距，并限制在屏幕范围内
    final double left =
        (editorLeft + editorGap).clamp(0.0, math.max(0.0, screenSize.width - cardWidth));
    final double top = anchorRect.bottom + anchorGap;
    // 可用高度取锚点下方到屏幕底部之间的空间，超出时卡片内容自行滚动
    final double maxHeight = screenSize.height - top - screenMargin;

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: '关闭大纲编辑器设置',
      pageBuilder: (_, _, _) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: SizedBox(
              width: cardWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: const OutlineEditorSettingsCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 以 Material 承载卡片底色与阴影，同时为内部的水波纹控件提供材质层
    return Material(
      color: colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        // 监听设置变化，使各设置项始终回显当前设置
        listenable: SettingsService.instance,
        builder: (context, _) {
          final settings = SettingsService.instance;
          // 页面视图模式在分段选择器中的当前索引
          final selectedIndex = _pageViewModes
              .indexOf(settings.outlinePageViewMode)
              .clamp(0, _pageViewModes.length - 1);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(_padding, _padding, _padding, _padding + 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGroupLabel(context, '布局'),
                const SizedBox(height: _labelSpacing),
                _buildSliderRow(
                  context,
                  icon: Icons.vertical_align_top_outlined,
                  label: '顶边距',
                  value: settings.outlineTopMargin,
                  unit: '%',
                  min: 0,
                  max: 50,
                  divisions: 100,
                  onChanged: (value) => settings.updateOutlineTopMargin(value, debounce: true),
                ),
                const SizedBox(height: _rowSpacing),
                _buildSliderRow(
                  context,
                  icon: Icons.swap_horiz,
                  label: '左右边距',
                  value: settings.outlineHorizontalMargin,
                  unit: '%',
                  min: 0,
                  max: 40,
                  divisions: 80,
                  onChanged: (value) => settings.updateOutlineHorizontalMargin(value, debounce: true),
                ),
                const SizedBox(height: _rowSpacing),
                _buildSliderRow(
                  context,
                  icon: Icons.vertical_align_bottom_outlined,
                  label: '底边距',
                  value: settings.outlineBottomMargin,
                  unit: '%',
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: (value) => settings.updateOutlineBottomMargin(value, debounce: true),
                ),
                const SizedBox(height: _rowSpacing),
                _buildSliderRow(
                  context,
                  icon: Icons.format_line_spacing_rounded,
                  label: '节点间距',
                  value: settings.outlineNodeSpacing,
                  unit: 'px',
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (value) => settings.updateOutlineNodeSpacing(value, debounce: true),
                ),
                // 页面视图仅桌面端可用，移动端固定为默认模式
                if (!PlatformCapabilities.isMobile) ...[
                  _buildDivider(colorScheme),
                  _buildGroupLabel(context, '页面视图'),
                  const SizedBox(height: _labelSpacing),
                  SegmentedControl(
                    labels: const ['自适应', '默认', '纸张'],
                    selectedIndex: selectedIndex,
                    onChanged: (index) =>
                        SettingsService.instance.updateOutlinePageViewMode(_pageViewModes[index]),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建分组标签（主色竖条 + 名称）
  Widget _buildGroupLabel(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  /// 构建滑块设置项
  ///
  /// 图标、设置名称与当前数值占一行，滑块独占其下一行
  Widget _buildSliderRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
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
                '${value.toStringAsFixed(1)}$unit',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
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
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// 构建分组之间的分隔线
  Widget _buildDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
    );
  }
}
