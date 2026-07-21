import 'dart:io';
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 回收站列表组件
/// 
/// 以列表形式展示回收站中的书籍
class RecycleBinList extends StatelessWidget {
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

  const RecycleBinList({
    super.key,
    required this.recycledBooks,
    required this.selectedUuids,
    required this.onToggleSelection,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // 顶部留出间距，避免与标题栏太近
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 16, right: 32),
      itemCount: recycledBooks.length,
      itemBuilder: (context, index) {
        final book = recycledBooks[index];
        final isSelected = selectedUuids.contains(book.uuid);
        
        return _RecycleBinListItem(
          book: book,
          isSelected: isSelected,
          onToggleSelection: () => onToggleSelection(book.uuid),
          onRestore: () => onRestore(book.uuid),
          onDelete: () => onDelete(book.uuid),
        );
      },
    );
  }
}

/// 回收站列表项组件
class _RecycleBinListItem extends StatelessWidget {
  final RecycleBinModel book;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _RecycleBinListItem({
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected 
                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            borderRadius: BorderRadius.circular(8),
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
              const SizedBox(width: 12),
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
                      style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 字数和删除日期
                    Row(
                      children: [
                        Icon(
                          Icons.text_fields_rounded,
                          size: 14,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          book.displayWordCount,
                          style: context.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          book.displayDeletedDate,
                          style: context.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
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
                  // 恢复按钮
                  _HoverIconButton(
                    icon: Icons.restore,
                    tooltip: '恢复',
                    color: colorScheme.primary,
                    hoverBackgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    onPressed: onRestore,
                  ),
                  const SizedBox(width: 4),
                  // 彻底删除按钮
                  _HoverIconButton(
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
    // 封面尺寸
    const double coverWidth = 48;
    const double coverHeight = 64;
    const double borderRadius = 4;

    // 如果有封面路径，尝试加载封面图片
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
                // 加载失败时显示默认封面
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

/// 带悬浮效果的图标按钮
/// 
/// 悬浮时显示背景色，提供更好的交互反馈
class _HoverIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color hoverBackgroundColor;
  final VoidCallback onPressed;

  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.hoverBackgroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    
    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        hoverColor: hoverBackgroundColor,
        splashColor: hoverBackgroundColor.withValues(alpha: 0.3),
        highlightColor: hoverBackgroundColor.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: color,
          ),
        ),
      ),
    );
  }
}
