import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/models/custom_highlight.dart';
import 'package:quick_write/core/services/workspace/custom_highlight_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/custom_highlight_regex.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/dialogs/color_picker_dialog.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_snackbar.dart';
import 'package:quick_write/shared/widgets/qw_switch.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';
import 'package:quick_write/shared/widgets/toolbar_button.dart';
import 'right_sidebar_widgets.dart';
import 'package:quick_write/shared/widgets/qw_text_field.dart';

/// 显示自定义高亮设置对话框
///
/// 使用项目统一的 [showDialogBase] 弹窗外壳，固定尺寸避免内容变化导致弹窗大小跳动；
/// 移动端外壳会自动收窄宽度，桌面端与移动端共用同一份内容与交互。
Future<void> showCustomHighlightDialog({
  required BuildContext context,
  required CustomHighlightService service,
}) {
  return showDialogBase(
    context: context,
    title: '自定义高亮',
    subtitle: '支持常规匹配与正则表达式',
    titleAction: _buildRegexHelpButton(context),
    width: 520,
    height: 400,
    content: _CustomHighlightDialogContent(service: service),
  );
}

/// 标题栏帮助按钮：点击弹出正则用法说明
Widget _buildRegexHelpButton(BuildContext context) {
  return CursorTooltipTarget(
    tooltipContent: const Text('正则表达式用法'),
    child: IconButton(
        onPressed: () => _showRegexHelp(context),
        icon: const Icon(Icons.help_outline_rounded, size: 16),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        visualDensity: VisualDensity.compact,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
  );
}

/// 弹出正则用法说明（自适应高度，移动端内容可整体滚动）
Future<void> _showRegexHelp(BuildContext context) {
  return showDialogBase<void>(
    context: context,
    title: '正则表达式用法',
    subtitle: '每条高亮项可单独切换「常规 / 正则」模式',
    titleIcon: Icons.code_rounded,
    width: 500,
    height: 440,
    adaptiveHeight: true,
    content: const _RegexHelpContent(),
  );
}

/// 正则用法说明内容
class _RegexHelpContent extends StatelessWidget {
  const _RegexHelpContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '把某一项切成「正则」后，输入框里的内容按表达式匹配；'
            '语法与 Dart / JavaScript 正则一致，^、\$ 按行生效，区分大小写，. 不跨行。',
            style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          _helpExample(context, r'【[^】]*】', '高亮整段【…】（连同成对符号）'),
          _helpExample(context, r'(?<=【)[^】]*(?=】)', '只高亮【】内部的文字'),
          _helpExample(context, r'【([^】]*)】', '含捕获组时只高亮第 1 组，同样只着色内部'),
          _helpExample(context, r'《[^》]+》|（[^）]+）', '一次匹配书名号或圆括号里的内容'),
          _helpExample(context, r'^.*(忽然|骤然).*$', '高亮包含指定字句的整行'),
          const SizedBox(height: 6),
          SelectableText(
            '提示：非法表达式不会写入配置，云端同步来的坏配置也会被跳过而不崩溃；'
            '请尽量使用简单表达式、避免嵌套量词，单条最多着色 1000 处命中。',
            style: context.bodySmall?.copyWith(
              color: colorScheme.error.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// 帮助弹窗中的一条「表达式 + 说明」
Widget _helpExample(BuildContext context, String pattern, String description) {
  final colorScheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          pattern,
          style: TextStyle(
            fontSize: 12.5,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          description,
          style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

/// 自定义高亮设置对话框内容
///
/// 提供关键词与高亮颜色的增删改查界面，配置实时写入书籍根目录的 JSON 文件。
/// 通过 [CustomHighlightService] 与编辑器联动：修改后所有打开的编辑器会自动刷新高亮渲染。
class _CustomHighlightDialogContent extends StatefulWidget {
  /// 当前书籍的自定义高亮服务
  final CustomHighlightService service;

  const _CustomHighlightDialogContent({required this.service});

  @override
  State<_CustomHighlightDialogContent> createState() =>
      _CustomHighlightDialogContentState();
}

class _CustomHighlightDialogContentState
    extends State<_CustomHighlightDialogContent> {
  /// 新增关键词输入框控制器
  final TextEditingController _keywordInputController = TextEditingController();

  /// 新增关键词输入框焦点节点（与 ImeCursorFixerWrapper 共用）
  final FocusNode _keywordInputFocusNode = FocusNode();

  /// 新增关键词的当前颜色（HEX 字符串）
  String _newKeywordColorHex = '#FFB300';

  /// 新增项是否使用正则模式（默认常规，保持原有行为）
  bool _newKeywordIsRegex = false;

  /// 当前进入编辑模式的关键词索引（null 表示无编辑中项）
  int? _editingIndex;

  /// 编辑模式下的关键词输入框控制器
  final TextEditingController _editController = TextEditingController();

  /// 编辑模式下的关键词输入框焦点节点（与 ImeCursorFixerWrapper 共用）
  final FocusNode _editFocusNode = FocusNode();

  /// 关键词列表滚动控制器（用于添加关键词后滚动到新项）
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 监听 service 变化以刷新列表（外部修改时也能同步）
    widget.service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    _keywordInputController.dispose();
    _keywordInputFocusNode.dispose();
    _editController.dispose();
    _editFocusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  /// service 配置变化时刷新对话框
  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  /// 选择颜色（用于新增关键词）
  Future<void> _pickNewKeywordColor() async {
    await ColorPickerDialog.show(
      context: context,
      title: '选择高亮颜色',
      initialColorHex: _newKeywordColorHex,
      onColorSelected: (colorHex) {
        setState(() => _newKeywordColorHex = colorHex);
      },
    );
  }

  /// 选择指定关键词的颜色
  Future<void> _pickItemColor(int index, String currentHex) async {
    await ColorPickerDialog.show(
      context: context,
      title: '选择高亮颜色',
      initialColorHex: currentHex,
      onColorSelected: (colorHex) {
        widget.service.updateItemColor(index, colorHex);
      },
    );
  }

  /// 添加新关键词（或正则表达式）
  Future<void> _addKeyword() async {
    final keyword = _keywordInputController.text;
    if (keyword.trim().isEmpty) return;
    final result = await widget.service.addItem(
      keyword,
      _newKeywordColorHex,
      isRegex: _newKeywordIsRegex,
    );
    if (!mounted) return;
    if (result == CustomHighlightMutationResult.invalidRegex) {
      // 保留输入内容，方便用户就地修正表达式
      SnackBarService.show(context, '正则表达式无效，请检查语法');
      return;
    }
    _keywordInputController.clear();
    // 添加完成后将焦点归还输入框，便于连续添加
    _keywordInputFocusNode.requestFocus();
    // 滚动列表到底部，让新添加的关键词进入视口
    _scrollToBottom();
  }

  /// 滚动关键词列表到底部，确保最新添加的关键词可见
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listScrollController.hasClients) return;
      final maxScroll = _listScrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      _listScrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// 进入关键词编辑模式
  void _startEditing(int index, String currentKeyword) {
    setState(() {
      _editingIndex = index;
      _editController.text = currentKeyword;
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: currentKeyword.length,
      );
    });
    // 下一帧请求焦点，确保 TextField 已构建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocusNode.requestFocus();
    });
  }

  /// 提交关键词编辑
  Future<void> _commitEditing() async {
    final index = _editingIndex;
    if (index == null) return;
    final newKeyword = _editController.text;
    final result = await widget.service.updateItemKeyword(index, newKeyword);
    if (!mounted) return;
    if (result == CustomHighlightMutationResult.invalidRegex) {
      // 保持编辑态与输入内容，避免非法表达式被写入配置
      SnackBarService.show(context, '正则表达式无效，请检查语法');
      return;
    }
    setState(() => _editingIndex = null);
  }

  /// 切换某一项的匹配模式（常规 / 正则）
  ///
  /// [isRegex] 为切换后的目标模式，写入失败时提示正则语法有误。
  Future<void> _toggleItemRegex(int index, bool isRegex) async {
    final result = await widget.service.updateItemRegex(index, isRegex);
    if (!mounted) return;
    if (result == CustomHighlightMutationResult.invalidRegex) {
      SnackBarService.show(context, '当前内容不是合法正则，请先修改后再切换');
    }
  }

  /// 构建匹配模式图标开关
  ///
  /// 开启时图标点亮表示正则模式，关闭时表示常规匹配；云端同步来的
  /// 非法正则用警示图标与错误色标出（该项不会参与高亮）。
  Widget _buildModeToggle(
    CustomHighlightItem item,
    int index,
    ColorScheme colorScheme,
  ) {
    final bool invalid = item.isRegex && !CustomHighlightRegex.isValid(item.keyword);
    final String tooltip = invalid
        ? '正则表达式无效，该项不会高亮；点击可切回常规'
        : item.isRegex
            ? '正则模式，点击切换为常规'
            : '常规模式，点击切换为正则';

    return ToggleToolButton(
      icon: invalid ? Icons.warning_amber_rounded : Icons.code_rounded,
      tooltip: tooltip,
      isSelected: item.isRegex,
      size: 24,
      iconSize: 16,
      selectedColor: invalid ? colorScheme.error : null,
      unselectedColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      circular: true,
      onChanged: (value) => _toggleItemRegex(index, value),
    );
  }

  /// 取消关键词编辑
  void _cancelEditing() {
    if (mounted) setState(() => _editingIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 启用开关
          _buildEnableToggle(colorScheme),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          // 关键词列表标题
          _buildListHeader(colorScheme),
          const SizedBox(height: 8),
          // 关键词列表（占据剩余空间，空状态与有内容时弹窗大小一致）
          Expanded(child: _buildKeywordList(colorScheme)),
          const SizedBox(height: 16),
          // 新增关键词区域
          _buildAddKeywordRow(colorScheme),
        ],
      ),
    );
  }

  /// 构建启用开关
  Widget _buildEnableToggle(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          QwSwitch(
            value: widget.service.enabled,
            onChanged: (value) => widget.service.setEnabled(value),
          ),
          const SizedBox(width: 10),
          Text('启用自定义高亮', style: context.titleSmall),
          const Spacer(),
          // 状态描述
          Text(
            widget.service.enabled ? '已开启' : '已关闭',
            style: context.bodySmall?.copyWith(
              color: widget.service.enabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建关键词列表标题
  Widget _buildListHeader(ColorScheme colorScheme) {
    final count = widget.service.items.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.tag_rounded, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '高亮项',
            style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: context.bodySmall?.copyWith(color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建关键词列表
  ///
  /// 列表区域用 Expanded 撑满弹窗中部空间，保证空状态与有内容时弹窗尺寸一致。
  Widget _buildKeywordList(ColorScheme colorScheme) {
    final items = widget.service.items;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: items.isEmpty
          ? _buildEmptyHint(colorScheme)
          : ListView.separated(
              controller: _listScrollController,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SettingDivider(),
              itemBuilder: (context, index) {
                final item = items[index];
                // 当前项处于编辑模式时显示 TextField，否则显示文本
                final isEditing = _editingIndex == index;
                return _buildKeywordRow(item, index, isEditing, colorScheme);
              },
            ),
    );
  }

  /// 构建空列表提示
  Widget _buildEmptyHint(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 36,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          Text(
            '暂无高亮项',
            style: context.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '在下方输入框添加关键词，或切换为正则表达式',
            style: context.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单行关键词
  Widget _buildKeywordRow(
    CustomHighlightItem item,
    int index,
    bool isEditing,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 颜色指示器（点击切换颜色）
          GestureDetector(
            onTap: () => _pickItemColor(index, item.colorHex),
            child: CursorTooltipTarget(
              tooltipContent: const Text('点击修改颜色'),
              child: ColorIndicator(color: ColorUtils.parseHex(item.colorHex)),
            ),
          ),
          const SizedBox(width: 12),
          // 匹配模式开关（点击在常规 / 正则之间切换）
          _buildModeToggle(item, index, colorScheme),
          const SizedBox(width: 8),
          // 关键词文本（编辑模式显示输入框，否则双击进入编辑）
          Expanded(
            child: isEditing
                ? _buildKeywordEditField(colorScheme, item.isRegex)
                : GestureDetector(
                    onDoubleTap: () => _startEditing(index, item.keyword),
                    child: CursorTooltipTarget(
                      tooltipContent: const Text('双击编辑关键词'),
                      child: Text(
                        item.keyword,
                        style: context.titleSmall,
                      ),
                    ),
                  ),
          ),
          // 操作按钮
          if (!isEditing) ...[
            _buildIconButton(
              icon: Icons.edit_outlined,
              tooltip: '编辑',
              onTap: () => _startEditing(index, item.keyword),
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 4),
            _buildIconButton(
              icon: Icons.delete_outline,
              tooltip: '删除',
              color: Colors.redAccent,
              onTap: () => widget.service.removeItem(index),
              colorScheme: colorScheme,
            ),
          ],
        ],
      ),
    );
  }

  /// 构建关键词编辑输入框
  ///
  /// 使用 [ImeCursorFixerWrapper] 包裹，修复中文输入法候选框位置跟随问题。
  /// 回车提交修改，按 ESC 取消修改并退出编辑模式。
  Widget _buildKeywordEditField(ColorScheme colorScheme, bool isRegex) {
    return ImeCursorFixerWrapper(
      controller: _editController,
      focusNode: _editFocusNode,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _cancelEditing();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: QwTextField(
          controller: _editController,
          focusNode: _editFocusNode,
          autofocus: true,
          style: context.titleSmall,
          decoration: InputDecoration(
            isDense: true,
            hintText: isRegex ? '输入正则表达式' : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
          onSubmitted: (_) => _commitEditing(),
          onTapOutside: (_) => _commitEditing(),
        ),
      ),
    );
  }

  /// 构建图标按钮
  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
    required ColorScheme colorScheme,
  }) {
    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 18,
            color: color ?? colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 构建新增项的正则匹配图标开关
  ///
  /// 与列表项开关保持一致的视觉语言：图标点亮表示正则模式。
  Widget _buildNewItemModeToggle(ColorScheme colorScheme) {
    final bool isRegex = _newKeywordIsRegex;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ToggleToolButton(
        icon: Icons.code_rounded,
        tooltip: isRegex ? '正则模式，点击切换为常规匹配' : '常规模式，点击切换为正则匹配',
        isSelected: isRegex,
        size: 24,
        iconSize: 16,
        unselectedColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        circular: true,
        onChanged: (value) => setState(() => _newKeywordIsRegex = value),
      ),
    );
  }

  /// 构建新增关键词行
  ///
  /// 使用 [ImeCursorFixerWrapper] 包裹输入框，修复中文输入法候选框位置跟随问题。
  Widget _buildAddKeywordRow(ColorScheme colorScheme) {
    return Row(
      children: [
        // 新增关键词的颜色指示器
        GestureDetector(
          onTap: _pickNewKeywordColor,
          child: CursorTooltipTarget(
            tooltipContent: const Text('选择颜色'),
            child: ColorIndicator(color: ColorUtils.parseHex(_newKeywordColorHex)),
          ),
        ),
        const SizedBox(width: 12),
        // 关键词输入框
        Expanded(
          child: ImeCursorFixerWrapper(
            controller: _keywordInputController,
            focusNode: _keywordInputFocusNode,
            child: QwTextField(
              controller: _keywordInputController,
              focusNode: _keywordInputFocusNode,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: _newKeywordIsRegex
                    ? '输入正则表达式，回车添加'
                    : '输入关键词或字，回车添加',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                // 模式切换徽标放在输入框内，窄屏下也不会挤压输入区域
                suffixIcon: _buildNewItemModeToggle(colorScheme),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) => _addKeyword(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // 添加按钮
        FilledButton.tonalIcon(
          onPressed: _addKeyword,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加'),
        ),
      ],
    );
  }
}
