import 'package:flutter/material.dart';
import 'package:quick_write/core/models/quick_phrase.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_text_field.dart';

/// 显示快捷短语管理弹窗
///
/// 弹窗内列出全部快捷短语，支持新增、修改与删除，改动立即保存到设置。
Future<void> showQuickPhraseManagerDialog({required BuildContext context}) {
  return showDialogBase<void>(
    context: context,
    title: '快捷短语',
    subtitle: '列表显示简短文本，点击后键入完整内容',
    titleIcon: Icons.quickreply_rounded,
    width: 520,
    height: 620,
    content: const _QuickPhraseManagerContent(),
  );
}

/// 快捷短语管理弹窗内容
class _QuickPhraseManagerContent extends StatefulWidget {
  const _QuickPhraseManagerContent();

  @override
  State<_QuickPhraseManagerContent> createState() => _QuickPhraseManagerContentState();
}

class _QuickPhraseManagerContentState extends State<_QuickPhraseManagerContent> {
  /// 内容区左右留白
  static const double _horizontalPadding = 20;

  /// 底部新增按钮高度
  static const double _addButtonHeight = 42;

  /// 当前编辑中的短语列表（与设置保持同步）
  late List<QuickPhrase> _phrases;

  /// 短语列表滚动控制器，滚动条据此跟随列表滚动
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _phrases = List<QuickPhrase>.of(SettingsService.instance.quickPhrases);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 保存当前短语列表
  void _persist() {
    SettingsService.instance.updateQuickPhrases(_phrases);
  }

  /// 新增短语
  Future<void> _handleAdd() async {
    final phrase = await showQuickPhraseEditDialog(context: context);
    if (phrase == null || !mounted) return;
    setState(() => _phrases = [..._phrases, phrase]);
    _persist();
  }

  /// 修改指定位置的短语
  Future<void> _handleEdit(int index) async {
    final phrase = await showQuickPhraseEditDialog(
      context: context,
      phrase: _phrases[index],
    );
    if (phrase == null || !mounted) return;
    setState(() {
      _phrases = List<QuickPhrase>.of(_phrases)..[index] = phrase;
    });
    _persist();
  }

  /// 删除指定位置的短语
  Future<void> _handleDelete(int index) async {
    final phrase = _phrases[index];
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除短语',
      description: '确定删除「${phrase.displayText}」吗？',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _phrases = List<QuickPhrase>.of(_phrases)..removeAt(index);
    });
    _persist();
  }

  /// 调整短语的显示顺序
  ///
  /// 新版 Flutter 的 [ReorderableListView] 在下移时给出的目标位置包含原位置，
  /// 因此向前移动时需要先减去一，再插入到正确位置。
  void _handleReorder(int oldIndex, int newIndex) {
    final List<QuickPhrase> reordered = List<QuickPhrase>.of(_phrases);
    final int targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    reordered.insert(targetIndex, reordered.removeAt(oldIndex));
    setState(() => _phrases = reordered);
    _persist();
  }

  /// 构建拖拽中的条目代理
  ///
  /// 默认代理会用 Material 底色铺满整个条目（含条目之间预留的间距），
  /// 这里改用透明 Material 仅提供绘制环境，拖动时条目外观与列表中保持一致。
  Widget _buildDragProxy(Widget child, int index, Animation<double> animation) {
    return Material(
      type: MaterialType.transparency,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Expanded(
            child: _phrases.isEmpty
                ? _buildEmptyState(context)
                // 去除系统安全区内边距，避免滚动条被系统留白顶开
                : MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    removeLeft: true,
                    removeRight: true,
                    // 短语较多滚动时显示滚动条
                    child: Scrollbar(
                      controller: _scrollController,
                      // 通过每项左侧的拖拽手柄调整显示顺序
                      child: ReorderableListView.builder(
                        scrollController: _scrollController,
                        buildDefaultDragHandles: false,
                        proxyDecorator: _buildDragProxy,
                        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                        itemCount: _phrases.length,
                        onReorder: _handleReorder,
                        itemBuilder: (context, index) => _buildPhraseTile(context, index),
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
                label: const Text('新增短语'),
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
            Icons.quickreply_rounded,
            size: 40,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '还没有快捷短语',
            style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '点击下方按钮添加常用语句',
            style: context.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个短语条目
  ///
  /// 主行显示列表文本，副行预览键入正文的完整内容；
  /// 左侧提供拖拽手柄调整显示顺序，右侧提供修改与删除按钮。
  Widget _buildPhraseTile(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final phrase = _phrases[index];
    // 卡片拖动时会悬浮在其他条目上方，底色需使用不透明等效色，避免透出下层内容
    final Color tileColor = Color.alphaBlend(
      colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      colorScheme.surface,
    );

    // 以短语对象本身作为 key，拖拽重排后仍能保持各条目的状态
    return Padding(
      key: ObjectKey(phrase),
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // 拖拽手柄：按住后上下拖动即可调整顺序
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 30,
                height: 44,
                child: Center(
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phrase.displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phrase.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
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

/// 显示快捷短语编辑弹窗
///
/// [phrase] 为空表示新增短语，否则表示修改该短语；
/// 返回编辑后的短语，用户取消时返回 null。
Future<QuickPhrase?> showQuickPhraseEditDialog({
  required BuildContext context,
  QuickPhrase? phrase,
}) {
  return showDialogBase<QuickPhrase>(
    context: context,
    title: phrase == null ? '新增短语' : '修改短语',
    width: 420,
    height: 460,
    adaptiveHeight: true,
    content: _QuickPhraseEditContent(phrase: phrase),
  );
}

/// 快捷短语编辑弹窗内容
class _QuickPhraseEditContent extends StatefulWidget {
  /// 待修改的短语，为 null 表示新增
  final QuickPhrase? phrase;

  const _QuickPhraseEditContent({this.phrase});

  @override
  State<_QuickPhraseEditContent> createState() => _QuickPhraseEditContentState();
}

class _QuickPhraseEditContentState extends State<_QuickPhraseEditContent> {
  /// 内容区左右留白
  static const double _horizontalPadding = 20;

  /// 显示文本输入控制器
  late final TextEditingController _displayController;

  /// 短语内容输入控制器
  late final TextEditingController _contentController;

  /// 显示文本输入框焦点节点
  final FocusNode _displayFocusNode = FocusNode();

  /// 短语内容输入框焦点节点
  final FocusNode _contentFocusNode = FocusNode();

  /// 校验错误提示
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _displayController = TextEditingController(text: widget.phrase?.displayText ?? '');
    _contentController = TextEditingController(text: widget.phrase?.content ?? '');
  }

  @override
  void dispose() {
    _displayController.dispose();
    _contentController.dispose();
    _displayFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  /// 保存短语
  ///
  /// 显示文本与内容均为必填，内容保留用户输入的原始空白字符
  void _handleSave() {
    final String displayText = _displayController.text.trim();
    final String content = _contentController.text;

    if (displayText.isEmpty) {
      setState(() => _errorMessage = '请输入显示文本');
      return;
    }
    if (content.trim().isEmpty) {
      setState(() => _errorMessage = '请输入短语内容');
      return;
    }

    Navigator.of(context).pop(QuickPhrase(content: content, displayText: displayText));
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
          _buildFieldLabel(context, '显示文本'),
          const SizedBox(height: 8),
          _buildDisplayField(context),
          const SizedBox(height: 16),
          _buildFieldLabel(context, '短语内容'),
          const SizedBox(height: 8),
          _buildContentField(context),
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

  /// 显示文本输入框（单行）
  Widget _buildDisplayField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ImeCursorFixerWrapper(
      controller: _displayController,
      focusNode: _displayFocusNode,
      child: QwTextField(
        controller: _displayController,
        focusNode: _displayFocusNode,
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
          hintText: '列表中显示的简短名称',
          colorScheme: colorScheme,
        ),
      ),
    );
  }

  /// 短语内容输入框（多行）
  Widget _buildContentField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ImeCursorFixerWrapper(
      controller: _contentController,
      focusNode: _contentFocusNode,
      child: QwTextField(
        controller: _contentController,
        focusNode: _contentFocusNode,
        onTapOutside: (_) => _unfocus(),
        style: context.bodyMedium,
        minLines: 3,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        onChanged: (_) {
          if (_errorMessage != null) setState(() => _errorMessage = null);
        },
        decoration: _fieldDecoration(
          context,
          hintText: '点击短语后键入编辑器的完整内容',
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
