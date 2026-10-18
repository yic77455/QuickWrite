import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/models/name_gen/name_gen_options.dart';
import 'package:quick_write/core/services/cache_services/name_gen_cache_service.dart';
import 'package:quick_write/core/services/name_gen/name_generator.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/workspace/name_gen/widgets/name_dictionary_editor_dialog.dart';
import 'package:quick_write/pages/workspace/name_gen/widgets/name_dictionary_sheet.dart';
import 'package:quick_write/pages/workspace/name_gen/widgets/name_result_panel.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 结果标签之间的间距
const double _chipGap = 8;

/// 结果标签的高度
const double _chipHeight = 40;

/// 结果标签的左右内边距
const double _chipHorizontalPadding = 8;

/// 结果标签单个项的最小容字数量（以全角字宽计）
const int _minCharsInChip = 4;

/// 结果标签单个项的最大容字数量（以全角字宽计）
const int _maxCharsInChip = 7;

/// 移动端每次生成数量的默认值
const int _mobileDefaultBatchCount = 20;

/// 显示移动端随机取名弹窗
///
/// 以卡片式弹窗承载随机取名功能：弹窗内自上而下为类别切换、词典入口、
/// 生成参数、结果区与生成按钮，四周保留留白。词典的选中、新建、
/// 编辑与删除通过底部弹窗完成。
Future<void> showMobileNameGeneratorDialog({required BuildContext context}) {
  return showDialogBase(
    context: context,
    title: '随机取名',
    width: 420,
    height: 620,
    content: const _MobileNameGeneratorDialog(),
  );
}

/// 移动端随机取名弹窗内容
class _MobileNameGeneratorDialog extends StatefulWidget {
  const _MobileNameGeneratorDialog();

  @override
  State<_MobileNameGeneratorDialog> createState() => _MobileNameGeneratorDialogState();
}

class _MobileNameGeneratorDialogState extends State<_MobileNameGeneratorDialog> {
  /// 内容区左右留白
  static const double _horizontalPadding = 20;

  /// 参数控件高度
  static const double _controlHeight = 36;

  /// 参数项左侧标签宽度，保证同一行两个控件的起始位置对齐
  static const double _labelWidth = 50;

  /// 标签与控件之间的间距
  static const double _labelGap = 6;

  /// 同一行两个参数项之间的间距
  static const double _itemGap = 16;

  /// 缓存服务
  final NameGenCacheService _cache = NameGenCacheService.instance;

  /// 随机数发生器
  final Random _random = Random();

  /// 自定义姓氏输入控制器
  final TextEditingController _surnameController = TextEditingController();

  /// 自定义后缀输入控制器
  final TextEditingController _suffixController = TextEditingController();

  /// 当前类别
  NameCategory _category = NameCategory.person;

  /// 当前生成参数
  NameGenOptions _options = const NameGenOptions();

  /// 各类别的词典列表
  final Map<NameCategory, List<NameDictionary>> _dictionaries = {};

  /// 各类别选中的词典 ID
  final Map<NameCategory, String> _selectedIds = {};

  /// 各类别的生成历史
  final Map<NameCategory, List<String>> _history = {};

  /// 本次生成结果
  List<String> _results = const [];

  /// 结果区当前视图
  NameResultTab _resultTab = NameResultTab.results;

  @override
  void initState() {
    super.initState();
    // 尚未保存过参数时采用移动端默认生成数量
    _options = _normalizeOptions(
      _cache.getSavedOptions() ?? const NameGenOptions(batchCount: _mobileDefaultBatchCount),
    );
    _surnameController.text = _options.customSurname;
    _suffixController.text = _options.customSuffix;
    _reloadDictionaries();
    _reloadHistory();
    // 打开弹窗时立即生成一次结果
    _results = _generateNames();
  }

  @override
  void dispose() {
    _surnameController.dispose();
    _suffixController.dispose();
    super.dispose();
  }

  /// 规范化历史缓存中的生成参数
  ///
  /// 生成数量取值不在当前候选范围内时回退为默认值。
  NameGenOptions _normalizeOptions(NameGenOptions options) {
    if (NameGenOptions.batchCountOptions.contains(options.batchCount)) {
      return options;
    }
    return options.copyWith(batchCount: _mobileDefaultBatchCount);
  }

  // ================= 数据读取 =================

  /// 重新加载各类别的词典列表与选中项
  void _reloadDictionaries() {
    for (final category in NameCategory.values) {
      _dictionaries[category] = _cache.getDictionaries(category);
      _selectedIds[category] = _cache.getSelectedDictionaryId(category);
    }
  }

  /// 重新加载各类别的生成历史
  void _reloadHistory() {
    for (final category in NameCategory.values) {
      _history[category] = _cache.getHistory(category);
    }
  }

  /// 获取当前类别选中的词典
  NameDictionary? get _currentDictionary {
    final list = _dictionaries[_category] ?? const [];
    final id = _selectedIds[_category];
    final index = list.indexWhere((d) => d.id == id);
    return index >= 0 ? list[index] : null;
  }

  // ================= 生成与结果操作 =================

  /// 依据当前词典与参数生成一批名字
  ///
  /// 仅供生成使用，不写入历史；词典不存在或词条不足时返回空列表。
  List<String> _generateNames() {
    final dictionary = _currentDictionary;
    if (dictionary == null) return const [];

    return NameGenerator.generateBatch(
      dictionary,
      options: _options,
      count: _options.batchCount,
      random: _random,
    );
  }

  /// 将当前结果归档到历史
  ///
  /// 当前结果被新结果覆盖时调用，使其作为被覆盖的旧结果保留在历史中。
  void _archiveCurrentResults() {
    if (_results.isEmpty) return;
    _cache.addHistory(_category, _results);
    _history[_category] = _cache.getHistory(_category);
  }

  /// 点击生成按钮
  ///
  /// 批量生成名字并切换到结果视图，保持弹窗位置不变；无法生成时提示用户。
  void _generate() {
    if (_currentDictionary == null) {
      SnackBarService.show(context, '请先选择或新建一个词典');
      return;
    }
    final names = _generateNames();
    if (names.isEmpty) {
      SnackBarService.show(context, '词典词条不足，无法生成，请补充词条');
      return;
    }
    setState(() {
      _archiveCurrentResults();
      _results = names;
      _resultTab = NameResultTab.results;
    });
  }

  /// 复制名字到剪贴板
  Future<void> _copy(String name) async {
    await Clipboard.setData(ClipboardData(text: name));
    if (!mounted) return;
    SnackBarService.show(context, '已复制：$name');
  }

  /// 清空当前视图
  Future<void> _clearCurrentView() async {
    switch (_resultTab) {
      case NameResultTab.results:
        setState(() => _results = const []);
        break;
      case NameResultTab.history:
        await _cache.clearHistory(_category);
        if (!mounted) return;
        setState(_reloadHistory);
        break;
    }
  }

  // ================= 词典管理 =================

  /// 切换类别
  ///
  /// 切换后立即按新类别的词典生成一次结果。
  void _switchCategory(NameCategory category) {
    if (category == _category) return;
    setState(() {
      // 先把旧类别的当前结果归档，再切换类别生成新结果
      _archiveCurrentResults();
      _category = category;
      _resultTab = NameResultTab.results;
      _results = _generateNames();
    });
  }

  /// 选中词典
  ///
  /// 切换后立即按新词典生成一次结果。
  void _selectDictionary(String id) {
    _cache.saveSelectedDictionaryId(_category, id);
    setState(() {
      _archiveCurrentResults();
      _selectedIds[_category] = id;
      _resultTab = NameResultTab.results;
      _results = _generateNames();
    });
  }

  /// 打开词典管理弹窗并处理其中选择的操作
  Future<void> _openDictionarySheet() async {
    final action = await showNameDictionarySheet(
      context: context,
      dictionaries: _dictionaries[_category] ?? const [],
      selectedId: _selectedIds[_category] ?? '',
    );
    if (action == null || !mounted) return;

    switch (action.type) {
      case NameDictionarySheetActionType.select:
        _selectDictionary(action.dictionary!.id);
        break;
      case NameDictionarySheetActionType.edit:
        await _editDictionary(action.dictionary!);
        break;
      case NameDictionarySheetActionType.delete:
        await _deleteDictionary(action.dictionary!);
        break;
      case NameDictionarySheetActionType.create:
        await _createDictionary();
        break;
    }
  }

  /// 新建词典
  Future<void> _createDictionary() async {
    final result = await showNameDictionaryEditorDialog(
      context: context,
      initialCategory: _category,
    );
    if (result == null) return;
    await _cache.saveDictionary(result);
    if (!mounted) return;
    setState(() {
      _archiveCurrentResults();
      _reloadDictionaries();
      _selectedIds[result.category] = result.id;
      _category = result.category;
      _resultTab = NameResultTab.results;
      _results = _generateNames();
    });
  }

  /// 编辑词典
  Future<void> _editDictionary(NameDictionary dictionary) async {
    final result = await showNameDictionaryEditorDialog(
      context: context,
      dictionary: dictionary,
    );
    if (result == null) return;
    await _cache.saveDictionary(result);
    if (!mounted) return;
    setState(_reloadDictionaries);
  }

  /// 删除词典
  Future<void> _deleteDictionary(NameDictionary dictionary) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除词典',
      description: '确定要删除词典「${dictionary.name}」吗？',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
    );
    if (!confirmed) return;
    await _cache.deleteDictionary(dictionary.id);
    if (!mounted) return;
    setState(_reloadDictionaries);
  }

  // ================= 参数变化 =================

  /// 参数变化处理
  void _onOptionsChanged(NameGenOptions options) {
    _cache.saveOptions(options);
    setState(() => _options = options);
  }

  // ================= 构建 =================

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 主内容区可滚动；生成按钮固定于底部，便于随时触发生成
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(_horizontalPadding, 12, _horizontalPadding, 4),
            children: [
              _buildCategorySelector(),
              const SizedBox(height: 16),
              _buildDictionarySelector(),
              const SizedBox(height: 16),
              ..._buildOptions(),
              const SizedBox(height: 20),
              _buildResultsSection(),
            ],
          ),
        ),
        _buildGenerateBar(),
      ],
    );
  }

  /// 构建类别切换栏
  Widget _buildCategorySelector() {
    return SegmentedControl(
      labels: NameCategory.values.map((c) => c.label).toList(),
      selectedIndex: NameCategory.values.indexOf(_category),
      height: 40,
      onChanged: (index) => _switchCategory(NameCategory.values[index]),
    );
  }

  /// 构建词典选择入口
  ///
  /// 展示当前词典名称与词典数量，点击打开词典管理弹窗。
  Widget _buildDictionarySelector() {
    final colorScheme = Theme.of(context).colorScheme;
    final dictionary = _currentDictionary;
    final count = _dictionaries[_category]?.length ?? 0;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _openDictionarySheet,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.auto_stories_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '当前词典',
                      style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dictionary?.name ?? '暂无词典',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$count 个',
                style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建生成参数
  ///
  /// 参数按每行两项紧凑排布：人名提供性别、名长、姓氏与数量，
  /// 地名提供主体字数、后缀与数量。
  List<Widget> _buildOptions() {
    final person = _category == NameCategory.person;

    if (person) {
      return [
        _buildOptionRow(
          left: _buildOptionItem(label: '性别', control: _buildGenderDropdown()),
          right: _buildOptionItem(label: '名长', control: _buildLengthDropdown()),
        ),
        const SizedBox(height: 12),
        _buildOptionRow(
          left: _buildOptionItem(
            label: '姓氏',
            control: _buildTextControl(
              controller: _surnameController,
              hintText: '随机',
              onChanged: (value) => _onOptionsChanged(_options.copyWith(customSurname: value)),
            ),
          ),
          right: _buildOptionItem(label: '数量', control: _buildCountDropdown()),
        ),
      ];
    }

    return [
      _buildOptionRow(
        left: _buildOptionItem(label: '主体字数', control: _buildLengthDropdown()),
        right: _buildOptionItem(
          label: '后缀',
          control: _buildTextControl(
            controller: _suffixController,
            hintText: '随机',
            onChanged: (value) => _onOptionsChanged(_options.copyWith(customSuffix: value)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _buildOptionRow(
        left: _buildOptionItem(label: '数量', control: _buildCountDropdown()),
        right: const SizedBox.shrink(),
      ),
    ];
  }

  /// 构建一行两个参数项
  Widget _buildOptionRow({required Widget left, required Widget right}) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: _itemGap),
        Expanded(child: right),
      ],
    );
  }

  /// 构建单个参数项（左侧标签 + 右侧控件）
  Widget _buildOptionItem({required String label, required Widget control}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: _labelGap),
        Expanded(child: control),
      ],
    );
  }

  /// 构建性别下拉框
  Widget _buildGenderDropdown() {
    return CustomDropdown(
      width: double.infinity,
      height: _controlHeight,
      value: _options.gender.id,
      items: PersonGender.values
          .map((g) => DropdownItem(displayText: g.label, value: g.id))
          .toList(),
      onChanged: (value) => _onOptionsChanged(_options.copyWith(gender: PersonGender.fromId(value))),
    );
  }

  /// 构建名字字数下拉框
  ///
  /// 逐字词典按字数组合，整词词典只能随机取整词。
  Widget _buildLengthDropdown() {
    final person = _category == NameCategory.person;
    final usesCharPool = _currentDictionary?.isCharBased ?? true;

    final items = usesCharPool
        ? (person ? _personLengthItems : _placeLengthItems)
        : _wordLengthItems;
    final value = person ? '${_options.givenLength}' : '${_options.stemLength}';
    // 词典切换后原有取值可能不在新选项中，此时回退为"随机"
    final resolved = items.any((item) => item.value == value) ? value : '0';

    return CustomDropdown(
      width: double.infinity,
      height: _controlHeight,
      value: resolved,
      items: items,
      onChanged: (value) => _onOptionsChanged(
        person
            ? _options.copyWith(givenLength: int.parse(value))
            : _options.copyWith(stemLength: int.parse(value)),
      ),
    );
  }

  /// 构建生成数量下拉框
  Widget _buildCountDropdown() {
    return CustomDropdown(
      width: double.infinity,
      height: _controlHeight,
      value: '${_options.batchCount}',
      items: NameGenOptions.batchCountOptions
          .map((count) => DropdownItem(displayText: '$count', value: '$count'))
          .toList(),
      onChanged: (value) => _onOptionsChanged(_options.copyWith(batchCount: int.parse(value))),
    );
  }

  /// 构建文本参数输入框
  ///
  /// 输入框与下拉框保持同样高度并填满可用宽度，文字垂直居中，
  /// 与左侧标签在同一行内对齐。
  Widget _buildTextControl({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _controlHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        // 输入框填满固定高度的容器，文字在其中垂直居中
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.center,
        style: context.bodySmall,
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
    );
  }

  /// 构建结果区
  ///
  /// 顶部为「生成结果 / 历史」切换与清空入口，下方以标签流展示名字，
  /// 点击任意名字即可复制。
  Widget _buildResultsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final names = _namesOfCurrentTab();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedControl(
                labels: NameResultTab.values.map((t) => t.label).toList(),
                selectedIndex: NameResultTab.values.indexOf(_resultTab),
                height: 40,
                onChanged: (index) => setState(() => _resultTab = NameResultTab.values[index]),
              ),
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${names.length}',
                style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              IconButton(
                onPressed: _clearCurrentView,
                icon: const Icon(Icons.delete_sweep_outlined),
                iconSize: 20,
                tooltip: '清空${_resultTab.label}',
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (names.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                _emptyHintOfCurrentTab(),
                textAlign: TextAlign.center,
                style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          // 结果标签按整行铺满的方式排布，左右两侧对齐
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _resolveChipColumns(context, constraints.maxWidth);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: _chipGap,
                  mainAxisSpacing: _chipGap,
                  mainAxisExtent: _chipHeight,
                ),
                itemCount: names.length,
                itemBuilder: (context, index) => _NameChip(
                  name: names[index],
                  onTap: () => _copy(names[index]),
                ),
              );
            },
          ),
      ],
    );
  }

  /// 计算结果标签的每行数量
  ///
  /// 以「[_minCharsInChip] 个字宽」为单项最小宽度、「[_maxCharsInChip] 个字宽」为最大宽度，
  /// 选出既不低于最小宽度、又不高于最大宽度的最大列数，使标签铺满整行且宽度舒适；
  /// 可用宽度过窄无法同时满足上下限时退回单列。
  int _resolveChipColumns(BuildContext context, double availableWidth) {
    // 以全角字符实测宽度作为字宽基准
    final charWidth = _measureTextWidth('国', context.bodyMedium);
    final minChipWidth = charWidth * _minCharsInChip + _chipHorizontalPadding * 2;
    final maxChipWidth = charWidth * _maxCharsInChip + _chipHorizontalPadding * 2;

    int columns = 1;
    for (int count = 1; count <= 50; count++) {
      final itemWidth = (availableWidth - (count - 1) * _chipGap) / count;
      // 再增加列数会更窄，低于最小宽度，结束查找
      if (itemWidth < minChipWidth) break;
      // 宽度落在上下限区间内的最大列数
      if (itemWidth <= maxChipWidth) columns = count;
    }
    return columns;
  }

  /// 测量文本在指定样式下的宽度
  double _measureTextWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// 构建底部生成按钮
  Widget _buildGenerateBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_horizontalPadding, 8, _horizontalPadding, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.casino_rounded, size: 20),
          label: const Text('生成'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ),
    );
  }

  /// 获取当前视图展示的名字列表
  List<String> _namesOfCurrentTab() {
    switch (_resultTab) {
      case NameResultTab.results:
        return _results;
      case NameResultTab.history:
        return _history[_category] ?? const [];
    }
  }

  /// 获取当前视图的空状态提示
  String _emptyHintOfCurrentTab() {
    switch (_resultTab) {
      case NameResultTab.results:
        return '点击"生成"按钮开始取名，点击名字即可复制';
      case NameResultTab.history:
        return '暂无生成历史';
    }
  }

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
}

/// 单个名字标签
///
/// 宽度由所在网格单元决定并铺满该单元，文字居中，使整行标签左右对齐；
/// 点击即复制名字到剪贴板。
class _NameChip extends StatelessWidget {
  /// 名字文本
  final String name;

  /// 点击回调
  final VoidCallback onTap;

  const _NameChip({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _chipHorizontalPadding),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.bodyMedium?.copyWith(color: colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
