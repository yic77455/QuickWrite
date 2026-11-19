import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/workspace/name_gen/name_generator_dialog.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/book_info_section.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/tools_display_settings.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/writing_stats_section.dart';
import 'package:quick_write/pages/workspace/sensitive_word/sensitive_word_check_dialog.dart';

/// 工具面板
///
/// 右侧边栏的工具面板，上方为功能区（随机取名、敏感词检测），下方为按配置顺序
/// 展示的可见区块（书籍信息、码字统计）。两个区域的显示开关与区域内顺序由标题栏的
/// "显示设置"配置，配置状态由父级 [RightSidebar] 持有并通过参数传入。
class ToolsPanel extends StatefulWidget {
  /// 功能区可见项的显示顺序列表（元素为 [ToolsSection] 的 id）
  final List<String> functionOrder;

  /// 可见区块的显示顺序列表（元素为 [ToolsSection] 的 id）
  final List<String> sectionOrder;

  const ToolsPanel({
    super.key,
    required this.functionOrder,
    required this.sectionOrder,
  });

  @override
  State<ToolsPanel> createState() => _ToolsPanelState();
}

class _ToolsPanelState extends State<ToolsPanel> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface.withValues(alpha: 0.3),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 功能区（全部工具都关闭显示时不渲染）
            if (widget.functionOrder.isNotEmpty) _buildFunctionSection(context),
            // 按配置顺序渲染可见区块（书籍信息/码字统计）
            ..._buildSectionWidgets(),
          ],
        ),
      ),
    );
  }

  /// 按配置顺序构建信息区块列表（相邻区块之间留出间距）
  ///
  /// 首个区块与上方功能区之间的间距仅在功能区可见时添加
  List<Widget> _buildSectionWidgets() {
    final widgets = <Widget>[];
    for (final id in widget.sectionOrder) {
      final section = _buildSectionById(id);
      if (section == null) continue;
      if (widgets.isNotEmpty || widget.functionOrder.isNotEmpty) {
        widgets.add(const SizedBox(height: 20));
      }
      widgets.add(section);
    }
    return widgets;
  }

  /// 根据区块 ID 构建对应的区块组件
  ///
  /// 功能区 ID 返回 null，避免误渲染到信息区块列表
  Widget? _buildSectionById(String id) {
    switch (ToolsSection.fromId(id)) {
      case ToolsSection.bookInfo:
        return const BookInfoSection();
      case ToolsSection.stats:
        return WritingStatsSection(tracker: context.watch<WorkspaceProvider>().sessionTracker);
      case ToolsSection.nameGen:
      case ToolsSection.sensitiveWord:
        return null;
    }
  }

  /// 构建分区标题（图标 + 文字）
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: context.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 构建功能区
  ///
  /// 按配置顺序排列各功能工具卡片
  Widget _buildFunctionSection(BuildContext context) {
    // 按配置顺序收集工具卡片（单项之间留出间距）
    final buttons = <Widget>[];
    for (final id in widget.functionOrder) {
      final button = _buildFunctionButton(context, id);
      if (button == null) continue;
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 8));
      buttons.add(button);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, '功能区', Icons.build_outlined),
        const SizedBox(height: 8),
        ...buttons,
      ],
    );
  }

  /// 根据区块 ID 构建对应的功能工具卡片
  ///
  /// 非功能区 ID 返回 null，避免误渲染到功能区
  Widget? _buildFunctionButton(BuildContext context, String id) {
    switch (ToolsSection.fromId(id)) {
      case ToolsSection.nameGen:
        return _buildToolButton(
          context,
          icon: Icons.casino_rounded,
          title: '随机取名',
          description: '一键生成角色姓名',
          onTap: _openNameGenerator,
        );
      case ToolsSection.sensitiveWord:
        return _buildToolButton(
          context,
          icon: Icons.gpp_bad_outlined,
          title: '敏感词检测',
          description: '扫描全书并定位敏感词',
          onTap: _openSensitiveWordCheck,
        );
      case ToolsSection.bookInfo:
      case ToolsSection.stats:
        return null;
    }
  }

  /// 打开随机取名弹窗
  void _openNameGenerator() {
    showNameGeneratorDialog(context: context);
  }

  /// 打开敏感词检测弹窗
  void _openSensitiveWordCheck() {
    showSensitiveWordCheckDialog(
      context: context,
      provider: context.read<WorkspaceProvider>(),
    );
  }

  /// 构建功能按钮卡片
  Widget _buildToolButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: colorScheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 工具图标
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              // 标题和描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(description, style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              // 右侧箭头
              Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
