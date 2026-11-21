import 'package:flutter/material.dart';
import 'package:quick_write/core/models/text_replacement_rule.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_switch.dart';

/// 显示正文自动替换规则弹窗
///
/// 弹窗内列出全部替换规则，支持新增、修改与删除，改动立即保存到设置
Future<void> showAutoReplaceRulesDialog({required BuildContext context}) {
  return showDialogBase<void>(
    context: context,
    title: '自动替换',
    subtitle: '输入原文本后自动替换为指定内容',
    titleIcon: Icons.repeat_rounded,
    width: 520,
    height: 620,
    content: const _AutoReplaceRulesContent(),
  );
}

/// 自动替换规则弹窗内容
class _AutoReplaceRulesContent extends StatefulWidget {
  const _AutoReplaceRulesContent();

  @override
  State<_AutoReplaceRulesContent> createState() => _AutoReplaceRulesContentState();
}

class _AutoReplaceRulesContentState extends State<_AutoReplaceRulesContent> {
  /// 内容区左右留白
  static const double _horizontalPadding = 20;

  /// 底部新增按钮高度
  static const double _addButtonHeight = 42;

  /// 当前编辑中的规则列表（与设置保持同步）
  late List<TextReplacementRule> _rules;

  /// 规则列表滚动控制器，滚动条据此跟随列表滚动
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _rules = List<TextReplacementRule>.of(SettingsService.instance.textReplacementRules);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 保存当前规则列表
  void _persist() {
    SettingsService.instance.updateTextReplacementRules(_rules);
  }

  /// 新增规则
  Future<void> _handleAdd() async {
    final rule = await showAutoReplaceRuleEditDialog(context: context);
    if (rule == null || !mounted) return;
    setState(() => _rules = [..._rules, rule]);
    _persist();
  }

  /// 修改指定位置的规则
  Future<void> _handleEdit(int index) async {
    final rule = await showAutoReplaceRuleEditDialog(
      context: context,
      rule: _rules[index],
    );
    if (rule == null || !mounted) return;
    setState(() {
      _rules = List<TextReplacementRule>.of(_rules)..[index] = rule;
    });
    _persist();
  }

  /// 删除指定位置的规则
  Future<void> _handleDelete(int index) async {
    final rule = _rules[index];
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除规则',
      description: '确定删除「${rule.trigger}」的替换规则吗？',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _rules = List<TextReplacementRule>.of(_rules)..removeAt(index);
    });
    _persist();
  }

  /// 切换指定规则的启用状态
  void _handleToggle(int index, bool enabled) {
    final oldRule = _rules[index];
    setState(() {
      _rules = List<TextReplacementRule>.of(_rules)
        ..[index] = TextReplacementRule(
          trigger: oldRule.trigger,
          replacement: oldRule.replacement,
          enabled: enabled,
        );
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Expanded(
            child: _rules.isEmpty
                ? _buildEmptyState(context)
                // 去除系统安全区内边距，避免滚动条被系统留白顶开
                : MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    removeLeft: true,
                    removeRight: true,
                    // 规则较多滚动时显示滚动条
                    child: Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                        itemCount: _rules.length,
                        itemBuilder: (context, index) => _buildRuleTile(context, index),
                      ),
                    ),
                  ),
          ),
          // 底部新增入口
          Padding(
            padding: const EdgeInsets.fromLTRB(_horizontalPadding, 12, _horizontalPadding, 0),
            child: SizedBox(
              width: double.infinity,
              height: _addButtonHeight,
              child: FilledButton.icon(
                onPressed: _handleAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新增规则'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建空列表提示
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.repeat_rounded,
            size: 40,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '还没有替换规则',
            style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '添加后，输入原文本会自动替换为指定内容',
            style: context.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单条规则条目
  ///
  /// 上行显示原文本，下行显示替换后的文本；
  /// 右侧提供启用开关、修改与删除按钮
  Widget _buildRuleTile(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final rule = _rules[index];
    final Color tileColor = Color.alphaBlend(
      colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      colorScheme.surface,
    );
    // 规则关闭时文字弱化显示
    final Color triggerColor = rule.enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    final Color contentColor = rule.enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.trigger,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyMedium?.copyWith(
                      color: triggerColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: contentColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          rule.replacement,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.bodySmall?.copyWith(color: contentColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            QwSwitch(
              value: rule.enabled,
              onChanged: (value) => _handleToggle(index, value),
            ),
            IconButton(
              onPressed: () => _handleEdit(index),
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: colorScheme.onSurfaceVariant,
              tooltip: '修改',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: () => _handleDelete(index),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: colorScheme.error,
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// 显示替换规则编辑弹窗
///
/// [rule] 为空表示新增规则，否则表示修改该规则；
/// 返回编辑后的规则，用户取消时返回 null。
Future<TextReplacementRule?> showAutoReplaceRuleEditDialog({
  required BuildContext context,
  TextReplacementRule? rule,
}) {
  return showDialogBase<TextReplacementRule>(
    context: context,
    title: rule == null ? '新增规则' : '修改规则',
    width: 420,
    height: 400,
    adaptiveHeight: true,
    content: _AutoReplaceRuleEditContent(rule: rule),
  );
}

/// 替换规则编辑弹窗内容
class _AutoReplaceRuleEditContent extends StatefulWidget {
  /// 待修改的规则，为 null 表示新增
  final TextReplacementRule? rule;

  const _AutoReplaceRuleEditContent({this.rule});

  @override
  State<_AutoReplaceRuleEditContent> createState() => _AutoReplaceRuleEditContentState();
}

class _AutoReplaceRuleEditContentState extends State<_AutoReplaceRuleEditContent> {
  /// 内容区左右留白
  static const double _horizontalPadding = 20;

  /// 原文本输入控制器
  late final TextEditingController _triggerController;

  /// 替换文本输入控制器
  late final TextEditingController _replacementController;

  /// 原文本输入框焦点节点
  final FocusNode _triggerFocusNode = FocusNode();

  /// 替换文本输入框焦点节点
  final FocusNode _replacementFocusNode = FocusNode();

  /// 校验错误提示
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _triggerController = TextEditingController(text: widget.rule?.trigger ?? '');
    _replacementController = TextEditingController(text: widget.rule?.replacement ?? '');
  }

  @override
  void dispose() {
    _triggerController.dispose();
    _replacementController.dispose();
    _triggerFocusNode.dispose();
    _replacementFocusNode.dispose();
    super.dispose();
  }

  /// 保存规则
  ///
  /// 原文本与替换文本均为必填，保存时保留用户输入的原始字符
  void _handleSave() {
    final String trigger = _triggerController.text;
    final String replacement = _replacementController.text;

    if (trigger.trim().isEmpty) {
      setState(() => _errorMessage = '请输入原文本');
      return;
    }
    if (replacement.trim().isEmpty) {
      setState(() => _errorMessage = '请输入替换文本');
      return;
    }

    Navigator.of(context).pop(TextReplacementRule(
      trigger: trigger,
      replacement: replacement,
      // 修改时保留原有的启用状态
      enabled: widget.rule?.enabled ?? true,
    ));
  }

  /// 退出输入框焦点
  void _unfocus() => FocusScope.of(context).unfocus();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_horizontalPadding, 16, _horizontalPadding, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(context, '原文本'),
          const SizedBox(height: 8),
          _buildTriggerField(context),
          const SizedBox(height: 16),
          _buildFieldLabel(context, '替换为'),
          const SizedBox(height: 8),
          _buildReplacementField(context),
          // 校验错误提示
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style: context.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
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
                style: FilledButton.styleFrom(backgroundColor: colorScheme.primary),
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

  /// 原文本输入框（单行）
  Widget _buildTriggerField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ImeCursorFixerWrapper(
      controller: _triggerController,
      focusNode: _triggerFocusNode,
      child: TextField(
        controller: _triggerController,
        focusNode: _triggerFocusNode,
        autofocus: true,
        onTapOutside: (_) => _unfocus(),
        style: context.bodyMedium,
        maxLines: 1,
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          if (_errorMessage != null) setState(() => _errorMessage = null);
        },
        decoration: _fieldDecoration(
          context,
          hintText: '输入需要被替换的文本',
          colorScheme: colorScheme,
        ),
      ),
    );
  }

  /// 替换文本输入框（单行）
  Widget _buildReplacementField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ImeCursorFixerWrapper(
      controller: _replacementController,
      focusNode: _replacementFocusNode,
      child: TextField(
        controller: _replacementController,
        focusNode: _replacementFocusNode,
        onTapOutside: (_) => _unfocus(),
        style: context.bodyMedium,
        maxLines: 1,
        onChanged: (_) {
          if (_errorMessage != null) setState(() => _errorMessage = null);
        },
        decoration: _fieldDecoration(
          context,
          hintText: '输入替换后的文本',
          colorScheme: colorScheme,
        ),
      ),
    );
  }

  /// 输入框统一样式
  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String hintText,
    required ColorScheme colorScheme,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: context.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      isDense: true,
      contentPadding: const EdgeInsets.all(12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }
}
