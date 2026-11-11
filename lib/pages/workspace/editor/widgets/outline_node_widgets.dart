import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/find_match_highlighter.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
import 'package:quick_write/core/utils/rich_text_controller.dart';
import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_color_palette.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_connection_painter.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_editor_widgets.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_node_attachment.dart';

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

  /// 是否为当前编辑节点
  ///
  /// 为 true 时圆点以点亮色绘制，标识当前正在编辑的节点
  final bool isActiveNode;

  /// 需要点亮的连接线所在列
  ///
  /// 非空时该列连接线以点亮色绘制，即当前编辑节点圆点下方通往下一个同级节点的连接线；
  /// 不处于该连接线上的节点传 null
  final int? highlightedLineColumn;

  /// 是否处于批量选择模式
  final bool isBatchMode;

  /// 是否只读
  final bool readOnly;

  /// 切换展开/折叠回调
  final VoidCallback onToggleExpand;

  /// 点击圆点进入该节点主题视图回调
  ///
  /// 为空时圆点不响应点击，仅保留长按拖拽排序
  final VoidCallback? onDotTap;

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

  /// 圆点长按开始拖拽排序回调（传入长按位置的全局坐标）
  ///
  /// 为空时不注册圆点长按手势，节点圆点不可拖拽
  final ValueChanged<Offset>? onDotDragStart;

  /// 圆点拖拽移动回调（传入指针当前的全局坐标）
  final ValueChanged<Offset>? onDotDragMove;

  /// 圆点拖拽结束回调（松手时触发，由调用方按落点执行移动）
  final VoidCallback? onDotDragEnd;

  /// 圆点拖拽取消回调
  final VoidCallback? onDotDragCancel;

  /// 是否正在被拖拽排序
  ///
  /// 为 true 时整行降低不透明度，提示该节点正在被移动
  final bool isDragging;

  /// 子节点收进圆点的动画进度
  ///
  /// 非空时整行随进度向目标圆点缩放、淡出，同时高度收缩，
  /// 使下方节点行平滑上移填补空出的位置；为 null 时按普通节点行渲染
  final Animation<double>? subtreeFoldProgress;

  /// 子节点收拢动画的目标圆点所在深度
  ///
  /// 收起过程中整行向该深度对应的圆点缩放；无动画时为 null
  final int? foldTargetDotDepth;

  /// 本节点圆点自身的折叠动画进度
  ///
  /// 非空时圆点外轮廓半径随进度变化，与子节点收进圆点的过程同步
  final Animation<double>? dotFoldProgress;

  /// 失焦时是否应保留选区（传入节点ID，仅右键菜单目标节点为 true）
  final bool Function(String nodeId) shouldPersistSelectionOnFocusLoss;

  /// 点击关联文本回调（参数为文本样式区间中记录的关联标识）
  final ValueChanged<String>? onLinkTap;

  /// 节点附加图片的绝对路径（空字符串表示没有图片）
  final String imagePath;

  /// 是否正在编辑节点备注
  final bool isEditingNote;

  /// 节点备注内容变化回调
  final ValueChanged<String> onNoteChanged;

  /// 开始编辑节点备注回调
  final VoidCallback onStartNoteEdit;

  /// 结束编辑节点备注回调
  final VoidCallback onStopNoteEdit;

  /// 删除节点图片回调
  final VoidCallback onDeleteNodeImage;

  /// 附加备注区的全局键
  ///
  /// 供编辑器判断指针是否落在备注区，从而把手势让给备注输入框。
  final Key? attachmentKey;

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
    required this.isActiveNode,
    this.highlightedLineColumn,
    required this.isBatchMode,
    required this.readOnly,
    required this.onToggleExpand,
    this.onDotTap,
    required this.onBatchTap,
    required this.onChanged,
    required this.onTrailingBarLongPress,
    required this.onTrailingBarLongPressMove,
    required this.onTrailingBarDragStart,
    required this.onTrailingBarDragEnd,
    this.onDotDragStart,
    this.onDotDragMove,
    this.onDotDragEnd,
    this.onDotDragCancel,
    this.isDragging = false,
    this.subtreeFoldProgress,
    this.foldTargetDotDepth,
    this.dotFoldProgress,
    required this.shouldPersistSelectionOnFocusLoss,
    this.onLinkTap,
    this.imagePath = '',
    this.isEditingNote = false,
    required this.onNoteChanged,
    required this.onStartNoteEdit,
    required this.onStopNoteEdit,
    required this.onDeleteNodeImage,
    this.attachmentKey,
  });

  /// 计算指定深度节点行首连接线区域的总宽度
  ///
  /// 连接线区域包含圆点占位与缩进列，并减去圆点与文本之间的间距缩减量；
  /// 移动端折叠入口位于行尾、行首少一列，因此按移动端布局额外左移一列。
  static double connectionWidthForDepth(
    int depth, {
    required double indentWidth,
    required double dotTextGapReduction,
  }) {
    final int columnOffset = PlatformCapabilities.isMobile ? -1 : 0;
    return (depth + 2 + columnOffset) * indentWidth - dotTextGapReduction;
  }

  /// 计算指定深度节点的圆点左边缘在节点行内的水平位置
  ///
  /// 圆点绘制在列 (depth + 1) 的中心，移动端整体左移一列；
  /// 左边缘取圆心横坐标减去圆点半径。
  static double dotLeftInsetForDepth(int depth, {required double indentWidth}) {
    final int columnOffset = PlatformCapabilities.isMobile ? -1 : 0;
    final double dotCenterX = (depth + 1 + columnOffset) * indentWidth + indentWidth / 2;
    return dotCenterX - OutlineConnectionMetrics.dotRadius;
  }

  /// 计算折叠箭头在节点行内的矩形
  ///
  /// 箭头占据列 [depth] 的整列宽度，纵向自半行高上移固定偏移量处开始，
  /// 高度为图标边长加四周内边距。命中检测与布局共用此定义。
  static Rect foldArrowLocalRect({
    required int depth,
    required double indentWidth,
    required double textLineHeight,
  }) {
    return Rect.fromLTWH(
      depth * indentWidth,
      textLineHeight / 2 - foldArrowTopOffset,
      indentWidth,
      foldArrowIconSize + foldArrowPadding * 2,
    );
  }

  /// 折叠箭头图标的边长
  static const double foldArrowIconSize = 16.0;

  /// 折叠箭头四周的内边距
  static const double foldArrowPadding = 2.0;

  /// 折叠箭头相对行顶的垂直内缩偏移
  ///
  /// 箭头位于半行高再上移该偏移量处，使其视觉重心与首行文字居中对齐。
  static const double foldArrowTopOffset = 5.0;

  @override
  State<OutlineNodeTile> createState() => _OutlineNodeTileState();
}

class _OutlineNodeTileState extends State<OutlineNodeTile> {
  /// 鼠标是否悬停在节点行上
  bool _isHovered = false;

  /// 鼠标是否悬停在圆点热区上
  bool _isDotHovered = false;

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
  final PersistentSelectionOverlayPainter _persistentSelectionPainter = PersistentSelectionOverlayPainter();

  /// 当前查找匹配高亮绘制器
  ///
  /// 与持久化选区绘制器组合注入 RenderEditable，绘制在选区之上、文字之下。
  final CurrentMatchHighlightPainter _currentMatchPainter = CurrentMatchHighlightPainter();

  /// 关键词标签的锚点（相对于文本输入框左上角）
  ///
  /// 由节点文本末尾的光标矩形决定，标签紧随文本末尾排布；
  /// 为空表示尚未完成测量，此时不渲染标签。
  Rect? _keywordAnchor;

  /// 测量锚点时文本输入框的宽度
  double _keywordFieldWidth = 0;

  /// 测量锚点时文本输入框的高度
  double _keywordFieldHeight = 0;

  /// 关键词标签换行到文本下方时占用的额外高度
  double _keywordOverflowHeight = 0;

  /// 节点文本相对输入框左边缘的水平偏移
  ///
  /// 输入框的装饰内边距会让文字比输入框本身更靠右，
  /// 附加备注区据此对齐到文字左边缘而不是输入框边缘。
  double _textLeftInset = 0;

  /// 测量锚点时的文本内容
  String? _measuredText;

  /// 测量锚点时的字号
  double _measuredFontSize = 0;

  /// 测量锚点时的字体
  String _measuredFontFamily = '';

  /// 是否已排队等待测量，避免同一帧内重复排队
  bool _keywordMeasureScheduled = false;

  /// TextField 的 GlobalKey，用于查找 RenderEditable 注入 Painter
  final GlobalKey _textFieldKey = GlobalKey();

  /// 关联文本点击的判定距离
  ///
  /// 指针按下与抬起的位置超过该距离时视为拖动选择文字，不触发关联跳转。
  static const double _linkTapSlop = 6.0;

  /// 按下指针的位置（用于区分点击与拖动）
  Offset? _linkPointerDownPosition;

  /// 按下指针的时间（用于排除长按选字）
  DateTime? _linkPointerDownTime;

  /// 按下的指针是否为左键或触摸
  ///
  /// 仅左键与触摸触发关联跳转，右键交由自定义右键菜单处理。
  bool _linkPointerIsPrimary = false;

  /// 鼠标是否悬停在关联文本上
  ///
  /// 悬停时把输入框光标换成手型，提示该段文字可点击跳转。
  bool _isHoveringLink = false;

  /// 记录指针按下位置与按键类型
  void _handleLinkPointerDown(PointerDownEvent event) {
    if (widget.onLinkTap == null) return;
    _linkPointerDownPosition = event.position;
    _linkPointerDownTime = DateTime.now();
    _linkPointerIsPrimary = event.buttons == kPrimaryButton || event.kind == PointerDeviceKind.touch;
  }

  /// 指针抬起时判断是否点击了关联文本
  ///
  /// 根据按下位置、按住时长与位移排除拖动选择和长按选字，
  /// 再用命中位置换算文本偏移量，落在关联文本范围内时回调关联标识。
  void _handleLinkPointerUp(PointerUpEvent event) {
    final Offset? downPosition = _linkPointerDownPosition;
    final DateTime? downTime = _linkPointerDownTime;
    _linkPointerDownPosition = null;
    _linkPointerDownTime = null;
    final ValueChanged<String>? onLinkTap = widget.onLinkTap;
    if (onLinkTap == null || !_linkPointerIsPrimary || downPosition == null || downTime == null) return;
    // 长按用于选择文字，不触发跳转
    if (DateTime.now().difference(downTime).inMilliseconds > 300) return;
    if ((event.position - downPosition).distance > _linkTapSlop) return;

    final renderEditable = findPersistentRenderEditable(_textFieldKey);
    if (renderEditable == null || !renderEditable.attached) return;

    final int offset = renderEditable.getPositionForPoint(event.position).offset;
    final span = widget.node.linkSpanAt(offset);
    if (span == null) return;

    // 点击关联文本时把光标置于关联文本末尾，避免光标停在关联文本中间
    widget.controller.selection = TextSelection.collapsed(offset: span.end);
    onLinkTap(span.linkId);

    // 点击手势可能在本回调之后重新定位光标，帧末再校正一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final TextSelection selection = widget.controller.selection;
      if (!selection.isValid || !selection.isCollapsed) return;
      final current = widget.node.linkSpanAt(selection.start);
      if (current == null || selection.start == current.start) return;
      widget.controller.selection = TextSelection.collapsed(offset: current.end);
    });
  }

  /// 鼠标悬停在文本上时更新关联文本状态
  ///
  /// 仅在悬停状态发生变化时重建，避免鼠标移动过程中频繁刷新。
  void _handleLinkHover(PointerHoverEvent event) {
    if (widget.onLinkTap == null) {
      if (_isHoveringLink) setState(() => _isHoveringLink = false);
      return;
    }

    final renderEditable = findPersistentRenderEditable(_textFieldKey);
    if (renderEditable == null || !renderEditable.attached) return;

    final int offset = renderEditable.getPositionForPoint(event.position).offset;
    final bool hovering = widget.node.linkSpanAt(offset) != null;
    if (hovering != _isHoveringLink) {
      setState(() => _isHoveringLink = hovering);
    }
  }

  /// 鼠标离开输入框时清除关联文本悬停状态
  void _handleLinkHoverExit(PointerExitEvent event) {
    if (!_isHoveringLink) return;
    setState(() => _isHoveringLink = false);
  }

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
    _currentMatchPainter.dispose();
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
    _persistentSelectionPainter.update(selection: widget.controller.selection);
    // 文本变化会改变文本末尾位置，重新测量关键词标签锚点
    _scheduleKeywordMeasure();
  }

  /// 安排一次关键词锚点测量
  ///
  /// 测量依赖节点行完成布局后的 RenderEditable，因此延后到帧末执行；
  /// 同一帧内多次调用只排队一次。
  void _scheduleKeywordMeasure() {
    if (_keywordMeasureScheduled) return;
    _keywordMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keywordMeasureScheduled = false;
      if (!mounted) return;
      _measureKeywordAnchor();
    });
  }

  /// 测量节点文本末尾的位置，作为关键词标签的锚点
  ///
  /// 同时测量文字相对输入框左边缘的偏移，供附加备注区对齐文字左边缘。
  /// 文本、框宽或字体均未变化时跳过，避免测量结果触发无意义的重建。
  void _measureKeywordAnchor() {
    final renderEditable = findPersistentRenderEditable(_textFieldKey);
    if (renderEditable == null || !renderEditable.attached) return;
    final Size fieldSize = renderEditable.size;
    if (fieldSize.width <= 0 || fieldSize.height <= 0) return;

    // 文字实际起点与输入框左边缘的差值：输入框装饰内边距会让文字更靠右
    final RenderBox? fieldBox = _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    double textLeftInset = _textLeftInset;
    if (fieldBox != null && fieldBox.attached) {
      final double fieldLeft = fieldBox.localToGlobal(Offset.zero).dx;
      final double textLeft = renderEditable.localToGlobal(Offset.zero).dx;
      textLeftInset = (textLeft - fieldLeft).clamp(0.0, 32.0).toDouble();
    }
    final bool insetChanged = (textLeftInset - _textLeftInset).abs() > 0.5;

    final String text = widget.controller.text;
    final double fontSize = _fontSize;
    final String fontFamily = SettingsService.instance.outlineFontFamily;
    if (!insetChanged &&
        text == _measuredText &&
        fieldSize.width == _keywordFieldWidth &&
        fontSize == _measuredFontSize &&
        fontFamily == _measuredFontFamily) {
      return;
    }

    // 优先取末尾字符的紧致字形框作为锚点：光标矩形以整行行框为准，
    // 行框含有上下留白，直接使用会让标签浮到文字上方
    Rect anchorRect = renderEditable.getLocalRectForCaret(TextPosition(offset: text.length));
    if (text.isNotEmpty) {
      final List<TextBox> boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: text.length - 1, extentOffset: text.length),
      );
      if (boxes.isNotEmpty) {
        final TextBox box = boxes.last;
        anchorRect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
      }
    }

    setState(() {
      _keywordAnchor = anchorRect;
      _keywordFieldWidth = fieldSize.width;
      _keywordFieldHeight = fieldSize.height;
      _measuredText = text;
      _measuredFontSize = fontSize;
      _measuredFontFamily = fontFamily;
      _textLeftInset = textLeftInset;
      // 锚点变化后标签可能重新换行，交由测量控件重新上报占用高度
      _keywordOverflowHeight = 0;
    });
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
      // 当前匹配高亮排在选区绘制器之后，避免被选区遮盖
      overlayPainter: _currentMatchPainter,
    );
  }

  /// 将节点的查找匹配状态同步给当前匹配高亮绘制器
  void _syncCurrentMatchPainter(BuildContext context) {
    final controller = widget.controller;
    if (controller is! RichTextEditingController) return;
    _currentMatchPainter.update(
      matches: controller.findMatches,
      currentMatchIndex: controller.currentMatchIndex,
      color: FindMatchHighlighter.getCurrentMatchColor(context),
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

        // 同步当前节点的查找匹配状态，供高亮绘制器使用
        _syncCurrentMatchPainter(context);

        // 移动端折叠入口位于行尾，行首不再为折叠箭头预留列，指示区整体左移一列
        final bool isMobile = PlatformCapabilities.isMobile;
        final int columnOffset = isMobile ? -1 : 0;

        // 连接线绘制区域总宽度（包含圆点占位，减去与文本的间距缩减量）
        final connectionWidth = OutlineNodeTile.connectionWidthForDepth(
          depth,
          indentWidth: indentWidth,
          dotTextGapReduction: widget.dotTextGapReduction,
        );

        // 圆点颜色
        final dotColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

        // 当前编辑节点的点亮色
        final activeColor = colorScheme.primary.withValues(alpha: 0.6);

        // 折叠态圆点外轮廓色：与圆点同色但更透明，作为子节点被收起的视觉提示
        final collapsedDotBackground = colorScheme.onSurfaceVariant.withValues(alpha: 0.1);

        // 节点行内容：文本输入区与附加备注区
        // 底部间距纳入内容区高度，使连接线的 Positioned 能覆盖间距区域
        // 右侧留白由外层内容区的内边距统一承担，为行尾竖条与左右边距预留空间
        final Widget rowContent = Padding(
          padding: EdgeInsets.only(left: connectionWidth, bottom: widget.nodeSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNodeTextArea(node, colorScheme),
              // 图片与备注位于节点文字下方，与文字左对齐
              if (node.note.isNotEmpty ||
                  widget.imagePath.isNotEmpty ||
                  widget.isEditingNote)
                OutlineNodeAttachment(
                  key: widget.attachmentKey,
                  note: node.note,
                  imagePath: widget.imagePath,
                  colorScheme: colorScheme,
                  // 备注字号比设置的大纲字号小 4 号
                  noteFontSize: (SettingsService.instance.outlineFontSize - 4)
                      .clamp(8.0, 72.0)
                      .toDouble(),
                  // 对齐节点文字左边缘
                  textLeftInset: _textLeftInset,
                  readOnly: widget.readOnly || widget.isBatchMode,
                  isEditingNote: widget.isEditingNote,
                  onNoteChanged: widget.onNoteChanged,
                  onStartNoteEdit: widget.onStartNoteEdit,
                  onStopNoteEdit: widget.onStopNoteEdit,
                  onDeleteImage: widget.onDeleteNodeImage,
                ),
            ],
          ),
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
              // 圆点外轮廓的悬停动效：折叠态从基础半径向外扩大，展开态从圆点内部向外扩大
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: _isDotHovered ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                builder: (context, hoverProgress, _) {
                  final bool collapsed = hasChildren && !node.isExpanded;

                  // 折叠动画期间圆点外轮廓半径随进度连续变化：
                  // 收起时轮廓由小到大展开，展开时反向收拢，与子节点行的收放过程同步
                  Widget paintConnection(double foldProgress) {
                    final double baseRadius = widget.dotFoldProgress != null
                        ? OutlineConnectionMetrics.collapsedDotBackgroundRadius * (1 - foldProgress)
                        : (collapsed ? OutlineConnectionMetrics.collapsedDotBackgroundRadius : 0.0);
                    final double outlineRadius = baseRadius +
                        (OutlineConnectionMetrics.hoverDotBackgroundRadius - baseRadius) * hoverProgress;

                    return CustomPaint(
                      painter: OutlineConnectionPainter(
                        depth: depth,
                        columnOffset: columnOffset,
                        indentWidth: indentWidth,
                        textLineHeight: _textLineHeight,
                        lineColor: lineColor,
                        dotColor: dotColor,
                        // 移动端圆点整体上移两个像素，与行尾竖条折叠三角的视觉重心对齐
                        dotVerticalOffset: OutlineConnectionMetrics.dotVerticalOffset - (isMobile ? 2.0 : 0.0),
                        // 折叠态与悬停态共用同一圈轮廓，只改变半径大小
                        dotOutlineColor: collapsedDotBackground,
                        dotOutlineRadius: outlineRadius,
                        // 当前编辑节点的圆点点亮
                        activeDotColor: widget.isActiveNode ? activeColor : null,
                        // 当前编辑节点圆点下方连接线的点亮
                        siblingLineHighlight: widget.highlightedLineColumn == null
                            ? null
                            : OutlineSiblingLineHighlight(column: widget.highlightedLineColumn!, color: activeColor),
                      ),
                    );
                  }

                  final Animation<double>? dotFold = widget.dotFoldProgress;
                  if (dotFold == null) return paintConnection(1.0);
                  // 折叠动画期间逐帧刷新圆点轮廓半径
                  return AnimatedBuilder(
                    animation: dotFold,
                    builder: (context, _) => paintConnection(dotFold.value.clamp(0.0, 1.0)),
                  );
                },
              ),
            ),
            // 箭头交互层（桌面端有子节点时叠加在连接线上方）
            if (hasChildren && !isMobile) _buildArrowButton(node, colorScheme, indentWidth),
            // 圆点交互热区：点击进入该节点主题，长按进入拖拽排序，位于箭头之上以便优先响应
            if (widget.onDotDragStart != null || widget.onDotTap != null) _buildDotHandle(columnOffset),
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
              ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onBatchTap, child: row)
              : row,
        );

        final Widget tile = Opacity(
          // 拖拽排序时整行变淡，提示该节点正在被移动
          opacity: widget.isDragging ? 0.4 : 1.0,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: ColoredBox(
              // 选中节点时显示高亮背景
              color: widget.isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
              child: isMobile
                  // 行尾竖条叠加在内容区之上并贴到编辑区右边缘，不随左右边距设置移动
                  ? Stack(children: [content, _buildTrailingBar(node, colorScheme)])
                  : content,
            ),
          ),
        );

        // 折叠动画中的子节点行向父节点圆点收拢
        return _buildFoldAnimatedRow(tile);
      },
    );
  }

  /// 构建节点行的折叠动画包装
  ///
  /// 子节点行收起时整行向目标圆点缩放并淡出，同时把高度收缩为 0，
  /// 使下方节点行平滑上移填补空出的位置；展开时按相反方向播放同一进度。
  /// 未处于折叠动画中时原样返回 [child]。
  Widget _buildFoldAnimatedRow(Widget child) {
    final Animation<double>? fold = widget.subtreeFoldProgress;
    if (fold == null) return child;

    return AnimatedBuilder(
      animation: fold,
      // 动画期间节点行不响应交互，避免收缩中的行抢占点击
      child: IgnorePointer(child: child),
      builder: (context, child) {
        // 缓动后的进度同时驱动高度收缩、缩放与淡出，使收拢过程先慢后快
        final double progress = Curves.easeInOutCubic.transform(fold.value.clamp(0.0, 1.0));

        return LayoutBuilder(
          builder: (context, constraints) {
            // 缩放中心落在目标圆点上：横向取圆点所在列，纵向取行顶部（收起方向的上方）
            final int dotDepth = widget.foldTargetDotDepth ?? widget.depth;
            final int columnOffset = PlatformCapabilities.isMobile ? -1 : 0;
            final double dotCenterX = (dotDepth + 1 + columnOffset) * widget.indentWidth + widget.indentWidth / 2;
            final double rowWidth = constraints.maxWidth;
            final Alignment target = Alignment(rowWidth > 0 ? (dotCenterX / rowWidth) * 2 - 1 : -1.0, -1.0);
            // 收起完成时本行顶部恰好落在父节点行底部，再向上偏移即可到达父节点圆点
            final double targetOffsetY =
                -(_textLineHeight / 2 - OutlineConnectionMetrics.dotVerticalOffset + widget.nodeSpacing);

            return Align(
              alignment: Alignment.topLeft,
              heightFactor: progress,
              child: Transform.translate(
                // 收拢过程中内容逐渐上移，末端汇聚到父节点圆点
                offset: Offset(0, targetOffsetY * (1 - progress)),
                child: Transform.scale(
                  scale: 0.2 + 0.8 * progress,
                  alignment: target,
                  child: Opacity(opacity: progress, child: child),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 构建节点文本区
  ///
  /// 关键词标签按文本末尾位置排布：末行剩余空间足够时紧跟其后，
  /// 不足时换到文本下方，并通过底部内边距为标签预留高度，避免压住下一节点。
  Widget _buildNodeTextArea(OutlineNode node, ColorScheme colorScheme) {
    // 文本、字体或关键词变化后重新测量锚点（帧末执行，内部按指纹去重）
    _scheduleKeywordMeasure();

    final Widget textField = Padding(
      // 没有关键词时忽略历史遗留的预留高度，避免节点行下方多出空白
      padding: EdgeInsets.only(bottom: node.keywords.isEmpty ? 0 : _keywordOverflowHeight),
      child: _buildTextField(node, colorScheme),
    );

    final Rect? anchor = _keywordAnchor;
    // 锚点必须与当前文本和字体一致，否则说明尚未重新测量，先不绘制避免错位
    if (anchor == null || !_isKeywordAnchorCurrent()) return textField;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        textField,
        if (node.keywords.isNotEmpty) _buildKeywordTags(node, colorScheme, anchor),
      ],
    );
  }

  /// 当前锚点是否对应当前文本与字体
  bool _isKeywordAnchorCurrent() {
    return _measuredText == widget.controller.text &&
        _measuredFontSize == _fontSize &&
        _measuredFontFamily == SettingsService.instance.outlineFontFamily;
  }

  /// 关键词标签的字号
  double get _keywordTagFontSize => (_fontSize - 5).clamp(8.0, 10.0).toDouble();

  /// 计算关键词标签组的摆放位置
  ///
  /// 锚点取末尾字符的紧致字形框，末行剩余宽度足够时紧跟文本末尾，
  /// 否则另起一行放在文本起始位置。
  ({double left, double top, double width}) _keywordTagLayout(Rect anchor) {
    // 与文末文字留出间距，避免标签紧贴文本
    const double gap = 24;
    // 末行剩余空间小于该值时换行，避免标签被挤压成多行碎片
    const double minInlineWidth = 80;
    final double remaining = _keywordFieldWidth - anchor.right - gap;
    if (remaining >= minInlineWidth) {
      // 以文字顶部为基准整体下移，偏移随字号等比变化，
      // 保证任意字号下标签与文字的相对位置一致
      final double verticalOffset = _fontSize * 0.32;
      return (left: anchor.right + gap, top: anchor.top + verticalOffset, width: remaining);
    }
    return (left: 0, top: anchor.bottom + 2, width: _keywordFieldWidth);
  }

  /// 构建节点关键词标签组
  Widget _buildKeywordTags(OutlineNode node, ColorScheme colorScheme, Rect anchor) {
    final layout = _keywordTagLayout(anchor);

    return Positioned(
      left: layout.left,
      top: layout.top,
      width: layout.width,
      child: MeasureSize(
        onSizeChanged: (size) {
          // 标签超出文本区底部时补足底部内边距，避免压住下一节点
          final double overflow = layout.top + size.height + 2 - _keywordFieldHeight;
          final double height = overflow > 0 ? overflow : 0.0;
          if ((height - _keywordOverflowHeight).abs() <= 0.5 || !mounted) return;
          setState(() => _keywordOverflowHeight = height);
        },
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final keyword in node.keywords) _buildKeywordTag(keyword, colorScheme)],
        ),
      ),
    );
  }

  /// 构建单个关键词标签
  ///
  /// 采用胶囊样式：关键词色淡底 + 同色描边 + 前置小圆点与文字，
  /// 颜色按主题明暗做可读性调整。
  Widget _buildKeywordTag(OutlineKeyword keyword, ColorScheme colorScheme) {
    final bool isDark = colorScheme.brightness == Brightness.dark;
    final Color accent = OutlineColorPalette.readableTextColor(keyword.color, colorScheme.brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              keyword.keyword,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: SettingsService.instance.outlineFontFamily,
                fontSize: _keywordTagFontSize,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ),
        ],
      ),
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
        // 通过 DefaultSelectionStyle 注入选区底色，使节点文本选区与正文编辑器使用同一套配色
        child: DefaultSelectionStyle.merge(
          selectionColor: computeFocusedSelectionColor(colorScheme),
          // 悬停关联文本时切换为手型光标，提示该段文字可点击跳转
          child: MouseRegion(
            opaque: false,
            onHover: _handleLinkHover,
            onExit: _handleLinkHoverExit,
            // 关联文本点击检测需要原始指针位置与位移，故在输入框外层监听指针事件
            child: Listener(
              onPointerDown: _handleLinkPointerDown,
              onPointerUp: _handleLinkPointerUp,
              child: TextField(
                key: _textFieldKey,
                controller: widget.controller,
                focusNode: widget.focusNode,
                readOnly: widget.readOnly,
                // 悬停关联文本时显示手型，其余位置保持文本光标
                mouseCursor: _isHoveringLink ? SystemMouseCursors.click : SystemMouseCursors.text,
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
          ),
        ),
      ),
    );
  }

  /// 构建移动端文字选择工具栏
  ///
  /// 长按选中文字后在选区上方弹出，提供剪切、复制、粘贴、全选四项操作；
  /// 无选中文字时仅保留粘贴与全选，只读节点仅保留复制与全选。
  Widget _buildMobileSelectionToolbar(BuildContext context, EditableTextState editableTextState) {
    final bool hasSelection =
        editableTextState.textEditingValue.selection.isValid &&
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
            SizedBox(width: indentWidth, height: _textLineHeight / 2 - OutlineNodeTile.foldArrowTopOffset),
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
                    padding: const EdgeInsets.all(OutlineNodeTile.foldArrowPadding),
                    child: AnimatedRotation(
                      turns: node.isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: OutlineNodeTile.foldArrowIconSize,
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

  /// 构建圆点交互热区
  ///
  /// 热区以圆点为中心覆盖圆点周边的小块区域：点击进入该节点的主题视图，
  /// 长按进入拖拽排序；按住移动时把指针的全局坐标交给调用方，由调用方按位置计算落点
  Widget _buildDotHandle(int columnOffset) {
    // 热区边长：需覆盖圆点周边的空白，同时避免过度侵入右侧文本输入区
    const double hitSize = 20.0;

    // 圆点中心在节点行内的坐标，与连接线绘制器使用同一坐标系
    final double dotCenterX = (widget.depth + 1 + columnOffset) * widget.indentWidth + widget.indentWidth / 2;
    final double dotCenterY =
        _textLineHeight / 2 + OutlineConnectionMetrics.dotVerticalOffset - (PlatformCapabilities.isMobile ? 2.0 : 0.0);

    return Positioned(
      left: dotCenterX - hitSize / 2,
      top: dotCenterY - hitSize / 2,
      width: hitSize,
      height: hitSize,
      child: MouseRegion(
        // 桌面端使用手型光标，提示圆点可交互；移动端不显示光标
        cursor: PlatformCapabilities.isMobile ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isDotHovered = true),
        onExit: (_) => setState(() => _isDotHovered = false),
        child: GestureDetector(
          // 空白处同样响应手势，保证整个热区都是有效的交互热区
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDotTap,
          onLongPressStart: (details) => widget.onDotDragStart?.call(details.globalPosition),
          onLongPressMoveUpdate: (details) => widget.onDotDragMove?.call(details.globalPosition),
          onLongPressEnd: (_) => widget.onDotDragEnd?.call(),
          onLongPressCancel: () => widget.onDotDragCancel?.call(),
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
        onTap: widget.isBatchMode ? widget.onBatchTap : (hasChildren ? widget.onToggleExpand : null),
        onLongPressStart: (details) => widget.onTrailingBarLongPress(details.globalPosition),
        onLongPressMoveUpdate: (details) => widget.onTrailingBarLongPressMove(details.globalPosition),
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
                    child: Icon(Icons.arrow_drop_down, size: _trailingBarIconSize, color: iconColor),
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
class _OutlineNodeSelectionControls extends MaterialTextSelectionControls with TextSelectionHandleControls {
  @override
  Widget buildHandle(BuildContext context, TextSelectionHandleType type, double textHeight, [VoidCallback? onTap]) {
    if (type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    return super.buildHandle(context, type, textHeight, onTap);
  }
}

/// 大纲节点输入框在 Android 上使用的文字选择控件实例
final TextSelectionControls _outlineNodeSelectionControls = _OutlineNodeSelectionControls();

