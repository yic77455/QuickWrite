import 'dart:io';
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'hover_icon_button.dart';
import 'recycle_empty_state.dart';

/// 书籍回收站视图
///
/// 支持单选/多选、单项恢复、单项彻底删除
class BookRecycleView extends StatelessWidget {
  /// 回收站书籍列表
  final List<RecycleBinModel> recycledBooks;

  /// 选中的 UUID 集合
  final Set<String> selectedUuids;

  /// 切换选中状态回调
  final void Function(String) onToggleSelection;

  /// 恢复回调
  final void Function(String) onRestore;

  /// 彻底删除回调
  final void Function(String) onDelete;

  const BookRecycleView({
    required this.recycledBooks,
    required this.selectedUuids,
    required this.onToggleSelection,
    required this.onRestore,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // 空状态
    if (recycledBooks.isEmpty) {
      return const RecycleEmptyState(
        icon: Icons.delete_outline_rounded,
        title: '书籍回收站是空的',
        description: '删除的作品会在这里保留，你可以随时恢复',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24, left: 32, right: 32),
      itemCount: recycledBooks.length,
      itemBuilder: (context, index) {
        final book = recycledBooks[index];
        final isSelected = selectedUuids.contains(book.uuid);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BookRecycleCard(
            book: book,
            isSelected: isSelected,
            onToggleSelection: () => onToggleSelection(book.uuid),
            onRestore: () => onRestore(book.uuid),
            onDelete: () => onDelete(book.uuid),
          ),
        );
      },
    );
  }
}

/// 书籍回收站卡片
class _BookRecycleCard extends StatelessWidget {
  final RecycleBinModel book;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _BookRecycleCard({
    required this.book,
    required this.isSelected,
    required this.onToggleSelection,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggleSelection,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // 复选框
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelection(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              // 封面
              _buildCover(context),
              const SizedBox(width: 16),
              // 书籍信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 书名
                    Text(
                      book.title,
                      style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // 元信息行：字数 + 删除日期
                    Row(
                      children: [
                        _MetaChip(
                          icon: Icons.text_fields_rounded,
                          text: book.displayWordCount,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 12),
                        _MetaChip(
                          icon: Icons.delete_outline_rounded,
                          text: book.displayDeletedDate,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 操作按钮
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HoverIconButton(
                    icon: Icons.restore,
                    tooltip: '恢复',
                    color: colorScheme.primary,
                    hoverBackgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    onPressed: onRestore,
                  ),
                  const SizedBox(width: 4),
                  HoverIconButton(
                    icon: Icons.delete_forever_outlined,
                    tooltip: '彻底删除',
                    color: colorScheme.error,
                    hoverBackgroundColor: colorScheme.errorContainer.withValues(alpha: 0.5),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建封面
  Widget _buildCover(BuildContext context) {
    const double coverWidth = 48;
    const double coverHeight = 64;
    const double borderRadius = 4;

    // 有封面路径时尝试加载封面图片
    if (book.coverPath.isNotEmpty) {
      final coverFile = File(book.coverPath);
      if (coverFile.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: SizedBox(
            width: coverWidth,
            height: coverHeight,
            child: ThemedCoverImage(
              coverPath: book.coverPath,
              errorBuilder: (context, error, stackTrace) {
                return DefaultCover.buildThemed(
                  title: book.title,
                  context: context,
                  fontSize: 12,
                  borderRadius: 0,
                );
              },
            ),
          ),
        );
      }
    }

    // 没有封面时显示默认封面
    return SizedBox(
      width: coverWidth,
      height: coverHeight,
      child: DefaultCover.buildThemed(
        title: book.title,
        context: context,
        fontSize: 12,
        borderRadius: borderRadius,
      ),
    );
  }
}

/// 元信息小标签（图标 + 文本）
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: context.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
