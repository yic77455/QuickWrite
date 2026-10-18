import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/code_line_selection_utils.dart';
import 'package:quick_write/core/utils/paragraph_formatter.dart';
import 'package:quick_write/pages/workspace/editor/novel_editor.dart';
import 'package:quick_write/pages/workspace/name_gen/name_generator_dialog_mobile.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/writing_stats_section.dart';
import 'package:quick_write/shared/dialogs/export_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 移动端工具卡片可执行的动作
enum MobileToolAction {
  /// 查找替换
  findReplace,
  /// 全文搜索
  fullTextSearch,
  /// 段落整理
  formatParagraph,
  /// 历史版本
  history,
  /// 导出本章
  exportChapter,
  /// 码字统计
  writingStats,
  /// 随机取名
  randomName,
  /// 布局设置
  layout,
  /// 排版设置
  typeset,
  /// 备份设置
  backup,
  /// 其他设置
  other,
}

/// 移动端工具卡片
///
/// 由顶部操作栏的「工具」入口在操作栏下方弹出，按分区承载各类快捷功能与设置入口，
/// 每个分区内以每行三个的图标网格排列。点击某一项后卡片关闭，
/// 并通过 [onSelected] 回传所选动作
class MobileToolsCard extends StatelessWidget {
  /// 卡片最大宽度
  static const double maxWidth = 240;

  /// 卡片与屏幕左右边缘的最小留白
  static const double screenMargin = 16;

  /// 每行的图标数量（不足时补空位，保证各行图标纵向对齐）
  static const int _columns = 3;

  /// 卡片内容的内边距
  static const double _padding = 16;

  /// 卡片分区
  static const List<_ToolSection> _sections = [
    // 针对当前文档的编辑与检索操作
    _ToolSection('编辑', [
      _ToolEntry(MobileToolAction.findReplace, Icons.find_replace_rounded, '查找替换'),
      _ToolEntry(MobileToolAction.fullTextSearch, Icons.search_rounded, '全文搜索'),
      _ToolEntry(MobileToolAction.formatParagraph, Icons.format_align_left_rounded, '段落整理'),
    ]),
    // 内容辅助工具
    _ToolSection('工具', [
      _ToolEntry(MobileToolAction.history, Icons.history_rounded, '历史版本'),
      _ToolEntry(MobileToolAction.exportChapter, Icons.file_download_outlined, '导出本章'),
      _ToolEntry(MobileToolAction.writingStats, Icons.insights_rounded, '码字统计'),
      _ToolEntry(MobileToolAction.randomName, Icons.casino_rounded, '随机取名'),
    ]),
    // 各类设置面板入口
    _ToolSection('设置', [
      _ToolEntry(MobileToolAction.layout, Icons.space_dashboard_outlined, '布局'),
      _ToolEntry(MobileToolAction.typeset, Icons.format_line_spacing, '排版'),
      _ToolEntry(MobileToolAction.backup, Icons.backup_outlined, '备份'),
      _ToolEntry(MobileToolAction.other, Icons.tune_rounded, '其他'),
    ]),
  ];

  /// 选中某项后的回调
  final ValueChanged<MobileToolAction> onSelected;

  /// 卡片的最大高度
  ///
  /// 由弹出方按操作栏下方的屏幕剩余空间给出，内容超出该高度时转为内部纵向滚动，
  /// 避免横屏等纵向空间紧张的场景下工具项被截断
  final double maxHeight;

  const MobileToolsCard({super.key, required this.onSelected, required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 卡片宽度取最大宽度与「屏幕宽度减去两侧留白」中的较小值，避免贴近屏幕边缘
    final cardWidth = math.min(
      MobileToolsCard.maxWidth,
      MediaQuery.sizeOf(context).width - MobileToolsCard.screenMargin * 2,
    );

    return Material(
      color: colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: cardWidth,
        // 卡片高度限制在可用空间内，空间不足时内容转为内部纵向滚动，保证工具项都能触达
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_padding, 16, _padding, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 依次渲染各分区，分区之间用分隔线隔开
                  for (int i = 0; i < _sections.length; i++) ...[
                    if (i > 0) _buildDivider(colorScheme),
                    _buildGroupLabel(context, _sections[i].label, colorScheme),
                    const SizedBox(height: 12),
                    ..._buildSectionRows(_sections[i].entries),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建分区标签（主色竖条 + 分区名称）
  Widget _buildGroupLabel(BuildContext context, String text, ColorScheme colorScheme) {
    return Row(
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

  /// 构建分区之间的分隔线
  Widget _buildDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
    );
  }

  /// 将分区内的工具项按 [_columns] 个一行拆分为若干行
  List<Widget> _buildSectionRows(List<_ToolEntry> entries) {
    final rows = <Widget>[];
    for (int i = 0; i < entries.length; i += _columns) {
      if (i > 0) rows.add(const SizedBox(height: 6));
      rows.add(_buildRow(entries.sublist(i, math.min(i + _columns, entries.length))));
    }
    return rows;
  }

  /// 构建一行工具项，并为不足一行的部分补空位，保证各行图标纵向对齐
  Widget _buildRow(List<_ToolEntry> entries) {
    return Row(
      children: [
        for (final entry in entries)
          Expanded(
            child: _ToolItem(
              entry: entry,
              onTap: () => onSelected(entry.action),
            ),
          ),
        for (int i = entries.length; i < _columns; i++) const Expanded(child: SizedBox()),
      ],
    );
  }
}

/// 工具项配置（动作、图标、名称）
class _ToolEntry {
  /// 对应的动作
  final MobileToolAction action;

  /// 图标
  final IconData icon;

  /// 名称
  final String label;

  const _ToolEntry(this.action, this.icon, this.label);
}

/// 工具卡片分区（分区名称与分区内的工具项）
class _ToolSection {
  /// 分区名称
  final String label;

  /// 分区内的工具项
  final List<_ToolEntry> entries;

  const _ToolSection(this.label, this.entries);
}

/// 单个工具项（圆角底色图标 + 名称）
class _ToolItem extends StatelessWidget {
  /// 工具项配置
  final _ToolEntry entry;

  /// 点击回调
  final VoidCallback onTap;

  const _ToolItem({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标底衬
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(entry.icon, size: 20, color: colorScheme.primary),
            ),
            const SizedBox(height: 6),
            // 名称
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 执行移动端工具卡片所选的动作
///
/// [context] 为顶部操作栏所在上下文（位于工作台 Provider 之下）
Future<void> handleMobileToolAction(BuildContext context, MobileToolAction action) async {
  final provider = context.read<WorkspaceProvider>();

  switch (action) {
    case MobileToolAction.findReplace:
      // 切换当前编辑器的查找替换栏
      provider.toggleFindReplace();
      break;
    case MobileToolAction.fullTextSearch:
      // 打开全文搜索面板
      provider.openRightSidebar(RightSidebarType.search);
      break;
    case MobileToolAction.formatParagraph:
      // 依据排版设置一键整理当前段落
      _formatCurrentParagraph(provider);
      break;
    case MobileToolAction.history:
      // 打开历史版本面板
      provider.openRightSidebar(RightSidebarType.history);
      break;
    case MobileToolAction.exportChapter:
      // 导出当前章节
      _exportCurrentChapter(context, provider);
      break;
    case MobileToolAction.writingStats:
      // 以弹窗展示码字统计
      showWritingStatsDialog(context: context, tracker: provider.sessionTracker);
      break;
    case MobileToolAction.randomName:
      // 打开随机取名弹窗
      showMobileNameGeneratorDialog(context: context);
      break;
    case MobileToolAction.layout:
      // 打开布局设置面板
      provider.openRightSidebar(RightSidebarType.layout);
      break;
    case MobileToolAction.typeset:
      // 打开排版设置面板
      provider.openRightSidebar(RightSidebarType.typeset);
      break;
    case MobileToolAction.backup:
      // 打开备份设置面板（仅展示备份相关区块）
      provider.openRightSidebar(RightSidebarType.backup);
      break;
    case MobileToolAction.other:
      // 打开其他设置面板（仅展示编辑器相关区块）
      provider.openRightSidebar(RightSidebarType.other);
      break;
  }
}

/// 依据排版设置一键整理当前标签页的段落
///
/// 仅对正文编辑器（拥有文本控制器的标签页）生效
void _formatCurrentParagraph(WorkspaceProvider provider) {
  final tab = provider.currentTab;
  if (tab == null || tab.textController == null) return;

  final controller = tab.textController!;
  final String currentText = controller.text;
  if (currentText.isEmpty) return;

  final String formattedText = ParagraphFormatter.formatText(currentText);
  if (formattedText == currentText) return;

  // 程序化改写全文，不产生编辑事件
  NovelEditorState.runSilently(() {
    controller.text = formattedText;
    controller.selection = CodeLineSelectionUtils.collapsedSelection(formattedText, 0);
  });

  // 标记为已修改并更新字数统计
  if (!tab.isModified) {
    tab.isModified = true;
    provider.notifyTabModified(tab.id);
  }
  tab.updateWordCount();
  provider.notifyWordCountUpdated();

  // 触发自动保存
  provider.triggerAutoSave();
}

/// 导出当前标签页对应的章节
///
/// 当前标签页不是章节（如设定项）时提示并中止
void _exportCurrentChapter(BuildContext context, WorkspaceProvider provider) {
  final tab = provider.currentTab;
  if (tab == null) return;

  ChapterModel? chapter;
  for (final item in provider.chapters) {
    if (item.uuid == tab.id) {
      chapter = item;
      break;
    }
  }

  if (chapter == null) {
    SnackBarService.show(context, '当前标签页不是章节，无法导出');
    return;
  }

  showExportDialog(
    context: context,
    mode: ExportMode.chapter,
    chapters: [chapter],
    bookTitle: provider.bookTitle,
  );
}
