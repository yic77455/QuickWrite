import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 辅助信息行组件
/// 
/// 用于展示书籍的元信息（字数、章节、编辑时间等）
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: context.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.secondary),
        ),
        Expanded(
          child: Text(
            value,
            style: context.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
