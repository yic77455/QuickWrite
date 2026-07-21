import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示字数统计弹窗
///
/// [context] 上下文
/// [result] 字数统计详细结果
/// [chapterTitle] 章节标题
Future<void> showWordCountDialog({
  required BuildContext context,
  required WordCountResult result,
  required String chapterTitle,
}) {
  return showDialogBase(
    context: context,
    title: '字数统计',
    width: 360,
    height: 530,
    content: _WordCountDialogContent(
      result: result,
      chapterTitle: chapterTitle,
    ),
  );
}

/// 字数统计对话框内容
class _WordCountDialogContent extends StatelessWidget {
  final WordCountResult result;
  final String chapterTitle;

  const _WordCountDialogContent({
    required this.result,
    required this.chapterTitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 章节标题
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapterTitle,
                  style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '${result.wordCount} 字',
                  style: context.displayMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // 详细统计列表
          _buildStatItem(context, '字数', result.wordCount, Icons.text_fields),
          _buildStatItem(context, '中文字符', result.chineseChars, Icons.translate),
          _buildStatItem(context, '非中文单词', result.nonChineseWords, Icons.abc),
          _buildStatItem(context, '段落数', result.paragraphs, Icons.article_outlined),
          _buildStatItem(context, '标点符号', result.punctuation, Icons.abc),
          _buildStatItem(context, '数字', result.numbers, Icons.pin),
          _buildStatItem(context, '字符数（含空格、换行）', result.characters, Icons.space_bar),
          _buildStatItem(context, '字符数（不含空格、换行）', result.charactersWithoutSpaces, Icons.text_fields_outlined),
        ],
      ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem(BuildContext context, String label, int count, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: context.bodyLarge?.copyWith(color: colorScheme.onSurface),
          ),
          const Spacer(),
          Text(
            count.toString(),
            style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
