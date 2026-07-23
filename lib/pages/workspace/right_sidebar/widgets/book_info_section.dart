import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 书籍信息区域
///
/// 工具面板的概要卡片，展示当前打开书籍的封面、书名、章节数、
/// 分卷数、总字数（不含设定），以及当前标签页章节所在分卷的章节数与字数。
class BookInfoSection extends StatelessWidget {
  const BookInfoSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = context.watch<WorkspaceProvider>();
    final book = provider.currentBook;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分区标题：图标 + 文字
        Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '书籍信息',
              style: context.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 信息卡片：书籍未加载时显示占位
        book == null ? _buildPlaceholder(context) : _buildInfoCard(context, provider, book),
      ],
    );
  }

  /// 构建书籍未加载时的占位卡片
  Widget _buildPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          '书籍信息加载中...',
          style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// 构建书籍信息卡片
  Widget _buildInfoCard(BuildContext context, WorkspaceProvider provider, BookModel book) {
    final colorScheme = Theme.of(context).colorScheme;
    final chapters = provider.chapters;
    final volumes = provider.volumes;

    // 总字数（不含设定）：所有章节字数之和
    final totalWords = chapters.fold<int>(0, (sum, c) => sum + c.wordCount);

    // 解析当前标签页章节所在分卷
    // 返回 null 表示当前无章节标签页；空字符串表示未分卷；非空为分卷 UUID
    final currentVolumeUuid = _resolveCurrentVolumeUuid(provider);
    final hasCurrentChapter = currentVolumeUuid != null;
    // 仅当当前章节属于某个具体分卷时才展示分卷统计数据
    final hasCurrentVolume = currentVolumeUuid != null && currentVolumeUuid.isNotEmpty;
    final volumeName = hasCurrentChapter ? provider.getVolumeName(currentVolumeUuid) : '';
    final volumeChapters = hasCurrentVolume
        ? chapters.where((c) => c.volumeUuid == currentVolumeUuid).toList()
        : <ChapterModel>[];
    final volumeWords = volumeChapters.fold<int>(0, (sum, c) => sum + c.wordCount);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面 + 书名
          _buildHeader(context, book),
          _buildDivider(colorScheme),
          // 全局统计：章节数 / 分卷数（两列网格）
          Row(
            children: [
              Expanded(
                child: _BookStatCard(
                  icon: Icons.article_outlined,
                  label: '章节数',
                  value: '${chapters.length}',
                  unit: '章',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BookStatCard(
                  icon: Icons.collections_bookmark_outlined,
                  label: '分卷数',
                  value: '${volumes.length}',
                  unit: '卷',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 总字数（不含设定），独占一行并突出显示
          _BookStatCard(
            icon: Icons.text_fields_rounded,
            label: '总字数（不含设定）',
            value: WordCountUtils.formatWordCount(totalWords),
            highlight: true,
          ),
          _buildDivider(colorScheme),
          // 当前分卷小标题行：左侧标题 + 右侧分卷名
          _buildCurrentVolumeHeader(context, hasCurrentChapter, volumeName),
          // 当前分卷的章节数与字数（两列网格，仅在当前章节属于具体分卷时显示）
          if (hasCurrentVolume) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BookStatCard(
                    icon: Icons.article_outlined,
                    label: '分卷章节',
                    value: '${volumeChapters.length}',
                    unit: '章',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BookStatCard(
                    icon: Icons.text_fields_rounded,
                    label: '分卷字数',
                    value: WordCountUtils.formatWordCount(volumeWords),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 构建封面与书名区域
  Widget _buildHeader(BuildContext context, BookModel book) {
    final colorScheme = Theme.of(context).colorScheme;

    // 封面：有路径时显示图片，否则使用书名生成的默认渐变封面
    final coverWidget = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 64,
        height: 90,
        child: book.coverPath.isEmpty
            ? DefaultCover.buildThemed(
                title: book.title,
                context: context,
                fontSize: 12,
                borderRadius: 0,
              )
            : ThemedCoverImage(coverPath: book.coverPath, fit: BoxFit.cover),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        coverWidget,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            book.title,
            style: context.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 构建当前分卷小标题行
  ///
  /// 左侧为"当前分卷"标题，右侧显示分卷名；
  /// 无当前章节时右侧显示"未选中章节"。
  Widget _buildCurrentVolumeHeader(BuildContext context, bool hasCurrentChapter, String volumeName) {
    final colorScheme = Theme.of(context).colorScheme;
    final display = hasCurrentChapter
        ? (volumeName.isEmpty ? '未分卷' : volumeName)
        : '未选中章节';

    return Row(
      children: [
        const SizedBox(width: 6),
        Icon(Icons.folder_outlined, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          '当前分卷',
          style: context.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            display,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建分隔线
  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
    );
  }

  /// 解析当前标签页章节所在分卷 UUID
  ///
  /// 仅当当前标签页为章节类型且能匹配到章节时返回其分卷 UUID
  /// （空字符串表示未分卷）；否则返回 null 表示无当前章节。
  String? _resolveCurrentVolumeUuid(WorkspaceProvider provider) {
    final tab = provider.currentTab;
    if (tab == null || tab.type != EditorTabType.chapter) return null;
    final chapter = provider.chapters.where((c) => c.uuid == tab.id).firstOrNull;
    return chapter?.volumeUuid;
  }
}

/// 书籍统计数据卡片
///
/// 用于展示单项统计数据，包含图标、标签、数值和可选单位。
/// [highlight] 为 true 时使用更突出的样式（用于总字数等核心指标）。
class _BookStatCard extends StatelessWidget {
  /// 卡片图标
  final IconData icon;

  /// 数据标签
  final String label;

  /// 数据数值
  final String value;

  /// 数值单位（为空则不显示）
  final String unit;

  /// 是否使用突出样式
  final bool highlight;

  const _BookStatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图标 + 标签
          Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: highlight ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 数值 + 单位
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: (highlight ? context.headlineSmall : context.titleLarge)?.copyWith(
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                  color: highlight ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
