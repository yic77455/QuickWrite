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
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 32,bottom: 2),
      child: Row(
        children: [
          // 选中数量提示
          Text(
            '已选中 $selectedCount 本',
            style: context.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 12),
          // 全选按钮
          TextButton(
            onPressed: onSelectAll,
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            ),
            child: const Text('全选'),
          ),
          const SizedBox(width: 8),
          // 取消全选按钮
          TextButton(
            onPressed: onDeselectAll,
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            ),
            child: const Text('取消全选'),
          ),
          const Spacer(),
          // 批量操作按钮
          TextButton.icon(
            onPressed: hasSelection ? onMoveToGroup : null,
            icon: const Icon(Icons.folder_outlined, size: 18),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            ),
            label: const Text('移动到'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: hasSelection ? onExport : null,
            icon: const Icon(Icons.upload, size: 18),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            ),
            label: const Text('导出'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: hasSelection ? onDelete : null,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: hasSelection ? const Color.fromARGB(255, 224, 52, 40) : null,
            ),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            ),
            label: Text(
              '删除',
              style: TextStyle(
                color: hasSelection ? const Color.fromARGB(255, 224, 52, 40) : null,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 退出批量模式按钮
          FilledButton.tonal(
            onPressed: onComplete,
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
