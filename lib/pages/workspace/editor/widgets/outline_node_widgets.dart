import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
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

  /// 编辑区背景色（用于箭头遮罩的底色，与编辑器背景保持一致）
  final Color editorBackgroundColor;

  /// 每级缩进的像素宽度
  final double indentWidth;

  /// 圆点与文本间距缩减量
  final double dotTextGapReduction;

  /// 节点底部间距（用于让连接线延伸覆盖，避免间距处连接线中断）
  final double nodeSpacing;

  /// 左右边距（仅移动端使用）
  ///
  /// 桌面端由滚动容器内边距统一施加，移动端作用于节点行内容；
  /// 行尾竖条位于内容区之外，始终贴到编辑区右边缘，不受该设置影响
  final double horizontalMargin;

  /// 是否被选中
  final bool isSelected;

  /// 是否处于批量选择模式
  final bool isBatchMode;

  /// 是否只读
  final bool readOnly;

  /// 切换展开/折叠回调
  final VoidCallback onToggleExpand;

  /// 批量选择模式下点击节点回调（切换该节点及其子树的选中状态）
  final VoidCallback onBatchTap;

  /// 文本变化回调
  final ValueChanged<String> onChanged;

  /// 行尾竖条长按回调（传入长按位置的全局坐标）
  ///
  /// 仅移动端触发，用于选中长按所在的节点及其子节点并进入批量选择模式
  final ValueChanged<Offset> onTrailingBarLongPress;

  /// 行尾竖条长按拖动回调（传入指针当前的全局坐标）
  ///
  /// 仅移动端触发，用于在长按不松手的情况下扩展或收缩节点选区
  final ValueChanged<Offset> onTrailingBarLongPressMove;

  /// 批量选择模式下按住行尾竖条开始滑动选择的回调
  ///
  /// 仅移动端触发，以按下节点为锚点，滑动过程中按指针位置连续选中或取消途经节点
  final VoidCallback onTrailingBarDragStart;

  /// 批量选择模式下行尾竖条滑动选择结束的回调
  final VoidCallback onTrailingBarDragEnd;

  /// 失焦时是否应保留选区（传入节点ID，仅右键菜单目标节点为 true）
  final bool Function(String nodeId) shouldPersistSelectionOnFocusLoss;

  const OutlineNodeTile({
    super.key,
    required this.node,
    required this.depth,
    required this.controller,
    required this.focusNode,
    required this.colorScheme,
    required this.editorBackgroundColor,
    required this.indentWidth,
    required this.dotTextGapReduction,
    required this.nodeSpacing,
    required this.horizontalMargin,
    required this.isSelected,
    required this.isBatchMode,
    required this.readOnly,
    required this.onToggleExpand,
    required this.onBatchTap,
    required this.onChanged,
    required this.onTrailingBarLongPress,
    required this.onTrailingBarLongPressMove,
    required this.onTrailingBarDragStart,
    required this.onTrailingBarDragEnd,
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

  /// 行尾竖条宽度（仅移动端），需容纳得下顶部的折叠图标
  static const double _trailingBarWidth = 14.0;

  /// 行尾竖条顶部折叠图标大小
  static const double _trailingBarIconSize = 22.0;

  /// 行尾竖条折叠图标相对竖条右边缘的水平内缩量
  ///
  /// 取负值让图标向竖条两侧等量溢出，使图标在竖条内水平居中
  static const double _trailingBarIconInset = -(_trailingBarIconSize - _trailingBarWidth) / 2;

  /// 行尾竖条折叠图标的水平微调偏移量
  ///
  /// 展开态与折叠态共用该偏移量做整体水平微调，默认为 0 时两态三角均落在竖条内居中位置
  static const double _trailingBarIconOffsetX = 1.0;

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

        // 移动端折叠入口位于行尾，行首不再为折叠箭头预留列，指示区整体左移一列
        final bool isMobile = PlatformCapabilities.isMobile;
        final int columnOffset = isMobile ? -1 : 0;

        // 连接线绘制区域总宽度（包含圆点占位，减去与文本的间距缩减量）
        final connectionWidth =
            (depth + 2 + columnOffset) * indentWidth - widget.dotTextGapReduction;

        // 圆点颜色
        final dotColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

        // 折叠态圆点背景色：与圆点同色但更透明，作为子节点被收起的视觉提示
        final collapsedDotBackground = colorScheme.onSurfaceVariant.withValues(alpha: 0.1);

        // 节点行内容：文本输入区
        // 底部间距纳入内容区高度，使连接线的 Positioned 能覆盖间距区域
        // 右侧留白由外层内容区的内边距统一承担，为行尾竖条与左右边距预留空间
        final Widget rowContent = Padding(
          padding: EdgeInsets.only(
            left: connectionWidth,
            bottom: widget.nodeSpacing,
          ),
          child: _buildTextField(node, colorScheme),
        );

        final Widget row = Stack(
          children: [
            rowContent,
            // 连接线与圆点（填充整个节点行高度，含底部间距）
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: connectionWidth,
              child: CustomPaint(
                painter: OutlineConnectionPainter(
                  depth: depth,
                  columnOffset: columnOffset,
                  indentWidth: indentWidth,
                  textLineHeight: _textLineHeight,
                  lineColor: lineColor,
                  dotColor: dotColor,
                  // 移动端圆点整体上移两个像素，与行尾竖条折叠三角的视觉重心对齐
                  dotVerticalOffset:
                      OutlineConnectionMetrics.dotVerticalOffset - (isMobile ? 2.0 : 0.0),
                  // 有子节点且处于折叠态时，为圆点绘制背景以提示子节点被收起
                  collapsedDotBackgroundColor: hasChildren && !node.isExpanded
                      ? collapsedDotBackground
                      : null,
                ),
              ),
            ),
            // 箭头交互层（桌面端有子节点时叠加在连接线上方）
            if (hasChildren && !isMobile) _buildArrowButton(node, colorScheme, indentWidth),
          ],
        );

        // 节点行内容区：左侧留白用于缩进节点，左右边距设置在此处生效
        final Widget content = Padding(
          padding: EdgeInsets.only(
            left: 8 + (isMobile ? widget.horizontalMargin : 0),
            // 移动端在右侧预留行尾竖条宽度与左右边距，竖条本身位于内容区之外
            right: isMobile ? _trailingBarWidth + widget.horizontalMargin : 8,
          ),
          child: widget.isBatchMode
              // 批量选择模式下整行可点击切换节点选中
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onBatchTap,
                  child: row,
                )
              : row,
        );

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: ColoredBox(
            // 选中节点时显示高亮背景
            color: widget.isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            child: isMobile
                // 行尾竖条叠加在内容区之上并贴到编辑区右边缘，不随左右边距设置移动
                ? Stack(
                    children: [
                      content,
                      _buildTrailingBar(node, colorScheme),
                    ],
                  )
                : content,
          ),
        );
      },
    );
  }

  /// 构建节点文本输入区
  ///
  /// 批量选择模式下屏蔽输入交互，节点只能整体选中与操作，不能编辑文字
  Widget _buildTextField(OutlineNode node, ColorScheme colorScheme) {
    return IgnorePointer(
      ignoring: widget.isBatchMode,
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
          // 折叠光标（单击定位产生的光标）不绘制拖动调整用的手柄，仅保留光标本身；
          // 仅 Android 的默认控件会为折叠光标绘制手柄，故只在 Android 上替换，桌面端与 iOS 保持系统默认
          selectionControls: Theme.of(context).platform == TargetPlatform.android
              ? _outlineNodeSelectionControls
              : null,
          // 桌面端屏蔽 TextField 原生右键菜单，改用自定义右键菜单；
          // 移动端长按选中文字后弹出文字选择工具栏
          contextMenuBuilder: PlatformCapabilities.isMobile
              ? _buildMobileSelectionToolbar
              : (context, editableTextState) => const SizedBox.shrink(),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }

  /// 构建移动端文字选择工具栏
  ///
  /// 长按选中文字后在选区上方弹出，提供剪切、复制、粘贴、全选四项操作；
  /// 无选中文字时仅保留粘贴与全选，只读节点仅保留复制与全选。
  Widget _buildMobileSelectionToolbar(BuildContext context, EditableTextState editableTextState) {
    final bool hasSelection = editableTextState.textEditingValue.selection.isValid &&
        !editableTextState.textEditingValue.selection.isCollapsed;

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: [
        if (!widget.readOnly && hasSelection)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.cut,
            onPressed: () => editableTextState.cutSelection(SelectionChangedCause.toolbar),
          ),
        if (hasSelection)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.copy,
            onPressed: () => editableTextState.copySelection(SelectionChangedCause.toolbar),
          ),
        if (!widget.readOnly)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.paste,
            onPressed: () => editableTextState.pasteText(SelectionChangedCause.toolbar),
          ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () => editableTextState.selectAll(SelectionChangedCause.toolbar),
        ),
      ],
    );
  }

  /// 构建箭头按钮（悬停时显示，叠加在连接线之上）
  ///
  /// 箭头位于列 depth 的中心，与第一行文字对齐。
  /// 通过 Opacity 控制可见性，保留 AnimatedRotation 动画连续性。
  /// 箭头的 Material 背景用于遮住下方的连接线，避免视觉穿透
  Widget _buildArrowButton(OutlineNode node, ColorScheme colorScheme, double indentWidth) {
    // 节点行实际背景色：选中时为 primary 半透明叠加编辑区背景色，否则为编辑区背景色
    // 用于遮住箭头位置下方的连接线，避免视觉穿透
    final nodeBackgroundColor = widget.isSelected
        ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.12), widget.editorBackgroundColor)
        : widget.editorBackgroundColor;

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

  /// 构建行尾竖条（仅移动端）
  ///
  /// 竖条铺满节点行的高度并贴到编辑区右边缘，宽度足以容纳顶部的折叠图标；
  /// 所有节点（含无子节点的节点）都显示竖条，有子节点时在竖条内部顶部额外显示折叠三角，
  /// 点击竖条切换展开/折叠；长按竖条选中该节点及其子节点并进入批量选择模式，
  /// 批量选择模式下点击竖条切换节点选中状态，按住滑动则连续选中或取消途经节点
  Widget _buildTrailingBar(OutlineNode node, ColorScheme colorScheme) {
    final bool hasChildren = node.children.isNotEmpty;

    // 所在节点行的实际背景色：选中时为 primary 半透明叠加编辑区背景色，否则为编辑区背景色
    final Color rowBackgroundColor = widget.isSelected
        ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.12), widget.editorBackgroundColor)
        : widget.editorBackgroundColor;

    // 竖条底色：先与节点行背景合成再填色，避免相邻竖条的半透明色相互叠加产生接缝；
    // 批量选择模式下未选中节点用更明显的弱化底色，让整条竖带连续可见，便于按住滑动选择
    final Color barColor = widget.isSelected
        ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.5), rowBackgroundColor)
        : Color.alphaBlend(
            colorScheme.onSurfaceVariant.withValues(alpha: widget.isBatchMode ? 0.05 : 0.03),
            rowBackgroundColor,
          );

    // 折叠三角：仅在有子节点时显示；批量选择模式下不显示展开态三角，只保留折叠态三角提示子节点被收起
    final bool showFoldIcon = hasChildren && (!widget.isBatchMode || !node.isExpanded);

    // 折叠三角颜色：跟随竖条底色选择对比色，保证在两种状态下都清晰可见
    final Color iconColor = widget.isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: _trailingBarWidth,
      child: GestureDetector(
        // 空白处同样响应手势，保证整个竖条区域都是有效的点击与长按热区
        behavior: HitTestBehavior.opaque,
        onTap: widget.isBatchMode
            ? widget.onBatchTap
            : (hasChildren ? widget.onToggleExpand : null),
        onLongPressStart: (details) => widget.onTrailingBarLongPress(details.globalPosition),
        onLongPressMoveUpdate: (details) =>
            widget.onTrailingBarLongPressMove(details.globalPosition),
        // 批量选择模式下按住竖条纵向滑动即可连续选中或取消途经节点
        onVerticalDragStart: widget.isBatchMode ? (_) => widget.onTrailingBarDragStart() : null,
        onVerticalDragEnd: widget.isBatchMode ? (_) => widget.onTrailingBarDragEnd() : null,
        onVerticalDragCancel: widget.isBatchMode ? widget.onTrailingBarDragEnd : null,
        child: Stack(
          children: [
            // 竖条本体，贴在最右侧边缘
            Positioned.fill(child: ColoredBox(color: barColor)),
            // 折叠三角：位于竖条内部并与第一行文字垂直对齐
            if (showFoldIcon)
              Positioned(
                top: 0,
                // 图标比竖条宽，向两侧等量溢出，使旋转围绕图标自身中心进行，
                // 保证展开态与折叠态的三角水平位置一致
                right: _trailingBarIconInset,
                height: _textLineHeight,
                child: Transform.translate(
                  offset: const Offset(_trailingBarIconOffsetX, 0),
                  // 展开时三角向下（倒三角），折叠时顺时针旋转为向左的三角
                  child: AnimatedRotation(
                    turns: node.isExpanded ? 0 : 0.25,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: _trailingBarIconSize,
                      color: iconColor,
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

/// 大纲节点输入框在 Android 上使用的文字选择控件
///
/// 折叠光标（单击定位时的光标）不绘制拖动调整用的手柄，仅显示光标本身；
/// 选中文字后的左右手柄沿用 Material 默认样式，仍可拖动调整选区范围。
class _OutlineNodeSelectionControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textHeight, [
    VoidCallback? onTap,
  ]) {
    if (type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    return super.buildHandle(context, type, textHeight, onTap);
  }
}

/// 大纲节点输入框在 Android 上使用的文字选择控件实例
final TextSelectionControls _outlineNodeSelectionControls = _OutlineNodeSelectionControls();
