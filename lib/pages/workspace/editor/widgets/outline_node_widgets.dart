import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_connection_painter.dart';

/// 单个节点行组件
///
/// 使用 CustomPaint 绘制连接线和圆点，箭头作为独立交互层叠加在连接线之上。
/// 连接线区域与文本输入区通过 Stack 叠加。
class OutlineNodeTile extends StatefulWidget {
  /// 节点数据
  final OutlineNode node;

  /// 节点深度
  final int depth;

  /// 文本控制器
  final TextEditingController controller;

  /// 焦点节点
  final FocusNode focusNode;

  /// 颜色方案
  final ColorScheme colorScheme;

  /// 每级缩进的像素宽度
  final double indentWidth;

  /// 圆点与文本间距缩减量
  final double dotTextGapReduction;

  /// 节点底部间距（用于让连接线延伸覆盖，避免间距处连接线中断）
  final double nodeSpacing;

  /// 是否被选中
  final bool isSelected;

  /// 是否只读
  final bool readOnly;

  /// 切换展开/折叠回调
  final VoidCallback onToggleExpand;

  /// 文本变化回调
  final ValueChanged<String> onChanged;

  /// 失焦时是否应保留选区（传入节点ID，仅右键菜单目标节点为 true）
  final bool Function(String nodeId) shouldPersistSelectionOnFocusLoss;

  const OutlineNodeTile({
    super.key,
    required this.node,
    required this.depth,
    required this.controller,
    required this.focusNode,
    required this.colorScheme,
    required this.indentWidth,
    required this.dotTextGapReduction,
    required this.nodeSpacing,
    required this.isSelected,
    required this.readOnly,
    required this.onToggleExpand,
    required this.onChanged,
    required this.shouldPersistSelectionOnFocusLoss,
  });

  @override
  State<OutlineNodeTile> createState() => _OutlineNodeTileState();
}

class _OutlineNodeTileState extends State<OutlineNodeTile> {
  /// 鼠标是否悬停在节点行上
  bool _isHovered = false;

  /// 文字行高倍数
  static const double _lineHeightFactor = 1.5;

  /// 内容垂直内边距
  // static const double _contentPaddingVertical = 8.0;

  /// 折叠提示占位宽度
  static const double indentWidthHint = 28.0;

  /// 失焦时绘制持久化选区的 Painter
  final PersistentSelectionOverlayPainter _persistentSelectionPainter =
      PersistentSelectionOverlayPainter();

  /// TextField 的 GlobalKey，用于查找 RenderEditable 注入 Painter
  final GlobalKey _textFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 监听焦点变化，更新持久化选区 Painter 的失焦状态
    widget.focusNode.addListener(_onFocusChanged);
    // 监听选区变化，同步给 Painter
    widget.controller.addListener(_onSelectionChanged);
    // 第一帧后将 Painter 注入到 RenderEditable，此时渲染树已构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attachPersistentSelectionPainter();
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onSelectionChanged);
    _persistentSelectionPainter.dispose();
    super.dispose();
  }

  /// 焦点变化时更新 Painter 的失焦状态
  void _onFocusChanged() {
    final hasFocus = widget.focusNode.hasFocus;
    // 失焦时：非右键菜单目标节点清除文本选区，避免切换到其他节点时旧选区残留
    if (!hasFocus && !widget.shouldPersistSelectionOnFocusLoss(widget.node.id)) {
      final offset = widget.controller.selection.baseOffset.clamp(0, widget.controller.text.length);
      widget.controller.selection = TextSelection.collapsed(offset: offset);
    }
    _persistentSelectionPainter.update(
      isUnfocused: !hasFocus,
      selection: widget.controller.selection,
      color: computePersistentSelectionColor(context, widget.colorScheme.primary),
    );
  }

  /// 选区变化时同步给 Painter
  void _onSelectionChanged() {
    _persistentSelectionPainter.update(
      selection: widget.controller.selection,
    );
  }

  /// 将持久化选区 Painter 注入到 RenderEditable
  void _attachPersistentSelectionPainter() {
    attachPersistentSelectionPainter(
      textFieldKey: _textFieldKey,
      painter: _persistentSelectionPainter,
      controller: widget.controller,
      focusNode: widget.focusNode,
      context: context,
      fallbackColor: widget.colorScheme.primary,
    );
  }

  /// 最大标题级别常量
  ///
  /// 用于计算标题字号偏移，扩展标题级别时只需调整此值。
  static const int _maxHeadingLevel = 3;

  /// 当前文字字号（基础字号 + 标题级别偏移）
  ///
  /// 标题级别数字越低字号越大：H1=+6, H2=+4, H3=+2，正文(0)无偏移。
  double get _fontSize {
    final level = widget.node.headingLevel;
    final offset = level == 0 ? 0 : (_maxHeadingLevel - level + 1) * 2;
    return SettingsService.instance.outlineFontSize + offset;
  }

  /// 单行文字高度（字号 × 行高倍数）
  double get _textLineHeight => _fontSize * _lineHeightFactor;

  @override
  Widget build(BuildContext context) {
    // 监听设置变化，字体或字号改变时重建节点
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final node = widget.node;
        final depth = widget.depth;
        final hasChildren = node.children.isNotEmpty;
        final colorScheme = widget.colorScheme;
        final indentWidth = widget.indentWidth;
        final lineColor = colorScheme.outlineVariant.withValues(alpha: 0.4);

        // 连接线绘制区域总宽度（包含圆点占位，减去与文本的间距缩减量）
        final connectionWidth = (depth + 2) * indentWidth - widget.dotTextGapReduction;

        // 圆点颜色
        final dotColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: ColoredBox(
            // 选中节点时显示高亮背景
            color: widget.isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                children: [
                  // 内容区：文本输入框 + 折叠提示（决定 Stack 高度）
                  // 底部间距纳入内容区高度，使连接线的 Positioned 能覆盖间距区域
                  Padding(
                    padding: EdgeInsets.only(left: connectionWidth, bottom: widget.nodeSpacing),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 文本输入区
                        Expanded(
                          child: ImeCursorFixerWrapper(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            child: TextField(
                              key: _textFieldKey,
                              controller: widget.controller,
                              focusNode: widget.focusNode,
                              readOnly: widget.readOnly,
                              maxLines: null,
                              minLines: 1,
                              // 基础样式：字号、字体、行高、默认文字颜色
                              // 加粗/斜体/下划线/删除线由 RichTextEditingController 的 buildTextSpan 根据 styleRanges 叠加
                              style: TextStyle(
                                fontFamily: SettingsService.instance.outlineFontFamily,
                                fontSize: _fontSize,
                                height: _lineHeightFactor,
                                color: node.foregroundColor ?? colorScheme.onSurface,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                filled: false,
                                isCollapsed: true,
                                // contentPadding: EdgeInsets.fromLTRB(6, _contentPaddingVertical - 2.5, 6, _contentPaddingVertical + 2.5),
                                isDense: true,
                              ),
                              cursorColor: colorScheme.primary,
                              // 屏蔽 TextField 原生右键菜单，改用自定义 ContextMenu
                              contextMenuBuilder: (context, editableTextState) => const SizedBox.shrink(),
                              onChanged: widget.onChanged,
                            ),
                          ),
                        ),
                        // 折叠子节点数量提示（折叠时显示）
                        if (hasChildren && !node.isExpanded) _buildCollapsedHint(colorScheme),
                      ],
                    ),
                  ),
                  // 连接线与圆点（填充整个节点行高度，含底部间距）
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: connectionWidth,
                    child: CustomPaint(
                      painter: OutlineConnectionPainter(
                        depth: depth,
                        indentWidth: indentWidth,
                        textLineHeight: _textLineHeight,
                        lineColor: lineColor,
                        dotColor: dotColor,
                      ),
                    ),
                  ),
                  // 箭头交互层（有子节点时叠加在连接线上方）
                  if (hasChildren) _buildArrowButton(node, colorScheme, indentWidth),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建折叠子节点数量提示
  ///
  /// 与文字第一行垂直居中对齐
  Widget _buildCollapsedHint(ColorScheme colorScheme) {
    return SizedBox(
      width: indentWidthHint,
      height: _textLineHeight,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Text(
            '${widget.node.children.length}',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  /// 构建箭头按钮（悬停时显示，叠加在连接线之上）
  ///
  /// 箭头位于列 depth 的中心，与第一行文字对齐。
  /// 通过 Opacity 控制可见性，保留 AnimatedRotation 动画连续性。
  /// 箭头的 Material 背景用于遮住下方的连接线，避免视觉穿透
  Widget _buildArrowButton(OutlineNode node, ColorScheme colorScheme, double indentWidth) {
    // 节点行实际背景色：选中时为 primary 半透明叠加 surfaceContainerLowest，否则为 surfaceContainerLowest
    // 用于遮住箭头位置下方的连接线，避免视觉穿透
    final nodeBackgroundColor = widget.isSelected
        ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.12), colorScheme.surfaceContainerLowest)
        : colorScheme.surfaceContainerLowest;

    return Positioned(
      left: widget.depth * indentWidth,
      top: 0,
      child: SizedBox(
        width: indentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: indentWidth, height: _textLineHeight / 2 - 5),
            Opacity(
              opacity: _isHovered ? 1.0 : 0.0,
              child: Material(
                color: _isHovered ? nodeBackgroundColor : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: widget.onToggleExpand,
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: AnimatedRotation(
                      turns: node.isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
