import 'package:flutter/material.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/models/name_gen/name_gen_options.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dropdown.dart';

/// 生成参数面板
///
/// 随机取名弹窗顶部的参数区，以紧凑的横向排列展示可配置项，尽量把空间留给结果区。
/// 参数按当前类别展示：
/// - 人名：性别取向、名字字数（选项随词典类型变化）、自定义姓氏
/// - 地名：主体词字数（选项随词典类型变化）、自定义后缀
/// - 通用：每次生成数量
class NameOptionsPanel extends StatelessWidget {
  /// 当前类别
  final NameCategory category;

  /// 当前选中的词典（用于判断名字用字是否为逐字池）
  final NameDictionary? dictionary;

  /// 当前生成参数
  final NameGenOptions options;

  /// 自定义姓氏输入控制器
  final TextEditingController surnameController;

  /// 自定义后缀输入控制器
  final TextEditingController suffixController;

  /// 自定义姓氏输入框的焦点节点（与输入法光标修复包装器共用）
  final FocusNode surnameFocusNode;

  /// 自定义后缀输入框的焦点节点（与输入法光标修复包装器共用）
  final FocusNode suffixFocusNode;

  /// 参数变化回调
  final ValueChanged<NameGenOptions> onChanged;

  const NameOptionsPanel({
    super.key,
    required this.category,
    required this.dictionary,
    required this.options,
    required this.surnameController,
    required this.suffixController,
    required this.surnameFocusNode,
    required this.suffixFocusNode,
    required this.onChanged,
  });

  /// 人名的名字长度选项
  ///
  /// 中文人名由姓氏加一到两个字组成，故只提供一到二字。
  static const List<DropdownItem> _personLengthItems = [
    DropdownItem(displayText: '随机', value: '0'),
    DropdownItem(displayText: '1 字', value: '1'),
    DropdownItem(displayText: '2 字', value: '2'),
  ];

  /// 地名的主体词长度选项
  static const List<DropdownItem> _placeLengthItems = [
    DropdownItem(displayText: '随机', value: '0'),
    DropdownItem(displayText: '1 字', value: '1'),
    DropdownItem(displayText: '2 字', value: '2'),
    DropdownItem(displayText: '3 字', value: '3'),
  ];

  /// 整词池的长度选项
  ///
  /// 整词池的词条本身即完整的名字或地名，不存在按字数组合的概念，
  /// 因此只提供"随机"。
  static const List<DropdownItem> _wordLengthItems = [
    DropdownItem(displayText: '随机', value: '0'),
  ];

  /// 控件统一高度
  static const double _controlHeight = 36;

  /// 参数下拉框统一宽度
  static const double _dropdownWidth = 78;

  /// 参数输入框统一宽度
  static const double _fieldWidth = 100;

  /// 当前词典是否按逐字方式生成
  ///
  /// 由词典自身声明；未选择词典时按逐字处理，保留字数选项。
  bool get _usesCharPool => dictionary?.isCharBased ?? true;

  /// 当前词典对应的长度选项
  ///
  /// 逐字式按字数组合，整词式只能随机取整词。
  List<DropdownItem> get _lengthItems {
    if (!_usesCharPool) return _wordLengthItems;
    return category == NameCategory.person ? _personLengthItems : _placeLengthItems;
  }

  /// 当前长度参数的显示取值
  ///
  /// 词典切换后原有取值可能不在新选项中，此时回退为"随机"。
  String get _lengthValue {
    final value = category == NameCategory.person
        ? '${options.givenLength}'
        : '${options.stemLength}';
    return _lengthItems.any((item) => item.value == value) ? value : '0';
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (category == NameCategory.person) ...[
          _buildDropdownField(
            context,
            label: '性别',
            value: options.gender.id,
            items: PersonGender.values
                .map((g) => DropdownItem(displayText: g.label, value: g.id))
                .toList(),
            onChanged: (value) =>
                onChanged(options.copyWith(gender: PersonGender.fromId(value))),
          ),
          _buildDropdownField(
            context,
            label: '名长',
            value: _lengthValue,
            items: _lengthItems,
            onChanged: (value) =>
                onChanged(options.copyWith(givenLength: int.parse(value))),
          ),
          _buildTextFieldField(
            context,
            label: '姓氏',
            controller: surnameController,
            focusNode: surnameFocusNode,
            hintText: '随机',
            onChanged: (value) => onChanged(options.copyWith(customSurname: value)),
          ),
        ] else ...[
          _buildDropdownField(
            context,
            label: '主体字数',
            value: _lengthValue,
            items: _lengthItems,
            onChanged: (value) =>
                onChanged(options.copyWith(stemLength: int.parse(value))),
          ),
          _buildTextFieldField(
            context,
            label: '后缀',
            controller: suffixController,
            focusNode: suffixFocusNode,
            hintText: '随机',
            onChanged: (value) => onChanged(options.copyWith(customSuffix: value)),
          ),
        ],
        _buildDropdownField(
          context,
          label: '数量',
          value: '${options.batchCount}',
          items: NameGenOptions.batchCountOptions
              .map((count) => DropdownItem(displayText: '$count', value: '$count'))
              .toList(),
          onChanged: (value) =>
              onChanged(options.copyWith(batchCount: int.parse(value))),
        ),
      ],
    );
  }

  /// 构建带前置标签的下拉参数
  Widget _buildDropdownField(
    BuildContext context, {
    required String label,
    required String value,
    required List<DropdownItem> items,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildLabel(context, label),
        const SizedBox(width: 6),
        CustomDropdown(
          width: _dropdownWidth,
          height: _controlHeight,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// 构建带前置标签的文本输入参数
  Widget _buildTextFieldField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildLabel(context, label),
        const SizedBox(width: 6),
        // 输入框自身撑满指定尺寸，样式与下拉框保持一致，文字垂直居中
        SizedBox(
          width: _fieldWidth,
          height: _controlHeight-4,
          child: ImeCursorFixerWrapper(
            controller: controller,
            focusNode: focusNode,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: context.bodyMedium,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: context.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建参数标签文字
  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text,
      style: context.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
