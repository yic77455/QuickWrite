import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示作品详情弹窗
///
/// [context] 上下文
/// [book] 要展示详情的作品
Future<void> showBookDetailDialog({
  required BuildContext context,
  required BookModel book,
}) {
  return showDialogBase(
    context: context,
    title: '作品详情',
    width: 480,
    height: 720,
    adaptiveHeight: true,
    content: _BookDetailContent(book: book),
  );
}

/// 作品详情弹窗内容
///
/// 通过 Isar 异步查询作品的分卷、章节、设定等统计数据并展示。
class _BookDetailContent extends StatefulWidget {
  final BookModel book;

  const _BookDetailContent({required this.book});

  @override
  State<_BookDetailContent> createState() => _BookDetailContentState();
}

class _BookDetailContentState extends State<_BookDetailContent> {
  // 分卷数
  int _volumeCount = 0;
  // 章节数
  int _chapterCount = 0;
  // 设定项数
  int _settingCount = 0;
  // 作品字数（所有章节字数之和）
  int _chapterWords = 0;
  // 设定字数（所有设定项字数之和）
  int _settingWords = 0;
  // 数据是否加载中
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  /// 异步加载作品的统计数据
  Future<void> _loadStatistics() async {
    final isar = context.read<BookshelfProvider>().isar;
    final bookUuid = widget.book.uuid;

    // 先创建所有查询 Future，再统一 await，实现并行查询
    final volumesFuture = isar.volumeModels
        .where()
        .bookUuidEqualTo(bookUuid)
        .sortByOrderIndex()
        .findAll();
    final chaptersFuture = isar.chapterModels
        .where()
        .bookUuidEqualTo(bookUuid)
        .sortByOrderIndex()
        .findAll();
    final settingsFuture = isar.settingItemModels
        .where()
        .bookUuidEqualTo(bookUuid)
        .sortByOrderIndex()
        .findAll();

    final volumes = await volumesFuture;
    final chapters = await chaptersFuture;
    final settings = await settingsFuture;

    if (!mounted) return;

    setState(() {
      _volumeCount = volumes.length;
      _chapterCount = chapters.length;
      _settingCount = settings.length;
      _chapterWords = chapters.fold<int>(0, (sum, c) => sum + c.wordCount);
      _settingWords = settings.fold<int>(0, (sum, s) => sum + s.wordCount);
      _isLoading = false;
    });
  }

  /// 格式化日期时间为 "YYYY-MM-DD HH:MM" 形式
  String _formatDateTime(DateTime dateTime) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)} '
        '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: _isLoading
          ? const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：封面 + 书名 + 最新章节 + 作品字数
                _buildHeader(context, colorScheme),
                _buildDivider(colorScheme),
                // 数量统计：分卷数、章节数
                _buildCountGrid(colorScheme),
                const SizedBox(height: 12),
                // 设定统计：设定数、设定字数
                _buildSettingStats(colorScheme),
                _buildDivider(colorScheme),
                // 时间信息：创建时间、上次编辑时间
                _buildTimeInfo(colorScheme),
              ],
            ),
    );
  }

  /// 构建头部区域：封面、书名、最新章节、作品字数
  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    // 封面：有路径时显示图片，否则使用书名生成的默认渐变封面
    final coverWidget = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 120,
        height: 160,
        child: widget.book.coverPath.isEmpty
            ? DefaultCover.buildThemed(
                title: widget.book.title,
                context: context,
                fontSize: 18,
                borderRadius: 0,
              )
            : ThemedCoverImage(
                coverPath: widget.book.coverPath,
                cacheKey: widget.book.updatedAt.millisecondsSinceEpoch.toString(),
                errorBuilder: (context, error, stackTrace) => DefaultCover.buildThemed(
                  title: widget.book.title,
                  context: context,
                  fontSize: 18,
                  borderRadius: 0,
                ),
              ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面阴影
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: coverWidget,
        ),
        const SizedBox(width: 20),
        // 书名 + 最新章节 + 作品字数
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.book.title,
                  style: context.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                // 最新章节
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_outlined,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.book.latestChapter,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 作品字数
                _buildWordCountCard(colorScheme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建作品字数卡片（主色调突出，用于头部）
  Widget _buildWordCountCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // color: colorScheme.primary.withValues(alpha: 0.08),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.text_fields_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '作品字数',
                style: context.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            WordCountUtils.formatWordCount(_chapterWords),
            style: context.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建数量统计区域：分卷数、章节数
  Widget _buildCountGrid(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.collections_bookmark_outlined,
            label: '分卷数',
            value: '$_volumeCount',
            unit: '卷',
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.article_outlined,
            label: '章节数',
            value: '$_chapterCount',
            unit: '章',
            colorScheme: colorScheme,
          ),
        ),
      ],
    );
  }

  /// 构建设定统计区域：设定数、设定字数
  Widget _buildSettingStats(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.description_outlined,
            label: '设定数',
            value: '$_settingCount',
            unit: '项',
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.notes_rounded,
            label: '设定字数',
            value: WordCountUtils.formatWordCount(_settingWords),
            colorScheme: colorScheme,
          ),
        ),
      ],
    );
  }

  /// 构建时间信息区域
  Widget _buildTimeInfo(ColorScheme colorScheme) {
    return Column(
      children: [
        _InfoRow(
          icon: Icons.schedule_outlined,
          label: '创建时间',
          value: _formatDateTime(widget.book.createdAt),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 10),
        _InfoRow(
          icon: Icons.edit_outlined,
          label: '上次编辑',
          value: _formatDateTime(widget.book.updatedAt),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  /// 构建分隔线
  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 16),
      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

/// 数量统计卡片
///
/// 用于展示分卷、章节、设定项的数量统计。
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final ColorScheme colorScheme;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: context.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: context.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 信息行
///
/// 用于展示创建时间、编辑时间等键值对形式的信息。
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: context.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: context.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
