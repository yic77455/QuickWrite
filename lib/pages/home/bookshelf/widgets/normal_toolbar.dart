import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';

/// 普通模式工具栏组件
/// 
/// 显示分组选择器和操作按钮
class NormalToolbar extends StatelessWidget {
  /// 分组选择器组件
  final Widget groupSelector;
  /// 进入批量模式回调
  final VoidCallback onEnterBatchMode;
  /// 导入书籍回调
  final VoidCallback onImportBook;
  /// 新建作品回调
  final VoidCallback onAddBook;

  const NormalToolbar({
    super.key,
    required this.groupSelector,
    required this.onEnterBatchMode,
    required this.onImportBook,
    required this.onAddBook,
  });

  @override
  Widget build(BuildContext context) {
    // 移动端屏幕较窄，操作按钮由悬浮按钮组承载，工具栏只保留分组选择器
    final bool showActions = !PlatformCapabilities.isMobile;

    return Padding(
      padding: PlatformCapabilities.isMobile
          ? const EdgeInsets.only(right: 32)
          : const EdgeInsets.only(left: 12, right: 32),
      child: Row(
        children: [
          // 分组选择器
          groupSelector,
          if (showActions) ...[
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: onEnterBatchMode,
              icon: const Icon(Icons.checklist),
              label: Text(
                '批量操作',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onImportBook,
              icon: const Icon(Icons.download),
              label: Text(
                '导入书籍',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onAddBook,
              icon: const Icon(Icons.add),
              label: const Text('新建作品', style: TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}
