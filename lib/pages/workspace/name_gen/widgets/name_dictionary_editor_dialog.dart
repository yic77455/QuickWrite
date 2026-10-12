import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_dropdown.dart';

/// 显示词典编辑对话框
///
/// [dictionary] 为空表示新建词典，否则表示编辑该词典；
/// [initialCategory] 指定新建词典的默认类别。
/// 返回编辑后的词典对象；用户取消时返回 null。
Future<NameDictionary?> showNameDictionaryEditorDialog({
  required BuildContext context,
  NameDictionary? dictionary,
  NameCategory initialCategory = NameCategory.person,
}) {
  final isEditing = dictionary != null;
  return showDialogBase<NameDictionary>(
    context: context,
    title: isEditing ? '编辑词典' : '新建词典',
    width: 520,
    height: 560,
    content: _NameDictionaryEditorContent(
      dictionary: dictionary,
      initialCategory: initialCategory,
    ),
  );
}

/// 词典编辑对话框内容
///
/// 支持设置词典名称、类别（新建时可选），以及各分组的词条；
/// 人物名字典额外支持"名在前"顺序开关。
class _NameDictionaryEditorContent extends StatefulWidget {
  final NameDictionary? dictionary;
  final NameCategory initialCategory;

  const _NameDictionaryEditorContent({
    this.dictionary,
    required this.initialCategory,
  });

  @override
  State<_NameDictionaryEditorContent> createState() => _NameDictionaryEditorContentState();
}

class _NameDictionaryEditorContentState extends State<_NameDictionaryEditorContent> {
  /// 词条输入框高度
  static const double _poolFieldHeight = 96;

  late final TextEditingController _nameController;
  late NameCategory _category;
  late bool _givenFirst;
  late final Map<String, TextEditingController> _poolControllers;

  @override
  void initState() {
    super.initState();
    final dictionary = widget.dictionary;
    _nameController = TextEditingController(text: dictionary?.name ?? '');
    _category = dictionary?.category ?? widget.initialCategory;
    _givenFirst = dictionary?.givenFirst ?? false;
    _poolControllers = {
      for (final key in NamePoolKeys.keysOf(_category))
        key: TextEditingController(
          text: (dictionary?.pool(key) ?? const []).join(' '),
        ),
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _poolControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 切换类别
  ///
  /// 切换后需要重建对应类别的词条输入框，仅保留当前类别相关的各分组。
  void _onCategoryChanged(NameCategory category) {
    if (category == _category) return;
    setState(() {
      for (final controller in _poolControllers.values) {
        controller.dispose();
      }
      _poolControllers
        ..clear()
        ..addEntries(
          NamePoolKeys.keysOf(category).map((key) => MapEntry(key, TextEditingController())),
        );
      _category = category;
      _givenFirst = false;
    });
  }

  /// 解析词条输入
  ///
  /// 支持以空格、逗号、顿号、换行分隔，自动去空与去重。
  List<String> _parsePool(String raw) {
    final tokens = raw.split(RegExp(r'[\s,，、]+'));
    final result = <String>[];
    for (final token in tokens) {
      final value = token.trim();
      if (value.isNotEmpty && !result.contains(value)) {
        result.add(value);
      }
    }
    return result;
  }

  /// 保存词典
  void _handleSave() {
    final name = _nameController.text.trim();
    final pools = <String, List<String>>{};
    for (final entry in _poolControllers.entries) {
      pools[entry.key] = _parsePool(entry.value.text);
    }

    final dictionary = NameDictionary(
      id: widget.dictionary?.id ?? const Uuid().v4(),
      name: name.isEmpty ? _category.label : name,
      category: _category,
      isBuiltin: widget.dictionary?.isBuiltin ?? false,
      // 依据词条内容判定生成方式并写入词典，避免运行时再推断
      isCharBased: NameDictionary.inferCharBased(_category, pools),
      givenFirst: _category == NameCategory.person && _givenFirst,
      pools: pools,
    );
    Navigator.of(context).pop(dictionary);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.dictionary != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 词典名称
                  _buildFieldLabel(context, '词典名称'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    style: context.bodyMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '请输入词典名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 类别选择（编辑时不可修改，避免词条分组错位）
                  if (!isEditing) ...[
                    _buildFieldLabel(context, '类别'),
                    const SizedBox(height: 6),
                    CustomDropdown(
                      width: double.infinity,
                      value: _category.id,
                      items: NameCategory.values
                          .map((c) => DropdownItem(displayText: c.label, value: c.id))
                          .toList(),
                      onChanged: (value) => _onCategoryChanged(NameCategory.fromId(value)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // 名在前顺序（仅人物名）
                  if (_category == NameCategory.person) ...[
                    Row(
                      children: [
                        Text('名字在前（西式顺序）', style: context.bodyMedium),
                        const Spacer(),
                        Switch(
                          value: _givenFirst,
                          onChanged: (value) => setState(() => _givenFirst = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  // 各分组词条
                  for (final key in NamePoolKeys.keysOf(_category)) ...[
                    _buildFieldLabel(
                      context,
                      '${NamePoolKeys.labelOf(_category, key)}（以空格或逗号分隔）',
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: _poolFieldHeight,
                      child: TextField(
                        controller: _poolControllers[key],
                        style: context.bodyMedium,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '多个词条以空格或逗号分隔',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
          // 底部按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _handleSave,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                ),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建字段标签
  Widget _buildFieldLabel(BuildContext context, String text) {
    return Text(
      text,
      style: context.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
