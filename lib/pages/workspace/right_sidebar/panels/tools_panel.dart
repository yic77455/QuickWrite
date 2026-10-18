import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/workspace/name_gen/name_generator_dialog.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/book_info_section.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/tools_display_settings.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/writing_stats_section.dart';

/// 工具面板
///
/// 右侧边栏的工具面板，包含功能区和按配置顺序展示的可见区块（书籍信息、码字统计）。
/// 区块的显示开关与顺序由标题栏的"显示设置"配置，配置状态由父级 [RightSidebar] 持有并通过参数传入。
class ToolsPanel extends StatefulWidget {
  /// 可见区块的显示顺序列表（元素为 [ToolsSection] 的 id）
  final List<String> sectionOrder;

  const ToolsPanel({
    super.key,
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
            // 功能区
            _buildFunctionSection(context),
            // 按配置顺序渲染可见区块（书籍信息/码字统计）
            for (int i = 0; i < widget.sectionOrder.length; i++) ...[
              const SizedBox(height: 20),
              _buildSectionById(widget.sectionOrder[i]),
            ],
          ],
        ),
      ),
    );
  }

  /// 根据区块 ID 构建对应的区块组件
  Widget _buildSectionById(String id) {
    switch (ToolsSection.fromId(id)) {
      case ToolsSection.bookInfo:
        return const BookInfoSection();
      case ToolsSection.stats:
        return WritingStatsSection(tracker: context.watch<WorkspaceProvider>().sessionTracker);
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
  Widget _buildFunctionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, '功能区', Icons.build_outlined),
        const SizedBox(height: 8),
        _buildRandomNameButton(context),
      ],
    );
  }

  /// 打开随机取名弹窗
  void _openNameGenerator() {
    showNameGeneratorDialog(context: context);
  }

  /// 构建随机取名按钮卡片
  Widget _buildRandomNameButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _openNameGenerator,
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
                child: Icon(Icons.casino_rounded, size: 22, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              // 标题和描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '随机取名',
                      style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text('一键生成角色姓名', style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
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
