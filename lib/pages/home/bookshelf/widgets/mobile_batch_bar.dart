import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 移动端批量操作工具栏
///
/// 移动端宽度有限，顶部只保留选中数量、全选切换与完成按钮，
/// 批量操作按钮交由底部操作栏承载
class MobileBatchToolbar extends StatelessWidget {
  /// 已选中的数量
  final int selectedCount;

  /// 是否已全部选中
  final bool isAllSelected;

  /// 切换全选/取消全选回调
  final VoidCallback onToggleSelectAll;

  /// 完成回调（退出批量模式）
  final VoidCallback onComplete;

  const MobileBatchToolbar({
    super.key,
    required this.selectedCount,
    required this.isAllSelected,
    required this.onToggleSelectAll,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      // 页面本身已提供左右内边距，这里不再额外缩进，让「完成」与网格右边缘对齐
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          // 左侧：选中数量与全选切换
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 选中数量提示：空间不足时省略号收尾，避免窄屏下溢出
                Flexible(
                  child: Text.rich(
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
                ),
                const SizedBox(width: 4),
                // 全选 / 取消全选切换按钮
                TextButton(
                  onPressed: onToggleSelectAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                  ),
                  child: Text(isAllSelected ? '取消全选' : '全选'),
                ),
              ],
            ),
          ),
          // 右侧：退出批量模式按钮
          FilledButton.tonal(
            onPressed: onComplete,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
