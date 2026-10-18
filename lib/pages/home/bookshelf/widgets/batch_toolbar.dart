import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 批量操作工具栏组件
///
/// 显示选中数量、全选/取消全选按钮、批量操作按钮和完成按钮
class BatchToolbar extends StatelessWidget {
  /// 已选中的数量
  final int selectedCount;

  /// 是否有选中项
  final bool hasSelection;

  /// 全选回调
  final VoidCallback onSelectAll;

  /// 取消全选回调
  final VoidCallback onDeselectAll;

  /// 移动到分组回调
  final VoidCallback onMoveToGroup;

  /// 导出回调
  final VoidCallback onExport;

  /// 删除回调
  final VoidCallback onDelete;

  /// 完成回调（退出批量模式）
  final VoidCallback onComplete;

  const BatchToolbar({
    super.key,
    required this.selectedCount,
    required this.hasSelection,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onMoveToGroup,
    required this.onExport,
    required this.onDelete,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 32, bottom: 2),
      child: Row(
        children: [
          // 选中数量提示
          Text.rich(
            TextSpan(
              text: '已选中 ',
              style: context.bodyLarge?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
              children: [
                TextSpan(
                  text: '$selectedCount',
                  style: context.bodyLarge?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: ' 本',
                  style: context.bodyLarge?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 全选按钮
          TextButton(
            onPressed: onSelectAll,
            style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))),
            child: const Text('全选'),
          ),
          const SizedBox(width: 8),
          // 取消全选按钮
          TextButton(
            onPressed: onDeselectAll,
            style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))),
            child: const Text('取消全选'),
          ),
          const Spacer(),
          // 批量操作按钮
          _buildBatchMoveToGroupButton(enabled: hasSelection, onPressed: onMoveToGroup),
          const SizedBox(width: 8),
          _buildBatchExportButton(enabled: hasSelection, onPressed: onExport),
          const SizedBox(width: 8),
          _buildBatchDeleteButton(enabled: hasSelection, onPressed: onDelete),
          const SizedBox(width: 16),
          // 退出批量模式按钮
          FilledButton.tonal(onPressed: onComplete, child: const Text('完成')),
        ],
      ),
    );
  }
}

/// 批量操作栏
///
/// 移动端位于网格下方，显示选中数量并提供移动到分组、导出、删除操作入口
class BatchActionBar extends StatelessWidget {
  /// 已选中的数量
  final int selectedCount;

  /// 是否有选中项
  final bool hasSelection;

  /// 移动到分组回调
  final VoidCallback onMoveToGroup;

  /// 导出回调
  final VoidCallback onExport;

  /// 删除回调
  final VoidCallback onDelete;

  const BatchActionBar({
    super.key,
    required this.selectedCount,
    required this.hasSelection,
    required this.onMoveToGroup,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // 页面本身已提供左右内边距，这里不再额外缩进，让按钮与网格左右边缘对齐
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 左侧：移动到、导出
          _buildBatchMoveToGroupButton(enabled: hasSelection, onPressed: onMoveToGroup),
          const SizedBox(width: 8),
          _buildBatchExportButton(enabled: hasSelection, onPressed: onExport),
          const Spacer(),
          // 右侧：删除
          _buildBatchDeleteButton(enabled: hasSelection, onPressed: onDelete),
        ],
      ),
    );
  }
}

/// 构建移动到分组按钮
Widget _buildBatchMoveToGroupButton({required bool enabled, required VoidCallback onPressed}) {
  return TextButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: const Icon(Icons.folder_outlined, size: 18),
    style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))),
    label: const Text('移动到'),
  );
}

/// 构建导出按钮
Widget _buildBatchExportButton({required bool enabled, required VoidCallback onPressed}) {
  return TextButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: const Icon(Icons.upload, size: 18),
    style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))),
    label: const Text('导出'),
  );
}

/// 构建删除按钮
Widget _buildBatchDeleteButton({required bool enabled, required VoidCallback onPressed}) {
  return TextButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: Icon(Icons.delete_outline, size: 18, color: enabled ? const Color.fromARGB(255, 224, 52, 40) : null),
    style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))),
    label: Text('删除', style: TextStyle(color: enabled ? const Color.fromARGB(255, 224, 52, 40) : null)),
  );
}
