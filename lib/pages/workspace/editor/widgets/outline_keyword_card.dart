import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_color_palette.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 大纲节点关键词编辑弹窗
///
/// 以居中弹窗展示（弹窗外区域变暗），用于为节点增删关键词并设置颜色；
/// 每次增删改都立即回调 [onChanged] 写入节点并触发自动保存。
class OutlineKeywordCard extends StatefulWidget {
  /// 弹窗宽度
  static const double width = 400;

  /// 弹窗最大高度
  static const double maxHeight = 560;

  /// 节点当前绑定的关键词
  final List<OutlineKeyword> keywords;

  /// 关键词变化回调，返回被拒绝的关键词（已被其他节点绑定）
  final Set<String> Function(List<OutlineKeyword> keywords) onChanged;

  const OutlineKeywordCard({
    super.key,
    required this.keywords,
    required this.onChanged,
  });

  /// 弹出居中的关键词编辑弹窗
  static Future<void> show({
    required BuildContext context,
    required List<OutlineKeyword> keywords,
    required Set<String> Function(List<OutlineKeyword> keywords) onChanged,
  }) {
    return showDialogBase<void>(
      context: context,
      title: '节点关键词',
      subtitle: '同一关键词只能绑定一个节点',
      titleIcon: Icons.sell_outlined,
      titleFontSize: 15,
      width: width,
      // 高度随关键词数量自适应，超出该高度时内容整体滚动
      height: maxHeight,
      adaptiveHeight: true,
      content: OutlineKeywordCard(
        keywords: keywords,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<OutlineKeywordCard> createState() => _OutlineKeywordCardState();
}

class _OutlineKeywordCardState extends State<OutlineKeywordCard> {
  /// 输入行控件高度，输入框与添加按钮保持一致
  static const double _controlHeight = 40;

  /// 关键词输入框控制器
  final TextEditingController _inputController = TextEditingController();

  /// 输入框焦点
  final FocusNode _inputFocusNode = FocusNode();

  /// 弹窗内维护的关键词列表（与节点保持同步）
  late List<OutlineKeyword> _keywords;

  /// 新关键词默认使用的颜色
  Color _selectedColor = OutlineColorPalette.colors.first.foreground;

  /// 冲突提示
  String? _message;

  @override
  void initState() {
    super.initState();
    _keywords = List<OutlineKeyword>.of(widget.keywords);
    // 打开弹窗后直接聚焦输入框，便于立即输入关键词
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: _buildInputRow(colorScheme),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _buildColorRow(colorScheme),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_message!, style: TextStyle(fontSize: 12, color: colorScheme.error)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        _buildKeywordList(colorScheme),
      ],
    );
  }

  /// 构建输入行：关键词输入框 + 添加按钮
  Widget _buildInputRow(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: _controlHeight,
            child: ImeCursorFixerWrapper(
              controller: _inputController,
              focusNode: _inputFocusNode,
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addKeyword(),
                // 输入框填满固定高度的容器，文字在其中垂直居中
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '输入关键词',
                  hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: _controlHeight,
          child: FilledButton(
            onPressed: _addKeyword,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('添加'),
          ),
        ),
      ],
    );
  }

  /// 构建颜色选择行
  Widget _buildColorRow(ColorScheme colorScheme) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final color in OutlineColorPalette.colors) _buildColorOption(color.foreground),
      ],
    );
  }

  /// 构建单个颜色选项：外圈选中描边 + 内圈色块 + 选中对勾
  Widget _buildColorOption(Color color) {
    final bool selected = color == _selectedColor;
    final bool useLightCheck = ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    return _PressScale(
      onTap: () => setState(() => _selectedColor = color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: selected
              ? Icon(Icons.check_rounded, size: 13, color: useLightCheck ? Colors.white : Colors.black87)
              : null,
        ),
      ),
    );
  }

  /// 构建已绑定关键词列表
  Widget _buildKeywordList(ColorScheme colorScheme) {
    if (_keywords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sell_outlined,
              size: 26,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 8),
            Text(
              '暂未绑定关键词',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      // 列表不单独滚动，内容超出弹窗最大高度时由弹窗外壳统一滚动
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _keywords.length,
      itemBuilder: (context, index) {
        final OutlineKeyword keyword = _keywords[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildKeywordColorDot(keyword, index),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    keyword.keyword,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                  ),
                ),
                CursorTooltipTarget(
                  tooltipContent: const Text('移除关键词'),
                  child: IconButton(
                    onPressed: () => _removeKeyword(index),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    color: colorScheme.onSurfaceVariant,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建关键词颜色圆点（点击弹出颜色选择卡片）
  Widget _buildKeywordColorDot(OutlineKeyword keyword, int index) {
    return Builder(
      builder: (dotContext) => CursorTooltipTarget(
        tooltipContent: const Text('修改颜色'),
        child: _PressScale(
          onTap: () => _showColorPicker(dotContext, keyword, index),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: keyword.color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  /// 弹出颜色选择卡片
  ///
  /// 卡片以颜色圆点为锚点向上展开，横向排列调色板色块，点击色块即选定颜色并关闭。
  void _showColorPicker(BuildContext dotContext, OutlineKeyword keyword, int index) {
    final RenderBox dotBox = dotContext.findRenderObject() as RenderBox;
    final Rect anchor = dotBox.localToGlobal(Offset.zero) & dotBox.size;

    showGeneralDialog<void>(
      context: dotContext,
      barrierDismissible: true,
      barrierLabel: '关闭颜色选择',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => CustomSingleChildLayout(
        delegate: _ColorPickerLayout(anchor: anchor),
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            // 以卡片底部中心为缩放原点，使卡片从颜色圆点一侧展开
            alignment: Alignment.bottomCenter,
            child: _buildColorPickerCard(dialogContext, keyword, index),
          ),
        ),
      ),
    );
  }

  /// 构建颜色选择卡片
  Widget _buildColorPickerCard(BuildContext dialogContext, OutlineKeyword keyword, int index) {
    final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < OutlineColorPalette.colors.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _buildColorPickerOption(dialogContext, keyword, index, OutlineColorPalette.colors[i].foreground),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建卡片中的单个色块（当前颜色带选中描边与对勾）
  Widget _buildColorPickerOption(BuildContext dialogContext, OutlineKeyword keyword, int index, Color color) {
    final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
    final bool selected = color == keyword.color;
    final bool useLightCheck = ThemeData.estimateBrightnessForColor(color) == Brightness.dark;

    return _PressScale(
      onTap: () {
        _updateColor(index, color);
        Navigator.of(dialogContext).pop();
      },
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? colorScheme.onSurface : Colors.transparent, width: 2),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 13, color: useLightCheck ? Colors.white : Colors.black87)
            : null,
      ),
    );
  }

  /// 添加关键词
  ///
  /// 空值与当前节点内的重复关键词直接忽略；已被其他节点绑定的关键词被拒绝并提示。
  void _addKeyword() {
    final String text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (_keywords.any((keyword) => keyword.keyword == text)) {
      _inputController.clear();
      return;
    }

    final List<OutlineKeyword> candidate = [
      ..._keywords,
      OutlineKeyword(keyword: text, colorHex: ColorUtils.toHex(_selectedColor)),
    ];
    final Set<String> rejected = widget.onChanged(candidate);
    if (rejected.contains(text)) {
      setState(() => _message = '该关键词已被其他节点绑定');
      return;
    }

    setState(() {
      _keywords = candidate;
      _message = null;
    });
    _inputController.clear();
    _inputFocusNode.requestFocus();
  }

  /// 移除关键词
  void _removeKeyword(int index) {
    final List<OutlineKeyword> candidate = List<OutlineKeyword>.of(_keywords)..removeAt(index);
    final Set<String> rejected = widget.onChanged(candidate);
    setState(() {
      _keywords = candidate.where((keyword) => !rejected.contains(keyword.keyword)).toList();
      _message = null;
    });
  }

  /// 修改指定关键词的颜色
  void _updateColor(int index, Color color) {
    final List<OutlineKeyword> candidate = List<OutlineKeyword>.of(_keywords);
    candidate[index] = candidate[index].copyWith(colorHex: ColorUtils.toHex(color));
    widget.onChanged(candidate);
    setState(() => _keywords = candidate);
  }
}

/// 颜色选择卡片的定位委托
///
/// 卡片以颜色圆点为锚点：默认位于圆点上方且水平居中，上方空间不足时翻到下方，
/// 并始终限制在屏幕范围内。
class _ColorPickerLayout extends SingleChildLayoutDelegate {
  /// 锚点（颜色圆点）的全局矩形
  final Rect anchor;

  /// 卡片与锚点之间的间距
  static const double _gap = 8;

  /// 卡片与屏幕边缘的最小间距
  static const double _margin = 12;

  const _ColorPickerLayout({required this.anchor});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double maxLeft = math.max(_margin, size.width - childSize.width - _margin);
    final double left = (anchor.center.dx - childSize.width / 2).clamp(_margin, maxLeft).toDouble();
    final double above = anchor.top - childSize.height - _gap;
    final double top = above >= _margin ? above : anchor.bottom + _gap;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_ColorPickerLayout oldDelegate) => oldDelegate.anchor != anchor;
}

/// 可点击的缩放交互容器
///
/// 鼠标悬停时放大、按下时缩小，用于色块与颜色圆点的交互反馈。
class _PressScale extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 点击回调
  final VoidCallback? onTap;

  const _PressScale({required this.child, this.onTap});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  /// 悬停时的缩放倍数
  static const double _hoverScale = 1.15;

  /// 按下时的缩放倍数
  static const double _pressedScale = 0.9;

  /// 鼠标是否悬停在组件上
  bool _hovered = false;

  /// 组件是否处于按下状态
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // 按下优先于悬停，松开后回到悬停或原始大小
    final double scale = _pressed ? _pressedScale : (_hovered ? _hoverScale : 1);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
