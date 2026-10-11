import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
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
import 'package:quick_write/core/utils/line_separator_painter.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
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

  /// 行间线排版缓存
  final LineSeparatorLayoutCache _lineSeparatorCache = LineSeparatorLayoutCache();

  /// 章节标题区域的测量键
  final GlobalKey _titleAreaKey = GlobalKey();

  /// 章节标题区域（标题及其顶边距）的高度
  ///
  /// 标题与正文同屏滚动，其高度需计入编辑器顶部留白，由布局完成后测量得到。
  double _titleAreaHeight = 0;

  /// 标题区域测量是否已排队，避免同一帧内重复排队
  bool _titleAreaMeasureScheduled = false;

  /// 上下文菜单控制器
  late final _EditorToolbarController _toolbarController;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = SyncScrollController(onApplyContentDimensions: _onApplyContentDimensions);
    _codeScrollController = CodeScrollController(verticalScroller: _scrollController);
    _scrollGuard = EditorScrollGuard(_scrollController);
    _scrollController.addListener(_onScrollChanged);
    _indentPolicy = ReEditorIndentPolicy(controller: widget.controller);
    _toolbarController = _EditorToolbarController(onShowMenu: _showContextMenuAt);
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
        if (mounted) _focusNode.requestFocus();
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
    _scrollGuard.dispose();
    _scrollController.removeListener(_onScrollChanged);
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    SettingsService.instance.removeListener(_onSettingsChanged);
    _customHighlightService?.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    _codeScrollController.dispose();
    _focusNode.dispose();
    _lineSeparatorCache.dispose();
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
          _focusNode.requestFocus();
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

  /// 滚动到当前光标/选区位置
  ///
  /// 供外部调用（如查找替换导航时），使编辑器滚动到当前选区所在位置
  void scrollToCursor() {
    _scrollGuard.unprotect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.makeCursorCenterIfInvisible();
    });
  }

  /// 请求编辑器获取焦点
  ///
  /// 供外部调用（如关闭查找替换栏后），将焦点归还给编辑器
  void requestEditorFocus() {
    _scrollGuard.unprotect();
    _focusNode.requestFocus();
  }

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

  /// 维持底边距这一安全距离
  ///
  /// 光标位于最后一行时，内容增长会把最后一行向下推挤甚至顶出视口；
  /// 此处把滚动位置推到末尾，使最后一行与容器底边始终保持设定的底边距。
  void _keepBottomPaddingVisible() {
    if (widget.controller.selection.extentIndex < widget.controller.codeLines.length - 1) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ScrollPosition? position = _editorScrollPosition;
      if (position == null) return;
      final double targetOffset = position.maxScrollExtent;
      if (position.pixels < targetOffset - 0.5) {
        _scrollController.animateTo(targetOffset, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
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

  /// 在 Layout 阶段补偿额外顶边距变化导致的滚动偏移
  void _onApplyContentDimensions(ScrollPosition position, double minExt, double maxExt) {
    if (_pendingExtraPaddingDelta != null) {
      final double targetOffset = (position.pixels + _pendingExtraPaddingDelta!).clamp(minExt, maxExt);
      if ((position.pixels - targetOffset).abs() > 0.5) {
        position.correctPixels(targetOffset);
      }
      _pendingExtraPaddingDelta = null;
    }
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

  /// 撤销
  void _undo() {
    if (widget.readOnly || !widget.controller.canUndo) return;
    _runEdit(NovelEditType.undo, widget.controller.undo);
    widget.controller.makeCursorCenterIfInvisible();
  }

  /// 重做
  void _redo() {
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
          if (mounted && !_focusNode.hasFocus) _focusNode.requestFocus();
        },
      );
    });
  }

  /// 编辑器右键菜单项列表
  ///
  /// 根据当前编辑器状态（是否有选区、撤销栈等）动态生成菜单项。
  /// 撤销/恢复与快捷键 Ctrl+Z / Ctrl+Y 调用的是同一套实现（[_undo] / [_redo]），
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
        onTap: _undo,
      ),
      ContextMenuItem(
        labelText: '恢复',
        icon: Icons.redo,
        enabled: !isReadOnly && widget.controller.canRedo,
        onTap: _redo,
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

  /// 构建编辑器快捷键覆盖动作
  ///
  /// re_editor 自带代码编辑器语义的快捷键，这里替换为小说写作语义：
  /// 撤销/重做/剪切/粘贴标注事件来源，Tab 与回车走段落缩进策略，
  /// 查找替换与保存改用工作台的既有实现，注释、字符转换两类快捷键直接屏蔽。
  Map<Type, Action<Intent>> _buildShortcutOverrides() {
    final WorkspaceProvider provider = context.read<WorkspaceProvider>();
    return {
      CodeShortcutUndoIntent: CallbackAction<CodeShortcutUndoIntent>(
        onInvoke: (intent) {
          _undo();
          return null;
        },
      ),
      CodeShortcutRedoIntent: CallbackAction<CodeShortcutRedoIntent>(
        onInvoke: (intent) {
          _redo();
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
          if (!widget.readOnly) _indentPolicy.handleBackspace();
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
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  /// 处理保存快捷键（Ctrl+S / Cmd+S）
  void _handleSave() {
    widget.onSave?.call();
  }

  @override
  Widget build(BuildContext context) {
    // 检测窗口从最小化恢复的情况，请求编辑器焦点
    final bool isMinimized = context.select<WindowProvider, bool>((p) => p.isMinimized);
    if (_wasMinimized && !isMinimized && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _scrollGuard.protect(const Duration(milliseconds: 150));
          _focusNode.requestFocus();
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
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: settings.scrollbarAlwaysVisible ? true : null,
      thickness: 8.0,
      radius: const Radius.circular(4),
      child: ScrollConfiguration(
        // 屏蔽滚动视图自带滚动条与边界光效，滚动条统一由外层绘制
        behavior: CleanEditorScrollBehavior(),
        child: LayoutBuilder(builder: _buildEditorAreaContent),
      ),
    );
  }

  /// 编辑器区域内容：纸张 + 标题 + 编辑器 + 行间线
  ///
  /// 纸张宽度按模式约束（纸张模式为 A4 宽并居中，非纸张模式贴合上级容器），
  /// 高度由标题与正文内容撑开，纸张模式下至少为一页 A4 高。
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
    // 顶边距：百分比 × 视口高度，作为章节标题与正文首行之间的间距
    final double topMargin = constraints.maxHeight * (settings.topMargin / 100);
    // 底边距：百分比 × 视口高度，作为末行与纸张底边之间的安全距离
    final double bottomPadding = constraints.maxHeight * (settings.bottomMargin / 100);
    // 纸张上下与容器之间留出的空白，用于显露纸张轮廓
    final double paperGap = pageViewEnabled ? GlobalConstants.paperTopMargin : 0.0;
    final double scrollTopPadding = widget.extraTopPadding + paperGap;
    // 编辑器在滚动内容中的纵向偏移：滚动顶边距 + 章节标题高度
    final double editorContentOffset =
        scrollTopPadding + (showTitle ? _resolveTitleAreaHeight(settings) : 0.0);
    // 正文排版宽度：纸张宽度扣除纸张容器补偿、左右页边距与行首内边距
    final double contentWidth =
        paperWidth - paperCompensation * 2 - horizontalPadding * 2 - _contentLeftInset;

    return SingleChildScrollView(
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
              color: pageViewEnabled ? colorScheme.surfaceContainerLowest : Colors.transparent,
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
                  _buildEditorWithLineSeparator(
                    context,
                    horizontalPadding: horizontalPadding,
                    contentWidth: contentWidth,
                    contentTopInset: topMargin,
                    bottomPadding: bottomPadding,
                    editorContentOffset: editorContentOffset,
                  ),
                ],
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

  /// 构建带行间线的编辑器区域
  ///
  /// 页边距只是编辑器的内部留白，编辑器盒仍占满纸张宽度，
  /// 因此点击边距空白处会落在编辑器内并被换算为附近的正文位置；
  /// 行间线作为覆盖层对齐到正文文本区，与编辑器同处滚动内容之中，
  /// 按内容坐标系直接绘制，行位置与正文排版一致。
  Widget _buildEditorWithLineSeparator(
    BuildContext context, {
    required double horizontalPadding,
    required double contentWidth,
    required double contentTopInset,
    required double bottomPadding,
    required double editorContentOffset,
  }) {
    final Widget editor = _buildEditor(
      context,
      // 左右页边距让正文与纸张边缘保留距离；左侧额外加上行首内边距，
      // 保证行首光标完整可见；顶边距为标题与正文之间的间距，底边距为末行的安全距离
      EdgeInsets.fromLTRB(
        horizontalPadding + _contentLeftInset,
        contentTopInset,
        horizontalPadding,
        bottomPadding,
      ),
      editorContentOffset,
    );
    return Stack(
      children: [
        editor,
        Positioned.fill(
          child: IgnorePointer(
            // 内缩到正文文本区，使行间线与正文左右边界一致
            child: Padding(
              padding: EdgeInsets.only(left: horizontalPadding + _contentLeftInset, right: horizontalPadding),
              child: ListenableBuilder(
                // 正文变化时重建绘制器，使行间线随文字同步刷新
                listenable: widget.controller,
                builder: (context, child) => CustomPaint(
                  painter: SettingsService.instance.showLineSeparator
                      ? createLineSeparatorPainter(
                          text: widget.controller.text,
                          color: ColorUtils.getFontColorForTheme(context),
                          contentWidth: contentWidth,
                          contentTopInset: contentTopInset,
                          // 行间线延伸覆盖底部边距这一安全距离区域
                          bottomMargin: bottomPadding,
                          cache: _lineSeparatorCache,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建编辑器本体
  ///
  /// 选区颜色随焦点切换：失焦时使用派生灰显色，保持上一次选区的可见性。
  /// 页边距作为编辑器的内部留白而非外层容器的间距，
  /// 使编辑器盒覆盖整张纸张，点击边距空白处也能把光标定位到附近的正文行。
  Widget _buildEditor(BuildContext context, EdgeInsets padding, double contentOffset) {
    final SettingsService settings = SettingsService.instance;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color focusedSelectionColor = colorScheme.primary.withValues(alpha: 0.25);
    final Color unfocusedSelectionColor = computePersistentSelectionColor(context, colorScheme.primary);

    return ReEditorImeReporter(
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
            ),
            // 小说正文需要自动换行，且不显示行号与代码折叠标记
            wordWrap: true,
            readOnly: widget.readOnly,
            // 只读预览（如历史版本备份）不显示输入光标
            showCursorWhenReadOnly: false,
            // 关闭成对符号自动补全，避免把 ASCII 引号/括号写入正文
            autocompleteSymbols: false,
            chunkAnalyzer: const NonCodeChunkAnalyzer(),
            padding: padding,
            margin: EdgeInsets.zero,
            // hint: '开始输入内容……',
            toolbarController: _toolbarController,
            shortcutOverrideActions: _buildShortcutOverrides(),
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
