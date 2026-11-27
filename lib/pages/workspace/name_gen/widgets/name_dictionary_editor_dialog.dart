import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_dropdown.dart';
import 'package:quick_write/shared/widgets/qw_switch.dart';
import 'package:quick_write/shared/widgets/qw_text_field.dart';

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
    height: 650,
    content: _NameDictionaryEditorContent(
      dictionary: dictionary,
      initialCategory: initialCategory,
    ),
  );
}

/// 词典编辑对话框内容
///
/// 支持设置词典名称、类别（新建时可选），以及各分组的词条；
/// 人物名字典额外支持"名在前"顺序开关，其他类别支持自定义词组池数量。
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
  static const double _poolFieldHeight = 88;

  /// 词组池数量下拉框宽度
  static const double _partCountDropdownWidth = 96;

  /// 内容区左右留白
  static const double _contentHorizontalPadding = 24;

  late final TextEditingController _nameController;

  /// 词典名称输入框焦点节点（与输入法光标修复包装器共用）
  final FocusNode _nameFocusNode = FocusNode();

  late NameCategory _category;
  late bool _givenFirst;
  late int _partCount;
  late final Map<String, _PoolInput> _poolInputs;

  @override
  void initState() {
    super.initState();
    final dictionary = widget.dictionary;
    _nameController = TextEditingController(text: dictionary?.name ?? '');
    _category = dictionary?.category ?? widget.initialCategory;
    _givenFirst = dictionary?.givenFirst ?? false;
    _partCount = _resolvePartCount(dictionary);
    _poolInputs = _createPoolInputs(dictionary);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    for (final input in _poolInputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  /// 解析其他类别的词组池数量
  ///
  /// 编辑词典时沿用其原有数量；新建词典或数量超出可选范围时使用默认值。
  int _resolvePartCount(NameDictionary? dictionary) {
    if (dictionary == null || dictionary.category != NameCategory.other) {
      return NamePoolKeys.defaultPartCount;
    }
    return dictionary.partCount
        .clamp(NamePoolKeys.minPartCount, NamePoolKeys.maxPartCount)
        .toInt();
  }

  /// 按当前类别与词组池数量创建词条输入框
  ///
  /// [dictionary] 非空时以其词条作为输入框的初始内容。
  Map<String, _PoolInput> _createPoolInputs(NameDictionary? dictionary) {
    return {
      for (final key in NamePoolKeys.keysOf(_category, partCount: _partCount))
        key: _PoolInput(
          text: (dictionary?.pool(key) ?? const []).join(' '),
        ),
    };
  }

  /// 重建全部词条输入框
  ///
  /// 类别或词组池数量变化后，原有分组不再适用，需按新结构重新创建。
  void _rebuildPoolInputs() {
    for (final input in _poolInputs.values) {
      input.dispose();
    }
    _poolInputs
      ..clear()
      ..addAll(_createPoolInputs(null));
  }

  /// 切换类别
  ///
  /// 切换后各分组词条失去对应关系，重建输入框并重置类别专属设置。
  void _onCategoryChanged(NameCategory category) {
    if (category == _category) return;
    setState(() {
      _category = category;
      _givenFirst = false;
      _partCount = NamePoolKeys.defaultPartCount;
      _rebuildPoolInputs();
    });
  }

  /// 调整其他类别的词组池数量
  ///
  /// 保留序号仍在范围内的已有输入框及其内容，超出范围的部分随输入框销毁。
  void _onPartCountChanged(int count) {
    if (count == _partCount) return;
    setState(() {
      final reused = <String, _PoolInput>{};
      for (final key in NamePoolKeys.keysOf(NameCategory.other, partCount: count)) {
        reused[key] = _poolInputs[key] ?? _PoolInput();
      }
      for (final entry in _poolInputs.entries) {
        if (!reused.containsKey(entry.key)) {
          entry.value.dispose();
        }
      }
      _poolInputs
        ..clear()
        ..addAll(reused);
      _partCount = count;
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
    for (final entry in _poolInputs.entries) {
      pools[entry.key] = _parsePool(entry.value.controller.text);
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

  /// 退出输入框焦点。
  void _unfocus() => FocusScope.of(context).unfocus();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.dictionary != null;

    return Padding(
      // 仅保留上下留白，左右留白交由滚动视图与按钮行分别处理，
      // 使滚动条贴靠弹窗右缘显示
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              // 内容左右收窄，滚动条仍绘制在滚动视图边缘
              padding: const EdgeInsets.symmetric(horizontal: _contentHorizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 词典名称
                  _buildFieldLabel(context, '词典名称'),
                  const SizedBox(height: 8),
                  _buildNameField(context),
                  const SizedBox(height: 16),
                  // 类别选择（编辑时不可修改，避免词条分组错位）
                  if (!isEditing) ...[
                    _buildFieldLabel(context, '类别'),
                    const SizedBox(height: 8),
                    CustomDropdown(
                      width: double.infinity,
                      value: _category.id,
                      items: NameCategory.values
                          .map((c) => DropdownItem(displayText: c.label, value: c.id))
                          .toList(),
                      onChanged: (value) => _onCategoryChanged(NameCategory.fromId(value)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // 名在前顺序（仅人物名）
                  if (_category == NameCategory.person) ...[
                    _buildGivenFirstSwitch(context),
                    const SizedBox(height: 16),
                  ],
                  // 词组池数量（仅其他类别）
                  if (_category == NameCategory.other) ...[
                    _buildPoolCountRow(context),
                    const SizedBox(height: 16),
                  ],
                  // 各组词条
                  for (final key in NamePoolKeys.keysOf(_category, partCount: _partCount)) ...[
                    _buildFieldLabel(
                      context,
                      '${NamePoolKeys.labelOf(_category, key)}（以空格或逗号分隔）',
                    ),
                    const SizedBox(height: 8),
                    _buildPoolField(context, key),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          // 底部按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _contentHorizontalPadding,
              12,
              _contentHorizontalPadding,
              0,
            ),
            child: Row(
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
          ),
        ],
      ),
    );
  }

  /// 词典名称输入框
  Widget _buildNameField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ImeCursorFixerWrapper(
      controller: _nameController,
      focusNode: _nameFocusNode,
      child: QwTextField(
        controller: _nameController,
        focusNode: _nameFocusNode,
        onTapOutside: (_) => _unfocus(),
        style: context.bodyMedium,
        maxLines: 1,
        decoration: InputDecoration(
          hintText: '请输入词典名称',
          hintStyle: context.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          filled: true,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// 构建单个分组的词条输入框
  ///
  /// 多行输入，使用项目统一的输入法光标修复包装器。
  Widget _buildPoolField(BuildContext context, String key) {
    final colorScheme = Theme.of(context).colorScheme;
    final input = _poolInputs[key]!;

    return SizedBox(
      height: _poolFieldHeight,
      child: ImeCursorFixerWrapper(
        controller: input.controller,
        focusNode: input.focusNode,
        child: QwTextField(
          controller: input.controller,
          focusNode: input.focusNode,
          onTapOutside: (_) => _unfocus(),
          style: context.bodyMedium,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            hintText: '多个词条以空格或逗号分隔',
            hintStyle: context.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            filled: true,
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建"名字在前"开关行
  Widget _buildGivenFirstSwitch(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text('名字在前（西式顺序）', style: context.bodyMedium)),
          QwSwitch(
            value: _givenFirst,
            onChanged: (value) => setState(() => _givenFirst = value),
          ),
        ],
      ),
    );
  }

  /// 构建词组池数量选择行（仅其他类别）
  Widget _buildPoolCountRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('词组池数量', style: context.bodyMedium),
              const SizedBox(height: 2),
              Text(
                '按顺序从各池子中随机取词，拼接成一个名称',
                style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        CustomDropdown(
          width: _partCountDropdownWidth,
          value: '$_partCount',
          items: [
            for (int count = NamePoolKeys.minPartCount;
                count <= NamePoolKeys.maxPartCount;
                count++)
              DropdownItem(displayText: '$count 个', value: '$count'),
          ],
          onChanged: (value) => _onPartCountChanged(int.parse(value)),
        ),
      ],
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

/// 单个词条输入框的编辑状态
///
/// 将文本控制器与焦点节点成对管理，便于输入框重建时统一创建与释放。
class _PoolInput {
  final TextEditingController controller;
  final FocusNode focusNode;

  _PoolInput({String text = ''})
      : controller = TextEditingController(text: text),
        focusNode = FocusNode();

  /// 释放控制器与焦点节点
  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}
