import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/models/name_gen/name_gen_options.dart';
import 'package:quick_write/core/services/cache_services/name_gen_cache_service.dart';
import 'package:quick_write/core/services/name_gen/name_generator.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_dropdown.dart';
import 'package:quick_write/shared/widgets/qw_snackbar.dart';
import 'package:quick_write/pages/workspace/name_gen/widgets/name_dictionary_editor_dialog.dart';
import 'package:quick_write/pages/workspace/name_gen/widgets/name_dictionary_panel.dart';
import 'package:quick_write/pages/workspace/name_gen/widgets/name_options_panel.dart';
import 'package:quick_write/pages/workspace/name_gen/widgets/name_result_panel.dart';

/// 显示随机取名对话框
Future<void> showNameGeneratorDialog({
  required BuildContext context,
}) {
  return showDialogBase(
    context: context,
    title: '随机取名',
    width: 880,
    height: 600,
    content: const _NameGeneratorDialog(),
  );
}

/// 随机取名对话框主体
///
/// 左侧为类别切换与词典管理，右侧为参数配置与生成结果。
class _NameGeneratorDialog extends StatefulWidget {
  const _NameGeneratorDialog();

  @override
  State<_NameGeneratorDialog> createState() => _NameGeneratorDialogState();
}

class _NameGeneratorDialogState extends State<_NameGeneratorDialog> {
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
    _options = _normalizeOptions(_cache.getOptions());
    _surnameController.text = _options.customSurname;
    _suffixController.text = _options.customSuffix;
    _reloadDictionaries();
    _reloadHistory();
    // 打开界面时立即生成一次结果
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
    return options.copyWith(batchCount: NameGenOptions.defaultBatchCount);
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
  /// 批量生成名字并切换到结果视图；无法生成时提示用户。
  void _generate() {
    if (_currentDictionary == null) {
      SnackBarService.show(context, '请先在左侧选择或新建一个词典');
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
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // 左侧：类别切换 + 词典管理
        SizedBox(
          width: 244,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                child: CustomDropdown(
                  width: double.infinity,
                  value: _category.id,
                  items: NameCategory.values
                      .map((c) => DropdownItem(displayText: c.label, value: c.id))
                      .toList(),
                  onChanged: (value) => _switchCategory(NameCategory.fromId(value)),
                ),
              ),
              Expanded(
                child: NameDictionaryPanel(
                  dictionaries: _dictionaries[_category] ?? const [],
                  selectedId: _selectedIds[_category] ?? '',
                  onSelected: _selectDictionary,
                  onEdit: _editDictionary,
                  onDelete: _deleteDictionary,
                  onCreate: _createDictionary,
                ),
              ),
            ],
          ),
        ),
        // 竖直分隔线
        Container(width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        // 右侧：参数配置 + 生成 + 结果
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 参数行 + 生成按钮
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: NameOptionsPanel(
                        category: _category,
                        dictionary: _currentDictionary,
                        options: _options,
                        surnameController: _surnameController,
                        suffixController: _suffixController,
                        onChanged: _onOptionsChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.casino_rounded, size: 18),
                      label: const Text('生成'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 结果区
                Expanded(
                  child: NameResultPanel(
                    tab: _resultTab,
                    onTabChanged: (tab) => setState(() => _resultTab = tab),
                    names: _namesOfCurrentTab(),
                    onCopy: _copy,
                    onClear: _clearCurrentView,
                    emptyHint: _emptyHintOfCurrentTab(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
}
