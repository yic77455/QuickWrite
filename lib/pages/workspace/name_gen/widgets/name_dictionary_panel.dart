import 'package:flutter/material.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 词典面板
///
/// 随机取名弹窗左侧的词典列表，展示当前类别的全部词典，
/// 支持选中与新建；编辑、删除仅对用户自定义词典开放，内置词典不可修改。
class NameDictionaryPanel extends StatelessWidget {
  /// 当前类别的词典列表
  final List<NameDictionary> dictionaries;

  /// 当前选中的词典 ID
  final String selectedId;

  /// 选中词典回调
  final ValueChanged<String> onSelected;

  /// 编辑词典回调
  final ValueChanged<NameDictionary> onEdit;

  /// 删除词典回调
  final ValueChanged<NameDictionary> onDelete;

  /// 新建词典回调
  final VoidCallback onCreate;

  const NameDictionaryPanel({
    super.key,
    required this.dictionaries,
    required this.selectedId,
    required this.onSelected,
    required this.onEdit,
    required this.onDelete,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行：标题 + 词典数量
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Icon(Icons.auto_stories_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '词典',
                style: context.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${dictionaries.length}',
                style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // 词典列表
        Expanded(
          child: dictionaries.isEmpty
              ? Center(
                  child: Text(
                    '暂无词典',
                    style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: dictionaries.length,
                  itemBuilder: (context, index) {
                    final dictionary = dictionaries[index];
                    return _DictionaryTile(
                      dictionary: dictionary,
                      selected: dictionary.id == selectedId,
                      onTap: () => onSelected(dictionary.id),
                      onEdit: () => onEdit(dictionary),
                      onDelete: () => onDelete(dictionary),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        // 底部操作：新建词典
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('新建词典'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 词典列表项
///
/// 选中时使用主色底强调；自定义词典在鼠标悬浮时显示编辑与删除按钮，
/// 内置词典不提供这两个操作。
class _DictionaryTile extends StatefulWidget {
  final NameDictionary dictionary;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DictionaryTile({
    required this.dictionary,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DictionaryTile> createState() => _DictionaryTileState();
}

class _DictionaryTileState extends State<_DictionaryTile> {
  /// 鼠标是否悬浮在列表项上
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dictionary = widget.dictionary;
    final selected = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : _hovered
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    dictionary.category == NameCategory.person
                        ? Icons.person_outline_rounded
                        : Icons.place_outlined,
                    size: 16,
                    color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dictionary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  // 自定义词典悬浮时显示编辑/删除按钮
                  if (_hovered && !dictionary.isBuiltin) ...[
                    _buildActionIcon(
                      icon: Icons.edit_outlined,
                      tooltip: '编辑',
                      onTap: widget.onEdit,
                    ),
                    _buildActionIcon(
                      icon: Icons.delete_outline_rounded,
                      tooltip: '删除',
                      onTap: widget.onDelete,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建列表项右侧的小操作按钮
  Widget _buildActionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: InkResponse(
        onTap: onTap,
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
