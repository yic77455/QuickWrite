import 'package:flutter/material.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 词典管理弹窗的操作类型
enum NameDictionarySheetActionType {
  /// 选中词典
  select,

  /// 编辑词典
  edit,

  /// 删除词典
  delete,

  /// 新建词典
  create,
}

/// 词典管理弹窗返回的操作
///
/// 用户点击列表中某一词典、编辑/删除按钮或底部新建按钮后，
/// 弹窗关闭并回传对应的操作，由调用方据此执行具体逻辑。
class NameDictionarySheetAction {
  /// 操作类型
  final NameDictionarySheetActionType type;

  /// 操作涉及的词典
  ///
  /// 选中、编辑、删除时为其对应的词典；新建时为 null。
  final NameDictionary? dictionary;

  const NameDictionarySheetAction(this.type, [this.dictionary]);
}

/// 显示移动端词典管理弹窗
///
/// 以底部弹窗列出当前类别的全部词典，支持选中、新建，
/// 以及自定义词典的编辑与删除；操作结果以 [NameDictionarySheetAction] 返回。
Future<NameDictionarySheetAction?> showNameDictionarySheet({
  required BuildContext context,
  required List<NameDictionary> dictionaries,
  required String selectedId,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return showModalBottomSheet<NameDictionarySheetAction>(
    context: context,
    backgroundColor: colorScheme.surface,
    // 允许弹窗超出默认高度上限，由内容自行约束，便于词典较多时完整展示
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _NameDictionarySheet(
      dictionaries: dictionaries,
      selectedId: selectedId,
    ),
  );
}

/// 词典管理弹窗内容
class _NameDictionarySheet extends StatelessWidget {
  /// 当前类别的词典列表
  final List<NameDictionary> dictionaries;

  /// 当前选中的词典 ID
  final String selectedId;

  /// 弹窗内容的最大高度占屏幕高度的比例
  static const double _maxHeightRatio = 0.7;

  const _NameDictionarySheet({
    required this.dictionaries,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      // 限制弹窗最大高度，词典较多时列表在内部滚动
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _maxHeightRatio,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部拖动提示条
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题行：标题 + 词典数量
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Icon(Icons.auto_stories_outlined, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '词典',
                    style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${dictionaries.length} 个',
                    style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            // 词典列表
            Flexible(
              child: dictionaries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '暂无词典',
                        style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: dictionaries.length,
                      itemBuilder: (context, index) => _buildTile(context, dictionaries[index]),
                    ),
            ),
            const Divider(height: 1),
            // 底部操作：新建词典
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context)
                      .pop(const NameDictionarySheetAction(NameDictionarySheetActionType.create)),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建词典'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建单个词典条目
  ///
  /// 点击整项即选中该词典；自定义词典在右侧提供编辑与删除按钮，
  /// 内置词典以「内置」标记说明其不可修改。
  Widget _buildTile(BuildContext context, NameDictionary dictionary) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool selected = dictionary.id == selectedId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? colorScheme.primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => Navigator.of(context).pop(
            NameDictionarySheetAction(NameDictionarySheetActionType.select, dictionary),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  dictionary.category == NameCategory.person
                      ? Icons.person_outline_rounded
                      : Icons.place_outlined,
                  size: 18,
                  color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    dictionary.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                // 内置词典不可修改，以文字标记加以说明
                if (dictionary.isBuiltin)
                  Text(
                    '内置',
                    style: context.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  )
                else ...[
                  _buildActionIcon(
                    context,
                    icon: Icons.edit_outlined,
                    tooltip: '编辑',
                    onTap: () => Navigator.of(context).pop(
                      NameDictionarySheetAction(NameDictionarySheetActionType.edit, dictionary),
                    ),
                  ),
                  _buildActionIcon(
                    context,
                    icon: Icons.delete_outline_rounded,
                    tooltip: '删除',
                    onTap: () => Navigator.of(context).pop(
                      NameDictionarySheetAction(NameDictionarySheetActionType.delete, dictionary),
                    ),
                  ),
                ],
                // 选中标记
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建条目右侧的小操作按钮
  Widget _buildActionIcon(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: colorScheme.onSurfaceVariant,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}
