import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/edit_event.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/clean_scroll.dart';
import 'package:quick_write/core/utils/clipboard_state_cache.dart';
import 'package:quick_write/core/utils/dialogue_highlight_controller.dart';
import 'package:quick_write/core/utils/editor_scroll_helper.dart';
import 'package:quick_write/core/utils/editor_undo_manager.dart';
import 'package:quick_write/core/utils/paragraph_formatter.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
import 'package:quick_write/core/utils/line_separator_painter.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/vertical_caret_keeper.dart';
import 'package:quick_write/shared/widgets/context_menu.dart';
import 'widgets/paper_container.dart';

/// 小说编辑器
///
/// 基于 TextField 实现的小说专用编辑器
class NovelEditor extends StatefulWidget {
  /// 章节正文文本编辑控制器
  final TextEditingController controller;

  /// 章节标题编辑控制器（备份预览标签页为 null）
  final TextEditingController? chapterTitleController;

  /// 撤销管理器
  final EditorUndoManager? undoManager;

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

  /// 光标位置变化回调
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
    this.undoManager,
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
  /// 小文本粘贴阈值（小于此值直接走原生粘贴）
  static const int _smallTextThreshold = 5000;

  /// 滚动控制器
  late final SyncScrollController _scrollController;

  /// 为 Scrollable 内部的内容盒子增加一个 Key，用于在 Layout 阶段安全计算相对坐标
  final GlobalKey _scrollContentKey = GlobalKey();

  /// 用于记录需要在 Layout 阶段修正的光标比例
  double? _pendingCursorScrollRatio;

  /// 用于记录需要在 Layout 阶段补偿的额外顶边距变化量
  double? _pendingExtraPaddingDelta;

  /// 缓存输入框相对于滚动区域顶部的 Y 轴物理偏移量（固定值，仅窗口变化时改变）
  double _cachedEditorTopOffset = 0.0;

  /// 窗口缩放防抖定时器
  Timer? _resizeDebounceTimer;

  /// 记录当前帧 Layout 阶段锚点修正是否成功
  ///
  /// 由 _onApplyContentDimensions 设置，由 _scheduleFallbackScroll 读取并重置。
  /// 若 Layout 阶段修正成功，帧后回调无需再修正；若失败，帧后回调通过 jumpTo 兜底修正。
  bool _layoutAnchorRestoreSuccess = false;

  /// 焦点节点（用于触发 Flutter 内置的光标可见机制）
  final FocusNode _focusNode = FocusNode();

  /// TextField 键，用于获取 TextField 实例
  final GlobalKey _textFieldKey = GlobalKey();

  /// 章节标题键，用于获取标题 RenderBox 以计算标题横带范围
  final GlobalKey _titleKey = GlobalKey();

  /// 保持横向位置的纵向光标移动 Action
  late final KeepHorizontalXVerticalSelectionAction _verticalMoveAction;

  /// 编辑器滚动保护器
  late final EditorScrollGuard _scrollGuard;

  /// 编辑器底边距保持器（末尾换行时自动补偿滚动，确保底边距可见）
  late final EditorBottomPaddingKeeper _paddingKeeper;

  /// 失焦时绘制持久化选区的 Painter
  ///
  /// 注入到 RenderEditable.painter（backgroundPainter），在文字层之下绘制选区高亮
  final PersistentSelectionOverlayPainter _persistentSelectionPainter = PersistentSelectionOverlayPainter();

  /// 行间线排版缓存
  ///
  /// 复用 TextPainter 实例并缓存排版结果，由 LineSeparatorPainter 使用，
  /// 避免每次 paint 都对全文重新排版
  final LineSeparatorLayoutCache _lineSeparatorCache = LineSeparatorLayoutCache();

  /// 窗口大小变化前的视口锚点信息
  ///
  /// 用于在布局变化后恢复视口显示内容的位置。
  /// 以视口内第一个可见字符为锚点，记录其字符偏移和在视口内的相对Y位置，
  /// 布局完成后根据该字符在新排版中的位置重新计算滚动偏移量，
  /// 解决窗口宽度变化导致文字重排后可视区域内容偏移的问题
  _ViewportAnchor? _viewportAnchor;

  /// 上一次编辑器区域的宽度
  ///
  /// 用于检测边栏展开/收起或拖拽导致的编辑器宽度变化，
  /// 变化时触发视口锚点机制，防止文字重排后内容偏移
  double? _lastEditorWidth;

  /// 缓存窗口最小化状态，用于检测从最小化恢复的情况
  bool _wasMinimized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 初始化控制器，绑定同步拦截方法
    _scrollController = SyncScrollController(onApplyContentDimensions: _onApplyContentDimensions);

    _scrollGuard = EditorScrollGuard(_scrollController);
    _scrollController.addListener(_onScrollChanged);
    widget.controller.addListener(_onSelectionChanged);

    // 初始化纵向光标移动 Action，覆盖 Flutter 默认的上下方向键行为
    _verticalMoveAction = KeepHorizontalXVerticalSelectionAction(
      controller: widget.controller,
      textFieldKey: _textFieldKey,
    );

    // 初始化底边距保持器（封装了末尾换行检测 + 滚动补偿逻辑）
    _paddingKeeper = EditorBottomPaddingKeeper(
      scrollController: _scrollController,
      textController: widget.controller,
      paddingRatio: SettingsService.instance.bottomMargin / 100, // 使用设置的底边距百分比
    );
    _paddingKeeper.init();

    // 监听焦点变化，防止窗口恢复或失去/获取焦点时发生意外的滚动跳转
    _focusNode.addListener(_onFocusChanged);

    // 第一帧后将持久化选区 Painter 注入到 RenderEditable.foregroundPainter
    // 此时 TextField 的渲染树已构建完成，RenderEditable 可通过 findRenderObject 获取
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _attachPersistentSelectionPainter();
      }
    });

    // 如果初始化时处于激活状态，请求焦点
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }

    // 当 initialScrollToCursor = true 时，通过 _pendingCursorScrollRatio 标记请求同步光标定位
    // 这用于"打开章节时定位至章末/上一次编辑"功能
    if (widget.initialScrollToCursor) {
      _pendingCursorScrollRatio = 0.5;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听设置变化
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _scrollGuard.dispose();
    _paddingKeeper.dispose();
    _scrollController.removeListener(_onScrollChanged);
    widget.controller.removeListener(_onSelectionChanged);
    _focusNode.removeListener(_onFocusChanged);
    _resizeDebounceTimer?.cancel(); // 取消定时器
    // 取消监听设置变化
    SettingsService.instance.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    _focusNode.dispose();
    // 释放行间线排版缓存中持有的 TextPainter 资源
    _lineSeparatorCache.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 处理设置变化
  void _onSettingsChanged() {
    // 检查组件是否仍然挂载，防止在组件销毁后调用setState()
    if (mounted) {
      // 重新构建以应用新的设置（页边距、行间线等会随设置变化自动更新）
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(NovelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当标签页由不可见变为可见时，自动请求焦点
    if (widget.isActive && !oldWidget.isActive) {
      // 开启滚动保护（锁定当前滚动位置，防止 requestFocus 导致的自动滚动）
      _scrollGuard.protect(const Duration(milliseconds: 150));
      // 延迟一帧请求焦点，确保彻底夺回焦点
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }

    // 当额外顶边距变化时（如查找替换栏显示/隐藏），在 Layout 阶段补偿滚动偏移量防止内容跳动
    if (widget.extraTopPadding != oldWidget.extraTopPadding) {
      final delta = widget.extraTopPadding - oldWidget.extraTopPadding;
      if (delta != 0) {
        _pendingExtraPaddingDelta = delta;
      }
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 首次捕获后锁定锚点（第一个可见字符的位置信息），后续连续的尺寸变化不再覆盖
    // 用于布局完成后恢复视口内容位置，解决窗口大小变化导致文字重排后的偏移问题
    _viewportAnchor ??= _captureViewportAnchor();
    // 利用防抖定时器：只要还在连续拖拽窗口，定时器就会被重置。
    // 直到用户停止缩放 200ms 后，才释放锚点。
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      _viewportAnchor = null;
    });

    // 调度帧后滚动修正，作为 Layout 阶段修正的安全兜底
    _scheduleFallbackScroll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 开启滚动保护，防止应用从后台恢复时 TextField 自动滚动到光标位置
    if (state == AppLifecycleState.resumed) {
      _scrollGuard.protect(const Duration(milliseconds: 300));
    }
  }

  /// 滚动位置变化时通知父组件
  void _onScrollChanged() {
    if (_scrollController.hasClients && widget.onScrollOffsetChanged != null) {
      widget.onScrollOffsetChanged!(_scrollController.offset);
    }
  }

  /// 光标位置变化时通知父组件
  ///
  /// 同时同步持久化选区 Painter 的选区范围，
  /// 确保 Painter 始终绘制最新的选区位置
  void _onSelectionChanged() {
    if (widget.onSelectionChanged != null) {
      widget.onSelectionChanged!(widget.controller.selection);
    }

    // 同步 painter 的选区数据
    _persistentSelectionPainter.update(selection: widget.controller.selection);

    // 通知纵向光标移动 Action 检查是否需要重置状态
    // 非本 Action 触发的选区变化（如鼠标点击、左右键）会重置横向位置记忆
    _verticalMoveAction.onSelectionChanged();
  }

  /// 滚动到当前光标/选区位置
  ///
  /// 供外部调用（如查找替换导航时），使编辑器滚动到当前选区所在位置
  void scrollToCursor() {
    _scrollGuard.unprotect();
    _pendingCursorScrollRatio = 0.5;
    setState(() {});
  }

  /// 请求编辑器获取焦点
  ///
  /// 供外部调用（如关闭查找替换栏后），将焦点归还给编辑器
  void requestEditorFocus() {
    _scrollGuard.unprotect();
    _focusNode.requestFocus();
  }

  /// 执行撤销操作的内部辅助方法
  void _handleUndo() {
    // 撤销栈为空时直接返回，避免无操作触发 onEditEvent 误标记为已修改
    final bool didUndo = widget.undoManager?.undo() ?? false;
    if (!didUndo) return;
    _scrollGuard.unprotect();
    _pendingCursorScrollRatio = 0.5;
    // 通知父组件文本已变化
    widget.onEditEvent?.call(NovelEditType.undo);
    _pendingCursorScrollRatio = 0.5;
  }

  /// 执行重做操作的内部辅助方法
  void _handleRedo() {
    // 重做栈为空时直接返回，避免无操作触发 onEditEvent 误标记为已修改
    final bool didRedo = widget.undoManager?.redo() ?? false;
    if (!didRedo) return;
    _scrollGuard.unprotect();
    _pendingCursorScrollRatio = 0.5;
    // 通知父组件文本已变化
    widget.onEditEvent?.call(NovelEditType.redo);
    _pendingCursorScrollRatio = 0.5;
  }

  @override
  Widget build(BuildContext context) {
    // 检测窗口从最小化恢复的情况，请求编辑器焦点
    final windowProvider = context.watch<WindowProvider>();
    if (_wasMinimized && !windowProvider.isMinimized && widget.isActive) {
      // 窗口从最小化恢复，且当前标签页处于激活状态，请求焦点
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _scrollGuard.protect(const Duration(milliseconds: 150));
          _focusNode.requestFocus();
        }
      });
    }
    _wasMinimized = windowProvider.isMinimized;

    // 监听查找匹配状态变化，仅在匹配项或当前索引变化时重建
    // 使用哈希摘要避免在字数更新等无关通知时重建编辑器
    context.select<WorkspaceProvider, int>((p) {
      final matches = p.findMatches;
      int hash = p.currentMatchIndex ^ matches.length;
      for (final m in matches) {
        hash = Object.hash(hash, m.baseOffset, m.extentOffset);
      }
      return hash;
    });

    // 将查找匹配高亮同步到控制器
    // 在 build 阶段直接设置字段值（不触发 notifyListeners），
    // 后续 TextField 重建时会读取最新值以渲染高亮
    final workspaceProvider = context.read<WorkspaceProvider>();
    if (widget.controller is DialogueHighlightController) {
      final controller = widget.controller as DialogueHighlightController;
      controller.findMatches = workspaceProvider.findMatches;
      controller.currentMatchIndex = workspaceProvider.currentMatchIndex;
    }

    // 监听焦点变化，动态决定是否绑定编辑类快捷键
    // 焦点位于标题 TextField 时放行撤销/恢复/粘贴/Tab，让其原生处理
    return ListenableBuilder(
      listenable: _focusNode,
      builder: (context, child) {
        // 正文编辑器拥有焦点时才接管编辑类快捷键，否则放行给标题 TextField 原生处理
        final bool bodyHasFocus = _focusNode.hasFocus;
        return CallbackShortcuts(
          bindings: {
            // 编辑类快捷键（粘贴、撤销、恢复）仅在非只读且正文拥有焦点时绑定
            if (!widget.readOnly && bodyHasFocus) ...{
              // 拦截 Windows/Linux 的 Ctrl+V
              const SingleActivator(LogicalKeyboardKey.keyV, control: true): _handleCustomPaste,
              // 拦截 macOS 的 Cmd+V
              const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _handleCustomPaste,

              // 拦截并接管撤销操作 (Ctrl+Z / Cmd+Z)
              const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _handleUndo,
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _handleUndo,

              // 拦截并接管恢复操作 (Ctrl+Y / Cmd+Shift+Z / Ctrl+Shift+Z)
              const SingleActivator(LogicalKeyboardKey.keyY, control: true): _handleRedo,
              const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _handleRedo,
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _handleRedo,
            },

            // Tab 键始终绑定：正文焦点时插入全角空格，标题焦点时切换到正文
            if (!widget.readOnly)
              const SingleActivator(LogicalKeyboardKey.tab): _handleTabKey,

            // 以下为全局快捷键，无论焦点在标题还是正文都生效
            // 拦截 Windows/Linux 的 Ctrl+S 保存
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): _handleSave,
            // 拦截 macOS 的 Cmd+S 保存
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _handleSave,

            // Ctrl+F / Cmd+F：打开查找
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
              context.read<WorkspaceProvider>().openFindReplace();
            },
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
              context.read<WorkspaceProvider>().openFindReplace();
            },
            // Ctrl+H / Cmd+H：打开查找替换（展开替换区域）
            const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
              context.read<WorkspaceProvider>().openFindReplace(showReplace: true);
            },
            const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
              context.read<WorkspaceProvider>().openFindReplace(showReplace: true);
            },
            // Escape：关闭查找替换栏
            const SingleActivator(LogicalKeyboardKey.escape): () {
              final provider = context.read<WorkspaceProvider>();
              if (provider.isFindReplaceVisible) {
                provider.closeFindReplace();
              }
            },
          },
          child: child!,
        );
      },
      // 使用 LayoutBuilder 获取容器的真实高度
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 纸张模式下，编辑器内容宽度被约束为不超过 A4 纸宽
          final bool pageViewEnabled = SettingsService.instance.isPageViewEnabled;
          final double contentWidth = pageViewEnabled
              ? constraints.maxWidth.clamp(0.0, GlobalConstants.a4Width)
              : constraints.maxWidth;
          // 检测编辑器宽度变化（由边栏展开/收起或拖拽导致），触发视口锚点机制
          final currentEditorWidth = contentWidth;
          if (_lastEditorWidth != null && (_lastEditorWidth! - currentEditorWidth).abs() > 0.5) {
            // 首次捕获后锁定锚点，后续连续的宽度变化不再覆盖
            _viewportAnchor ??= _captureViewportAnchor();
            // 重置防抖定时器：只要还在连续变化，定时器就会被重置
            _resizeDebounceTimer?.cancel();
            _resizeDebounceTimer = Timer(const Duration(milliseconds: 200), () {
              _viewportAnchor = null;
            });
            // 调度兜底滚动修正
            _scheduleFallbackScroll();
          }
          _lastEditorWidth = currentEditorWidth;

          // 调度一个帧后回调，静默更新 TopOffset
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateCachedMetrics();
          });
          // 缓存容器高度到底边距保持器，供滚动补偿计算使用
          _paddingKeeper.updateMaxHeight(constraints.maxHeight);
          // 最外层包裹 Scrollbar，这样滚动条才能贴靠屏幕右侧边缘
          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: SettingsService.instance.scrollbarAlwaysVisible ? true : null,
            thickness: 8.0, // 滚动条宽度
            radius: const Radius.circular(4), // 滚动条圆角
            // 屏蔽 TextField 自带的内部滚动条，防止出现两条滚动条
            child: ScrollConfiguration(
              behavior: CleanEditorScrollBehavior(),
              child: SingleChildScrollView(
                controller: _scrollController,
                // 用 ConstrainedBox 强制内容最小高度等于父容器高度
                child: ConstrainedBox(
                  key: _scrollContentKey,
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  // 交互层包裹在 PaperContainer 外侧，使纸张外的空白区域也能响应光标定位、拖拽选区与右键菜单
                  // RawGestureDetector 通过自定义识别器仅在正文区域拦截右键，标题横带的右键放行给标题 TextField
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    gestures: <Type, GestureRecognizerFactory>{
                      _BodySecondaryButtonRecognizer:
                          GestureRecognizerFactoryWithHandlers<_BodySecondaryButtonRecognizer>(
                        () => _BodySecondaryButtonRecognizer(
                          shouldIntercept: (position) => !_isInTitleBand(position),
                          onSecondaryDown: (PointerDownEvent event) async {
                            _handleSecondaryTapDown(event);
                            // 刷新剪贴板状态缓存，确保菜单中"粘贴"项的启用状态正确
                            await ClipboardStateCache.refresh();
                            if (!mounted) return;
                            _showContextMenuAt(event.position);
                          },
                        ),
                        (_) {},
                      ),
                    },
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _handlePointerDownForMenu,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanDown: _handleBlankAreaPanDown,
                        onPanUpdate: _handleBlankAreaPanUpdate,
                        onPanEnd: _handleBlankAreaPanEnd,
                        onPanCancel: _handleBlankAreaPanCancel,
                        // 鼠标悬停时显示文本输入光标（I-beam）
                        child: MouseRegion(
                          cursor: SystemMouseCursors.text,
                          // 用 PaperContainer 包裹，纸张模式下约束为 A4 宽度并叠加纸张视觉
                          child: PaperContainer(
                            enabled: pageViewEnabled,
                            // 查找替换浮窗出现时的顶边距保护，防止浮窗遮挡文字
                            topPadding: widget.extraTopPadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.chapterTitleController != null && SettingsService.instance.showChapterTitle)
                                  _buildChapterTitle(context),
                                // 正文区域，保留页边距与行间线绘制
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    contentWidth * (SettingsService.instance.horizontalMargin / 100), // 左边距
                                    constraints.maxHeight * (SettingsService.instance.topMargin / 100), // 顶边距
                                    contentWidth * (SettingsService.instance.horizontalMargin / 100), // 右边距
                                    constraints.maxHeight * (SettingsService.instance.bottomMargin / 100), // 底边距
                                  ),
                                  child: _buildEditorWithLineSeparator(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 章节标题组件
  Widget _buildChapterTitle(BuildContext context) {
    final settings = SettingsService.instance;
    final titleController = widget.chapterTitleController!;
    return Padding(
      key: _titleKey,
      padding: EdgeInsets.only(top: settings.chapterTitleTopMargin),
      child: ImeCursorFixerWrapper(
        controller: titleController,
        focusNode: _focusNode,
        child: TextField(
          controller: titleController,
          decoration: InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hoverColor: Colors.transparent,
          ),
          style: context.headlineMedium?.copyWith(
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

  /// 构建带行间线的编辑器区域
  ///
  /// 使用 CustomPaint 的 foregroundPainter 在编辑器文字层之上绘制行间线，
  /// 通过 TextPainter 自主计算文本排版位置，完全脱离 RenderEditable。
  /// 这样可以覆盖自动换行、空行以及底部边距区域。
  Widget _buildEditorWithLineSeparator(BuildContext context) {
    final settings = SettingsService.instance;
    final bool showLine = settings.showLineSeparator;

    // 编辑器内容（TextField）
    final Widget editorContent = Focus(
      focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
      child: ImeCursorFixerWrapper(
        controller: widget.controller,
        focusNode: _focusNode,
        child: _buildEditorActionsAndTextField(context),
      ),
    );

    // 未开启行间线时直接返回编辑器，避免不必要的 CustomPaint 开销
    if (!showLine) return editorContent;

    // 用 LayoutBuilder 获取实际内容宽度，确保 TextPainter 的排版宽度与 TextField 一致
    return LayoutBuilder(
      builder: (context, constraints) {
        final double contentWidth = constraints.maxWidth;
        // 从设置服务获取底部边距比例，传递给绘制器用于延伸线条到底部边距区域
        final double bottomMarginRatio = settings.bottomMargin / 100;

        // 使用 CustomPaint 包裹编辑器，foregroundPainter 在 child 之后（之上）绘制，
        // 确保行间线不被 TextField 内部渲染覆盖。
        // 传入 _lineSeparatorCache 复用 TextPainter 实例与排版结果；
        // 传入 _scrollController 作为 repaint Listenable，滚动时自动触发重绘并限制绘制范围至可见行
        return CustomPaint(
          foregroundPainter: createLineSeparatorPainter(
            text: widget.controller.text,
            color: ColorUtils.getFontColorForTheme(context),
            contentWidth: contentWidth,
            bottomMarginRatio: bottomMarginRatio,
            cache: _lineSeparatorCache,
            scrollController: _scrollController,
          ),
          child: editorContent,
        );
      },
    );
  }

  /// 章节正文组件
  Widget _buildEditorActionsAndTextField(BuildContext context) {
    return Actions(
      actions: {
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (intent) {
            _handleUndo();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (intent) {
            _handleRedo();
            return null;
          },
        ),
        // 覆盖 Flutter 默认的上下方向键行为，保持纵向移动中的横向位置
        // 必须用 DirectionalCaretMovementIntent 作为 key：
        // EditableText 内部 _verticalSelectionUpdateAction 的泛型参数是
        // DirectionalCaretMovementIntent，overridable 查找以此 Type 为准
        DirectionalCaretMovementIntent: _verticalMoveAction,
      },
      child: TextField(
        key: _textFieldKey,
        controller: widget.controller,
        readOnly: widget.readOnly,
        // 禁用了 Flutter 默认的 UndoHistoryController，使用外层拦截接管撤销逻辑
        scrollPhysics: const NeverScrollableScrollPhysics(),
        focusNode: _focusNode,
        maxLines: null,
        // 防止点击外部区域时 TextField 失去焦点
        onTapOutside: (event) {},
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontFamily: SettingsService.instance.fontFamily,
          fontSize: SettingsService.instance.fontSize,
          letterSpacing: SettingsService.instance.letterSpacing,
          height: SettingsService.instance.lineHeight,
          fontWeight: SettingsService.instance.isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: SettingsService.instance.isItalic ? FontStyle.italic : FontStyle.normal,
          decoration: SettingsService.instance.isUnderline ? TextDecoration.underline : TextDecoration.none,
          color: ColorUtils.getFontColorForTheme(context),
          backgroundColor: Colors.transparent,
        ),
        inputFormatters: [ParagraphFormatter()],
        selectionWidthStyle: ui.BoxWidthStyle.tight,
        // 屏蔽 TextField 原生右键菜单，改用自定义 ContextMenu
        contextMenuBuilder: (context, editableTextState) => const SizedBox.shrink(),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hoverColor: Colors.transparent,
          // 内部边距彻底归零，防止产生内部死区
          contentPadding: EdgeInsets.zero,
          isDense: true,
          hintText: '开始输入内容……',
          hintStyle: context.bodyMedium?.copyWith(color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
        // 仅在用户真实键盘输入时触发（程序设置 controller.value 不会触发本回调）
        // 触发后通过 onEditEvent 通知父组件按 keyboard 类型参与码字统计
        onChanged: widget.onEditEvent == null
            ? null
            : (_) => widget.onEditEvent!.call(NovelEditType.keyboard),
      ),
    );
  }

  /// 编辑器右键菜单项列表
  ///
  /// 根据当前编辑器状态（光标选中、撤销栈等）动态生成菜单项
  /// 包含：撤销、恢复、剪切、复制、粘贴、删除、全选
  /// 只读模式下仅保留复制和全选，禁用所有编辑操作
  List<ContextMenuItem> _buildContextMenuItems() {
    final selection = widget.controller.selection;
    final bool hasSelection = selection.isValid && !selection.isCollapsed;
    // 只读模式下禁用所有编辑类操作，仅保留复制和全选
    final bool isReadOnly = widget.readOnly;

    return [
      // ===== 撤销 / 恢复组 =====
      ContextMenuItem(
        labelText: '撤销',
        icon: Icons.undo,
        enabled: !isReadOnly && (widget.undoManager?.canUndo ?? false),
        onTap: () {
          // 撤销栈为空时不执行，避免无操作触发 onEditEvent 误标记为已修改
          final bool didUndo = widget.undoManager?.undo() ?? false;
          if (!didUndo) return;
          _scrollGuard.unprotect();
          // 通知父组件文本已变化
          widget.onEditEvent?.call(NovelEditType.undo);
          _pendingCursorScrollRatio = 0.5;
        },
      ),
      ContextMenuItem(
        labelText: '恢复',
        icon: Icons.redo,
        enabled: !isReadOnly && (widget.undoManager?.canRedo ?? false),
        onTap: () {
          // 重做栈为空时不执行，避免无操作触发 onEditEvent 误标记为已修改
          final bool didRedo = widget.undoManager?.redo() ?? false;
          if (!didRedo) return;
          _scrollGuard.unprotect();
          // 通知父组件文本已变化
          widget.onEditEvent?.call(NovelEditType.redo);
          _pendingCursorScrollRatio = 0.5;
        },
      ),

      // ----- 分隔线 -----
      ContextMenuItem.divider(),

      // ===== 剪切 / 复制 / 粘贴 / 删除组 =====
      ContextMenuItem(labelText: '剪切', icon: Icons.cut, enabled: !isReadOnly && hasSelection, onTap: () => _handleCut()),
      ContextMenuItem(labelText: '复制', icon: Icons.copy, enabled: hasSelection, onTap: () => _handleCopy()),
      ContextMenuItem(labelText: '粘贴', icon: Icons.paste, enabled: !isReadOnly && ClipboardStateCache.hasContent, onTap: () => _handleCustomPaste()),
      ContextMenuItem(
        labelText: '删除',
        icon: Icons.delete_outline,
        enabled: !isReadOnly && hasSelection,
        labelColor: Colors.redAccent,
        onTap: () => _handleDelete(),
      ),

      // ----- 分隔线 -----
      ContextMenuItem.divider(),

      // ===== 全选 =====
      ContextMenuItem(labelText: '全选', icon: Icons.select_all, onTap: () => _handleSelectAll()),
    ];
  }

  /// ContextMenu 关闭回调
  void _handleContextMenuDismissed() {
    // 当菜单关闭时（包括按 ESC 键），确保 TextField 重新获得焦点
    if (mounted && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  /// Listener 点击拦截事件（处理右键菜单相关的光标跳动）
  void _handlePointerDownForMenu(PointerDownEvent event) {
    // 标题横带内的点击交给标题 TextField 原生处理，不干预正文光标
    if (_isInTitleBand(event.position)) return;
    // 拦截左键按下事件：
    // 当菜单处于显示状态或刚刚关闭时，由于焦点即将自动回到 TextField，
    // 为了避免焦点切回时的光标位置仍然是之前右键点击的位置，造成光标闪现的问题，
    // 在这里立即同步光标到最新点击位置。
    if (event.buttons == kPrimaryButton && (ContextMenu.isMenuShowing() || ContextMenu.wasJustClosed())) {
      _updateSelectionImmediately(event);
    }
  }

  /// 处理保存快捷键（Ctrl+S / Cmd+S）
  void _handleSave() {
    widget.onSave?.call();
  }

  /// 处理 TAB 键
  ///
  /// 正文拥有焦点时，在光标位置插入两个全角空格作为缩进；
  /// 标题拥有焦点时，将焦点切换到正文编辑器。
  void _handleTabKey() {
    if (_focusNode.hasFocus) {
      // 全角空格（IDEOGRAPHIC SPACE，U+3000），插入两个作为缩进
      _insertTextAtCursor('\u3000\u3000');
    } else {
      // 焦点在标题 TextField 时，Tab 切换到正文编辑器
      _focusNode.requestFocus();
    }
  }

  /// 焦点变化时触发
  ///
  /// 当窗口最小化恢复，或者从其他应用切回时，TextField 会重新获取焦点并自动滚动到光标位置
  /// 为了防止这种不期望的跳动，在获取焦点时短暂开启滚动保护
  ///
  /// 同时更新持久化选区 Painter 的失焦状态，让它在失焦时绘制灰色选区高亮
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _scrollGuard.protect(const Duration(milliseconds: 150));
    }

    // 同步 painter 的失焦状态并触发重绘（颜色从主题色派生）
    _persistentSelectionPainter.update(
      isUnfocused: !_focusNode.hasFocus,
      selection: widget.controller.selection,
      color: computePersistentSelectionColor(context, widget.colorScheme.primary),
    );
  }

  /// 将持久化选区 Painter 注入到 RenderEditable 的 painter（backgroundPainter）链中
  void _attachPersistentSelectionPainter() {
    attachPersistentSelectionPainter(
      textFieldKey: _textFieldKey,
      painter: _persistentSelectionPainter,
      controller: widget.controller,
      focusNode: _focusNode,
      context: context,
      fallbackColor: widget.colorScheme.primary,
    );
  }

  /// 自定义粘贴处理逻辑
  ///
  /// 解决长文本粘贴卡顿问题：
  /// 1. 小文本（<5000字）直接走原生粘贴
  /// 2. 大文本进行优化处理（规范化换行符）
  Future<void> _handleCustomPaste() async {
    // 从操作系统剪贴板读取纯文本
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) return;

    final String pastedText = data.text!;

    // 小文本直接走原生粘贴
    if (pastedText.length < _smallTextThreshold) {
      _insertTextAtCursor(pastedText);
      return;
    }

    // 大文本优化处理
    // 很多记事本复制出来的长文本，换行符是 \r\n，Flutter 对这种老旧格式的排版计算极慢
    // 强制统一替换为标准的单换行符 \n，打断 Flutter 底层的巨型排版连字块
    String optimizedText = pastedText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 瞬间将处理后的文本插入到光标位置
    _insertTextAtCursor(optimizedText);
  }

  /// 将处理好的文本精准插入到当前光标所在位置
  ///
  /// 支持以下情况：
  /// - 普通粘贴：在光标位置插入文本
  /// - 全选后粘贴：替换选中的文本
  /// - 粘贴后自动滚动到新光标位置
  void _insertTextAtCursor(String text) {
    final selection = widget.controller.selection;
    final String currentText = widget.controller.text;

    // 获取当前的光标位置或选中范围
    final int start = selection.isValid ? selection.start : 0;
    final int end = selection.isValid ? selection.end : 0;

    final String prefix = currentText.substring(0, start);
    final String suffix = currentText.substring(end);
    final String newText = prefix + text + suffix;

    // 计算插入后的新光标位置
    final newOffset = start + text.length;

    _pendingCursorScrollRatio = 0.95;

    // 利用 TextEditingValue 触发带有 Undo 记录的完整更新
    // 这种方式不仅更新了文本和光标，还能正确推入 Flutter 内置的 UndoHistoryState 栈中
    // 程序设置 value 不会触发 TextField.onChanged，因此不会与 keyboard 事件重复
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );

    // 通知父组件本次为粘贴事件，由父组件按 paste 类型计入码字统计
    widget.onEditEvent?.call(NovelEditType.paste);

    // 滚动到新光标位置
    // _scheduleFallbackScroll();
  }

  /// 处理剪切操作
  ///
  /// 将选中的文本复制到剪贴板，然后从编辑器中删除
  void _handleCut() async {
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final String selectedText = widget.controller.text.substring(selection.start, selection.end);

    // 将选中文本写入系统剪贴板
    await Clipboard.setData(ClipboardData(text: selectedText));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();

    // 从编辑器中删除选中的文本
    final String currentText = widget.controller.text;
    final newText = currentText.substring(0, selection.start) + currentText.substring(selection.end);

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start),
    );

    // 通知父组件本次为剪切事件，按 cut 类型（同 keyboard 语义）参与码字统计
    widget.onEditEvent?.call(NovelEditType.cut);
  }

  /// 处理复制操作
  ///
  /// 将选中的文本复制到剪贴板，不修改编辑器内容
  void _handleCopy() async {
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final String selectedText = widget.controller.text.substring(selection.start, selection.end);

    await Clipboard.setData(ClipboardData(text: selectedText));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();
  }

  /// 处理删除操作
  ///
  /// 直接删除选中的文本
  void _handleDelete() {
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final String currentText = widget.controller.text;
    final newText = currentText.substring(0, selection.start) + currentText.substring(selection.end);

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start),
    );

    // 通知父组件本次为删除事件，按 delete 类型（同 keyboard 语义）参与码字统计
    widget.onEditEvent?.call(NovelEditType.delete);
  }

  /// 处理全选操作
  ///
  /// 选中编辑器中的所有文本
  void _handleSelectAll() {
    widget.controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length);
  }

  /// 根据全局坐标获取对应的文本位置（偏移量与光标亲和性）
  ///
  /// 返回的 TextPosition 同时携带 affinity：行末点击时为 upstream，
  /// 用于创建 collapsed selection 时将光标显示在当前行末而非下一行起始。
  TextPosition? _getTextPositionFromPoint(Offset globalPosition) {
    // 遍历渲染树，捞出真正的文字排版引擎 RenderEditable
    final RenderEditable? renderEditable = findPersistentRenderEditable(_textFieldKey);
    if (renderEditable == null) return null;

    // 将全局坐标 clamp 到 RenderEditable 的全局边界内，
    // 避免点击在 TextField 外的空白处时 getPositionForPoint 误判为下一行起始位置
    final Offset topLeft = renderEditable.localToGlobal(Offset.zero);
    final Size size = renderEditable.size;
    final Offset clampedGlobal = Offset(
      globalPosition.dx.clamp(topLeft.dx, topLeft.dx + size.width),
      globalPosition.dy.clamp(topLeft.dy, topLeft.dy + size.height),
    );
    return renderEditable.getPositionForPoint(clampedGlobal);
  }

  /// 获取标题底部在屏幕坐标系下的 Y 值
  ///
  /// 用于划定"标题横带"的下边界：凡 Y 值小于此值的位置都视为标题水平延伸的区域，
  /// 此类位置不响应正文的光标定位、拖拽选区与右键菜单。
  /// 没有标题时返回 null，表示不存在标题横带。
  double? _getTitleBottomY() {
    if (widget.chapterTitleController == null || !SettingsService.instance.showChapterTitle) {
      return null;
    }
    final RenderBox? titleBox = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (titleBox == null || !titleBox.attached) return null;
    final Offset titleTopLeft = titleBox.localToGlobal(Offset.zero);
    return titleTopLeft.dy + titleBox.size.height;
  }

  /// 判断全局坐标是否位于标题水平延伸的横带内
  ///
  /// 标题横带定义：从内容区顶部到标题底部的整个水平范围，
  /// 包含标题顶边距与标题本体占用的区域。
  /// 此区域内的左键与右键事件均不响应正文交互，保留给标题 TextField 原生处理。
  bool _isInTitleBand(Offset globalPosition) {
    final double? titleBottomY = _getTitleBottomY();
    if (titleBottomY == null) return false;
    return globalPosition.dy < titleBottomY;
  }

  /// 在指定位置显示正文右键菜单
  ///
  /// 通过静态方法手动触发菜单显示，避免使用 ContextMenu 包裹整个区域造成标题右键被拦截。
  void _showContextMenuAt(Offset position) {
    if (!mounted) return;
    ContextMenu.showMenuAt(
      context: context,
      position: position,
      menuItems: _buildContextMenuItems(),
      itemPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      onDismissed: _handleContextMenuDismissed,
    );
  }

  /// 处理编辑器区域内的右键按下事件
  ///
  /// 由外层 [_BodySecondaryButtonRecognizer] 在拦截右键后调用，
  /// 手动实现右键的光标定位功能（TextField 本身已收不到右键事件）。
  ///
  /// 核心逻辑：
  /// - 有选区时：不修改 selection，保持原选区完全不变
  /// - 无选区时：根据点击位置设置 collapsed selection（光标定位）
  void _handleSecondaryTapDown(PointerDownEvent event) {
    final TextSelection currentSelection = widget.controller.selection;

    // 只有无选区时才定位光标；有选区时保持不动
    if (currentSelection.isCollapsed || !currentSelection.isValid) {
      final TextPosition? position = _getTextPositionFromPoint(event.position);
      if (position != null) {
        widget.controller.selection = TextSelection.collapsed(
          offset: position.offset,
          affinity: position.affinity,
        );
      }
    }

    // 确保编辑器拥有焦点
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  /// 立即根据物理坐标更新光标位置
  ///
  /// 用于处理右键菜单关闭时，焦点恢复造成的瞬间光标闪烁问题。
  /// 与 `_handleBlankAreaPanDown` 逻辑类似，但输入参数为 `PointerDownEvent`。
  void _updateSelectionImmediately(PointerDownEvent event) {
    final TextPosition? position = _getTextPositionFromPoint(event.position);
    if (position != null) {
      widget.controller.selection = TextSelection.collapsed(
        offset: position.offset,
        affinity: position.affinity,
      );
    } else {
      widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    }
  }

  /// 拖拽选区起始位置记录
  int? _dragBaseOffset;

  /// 处理在空白区域按下鼠标/手指的事件（准备定位光标或开始框选）
  ///
  /// 普通点击：设置光标位置或开始新的选择
  /// Shift+点击：从当前光标或选区边界扩展选择范围
  void _handleBlankAreaPanDown(DragDownDetails details) {
    // 标题横带内的左键交给标题 TextField 原生处理，不抢焦点也不修改正文选区
    if (_isInTitleBand(details.globalPosition)) return;

    // 无论当前是否有焦点，强制要求保持焦点
    // 使用 addPostFrameCallback 确保在当前手势竞技场胜出、
    // TextField 可能被框架自动 unfocus 之后，再强行把焦点抢回来
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });

    final TextPosition? clickPosition = _getTextPositionFromPoint(details.globalPosition);
    final int clickOffset = clickPosition?.offset ?? widget.controller.text.length;
    final TextAffinity clickAffinity = clickPosition?.affinity ?? TextAffinity.downstream;

    // 检测是否按住了 Shift 键，若是则执行选区扩展逻辑
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final isShiftPressed =
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

    if (isShiftPressed) {
      // Shift+点击模式：基于当前选区扩展选择范围
      final TextSelection currentSelection = widget.controller.selection;
      if (currentSelection.isValid && !currentSelection.isCollapsed) {
        // 已有选区时，保持 base 不变，将 extent 扩展到点击位置
        _dragBaseOffset = currentSelection.baseOffset;
        widget.controller.selection = TextSelection(baseOffset: currentSelection.baseOffset, extentOffset: clickOffset);
      } else {
        // 无选区时，以当前光标位置为 base，点击位置为 extent
        _dragBaseOffset = currentSelection.extentOffset;
        widget.controller.selection = TextSelection(
          baseOffset: currentSelection.extentOffset,
          extentOffset: clickOffset,
        );
      }
    } else {
      // 普通点击模式：设置光标位置并准备开始新选择，携带 affinity 避免行末跑到下一行起始
      _dragBaseOffset = clickOffset;
      widget.controller.selection = TextSelection.collapsed(offset: clickOffset, affinity: clickAffinity);
    }
  }

  /// 处理在空白区域拖拽以选中文字的事件
  void _handleBlankAreaPanUpdate(DragUpdateDetails details) {
    if (_dragBaseOffset == null) return;

    final TextPosition? position = _getTextPositionFromPoint(details.globalPosition);
    if (position != null) {
      widget.controller.selection = TextSelection(
        baseOffset: _dragBaseOffset!,
        extentOffset: position.offset,
        affinity: position.affinity,
      );
    }

    // 更新记录当前的全局坐标，供边缘滚动使用
    _lastDragPosition = details.globalPosition;
    // 边缘滚动逻辑
    _handleEdgeAutoScroll(details.globalPosition);
  }

  /// 边缘自动滚动的状态记录
  bool _isAutoScrolling = false;

  /// 记录最新的拖拽坐标
  Offset? _lastDragPosition;

  /// 边缘滚动触发区域的高度（像素）
  static const double _edgeScrollZoneHeight = 50.0;

  /// 边缘滚动速度（像素/帧）
  static const double _edgeScrollSpeed = 15.0;

  /// 处理拖拽到边缘时的自动滚动
  void _handleEdgeAutoScroll(Offset globalPosition) {
    final RenderBox? scrollBox =
        _scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
    if (scrollBox == null) return;

    // 将全局坐标转换为 Scrollable 的局部坐标
    final Offset localPosition = scrollBox.globalToLocal(globalPosition);
    final double viewportHeight = scrollBox.size.height;

    // 检查是否在上下边缘区域
    final bool nearTop = localPosition.dy < _edgeScrollZoneHeight;
    final bool nearBottom = localPosition.dy > viewportHeight - _edgeScrollZoneHeight;

    if (nearTop && !_isAutoScrolling) {
      _startAutoScroll(-1);
    } else if (nearBottom && !_isAutoScrolling) {
      _startAutoScroll(1);
    } else if (!nearTop && !nearBottom && _isAutoScrolling) {
      _stopAutoScroll();
    }
  }

  /// 开始边缘自动滚动
  void _startAutoScroll(int direction) {
    if (_isAutoScrolling) return;
    _isAutoScrolling = true;

    void scrollStep() {
      if (!_isAutoScrolling || !mounted) return;

      final double currentOffset = _scrollController.offset;
      final double maxOffset = _scrollController.position.maxScrollExtent;
      final double targetOffset = currentOffset + (direction * _edgeScrollSpeed);

      if (targetOffset < 0 || targetOffset > maxOffset) {
        _stopAutoScroll();
        return;
      }

      _scrollController.jumpTo(targetOffset);

      // 滚动后，使用保存的最新鼠标位置再次触发选区更新
      if (_lastDragPosition != null && _dragBaseOffset != null) {
        final TextPosition? position = _getTextPositionFromPoint(_lastDragPosition!);
        if (position != null) {
          widget.controller.selection = TextSelection(
            baseOffset: _dragBaseOffset!,
            extentOffset: position.offset,
            affinity: position.affinity,
          );
        }
      }

      // 为了更平滑，通过 requestAnimationFrame 不断触发滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollStep();
      });
    }

    scrollStep();
  }

  /// 停止边缘自动滚动
  void _stopAutoScroll() {
    _isAutoScrolling = false;
  }

  /// 拖拽结束时清理状态
  void _handleBlankAreaPanEnd(DragEndDetails details) {
    _dragBaseOffset = null;
    _lastDragPosition = null;
    _stopAutoScroll();
  }

  /// 拖拽取消时清理状态
  void _handleBlankAreaPanCancel() {
    _dragBaseOffset = null;
    _lastDragPosition = null;
    _stopAutoScroll();
  }

  // ==================== 视口锚点机制 ====================

  /// 捕获当前视口的锚点信息
  ///
  /// 以视口内第一个可见字符为锚点，通过二分查找定位该字符，
  /// 记录其字符偏移量和在视口内的相对Y位置比例。
  /// 此方法必须在旧布局仍有效时调用（即 didChangeMetrics 同步阶段）。
  _ViewportAnchor? _captureViewportAnchor() {
    if (!_scrollController.hasClients) return null;

    final RenderEditable? re = findPersistentRenderEditable(_textFieldKey);
    if (re == null) return null;

    final int textLength = widget.controller.text.length;
    if (textLength == 0) return null;

    // 当前滚动条的绝对坐标
    final double scrollOffset = _scrollController.offset;
    // 视口高度
    final double viewportHeight = _scrollController.position.viewportDimension;

    // 将滚动坐标转换到正文内部的相对坐标系
    // 如果算出来小于 0，说明还在章节标题或边距区域，正文的第一行肯定是可见的
    final double localVisibleTop = scrollOffset - _cachedEditorTopOffset;

    int low = 0, high = textLength;
    int anchorOffset = 0;
    double anchorY = 0.0;

    // 二分查找：找到 Y 坐标最接近且 >= 视口顶部的第一个字符
    while (low < high) {
      final int mid = (low + high) ~/ 2;
      final Rect caretRect = re.getLocalRectForCaret(TextPosition(offset: mid));

      final double charTop = caretRect.top;
      // 使用修正后的 localVisibleTop 进行比较
      if (charTop < localVisibleTop - 1.0) {
        // 字符在视口上方，需要找更靠后的字符
        low = mid + 1;
      } else {
        // 字符已在视口内或下方，记录并继续向左搜索更精确的位置
        high = mid;
        anchorOffset = mid;
        anchorY = charTop;
      }
    }

    if (anchorY < localVisibleTop - 1.0 && textLength > 0) {
      anchorOffset = textLength - 1;
      final Rect lastRect = re.getLocalRectForCaret(TextPosition(offset: anchorOffset));
      anchorY = lastRect.top;
    }

    // 计算比例时，把文字内部坐标转回绝对坐标
    final double absoluteAnchorY = _cachedEditorTopOffset + anchorY;
    final double ratioInViewport = ((absoluteAnchorY - scrollOffset) / viewportHeight).clamp(0.0, 1.0);

    return _ViewportAnchor(characterOffset: anchorOffset, ratioInViewport: ratioInViewport);
  }

  /// 根据锚点信息锁定视口内容位置
  ///
  /// 在新布局生效后，查询锚点字符的新Y坐标，
  /// 并结合其相对位置比例计算出目标滚动偏移量，使该字符回到视口中的相同相对位置。
  void _restoreViewportByAnchor(_ViewportAnchor anchor) {
    if (!_scrollController.hasClients) return;

    final RenderEditable? re = findPersistentRenderEditable(_textFieldKey);
    if (re == null) return;

    // 获取锚点字符在新布局中的位置
    final int clampedOffset = anchor.characterOffset.clamp(0, widget.controller.text.length);
    final Rect newCaretRect = re.getLocalRectForCaret(TextPosition(offset: clampedOffset));

    // 锚点字符在新布局中的Y坐标
    final double anchorNewY = newCaretRect.top;
    // 实时计算编辑器顶部偏移量，而非使用可能尚未更新的缓存值
    final double absoluteAnchorNewY = _computeEditorTopOffset() + anchorNewY;
    // 新的视口高度
    final double newViewportHeight = _scrollController.position.viewportDimension;

    // 目标滚动偏移量：使锚点字符出现在视口的相同相对位置
    // targetOffset = anchorNewY - viewportHeight * ratio
    final double targetOffset = absoluteAnchorNewY - (newViewportHeight * anchor.ratioInViewport);

    // 限制在有效滚动范围内
    final double clampedTarget = targetOffset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    // 仅当偏移差异超过阈值时才执行跳转
    if ((_scrollController.offset - clampedTarget).abs() > 0.5) {
      _scrollController.jumpTo(clampedTarget);
    }
  }

  /// 在 Layout 阶段拦截并修正滚动像素
  ///
  /// 通过 SyncScrollPosition.applyContentDimensions 拦截，在 Paint 之前通过 correctPixels 修正位置，
  /// 避免闪烁。此方法在每次 Viewport 布局时被调用。
  void _onApplyContentDimensions(ScrollPosition position, double minExt, double maxExt) {
    if (_viewportAnchor != null) {
      // 记录 Layout 阶段锚点修正是否成功，供 _scheduleFallbackScroll 判断是否需要帧后兜底
      _layoutAnchorRestoreSuccess = _restoreViewportByAnchorInLayout(position, _viewportAnchor!, minExt, maxExt);
    }

    if (_pendingCursorScrollRatio != null) {
      if (_scrollToCursorInLayout(position, _pendingCursorScrollRatio!, minExt, maxExt)) {
        _pendingCursorScrollRatio = null;
      }
    }

    // 在 Layout 阶段补偿额外顶边距变化导致的滚动偏移
    if (_pendingExtraPaddingDelta != null) {
      final targetOffset = (position.pixels + _pendingExtraPaddingDelta!).clamp(minExt, maxExt);
      if ((position.pixels - targetOffset).abs() > 0.5) {
        position.correctPixels(targetOffset);
      }
      _pendingExtraPaddingDelta = null;
    }
  }

  /// 在 Layout 阶段通过 correctPixels() 修正视口锚点位置
  bool _restoreViewportByAnchorInLayout(ScrollPosition position, _ViewportAnchor anchor, double minExt, double maxExt) {
    final RenderEditable? re = findPersistentRenderEditable(_textFieldKey);
    if (re == null) return false;

    double? anchorY;
    try {
      // 在 Profile/Release 模式下，RenderEditable 已完成布局，此时读取坐标成功且精准。
      // 在 Debug 模式下，Flutter 的层级访问断言会抛出异常，导致此处失败，
      // 需要由 _scheduleFallbackScroll 的帧后回调兜底修正。
      final int clampedOffset = anchor.characterOffset.clamp(0, widget.controller.text.length);
      anchorY = re.getLocalRectForCaret(TextPosition(offset: clampedOffset)).top;
    } catch (e) {
      // 读取坐标失败（Debug模式下被系统抓到了越级访问，断言拦截或其他异常），返回 false 让帧后回调兜底
      return false;
    }

    // final double absoluteY = _cachedEditorTopOffset + anchorY;
    // 实时计算编辑器相对于滚动内容区域的顶部偏移量
    // 不能使用 _cachedEditorTopOffset，因为该缓存值在首次 Layout 阶段尚未更新（仍为初始值 0），
    // 会导致忽略顶边距和章节标题占据的高度，造成滚动定位失败
    final double editorTopOffset = _computeEditorTopOffset();
    final double absoluteY = editorTopOffset + anchorY;
    final double targetOffset = absoluteY - (position.viewportDimension * anchor.ratioInViewport);

    if ((position.pixels - targetOffset).abs() > 0.5) {
      position.correctPixels(targetOffset.clamp(minExt, maxExt));
    }
    return true;
  }

  /// 在 Layout 阶段通过 correctPixels() 修正光标滚动位置
  bool _scrollToCursorInLayout(ScrollPosition position, double offsetRatio, double minExt, double maxExt) {
    final RenderEditable? re = findPersistentRenderEditable(_textFieldKey);
    if (re == null) return false;

    final selection = widget.controller.selection;
    if (!selection.isValid) return false;

    double? caretY;
    double? caretTop;
    try {
      // 获取光标 baseline 位置（用于定位计算）
      final List<TextSelectionPoint> boxes = re.getEndpointsForSelection(selection);
      if (boxes.isEmpty) return false;
      caretY = boxes.last.point.dy;

      // 额外尝试获取光标矩形的顶部位置
      // 用于精确判断光标是否在视口顶部被部分遮挡
      try {
        caretTop = re.getLocalRectForCaret(TextPosition(offset: selection.extentOffset)).top;
      } catch (_) {
        // getLocalRectForCaret 在 Debug 模式的 Layout 阶段可能被 Assert 拦截，
        // 失败时后续会用 baseline 减去行高估算值代替
      }
    } catch (e) {
      debugPrint('修正光标位置失败');
      return false;
    }
    // final double absoluteY = _cachedEditorTopOffset + caretY;
    // 实时计算编辑器相对于滚动内容区域的顶部偏移量
    // 不能使用 _cachedEditorTopOffset，因为该缓存值在首次 Layout 阶段尚未更新（仍为初始值 0），
    // 会导致忽略顶边距和章节标题占据的高度，造成滚动定位失败
    final double editorTopOffset = _computeEditorTopOffset();
    final double absoluteY = editorTopOffset + caretY;
    final double viewportHeight = position.viewportDimension;

    // 判定光标是否需要滚动修正：
    // - 上边界：优先用 caretTop 精确判断，若不可得则用 baseline 减去默认行高估算
    //   这解决了光标位于视口顶部边缘、仅显示下半行时原逻辑不触发滚动的问题
    // - 下边界：baseline 超出视口底部即视为不可见
    final double effectiveTop = caretTop ?? (caretY - 20.0); // 20pt 作为默认行高安全边距
    final double absoluteTop = editorTopOffset + effectiveTop;

    if (absoluteTop < position.pixels || absoluteY > position.pixels + viewportHeight) {
      final double targetOffset = absoluteY - (viewportHeight * offsetRatio);
      position.correctPixels(targetOffset.clamp(minExt, maxExt));
    }
    return true;
  }

  /// 调度帧后滚动修正
  ///
  /// 在视口锚点捕获后，注册一个 postFrameCallback 来检查 Layout 阶段的修正是否成功。
  /// 如果 Layout 阶段的修正未成功（如 findPersistentRenderEditable 返回 null、
  /// getLocalRectForCaret 抛出异常、或 applyContentDimensions 未被调用），
  /// 则在此回调中通过 jumpTo 进行修正。
  ///
  /// Debug 模式下，由于 Flutter 的层级访问断言，Layout 阶段的修正通常会失败，
  /// 因此主要依赖此回调进行修正。Profile/Release 模式下，Layout 阶段的修正通常成功，
  /// 此回调仅作为安全兜底。
  void _scheduleFallbackScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 如果 Layout 阶段修正未成功，则通过帧后回调兜底修正
      if (_viewportAnchor != null && !_layoutAnchorRestoreSuccess) {
        _restoreViewportByAnchor(_viewportAnchor!);
      }
      // 每一帧结束，重置标记位，等待下一帧
      _layoutAnchorRestoreSuccess = false;

      // 焦点恢复等不影响闪烁的操作放这里
      if (!_focusNode.hasFocus && widget.isActive) {
        _focusNode.requestFocus();
      }
    });
  }

  /// 安全地缓存 TextField 距离滚动视口顶部的物理偏移量
  void _updateCachedMetrics() {
    final RenderEditable? re = findPersistentRenderEditable(_textFieldKey);
    final RenderBox? scrollContentBox = _scrollContentKey.currentContext?.findRenderObject() as RenderBox?;
    if (re != null && scrollContentBox != null && re.attached && scrollContentBox.attached) {
      try {
        _cachedEditorTopOffset = MatrixUtils.transformPoint(re.getTransformTo(scrollContentBox), Offset.zero).dy;
      } catch (_) {
        // 忽略极端情况下的计算失败
      }
    }
  }

  /// 实时计算编辑器相对于滚动内容区域的顶部偏移量
  ///
  /// 与 _updateCachedMetrics() 的计算逻辑相同，但直接返回结果而非写入缓存。
  /// 用于 Layout 阶段的滚动修正，此时 _cachedEditorTopOffset 可能尚未初始化。
  double _computeEditorTopOffset() {
    final RenderEditable? re = findPersistentRenderEditable(_textFieldKey);
    final RenderBox? scrollContentBox = _scrollContentKey.currentContext?.findRenderObject() as RenderBox?;
    if (re != null && scrollContentBox != null && re.attached && scrollContentBox.attached) {
      try {
        return MatrixUtils.transformPoint(re.getTransformTo(scrollContentBox), Offset.zero).dy;
      } catch (_) {
        // 计算失败时回退到缓存值（可能为 0 或上次帧后更新的值）
        return _cachedEditorTopOffset;
      }
    }
    return _cachedEditorTopOffset;
  }
}

/// 仅在正文区域拦截右键的手势识别器
///
/// 继承自 [EagerGestureRecognizer]，在检测到右键（buttons == 2）且
/// [shouldIntercept] 返回 true 时立即消费整个指针事件序列，
/// 阻止事件继续向子组件传递（避免正文 TextField 收到右键后弹出原生菜单）。
///
/// 标题横带内的右键不被拦截，会正常传递给标题 TextField 由其原生菜单处理；
/// 左键、中键等其他按钮事件一概放行，不影响拖拽选区等左键交互。
class _BodySecondaryButtonRecognizer extends EagerGestureRecognizer {
  /// 判断当前位置是否应该拦截右键事件
  final bool Function(Offset position)? shouldIntercept;

  /// 右键被拦截时的回调
  final void Function(PointerDownEvent event)? onSecondaryDown;

  _BodySecondaryButtonRecognizer({
    this.shouldIntercept,
    this.onSecondaryDown,
  });

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // 仅处理右键，且通过 shouldIntercept 判定位于正文区域时才拦截
    if (event.buttons == 2 && shouldIntercept?.call(event.position) != false) {
      super.addAllowedPointer(event);
      onSecondaryDown?.call(event);
    }
  }
}

/// 视口锚点数据结构
///
/// 记录窗口大小变化前视口内的关键位置信息，
/// 用于布局变化后恢复视口显示的内容位置
class _ViewportAnchor {
  /// 锚点字符在文本中的偏移量
  final int characterOffset;

  /// 锚点字符在视口内的相对Y位置比例（0.0 = 视口顶部，1.0 = 视口底部）
  final double ratioInViewport;

  const _ViewportAnchor({required this.characterOffset, required this.ratioInViewport});
}
