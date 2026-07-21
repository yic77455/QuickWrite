import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/segmented_control.dart';
import '../widgets/right_sidebar_widgets.dart';

/// 布局设置面板
///
/// 包含页面布局相关的设置项：显示章节标题、页边距、纸张模式等
class LayoutPanel extends StatefulWidget {
  const LayoutPanel({super.key});

  @override
  State<LayoutPanel> createState() => _LayoutPanelState();
}

class _LayoutPanelState extends State<LayoutPanel> {
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
    final showChapterTitle = settingsService.showChapterTitle;
    final topMargin = settingsService.topMargin;
    final horizontalMargin = settingsService.horizontalMargin;
    final bottomMargin = settingsService.bottomMargin;
    final isPageViewEnabled = settingsService.isPageViewEnabled;
    final scrollbarAlwaysVisible = settingsService.scrollbarAlwaysVisible;
    // 大纲编辑器布局设置
    final outlineTopMargin = settingsService.outlineTopMargin;
    final outlineHorizontalMargin = settingsService.outlineHorizontalMargin;
    final outlineBottomMargin = settingsService.outlineBottomMargin;
    final outlineNodeSpacing = settingsService.outlineNodeSpacing;
    final outlinePageViewMode = settingsService.outlinePageViewMode;
    
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
                  // 页面显示设置区块
                  _buildPageDisplaySection(context, showChapterTitle, scrollbarAlwaysVisible),
                  
                  const SizedBox(height: 20),
                  
                  // 页边距设置区块
                  _buildMarginSection(context, topMargin, horizontalMargin, bottomMargin),
                  
                  const SizedBox(height: 20),
                  
                  // 视图模式设置区块
                  _buildViewModeSection(context, isPageViewEnabled),

                  const SizedBox(height: 20),

                  // 大纲编辑器设置区块
                  _buildOutlineEditorSection(
                    context,
                    outlineTopMargin,
                    outlineHorizontalMargin,
                    outlineBottomMargin,
                    outlineNodeSpacing,
                    outlinePageViewMode,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建页面显示设置区块
  Widget _buildPageDisplaySection(BuildContext context, bool showChapterTitle, bool scrollbarAlwaysVisible) {
    final settings = SettingsService.instance;
    return SettingsSection(
      title: '页面显示',
      icon: Icons.visibility_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.title_outlined,
          label: '显示章节标题',
          value: showChapterTitle,
          onChanged: (value) {
            SettingsService.instance.updateShowChapterTitle(value);
            setState(() {});
          },
        ),
        if (showChapterTitle) ...[
          // 章节标题顶边距设置
          SliderSettingItem(
            icon: Icons.vertical_align_top_outlined,
            label: '章节标题顶边距',
            value: settings.chapterTitleTopMargin,
            min: 0.0,
            max: 50.0,
            divisions: 100,
            onChanged: (value) {
              settings.updateChapterTitleTopMargin(value, debounce: true);
              setState(() {});
            },
            unit: 'px',
          ),
          const SizedBox(height: 8),
        ],
        const SettingDivider(),
        SwitchSettingItem(
          icon: Icons.expand,
          label: '滚动条常驻',
          value: scrollbarAlwaysVisible,
          onChanged: (value) {
            SettingsService.instance.updateScrollbarAlwaysVisible(value);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建页边距设置区块
  Widget _buildMarginSection(BuildContext context, double topMargin, double horizontalMargin, double bottomMargin) {
    return SettingsSection(
      title: '页边距',
      icon: Icons.padding_outlined,
      children: [
        SliderSettingItem(
          icon: Icons.vertical_align_top_outlined,
          label: '顶边距',
          value: topMargin,
          min: 0,
          max: 50,
          divisions: 100,
          unit: '%',
          onChanged: (value) {
            SettingsService.instance.updateTopMargin(value, debounce: true);
            setState(() {});
          },
        ),
        const SettingDivider(),
        SliderSettingItem(
          icon: Icons.horizontal_rule_outlined,
          label: '左右边距',
          value: horizontalMargin,
          min: 0,
          max: 40,
          divisions: 80,
          unit: '%',
          onChanged: (value) {
            SettingsService.instance.updateHorizontalMargin(value, debounce: true);
            setState(() {});
          },
        ),
        const SettingDivider(),
        SliderSettingItem(
          icon: Icons.vertical_align_bottom_outlined,
          label: '底边距',
          value: bottomMargin,
          min: 0,
          max: 100,
          divisions: 100,
          unit: '%',
          onChanged: (value) {
            SettingsService.instance.updateBottomMargin(value, debounce: true);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建页面视图设置区块
  Widget _buildViewModeSection(BuildContext context, bool isPageViewEnabled) {
    return SettingsSection(
      title: '页面视图',
      icon: Icons.view_agenda_outlined,
      children: [
        SwitchSettingItem(
          icon: Icons.description_outlined,
          label: '纸张模式',
          value: isPageViewEnabled,
          onChanged: (value) {
            SettingsService.instance.updateIsPageViewEnabled(value);
            setState(() {});
          },
        ),
      ],
    );
  }

  /// 构建大纲编辑器布局设置区块
  Widget _buildOutlineEditorSection(
    BuildContext context,
    double outlineTopMargin,
    double outlineHorizontalMargin,
    double outlineBottomMargin,
    double outlineNodeSpacing,
    String outlinePageViewMode,
  ) {
    final settings = SettingsService.instance;
    final colorScheme = Theme.of(context).colorScheme;
    // 大纲编辑器页面视图模式与分段索引的映射
    const modeList = ['adaptive', 'default', 'paper'];
    final selectedIndex = modeList.indexOf(outlinePageViewMode).clamp(0, modeList.length - 1);

    return SettingsSection(
      title: '大纲编辑器',
      icon: Icons.account_tree_outlined,
      children: [
        SliderSettingItem(
          icon: Icons.vertical_align_top_outlined,
          label: '顶边距',
          value: outlineTopMargin,
          min: 0,
          max: 50,
          divisions: 100,
          unit: '%',
          onChanged: (value) {
            settings.updateOutlineTopMargin(value, debounce: true);
            setState(() {});
          },
        ),
        const SettingDivider(),
        SliderSettingItem(
          icon: Icons.horizontal_rule_outlined,
          label: '左右边距',
          value: outlineHorizontalMargin,
          min: 0,
          max: 40,
          divisions: 80,
          unit: '%',
          onChanged: (value) {
            settings.updateOutlineHorizontalMargin(value, debounce: true);
            setState(() {});
          },
        ),
        const SettingDivider(),
        SliderSettingItem(
          icon: Icons.vertical_align_bottom_outlined,
          label: '底边距',
          value: outlineBottomMargin,
          min: 0,
          max: 100,
          divisions: 100,
          unit: '%',
          onChanged: (value) {
            settings.updateOutlineBottomMargin(value, debounce: true);
            setState(() {});
          },
        ),
        const SettingDivider(),
        SliderSettingItem(
          icon: Icons.height_outlined,
          label: '节点间距',
          value: outlineNodeSpacing,
          min: 0,
          max: 20,
          divisions: 20,
          unit: 'px',
          onChanged: (value) {
            settings.updateOutlineNodeSpacing(value, debounce: true);
            setState(() {});
          },
        ),
        const SettingDivider(),
        // 页面视图分段选择器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 2),
                  Icon(Icons.view_agenda_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Text(
                    '页面视图',
                    style: context.titleSmall?.copyWith(color: colorScheme.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedControl(
                labels: const ['自适应', '默认', '纸张'],
                selectedIndex: selectedIndex,
                onChanged: (index) {
                  settings.updateOutlinePageViewMode(modeList[index]);
                  setState(() {});
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ],
    );
  }
}
