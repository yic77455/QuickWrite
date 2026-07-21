import 'package:flutter/material.dart';

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
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 32),
      child: Row(
        children: [
          // 分组选择器
          groupSelector,
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
      ),
    );
  }
}
