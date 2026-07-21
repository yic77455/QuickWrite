import 'package:flutter/material.dart';
import 'package:quick_write/core/models/recycle_item.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'hover_icon_button.dart';
import 'recycle_empty_state.dart';

/// 章节回收站视图
///
/// 支持单选/多选、单项恢复、单项彻底删除
/// 恢复时需要原书籍仍然存在于书架上
class ItemRecycleView extends StatelessWidget {
  /// 回收项列表
  final List<RecycleItemModel> recycledItems;

  /// 当前书架上存在的书籍 UUID 集合（用于判断章节是否可恢复）
  final Set<String> existingBookUuids;

  /// 选中的 UUID 集合
  final Set<String> selectedUuids;

  /// 切换选中状态回调
  final void Function(String) onToggleSelection;

  /// 恢复回调
  final void Function(String) onRestore;

  /// 彻底删除回调
  final void Function(String) onDelete;

  const ItemRecycleView({
    required this.recycledItems,
    required this.existingBookUuids,
    required this.selectedUuids,
    required this.onToggleSelection,
    required this.onRestore,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // 空状态
    if (recycledItems.isEmpty) {
      return const RecycleEmptyState(
        icon: Icons.auto_delete_outlined,
        title: '章节回收站是空的',
        description: '删除的章节和设定项会在这里保留，你可以随时恢复',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24, left: 32, right: 32),
      itemCount: recycledItems.length,
      itemBuilder: (context, index) {
        final item = recycledItems[index];
        final isSelected = selectedUuids.contains(item.uuid);
        // 原书籍是否还存在（决定是否可恢复）
        final isRestorable = existingBookUuids.contains(item.bookUuid);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ItemRecycleCard(
            item: item,
            isSelected: isSelected,
            isRestorable: isRestorable,
            onToggleSelection: () => onToggleSelection(item.uuid),
            onRestore: () => onRestore(item.uuid),
            onDelete: () => onDelete(item.uuid),
          ),
        );
      },
    );
  }
}

/// 章节回收站卡片
class _ItemRecycleCard extends StatelessWidget {
  final RecycleItemModel item;
  final bool isSelected;
  final bool isRestorable;
  final VoidCallback onToggleSelection;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _ItemRecycleCard({
    required this.item,
    required this.isSelected,
    required this.isRestorable,
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
              // 类型图标
              _buildTypeIcon(colorScheme),
              const SizedBox(width: 16),
              // 项目信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 原书籍不可恢复时的警告标记
                        if (!isRestorable)
                          Tooltip(
                            message: '原书籍已被删除，无法恢复',
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: colorScheme.error.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 元信息行：原书籍 + 容器 + 字数 + 删除日期
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _MetaChip(
                          icon: Icons.book_outlined,
                          text: item.bookTitle,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        _MetaChip(
                          icon: item.isChapter
                              ? Icons.folder_outlined
                              : Icons.category_outlined,
                          text: item.displayContainerName,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        _MetaChip(
                          icon: Icons.text_fields_rounded,
                          text: item.displayWordCount,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        _MetaChip(
                          icon: Icons.delete_outline_rounded,
                          text: item.displayDeletedDate,
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
                    tooltip: isRestorable ? '恢复' : '原书籍已删除，无法恢复',
                    color: isRestorable
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.3),
                    hoverBackgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    onPressed: onRestore,
                    isDisabled: !isRestorable,
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

  /// 构建类型图标
  ///
  /// 章节显示文章图标，设定项显示标签图标
  Widget _buildTypeIcon(ColorScheme colorScheme) {
    final isChapter = item.isChapter;
    final icon = isChapter ? Icons.description_outlined : Icons.account_tree_outlined;
    final bgColor = isChapter
        ? colorScheme.primaryContainer.withValues(alpha: 0.6)
        : colorScheme.secondaryContainer.withValues(alpha: 0.6);
    final iconColor = isChapter
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 22,
        color: iconColor,
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
