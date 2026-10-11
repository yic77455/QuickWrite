import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import '../utils/shortcut_catalog.dart';

/// 快捷键条目行
///
/// 左列展示功能描述，右列展示等宽字体的按键徽标，
/// 供大纲编辑器快捷键面板与快捷键查看对话框共用，保证两处样式一致。
class ShortcutEntryTile extends StatelessWidget {
  /// 快捷键条目数据
  final ShortcutEntry entry;

  const ShortcutEntryTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左列：功能描述
          Expanded(
            child: Text(
              entry.description,
              style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          // 右列：快捷键徽标
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Text(
              entry.keys,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
