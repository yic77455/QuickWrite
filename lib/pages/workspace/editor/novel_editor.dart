import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/workspace/custom_highlight_service.dart';
import 'package:quick_write/core/utils/chinese_word_segmenter.dart';
import 'package:quick_write/core/utils/clean_scroll.dart';
import 'package:quick_write/core/utils/clipboard_state_cache.dart';
import 'package:quick_write/core/utils/code_line_selection_utils.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/editor_scroll_helper.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/re_editor_span_builder.dart';
import 'package:quick_write/pages/workspace/editor/utils/re_editor_indent_policy.dart';
import 'package:quick_write/pages/workspace/editor/widgets/re_editor_ime_reporter.dart';
import 'package:quick_write/shared/widgets/context_menu.dart';
import 'package:re_editor/re_editor.dart';

/// 小说编辑器
///
/// 基于 re_editor 实现的小说专用编辑器。
/// 编辑器高度随正文篇幅自适应，纸张背景、页边距与滚动统一由外层容器负责。
class NovelEditor extends StatefulWidget {
  /// 章节正文编辑控制器
  final CodeLineEditingController controller;

  /// 章节标题编辑控制器（备份预览标签页为 null）
  final TextEditingController? chapterTitleController;

  /// 行样式构建器（负责排版注入与高亮着色）
  final ReEditorSpanBuilder? spanBuilder;

  /// 文本变化事件回调
  final OnEditEvent? onEditEvent;

  /// 章节标题变化回调
  final ValueChanged<String>? onChapterTitleChanged;

  /// 颜色方案
  final ColorScheme colorScheme;

  /// 初始滚动位置
  final double initialScrollOffset;

  /// 滚动位置变化回调
  final ValueChanged<double>? onScrollOffsetChanged;

  /// 初始光标位置
  final TextSelection? initialSelection;

  /// 光标位置变化回调（使用扁平偏移量）
  final ValueChanged<TextSelection>? onSelectionChanged;

  /// 首次加载时是否跳转到光标位置
  ///
  /// true：打开章节后自动跳转到光标位置（用于"定位至章末"等场景）
  /// false：保持初始滚动位置（默认行为）
  final bool initialScrollToCursor;

  /// 保存回调（Ctrl+S 触发）
  final VoidCallback? onSave;

  /// 当前标签页是否处于激活（可见）状态
  final bool isActive;

  /// 额外顶边距（用于查找替换浮窗出现时，在编辑器顶部留出空白防止遮挡文字）
  final double extraTopPadding;

  /// 是否为只读模式（备份预览标签页为只读）
  final bool readOnly;

  const NovelEditor({
    super.key,
    required this.controller,
    this.chapterTitleController,
    this.spanBuilder,
    this.onEditEvent,
    this.onChapterTitleChanged,
    required this.colorScheme,
    this.initialScrollOffset = 0.0,
    this.onScrollOffsetChanged,
    this.initialSelection,
    this.onSelectionChanged,
    this.initialScrollToCursor = false,
    this.onSave,
    this.isActive = true,
    this.extraTopPadding = 0.0,
    this.readOnly = false,
  });

  @override
  State<NovelEditor> createState() => NovelEditorState();
}

class NovelEditorState extends State<NovelEditor> with WidgetsBindingObserver {
  /// 大段粘贴阈值（不小于此值的文本在粘贴时统一换行符）
  static const int _largeTextThreshold = 5000;

  /// 光标宽度
  static const double _cursorWidth = 2.0;

  /// 正文左内边距
  ///
  /// 光标以字符边界为中心绘制，正文最左侧的光标会有一半落在视口裁剪区外，
  /// 因此留出等于光标半宽的内边距，保证行首光标完整可见。
  static const double _contentLeftInset = _cursorWidth / 2 + 0.5;

  /// 纸张模式下纸张容器的左右间距补偿（像素）
  static const double _paperHorizontalCompensation = 16.0;

  /// 正文标点的成对符号表
  ///
  /// 由标点符号表推导，与快捷输入栏的按键共用同一数据源。
  static final List<CodeSymbolPair> _punctuationPairs = [
    for (final symbol in PunctuationSymbols.quickInputKeys)
      if (symbol.isPairStart) CodeSymbolPair(symbol.symbol, symbol.closing!),
  ];

  /// 程序化文本改写的抑制深度
  ///
  /// 备份恢复、段落整理等场景在改写全文期间递增该计数，
  /// 编辑器据此跳过编辑事件上报，避免程序化改写被误计为键盘输入。
  static int _silentWriteDepth = 0;

  /// 在不触发编辑事件的前提下执行文本改写
  static void runSilently(VoidCallback action) {
    _silentWriteDepth++;
    try {
      action();
    } finally {
      _silentWriteDepth--;
    }
  }

  /// 编辑器滚动控制器（作为 re_editor 的纵向滚动控制器）
  late final SyncScrollController _scrollController;

  /// re_editor 的双向滚动控制器
  late final CodeScrollController _codeScrollController;

  /// 编辑器滚动保护器
  late final EditorScrollGuard _scrollGuard;

  /// 段落缩进策略
  late final ReEditorIndentPolicy _indentPolicy;

  /// 焦点节点
  final FocusNode _focusNode = FocusNode();

  /// 章节标题区域的测量键
  final GlobalKey _titleAreaKey = GlobalKey();

  /// 章节标题区域（标题及其顶边距）的高度
  ///
  /// 标题与正文同屏滚动，其高度需计入编辑器顶部留白，由布局完成后测量得到。
  double _titleAreaHeight = 0;

  /// 标题区域测量是否已排队，避免同一帧内重复排队
  bool _titleAreaMeasureScheduled = false;

  /// 选择工具栏控制器
  ///
  /// 桌面端右键弹出应用自定义的菜单，移动端长按弹出系统风格的选择工具栏。
  late final SelectionToolbarController _toolbarController;

  /// 自定义高亮服务引用（用于监听配置变化触发重绘）
  CustomHighlightService? _customHighlightService;

  /// 待消费的编辑事件类型
  ///
  /// 程序化编辑（撤销、粘贴、剪切等）在执行前先置入类型，
  /// 由内容变化监听消费，从而把事件来源准确传给码字统计。
  NovelEditType? _pendingEditType;

  /// 上一次的内容行数据引用
  ///
  /// 仅移动光标时 re_editor 不会重建行数据，据此区分"内容变化"与"选区变化"。
  CodeLines? _lastCodeLines;

  /// 上一次向外通知的选区委
  TextSelection? _lastSelection;

  /// 用于记录需要在 Layout 阶段补偿的额外顶边距变化量
  double? _pendingExtraPaddingDelta;

  /// 待对齐末行的标记
  ///
  /// 内容在末行增长时置位，由 [SyncScrollPosition.applyContentDimensions]
  /// 在布局阶段消费，使滚动修正与当帧渲染一并生效，不出现先渲染再滚动的二次跳动。
  bool _pendingBottomAlignment = false;

  /// 末行与视口底部之间保留的底边距
  ///
  /// 由布局过程按设置换算（视口高度 × 底边距百分比），供末行对齐使用。
  double _resolvedBottomPadding = 0;

  /// 滚动内容在纸张下方留出的空白高度
  ///
  /// 用于显露纸张下边缘；末行对齐时需一并计入，否则纸张下边缘会被推进视口之外。
  double _resolvedBottomGap = 0;

  /// 页边距换算所依据的编辑区高度
  ///
  /// 页边距按视口高度的百分比换算，而软键盘升降会压缩编辑区高度；
  /// 若直接采用实时高度，键盘动画期间正文会随之上下移动。
  /// 此处记录键盘收起时的编辑区高度作为基准，键盘弹出期间沿用该基准。
  double _marginBasisHeight = 0;

  /// 上一次的高亮摘要
  ///
  /// 查找匹配变化不会改变编辑器属性，需要据此主动请求重绘以刷新高亮。
  int? _lastHighlightHash;

  /// 上一次的内容长度
  ///
  /// 用于判断文本是否增长，进而在末行输入时维持底边距这一安全距离。
  int _previousTextLength = 0;

  /// 首次加载时光标定位的待处理标记
  bool _pendingScrollToCursor = false;

  /// 缓存窗口最小化状态，用于检测从最小化恢复的情况
  bool _wasMinimized = false;

  /// 输入法光标上报器的状态键
  ///
  /// 布局阶段修正滚动位置后需要立即刷新输入法坐标，
  /// 通过它直接触发上报，避免候选框停留在滚动前的位置。
  final GlobalKey<ReEditorImeReporterState> _imeReporterKey =
      GlobalKey<ReEditorImeReporterState>();

  /// 缓存软键盘高度，用于识别键盘新升起导致的视口压缩
  double _keyboardHeight = 0;

  /// 视口尺寸变化后合并重绘的延迟
  static const Duration _viewportRepaintDelay = Duration(milliseconds: 120);

  /// 待执行的视口重绘任务
  Timer? _viewportRepaintTimer;

  /// 快捷键覆盖动作缓存
  Map<Type, Action<Intent>>? _shortcutOverrides;

  /// 缓存快捷键覆盖动作时所用的工作台 Provider
  WorkspaceProvider? _shortcutOverridesProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = SyncScrollController(onApplyContentDimensions: _onApplyContentDimensions);
    _codeScrollController = CodeScrollController(verticalScroller: _scrollController);
    _scrollGuard = EditorScrollGuard(_scrollController);
    _scrollController.addListener(_onScrollChanged);
    _indentPolicy = ReEditorIndentPolicy(controller: widget.controller);
    _toolbarController = PlatformCapabilities.isMobile
        ? MobileSelectionToolbarController(builder: _buildMobileSelectionToolbar)
        : _EditorToolbarController(onShowMenu: _showContextMenuAt);
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
    _lastCodeLines = widget.controller.value.codeLines;
    _previousTextLength = widget.controller.text.length;

    // 加载中文词库，为双击选词提供分词能力
    ChineseWordSegmenter.instance.install();

    // 打开章节时按需定位到光标位置（如"定位至章末""上一次编辑位置"）
    if (widget.initialScrollToCursor) {
      _pendingScrollToCursor = true;
    }

    // 如果初始化时处于激活状态，请求焦点
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusEditor();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听设置变化（页边距、行间线、排版等）
    SettingsService.instance.addListener(_onSettingsChanged);
    // 监听自定义高亮配置变化（service 随书籍工作台绑定，切换书籍时需重新绑定）
    final CustomHighlightService newService = context.read<WorkspaceProvider>().customHighlightService;
    if (!identical(newService, _customHighlightService)) {
      _customHighlightService?.removeListener(_onSettingsChanged);
      _customHighlightService = newService;
      _customHighlightService!.addListener(_onSettingsChanged);
    }
  }

  @override
  void dispose() {
    _viewportRepaintTimer?.cancel();
    _scrollGuard.dispose();
    _scrollController.removeListener(_onScrollChanged);
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    SettingsService.instance.removeListener(_onSettingsChanged);
    _customHighlightService?.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    _codeScrollController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(NovelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当标签页由不可见变为可见时，自动请求焦点
    if (widget.isActive && !oldWidget.isActive) {
      // 开启滚动保护（锁定当前滚动位置，防止 requestFocus 导致的自动滚动）
      _scrollGuard.protect(const Duration(milliseconds: 150));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusEditor();
        }
      });
    }

    // 当额外顶边距变化时（如查找替换栏显示/隐藏），在 Layout 阶段补偿滚动偏移量防止内容跳动
    if (widget.extraTopPadding != oldWidget.extraTopPadding) {
      final double delta = widget.extraTopPadding - oldWidget.extraTopPadding;
      if (delta != 0) {
        _pendingExtraPaddingDelta = delta;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 开启滚动保护，防止应用从后台恢复时编辑器自动滚动到光标位置
    if (state == AppLifecycleState.resumed) {
      _scrollGuard.protect(const Duration(milliseconds: 300));
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 移动端软键盘升降会改变视口高度，度量变化当帧尚未完成布局，
    // 视口尺寸需等布局结束后才能取得，因此统一在帧末处理
    if (PlatformCapabilities.isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectionWhenKeyboardShown());
    }
  }

  /// 软键盘新升起时把选区所在行滚入视口
  ///
  /// 仅在键盘高度增加且编辑器持有焦点时滚动，使被选中文字落到键盘上方的可见区域内；
  /// 选区行本就可见时不产生任何滚动。
  /// 键盘高度取自窗口视图的原始内边距：Scaffold 按键盘高度收缩本子树时，
  /// 会一并剔除子树 MediaQuery 中的底部内边距，从 MediaQuery 读取无法识别键盘升降。
  void _revealSelectionWhenKeyboardShown() {
    if (!mounted) return;
    final double keyboardHeight = View.of(context).viewInsets.bottom;
    final double previousHeight = _keyboardHeight;
    _keyboardHeight = keyboardHeight;
    if (keyboardHeight <= previousHeight || keyboardHeight <= 0 || !_focusNode.hasFocus) return;
    // 滚动前解除滚动保护，避免保护逻辑把位置拉回旧的滚动值导致定位无效
    _scrollGuard.unprotect();
    widget.controller.makeCursorCenterIfInvisible();
  }

  /// 合并同一轮视口尺寸变化，仅在尺寸稳定后重绘一次
  ///
  /// 连续重绘会让可见行逐次重新排版，代价远高于单次重绘，故把中间过程合并掉。
  void _scheduleViewportRepaint() {
    _viewportRepaintTimer?.cancel();
    _viewportRepaintTimer = Timer(_viewportRepaintDelay, () {
      if (mounted) widget.controller.forceRepaint();
    });
  }

  /// 滚动到当前光标/选区位置
  ///
  /// 供外部调用（如查找替换导航时），使编辑器滚动到当前选区所在位置
  void scrollToCursor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 滚动前解除滚动保护，避免保护逻辑把位置拉回旧的滚动值导致定位无效
      _scrollGuard.unprotect();
      widget.controller.makeCursorCenterIfInvisible();
    });
  }

  /// 请求编辑器获取焦点（统一入口）
  ///
  /// 移动端不主动唤起输入法，需由用户点击编辑区自行聚焦，因此移动端直接忽略
  void _focusEditor() {
    if (PlatformCapabilities.isMobile) return;
    _focusNode.requestFocus();
  }

  /// 请求编辑器获取焦点
  ///
  /// 供外部调用（如关闭查找替换栏后），将焦点归还给编辑器
  void requestEditorFocus() {
    _scrollGuard.unprotect();
    _focusEditor();
  }

  /// 编辑器当前是否持有焦点
  ///
  /// 供外部（如移动端快捷输入栏）判断输入法是否由本编辑器唤起。
  bool get hasEditorFocus => _focusNode.hasFocus;

  /// 设置变化时刷新样式并重绘
  void _onSettingsChanged() {
    if (!mounted) return;
    // 标题字号、标题显隐等设置会改变标题区域高度，需要重新测量
    if (widget.chapterTitleController != null && SettingsService.instance.showChapterTitle) {
      _scheduleTitleAreaMeasure();
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.forceRepaint();
    });
  }

  /// 编辑器当前的滚动位置
  ///
  /// 编辑器滚动视图重建的同一帧内，滚动控制器可能短暂挂载新旧两个位置，
  /// 此时读取偏移会触发断言，因此仅在恰好挂载一个位置时返回。
  ScrollPosition? get _editorScrollPosition {
    final List<ScrollPosition> positions = _scrollController.positions.toList();
    return positions.length == 1 ? positions.first : null;
  }

  /// 滚动位置变化时通知父组件
  void _onScrollChanged() {
    if (widget.onScrollOffsetChanged == null) return;
    final ScrollPosition? position = _editorScrollPosition;
    if (position != null) {
      widget.onScrollOffsetChanged!(position.pixels);
    }
  }

  /// 内容或选区变化时通知父组件
  void _onControllerChanged() {
    if (!mounted) return;
    final CodeLineEditingValue value = widget.controller.value;

    // 选区变化：换算为扁平偏移量后向外通知
    final TextSelection flatSelection = CodeLineSelectionUtils.flatSelectionOf(widget.controller.text, value.selection);
    if (flatSelection != _lastSelection) {
      _lastSelection = flatSelection;
      widget.onSelectionChanged?.call(flatSelection);
    }

    // 仅移动光标时行数据引用不变，此时不视为内容变化
    if (identical(value.codeLines, _lastCodeLines)) return;
    _lastCodeLines = value.codeLines;

    // 同步刷新高亮解析缓存
    //
    // 高亮范围以全文偏移量表示，必须在渲染前按最新文本重算；
    // 否则旧偏移量被套用到新文本上会出现整段错位（插入点之后全部着色、
    // 或被后推的引号失去高亮），直至下一次重建才恢复。
    widget.spanBuilder?.update(context: context, text: widget.controller.text);

    // 程序化改写全文（备份恢复、段落整理）不计入编辑事件
    if (_silentWriteDepth > 0) return;

    // 内容增长时维持底边距这一安全距离
    final int currentLength = widget.controller.text.length;
    final bool isTextGrown = currentLength > _previousTextLength;
    _previousTextLength = currentLength;
    if (isTextGrown) _keepBottomPaddingVisible();

    final NovelEditType type = _pendingEditType ?? NovelEditType.keyboard;
    _pendingEditType = null;
    widget.onEditEvent?.call(type);
  }

  /// 标记末行需要在布局阶段对齐底边距
  ///
  /// 光标位于最后一行时，内容增长会把最后一行向下推挤甚至顶出视口；
  /// 置位后由布局阶段把滚动位置调整到「末行底部 + 底边距 与视口底部对齐」处，
  /// 使最后一行在视口中的位置保持稳定。
  void _keepBottomPaddingVisible() {
    if (widget.controller.selection.extentIndex < widget.controller.codeLines.length - 1) {
      return;
    }

    _pendingBottomAlignment = true;
  }

  /// 焦点变化时触发
  ///
  /// 窗口最小化恢复或从其他应用切回时开启短暂的滚动保护，避免不期望的跳动。
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _scrollGuard.protect(const Duration(milliseconds: 150));
    }
    // 选区颜色随焦点变化（失焦时灰显），需要重建编辑器
    if (mounted) setState(() {});
  }

  /// 在 Layout 阶段修正滚动像素
  ///
  /// 修正发生在 Paint 之前，因此结果随当帧一并呈现，不会出现先渲染再滚动的二次跳动。
  /// 一是补偿额外顶边距变化导致的滚动偏移，二是让末行连同底边距对齐视口底部。
  void _onApplyContentDimensions(ScrollPosition position, double minExt, double maxExt) {
    bool corrected = false;
    if (_pendingExtraPaddingDelta != null) {
      final double targetOffset = (position.pixels + _pendingExtraPaddingDelta!).clamp(minExt, maxExt);
      if ((position.pixels - targetOffset).abs() > 0.5) {
        position.correctPixels(targetOffset);
        corrected = true;
      }
      _pendingExtraPaddingDelta = null;
    }
    if (_pendingBottomAlignment) {
      _pendingBottomAlignment = false;
      if (_alignLastLineWithBottomPadding(position, minExt, maxExt)) {
        corrected = true;
      }
    }
    // 滚动位置改变后光标在屏幕上的位置随之变化，需要在当帧内刷新输入法坐标：
    // 若等到下一帧，输入法会先按滚动前的位置显示候选框，再跳回正确位置
    if (corrected) {
      _imeReporterKey.currentState?.reportNow();
    }
  }

  /// 让末行连同其下方的底边距与纸张下留白对齐视口底部
  ///
  /// 目标偏移取「末行底部 + 编辑区底边距 + 纸张下留白 − 视口高度」：
  /// 末行尚未顶到视口底部时该值小于当前偏移，不产生滚动；
  /// 正文未撑满视口（滚动内容由纸张最小页高撑起）时该值同样不足视口高度，视口不会被推到纸张末尾；
  /// 正文撑满视口后，滚动内容的下边缘即末行下方的这段留白，
  /// 该值等于滚动内容的最大偏移，末行、纸张下边缘与其外留白一并对齐视口底部。
  bool _alignLastLineWithBottomPadding(ScrollPosition position, double minExt, double maxExt) {
    final double? lineBottom = _codeScrollController.contentBottomOfLine(widget.controller.codeLines.length - 1);
    if (lineBottom == null) return false;
    final double bottomMargin = _resolvedBottomPadding + _resolvedBottomGap;
    final double targetOffset = (lineBottom + bottomMargin - position.viewportDimension).clamp(minExt, maxExt);
    if (targetOffset > position.pixels + 0.5) {
      position.correctPixels(targetOffset);
      return true;
    }
    return false;
  }

  /// 执行一次程序化编辑并标注事件来源
  ///
  /// 编辑引起内容变化时由 [_onControllerChanged] 消费类型；
  /// 未引起变化（如撤销栈为空）时标记作废，不触发统计。
  void _runEdit(NovelEditType type, VoidCallback operation) {
    _pendingEditType = type;
    operation();
    _pendingEditType = null;
  }

  /// 是否可撤销（只读模式下不可撤销）
  bool get canUndo => !widget.readOnly && widget.controller.canUndo;

  /// 是否可重做（只读模式下不可重做）
  bool get canRedo => !widget.readOnly && widget.controller.canRedo;

  /// 撤销
  void undo() {
    if (widget.readOnly || !widget.controller.canUndo) return;
    _runEdit(NovelEditType.undo, widget.controller.undo);
    widget.controller.makeCursorCenterIfInvisible();
  }

  /// 重做
  void redo() {
    if (widget.readOnly || !widget.controller.canRedo) return;
    _runEdit(NovelEditType.redo, widget.controller.redo);
    widget.controller.makeCursorCenterIfInvisible();
  }

  /// 剪切
  void _cut() {
    if (widget.readOnly) return;
    _runEdit(NovelEditType.cut, widget.controller.cut);
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();
  }

  /// 复制
  void _copy() {
    widget.controller.copy();
    ClipboardStateCache.markHasContent();
  }

  /// 删除选中内容
  void _delete() {
    if (widget.readOnly) return;
    _runEdit(NovelEditType.delete, widget.controller.deleteSelection);
  }

  /// 在光标处插入文本片段
  ///
  /// 插入会替换当前选区，插入后光标定位到片段内的 [caretOffsetInText] 处
  /// （为空时落在片段末尾），用于插入成对符号并把光标置于两条符号之间；
  /// 该替换按键盘输入计入编辑事件。
  void insertText(String text, {int? caretOffsetInText}) {
    if (widget.readOnly || text.isEmpty) return;
    final String currentText = widget.controller.text;
    final TextSelection flatSelection = CodeLineSelectionUtils.flatSelectionOf(currentText, widget.controller.selection);
    final int insertOffset = flatSelection.start;
    _runEdit(NovelEditType.keyboard, () {
      widget.controller.replaceSelection(text);
    });
    final String updatedText = widget.controller.text;
    widget.controller.selection = CodeLineSelectionUtils.collapsedSelection(
      updatedText,
      (insertOffset + (caretOffsetInText ?? text.length)).clamp(0, updatedText.length),
    );
    widget.controller.makeCursorCenterIfInvisible();
  }

  /// 自定义粘贴处理
  ///
  /// 大段文本粘贴时统一换行符：部分编辑器复制出的长文本使用 `\r\n`，
  /// 归一化为 `\n` 可避免排版与统计上的额外开销。
  Future<void> _handleCustomPaste() async {
    if (widget.readOnly) return;
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? rawText = data?.text;
    if (rawText == null || rawText.isEmpty) return;

    final String text = rawText.length < _largeTextThreshold
        ? rawText
        : rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    _runEdit(NovelEditType.paste, () => widget.controller.replaceSelection(text));
    ClipboardStateCache.markHasContent();
    widget.controller.makeCursorCenterIfInvisible();
  }

  /// 显示正文右键菜单
  void _showContextMenuAt(Offset position) {
    if (!mounted) return;
    // 刷新剪贴板状态缓存，确保菜单中"粘贴"项的启用状态正确
    ClipboardStateCache.refresh().then((_) {
      if (!mounted) return;
      ContextMenu.showMenuAt(
        context: context,
        position: position,
        menuItems: _buildContextMenuItems(),
        itemPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        onDismissed: () {
          if (mounted && !_focusNode.hasFocus) _focusEditor();
        },
      );
    });
  }

  /// 编辑器右键菜单项列表
  ///
  /// 根据当前编辑器状态（是否有选区、撤销栈等）动态生成菜单项。
  /// 撤销/恢复与快捷键 Ctrl+Z / Ctrl+Y 调用的是同一套实现（[undo] / [redo]），
  /// 只读模式下仅保留复制和全选，禁用所有编辑操作。
  List<ContextMenuItem> _buildContextMenuItems() {
    final bool hasSelection = !widget.controller.selection.isCollapsed;
    final bool isReadOnly = widget.readOnly;

    return [
      // ===== 撤销 / 恢复组 =====
      ContextMenuItem(
        labelText: '撤销',
        icon: Icons.undo,
        enabled: !isReadOnly && widget.controller.canUndo,
        onTap: undo,
      ),
      ContextMenuItem(
        labelText: '恢复',
        icon: Icons.redo,
        enabled: !isReadOnly && widget.controller.canRedo,
        onTap: redo,
      ),

      // ----- 分隔线 -----
      ContextMenuItem.divider(),

      // ===== 剪切 / 复制 / 粘贴 / 删除组 =====
      ContextMenuItem(labelText: '剪切', icon: Icons.cut, enabled: !isReadOnly && hasSelection, onTap: _cut),
      ContextMenuItem(labelText: '复制', icon: Icons.copy, enabled: hasSelection, onTap: _copy),
      ContextMenuItem(
        labelText: '粘贴',
        icon: Icons.paste,
        enabled: !isReadOnly && ClipboardStateCache.hasContent,
        onTap: _handleCustomPaste,
      ),
      ContextMenuItem(
        labelText: '删除',
        icon: Icons.delete_outline,
        enabled: !isReadOnly && hasSelection,
        labelColor: Colors.redAccent,
        onTap: _delete,
      ),

      // ----- 分隔线 -----
      ContextMenuItem.divider(),

      // ===== 全选 =====
      ContextMenuItem(labelText: '全选', icon: Icons.select_all, onTap: widget.controller.selectAll),
    ];
  }

  /// 构建移动端选择工具栏
  ///
  /// 移动端长按选中文本后回调此方法，返回 Flutter 自适应工具栏，
  /// 外观与按钮文案交由平台渲染；按钮动作复用编辑器既有实现，
  /// 使剪切、粘贴等操作与码字统计、剪贴板处理保持一致。
  Widget _buildMobileSelectionToolbar({
    required BuildContext context,
    required TextSelectionToolbarAnchors anchors,
    required CodeLineEditingController controller,
    required VoidCallback onDismiss,
    required VoidCallback onRefresh,
  }) {
    final bool hasSelection = !controller.selection.isCollapsed;
    final List<ContextMenuButtonItem> buttonItems = [
      if (!widget.readOnly && hasSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {
            onDismiss();
            _cut();
          },
        ),
      if (hasSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            onDismiss();
            _copy();
          },
        ),
      if (!widget.readOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            onDismiss();
            _handleCustomPaste();
          },
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () {
          onDismiss();
          controller.selectAll();
        },
      ),
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: buttonItems,
    );
  }

  /// 获取编辑器快捷键覆盖动作
  ///
  /// 动作只随工作台 Provider 变化，Provider 未变化时复用已构建的一份，
  /// 避免编辑区每次重建都新建一批动作对象。
  Map<Type, Action<Intent>> _resolveShortcutOverrides(WorkspaceProvider provider) {
    if (!identical(provider, _shortcutOverridesProvider)) {
      _shortcutOverridesProvider = provider;
      _shortcutOverrides = _buildShortcutOverrides(provider);
    }
    return _shortcutOverrides!;
  }

  /// 构建编辑器快捷键覆盖动作
  ///
  /// re_editor 自带代码编辑器语义的快捷键，这里替换为小说写作语义：
  /// 撤销/重做/剪切/粘贴标注事件来源，Tab 与回车走段落缩进策略，
  /// 退格删除行首缩进、Delete 键执行前向删除，
  /// 查找替换与保存改用工作台的既有实现，注释、字符转换两类快捷键直接屏蔽。
  Map<Type, Action<Intent>> _buildShortcutOverrides(WorkspaceProvider provider) {
    return {
      CodeShortcutUndoIntent: CallbackAction<CodeShortcutUndoIntent>(
        onInvoke: (intent) {
          undo();
          return null;
        },
      ),
      CodeShortcutRedoIntent: CallbackAction<CodeShortcutRedoIntent>(
        onInvoke: (intent) {
          redo();
          return null;
        },
      ),
      CodeShortcutCutIntent: CallbackAction<CodeShortcutCutIntent>(
        onInvoke: (intent) {
          _cut();
          return null;
        },
      ),
      CodeShortcutPasteIntent: CallbackAction<CodeShortcutPasteIntent>(
        onInvoke: (intent) {
          _handleCustomPaste();
          return null;
        },
      ),
      CodeShortcutIndentIntent: CallbackAction<CodeShortcutIndentIntent>(
        onInvoke: (intent) {
          if (!widget.readOnly) _indentPolicy.handleTab();
          return null;
        },
      ),
      CodeShortcutNewLineIntent: CallbackAction<CodeShortcutNewLineIntent>(
        onInvoke: (intent) {
          if (!widget.readOnly) _indentPolicy.handleNewLine();
          return null;
        },
      ),
      CodeShortcutDeleteIntent: CallbackAction<CodeShortcutDeleteIntent>(
        onInvoke: (intent) {
          if (widget.readOnly) return null;
          if (intent.forward) {
            widget.controller.deleteForward();
          } else {
            _indentPolicy.handleBackspace();
          }
          return null;
        },
      ),
      CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
        onInvoke: (intent) {
          widget.onSave?.call();
          return null;
        },
      ),
      CodeShortcutFindIntent: CallbackAction<CodeShortcutFindIntent>(
        onInvoke: (intent) {
          provider.openFindReplace();
          return null;
        },
      ),
      CodeShortcutReplaceIntent: CallbackAction<CodeShortcutReplaceIntent>(
        onInvoke: (intent) {
          provider.openFindReplace(showReplace: true);
          return null;
        },
      ),
      CodeShortcutEscIntent: CallbackAction<CodeShortcutEscIntent>(
        onInvoke: (intent) {
          if (provider.isFindReplaceVisible) provider.closeFindReplace();
          return null;
        },
      ),
      // 屏蔽单行/多行注释快捷键（Control/Command + / 与 Shift + Control/Command + /）
      CodeShortcutCommentIntent: DoNothingAction(),
      // 屏蔽字符转换快捷键（Control/Command + T）
      CodeShortcutTransposeCharactersIntent: DoNothingAction(),
    };
  }

  /// 标题焦点下 Tab 切换到正文编辑器
  ///
  /// 正文拥有焦点时由 re_editor 自己的快捷键处理 Tab，此处的绑定不会被触发。
  void _handleGlobalTab() {
    if (!_focusNode.hasFocus) _focusEditor();
  }

  /// 处理保存快捷键（Ctrl+S / Cmd+S）
  void _handleSave() {
    widget.onSave?.call();
  }

  @override
  Widget build(BuildContext context) {
    // 编辑器内容不随应用界面字号缩放，保留编辑器自身的字体大小设置
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: _buildEditorBody(context),
    );
  }

  /// 构建编辑器主体内容
  Widget _buildEditorBody(BuildContext context) {
    // 检测窗口从最小化恢复的情况，请求编辑器焦点
    final bool isMinimized = context.select<WindowProvider, bool>((p) => p.isMinimized);
    if (_wasMinimized && !isMinimized && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _scrollGuard.protect(const Duration(milliseconds: 150));
          _focusEditor();
        }
      });
    }
    _wasMinimized = isMinimized;

    final WorkspaceProvider workspaceProvider = context.read<WorkspaceProvider>();
    final int highlightHash = context.select<WorkspaceProvider, int>((p) {
      final matches = p.findMatches;
      int hash = p.currentMatchIndex ^ matches.length;
      for (final m in matches) {
        hash = Object.hash(hash, m.baseOffset, m.extentOffset);
      }
      return hash;
    });

    // 同步查找匹配到样式构建器，并刷新其高亮解析缓存
    final ReEditorSpanBuilder? spanBuilder = widget.spanBuilder;
    if (spanBuilder != null) {
      spanBuilder.findMatches = workspaceProvider.findMatches;
      spanBuilder.currentMatchIndex = workspaceProvider.currentMatchIndex;
      spanBuilder.update(context: context, text: widget.controller.text);
    }

    // 高亮输入变化（如查找匹配变化）不改变编辑器属性，需主动请求重绘
    if (_lastHighlightHash != highlightHash) {
      _lastHighlightHash = highlightHash;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.forceRepaint();
      });
    }

    // 首次加载时按需跳转到光标位置
    if (_pendingScrollToCursor) {
      _pendingScrollToCursor = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.makeCursorCenterIfInvisible();
      });
    }

    // 标题区域高度决定编辑器顶部留白，首次展示时在布局完成后测量
    if (_titleAreaHeight <= 0 && widget.chapterTitleController != null && SettingsService.instance.showChapterTitle) {
      _scheduleTitleAreaMeasure();
    }

    return CallbackShortcuts(
      bindings: {
        // 标题焦点下按 Tab 切换到正文编辑器
        if (!widget.readOnly) const SingleActivator(LogicalKeyboardKey.tab): _handleGlobalTab,
        // 以下为全局快捷键，无论焦点在标题还是正文都生效
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _handleSave,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _handleSave,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          workspaceProvider.openFindReplace();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          workspaceProvider.openFindReplace();
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          workspaceProvider.openFindReplace(showReplace: true);
        },
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
          workspaceProvider.openFindReplace(showReplace: true);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (workspaceProvider.isFindReplaceVisible) workspaceProvider.closeFindReplace();
        },
      },
      child: _buildEditorArea(context),
    );
  }

  /// 编辑器区域：纸张背景 + 页边距 + 标题 + 编辑器
  ///
  /// 滚动由外层滚动容器承载（参照大纲编辑器）：滚动条紧贴容器，
  /// 纸张作为滚动内容的一部分，宽度按模式约束、高度随正文篇幅自适应。
  /// 纸张边界、页边距与标题都是滚动内容的组成部分，随正文一起滚动。
  Widget _buildEditorArea(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    return NotificationListener<ScrollMetricsNotification>(
      // 视口尺寸变化时（如窗口最大化/恢复、拖动调整窗口大小），按新的视口高度重算可见行区间并重新排版
      onNotification: (notification) {
        if (PlatformCapabilities.isMobile) {
          // 移动端键盘升降会在动画期间连续产生多次尺寸通知，逐次重绘会反复重排可见行
          _scheduleViewportRepaint();
        } else {
          widget.controller.forceRepaint();
        }
        return false;
      },
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: settings.scrollbarAlwaysVisible ? true : null,
        thickness: editorScrollbarThickness,
        radius: Radius.circular(editorScrollbarThickness / 2),
        child: ScrollConfiguration(
          // 屏蔽滚动视图自带滚动条与边界光效，滚动条统一由外层绘制
          behavior: CleanEditorScrollBehavior(),
          child: LayoutBuilder(builder: _buildEditorAreaContent),
        ),
      ),
    );
  }

  /// 取页边距换算所依据的编辑区高度
  ///
  /// 键盘收起时以当前可用高度更新基准，键盘弹出期间沿用上一次记录的基准，
  /// 使页边距不随键盘动画变化，正文在键盘升降过程中保持原位。
  double _resolveMarginBasisHeight(double availableHeight) {
    // 高度取自窗口视图的原始内边距：需要区分键盘升降，与应用内边距无关
    if (View.of(context).viewInsets.bottom <= 0) {
      _marginBasisHeight = availableHeight;
    }
    return _marginBasisHeight > 0 ? _marginBasisHeight : availableHeight;
  }

  /// 编辑器区域内容：纸张 + 标题 + 编辑器
  ///
  /// 纸张宽度按模式约束（纸张模式为 A4 宽并居中，非纸张模式贴合上级容器），
  /// 高度由标题与正文内容撑开；编辑器另设最小高度以撑满视口，
  /// 纸张模式下纸张容器再保证至少为一页 A4 高。
  /// 纸张背景占满纸张宽度；纸张模式下纸张容器再补偿左右各 16 像素，
  /// 布局设置-页边距（左右上下）则全部作为编辑器的内部留白，
  /// 使其落在编辑器盒内，点击边距空白处可把光标定位到附近的正文行。
  Widget _buildEditorAreaContent(BuildContext context, BoxConstraints constraints) {
    final SettingsService settings = SettingsService.instance;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool pageViewEnabled = settings.isPageViewEnabled;
    final bool showTitle = widget.chapterTitleController != null && settings.showChapterTitle;
    // 纸张宽度：纸张模式恒为 A4 宽，非纸张模式贴合上级容器（即视口宽度）
    final double paperWidth = pageViewEnabled ? GlobalConstants.a4Width : constraints.maxWidth;
    // 纸张容器的左右补偿：仅纸张模式生效
    final double paperCompensation = pageViewEnabled ? _paperHorizontalCompensation : 0.0;
    // 左右页边距：百分比 × 纸张宽度
    final double horizontalPadding = paperWidth * (settings.horizontalMargin / 100);
    // 上下页边距的换算基准：键盘升降期间保持不变，避免正文随键盘上下移动
    final double marginBasisHeight = _resolveMarginBasisHeight(constraints.maxHeight);
    // 顶边距：百分比 × 视口高度，作为章节标题与正文首行之间的间距
    final double topMargin = marginBasisHeight * (settings.topMargin / 100);
    // 底边距：百分比 × 视口高度，作为末行与纸张底边之间的安全距离
    final double bottomPadding = marginBasisHeight * (settings.bottomMargin / 100);
    // 记录到实例状态，供布局阶段对齐末行时计算目标滚动偏移
    _resolvedBottomPadding = bottomPadding;
    // 纸张上下与容器之间留出的空白，用于显露纸张轮廓
    final double paperGap = pageViewEnabled ? GlobalConstants.paperTopMargin : 0.0;
    // 记录到实例状态，供布局阶段对齐末行时计算目标滚动偏移
    _resolvedBottomGap = paperGap;
    final double scrollTopPadding = widget.extraTopPadding + paperGap;
    // 标题区域占用的高度（纸张内标题及其顶部间距）
    final double titleAreaHeight = showTitle ? _resolveTitleAreaHeight(settings) : 0.0;
    // 视口扣除滚动容器上下留白后可供纸张使用的高度
    final double viewportFillHeight = constraints.maxHeight - scrollTopPadding - paperGap;
    // 编辑器最小高度：撑满视口中除去标题后的剩余区域，
    // 使空文档或短章节下方的空白区仍属于编辑区（可命中并显示文本光标），不会露出母容器背景
    final double editorMinHeight = math.max(0.0, viewportFillHeight - titleAreaHeight);
    // 编辑器在滚动内容中的纵向偏移：滚动顶边距 + 章节标题高度
    final double editorContentOffset = scrollTopPadding + titleAreaHeight;
    // 编辑区底色：默认跟随主题，自定义时使用配置的颜色，纸张与编辑区共用同一底色
    final Color editorBackgroundColor = ColorUtils.getEditorBackgroundColorForTheme(context);
    // 纸张外的背景色：纸张模式下由淡化设置决定，其余模式与编辑区底色保持一致
    final Color outsideBackgroundColor = pageViewEnabled
        ? ColorUtils.getPaperOutsideBackgroundColor(context)
        : editorBackgroundColor;

    return ColoredBox(
      // 铺满编辑区域的底色，用于显露纸张外的背景
      color: outsideBackgroundColor,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.only(top: scrollTopPadding, bottom: paperGap),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: pageViewEnabled ? GlobalConstants.a4Width : double.infinity,
              minHeight: pageViewEnabled ? GlobalConstants.a4Height : 0.0,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: pageViewEnabled ? editorBackgroundColor : Colors.transparent,
                boxShadow: pageViewEnabled
                    ? [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              // 纸张容器的左右补偿：纸张背景仍占满纸张宽度，内容两侧各内缩该补偿
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: paperCompensation),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题与正文文本区左右对齐，故同样内缩左右页边距
                    if (showTitle)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: _buildChapterTitle(context),
                      ),
                    _buildEditor(
                      context,
                      // 左右页边距让正文与纸张边缘保留距离；左侧额外加上行首内边距，
                      // 保证行首光标完整可见；顶边距为标题与正文之间的间距，底边距为末行的安全距离
                      EdgeInsets.fromLTRB(
                        horizontalPadding + _contentLeftInset,
                        topMargin,
                        horizontalPadding,
                        bottomPadding,
                      ),
                      editorContentOffset,
                      editorMinHeight,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 章节标题组件
  Widget _buildChapterTitle(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    final TextEditingController titleController = widget.chapterTitleController!;
    return Padding(
      // 供测量标题区域高度使用
      key: _titleAreaKey,
      padding: EdgeInsets.only(top: settings.chapterTitleTopMargin + 16),
      child: ImeCursorFixerWrapper(
        controller: titleController,
        focusNode: _focusNode,
        child: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hoverColor: Colors.transparent,
          ),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            // 章节标题与正文保持一致，使用编辑器正文字体，不受界面字体影响
            fontFamily: settings.fontFamily,
            fontSize: settings.chapterTitleFontSize,
            color: ColorUtils.getChapterTitleColorForTheme(context),
          ),
          maxLines: 1,
          textAlign: TextAlign.center,
          onChanged: widget.onChapterTitleChanged,
        ),
      ),
    );
  }

  /// 章节标题区域（标题及其顶边距）的高度
  ///
  /// 优先使用实际排版测得的高度；尚未测得时按字号估算，待测量完成后自动校正。
  double _resolveTitleAreaHeight(SettingsService settings) {
    if (_titleAreaHeight > 0) return _titleAreaHeight;
    return settings.chapterTitleTopMargin + settings.chapterTitleFontSize * 1.5;
  }

  /// 在帧末按实际排版结果校正章节标题区域高度
  ///
  /// 标题高度取决于字号与主题样式，只能在布局完成后取得；
  /// 高度变化时触发重建以刷新编辑器顶部留白，未变化则不再重建。
  void _scheduleTitleAreaMeasure() {
    if (_titleAreaMeasureScheduled) return;
    _titleAreaMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleAreaMeasureScheduled = false;
      if (!mounted) return;
      final RenderObject? render = _titleAreaKey.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final double height = render.size.height;
      if ((height - _titleAreaHeight).abs() < 1.0) return;
      setState(() => _titleAreaHeight = height);
    });
  }

  /// 构建编辑器本体
  ///
  /// 选区颜色随焦点切换：失焦时使用派生灰显色，保持上一次选区的可见性。
  /// 页边距作为编辑器的内部留白而非外层容器的间距，
  /// 使编辑器盒覆盖整张纸张，点击边距空白处也能把光标定位到附近的正文行。
  /// 行间线随正文一并交给编辑器绘制，跟随其懒加载只绘制可见行。
  /// [minHeight] 为编辑器最小高度，内容不足时按下限撑开，避免短章节露出纸张外的背景。
  Widget _buildEditor(
    BuildContext context,
    EdgeInsets padding,
    double contentOffset,
    double minHeight,
  ) {
    final SettingsService settings = SettingsService.instance;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color focusedSelectionColor = colorScheme.primary.withValues(alpha: 0.25);
    final Color unfocusedSelectionColor = computePersistentSelectionColor(context, colorScheme.primary);
    // 行间线样式：仅在开启时传入，关闭时交由编辑器跳过绘制
    final CodeLineSeparatorStyle? lineSeparator = settings.showLineSeparator
        ? CodeLineSeparatorStyle(
            color: ColorUtils.getFontColorForTheme(context),
            dashed: settings.lineSeparatorStyle == 'dashed',
            opacity: settings.lineSeparatorOpacity,
          )
        : null;

    return ReEditorImeReporter(
      key: _imeReporterKey,
      controller: widget.controller,
      focusNode: _focusNode,
      scrollController: _scrollController,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, child) {
          return CodeEditor(
            controller: widget.controller,
            focusNode: _focusNode,
            scrollController: _codeScrollController,
            // 编辑器不承载滚动：高度随内容自适应，滚动由外层容器统一负责
            viewportScroller: _scrollController,
            viewportContentOffset: contentOffset,
            // 内容不足视口时按下限撑开编辑器，使下方空白区仍属于编辑区
            viewportMinHeight: minHeight,
            style: CodeEditorStyle(
              fontSize: settings.fontSize,
              fontFamily: settings.fontFamily,
              fontHeight: settings.lineHeight,
              letterSpacing: settings.letterSpacing,
              textColor: ColorUtils.getFontColorForTheme(context),
              backgroundColor: Colors.transparent,
              cursorColor: colorScheme.primary,
              cursorWidth: _cursorWidth,
              selectionColor: _focusNode.hasFocus ? focusedSelectionColor : unfocusedSelectionColor,
              highlightColor: focusedSelectionColor,
              lineSeparator: lineSeparator,
            ),
            // 小说正文需要自动换行，且不显示行号与代码折叠标记
            wordWrap: true,
            readOnly: widget.readOnly,
            // 关闭编辑器自身的自动聚焦：是否聚焦由外部按平台决定，
            // 移动端打开作品或切换标签页时不主动唤起输入法
            autofocus: false,
            // 只读预览（如历史版本备份）不显示输入光标
            showCursorWhenReadOnly: false,
            // 成对符号自动补全仅移动端启用，符号表取自标点符号表；
            // 表中未列出的 ASCII 引号与括号不会被写入正文
            autocompleteSymbols: PlatformCapabilities.isMobile &&
                SettingsService.instance.punctuationAutoCompleteEnabled,
            autocompletePairs: _punctuationPairs,
            // 移动端软键盘换行交由段落缩进策略处理，与桌面端回车共用补空行与首行缩进规则；
            // 只读编辑器与桌面端不接管，沿用编辑器默认换行
            onNewLine: PlatformCapabilities.isMobile && !widget.readOnly
                ? _indentPolicy.handleNewLine
                : null,
            chunkAnalyzer: const NonCodeChunkAnalyzer(),
            padding: padding,
            margin: EdgeInsets.zero,
            // hint: '开始输入内容……',
            toolbarController: _toolbarController,
            shortcutOverrideActions: _resolveShortcutOverrides(context.read<WorkspaceProvider>()),
            // 滚动条由外层统一绘制，这里屏蔽编辑器自带的滚动条
            scrollbarBuilder: (context, child, details) => child,
          );
        },
      ),
    );
  }
}

/// 正文右键菜单控制器
///
/// re_editor 在桌面端点击右键时通过该控制器回调显示菜单，
/// 菜单内容与定位交由外部实现，以便复用应用既有的菜单样式。
class _EditorToolbarController implements SelectionToolbarController {
  _EditorToolbarController({required this.onShowMenu});

  /// 显示菜单的回调，参数为菜单锚点的屏幕坐标
  final void Function(Offset position) onShowMenu;

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    onShowMenu(anchors.primaryAnchor);
  }

  @override
  void hide(BuildContext context) {}
}

/// 编辑器文本变化事件类型
///
/// 用于在编辑器拦截层（粘贴、撤销、恢复、剪切、删除、键盘输入）
/// 明确区分事件来源，供码字统计模块按类型分别处理：
/// - keyboard/paste/cut/delete 参与码字统计
/// - undo/redo 不参与码字统计（仅同步基线，避免影响今日码字与码字速度）
enum NovelEditType {
  /// 键盘输入（含 Backspace/Delete 键删除）
  keyboard,

  /// 粘贴
  paste,

  /// 剪切
  cut,

  /// 删除选中文本（右键菜单触发）
  delete,

  /// 撤销（不参与码字统计）
  undo,

  /// 恢复（不参与码字统计）
  redo,
}

/// 编辑事件回调签名
///
/// 由 [NovelEditor] 在文本变化时触发，参数为事件类型。
/// 字数增量由调用方根据控制器字数变化计算。
typedef OnEditEvent = void Function(NovelEditType type);
