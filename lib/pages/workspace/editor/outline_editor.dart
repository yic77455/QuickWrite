import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/utils/batch_selection_controller.dart';
import 'package:quick_write/core/utils/clean_scroll.dart';
import 'package:quick_write/core/utils/clipboard_state_cache.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/editor_scroll_helper.dart';
import 'package:quick_write/core/utils/find_replace_target.dart';
import 'package:quick_write/core/utils/outline_markdown_codec.dart';
import 'package:quick_write/core/utils/outline_undo_manager.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/rich_text_controller.dart';
import 'package:quick_write/core/utils/text_style_range.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'utils/outline_shortcut_keys.dart';
import 'widgets/outline_color_palette.dart';
import 'widgets/outline_node_widgets.dart';
import 'widgets/outline_editor_widgets.dart';
import 'widgets/outline_settings_card.dart';
import 'widgets/outline_shortcut_panel.dart';

/// 大纲编辑器
///
/// 支持树形结构、折叠展开、快捷键操作。
/// 通过快捷键完成节点的增删、缩进、导航等操作。
class OutlineEditor extends StatefulWidget {
  /// 颜色方案
  final ColorScheme colorScheme;

  /// 关联的本地文件路径（为空时不进行文件读写）
  final String? filePath;

  /// 内容变化回调（用于触发自动保存和备份）
  final VoidCallback? onContentChanged;

  /// 保存回调（Ctrl+S 触发）
  final VoidCallback? onSave;

  /// 是否只读（备份预览时为 true）
  final bool readOnly;

  /// 统计信息变化回调（主题数、总字数）
  ///
  /// 在内容加载和内容变化时触发，用于更新外部状态栏显示。
  /// 主题数 = 所有节点总数；总字数 = 所有节点纯文本字数总和（不含样式标记符号）。
  final void Function(int topicCount, int wordCount)? onStatsChanged;

  /// 额外顶边距（用于查找替换浮窗出现时，在编辑器顶部留出空白防止遮挡文字）
  final double extraTopPadding;

  /// 内容加载完成回调
  ///
  /// 异步加载文件内容完成后触发，用于通知外部刷新查找替换结果等依赖内容的状态。
  final VoidCallback? onContentLoaded;

  const OutlineEditor({
    super.key,
    required this.colorScheme,
    this.filePath,
    this.onContentChanged,
    this.onSave,
    this.readOnly = false,
    this.onStatsChanged,
    this.extraTopPadding = 0.0,
    this.onContentLoaded,
  });

  @override
  State<OutlineEditor> createState() => OutlineEditorState();
}

class OutlineEditorState extends State<OutlineEditor> with WidgetsBindingObserver implements FindReplaceTarget {
  // ================= 常量 =================

  /// 每级缩进的像素宽度
  static const double _indentWidth = 24.0;

  /// 最大节点深度（避免节点层级过深导致显示溢出）
  static const int _maxDepth = 20;

  /// 圆点与文本间距缩减量
  static const double _dotTextGapReduction = 5.0;

  // ================= 树结构数据 =================

  /// 根节点列表
  final List<OutlineNode> _roots = [];

  /// 节点ID计数器（用于生成唯一ID）
  int _idCounter = 0;

  // ================= 控制器与焦点节点 =================

  /// 节点ID到文本控制器的映射
  final Map<String, TextEditingController> _controllers = {};

  /// 节点ID到焦点节点的映射
  final Map<String, FocusNode> _focusNodes = {};

  /// 节点瓦片的全局键映射（节点ID -> GlobalKey），用于命中检测
  final Map<String, GlobalKey> _nodeTileKeys = {};

  /// 滚动控制器
  ///
  /// 使用 [SyncScrollController] 以便在 Layout 阶段通过 [ScrollPosition.correctPixels] 同步修正滚动像素
  late final SyncScrollController _scrollController;

  /// 滚动条区域的全局键，用于命中检测判断指针是否落在滚动条上
  final GlobalKey _scrollbarKey = GlobalKey();

  /// 滚动视口的全局键，用于边缘自动滚动时取视口屏幕矩形
  final GlobalKey _scrollViewKey = GlobalKey();

  /// 编辑器级焦点节点（节点选区激活时持有焦点，用于接收键盘事件）
  final FocusNode _editorFocusNode = FocusNode();

  /// 全局撤销/恢复管理器
  ///
  /// 管理整个大纲编辑器的撤销/恢复栈，覆盖所有节点的文本编辑
  /// 和所有结构操作（增删、移动、合并、样式变更等）。
  late final OutlineUndoManager _undoManager;

  /// 编辑器滚动保护器
  ///
  /// 在窗口恢复、标签页切换等场景下锁定滚动位置，防止 TextField 获取焦点时
  /// 触发 Scrollable.ensureVisible 自动滚动到光标位置导致视口跳动
  late final EditorScrollGuard _scrollGuard;

  /// 缓存窗口最小化状态，用于检测从最小化恢复的情况
  bool _wasMinimized = false;

  /// 待补偿的额外顶边距变化量
  double? _pendingExtraPaddingDelta;

  /// 上下边距换算所依据的编辑区高度
  ///
  /// 上下边距按编辑区高度的百分比换算，而软键盘升降会压缩编辑区高度；
  /// 若直接采用实时高度，键盘动画期间节点内容会随之上下移动。
  /// 此处记录键盘收起时的编辑区高度作为基准，键盘弹出期间沿用该基准。
  double _marginBasisHeight = 0;

  /// 底部内容边距（像素）
  ///
  /// 由用户设置的底边距按编辑区高度百分比换算而来，随布局一并更新。
  /// 节点定位时以该值作为节点底部与视口底部之间应保留的安全间距。
  double _bottomContentPadding = 0;

  // ================= 选区状态 =================

  /// 当前选中的节点ID集合（多节点选区）
  final Set<String> _selectedNodeIds = {};

  /// 是否处于批量选择模式
  ///
  /// 批量选择模式下节点只能整体选中与操作，不能编辑节点文字
  bool _isBatchSelectionMode = false;

  /// 批量选择模式与节点选区的变更通知
  ///
  /// 供编辑器之外的移动端键盘工具栏监听，同步工具栏的显隐、形态与按钮可用状态
  final ValueNotifier<int> _batchRevision = ValueNotifier(0);

  /// Ctrl+A 全选状态：0=未全选，1=已全选主题，2=已全选文档
  int _selectAllLevel = 0;

  /// 选区锚点索引（Shift+click 扩展选区时的起始点）
  int? _selectionAnchorIndex;

  /// 最近获得焦点的节点ID（用于取消选区后恢复焦点）
  String? _lastFocusedNodeId;

  /// 批量选择模式下的滑选交互控制器
  ///
  /// 复用列表批量多选的统一逻辑，按住行尾竖条滑动时按区间连续选中或取消途经节点
  late final BatchSelectionController _batchSelectionController;

  /// 右键菜单当前操作的节点ID（右键点击时确定，菜单项据此操作对应节点）
  String? _contextMenuNodeId;

  // ================= 拖拽状态 =================

  /// 拖拽选区起始节点在扁平列表中的索引
  int? _dragStartIndex;

  /// 拖拽起始全局坐标
  Offset? _dragStartPosition;

  /// 拖拽选区模式：无、文本选区、节点选区
  _DragMode _dragMode = _DragMode.none;

  /// 文本选区锚点（拖拽起始处在文本中的位置）
  TextPosition? _dragTextAnchor;

  /// 拖拽起始节点ID
  String? _dragStartNodeId;

  // ================= 边缘自动滚动 =================

  /// 指针进入视口上下边缘的触发区高度（像素）
  ///
  /// 指针越过该范围后视口开始自动滚动
  static const double _autoScrollEdgeZone = 24.0;

  /// 自动滚动每帧的最大滚动步长（像素）
  static const double _autoScrollMaxStep = 14.0;

  /// 自动滚动的定时器
  Timer? _autoScrollTimer;

  /// 指针最近一次的位置（全局坐标）
  ///
  /// 视口自动滚动时指针可能保持不动，需要据此重新刷新选区
  Offset? _autoScrollPointerPosition;

  /// 自动滚动过程中按指针位置刷新选区的回调
  ///
  /// 由各类拖拽/滑选手势在开始时注入，结束或取消时清空
  void Function(Offset globalPosition)? _autoScrollSelectionUpdater;

  // ================= 其他状态 =================

  /// 是否正在异步加载文件内容
  bool _isLoading = false;

  /// 折叠状态写入任务链
  ///
  /// 因内容与结构变化都会刷新折叠状态，多次保存按此链顺序执行，避免并发写同一文件
  Future<void> _foldStateWriteChain = Future.value();

  /// 底部快捷键提示的高度（为滚动列表预留底部内边距，避免末节点被浮动提示遮挡）
  double _bottomHintHeight = 0;

  /// 是否正在唤起右键菜单（防止 focusNode 获得焦点时清除选区）
  bool _isContextMenuOpening = false;

  /// 是否正在执行撤销/重做（防止焦点变化监听器清除恢复的选区）
  bool _isUndoRedoing = false;

  /// 是否正在处理 Shift+click（防止 TextField tap 触发的焦点变化清除选区）
  bool _isShiftClicking = false;

  /// Shift+click 后待恢复的选区操作（在 PointerUp 后的帧执行，覆盖 TextField tap 的默认行为）
  VoidCallback? _pendingShiftClickRestore;

  /// 快捷键列表面板是否可见
  bool _isShortcutPanelVisible = false;

  /// 布局设置入口按钮的键，用于定位设置卡片的弹出位置
  final GlobalKey _settingsButtonKey = GlobalKey();

  /// 布局设置卡片是否已展开
  bool _isSettingsCardVisible = false;

  // ================= 生命周期 =================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = SyncScrollController(onApplyContentDimensions: _onApplyContentDimensions);
    _scrollGuard = EditorScrollGuard(_scrollController);

    // 初始化批量选择滑选交互控制器，按住行尾竖条滑动时按区间连续选中或取消途经节点
    _batchSelectionController = BatchSelectionController(
      getSelectedIds: () => _selectedNodeIds,
      getFlatDisplayIds: () => _flatten().map((flat) => flat.node.id).toList(),
      onChanged: () {
        if (!mounted) return;
        _selectAllLevel = 0;
        setState(() {});
        _notifyBatchChanged();
      },
      hitTestId: _hitTestNodeIdAt,
    );

    // 监听设置变化，以便布局设置变更时重新构建
    SettingsService.instance.addListener(_onSettingsChanged);

    // 先创建撤销管理器，确保后续创建的控制器能被注册
    _undoManager = OutlineUndoManager(captureSnapshot: captureUndoSnapshot, applySnapshot: applyUndoSnapshot);

    // 从关联文件加载内容
    if (widget.filePath != null && widget.filePath!.isNotEmpty) {
      _loadFromFile();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopEdgeAutoScroll();
    _scrollGuard.dispose();
    SettingsService.instance.removeListener(_onSettingsChanged);
    _undoManager.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _editorFocusNode.dispose();
    _scrollController.dispose();
    _batchRevision.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 应用从后台恢复时开启滚动保护，防止 TextField 自动滚动到光标位置
    if (state == AppLifecycleState.resumed) {
      _scrollGuard.protect(const Duration(milliseconds: 300));
    }
  }

  @override
  void didUpdateWidget(covariant OutlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 查找替换栏显示/隐藏导致额外顶边距变化时，记录变化量供 Layout 阶段补偿滚动偏移
    if (widget.extraTopPadding != oldWidget.extraTopPadding) {
      final delta = widget.extraTopPadding - oldWidget.extraTopPadding;
      if (delta != 0) {
        _pendingExtraPaddingDelta = delta;
      }
    }
  }

  /// 在 Layout 阶段拦截并修正滚动像素
  ///
  /// 通过 [SyncScrollPosition.applyContentDimensions] 拦截，在 Paint 之前通过
  /// [ScrollPosition.correctPixels] 修正位置，避免闪烁。此方法在每次 Viewport 布局时被调用。
  void _onApplyContentDimensions(ScrollPosition position, double minExt, double maxExt) {
    // 补偿额外顶边距变化导致的滚动偏移，保持视口内内容位置不变
    if (_pendingExtraPaddingDelta != null) {
      final targetOffset = (position.pixels + _pendingExtraPaddingDelta!).clamp(minExt, maxExt);
      if ((position.pixels - targetOffset).abs() > 0.5) {
        position.correctPixels(targetOffset);
        // 同步更新滚动保护的目标偏移量，避免保护器将滚动位置拉回补偿前的值导致视口内容闪烁（关闭查找替换时光标不在视口内时尤为明显）
        _scrollGuard.retarget();
      }
      _pendingExtraPaddingDelta = null;
    }
  }

  /// 处理设置变化
  void _onSettingsChanged() {
    if (mounted) {
      setState(() {
        // 重新构建以应用新的布局设置
      });
    }
  }

  // ================= 树结构数据工具 =================

  /// 生成唯一节点ID
  String _generateId() {
    _idCounter++;
    return 'node_$_idCounter';
  }

  /// 创建新节点
  OutlineNode _createNode(String text) {
    return OutlineNode(id: _generateId(), text: text);
  }

  /// 扁平化树形结构为一维列表（仅包含可见的展开节点）
  List<FlatNode> _flatten() {
    final result = <FlatNode>[];

    void walk(OutlineNode node, int depth, OutlineNode? parent) {
      result.add(FlatNode(node: node, depth: depth, parent: parent));
      if (node.isExpanded) {
        for (final child in node.children) {
          walk(child, depth + 1, node);
        }
      }
    }

    for (final root in _roots) {
      walk(root, 0, null);
    }
    return result;
  }

  /// 查找节点的位置信息（父节点和在父节点children中的索引）
  ({OutlineNode? parent, int index})? _findLocation(String id) {
    ({OutlineNode? parent, int index})? search(List<OutlineNode> nodes, OutlineNode? parent) {
      for (int i = 0; i < nodes.length; i++) {
        if (nodes[i].id == id) {
          return (parent: parent, index: i);
        }
        final result = search(nodes[i].children, nodes[i]);
        if (result != null) return result;
      }
      return null;
    }

    return search(_roots, null);
  }

  /// 查找节点
  OutlineNode? _findNode(String id) {
    final location = _findLocation(id);
    if (location == null) return null;
    final siblings = location.parent?.children ?? _roots;
    if (location.index >= siblings.length) return null;
    return siblings[location.index];
  }

  /// 获取节点的所有同级节点 ID（包含自身）
  ///
  /// 同级节点指具有相同父节点的节点；根节点的同级为所有根节点。
  List<String> _getSiblingNodeIds(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null) return [nodeId];
    final siblings = location.parent?.children ?? _roots;
    return siblings.map((node) => node.id).toList();
  }

  /// 计算节点子树的最大相对深度（节点自身为 0，每深入一层加 1）
  ///
  /// 用于缩进前判断子树整体下移后是否会超过最大深度限制
  int _subtreeHeight(OutlineNode node) {
    int height = 0;
    for (final child in node.children) {
      final childHeight = _subtreeHeight(child) + 1;
      if (childHeight > height) height = childHeight;
    }
    return height;
  }

  /// 获取节点的最后一个后代（文档顺序最末的子孙节点）
  OutlineNode _lastDescendant(OutlineNode node) {
    while (node.children.isNotEmpty) {
      node = node.children.last;
    }
    return node;
  }

  // ================= 资源管理 =================

  /// 为单个节点创建控制器和焦点节点
  void _ensureResources(OutlineNode node) {
    if (!_controllers.containsKey(node.id)) {
      final controller = RichTextEditingController(text: node.text, styleResolver: defaultStyleResolver);
      // 同步节点的样式区间到控制器
      controller.styleRanges = List.of(node.styleRanges);
      _controllers[node.id] = controller;
      // 注册到撤销管理器，监听文本变化
      _undoManager.registerController(node.id, controller);
    }
    if (!_focusNodes.containsKey(node.id)) {
      final focusNode = FocusNode();
      focusNode.onKeyEvent = (FocusNode fn, KeyEvent event) {
        return _onKeyEvent(fn, event, node.id);
      };
      // 监听焦点变化，记录最近获得焦点的节点
      focusNode.addListener(() {
        if (focusNode.hasFocus) {
          _lastFocusedNodeId = node.id;
          // 输入框获得焦点时清除节点选区（Shift+click、右键菜单唤起、撤销/重做时除外）
          if (!_isShiftClicking &&
              !_isContextMenuOpening &&
              !_isUndoRedoing &&
              (_selectedNodeIds.isNotEmpty || _selectAllLevel != 0)) {
            _selectedNodeIds.clear();
            _selectAllLevel = 0;
            if (mounted) setState(() {});
          }
          // 重置选区锚点：点击输入框获得焦点后，Shift+click 应以当前焦点节点为起始
          if (!_isShiftClicking && !_isContextMenuOpening && !_isUndoRedoing) {
            _selectionAnchorIndex = null;
          }
        }
      });
      _focusNodes[node.id] = focusNode;
    }
    // 预创建全局键，使未构建的节点也能被定位滚动
    if (!_nodeTileKeys.containsKey(node.id)) {
      _nodeTileKeys[node.id] = GlobalKey();
    }
  }

  /// 递归确保节点及其子节点都有控制器和焦点节点
  void _ensureResourcesForNode(OutlineNode node) {
    _ensureResources(node);
    for (final child in node.children) {
      _ensureResourcesForNode(child);
    }
  }

  /// 同步控制器/焦点节点/全局键与当前树结构
  ///
  /// 遍历树中所有节点：为新节点创建资源，为已存在节点更新文本内容
  /// （快照中的文本可能与当前控制器不同）；移除树中已不存在的节点资源。
  void _syncResourcesWithTree() {
    // 收集当前树中的所有节点 ID 及对应的节点引用
    final Map<String, OutlineNode> existingNodes = {};
    void walk(OutlineNode node) {
      existingNodes[node.id] = node;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }

    // 为树中所有节点确保资源已创建，并同步文本内容和样式区间
    for (final entry in existingNodes.entries) {
      _ensureResources(entry.value);
      final controller = _controllers[entry.value.id];
      if (controller == null) continue;
      // 同步控制器文本与节点文本（不触发选区变化）
      if (controller.text != entry.value.text) {
        controller.text = entry.value.text;
      }
      // 同步样式区间到富文本控制器
      if (controller is RichTextEditingController) {
        controller.styleRanges = entry.value.styleRanges;
      }
    }

    // 释放树中已不存在的节点资源
    final staleIds = <String>[];
    for (final id in _controllers.keys) {
      if (!existingNodes.containsKey(id)) {
        staleIds.add(id);
      }
    }
    for (final id in staleIds) {
      final controller = _controllers[id];
      if (controller != null) {
        _undoManager.unregisterController(id, controller);
        controller.dispose();
        _controllers.remove(id);
      }
      _focusNodes[id]?.dispose();
      _focusNodes.remove(id);
      _nodeTileKeys.remove(id);
    }
  }

  // ================= 文件读写 =================

  /// 从关联的文件加载大纲内容
  ///
  /// 文件不存在时视为新设定项，初始化一个默认空节点
  Future<void> _loadFromFile() async {
    _isLoading = true;
    try {
      final file = File(widget.filePath!);
      if (await file.exists()) {
        final text = await file.readAsString();
        parseFromText(text);
        // 恢复上次退出时的节点折叠状态
        await _loadFoldState();
      } else {
        // 文件不存在时视为新设定项，初始化默认空节点
        parseFromText('');
      }
    } catch (e) {
      debugPrint('加载大纲文件失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // 通知外部内容已加载完成，用于刷新查找替换等依赖内容的状态
        widget.onContentLoaded?.call();
      }
    }
  }

  /// 将大纲树序列化为纯文本
  ///
  /// 格式：每行一个节点，行首制表符表示层级深度。
  /// 节点内容使用 Markdown 格式：
  /// - 标题级别转换为行首 `#` 前缀（H1=`#`，H2=`##`，H3=`###`）
  /// - 文字样式转换为内联标记（`**`、`*`、`~~`、`<u>`）
  String serializeToText() {
    final buffer = StringBuffer();
    void walk(OutlineNode node, int depth) {
      // 写入缩进（每级一个制表符）
      buffer.write('\t' * depth);
      // 序列化为 Markdown 格式
      buffer.writeln(OutlineMarkdownCodec.serialize(node));
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    for (final root in _roots) {
      walk(root, 0);
    }
    return buffer.toString();
  }

  /// 从纯文本解析大纲树
  ///
  /// 支持制表符和 4 空格缩进表示层级。
  /// 节点内容支持 Markdown 格式，解析标题级别和内联样式标记。
  void parseFromText(String text) {
    _roots.clear();
    // 栈中保存 (节点, 深度) 对
    final stack = <(OutlineNode, int)>[];

    final lines = text.split('\n');
    for (final rawLine in lines) {
      // 跳过空行（末尾换行产生的空行）
      if (rawLine.isEmpty) continue;

      // 计算行首制表符数量，确定层级深度
      var depth = 0;
      var line = rawLine;
      while (line.startsWith('\t')) {
        if (depth < _maxDepth) {
          depth++;
        }
        line = line.substring(1);
      }
      // 兼容 4 空格缩进
      while (line.startsWith('    ')) {
        if (depth < _maxDepth) {
          depth++;
        }
        line = line.substring(4);
      }

      // 从 Markdown 解析标题级别和样式区间
      final parsed = OutlineMarkdownCodec.deserialize(line);
      final node = OutlineNode(
        id: _generateId(),
        text: parsed.text,
        headingLevel: parsed.headingLevel,
        styleRanges: parsed.styleRanges,
      );

      // 弹出栈中深度大于等于当前深度的节点
      while (stack.isNotEmpty && stack.last.$2 >= depth) {
        stack.removeLast();
      }

      if (stack.isEmpty) {
        _roots.add(node);
      } else {
        stack.last.$1.children.add(node);
      }
      stack.add((node, depth));
    }

    // 解析结果为空时创建一个默认空节点，始终保证至少有一个节点存在
    if (_roots.isEmpty) {
      _roots.add(_createNode(''));
    }

    // 同步资源：为新节点创建控制器/焦点节点，清理已不存在的节点资源
    _syncResourcesWithTree();

    // 重置选区状态
    _selectedNodeIds.clear();
    _selectAllLevel = 0;
    _selectionAnchorIndex = null;

    if (mounted) {
      setState(() {});
    }

    // 通知统计信息更新（初始加载或备份恢复后）
    _notifyStatsChanged();
  }

  /// 保存大纲内容到关联的文件
  ///
  /// 返回是否保存成功
  Future<bool> saveToFile() async {
    if (widget.filePath == null || widget.filePath!.isEmpty) {
      return false;
    }
    try {
      final file = File(widget.filePath!);
      // 确保父目录存在
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString(serializeToText());
      // 结构变化会改变节点路径，随内容一并刷新折叠状态
      _saveFoldState();
      return true;
    } catch (e) {
      debugPrint('保存大纲文件失败: $e');
      return false;
    }
  }

  /// 折叠状态文件路径
  ///
  /// 与大纲文件同目录同名、扩展名替换为 `.fold.json`，
  /// 独立存放可避免折叠标记混入正文，影响导出与备份的内容。
  String? get _foldStateFilePath {
    final String? path = widget.filePath;
    if (path == null || path.isEmpty) return null;
    const String extension = GlobalConstants.settingFileExtension;
    final String base = path.endsWith(extension)
        ? path.substring(0, path.length - extension.length)
        : path;
    return '$base.fold.json';
  }

  /// 从文件读取折叠状态并应用到当前大纲树
  Future<void> _loadFoldState() async {
    final String? path = _foldStateFilePath;
    if (path == null) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final dynamic data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      final Set<String>? collapsed =
          (data['collapsed'] as List?)?.whereType<String>().toSet();
      if (collapsed == null || collapsed.isEmpty || !mounted) return;
      setState(() => _applyFoldState(collapsed));
    } catch (e) {
      debugPrint('加载大纲折叠状态失败: $e');
    }
  }

  /// 保存折叠状态到文件
  ///
  /// 连续操作会触发多次保存，写入按任务链串行执行，
  /// 避免同一文件的并发写使内容交错。
  void _saveFoldState() {
    if (widget.readOnly) return;
    final String? path = _foldStateFilePath;
    if (path == null) return;
    _foldStateWriteChain = _foldStateWriteChain.then((_) => _writeFoldStateFile(path));
  }

  /// 将当前折叠状态写入指定文件
  Future<void> _writeFoldStateFile(String path) async {
    try {
      final file = File(path);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString(jsonEncode({'collapsed': _collectCollapsedPaths()}));
    } catch (e) {
      debugPrint('保存大纲折叠状态失败: $e');
    }
  }

  /// 收集全部折叠节点的路径
  ///
  /// 节点 ID 每次解析文件都会重新生成，无法跨次加载对应到同一节点，
  /// 因此改用「自根节点起的层级索引路径」标识节点。
  List<String> _collectCollapsedPaths() {
    final paths = <String>[];
    void walk(OutlineNode node, String path) {
      if (!node.isExpanded) paths.add(path);
      for (int i = 0; i < node.children.length; i++) {
        walk(node.children[i], '$path.$i');
      }
    }

    for (int i = 0; i < _roots.length; i++) {
      walk(_roots[i], '$i');
    }
    return paths;
  }

  /// 按节点路径应用折叠状态
  ///
  /// 路径存在于折叠集合中的节点收起子节点，其余节点保持展开。
  void _applyFoldState(Set<String> collapsedPaths) {
    void walk(OutlineNode node, String path) {
      node.isExpanded = !collapsedPaths.contains(path);
      for (int i = 0; i < node.children.length; i++) {
        walk(node.children[i], '$path.$i');
      }
    }

    for (int i = 0; i < _roots.length; i++) {
      walk(_roots[i], '$i');
    }
  }

  // ================= 统计与通知 =================

  /// 通知内容已变化
  ///
  /// 由编辑器的各类操作在修改数据后调用，触发外部自动保存和备份
  void _notifyContentChanged() {
    widget.onContentChanged?.call();
    _notifyStatsChanged();
  }

  /// 通知统计信息变化
  ///
  /// 计算当前大纲的主题数（所有节点数量）和总字数（所有节点纯文本字数总和），
  /// 通过回调通知外部更新状态栏显示。
  void _notifyStatsChanged() {
    widget.onStatsChanged?.call(_countNodes(), _computeWordCount());
  }

  /// 计算大纲所有节点的总数（包含根节点及其所有子孙节点）
  int _countNodes() {
    int count = 0;
    void walk(OutlineNode node) {
      count++;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }
    return count;
  }

  /// 计算大纲所有节点的总字数
  ///
  /// 遍历所有节点的纯文本（node.text，不含样式序列化标记符号），
  /// 使用字数统计工具计算每个节点的字数并累加。
  int _computeWordCount() {
    int wordCount = 0;
    void walk(OutlineNode node) {
      wordCount += WordCountUtils.countWords(node.text);
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }
    return wordCount;
  }

  /// 结束批量操作并通知内容变化
  ///
  /// 在结构操作（增删、移动、合并等）完成后调用，
  /// 既记录撤销项，又通知外部触发自动保存和备份
  void _endBatchAndNotify({required String description, String? focusNodeId, TextSelection? focusSelection}) {
    _undoManager.endBatch(description: description, focusNodeId: focusNodeId, focusSelection: focusSelection);
    _notifyContentChanged();
    // 结构变化会改变节点路径，同步刷新折叠状态，避免下次加载对应到错误的节点
    _saveFoldState();
  }

  // ================= 撤销/恢复 =================

  /// 捕获当前大纲编辑器的状态快照
  ///
  /// 由 [OutlineUndoManager] 在 beginBatch/endBatch 和撤销/重做时调用。
  /// 返回的快照包含整树的深拷贝以及当前的焦点、选区状态。
  ///
  /// 可选参数 [focusNodeId] / [focusSelection] 用于异步聚焦场景：
  /// 当 hasFocus 尚未及时生效时，由调用方显式指定焦点节点和选区，
  /// 优先于自动检测的实际焦点。
  ///
  /// 可选参数 [nodeTextOverrides] 用于文本编辑场景：
  /// 控制器变化监听器触发时，节点的 text 字段尚未通过 onChanged 同步到最新值，
  /// 传入 {nodeId: text} 可在深拷贝后覆盖对应节点的文本，确保快照记录正确文本。
  /// 传 null 时（结构操作场景），会从控制器同步所有节点的文本，避免遗漏。
  OutlineTreeSnapshot captureUndoSnapshot({
    String? focusNodeId,
    TextSelection? focusSelection,
    Map<String, String>? nodeTextOverrides,
  }) {
    // 深拷贝整棵树，避免后续修改影响快照
    final rootsClone = _roots.map((r) => r.clone()).toList();

    // 在克隆的树上修正节点文本，确保快照捕获的是正确的文本状态
    if (nodeTextOverrides != null) {
      // 文本编辑场景：用指定的文本覆盖对应节点
      void applyOverride(OutlineNode node) {
        final text = nodeTextOverrides[node.id];
        if (text != null) {
          node.text = text;
        }
        for (final child in node.children) {
          applyOverride(child);
        }
      }

      for (final root in rootsClone) {
        applyOverride(root);
      }
    } else {
      // 结构操作场景：从控制器同步所有节点文本，
      // 防止用户刚输入但 onChanged 尚未同步时捕获到旧文本
      void syncFromController(OutlineNode node) {
        final controller = _controllers[node.id];
        if (controller != null && controller.text != node.text) {
          node.text = controller.text;
        }
        for (final child in node.children) {
          syncFromController(child);
        }
      }

      for (final root in rootsClone) {
        syncFromController(root);
      }
    }

    String? focusedNodeId;
    TextSelection? focusedSelection;

    if (focusNodeId != null) {
      // 显式指定的焦点节点：优先于自动检测
      focusedNodeId = focusNodeId;
      if (focusSelection != null) {
        focusedSelection = focusSelection;
      } else {
        final controller = _controllers[focusNodeId];
        if (controller != null) {
          focusedSelection = controller.selection;
        }
      }
    } else {
      // 自动检测当前实际焦点节点
      for (final entry in _focusNodes.entries) {
        if (entry.value.hasFocus) {
          focusedNodeId = entry.key;
          final controller = _controllers[entry.key];
          if (controller != null) {
            focusedSelection = controller.selection;
          }
          break;
        }
      }
      // 编辑器级焦点激活（节点选区模式）时，使用最近编辑的节点作为焦点记录
      if (focusedNodeId == null && _editorFocusNode.hasFocus && _lastFocusedNodeId != null) {
        focusedNodeId = _lastFocusedNodeId;
        final controller = _controllers[focusedNodeId];
        if (controller != null) {
          focusedSelection = controller.selection;
        }
      }
    }

    return OutlineTreeSnapshot(
      roots: rootsClone,
      focusedNodeId: focusedNodeId,
      focusedSelection: focusedSelection,
      selectedNodeIds: Set<String>.from(_selectedNodeIds),
      selectAllLevel: _selectAllLevel,
      selectionAnchorIndex: _selectionAnchorIndex,
    );
  }

  /// 应用状态快照（撤销/重做时调用）
  ///
  /// 用快照中的树结构替换当前树，并同步控制器、焦点节点等资源，
  /// 然后恢复焦点、选区和文字样式状态。
  /// 同步执行焦点和选区恢复，避免 post-frame 回调交叉导致状态错乱。
  void applyUndoSnapshot(OutlineTreeSnapshot snapshot) {
    // 深拷贝快照中的树，避免后续修改污染原快照
    // （applyUndoSnapshot 后，_roots 会持有节点引用，onChanged 等回调会直接修改节点，
    //   若不深拷贝，这些修改会污染撤销栈中已保存的快照，导致循环撤销时状态错乱）
    _roots
      ..clear()
      ..addAll(snapshot.roots.map((r) => r.clone()));

    // 同步控制器/焦点节点/全局键与新的树结构
    _syncResourcesWithTree();

    // 恢复多节点选区状态
    _selectedNodeIds
      ..clear()
      ..addAll(snapshot.selectedNodeIds);
    _selectAllLevel = snapshot.selectAllLevel;
    _selectionAnchorIndex = snapshot.selectionAnchorIndex;

    setState(() {});

    // 同步恢复焦点和选区，不依赖 post-frame，避免多次撤销/重做时回调交叉
    _restoreFocusFromSnapshot(snapshot);

    // 通知统计信息更新（撤销/重做后内容已变化）
    _notifyStatsChanged();
  }

  /// 从快照恢复焦点和文本选区
  ///
  /// 同步执行焦点请求和选区设置，确保撤销/重做后光标位置正确。
  /// 同时注册一个 post-frame 回调作为兜底，防止 TextField 内部行为覆盖选区。
  void _restoreFocusFromSnapshot(OutlineTreeSnapshot snapshot) {
    // 移动端不主动唤起输入法，仅在桌面端恢复焦点，移动端只恢复选区
    final bool canRequestFocus = !PlatformCapabilities.isMobile;
    final focusedId = snapshot.focusedNodeId;
    if (focusedId == null) {
      // 无焦点记录时，若有节点选区则激活编辑器焦点
      if (_selectedNodeIds.isNotEmpty && canRequestFocus) {
        _editorFocusNode.requestFocus();
      }
      return;
    }

    final focusNode = _focusNodes[focusedId];
    final controller = _controllers[focusedId];
    if (focusNode == null || controller == null) {
      // 节点资源不存在（可能已被移除），降级为编辑器焦点
      if (_selectedNodeIds.isNotEmpty && canRequestFocus) {
        _editorFocusNode.requestFocus();
      }
      return;
    }

    // 同步请求焦点
    if (canRequestFocus) {
      focusNode.requestFocus();
    }

    // 同步设置选区（清除 composing 状态防止输入法残留）
    final selection = snapshot.focusedSelection;
    if (selection != null && selection.isValid) {
      controller.value = controller.value.copyWith(selection: selection, composing: TextRange.empty);
    } else {
      // 无有效选区记录时，光标置于文本末尾
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }

    // post-frame 兜底：仅当 TextField rebuild 后选区被覆盖时才重新应用，避免覆盖已正确的选区
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (selection != null && selection.isValid && controller.selection != selection) {
        controller.selection = selection;
      }
      // 恢复的焦点节点可能位于视口之外而尚未构建，需在布局完成后滚动使其可见
      _scrollToNode(focusedId);
    });
  }

  /// 是否可撤销（只读模式下不可撤销）
  bool get canUndo => !widget.readOnly && _undoManager.canUndo;

  /// 是否可重做（只读模式下不可重做）
  bool get canRedo => !widget.readOnly && _undoManager.canRedo;

  /// 执行撤销操作
  ///
  /// 返回 true 表示成功执行；false 表示撤销栈为空，未执行任何操作。
  /// 设置 [_isUndoRedoing] 标志，防止焦点变化监听器清除恢复的选区。
  /// 标志在下一帧重置（兜底 post-frame 选区恢复执行后）。
  bool undo() {
    _isUndoRedoing = true;
    final result = _undoManager.undo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isUndoRedoing = false;
    });
    // 撤销改变了文档内容，需通知外部标记修改并触发自动保存
    if (result) _notifyContentChanged();
    return result;
  }

  /// 执行重做操作
  ///
  /// 返回 true 表示成功执行；false 表示重做栈为空，未执行任何操作。
  /// 设置 [_isUndoRedoing] 标志，防止焦点变化监听器清除恢复的选区。
  /// 标志在下一帧重置（兜底 post-frame 选区恢复执行后）。
  bool redo() {
    _isUndoRedoing = true;
    final result = _undoManager.redo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isUndoRedoing = false;
    });
    // 恢复改变了文档内容，需通知外部标记修改并触发自动保存
    if (result) _notifyContentChanged();
    return result;
  }

  /// 构造光标位于文本开头的选区（用于 endBatch 的 focusSelection 参数）
  TextSelection _selectionAtStart() => const TextSelection.collapsed(offset: 0);

  /// 构造光标位于指定节点文本末尾的选区（用于 endBatch 的 focusSelection 参数）
  TextSelection _selectionAtEnd(String nodeId) {
    final controller = _controllers[nodeId];
    if (controller != null) {
      return TextSelection.collapsed(offset: controller.text.length);
    }
    final node = _findNode(nodeId);
    return TextSelection.collapsed(offset: node?.text.length ?? 0);
  }

  // ================= 焦点与滚动 =================

  /// 在节点间移动焦点
  ///
  /// [forward] 为 true 向下移动，false 向上移动
  void _moveFocus(String nodeId, bool forward) {
    final flatList = _flatten();
    final currentIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    if (currentIndex == -1) return;

    final targetIndex = forward ? currentIndex + 1 : currentIndex - 1;
    if (targetIndex < 0 || targetIndex >= flatList.length) return;

    final targetId = flatList[targetIndex].node.id;
    _focusNodeWithSelection(targetId, moveCursorToEnd: !forward);
  }

  /// 聚焦指定节点并设置光标位置
  ///
  /// [ensureVisible] 为 true 时立即把节点滚动进视口：
  /// 节点可能位于视口之外而尚未构建，仅请求焦点不会带动视口，
  /// 因此交由 [_scrollToNode] 滚动并按需重试定位。
  void _focusNodeWithSelection(
    String nodeId, {
    required bool moveCursorToEnd,
    bool ensureVisible = true,
  }) {
    final focusNode = _focusNodes[nodeId];
    final controller = _controllers[nodeId];
    if (focusNode == null || controller == null) return;

    focusNode.requestFocus();
    final offset = moveCursorToEnd ? controller.text.length : 0;
    controller.selection = TextSelection.fromPosition(TextPosition(offset: offset));

    if (ensureVisible) {
      _scrollToNode(nodeId);
    }
  }

  /// 聚焦指定节点并滚动到视口中可见
  ///
  /// 对于未构建的节点（位于视口外），先估算位置滚动使其进入构建范围，
  /// 再在下一帧精确滚动到视口中央并聚焦。
  /// 估算失败时改用逐步滚动扫描，直到节点被构建。
  void _focusAndScrollToNode(
    String nodeId, {
    required bool moveCursorToEnd,
    int retryCount = 0,
    double? lastJumpOffset,
  }) {
    if (!mounted) return;

    final key = _nodeTileKeys[nodeId];
    final context = key?.currentContext;

    // 节点已构建：精确滚动到视口中央并聚焦
    if (context != null && context.findRenderObject()?.attached == true) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ).then((_) {
        if (mounted) {
          _focusNodeWithSelection(nodeId, moveCursorToEnd: moveCursorToEnd, ensureVisible: false);
        }
      });
      return;
    }

    // 无法滚动或超过最大重试次数：放弃聚焦
    // 不调用 requestFocus，避免在未附加的 FocusNode 上设置延迟焦点，
    // 否则节点后续构建附加时会自动抢焦点导致视口突跳
    if (!_scrollController.hasClients || retryCount >= 30) return;

    final flatList = _flatten();
    final targetIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    if (targetIndex == -1) return;

    // 测量已构建节点的平均高度作为估算基准
    double totalHeight = 0;
    int measuredCount = 0;
    for (final flat in flatList) {
      final k = _nodeTileKeys[flat.node.id];
      final box = k?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.size.height > 0) {
        totalHeight += box.size.height;
        measuredCount++;
      }
    }
    final estimatedHeight = measuredCount > 0 ? totalHeight / measuredCount : 40.0;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final currentOffset = _scrollController.offset;
    final estimatedOffset = (targetIndex * estimatedHeight).clamp(0.0, maxExtent);

    double jumpTarget;
    // 若估算偏移与上次跳转位置一致（说明估算无效，节点仍未构建），
    // 改用逐步滚动扫描，确保目标区域节点被构建
    if (lastJumpOffset != null && (estimatedOffset - lastJumpOffset).abs() < 1.0) {
      final viewport = _scrollController.position.viewportDimension;
      jumpTarget = (currentOffset + viewport * 0.6).clamp(0.0, maxExtent);
      // 已到达底部仍无法构建目标节点，放弃聚焦
      if (jumpTarget <= currentOffset + 1.0) return;
    } else {
      jumpTarget = estimatedOffset;
    }

    _scrollController.position.jumpTo(jumpTarget);

    // 跳转后下一帧重试（目标节点应已构建）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusAndScrollToNode(
        nodeId,
        moveCursorToEnd: moveCursorToEnd,
        retryCount: retryCount + 1,
        lastJumpOffset: jumpTarget,
      );
    });
  }

  // ================= 节点结构操作 =================

  /// 创建同级新节点
  ///
  /// 按就近原则在光标位置插入新节点：
  /// - 光标在开头：在当前节点上方插入空节点，将当前行下推；
  /// - 光标在中段：分割文本，有子节点时新节点在上方承载前半部分（保留子节点随当前节点下移），
  ///   无子节点时新节点在下方承载后半部分；
  /// - 光标在末尾：有子节点时在子节点列表开头插入新子节点，无子节点时在下方插入同级空节点。
  void _createSibling(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null) return;

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    final siblings = location.parent?.children ?? _roots;
    final currentNode = siblings[location.index];
    final controller = _controllers[nodeId]!;
    final selection = controller.selection;
    final text = controller.text;
    final hasChildren = currentNode.children.isNotEmpty;

    // 光标在文本开头（且非空）：在当前节点上方插入空节点，将当前行下推
    if (selection.isCollapsed && selection.baseOffset == 0 && text.isNotEmpty) {
      final newNode = _createNode('');
      _ensureResources(newNode);
      siblings.insert(location.index, newNode);

      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodeWithSelection(newNode.id, moveCursorToEnd: false);
        _endBatchAndNotify(description: '创建同级节点', focusNodeId: newNode.id, focusSelection: _selectionAtStart());
      });
      return;
    }

    // 光标在文本中段：分割文本
    if (selection.isCollapsed && selection.baseOffset > 0 && selection.baseOffset < text.length) {
      final textBefore = text.substring(0, selection.baseOffset);
      final textAfter = text.substring(selection.baseOffset);

      if (hasChildren) {
        // 有子节点：在当前节点上方插入新节点承载前半部分，当前节点保留后半部分和子节点
        final newNode = _createNode(textBefore);
        _ensureResources(newNode);
        siblings.insert(location.index, newNode);

        controller.text = textAfter;
        currentNode.text = textAfter;

        setState(() {});

        // 聚焦当前节点开头（光标后内容）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodeWithSelection(currentNode.id, moveCursorToEnd: false);
          _endBatchAndNotify(description: '创建同级节点', focusNodeId: currentNode.id, focusSelection: _selectionAtStart());
        });
        return;
      }

      // 无子节点：前半部分留当前节点，新节点在下方承载后半部分
      controller.text = textBefore;
      currentNode.text = textBefore;

      final newNode = _createNode(textAfter);
      _ensureResources(newNode);
      siblings.insert(location.index + 1, newNode);

      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodeWithSelection(newNode.id, moveCursorToEnd: false);
        _endBatchAndNotify(description: '创建同级节点', focusNodeId: newNode.id, focusSelection: _selectionAtStart());
      });
      return;
    }

    // 光标在文本末尾：就近原则，有子节点时新节点成为第一个子节点，否则成为下方同级节点
    if (selection.isCollapsed && selection.baseOffset == text.length) {
      if (hasChildren) {
        // 有子节点：在子节点列表开头插入空子节点
        final newNode = _createNode('');
        _ensureResources(newNode);
        currentNode.children.insert(0, newNode);
        currentNode.isExpanded = true;

        setState(() {});

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodeWithSelection(newNode.id, moveCursorToEnd: false);
          _endBatchAndNotify(description: '创建同级节点', focusNodeId: newNode.id, focusSelection: _selectionAtStart());
        });
        return;
      }

      // 无子节点：在当前节点下方插入同级空节点
      final newNode = _createNode('');
      _ensureResources(newNode);
      siblings.insert(location.index + 1, newNode);

      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodeWithSelection(newNode.id, moveCursorToEnd: false);
        _endBatchAndNotify(description: '创建同级节点', focusNodeId: newNode.id, focusSelection: _selectionAtStart());
      });
      return;
    }

    // 其他情况（如非折叠选区）：在当前节点后插入空节点
    final newNode = _createNode('');
    _ensureResources(newNode);
    siblings.insert(location.index + 1, newNode);

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodeWithSelection(newNode.id, moveCursorToEnd: false);
      _endBatchAndNotify(description: '创建同级节点', focusNodeId: newNode.id, focusSelection: _selectionAtStart());
    });
  }

  /// 判断节点是否可以缩进
  ///
  /// 存在前一兄弟节点，且整棵子树下移一级后不超过最大深度限制时返回 true。
  bool _canIndentNode(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null) return false;

    final siblings = location.parent?.children ?? _roots;
    // 第一个节点无法缩进（没有前一个兄弟节点）
    if (location.index == 0) return false;

    // 检查缩进后是否超过最大节点深度限制
    final flatList = _flatten();
    final nodeFlatIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    if (nodeFlatIndex == -1) return true;

    final nodeDepth = flatList[nodeFlatIndex].depth;
    // 缩进后子树最大深度 = 节点新深度 + 子树高度
    return nodeDepth + 1 + _subtreeHeight(siblings[location.index]) <= _maxDepth;
  }

  /// 缩进节点（变成前一兄弟节点的子节点）
  void _indentNode(String nodeId) {
    if (!_canIndentNode(nodeId)) return;

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    _applyIndentNode(nodeId);

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodeWithSelection(nodeId, moveCursorToEnd: true);
      _endBatchAndNotify(description: '缩进节点', focusNodeId: nodeId, focusSelection: _selectionAtEnd(nodeId));
    });
  }

  /// 将节点移动到前一兄弟节点之下（不处理撤销记录与焦点）
  ///
  /// 调用前需确保该节点存在前一兄弟节点。
  void _applyIndentNode(String nodeId) {
    final location = _findLocation(nodeId)!;
    final siblings = location.parent?.children ?? _roots;
    _moveNodeUnderParent(nodeId, siblings[location.index - 1]);
  }

  /// 将节点移动到指定父节点的子节点列表末尾（不处理撤销记录与焦点）
  ///
  /// 目标父节点需与原父节点同处一级，保证移动后的层级关系正确。
  void _moveNodeUnderParent(String nodeId, OutlineNode parent) {
    final location = _findLocation(nodeId);
    if (location == null) return;

    final siblings = location.parent?.children ?? _roots;
    final node = siblings.removeAt(location.index);
    parent.children.add(node);
    // 缩进后自动展开父节点，使新子节点可见
    parent.isExpanded = true;
  }

  /// 查找节点批量缩进时的目标父节点
  ///
  /// 自该节点向前查找第一个未被选中的兄弟节点；批量缩进时被选中的兄弟节点会一起上移，
  /// 不能作为父节点，否则会在被缩进的节点之间层层嵌套。
  /// 找不到未被选中的前兄弟节点时返回 null，表示该节点无法缩进。
  OutlineNode? _indentTargetParent(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null) return null;

    final siblings = location.parent?.children ?? _roots;
    for (int i = location.index - 1; i >= 0; i--) {
      if (!_selectedNodeIds.contains(siblings[i].id)) return siblings[i];
    }
    return null;
  }

  /// 批量缩进时判断节点是否可以缩进
  ///
  /// 除单个节点的缩进条件外，还要求存在未被选中的前兄弟节点作为移动目标
  bool _canBatchIndentNode(String nodeId) =>
      _canIndentNode(nodeId) && _indentTargetParent(nodeId) != null;

  /// 反缩进节点（提升一级，变成父节点的兄弟节点）
  void _outdentNode(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null || location.parent == null) return;

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    _applyOutdentNode(nodeId);

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodeWithSelection(nodeId, moveCursorToEnd: true);
      _endBatchAndNotify(description: '反缩进节点', focusNodeId: nodeId, focusSelection: _selectionAtEnd(nodeId));
    });
  }

  /// 将节点提升一级，变为父节点的兄弟节点（不处理撤销记录与焦点）
  ///
  /// 节点已位于根级时不产生任何变化。
  void _applyOutdentNode(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null || location.parent == null) return;

    final parent = location.parent!;
    final grandparentLocation = _findLocation(parent.id);
    if (grandparentLocation == null) return;

    final grandparentSiblings = grandparentLocation.parent?.children ?? _roots;
    final node = parent.children.removeAt(location.index);
    grandparentSiblings.insert(grandparentLocation.index + 1, node);
  }

  /// 删除节点
  ///
  /// 子节点提升到当前节点的位置。
  /// 最后一个无子节点的根节点不可删除，始终保持至少一个节点存在。
  void _deleteNode(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null) return;

    final siblings = location.parent?.children ?? _roots;
    if (siblings.isEmpty) return;

    final nodeToDelete = siblings[location.index];

    // 最后一个无子节点的根节点不可删除，始终保持至少一个节点存在
    if (location.parent == null &&
        nodeToDelete.children.isEmpty &&
        _roots.length == 1) {
      return;
    }

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    // 删除前记录扁平列表中的上一节点（就近原则：删除后聚焦到上一位置）
    final flatListBefore = _flatten();
    final currentIndex = flatListBefore.indexWhere((f) => f.node.id == nodeId);
    final previousNodeId = currentIndex > 0 ? flatListBefore[currentIndex - 1].node.id : null;

    // 将子节点提升到当前节点的位置
    siblings.removeAt(location.index);
    for (int i = 0; i < nodeToDelete.children.length; i++) {
      siblings.insert(location.index + i, nodeToDelete.children[i]);
    }

    // 释放被删除节点的资源（子节点资源保留，因为子节点被提升了）
    final deletedController = _controllers[nodeToDelete.id];
    if (deletedController != null) {
      _undoManager.unregisterController(nodeToDelete.id, deletedController);
      deletedController.dispose();
      _controllers.remove(nodeToDelete.id);
    }
    _focusNodes[nodeToDelete.id]?.dispose();
    _focusNodes.remove(nodeToDelete.id);
    _nodeTileKeys.remove(nodeToDelete.id);
    _selectedNodeIds.remove(nodeToDelete.id);

    setState(() {});

    // 聚焦到扁平列表中的上一节点；无上一节点时聚焦到删除后的第一个节点
    String? targetId = previousNodeId;
    if (targetId == null) {
      final flatListAfter = _flatten();
      if (flatListAfter.isNotEmpty) {
        targetId = flatListAfter[0].node.id;
      } else if (location.parent != null) {
        targetId = location.parent!.id;
      }
    }

    if (targetId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodeWithSelection(targetId!, moveCursorToEnd: true);
        _endBatchAndNotify(description: '删除节点', focusNodeId: targetId, focusSelection: _selectionAtEnd(targetId));
      });
    } else {
      // 无可聚焦节点时（如所有节点被删除），仍需结束批量操作
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _endBatchAndNotify(description: '删除节点');
      });
    }
  }

  /// 合并当前节点到上一节点
  ///
  /// 将当前节点的文本追加到同级上一节点末尾，并删除当前节点。
  /// 子节点提升到当前节点的位置。光标定位到合并处。
  /// 上一节点与当前节点非同级时不处理。
  void _mergeWithPreviousNode(String nodeId) {
    final flatList = _flatten();
    final currentIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    // 没有上一节点时无法合并
    if (currentIndex <= 0) return;

    final currentFlat = flatList[currentIndex];
    final previousFlat = flatList[currentIndex - 1];
    // 上一节点与当前节点非同级时不合并
    if (currentFlat.depth != previousFlat.depth) return;

    final previousNode = previousFlat.node;
    final currentLocation = _findLocation(nodeId);
    if (currentLocation == null) return;

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    final siblings = currentLocation.parent?.children ?? _roots;
    final currentNode = siblings[currentLocation.index];

    // 将当前节点的文本追加到上一节点末尾，记录合并位置（即上一节点原文本长度）
    final mergeOffset = previousNode.text.length;
    final mergedText = previousNode.text + currentNode.text;
    final previousController = _controllers[previousNode.id];
    if (previousController != null) {
      previousController.text = mergedText;
    }
    previousNode.text = mergedText;

    // 删除当前节点，子节点提升到当前位置
    siblings.removeAt(currentLocation.index);
    for (int i = 0; i < currentNode.children.length; i++) {
      siblings.insert(currentLocation.index + i, currentNode.children[i]);
    }

    // 释放被删除节点的资源（子节点资源保留，因为子节点被提升了）
    final deletedController = _controllers[currentNode.id];
    if (deletedController != null) {
      _undoManager.unregisterController(currentNode.id, deletedController);
      deletedController.dispose();
      _controllers.remove(currentNode.id);
    }
    _focusNodes[currentNode.id]?.dispose();
    _focusNodes.remove(currentNode.id);
    _nodeTileKeys.remove(currentNode.id);
    _selectedNodeIds.remove(currentNode.id);

    setState(() {});

    // 聚焦到上一节点，光标定位到合并位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focusNode = _focusNodes[previousNode.id];
      final controller = _controllers[previousNode.id];
      if (focusNode != null && controller != null) {
        focusNode.requestFocus();
        controller.selection = TextSelection.fromPosition(TextPosition(offset: mergeOffset));
      }
      _endBatchAndNotify(
        description: '合并节点',
        focusNodeId: previousNode.id,
        focusSelection: TextSelection.collapsed(offset: mergeOffset),
      );
    });
  }

  /// 切换节点展开/折叠状态
  void _toggleExpand(String nodeId) {
    final node = _findNode(nodeId);
    if (node == null) return;
    setState(() {
      node.isExpanded = !node.isExpanded;
    });
    _saveFoldState();
  }

  /// 添加根节点
  void _addRootNode() {
    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    final newNode = _createNode('');
    _ensureResources(newNode);
    _roots.add(newNode);
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 滚动使新节点可见
      _focusAndScrollToNode(newNode.id, moveCursorToEnd: false);
      _endBatchAndNotify(description: '添加根节点', focusNodeId: newNode.id, focusSelection: _selectionAtStart());
    });
  }

  /// 展开所有节点
  void _expandAll() {
    void walk(OutlineNode node) {
      node.isExpanded = true;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }
    setState(() {});
    _saveFoldState();
  }

  /// 折叠所有节点（仅保留根级节点可见）
  void _collapseAll() {
    void walk(OutlineNode node) {
      node.isExpanded = false;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }
    setState(() {});
    _saveFoldState();
  }

  // ================= 选区管理 =================

  /// 清除多节点选区（仅清除视觉选区，不改变焦点）
  void _clearSelection() {
    if (_selectedNodeIds.isEmpty && _selectAllLevel == 0) return;
    _selectedNodeIds.clear();
    _selectAllLevel = 0;
    _selectionAnchorIndex = null;
    setState(() {});
  }

  /// 清除多节点选区并恢复焦点到最近编辑的节点
  void _clearSelectionAndRefocus() {
    final hadSelection = _selectedNodeIds.isNotEmpty || _selectAllLevel != 0;
    _selectedNodeIds.clear();
    _selectAllLevel = 0;
    _selectionAnchorIndex = null;
    setState(() {});
    if (hadSelection && _lastFocusedNodeId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodeWithSelection(_lastFocusedNodeId!, moveCursorToEnd: false);
      });
    }
  }

  /// 选择指定索引范围的节点（包含两端）
  void _selectNodeRange(int startIndex, int endIndex) {
    final flatList = _flatten();
    if (flatList.isEmpty) return;

    final start = startIndex < endIndex ? startIndex : endIndex;
    final end = startIndex < endIndex ? endIndex : startIndex;

    _selectedNodeIds.clear();
    for (int i = start; i <= end && i < flatList.length; i++) {
      _selectedNodeIds.add(flatList[i].node.id);
    }
    _selectAllLevel = 0;
    setState(() {});
    _notifyBatchChanged();
  }

  /// 收集节点及其全部子节点（含各级子孙）的 ID
  ///
  /// 依据扁平列表中的深度判断子树范围，折叠状态下不可见的子孙节点不在其中
  List<String> _collectSubtreeIds(String nodeId) {
    final flatList = _flatten();
    final index = flatList.indexWhere((f) => f.node.id == nodeId);
    if (index == -1) return const [];

    final ids = <String>[flatList[index].node.id];
    final depth = flatList[index].depth;
    for (int i = index + 1; i < flatList.length; i++) {
      if (flatList[i].depth <= depth) break;
      ids.add(flatList[i].node.id);
    }
    return ids;
  }

  /// 清除所有输入框的文本选区，避免文本选区与节点选区同时显示
  void _collapseTextSelections() {
    for (final controller in _controllers.values) {
      if (!controller.selection.isCollapsed) {
        controller.selection = TextSelection.collapsed(offset: controller.selection.extentOffset);
      }
    }
  }

  /// 激活节点选区时切换焦点到编辑器级焦点节点，隐藏输入光标
  void _activateNodeSelectionFocus() {
    _collapseTextSelections();
    // 将焦点从输入框转移到编辑器，隐藏光标
    _editorFocusNode.requestFocus();
  }

  /// 行尾竖条长按：选中长按所在的节点及其全部子节点，并进入批量选择模式
  ///
  /// 移动端专用。长按不松手继续上下拖动可按指针位置扩展或收缩节点选区
  void _onTrailingBarLongPress(Offset globalPosition) {
    final flatList = _flatten();
    if (flatList.isEmpty) return;

    final index = _findNodeIndexAtPosition(globalPosition);
    if (index == null || index >= flatList.length) return;

    // 仅在首次进入批量选择模式时给出震动反馈，模式内继续拖动选择不再震动
    final bool wasBatchMode = _isBatchSelectionMode;

    // 进入批量选择模式：收起输入法，节点转为整体选中操作
    _setBatchSelectionMode(true);
    if (!wasBatchMode) HapticFeedback.mediumImpact();

    _selectionAnchorIndex = index;
    _selectAllLevel = 0;
    _selectedNodeIds
      ..clear()
      ..addAll(_collectSubtreeIds(flatList[index].node.id));
    _collapseTextSelections();
    setState(() {});
    _notifyBatchChanged();
    // 长按后按住不放继续上下拖动时，指针越出视口边缘即持续滚动视口
    _updateEdgeAutoScroll(
      globalPosition,
      selectionUpdater: _onTrailingBarLongPressMove,
    );
  }

  /// 行尾竖条长按拖动：以长按节点为锚点，按指针位置扩展或收缩节点选区
  ///
  /// 向区间外拖动持续选中途经的节点，往回拖动则收缩区间并取消已越过的节点选中
  void _onTrailingBarLongPressMove(Offset globalPosition) {
    final anchor = _selectionAnchorIndex;
    if (anchor == null) return;

    final flatList = _flatten();
    if (flatList.isEmpty) return;

    // 指针位于首个节点上方时按首个节点处理，保证区间能延伸到列表顶端
    final index = _findNodeIndexAtPosition(globalPosition) ?? 0;
    _selectNodeRange(anchor, index);
  }

  /// 获取按扁平列表顺序排列的选中节点
  List<FlatNode> _getSelectedFlatNodes() {
    final flatList = _flatten();
    return flatList.where((f) => _selectedNodeIds.contains(f.node.id)).toList();
  }

  /// 处理 Ctrl+A 全选操作
  ///
  /// 状态循环：未选区 → 全选当前主题 → 全选整个文档 → 取消全选
  /// 进入主题/文档选区时转移焦点到编辑器，取消时恢复到最近编辑的节点
  void _handleSelectAll(String focusedNodeId) {
    final flatList = _flatten();
    if (flatList.isEmpty) return;

    if (_selectAllLevel == 0) {
      // 全选当前节点及其子节点
      final focusIndex = flatList.indexWhere((f) => f.node.id == focusedNodeId);
      if (focusIndex == -1) return;
      final focusDepth = flatList[focusIndex].depth;

      _selectedNodeIds.clear();
      _selectedNodeIds.add(flatList[focusIndex].node.id);
      // 遍历后续节点，选择所有深度大于当前节点的子节点
      for (int i = focusIndex + 1; i < flatList.length; i++) {
        if (flatList[i].depth <= focusDepth) break;
        _selectedNodeIds.add(flatList[i].node.id);
      }
      _selectAllLevel = 1;
      // 记录选区的起始锚点
      _selectionAnchorIndex = focusIndex;
      _activateNodeSelectionFocus();
    } else if (_selectAllLevel == 1) {
      // 全选整个文档
      _selectedNodeIds.clear();
      for (final flat in flatList) {
        _selectedNodeIds.add(flat.node.id);
      }
      _selectAllLevel = 2;
      _selectionAnchorIndex = 0;
    } else {
      // 取消全选并恢复焦点
      _clearSelectionAndRefocus();
      return;
    }

    setState(() {});
  }

  /// 右键菜单全选操作
  void _handleSelectAllFromMenu(String? nodeId) {
    final flatList = _flatten();
    if (flatList.isEmpty) return;

    // 存在节点选区 → 全选所有节点
    if (_selectedNodeIds.isNotEmpty) {
      _selectedNodeIds.clear();
      for (final flat in flatList) {
        _selectedNodeIds.add(flat.node.id);
      }
      _selectAllLevel = 2;
      _selectionAnchorIndex = 0;
      _activateNodeSelectionFocus();
      setState(() {});
      return;
    }

    // 无目标节点 → 全选所有节点
    if (nodeId == null) {
      for (final flat in flatList) {
        _selectedNodeIds.add(flat.node.id);
      }
      _selectAllLevel = 2;
      _selectionAnchorIndex = 0;
      setState(() {});
      return;
    }

    final controller = _controllers[nodeId];
    if (controller == null) return;

    final selection = controller.selection;
    final bool isTextAllSelected =
        selection.isValid && !selection.isCollapsed && selection.start == 0 && selection.end == controller.text.length;

    if (!isTextAllSelected) {
      // 文字未全选 → 全选当前节点文字
      controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    } else {
      // 文字已全选 → 选择当前节点及其所有子节点
      final focusIndex = flatList.indexWhere((f) => f.node.id == nodeId);
      if (focusIndex == -1) return;
      final focusDepth = flatList[focusIndex].depth;

      _selectedNodeIds.clear();
      _selectedNodeIds.add(nodeId);
      for (int i = focusIndex + 1; i < flatList.length; i++) {
        if (flatList[i].depth <= focusDepth) break;
        _selectedNodeIds.add(flatList[i].node.id);
      }
      _selectAllLevel = 1;
      _selectionAnchorIndex = focusIndex;
      _activateNodeSelectionFocus();
      setState(() {});
    }
  }

  // ================= 批量选择模式 =================

  /// 是否处于批量选择模式
  bool get isBatchSelectionMode => _isBatchSelectionMode;

  /// 批量选择模式与节点选区的变更通知
  Listenable get batchRevision => _batchRevision;

  /// 选中节点的数量
  int get selectedNodeCount => _selectedNodeIds.length;

  /// 是否已选中全部可见节点
  bool get isAllNodesSelected {
    final flatList = _flatten();
    return flatList.isNotEmpty && _selectedNodeIds.length >= flatList.length;
  }

  /// 是否仅选中了部分可见节点（有选中项但未全选）
  bool get isPartialNodesSelected {
    final flatList = _flatten();
    return _selectedNodeIds.isNotEmpty && _selectedNodeIds.length < flatList.length;
  }

  /// 通知批量选择状态发生变化
  void _notifyBatchChanged() => _batchRevision.value++;

  /// 设置批量选择模式状态
  ///
  /// 开启时收起输入法与文本选区，使节点转为整体选中与操作；
  /// 关闭时清空节点选区，恢复到可编辑状态
  void _setBatchSelectionMode(bool enabled) {
    if (_isBatchSelectionMode == enabled) return;
    _isBatchSelectionMode = enabled;
    // 重置滑选交互状态，避免进入或退出批量模式时残留拖拽选区状态
    _batchSelectionController.reset();
    if (enabled) {
      // 收起输入法，避免批量操作期间误触输入
      FocusManager.instance.primaryFocus?.unfocus();
      _collapseTextSelections();
      _editorFocusNode.requestFocus();
    } else {
      _selectedNodeIds.clear();
      _selectAllLevel = 0;
      _selectionAnchorIndex = null;
    }
    setState(() {});
    _notifyBatchChanged();
  }

  /// 进入批量选择模式（顶部操作栏的批量选择入口）
  void enterBatchSelectionMode() => _setBatchSelectionMode(true);

  /// 退出批量选择模式
  void exitBatchSelectionMode() => _setBatchSelectionMode(false);

  /// 批量模式下点击节点：切换该节点及其子树的选中状态
  ///
  /// 节点已选中时连同其子节点一起取消选中，未选中时连同其子节点一起选中
  void toggleNodeSubtreeSelection(String nodeId) {
    final ids = _collectSubtreeIds(nodeId);
    if (ids.isEmpty) return;

    setState(() {
      if (_selectedNodeIds.contains(nodeId)) {
        _selectedNodeIds.removeAll(ids);
      } else {
        _selectedNodeIds.addAll(ids);
      }
      _selectAllLevel = 0;
      _selectionAnchorIndex = null;
    });
    _notifyBatchChanged();
  }

  /// 全选或取消全选所有可见节点
  void toggleSelectAllNodes() {
    setState(() {
      if (isAllNodesSelected) {
        _selectedNodeIds.clear();
        _selectAllLevel = 0;
        _selectionAnchorIndex = null;
      } else {
        for (final flat in _flatten()) {
          _selectedNodeIds.add(flat.node.id);
        }
        _selectAllLevel = 2;
        _selectionAnchorIndex = 0;
      }
    });
    _notifyBatchChanged();
  }

  /// 复制批量选中的节点到剪贴板
  void copySelectedNodes() => _copySelectedNodes();

  /// 删除批量选中的节点
  void deleteSelectedNodes() => _deleteSelectedNodes();

  /// 选中节点中的顶层节点（父节点未被选中的节点）
  ///
  /// 父节点被选中时子节点会跟随父节点一起移动，无需单独处理
  List<String> _selectedTopLevelNodeIds() {
    return _selectedNodeIds.where((id) {
      final parent = _findLocation(id)?.parent;
      return parent == null || !_selectedNodeIds.contains(parent.id);
    }).toList();
  }

  /// 按文档顺序返回批量选中的顶层节点ID
  ///
  /// 顺序取自扁平列表而非选中集合的插入顺序，避免批量操作结果随选择顺序变化
  List<String> _selectedTopLevelNodeIdsInOrder() {
    final topLevelIds = _selectedTopLevelNodeIds().toSet();
    return _flatten()
        .where((flat) => topLevelIds.contains(flat.node.id))
        .map((flat) => flat.node.id)
        .toList();
  }

  /// 批量选中的节点是否可以缩进为子节点
  bool get canIndentSelectedNodes => _selectedTopLevelNodeIds().any(_canBatchIndentNode);

  /// 批量选中的节点是否可以提升层级
  bool get canOutdentSelectedNodes =>
      _selectedTopLevelNodeIds().any((id) => _findLocation(id)?.parent != null);

  /// 批量缩进选中的节点
  ///
  /// 仅处理选中的顶层节点，无可缩进节点时不产生撤销记录
  void indentSelectedNodes() {
    // 按文档顺序处理，保证缩进后各节点在目标父节点下仍保持原有先后顺序
    final targets = _selectedTopLevelNodeIdsInOrder();
    if (targets.isEmpty) return;

    // 先依据原始树结构为各节点确定目标父节点，再统一执行移动，
    // 避免先移动的节点改变后续节点的兄弟结构而导致错误嵌套
    final targetParents = <String, OutlineNode>{};
    for (final nodeId in targets) {
      if (!_canBatchIndentNode(nodeId)) continue;
      targetParents[nodeId] = _indentTargetParent(nodeId)!;
    }
    if (targetParents.isEmpty) return;

    _undoManager.beginBatch();
    for (final nodeId in targets) {
      final parent = targetParents[nodeId];
      if (parent != null) _moveNodeUnderParent(nodeId, parent);
    }
    setState(() {});
    _endBatchAndNotify(description: '批量缩进节点');
  }

  /// 批量提升选中节点的层级
  ///
  /// 仅处理选中的顶层节点，无可提升节点时不产生撤销记录
  void outdentSelectedNodes() {
    // 按文档逆序处理，使同级节点依次插入到父节点之后时仍保持原有先后顺序
    final targets = _selectedTopLevelNodeIdsInOrder().reversed.toList();
    if (!targets.any((id) => _findLocation(id)?.parent != null)) return;

    _undoManager.beginBatch();
    for (final nodeId in targets) {
      _applyOutdentNode(nodeId);
    }
    setState(() {});
    _endBatchAndNotify(description: '批量提升层级');
  }

  // ================= 命中检测 =================

  /// 查找节点对应的 RenderEditable（文本渲染对象）
  RenderEditable? _findRenderEditable(String nodeId) {
    final key = _nodeTileKeys[nodeId];
    final context = key?.currentContext;
    if (context == null) return null;
    final root = context.findRenderObject();
    if (root == null) return null;
    RenderEditable? result;
    void visit(RenderObject child) {
      if (child is RenderEditable) {
        result = child;
        return;
      }
      child.visitChildren(visit);
    }

    visit(root);
    return result;
  }

  /// 判断全局坐标是否落在某个节点瓦片的文本输入区上
  ///
  /// 文本区位于指示符（占位）之后，通过节点深度计算指示符总宽度来确定边界
  bool _isPositionOnTextField(Offset globalPosition) {
    final flatList = _flatten();
    for (final flat in flatList) {
      final key = _nodeTileKeys[flat.node.id];
      final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;

      final rect = MatrixUtils.transformRect(renderBox.getTransformTo(null), Offset.zero & renderBox.size);
      // 坐标不在该瓦片范围内则跳过
      if (!rect.contains(globalPosition)) continue;

      // 指示符总宽度 = (深度 + 2) × 缩进宽度 - 圆点间距缩减量，加上水平内边距 8
      final textAreaStartX = rect.left + 8 + (flat.depth + 2) * _indentWidth - _dotTextGapReduction;
      // 坐标在指示符右侧即为文本区
      return globalPosition.dx >= textAreaStartX;
    }
    return false;
  }

  /// 根据全局坐标查找扁平列表中的节点索引
  ///
  /// 遍历已构建节点的渲染矩形，返回顶部边在坐标之上的最后一个节点，
  /// 用于支持从空白处拖拽时定位到最近的节点。
  /// 节点按需构建，指针拖出已构建范围时改用平均节点高度估算，
  /// 保证拖拽起始点落在视口外时仍能定位到对应的节点
  int? _findNodeIndexAtPosition(Offset globalPosition) {
    final flatList = _flatten();
    if (flatList.isEmpty) return null;

    int? result;
    int? firstBuiltIndex;
    int? lastBuiltIndex;
    Rect? firstBuiltRect;
    Rect? lastBuiltRect;
    double builtHeightSum = 0;

    for (int i = 0; i < flatList.length; i++) {
      final key = _nodeTileKeys[flatList[i].node.id];
      final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;

      final rect = MatrixUtils.transformRect(renderBox.getTransformTo(null), Offset.zero & renderBox.size);
      firstBuiltIndex ??= i;
      firstBuiltRect ??= rect;
      lastBuiltIndex = i;
      lastBuiltRect = rect;
      builtHeightSum += rect.height;
      // 顶部边在坐标之上的节点都作为候选，取最后一个
      if (globalPosition.dy >= rect.top) {
        result = i;
      } else {
        break;
      }
    }

    // 指针位于已构建范围之外：按平均节点高度估算目标索引
    if (lastBuiltIndex == null) return null;
    if (result == null || result == lastBuiltIndex) {
      if (lastBuiltRect!.bottom <= globalPosition.dy) {
        // 指针在已构建范围之下：命中最后一个节点
        return flatList.length - 1;
      }
      if (globalPosition.dy < firstBuiltRect!.top) {
        final double averageHeight = builtHeightSum / (lastBuiltIndex - firstBuiltIndex! + 1);
        if (averageHeight > 0) {
          final int offset = ((firstBuiltRect.top - globalPosition.dy) / averageHeight).ceil();
          return (firstBuiltIndex - offset).clamp(0, flatList.length - 1);
        }
      }
    }

    return result;
  }

  /// 按全局坐标命中节点ID
  ///
  /// 批量选择模式下滑选时，触摸端没有悬停事件，以此定位指针下方的节点
  String? _hitTestNodeIdAt(Offset globalPosition) {
    final index = _findNodeIndexAtPosition(globalPosition);
    if (index == null) return null;
    final flatList = _flatten();
    return index < flatList.length ? flatList[index].node.id : null;
  }

  /// 判断全局坐标是否在指定节点的文本渲染区域内
  bool _isPositionWithinNodeText(String nodeId, Offset globalPosition) {
    final renderEditable = _findRenderEditable(nodeId);
    if (renderEditable == null || !renderEditable.attached) return false;
    final rect = MatrixUtils.transformRect(renderEditable.getTransformTo(null), Offset.zero & renderEditable.size);
    return rect.contains(globalPosition);
  }

  /// 判断全局坐标是否落在滚动条所在的右侧条带上
  ///
  /// 滚动条 thumb 位于可滚动区域的右边缘，宽度等于 [editorScrollbarThickness]。
  /// 指针落在该条带时，编辑器的拖拽选区手势应让位于滚动条自身的拖拽与点击交互。
  bool _isPositionOnScrollbar(Offset globalPosition) {
    final renderObject = _scrollbarKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final rect = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & renderObject.size,
    );
    return globalPosition.dx >= rect.right - editorScrollbarThickness &&
        globalPosition.dx <= rect.right &&
        globalPosition.dy >= rect.top &&
        globalPosition.dy <= rect.bottom;
  }

  // ================= 指针事件与拖拽选区 =================

  /// 指针按下：记录起始位置用于后续判断是否为点击
  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;

    // 指针位于滚动条区域时跳过编辑器自身的指针处理，让滚动条正常响应点击与拖拽
    if (_isPositionOnScrollbar(event.position)) {
      _dragStartPosition = null;
      return;
    }

    // Shift+左键：基于当前光标位置或选区扩展选择范围
    if (HardwareKeyboard.instance.isShiftPressed) {
      _handleShiftClick(event.position);
      return;
    }

    // 右键菜单显示中或刚关闭时，立即同步光标到点击位置并聚焦目标节点，
    // 避免菜单关闭后焦点先回到菜单所在节点造成光标闪烁
    if (ContextMenu.isMenuShowing() || ContextMenu.wasJustClosed()) {
      _syncCursorAndFocusAfterMenuDismiss(event);
    }

    // 重置拖拽状态，防止上一次异常终止的拖拽残留状态
    _dragMode = _DragMode.none;
    _dragTextAnchor = null;
    _dragStartNodeId = null;
    _dragStartIndex = null;
    _dragStartPosition = event.position;
  }

  /// 指针抬起：若未发生拖拽则视为点击，点击空白处清除选区
  void _onPointerUp(PointerUpEvent event) {
    // Shift+click 的指针抬起：在帧后执行恢复操作，覆盖 TextField tap 的默认行为
    if (_isShiftClicking && _pendingShiftClickRestore != null) {
      final restore = _pendingShiftClickRestore!;
      _pendingShiftClickRestore = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isShiftClicking = false;
        if (!mounted) return;
        restore();
      });
      _dragStartPosition = null;
      return;
    }

    if (_dragMode == _DragMode.none && _dragStartPosition != null) {
      // 批量选择模式下节点选中由节点行自身处理，不在此处清除节点选区
      if (!_isBatchSelectionMode && !_isPositionOnTextField(event.position)) {
        _clearSelection();
        // 点击空白区域时，若无输入框持有焦点，则请求编辑器级焦点
        // 确保撤销/恢复等快捷键在空白区域也能正常响应
        if (!_focusNodes.values.any((fn) => fn.hasFocus)) {
          _editorFocusNode.requestFocus();
        }
      }
    }
    _dragStartPosition = null;
  }

  /// 批量选择模式下的指针移动
  ///
  /// 按指针位置更新竖条滑选的选区；处于滑选状态时，指针进入视口上下边缘
  /// 的触发区会持续滚动视口。非滑选状态（如拖动列表滚动）不介入，避免与列表自身滚动冲突
  void _onBatchPointerMove(PointerMoveEvent event) {
    final updater = _autoScrollSelectionUpdater;
    if (updater != null) {
      _updateEdgeAutoScroll(event.position, selectionUpdater: updater);
    }
    _batchSelectionController.onPointerMove(event);
  }

  /// 批量选择模式下的指针抬起或取消
  ///
  /// 结束竖条滑选并停止边缘自动滚动
  void _onBatchPointerUp(PointerEvent event) {
    _stopEdgeAutoScroll();
    _batchSelectionController.onPointerUp();
  }

  /// 拖拽开始：记录起始位置和起始节点
  void _onPanStart(DragStartDetails details) {
    // 批量选择模式下禁用拖拽选区与文本选区，节点选中由节点行自身处理
    if (_isBatchSelectionMode) return;

    _dragStartPosition = details.globalPosition;
    _dragMode = _DragMode.none;
    _dragTextAnchor = null;
    _dragStartNodeId = null;
    _dragStartIndex = _findNodeIndexAtPosition(details.globalPosition);
    if (_dragStartIndex != null) {
      final flatList = _flatten();
      _dragStartNodeId = flatList[_dragStartIndex!].node.id;
      _selectionAnchorIndex = _dragStartIndex;
    }
  }

  /// 拖拽更新：根据当前位置更新选区
  ///
  /// 指针越出视口上下边缘时同步启动边缘自动滚动
  void _onPanUpdate(DragUpdateDetails details) {
    // 批量选择模式下禁用拖拽选区与文本选区，节点选中由节点行自身处理
    if (_isBatchSelectionMode) return;

    final globalPosition = details.globalPosition;
    // 指针拖出视口上下边缘时持续滚动视口，滚动中指针不动也能继续扩展选区
    _updateEdgeAutoScroll(
      globalPosition,
      selectionUpdater: _updateDragSelection,
    );
    _updateDragSelection(globalPosition);
  }

  /// 按指针位置更新拖拽选区
  ///
  /// 统一选区逻辑：
  /// - 起始位置在文本内时先做文本选区，离开文本后切换到节点选区
  /// - 起始位置不在文本内时直接做节点选区
  void _updateDragSelection(Offset globalPosition) {
    // 起始索引尚未确定时，用当前位置确定
    if (_dragStartIndex == null) {
      _dragStartIndex = _findNodeIndexAtPosition(globalPosition);
      if (_dragStartIndex != null) {
        final flatList = _flatten();
        _dragStartNodeId = flatList[_dragStartIndex!].node.id;
      }
    }
    if (_dragStartIndex == null || _dragStartNodeId == null) return;

    // 尚未确定拖拽模式时，根据起始位置判断
    if (_dragMode == _DragMode.none) {
      final startInText =
          _dragStartPosition != null && _isPositionWithinNodeText(_dragStartNodeId!, _dragStartPosition!);
      if (startInText) {
        // 起始位置在文本内：进入文本选区模式
        _dragMode = _DragMode.text;
        final renderEditable = _findRenderEditable(_dragStartNodeId!);
        if (renderEditable != null && renderEditable.attached) {
          _dragTextAnchor = renderEditable.getPositionForPoint(_dragStartPosition!);
        }
        // 让起始节点获得焦点，确保文本选区可见
        _focusNodes[_dragStartNodeId!]?.requestFocus();
      } else {
        // 起始位置不在文本内：进入节点选区模式
        _dragMode = _DragMode.node;
        _selectAllLevel = 0;
        _activateNodeSelectionFocus();
      }
    }

    // 根据当前模式更新选区
    if (_dragMode == _DragMode.text) {
      if (_dragTextAnchor == null) {
        // 无法获取文本锚点：回退到节点选区
        _dragMode = _DragMode.node;
        _selectAllLevel = 0;
        _activateNodeSelectionFocus();
      } else {
        // 综合判断是否仍在起始节点的文本区域内：
        // 1. 当前位置在起始节点的 RenderEditable rect 内
        // 2. 当前节点索引仍为起始索引（防止 RenderEditable rect 不准确时误判）
        final currentIndex = _findNodeIndexAtPosition(globalPosition);
        final stillInStartNodeText =
            currentIndex == _dragStartIndex && _isPositionWithinNodeText(_dragStartNodeId!, globalPosition);
        if (stillInStartNodeText) {
          // 仍在起始文本内：扩展文本选区
          _extendTextSelection(_dragStartNodeId!, _dragTextAnchor!, globalPosition);
        } else {
          // 离开文本区域或进入其他节点：切换到节点选区
          _dragMode = _DragMode.node;
          _selectAllLevel = 0;
          _activateNodeSelectionFocus();
          if (currentIndex != null) {
            _selectNodeRange(_dragStartIndex!, currentIndex);
          }
        }
      }
    } else if (_dragMode == _DragMode.node) {
      // 回到起始节点文本区域时，从节点选区恢复到文本选区
      // 同时校验当前节点索引是否为起始索引，确保确实回到了起始节点
      final currentIndex = _findNodeIndexAtPosition(globalPosition);
      final backToStartText =
          _dragTextAnchor != null &&
          currentIndex == _dragStartIndex &&
          _isPositionWithinNodeText(_dragStartNodeId!, globalPosition);
      if (backToStartText) {
        _dragMode = _DragMode.text;
        _selectedNodeIds.clear();
        _selectAllLevel = 0;
        // 恢复焦点到起始节点的输入框
        _focusNodes[_dragStartNodeId!]?.requestFocus();
        _extendTextSelection(_dragStartNodeId!, _dragTextAnchor!, globalPosition);
        setState(() {});
      } else {
        // 节点选区模式：根据当前位置扩展节点选区
        if (currentIndex != null) {
          _selectNodeRange(_dragStartIndex!, currentIndex);
        }
      }
    }
  }

  /// 拖拽结束：清理拖拽状态
  void _onPanEnd(DragEndDetails details) {
    _stopEdgeAutoScroll();
    _dragStartPosition = null;
    _dragMode = _DragMode.none;
    _dragTextAnchor = null;
    _dragStartNodeId = null;
    _dragStartIndex = null;
  }

  /// 拖拽取消：清理拖拽状态
  void _onPanCancel() {
    _stopEdgeAutoScroll();
    _dragStartPosition = null;
    _dragMode = _DragMode.none;
    _dragTextAnchor = null;
    _dragStartNodeId = null;
    _dragStartIndex = null;
  }

  /// Shift+左键点击：基于当前光标位置或选区扩展选择范围
  void _handleShiftClick(Offset globalPosition) {
    final flatList = _flatten();
    if (flatList.isEmpty) return;

    final clickIndex = _findNodeIndexAtPosition(globalPosition);
    if (clickIndex == null) return;
    final clickNodeId = flatList[clickIndex].node.id;

    // 点击在当前焦点节点的文本区域内：扩展文本选区
    if (_lastFocusedNodeId != null &&
        _lastFocusedNodeId == clickNodeId &&
        _isPositionWithinNodeText(clickNodeId, globalPosition)) {
      final controller = _controllers[clickNodeId];
      final renderEditable = _findRenderEditable(clickNodeId);
      if (controller == null || renderEditable == null || !renderEditable.attached) return;

      final currentSelection = controller.selection;
      final clickPosition = renderEditable.getPositionForPoint(globalPosition);

      int baseOffset;
      if (currentSelection.isValid && !currentSelection.isCollapsed) {
        // 已有选区：保持 base 不变
        baseOffset = currentSelection.baseOffset;
      } else {
        // 无选区：以当前光标位置为 base
        baseOffset = currentSelection.extentOffset;
      }

      final newSelection = TextSelection(baseOffset: baseOffset, extentOffset: clickPosition.offset);
      controller.selection = newSelection;

      // 在 PointerUp 后的帧重新应用选区，覆盖 TextField tap 的默认行为
      _isShiftClicking = true;
      _pendingShiftClickRestore = () {
        controller.selection = newSelection;
      };
      return;
    }

    // 扩展节点选区
    int? startIndex = _selectionAnchorIndex;
    if (startIndex == null && _lastFocusedNodeId != null) {
      // 无锚点时以焦点节点为起始
      final focusIndex = flatList.indexWhere((f) => f.node.id == _lastFocusedNodeId);
      if (focusIndex != -1) {
        startIndex = focusIndex;
        _selectionAnchorIndex = focusIndex;
      }
    }
    if (startIndex == null) return;

    _selectAllLevel = 0;
    _selectNodeRange(startIndex, clickIndex);
    _activateNodeSelectionFocus();

    // 在 PointerUp 后的帧重新激活编辑器焦点，覆盖 TextField tap 获得的焦点
    _isShiftClicking = true;
    _pendingShiftClickRestore = () {
      _activateNodeSelectionFocus();
    };
  }

  /// 扩展文本选区到指定全局坐标位置
  ///
  /// 以 [anchor] 为选区锚点，根据 [globalPosition] 计算选区终点，
  /// 自动校正方向使 baseOffset 始终小于 extentOffset
  void _extendTextSelection(String nodeId, TextPosition anchor, Offset globalPosition) {
    final renderEditable = _findRenderEditable(nodeId);
    if (renderEditable == null || !renderEditable.attached) return;
    final extent = renderEditable.getPositionForPoint(globalPosition);
    final controller = _controllers[nodeId];
    if (controller == null) return;
    if (anchor.offset <= extent.offset) {
      controller.selection = TextSelection(baseOffset: anchor.offset, extentOffset: extent.offset);
    } else {
      controller.selection = TextSelection(baseOffset: extent.offset, extentOffset: anchor.offset);
    }
  }

  // ================= 文字样式与颜色 =================

  /// 获取需要应用样式的目标节点 ID 列表
  ///
  /// 优先级：
  /// 1. 存在节点选区且右键目标在选区内 → 返回所有选中节点
  /// 2. 右键目标节点存在 → 返回单节点列表
  /// 3. 否则返回空列表
  List<String> _getStyleTargetNodeIds(String? nodeId) {
    if (_selectedNodeIds.isNotEmpty && nodeId != null && _selectedNodeIds.contains(nodeId)) {
      return _selectedNodeIds.toList();
    }
    if (nodeId != null) return [nodeId];
    return [];
  }

  /// 获取选区或整个节点的样式状态
  ///
  /// [nodes] 为目标节点列表，会合并所有节点的样式状态。
  /// [selection] 仅在单节点时使用：
  /// - 有选中文字时返回该区间的样式标记
  /// - 无选中文字时返回整个文本的合并样式标记
  /// 多节点时忽略 [selection]，合并所有节点的整个文本样式。
  TextStyleFlags _getSelectionFlags(List<OutlineNode> nodes, TextSelection? selection) {
    var flags = TextStyleFlags.none;
    if (nodes.length == 1) {
      // 单节点：尊重文字选区
      final node = nodes.first;
      if (selection != null && selection.isValid && !selection.isCollapsed) {
        // 有文字选区：合并与选区重叠的所有区间样式
        final s = selection.start;
        final e = selection.end;
        for (final r in node.styleRanges) {
          if (r.start < e && r.end > s) {
            flags = flags.merge(r.flags);
          }
        }
        return flags;
      }
      // 无文字选区：合并整个文本的所有区间样式
      for (final r in node.styleRanges) {
        flags = flags.merge(r.flags);
      }
      return flags;
    }
    // 多节点：合并所有节点的整个文本样式
    for (final node in nodes) {
      for (final r in node.styleRanges) {
        flags = flags.merge(r.flags);
      }
    }
    return flags;
  }

  /// 获取选区或整个节点的当前颜色
  ///
  /// 遍历所有与目标范围重叠的样式区间，收集颜色值。
  /// 若所有区间颜色一致则 isUniform 为 true，color 为该颜色；
  /// 若颜色不一致或无区间覆盖则 isUniform 为 false。
  /// [isForeground] 为 true 时查询字体颜色，false 时查询字底颜色。
  ({bool isUniform, Color? color}) _getCurrentColor(
    List<OutlineNode> nodes,
    TextSelection? selection,
    bool isForeground,
  ) {
    final Set<Color?> colors = {};

    for (final node in nodes) {
      int start, end;
      if (nodes.length == 1 && selection != null && selection.isValid && !selection.isCollapsed) {
        start = selection.start;
        end = selection.end;
      } else {
        start = 0;
        end = node.text.length;
      }

      bool hasOverlap = false;
      for (final r in node.styleRanges) {
        if (r.start < end && r.end > start) {
          hasOverlap = true;
          colors.add(isForeground ? r.flags.foregroundColor : r.flags.backgroundColor);
        }
      }
      // 无样式区间覆盖时，使用默认颜色（null）
      if (!hasOverlap && start < end) {
        colors.add(null);
      }
    }

    if (colors.length == 1) {
      return (isUniform: true, color: colors.first);
    }
    return (isUniform: false, color: null);
  }

  /// 切换文字样式
  ///
  /// 根据当前选区决定作用范围：
  /// - 节点选区状态下：对所有选中节点的整个文本应用样式
  /// - 单节点且有选中文字时：仅作用于选中区间
  /// - 单节点且无选中文字时：作用于整个节点文本
  void _toggleTextStyle(List<String> nodeIds, TextStyleFlags Function(TextStyleFlags) toggleFn) {
    if (nodeIds.isEmpty) return;
    final nodes = nodeIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();
    if (nodes.isEmpty) return;

    // 单节点时考虑文字选区
    final TextSelection? selection = nodes.length == 1 ? _controllers[nodeIds.first]?.selection : null;

    // 计算选区主导样式状态（任一位置为 true 则视为已开启）
    final dominantFlags = _getSelectionFlags(nodes, selection);
    // 计算切换后的目标样式（基于主导状态切换对应标记位）
    final targetFlags = toggleFn(dominantFlags);
    // 提取发生变化的标记位（从主导状态到目标状态）
    // 仅切换这些标记位，其他标记位保持原值
    final changedBold = dominantFlags.bold != targetFlags.bold;
    final changedItalic = dominantFlags.italic != targetFlags.italic;
    final changedUnderline = dominantFlags.underline != targetFlags.underline;
    final changedStrikethrough = dominantFlags.strikethrough != targetFlags.strikethrough;

    _undoManager.beginBatch();
    setState(() {
      // 对每个目标节点应用统一样式切换
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final controller = _controllers[node.id];
        if (controller == null) continue;

        // 单节点时尊重文字选区，多节点时作用于整个文本
        int start, end;
        if (nodes.length == 1 && selection != null && selection.isValid && !selection.isCollapsed) {
          start = selection.start;
          end = selection.end;
        } else {
          start = 0;
          end = node.text.length;
        }

        node.styleRanges = TextStyleRangeUtils.applyToggle(
          node.styleRanges,
          start,
          end,
          (current) => current.toggle(
            bold: changedBold ? targetFlags.bold : null,
            italic: changedItalic ? targetFlags.italic : null,
            underline: changedUnderline ? targetFlags.underline : null,
            strikethrough: changedStrikethrough ? targetFlags.strikethrough : null,
          ),
          node.text.length,
        );
        // 同步到控制器以触发富文本重建
        (controller as RichTextEditingController).styleRanges = node.styleRanges;
      }
    });
    _endBatchAndNotify(description: '切换文字样式', focusNodeId: nodeIds.first, focusSelection: selection);
  }

  /// 对选中文字应用颜色
  ///
  /// 根据当前选区决定作用范围（与 [_toggleTextStyle] 一致）：
  /// - 节点选区状态下：对所有选中节点的整个文本应用颜色
  /// - 单节点且有选中文字时：仅作用于选中区间
  /// - 单节点且无选中文字时：作用于整个节点文本
  ///
  /// [foregroundColor] 和 [backgroundColor] 设置对应颜色；
  /// [clearForeground] 和 [clearBackground] 清除对应颜色（设为 null）。
  /// 设置和清除不会同时作用于同一颜色属性。
  void _applyColor(
    List<String> nodeIds, {
    Color? foregroundColor,
    Color? backgroundColor,
    bool clearForeground = false,
    bool clearBackground = false,
  }) {
    if (nodeIds.isEmpty) return;
    final nodes = nodeIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();
    if (nodes.isEmpty) return;

    final TextSelection? selection = nodes.length == 1 ? _controllers[nodeIds.first]?.selection : null;

    _undoManager.beginBatch();
    setState(() {
      for (final node in nodes) {
        final controller = _controllers[node.id];
        if (controller == null) continue;

        // 单节点时尊重文字选区，多节点时作用于整个文本
        int start, end;
        if (nodes.length == 1 && selection != null && selection.isValid && !selection.isCollapsed) {
          start = selection.start;
          end = selection.end;
        } else {
          start = 0;
          end = node.text.length;
        }

        // 设置或清除颜色（未操作的属性保持不变）
        node.styleRanges = TextStyleRangeUtils.applyToggle(
          node.styleRanges,
          start,
          end,
          (current) => current.copyWith(
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            clearForegroundColor: clearForeground,
            clearBackgroundColor: clearBackground,
          ),
          node.text.length,
        );
        // 同步到控制器以触发富文本重建
        (controller as RichTextEditingController).styleRanges = node.styleRanges;
      }
    });
    _endBatchAndNotify(
      description: clearForeground
          ? '清除字体颜色'
          : clearBackground
          ? '清除字底颜色'
          : foregroundColor != null
          ? '设置字体颜色'
          : '设置字底颜色',
      focusNodeId: nodeIds.first,
      focusSelection: selection,
    );
  }

  /// 设置节点的标题级别
  ///
  /// 对目标节点列表统一设置标题级别（0=正文, 1=H1, 2=H2, 3=H3）。
  /// 单节点时保留文字选区用于撤销后恢复。
  void _setHeadingLevel(List<String> nodeIds, int level) {
    if (nodeIds.isEmpty) return;
    final nodes = nodeIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();
    if (nodes.isEmpty) return;

    final TextSelection? selection =
        nodes.length == 1 ? _controllers[nodeIds.first]?.selection : null;

    _undoManager.beginBatch();
    setState(() {
      for (final node in nodes) {
        node.headingLevel = level;
      }
    });
    _endBatchAndNotify(
        description: '设置标题级别', focusNodeId: nodeIds.first, focusSelection: selection);
  }

  // ================= 移动端键盘工具栏接口 =================

  /// 编辑器是否持有输入焦点
  ///
  /// 供移动端键盘工具栏判断显隐：仅当某个节点输入框正在输入时显示。
  bool get hasEditorFocus {
    for (final focusNode in _focusNodes.values) {
      if (focusNode.hasFocus) return true;
    }
    return false;
  }

  /// 当前活动节点 ID
  ///
  /// 优先取正在输入的节点，无焦点时回退到最近一次获得焦点的节点。
  String? get _activeNodeId {
    for (final entry in _focusNodes.entries) {
      if (entry.value.hasFocus) return entry.key;
    }
    final lastId = _lastFocusedNodeId;
    return lastId != null && _findNode(lastId) != null ? lastId : null;
  }

  /// 当前活动节点的文本控制器
  ///
  /// 工具栏据此监听文字选区与样式变化，同步按钮的点亮状态。
  TextEditingController? get activeController {
    final nodeId = _activeNodeId;
    return nodeId == null ? null : _controllers[nodeId];
  }

  /// 工具栏样式操作的目标节点 ID 列表
  ///
  /// 存在节点选区时返回全部选中节点，否则返回当前活动节点。
  List<String> get _toolbarTargetNodeIds {
    if (_selectedNodeIds.isNotEmpty) return _selectedNodeIds.toList();
    final nodeId = _activeNodeId;
    return nodeId == null ? const [] : [nodeId];
  }

  /// 工具栏目标节点对应的节点数据
  List<OutlineNode> get _toolbarTargetNodes =>
      _toolbarTargetNodeIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();

  /// 工具栏目标节点的文字选区
  ///
  /// 仅单节点且无节点选区时使用文字选区，其余情况作用于整个节点文本。
  TextSelection? get _toolbarTargetSelection {
    if (_selectedNodeIds.isNotEmpty) return null;
    final nodeId = _activeNodeId;
    return nodeId == null ? null : _controllers[nodeId]?.selection;
  }

  /// 当前标题级别
  ///
  /// 各目标节点级别一致时返回该级别（0=正文, 1=H1, 2=H2, 3=H3），
  /// 级别不一致或无目标节点时返回 -1。
  int get currentHeadingLevel {
    final nodes = _toolbarTargetNodes;
    if (nodes.isEmpty) return -1;
    final level = nodes.first.headingLevel;
    return nodes.every((node) => node.headingLevel == level) ? level : -1;
  }

  /// 当前文字样式标记（加粗、斜体、下划线、删除线）
  TextStyleFlags get currentTextStyleFlags =>
      _getSelectionFlags(_toolbarTargetNodes, _toolbarTargetSelection);

  /// 当前字体颜色或字底颜色
  ///
  /// [isForeground] 为 true 时查询字体颜色，false 时查询字底颜色。
  ({bool isUniform, Color? color}) currentColor({required bool isForeground}) =>
      _getCurrentColor(_toolbarTargetNodes, _toolbarTargetSelection, isForeground);

  /// 活动节点是否可以缩进为子节点
  bool get canIndentActiveNode {
    final nodeId = _activeNodeId;
    return nodeId != null && _canIndentNode(nodeId);
  }

  /// 活动节点是否可以提升层级
  bool get canOutdentActiveNode {
    final nodeId = _activeNodeId;
    return nodeId != null && _findLocation(nodeId)?.parent != null;
  }

  /// 切换目标节点的文字样式
  void toggleTextStyle(TextStyleFlags Function(TextStyleFlags) toggleFn) =>
      _toggleTextStyle(_toolbarTargetNodeIds, toggleFn);

  /// 设置目标节点的标题级别
  void setHeadingLevel(int level) => _setHeadingLevel(_toolbarTargetNodeIds, level);

  /// 设置或清除目标节点的字体颜色与字底颜色
  void applyColor({
    Color? foregroundColor,
    Color? backgroundColor,
    bool clearForeground = false,
    bool clearBackground = false,
  }) =>
      _applyColor(
        _toolbarTargetNodeIds,
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        clearForeground: clearForeground,
        clearBackground: clearBackground,
      );

  /// 将活动节点缩进为前一兄弟节点的子节点
  void indentActiveNode() {
    final nodeId = _activeNodeId;
    if (nodeId != null) _indentNode(nodeId);
  }

  /// 将活动节点提升一级
  void outdentActiveNode() {
    final nodeId = _activeNodeId;
    if (nodeId != null) _outdentNode(nodeId);
  }

  /// 在活动节点的光标处插入标点符号
  ///
  /// 启用标点自动补全时：未选中文字则插入成对符号并将光标置于两条符号之间，
  /// 选中文字则用成对符号包裹选中内容；
  /// 光标右侧已是该符号的结束符号时直接跳过，仅移动光标；
  /// 其余情况按普通符号插入。
  void insertQuickSymbol(PunctuationSymbol symbol) {
    final nodeId = _activeNodeId;
    final controller = nodeId == null ? null : _controllers[nodeId];
    final node = nodeId == null ? null : _findNode(nodeId);
    if (controller == null || node == null) return;

    final text = controller.text;
    final selection = controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    // 光标右侧已是该符号的结束符号：跳过插入，避免出现重复的结束符号
    if (!hasSelection && symbol.closing != null && start < text.length && text[start] == symbol.closing) {
      controller.selection = TextSelection.collapsed(offset: start + 1);
      return;
    }

    final bool autoComplete =
        symbol.isPairStart && SettingsService.instance.punctuationAutoCompleteEnabled;

    final String inserted;
    final int caretOffset;
    if (autoComplete && hasSelection) {
      // 用成对符号包裹选中文字，光标落在结束符号之后
      inserted = symbol.symbol + text.substring(start, end) + symbol.closing!;
      caretOffset = start + inserted.length;
    } else if (autoComplete) {
      // 插入一对符号，光标落在两条符号之间
      inserted = symbol.symbol + symbol.closing!;
      caretOffset = start + symbol.symbol.length;
    } else {
      inserted = symbol.symbol;
      caretOffset = start + inserted.length;
    }

    final String newText = text.substring(0, start) + inserted + text.substring(end);

    _undoManager.beginBatch();
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    // 程序化改写不会触发输入框的 onChanged，需同步节点文本与样式区间
    node.styleRanges = TextStyleRangeUtils.adjustForTextChange(node.styleRanges, text, newText);
    (controller as RichTextEditingController).styleRanges = node.styleRanges;
    node.text = newText;
    _endBatchAndNotify(
        description: '插入标点符号', focusNodeId: nodeId, focusSelection: controller.selection);
  }

  // ================= 剪贴板操作 =================

  /// 剪切选中文本
  void _handleCutText() {
    final nodeId = _contextMenuNodeId;
    if (nodeId == null) return;
    final controller = _controllers[nodeId];
    final node = _findNode(nodeId);
    if (controller == null || node == null) return;

    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final selectedText = controller.text.substring(selection.start, selection.end);
    Clipboard.setData(ClipboardData(text: selectedText));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();

    final newText = controller.text.substring(0, selection.start) + controller.text.substring(selection.end);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start),
    );
    node.text = newText;
    _notifyContentChanged();
  }

  /// 复制选中文本
  void _handleCopyText() {
    final nodeId = _contextMenuNodeId;
    if (nodeId == null) return;
    final controller = _controllers[nodeId];
    if (controller == null) return;

    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final selectedText = controller.text.substring(selection.start, selection.end);
    Clipboard.setData(ClipboardData(text: selectedText));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();
  }

  /// 删除选中文本
  void _handleDeleteText() {
    final nodeId = _contextMenuNodeId;
    if (nodeId == null) return;
    final controller = _controllers[nodeId];
    final node = _findNode(nodeId);
    if (controller == null || node == null) return;

    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final newText = controller.text.substring(0, selection.start) + controller.text.substring(selection.end);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start),
    );
    node.text = newText;
    _notifyContentChanged();
  }

  /// 将节点序列化为带缩进的文本（保留选中范围内的相对层级结构）
  ///
  /// 以第一个节点的深度为基准计算相对缩进：与首个节点同级或更高级的节点
  /// 缩进清空，子节点按相对深度添加制表符
  String _serializeNodes(List<FlatNode> nodes) {
    final buffer = StringBuffer();
    // 栈记录已序列化节点的原始深度，用于计算相对缩进
    final stack = <int>[];

    for (final flat in nodes) {
      // 弹出栈中深度大于等于当前节点的节点（它们不是当前节点的祖先）
      while (stack.isNotEmpty && stack.last >= flat.depth) {
        stack.removeLast();
      }
      // 相对缩进深度 = 栈大小（选中范围内的祖先数量）
      buffer.write('\t' * stack.length);
      buffer.writeln(flat.node.text);
      stack.add(flat.depth);
    }
    return buffer.toString();
  }

  /// 复制选中节点到剪贴板
  void _copySelectedNodes() {
    final selectedNodes = _getSelectedFlatNodes();
    if (selectedNodes.isEmpty) return;

    final text = _serializeNodes(selectedNodes);
    Clipboard.setData(ClipboardData(text: text));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();
  }

  /// 剪切选中节点：复制后删除
  void _cutSelectedNodes() {
    final selectedNodes = _getSelectedFlatNodes();
    if (selectedNodes.isEmpty) return;

    final text = _serializeNodes(selectedNodes);
    Clipboard.setData(ClipboardData(text: text));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();
    _deleteSelectedNodes();
  }

  /// 删除选中节点（连同子节点一起删除，不提升子节点）
  /// 所有根节点都被选中时阻止删除，始终保持至少一个节点存在。
  void _deleteSelectedNodes() {
    if (_selectedNodeIds.isEmpty) return;

    // 所有根节点都被选中时阻止删除，始终保持至少一个节点存在
    if (_roots.every((r) => _selectedNodeIds.contains(r.id))) return;

    // 记录删除前选区中第一个节点的位置，用于后续恢复焦点
    final flatList = _flatten();
    final selectedFlatNodes = flatList.where((f) => _selectedNodeIds.contains(f.node.id)).toList();
    if (selectedFlatNodes.isEmpty) return;

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    final firstSelectedIndex = flatList.indexOf(selectedFlatNodes.first);

    // 收集所有需要删除的节点ID（包括选中节点的子节点）
    final idsToDelete = <String>{};
    void collectIds(OutlineNode node) {
      idsToDelete.add(node.id);
      for (final child in node.children) {
        collectIds(child);
      }
    }

    for (final flat in selectedFlatNodes) {
      collectIds(flat.node);
    }

    // 从树中移除选中的顶层节点
    void removeFromList(List<OutlineNode> nodes) {
      nodes.removeWhere((n) => _selectedNodeIds.contains(n.id));
      for (final node in nodes) {
        removeFromList(node.children);
      }
    }

    removeFromList(_roots);

    // 释放被删除节点的资源
    for (final id in idsToDelete) {
      final controller = _controllers[id];
      if (controller != null) {
        _undoManager.unregisterController(id, controller);
        controller.dispose();
        _controllers.remove(id);
      }
      _focusNodes[id]?.dispose();
      _focusNodes.remove(id);
      _nodeTileKeys.remove(id);
    }

    _selectedNodeIds.clear();
    _selectAllLevel = 0;
    _selectionAnchorIndex = null;
    setState(() {});
    _notifyBatchChanged();

    // 恢复焦点：优先聚焦到删除前的上一节点（就近原则），否则聚焦到删除后列表的第一个节点
    String? targetId;
    final previousIndex = firstSelectedIndex - 1;
    if (previousIndex >= 0) {
      targetId = flatList[previousIndex].node.id;
    }
    if (targetId == null) {
      final newFlatList = _flatten();
      if (newFlatList.isNotEmpty) {
        targetId = newFlatList[0].node.id;
      }
    }

    if (targetId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 批量选择模式下不聚焦输入框，避免误唤起输入法
        if (!_isBatchSelectionMode) {
          _focusNodeWithSelection(targetId!, moveCursorToEnd: true);
        }
        _endBatchAndNotify(
          description: '删除选中节点',
          focusNodeId: targetId,
          focusSelection: _selectionAtEnd(targetId!),
        );
      });
    } else {
      // 无可聚焦节点时仍需结束批量操作
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _endBatchAndNotify(description: '删除选中节点');
      });
    }
  }

  /// 粘贴剪贴板内容，替换当前选中的节点
  ///
  /// 先删除所有选中节点，在第一个选中节点的位置插入剪贴板解析出的新节点
  void _pasteNodes() {
    if (_selectedNodeIds.isEmpty) return;

    final selectedNodes = _getSelectedFlatNodes();
    if (selectedNodes.isEmpty) return;

    final firstSelected = selectedNodes.first;
    final firstLocation = _findLocation(firstSelected.node.id);
    if (firstLocation == null) return;

    Clipboard.getData('text/plain').then((data) {
      if (data == null || data.text == null || data.text!.isEmpty) return;

      final lines = data.text!.split('\n').where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) return;

      // 在剪贴板数据可用后再开启批量操作，确保 beginBatch 与 endBatch 配对
      _undoManager.beginBatch();

      // 记录选中节点所在兄弟列表和起始插入位置
      final siblings = firstLocation.parent?.children ?? _roots;
      var insertIndex = firstLocation.index;

      // 删除所有选中节点（连同子节点）
      final idsToDelete = <String>{};
      void collectIds(OutlineNode node) {
        idsToDelete.add(node.id);
        for (final child in node.children) {
          collectIds(child);
        }
      }

      for (final flat in selectedNodes) {
        collectIds(flat.node);
      }

      void removeFromList(List<OutlineNode> nodes) {
        nodes.removeWhere((n) => _selectedNodeIds.contains(n.id));
        for (final node in nodes) {
          removeFromList(node.children);
        }
      }

      removeFromList(_roots);

      // 释放被删除节点的资源
      for (final id in idsToDelete) {
        final controller = _controllers[id];
        if (controller != null) {
          _undoManager.unregisterController(id, controller);
          controller.dispose();
          _controllers.remove(id);
        }
        _focusNodes[id]?.dispose();
        _focusNodes.remove(id);
        _nodeTileKeys.remove(id);
      }

      _selectedNodeIds.clear();
      _selectAllLevel = 0;
      _selectionAnchorIndex = null;

      // 解析带缩进的文本，重建节点层级结构
      final newNodes = _parseNodesFromText(lines);

      for (final newNode in newNodes) {
        _ensureResourcesForNode(newNode);
        siblings.insert(insertIndex, newNode);
        insertIndex++;
      }

      setState(() {});

      // 聚焦到第一个新节点
      if (newNodes.isNotEmpty) {
        final firstNodeId = newNodes.first.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodeWithSelection(firstNodeId, moveCursorToEnd: false);
          _endBatchAndNotify(description: '粘贴节点', focusNodeId: firstNodeId, focusSelection: _selectionAtStart());
        });
      } else {
        // 无新节点插入时仍需结束批量操作
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _endBatchAndNotify(description: '粘贴节点');
        });
      }
    });
  }

  /// 粘贴文本到指定节点的光标位置
  ///
  /// 多行文本按行分割创建新节点，缩进转换为子节点层级；
  /// 单行文本直接插入到光标位置（替换选区）。
  void _pasteIntoNode(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null) return;

    final siblings = location.parent?.children ?? _roots;
    final currentNode = siblings[location.index];
    final controller = _controllers[nodeId];
    if (controller == null) return;

    Clipboard.getData('text/plain').then((data) {
      if (data == null || data.text == null || data.text!.isEmpty) return;

      // 统一换行符
      final normalized = data.text!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      // 单行文本：直接插入到光标位置
      if (!normalized.contains('\n')) {
        _insertTextAtCursor(controller, normalized);
        currentNode.text = controller.text;
        return;
      }

      // 多行文本：按行分割，过滤空白行
      final lines = normalized.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) return;

      // 解析为节点树，保留缩进层级
      final newNodes = _parseNodesFromText(lines);
      if (newNodes.isEmpty) return;

      // 多行粘贴涉及节点结构变化，开启批量操作
      _undoManager.beginBatch();

      final selection = controller.selection;
      final selStart = selection.start >= 0 ? selection.start : 0;
      final selEnd = selection.end >= 0 ? selection.end : controller.text.length;
      final textBefore = controller.text.substring(0, selStart);
      final textAfter = controller.text.substring(selEnd);

      final firstNode = newNodes.first;

      // 第一个节点的子节点追加为当前节点的子节点
      if (firstNode.children.isNotEmpty) {
        for (final child in firstNode.children) {
          _ensureResourcesForNode(child);
        }
        currentNode.children.addAll(firstNode.children);
        currentNode.isExpanded = true;
      }

      // 其余根节点作为同级节点插入到当前节点之后
      final pastedSiblings = <OutlineNode>[];
      for (int i = 1; i < newNodes.length; i++) {
        pastedSiblings.add(newNodes[i]);
      }

      // 光标后的剩余文本作为新节点追加到末尾（不属于粘贴内容）
      final nodesToInsert = <OutlineNode>[];
      nodesToInsert.addAll(pastedSiblings);
      if (textAfter.isNotEmpty) {
        nodesToInsert.add(_createNode(textAfter));
      }

      var insertIndex = location.index + 1;
      for (final newNode in nodesToInsert) {
        _ensureResourcesForNode(newNode);
        siblings.insert(insertIndex, newNode);
        insertIndex++;
      }

      // 确定最后一个粘贴节点（文档顺序最末的粘贴节点，排除 textAfter 节点）
      final OutlineNode lastPastedNode;
      if (pastedSiblings.isNotEmpty) {
        // 存在同级粘贴节点：取最后一个的最深右子孙
        lastPastedNode = _lastDescendant(pastedSiblings.last);
      } else if (firstNode.children.isNotEmpty) {
        // 仅第一个节点的子节点被追加为当前节点的子节点
        lastPastedNode = _lastDescendant(firstNode.children.last);
      } else {
        // 无独立粘贴节点，仅文本合并到当前节点
        lastPastedNode = currentNode;
      }

      // 在修改当前节点文本前，先把焦点切换到最后一个粘贴节点
      // 这样当前节点失去焦点，光标不显示，避免光标先在当前节点末尾闪烁再跳到目标节点
      if (lastPastedNode.id != nodeId) {
        final lastFocusNode = _focusNodes[lastPastedNode.id];
        if (lastFocusNode != null) {
          lastFocusNode.requestFocus();
        }
      }

      // 第一个解析节点的文本合并到当前节点光标位置
      final currentNewText = textBefore + firstNode.text;
      controller.text = currentNewText;
      currentNode.text = currentNewText;

      setState(() {});

      // 聚焦到最后一个粘贴节点并滚动到可见
      final lastPastedId = lastPastedNode.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusAndScrollToNode(lastPastedId, moveCursorToEnd: true);
        _endBatchAndNotify(
          description: '粘贴文本到节点',
          focusNodeId: lastPastedId,
          focusSelection: _selectionAtEnd(lastPastedId),
        );
      });
    });
  }

  /// 在控制器光标位置插入文本（替换当前选区）
  void _insertTextAtCursor(TextEditingController controller, String text) {
    final selection = controller.selection;
    final start = selection.start >= 0 ? selection.start : 0;
    final end = selection.end >= 0 ? selection.end : controller.text.length;
    final newText = controller.text.substring(0, start) + text + controller.text.substring(end);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  /// 从带缩进的文本行解析出节点列表（保留层级结构）
  ///
  /// 制表符表示层级深度，无缩进为根级节点
  List<OutlineNode> _parseNodesFromText(List<String> lines) {
    final roots = <OutlineNode>[];
    // 栈中保存 (节点, 深度) 对，用于构建层级
    final stack = <(OutlineNode, int)>[];

    for (final line in lines) {
      var depth = 0;
      var text = line;
      while (text.startsWith('\t')) {
        if (depth < _maxDepth) {
          depth++;
        }
        text = text.substring(1);
      }
      // 也处理空格缩进（4个空格视为1级）
      while (text.startsWith('    ')) {
        if (depth < _maxDepth) {
          depth++;
        }
        text = text.substring(4);
      }

      final node = _createNode(text.trim());

      // 弹出栈中深度大于等于当前深度的节点
      while (stack.isNotEmpty && stack.last.$2 >= depth) {
        stack.removeLast();
      }

      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.$1.children.add(node);
        stack.last.$1.isExpanded = true;
      }
      stack.add((node, depth));
    }

    return roots;
  }

  // ================= 右键菜单 =================

  /// 处理右键按下事件：定位光标并记录目标节点
  ///
  /// 根据点击位置查找对应的节点，聚焦该节点并在无选区时将光标移动到点击处。
  /// 记录目标节点ID供菜单项操作使用。
  ///
  /// 异步刷新剪贴板状态缓存，确保菜单中"粘贴"项的启用状态与实际剪贴板内容一致。
  Future<void> _handleSecondaryTapDown(Offset position) async {
    // 标记正在唤起右键菜单，阻止 focusNode 获得焦点时清除选区
    _isContextMenuOpening = true;

    final flatList = _flatten();
    if (flatList.isEmpty) {
      _contextMenuNodeId = null;
      return;
    }

    final nodeIndex = _findNodeIndexAtPosition(position);
    if (nodeIndex == null) {
      _contextMenuNodeId = null;
      return;
    }

    final nodeId = flatList[nodeIndex].node.id;

    // 右键目标节点切换时，主动清除上一个目标节点的文本选区
    // （失焦的节点不会触发焦点监听器，需在此显式清除）
    final previousNodeId = _contextMenuNodeId;
    _contextMenuNodeId = nodeId;
    if (previousNodeId != null && previousNodeId != nodeId) {
      final prevController = _controllers[previousNodeId];
      if (prevController != null && prevController.selection.isValid && !prevController.selection.isCollapsed) {
        final offset = prevController.selection.baseOffset.clamp(0, prevController.text.length);
        prevController.selection = TextSelection.collapsed(offset: offset);
      }
    }

    // 右键目标不在节点选区中时，清除节点选区
    if (_selectedNodeIds.isNotEmpty && !_selectedNodeIds.contains(nodeId)) {
      _selectedNodeIds.clear();
      _selectAllLevel = 0;
      if (mounted) setState(() {});
    }

    final focusNode = _focusNodes[nodeId];
    final controller = _controllers[nodeId];
    if (focusNode == null || controller == null) return;

    // 存在节点选区且右键目标在选区内时，不聚焦 TextField
    // （避免粘贴操作删除正持有焦点的节点，导致 focusNode 销毁时触发级联焦点变化）
    final skipFocus = _selectedNodeIds.isNotEmpty && _selectedNodeIds.contains(nodeId);
    if (!skipFocus) {
      focusNode.requestFocus();
    }

    // 无选区时将光标定位到点击处
    final selection = controller.selection;
    if (selection.isCollapsed || !selection.isValid) {
      final renderEditable = _findRenderEditable(nodeId);
      if (renderEditable != null && renderEditable.attached) {
        final offset = renderEditable.getPositionForPoint(position).offset;
        controller.selection = TextSelection.collapsed(offset: offset);
      }
    }

    // 刷新剪贴板状态缓存，确保菜单中"粘贴"项的启用状态正确
    await ClipboardStateCache.refresh();
  }

  /// 右键菜单关闭后恢复焦点
  void _handleContextMenuDismissed() {
    if (!mounted) return;

    // 存在节点选区时，恢复编辑器级焦点，不聚焦 TextField
    // （避免触发 focusNode listener 清除节点选区，导致后续操作失效）
    if (_selectedNodeIds.isNotEmpty) {
      _editorFocusNode.requestFocus();
      // 延迟重置标志，避免 TextField 失焦时 listener 清除节点选区
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isContextMenuOpening = false;
      });
      return;
    }

    _isContextMenuOpening = false;
    final nodeId = _contextMenuNodeId;
    if (nodeId != null) {
      final focusNode = _focusNodes[nodeId];
      if (focusNode != null && !focusNode.hasFocus) {
        focusNode.requestFocus();
      }
    }
  }

  /// 右键菜单关闭后的光标同步与焦点修正
  ///
  /// 在菜单显示中或刚关闭时收到下一次指针按下，立即将光标定位到点击位置
  /// 并聚焦目标节点，覆盖 [_handleContextMenuDismissed] 对旧节点的焦点请求，
  /// 避免菜单关闭后焦点先回到菜单所在节点造成光标闪烁
  void _syncCursorAndFocusAfterMenuDismiss(PointerDownEvent event) {
    final nodeIndex = _findNodeIndexAtPosition(event.position);
    if (nodeIndex == null) return;

    final flatList = _flatten();
    final nodeId = flatList[nodeIndex].node.id;
    final controller = _controllers[nodeId];
    final focusNode = _focusNodes[nodeId];
    final renderEditable = _findRenderEditable(nodeId);
    if (controller == null || focusNode == null || renderEditable == null || !renderEditable.attached) {
      return;
    }

    // 立即将光标定位到点击位置
    final offset = renderEditable.getPositionForPoint(event.position).offset;
    controller.selection = TextSelection.collapsed(offset: offset);

    // 请求目标节点焦点，覆盖 _handleContextMenuDismissed 对旧节点的焦点请求
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }
  }

  /// 构建右键菜单项列表
  ///
  /// 菜单结构：
  /// - 标题级别行（H1/H2/H3/T）
  /// - 文字样式行（加粗/斜体/下划线/删除线）
  /// - 字体颜色
  /// - 字底颜色
  /// - 常规菜单项：剪切、复制、粘贴、删除、全选
  List<ContextMenuItem> _buildContextMenuItems() {
    final nodeId = _contextMenuNodeId;
    final controller = nodeId != null ? _controllers[nodeId] : null;
    final selection = controller?.selection ?? const TextSelection.collapsed(offset: 0);
    final bool hasTextSelection = selection.isValid && !selection.isCollapsed;
    final bool hasNodeSelection = _selectedNodeIds.isNotEmpty;
    final bool isReadOnly = widget.readOnly;
    final bool hasTarget = nodeId != null && controller != null;

    // 计算当前选区/节点的颜色，用于子菜单高亮
    final targetIds = _getStyleTargetNodeIds(nodeId);
    final targetNodes = targetIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();
    final TextSelection? styleSelection = targetIds.length == 1 ? _controllers[targetIds.first]?.selection : null;
    final currentFg = _getCurrentColor(targetNodes, styleSelection, true);
    final currentBg = _getCurrentColor(targetNodes, styleSelection, false);

    return [
      // 标题/正文格式行
      ContextMenuItem(label: _buildHeadingRow(nodeId), enabled: false),
      // 文字样式行
      ContextMenuItem(label: _buildFormatRow(nodeId), enabled: false),

      ContextMenuItem.divider(),

      // 字体颜色
      ContextMenuItem(
        labelText: '字体颜色',
        iconBuilder: (color) => _buildColorBarIcon(Icons.format_color_text, color, Colors.red),
        children: [
          for (final c in OutlineColorPalette.colors)
            ContextMenuItem(
              // 当前颜色与该色板一致时，文字前加 '·' 标记
              labelText: currentFg.isUniform && currentFg.color == c.foreground ? '· ${c.name}' : c.name,
              iconBuilder: (_) => _buildColorSwatchIcon(c.foreground),
              // 当前颜色与该色板一致时，文字高亮为对应颜色并加粗
              labelColor: currentFg.isUniform && currentFg.color == c.foreground ? c.foreground : null,
              labelBold: currentFg.isUniform && currentFg.color == c.foreground,
              enabled: !isReadOnly && (hasNodeSelection || hasTarget),
              onTap: () {
                if (hasNodeSelection) {
                  _applyColor(_selectedNodeIds.toList(), foregroundColor: c.foreground);
                } else if (nodeId != null) {
                  _applyColor([nodeId], foregroundColor: c.foreground);
                }
              },
            ),
          // 默认：清除字体颜色
          ContextMenuItem.divider(),
          ContextMenuItem(
            labelText: '默认',
            iconBuilder: (_) => _buildColorSwatchIcon(widget.colorScheme.onSurface),
            enabled: !isReadOnly && (hasNodeSelection || hasTarget),
            onTap: () {
              if (hasNodeSelection) {
                _applyColor(_selectedNodeIds.toList(), clearForeground: true);
              } else if (nodeId != null) {
                _applyColor([nodeId], clearForeground: true);
              }
            },
          ),
        ],
      ),
      // 字底颜色
      ContextMenuItem(
        labelText: '字底颜色',
        iconBuilder: (color) => _buildColorBarIcon(Icons.format_color_fill, color, Colors.amber),
        children: [
          for (final c in OutlineColorPalette.colors)
            ContextMenuItem(
              // 当前字底色与该色板一致时，文字前加 '·' 标记
              labelText: currentBg.isUniform && currentBg.color == c.background ? '· ${c.name}' : c.name,
              iconBuilder: (_) => _buildColorSwatchIcon(c.background),
              // 当前字底色与该色板一致时，文字高亮为对应颜色并加粗
              labelColor: currentBg.isUniform && currentBg.color == c.background ? c.background : null,
              labelBold: currentBg.isUniform && currentBg.color == c.background,
              enabled: !isReadOnly && (hasNodeSelection || hasTarget),
              onTap: () {
                if (hasNodeSelection) {
                  _applyColor(_selectedNodeIds.toList(), backgroundColor: c.background);
                } else if (nodeId != null) {
                  _applyColor([nodeId], backgroundColor: c.background);
                }
              },
            ),
          // 默认：清除字底颜色
          ContextMenuItem.divider(),
          ContextMenuItem(
            labelText: '默认',
            iconBuilder: (_) => _buildColorSwatchIcon(widget.colorScheme.surface),
            enabled: !isReadOnly && (hasNodeSelection || hasTarget),
            onTap: () {
              if (hasNodeSelection) {
                _applyColor(_selectedNodeIds.toList(), clearBackground: true);
              } else if (nodeId != null) {
                _applyColor([nodeId], clearBackground: true);
              }
            },
          ),
        ],
      ),

      ContextMenuItem.divider(),

      // 剪切
      ContextMenuItem(
        labelText: '剪切',
        icon: Icons.cut,
        enabled: !isReadOnly && (hasNodeSelection || (hasTarget && hasTextSelection)),
        onTap: () {
          if (hasNodeSelection) {
            _cutSelectedNodes();
          } else {
            _handleCutText();
          }
        },
      ),
      // 复制
      ContextMenuItem(
        labelText: '复制',
        icon: Icons.copy,
        enabled: hasNodeSelection || (hasTarget && hasTextSelection),
        onTap: () {
          if (hasNodeSelection) {
            _copySelectedNodes();
          } else {
            _handleCopyText();
          }
        },
      ),
      // 粘贴
      ContextMenuItem(
        labelText: '粘贴',
        icon: Icons.paste,
        enabled: !isReadOnly && ClipboardStateCache.hasContent && (hasNodeSelection || hasTarget),
        onTap: () {
          if (hasNodeSelection) {
            _pasteNodes();
          } else if (nodeId != null) {
            _pasteIntoNode(nodeId);
          }
        },
      ),
      // 删除
      ContextMenuItem(
        labelText: '删除',
        icon: Icons.delete_outline,
        enabled: !isReadOnly && (hasNodeSelection || (hasTarget && hasTextSelection)),
        labelColor: Colors.redAccent,
        onTap: () {
          if (hasNodeSelection) {
            _deleteSelectedNodes();
          } else {
            _handleDeleteText();
          }
        },
      ),

      ContextMenuItem.divider(),

      // 全选
      ContextMenuItem(
        labelText: '全选',
        icon: Icons.select_all,
        enabled: hasTarget || _flatten().isNotEmpty,
        onTap: () => _handleSelectAllFromMenu(nodeId),
      ),
    ];
  }

  /// 构建带颜色指示条的菜单项图标
  ///
  /// 参考 [_MenuItem] 的图标尺寸（18px），在图标底部叠加一条固定颜色的指示条。
  /// 通过 [ContextMenuItem.iconBuilder] 传入，接收当前图标颜色（含悬停/禁用状态），
  /// 实现与普通菜单项一致的悬停变色效果。
  Widget _buildColorBarIcon(IconData icon, Color iconColor, Color indicatorColor) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor),
          // 颜色指示条，叠加在图标底部
          Positioned(
            bottom: -1,
            child: Container(width: 16, height: 4, decoration: BoxDecoration(color: indicatorColor)),
          ),
        ],
      ),
    );
  }

  /// 构建颜色色块图标（用于子菜单的颜色选项）
  ///
  /// 显示一个 18×18 的圆角填充色块，直观表示该选项对应的颜色。
  Widget _buildColorSwatchIcon(Color swatchColor) {
    return SizedBox(
      width: 18,
      height: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: swatchColor,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.black12, width: 0.5),
        ),
      ),
    );
  }

  /// 构建标题级别按钮行（H1/H2/H3/T）
  ///
  /// 以单选方式切换目标节点的标题级别，选中后立即写入并触发重建。
  /// 节点选区批量操作：所有选中节点会同时应用相同的标题级别。
  Widget _buildHeadingRow(String? nodeId) {
    final targetIds = _getStyleTargetNodeIds(nodeId);
    final nodes = targetIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();
    if (nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    return HeadingLevelSelector(
      nodes: nodes,
      onLevelChanged: (level) => _setHeadingLevel(targetIds, level),
    );
  }

  /// 构建文字样式按钮行（加粗/斜体/下划线/删除线）
  ///
  /// 按钮的初始状态由选区决定：
  /// - 节点选区状态下：合并所有选中节点的样式状态
  /// - 有选中文字时：根据选中文字的样式状态点亮
  /// - 无选中文字时：根据整个节点文本的样式状态点亮
  Widget _buildFormatRow(String? nodeId) {
    final targetIds = _getStyleTargetNodeIds(nodeId);
    if (targetIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final targetNodes = targetIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();
    if (targetNodes.isEmpty) {
      return const SizedBox.shrink();
    }
    // 节点选区状态下不使用文字选区，单节点时使用其文字选区
    final TextSelection? selection = targetIds.length == 1 ? _controllers[targetIds.first]?.selection : null;
    // 合并所有目标节点的样式状态
    final selectionFlags = _getSelectionFlags(targetNodes, selection);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ToggleToolButton(
          icon: MaterialIcons.format_bold,
          tooltip: '加粗',
          initialValue: selectionFlags.bold,
          onChanged: (_) => _toggleTextStyle(targetIds, TextStyleFlags.toggleBold),
        ),
        ToggleToolButton(
          icon: MaterialIcons.format_italic,
          tooltip: '斜体',
          initialValue: selectionFlags.italic,
          onChanged: (_) => _toggleTextStyle(targetIds, TextStyleFlags.toggleItalic),
        ),
        ToggleToolButton(
          icon: MaterialIcons.format_underlined,
          tooltip: '下划线',
          initialValue: selectionFlags.underline,
          onChanged: (_) => _toggleTextStyle(targetIds, TextStyleFlags.toggleUnderline),
        ),
        ToggleToolButton(
          icon: MaterialIcons.strikethrough_s,
          tooltip: '删除线',
          initialValue: selectionFlags.strikethrough,
          onChanged: (_) => _toggleTextStyle(targetIds, TextStyleFlags.toggleStrikethrough),
        ),
      ],
    );
  }

  // ================= 键盘事件 =================

  /// 节点级键盘事件处理
  ///
  /// 拦截特定按键并执行对应的节点操作，返回 handled 阻止 TextField 默认行为
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event, String nodeId) {
    // 拦截 Enter 键的重复事件，防止 TextField 插入换行符
    if (event is KeyRepeatEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      return KeyEventResult.handled;
    }

    // 拦截撤销/恢复的重复事件（长按 Ctrl+Z / Ctrl+Y），避免触发 TextField 内置撤销机制
    if (event is KeyRepeatEvent && HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          redo();
        } else {
          undo();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY) {
        redo();
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isControl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Ctrl+S / Cmd+S：保存
    if ((isControl || HardwareKeyboard.instance.isMetaPressed) && event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return KeyEventResult.handled;
    }

    // Ctrl+F / Cmd+F：打开查找
    if ((isControl || HardwareKeyboard.instance.isMetaPressed) && event.logicalKey == LogicalKeyboardKey.keyF) {
      context.read<WorkspaceProvider>().openFindReplace();
      return KeyEventResult.handled;
    }
    // Ctrl+H / Cmd+H：打开查找替换（展开替换区域）
    if ((isControl || HardwareKeyboard.instance.isMetaPressed) && event.logicalKey == LogicalKeyboardKey.keyH) {
      context.read<WorkspaceProvider>().openFindReplace(showReplace: true);
      return KeyEventResult.handled;
    }
    // Escape：查找替换栏可见时优先关闭它
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final provider = context.read<WorkspaceProvider>();
      if (provider.isFindReplaceVisible) {
        provider.closeFindReplace();
        return KeyEventResult.handled;
      }
    }

    // 只读模式下仅允许导航，禁用所有修改操作
    if (widget.readOnly) {
      // 上箭头：导航到上一节点
      if (event.logicalKey == LogicalKeyboardKey.arrowUp && !isShift) {
        _moveFocus(nodeId, false);
        return KeyEventResult.handled;
      }
      // 下箭头：导航到下一节点
      if (event.logicalKey == LogicalKeyboardKey.arrowDown && !isShift) {
        _moveFocus(nodeId, true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Ctrl+Z：撤销；Ctrl+Shift+Z 或 Ctrl+Y：重做
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        redo();
      } else {
        undo();
      }
      return KeyEventResult.handled;
    }
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyY) {
      redo();
      return KeyEventResult.handled;
    }

    // ================= 文字样式快捷键 =================

    // Ctrl+B：加粗
    if (isControl && !isAlt && event.logicalKey == LogicalKeyboardKey.keyB) {
      _toggleTextStyle([nodeId], TextStyleFlags.toggleBold);
      return KeyEventResult.handled;
    }
    // Ctrl+I：斜体
    if (isControl && !isAlt && event.logicalKey == LogicalKeyboardKey.keyI) {
      _toggleTextStyle([nodeId], TextStyleFlags.toggleItalic);
      return KeyEventResult.handled;
    }
    // Ctrl+U：下划线
    if (isControl && !isAlt && event.logicalKey == LogicalKeyboardKey.keyU) {
      _toggleTextStyle([nodeId], TextStyleFlags.toggleUnderline);
      return KeyEventResult.handled;
    }

    // Alt+数字：设置标题级别
    // Shift 时作用于当前节点的所有同级节点，否则仅作用于当前节点
    if (isAlt && !isControl) {
      final level = OutlineShortcutKeys.headingLevelFromKey(event.logicalKey);
      if (level != null) {
        final targetIds = isShift ? _getSiblingNodeIds(nodeId) : [nodeId];
        _setHeadingLevel(targetIds, level);
        return KeyEventResult.handled;
      }

      // Alt+字母：设置字体颜色（D 为清除）
      if (OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
        if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
          _applyColor([nodeId], clearForeground: true);
        } else {
          _applyColor([nodeId],
              foregroundColor: OutlineShortcutKeys.foregroundColor(event.logicalKey));
        }
        return KeyEventResult.handled;
      }
    }

    // Ctrl+Alt+字母：设置字底颜色（D 为清除）
    if (isControl && isAlt && OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
      if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
        _applyColor([nodeId], clearBackground: true);
      } else {
        _applyColor([nodeId],
            backgroundColor: OutlineShortcutKeys.backgroundColor(event.logicalKey));
      }
      return KeyEventResult.handled;
    }

    // Enter：创建同级新节点（Ctrl+Enter 切换删除线）
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (isControl || isAlt) {
        _toggleTextStyle([nodeId], TextStyleFlags.toggleStrikethrough);
      } else if (!isShift) {
        _createSibling(nodeId);
      }
      return KeyEventResult.handled;
    }

    // Tab：缩进 / Shift+Tab：反缩进
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (isShift) {
        _outdentNode(nodeId);
      } else {
        _indentNode(nodeId);
      }
      return KeyEventResult.handled;
    }

    // Backspace：空节点删除；有内容且光标在开头时仅合并到同级上一节点
    // 有子节点的节点视为非空，不删除也不合并
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final controller = _controllers[nodeId];
      if (controller != null && controller.selection.isCollapsed) {
        final node = _findNode(nodeId);
        final hasChildren = node != null && node.children.isNotEmpty;
        if (!hasChildren) {
          if (controller.text.isEmpty) {
            _deleteNode(nodeId);
            return KeyEventResult.handled;
          } else if (controller.selection.baseOffset == 0) {
            _mergeWithPreviousNode(nodeId);
            return KeyEventResult.handled;
          }
        }
      }
    }

    // 上箭头：导航到上一节点
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && !isShift) {
      _moveFocus(nodeId, false);
      return KeyEventResult.handled;
    }

    // 下箭头：导航到下一节点
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && !isShift) {
      _moveFocus(nodeId, true);
      return KeyEventResult.handled;
    }

    // Ctrl+A：全选当前主题，再次按下全选整个文档
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyA) {
      final controller = _controllers[nodeId];
      // 无节点选区时：先检查当前输入框文本是否已全选
      // 未全选则放行默认行为（全选文本），已全选则进入主题选区
      if (_selectedNodeIds.isEmpty && controller != null) {
        final sel = controller.selection;
        final isTextFullySelected =
            controller.text.isEmpty || (!sel.isCollapsed && sel.start == 0 && sel.end == controller.text.length);
        if (!isTextFullySelected) {
          return KeyEventResult.ignored;
        }
      }
      _handleSelectAll(nodeId);
      return KeyEventResult.handled;
    }

    // Ctrl+V：粘贴文本（多行转换为节点，缩进转换为子节点）
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyV) {
      _pasteIntoNode(nodeId);
      return KeyEventResult.handled;
    }

    // Escape：清除节点选区（仅有选区时拦截）
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selectedNodeIds.isNotEmpty || _selectAllLevel != 0) {
        _clearSelectionAndRefocus();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// 编辑器级键盘事件处理（节点选区激活时接收键盘事件）
  KeyEventResult _onEditorKeyEvent(FocusNode node, KeyEvent event) {
    // 拦截撤销/恢复的重复事件（长按 Ctrl+Z / Ctrl+Y），与 _onKeyEvent 保持一致
    if (event is KeyRepeatEvent && HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          redo();
        } else {
          undo();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY) {
        redo();
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isControl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Ctrl+S / Cmd+S：保存
    if ((isControl || HardwareKeyboard.instance.isMetaPressed) && event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return KeyEventResult.handled;
    }

    // Ctrl+F / Cmd+F：打开查找
    if ((isControl || HardwareKeyboard.instance.isMetaPressed) && event.logicalKey == LogicalKeyboardKey.keyF) {
      context.read<WorkspaceProvider>().openFindReplace();
      return KeyEventResult.handled;
    }
    // Ctrl+H / Cmd+H：打开查找替换（展开替换区域）
    if ((isControl || HardwareKeyboard.instance.isMetaPressed) && event.logicalKey == LogicalKeyboardKey.keyH) {
      context.read<WorkspaceProvider>().openFindReplace(showReplace: true);
      return KeyEventResult.handled;
    }
    // Escape：查找替换栏可见时优先关闭它
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final provider = context.read<WorkspaceProvider>();
      if (provider.isFindReplaceVisible) {
        provider.closeFindReplace();
        return KeyEventResult.handled;
      }
      // 查找替换栏未可见时，清除选区并恢复焦点
      _clearSelectionAndRefocus();
      return KeyEventResult.handled;
    }

    // 只读模式下禁用所有修改操作
    if (widget.readOnly) {
      // Ctrl+C：复制选中节点（只读模式下仍允许复制）
      if (isControl && event.logicalKey == LogicalKeyboardKey.keyC) {
        if (_selectedNodeIds.isNotEmpty) {
          _copySelectedNodes();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    // Ctrl+Z：撤销；Ctrl+Shift+Z 或 Ctrl+Y：重做
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        redo();
      } else {
        undo();
      }
      return KeyEventResult.handled;
    }
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyY) {
      redo();
      return KeyEventResult.handled;
    }

    // ================= 文字样式快捷键（作用于节点选区）=================

    if (_selectedNodeIds.isNotEmpty) {
      final targetIds = _selectedNodeIds.toList();

      // Ctrl+B：加粗；Ctrl+I：斜体；Ctrl+U：下划线；Ctrl+Enter：删除线
      if (isControl && !isAlt) {
        if (event.logicalKey == LogicalKeyboardKey.keyB) {
          _toggleTextStyle(targetIds, TextStyleFlags.toggleBold);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyI) {
          _toggleTextStyle(targetIds, TextStyleFlags.toggleItalic);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyU) {
          _toggleTextStyle(targetIds, TextStyleFlags.toggleUnderline);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _toggleTextStyle(targetIds, TextStyleFlags.toggleStrikethrough);
          return KeyEventResult.handled;
        }
      }

      // Alt+数字：设置标题级别
      if (isAlt && !isControl) {
        final level = OutlineShortcutKeys.headingLevelFromKey(event.logicalKey);
        if (level != null) {
          _setHeadingLevel(targetIds, level);
          return KeyEventResult.handled;
        }

        // Alt+字母：设置字体颜色（D 为清除）
        if (OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
          if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
            _applyColor(targetIds, clearForeground: true);
          } else {
            _applyColor(targetIds,
                foregroundColor: OutlineShortcutKeys.foregroundColor(event.logicalKey));
          }
          return KeyEventResult.handled;
        }
      }

      // Ctrl+Alt+字母：设置字底颜色（D 为清除）
      if (isControl && isAlt && OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
        if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
          _applyColor(targetIds, clearBackground: true);
        } else {
          _applyColor(targetIds,
              backgroundColor: OutlineShortcutKeys.backgroundColor(event.logicalKey));
        }
        return KeyEventResult.handled;
      }
    }

    // Tab：缩进全部选中节点；Shift+Tab：提升全部选中节点的层级
    if (_selectedNodeIds.isNotEmpty && event.logicalKey == LogicalKeyboardKey.tab) {
      if (isShift) {
        outdentSelectedNodes();
      } else {
        indentSelectedNodes();
      }
      return KeyEventResult.handled;
    }

    // Ctrl+A：在主题选区与文档选区间切换
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyA) {
      if (_selectAllLevel == 1) {
        // 主题已选 → 全选文档
        final flatList = _flatten();
        _selectedNodeIds.clear();
        for (final flat in flatList) {
          _selectedNodeIds.add(flat.node.id);
        }
        _selectAllLevel = 2;
        _selectionAnchorIndex = 0;
        setState(() {});
        return KeyEventResult.handled;
      } else if (_selectAllLevel == 2) {
        // 文档已选 → 取消全选
        _clearSelectionAndRefocus();
        return KeyEventResult.handled;
      }
      // 无节点选区时放行，由输入框执行默认全选文本
      return KeyEventResult.ignored;
    }

    // Ctrl+C：复制选中节点
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_selectedNodeIds.isNotEmpty) {
        _copySelectedNodes();
        return KeyEventResult.handled;
      }
    }

    // Ctrl+X：剪切选中节点
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyX) {
      if (_selectedNodeIds.isNotEmpty) {
        _cutSelectedNodes();
        return KeyEventResult.handled;
      }
    }

    // Ctrl+V：粘贴节点
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (_selectedNodeIds.isNotEmpty) {
        _pasteNodes();
        return KeyEventResult.handled;
      }
    }

    // Delete/Backspace：删除选中节点
    if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedNodeIds.isNotEmpty) {
        _deleteSelectedNodes();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ================= 查找替换 =================

  /// 扁平化整棵树（包含折叠的子节点），按文档顺序返回所有节点
  ///
  /// 与 [_flatten] 不同，此方法遍历所有节点（不论是否展开），
  /// 用于查找替换时搜索被折叠隐藏的内容。
  List<OutlineNode> _flattenAll() {
    final result = <OutlineNode>[];
    void walk(OutlineNode node) {
      result.add(node);
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }
    return result;
  }

  /// 扁平化整棵树并计算每个节点在全局文本中的起始偏移量
  ///
  /// 全局文本 = 所有节点文本以 '\n' 拼接。
  /// 节点起始偏移量 = 前面所有节点文本长度 + 换行符数量。
  List<({OutlineNode node, int startOffset})> _flattenAllWithOffsets() {
    final result = <({OutlineNode node, int startOffset})>[];
    int currentOffset = 0;
    void walk(OutlineNode node) {
      result.add((node: node, startOffset: currentOffset));
      final textLength = _controllers[node.id]?.text.length ?? node.text.length;
      currentOffset += textLength + 1; // +1 为节点间的换行符
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }
    return result;
  }

  /// 将全局偏移量解析为节点 ID、节点起始偏移量和节点内局部偏移量
  ///
  /// 返回 null 表示偏移量落在节点间的换行符上或超出范围。
  ({String nodeId, int nodeStart, int localOffset})? _resolveGlobalOffset(
    int globalOffset,
    List<({OutlineNode node, int startOffset})> nodesWithOffsets,
  ) {
    for (final entry in nodesWithOffsets) {
      final textLength = _controllers[entry.node.id]?.text.length ?? entry.node.text.length;
      final nodeEnd = entry.startOffset + textLength;
      if (globalOffset >= entry.startOffset && globalOffset <= nodeEnd) {
        return (
          nodeId: entry.node.id,
          nodeStart: entry.startOffset,
          localOffset: globalOffset - entry.startOffset,
        );
      }
    }
    return null;
  }

  /// 查找指定节点的所有祖先节点（从根到父节点）
  List<OutlineNode> _findAncestors(String nodeId) {
    final ancestors = <OutlineNode>[];
    bool search(List<OutlineNode> nodes) {
      for (final node in nodes) {
        if (node.id == nodeId) return true;
        ancestors.add(node);
        if (search(node.children)) return true;
        ancestors.removeLast();
      }
      return false;
    }

    search(_roots);
    return ancestors;
  }

  /// 展开指定节点的所有祖先，确保节点可见
  void _ensureAncestorsExpanded(String nodeId) {
    final ancestors = _findAncestors(nodeId);
    bool changed = false;
    for (final ancestor in ancestors) {
      if (!ancestor.isExpanded) {
        ancestor.isExpanded = true;
        changed = true;
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  /// 滚动使指定节点在视口内可见（不获取焦点）
  ///
  /// 先展开祖先确保节点可见，再通过估算位置逐步滚动使节点进入构建范围，
  /// 最终精确滚动到节点可见；节点已可见时补足底部 [margin] 的安全间距，
  /// 默认为用户设置的底边距。
  void _scrollToNode(String nodeId, {double? margin}) {
    if (!mounted) return;
    _ensureAncestorsExpanded(nodeId);
    _scrollToNodeWithRetry(nodeId, 0, null, margin: margin ?? _bottomContentPadding);
  }

  /// 滚动到节点的重试实现
  ///
  /// 节点未构建时通过估算偏移量跳转，下一帧重试直到节点构建成功或超过最大重试次数。
  void _scrollToNodeWithRetry(
    String nodeId,
    int retryCount,
    double? lastJumpOffset, {
    double margin = 0,
  }) {
    if (!mounted || !_scrollController.hasClients || retryCount >= 30) return;

    final key = _nodeTileKeys[nodeId];
    final context = key?.currentContext;

    // 节点已构建：确保目标在视口内可见
    if (context != null && context.findRenderObject()?.attached == true) {
      _ensureNodeVisible(context, margin: margin);
      return;
    }

    final flatList = _flatten();
    final targetIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    if (targetIndex == -1) return;

    // 累计目标节点之前所有已构建节点的实际高度，未构建节点用最近样本高度估算
    double measuredHeight = 0;
    int unmeasuredCount = 0;
    double sampleHeight = 40.0;
    for (int i = 0; i < targetIndex; i++) {
      final k = _nodeTileKeys[flatList[i].node.id];
      final box = k?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.size.height > 0) {
        measuredHeight += box.size.height;
        sampleHeight = box.size.height;
      } else {
        unmeasuredCount++;
      }
    }
    final estimatedOffset = measuredHeight + unmeasuredCount * sampleHeight;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final currentOffset = _scrollController.offset;
    final clampedEstimate = estimatedOffset.clamp(0.0, maxExtent);

    double jumpTarget;
    // 估算偏移被 maxScrollExtent 限制时，逐步向下推进以扩展可滚动范围
    if (lastJumpOffset != null && (clampedEstimate - lastJumpOffset).abs() < 1.0) {
      final viewport = _scrollController.position.viewportDimension;
      jumpTarget = (currentOffset + viewport * 0.6).clamp(0.0, maxExtent);
      if (jumpTarget <= currentOffset + 1.0) return;
    } else {
      jumpTarget = clampedEstimate;
    }

    _scrollController.position.jumpTo(jumpTarget);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNodeWithRetry(nodeId, retryCount + 1, jumpTarget, margin: margin);
    });
  }

  /// 确保已构建的目标节点在视口内可见
  ///
  /// 节点不在视口内时滚动到视口中央；已完全可见时若底部间距不足
  /// [margin]，只补足差额而不整体居中，避免视口跳动。
  void _ensureNodeVisible(BuildContext context, {double margin = 0}) {
    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) return;

    final viewport = RenderAbstractViewport.of(renderObject);
    final position = _scrollController.position;
    final currentOffset = _scrollController.offset;

    // 让目标顶部对齐视口顶部、底部对齐视口底部所需的偏移量
    final revealTop = viewport.getOffsetToReveal(renderObject, 0.0).offset;
    final revealBottom = viewport.getOffsetToReveal(renderObject, 1.0).offset;

    double target;
    // 当前偏移在 [revealBottom, revealTop] 之间时，目标完全在视口内
    if (currentOffset >= revealBottom && currentOffset <= revealTop) {
      // 底部间距已满足要求，无需滚动
      if (margin <= 0 || currentOffset >= revealBottom + margin) return;
      // 向下滚动补足底部间距
      target = revealBottom + margin;
    } else {
      // 目标不在视口内，滚转到让目标居中的位置
      target = viewport.getOffsetToReveal(renderObject, 0.5).offset;
    }

    position.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  // ================= 边缘自动滚动 =================

  /// 更新边缘自动滚动状态
  ///
  /// 指针进入视口上下边缘的触发区时启动定时滚动，离开触发区后停止；
  /// [selectionUpdater] 用于在指针不动、仅视口滚动的过程中继续刷新选区。
  void _updateEdgeAutoScroll(
    Offset globalPosition, {
    required void Function(Offset globalPosition) selectionUpdater,
  }) {
    _autoScrollPointerPosition = globalPosition;
    _autoScrollSelectionUpdater = selectionUpdater;

    final Rect? viewportRect = _viewportGlobalRect();
    if (viewportRect == null) {
      _stopEdgeAutoScroll();
      return;
    }

    if (_edgeScrollOvershoot(viewportRect, globalPosition) == 0) {
      _stopEdgeAutoScroll(clearUpdater: false);
      return;
    }

    _autoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _onEdgeAutoScrollTick(),
    );
  }

  /// 停止边缘自动滚动
  ///
  /// [clearUpdater] 为 false 时保留选区刷新回调，便于同一次手势内继续使用
  void _stopEdgeAutoScroll({bool clearUpdater = true}) {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (clearUpdater) {
      _autoScrollSelectionUpdater = null;
      _autoScrollPointerPosition = null;
    }
  }

  /// 边缘自动滚动的单帧处理
  ///
  /// 按指针越出边缘的距离换算滚动步长，滚动后以指针位置重新刷新选区，
  /// 使指针停住不动时仍可继续扩展选区
  void _onEdgeAutoScrollTick() {
    final Offset? pointer = _autoScrollPointerPosition;
    final Rect? viewportRect = _viewportGlobalRect();
    if (pointer == null || viewportRect == null) {
      _stopEdgeAutoScroll();
      return;
    }
    if (!_scrollController.hasClients) return;

    final double overshoot = _edgeScrollOvershoot(viewportRect, pointer);
    if (overshoot == 0) {
      _stopEdgeAutoScroll(clearUpdater: false);
      return;
    }

    // 越出越远滚动越快，单帧步长不超过上限；正值为向下滚动，负值为向上滚动
    final double magnitude = _autoScrollStepForOvershoot(overshoot.abs());
    final double delta = overshoot > 0 ? magnitude : -magnitude;

    final position = _scrollController.position;
    final double target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // 已到达可滚动边界，滚动不再生效
    if ((target - position.pixels).abs() < 0.5) return;

    position.jumpTo(target);
    _autoScrollSelectionUpdater?.call(pointer);
  }

  /// 计算指针相对视口上下边缘的越出距离
  ///
  /// 返回正数表示需要向下滚动，负数表示需要向上滚动，0 表示不在触发区内
  double _edgeScrollOvershoot(Rect viewportRect, Offset position) {
    final double distanceToTop = position.dy - viewportRect.top;
    final double distanceToBottom = viewportRect.bottom - position.dy;
    // 靠近上边缘：越出距离为负
    if (distanceToTop < _autoScrollEdgeZone) {
      return distanceToTop - _autoScrollEdgeZone;
    }
    // 靠近下边缘：越出距离为正
    if (distanceToBottom < _autoScrollEdgeZone) {
      return _autoScrollEdgeZone - distanceToBottom;
    }
    return 0;
  }

  /// 按指针越出边缘的距离换算单帧滚动步长
  double _autoScrollStepForOvershoot(double overshoot) {
    // 越出距离每增加 1 像素步长增加 0.5 像素，并在上限处截断
    final double step = 2.0 + overshoot * 0.5;
    return step > _autoScrollMaxStep ? _autoScrollMaxStep : step;
  }

  /// 取滚动视口在屏幕坐标系中的矩形
  ///
  /// 滚动视口未挂载时返回 null，此时不进行边缘自动滚动
  Rect? _viewportGlobalRect() {
    final renderObject = _scrollViewKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    return MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & renderObject.size,
    );
  }

  @override
  String get text {
    final buffer = StringBuffer();
    final allNodes = _flattenAll();
    for (int i = 0; i < allNodes.length; i++) {
      if (i > 0) buffer.write('\n');
      final controller = _controllers[allNodes[i].id];
      buffer.write(controller?.text ?? allNodes[i].text);
    }
    return buffer.toString();
  }

  @override
  TextSelection get selection {
    // 优先取当前获得焦点的节点选区，否则回退到最近聚焦过的节点
    String? focusedId;
    TextSelection? localSelection;
    for (final entry in _focusNodes.entries) {
      if (entry.value.hasFocus) {
        focusedId = entry.key;
        final controller = _controllers[entry.key];
        if (controller != null) {
          localSelection = controller.selection;
        }
        break;
      }
    }
    focusedId ??= _lastFocusedNodeId;
    if (focusedId == null) return const TextSelection.collapsed(offset: 0);

    // 若焦点节点已有选区直接使用，否则从控制器或默认值获取
    localSelection ??= _controllers[focusedId]?.selection ?? const TextSelection.collapsed(offset: 0);

    // 将局部偏移量转换为全局偏移量
    final nodesWithOffsets = _flattenAllWithOffsets();
    final nodeEntry = nodesWithOffsets.firstWhere(
      (e) => e.node.id == focusedId,
      orElse: () => (node: _roots.first, startOffset: 0),
    );
    return TextSelection(
      baseOffset: nodeEntry.startOffset + localSelection.baseOffset,
      extentOffset: nodeEntry.startOffset + localSelection.extentOffset,
    );
  }

  @override
  set selection(TextSelection value) {
    final nodesWithOffsets = _flattenAllWithOffsets();
    final baseResolved = _resolveGlobalOffset(value.baseOffset, nodesWithOffsets);
    final extentResolved = _resolveGlobalOffset(value.extentOffset, nodesWithOffsets);

    if (baseResolved == null || extentResolved == null) return;
    if (baseResolved.nodeId != extentResolved.nodeId) return;

    // 目标节点可能处于折叠状态尚未构建，需先确保其控制器已创建
    final node = _findNode(baseResolved.nodeId);
    if (node == null) return;
    _ensureResources(node);

    final controller = _controllers[baseResolved.nodeId];
    if (controller == null) return;

    // 切换到新节点时，清除上一个节点的文字选区
    final previousNodeId = _lastFocusedNodeId;
    if (previousNodeId != null &&
        previousNodeId != baseResolved.nodeId &&
        _controllers.containsKey(previousNodeId)) {
      final prevController = _controllers[previousNodeId]!;
      if (!prevController.selection.isCollapsed) {
        final offset = prevController.selection.baseOffset
            .clamp(0, prevController.text.length);
        prevController.selection = TextSelection.collapsed(offset: offset);
      }
    }

    // 更新最近聚焦节点为目标节点，使后续 selection 读取和滚动定位到正确节点
    _lastFocusedNodeId = baseResolved.nodeId;

    controller.selection = TextSelection(
      baseOffset: baseResolved.localOffset,
      extentOffset: extentResolved.localOffset,
    );
  }

  @override
  void replaceRange(int start, int end, String replacement) {
    if (widget.readOnly) return;

    final nodesWithOffsets = _flattenAllWithOffsets();
    final startResolved = _resolveGlobalOffset(start, nodesWithOffsets);
    final endResolved = _resolveGlobalOffset(end, nodesWithOffsets);

    if (startResolved == null || endResolved == null) return;
    if (startResolved.nodeId != endResolved.nodeId) return;

    final node = _findNode(startResolved.nodeId);
    final controller = _controllers[startResolved.nodeId];
    if (node == null || controller == null) return;

    final localStart = startResolved.localOffset;
    final localEnd = endResolved.localOffset;
    final oldText = controller.text;
    if (localStart < 0 || localEnd > oldText.length || localStart > localEnd) return;

    final newText = oldText.substring(0, localStart) + replacement + oldText.substring(localEnd);

    // 通过批量操作合并为单条撤销记录，期间抑制控制器变化监听
    _undoManager.beginBatch();
    // 调整样式区间位置，保持样式与文字对应
    node.styleRanges = TextStyleRangeUtils.adjustForTextChange(
      node.styleRanges,
      oldText,
      newText,
    );
    if (controller is RichTextEditingController) {
      controller.styleRanges = node.styleRanges;
    }
    controller.text = newText;
    node.text = newText;
    _undoManager.endBatch(description: '替换');
  }

  @override
  void replaceAll(List<TextSelection> matches, String replacement) {
    if (matches.isEmpty || widget.readOnly) return;

    final nodesWithOffsets = _flattenAllWithOffsets();

    // 按节点分组匹配项
    final nodeMatches = <String, List<TextSelection>>{};
    for (final match in matches) {
      final resolved = _resolveGlobalOffset(match.start, nodesWithOffsets);
      if (resolved == null) continue;
      nodeMatches.putIfAbsent(resolved.nodeId, () => []).add(match);
    }

    _undoManager.beginBatch();

    // 逐节点替换（每个节点内从后往前替换，避免偏移量变化影响）
    for (final entry in nodeMatches.entries) {
      final node = _findNode(entry.key);
      final controller = _controllers[entry.key];
      if (node == null || controller == null) continue;

      final nodeStart = nodesWithOffsets
          .firstWhere((e) => e.node.id == entry.key, orElse: () => (node: node, startOffset: 0))
          .startOffset;

      final sortedMatches = entry.value.toList()
        ..sort((a, b) => b.start.compareTo(a.start));

      final oldText = controller.text;
      var newText = oldText;
      for (final match in sortedMatches) {
        final localStart = match.start - nodeStart;
        final localEnd = match.end - nodeStart;
        if (localStart < 0 || localEnd > newText.length || localStart > localEnd) continue;
        newText = newText.substring(0, localStart) + replacement + newText.substring(localEnd);
      }

      if (newText == oldText) continue;

      // 调整样式区间位置
      node.styleRanges = TextStyleRangeUtils.adjustForTextChange(
        node.styleRanges,
        oldText,
        newText,
      );
      if (controller is RichTextEditingController) {
        controller.styleRanges = node.styleRanges;
      }
      controller.text = newText;
      node.text = newText;
    }

    _undoManager.endBatch(description: '全部替换');
  }

  @override
  void scrollToSelection() {
    final sel = selection;
    final nodesWithOffsets = _flattenAllWithOffsets();
    final resolved = _resolveGlobalOffset(sel.extentOffset, nodesWithOffsets);
    if (resolved != null) {
      _scrollToNode(resolved.nodeId);
    }
  }

  @override
  void requestFocus() {
    final sel = selection;
    final nodesWithOffsets = _flattenAllWithOffsets();
    final resolved = _resolveGlobalOffset(sel.extentOffset, nodesWithOffsets);
    if (resolved != null) {
      _ensureAncestorsExpanded(resolved.nodeId);
      // 开启滚动保护，防止 TextField 获取焦点时触发自动滚动到光标位置
      _scrollGuard.protect(const Duration(milliseconds: 150));
      _focusNodes[resolved.nodeId]?.requestFocus();
    }
  }

  @override
  void notifyContentChanged() {
    _notifyContentChanged();
  }

  /// 将全局查找匹配同步到各节点控制器，解析为节点本地偏移量
  ///
  /// 全局匹配的偏移量基于所有节点文本以换行符拼接后的完整文本，
  /// 这里按节点分组解析为本地匹配，再设置到对应的 [RichTextEditingController] 上。
  void _syncFindHighlightsToControllers(List<TextSelection> matches, int currentIndex) {
    if (matches.isEmpty) {
      // 无匹配时清除所有控制器的查找高亮
      for (final controller in _controllers.values) {
        if (controller is RichTextEditingController) {
          controller.findMatches = const <TextSelection>[];
          controller.currentMatchIndex = -1;
        }
      }
      return;
    }

    // 扁平化整棵树并计算每个节点的全局起始偏移量
    final nodesWithOffsets = _flattenAllWithOffsets();

    // 按节点分组：将全局匹配解析为本地匹配
    final matchesByNode = <String, List<TextSelection>>{};
    String? currentNodeId;
    int currentLocalIndex = -1;

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final resolved = _resolveGlobalOffset(match.start, nodesWithOffsets);
      if (resolved == null) continue;

      final nodeId = resolved.nodeId;
      final nodeStart = resolved.nodeStart;
      final controller = _controllers[nodeId];
      if (controller == null) continue;

      final localStart = match.start - nodeStart;
      final localEnd = match.end - nodeStart;
      final nodeTextLength = controller.text.length;

      // 跳过超出当前节点文本范围的匹配（跨节点匹配不处理）
      if (localStart < 0 || localEnd > nodeTextLength) continue;

      final localMatch = TextSelection(baseOffset: localStart, extentOffset: localEnd);
      matchesByNode.putIfAbsent(nodeId, () => <TextSelection>[]).add(localMatch);

      // 记录当前选中匹配所属的节点及其本地索引
      if (i == currentIndex) {
        currentNodeId = nodeId;
        currentLocalIndex = matchesByNode[nodeId]!.length - 1;
      }
    }

    // 将匹配应用到每个控制器
    for (final entry in _controllers.entries) {
      final controller = entry.value;
      if (controller is RichTextEditingController) {
        final nodeMatches = matchesByNode[entry.key] ?? const <TextSelection>[];
        controller.findMatches = nodeMatches;
        controller.currentMatchIndex = entry.key == currentNodeId ? currentLocalIndex : -1;
      }
    }
  }

  // ================= 渲染 =================

  /// 切换快捷键列表面板的显示状态
  void _toggleShortcutPanel() {
    setState(() {
      _isShortcutPanelVisible = !_isShortcutPanelVisible;
    });
  }

  /// 在大纲编辑器顶部工具栏的齿轮按钮下方弹出布局设置卡片
  ///
  /// 卡片打开期间齿轮入口保持高亮，关闭后恢复
  Future<void> _showSettingsCard() async {
    final buttonBox = _settingsButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) return;

    // 齿轮按钮矩形，用于确定卡片的上边缘
    final Rect anchorRect = buttonBox.localToGlobal(Offset.zero) & buttonBox.size;
    // 编辑器区域左边缘的屏幕横坐标，卡片与其保持固定间距
    final editorBox = context.findRenderObject() as RenderBox?;
    final double editorLeft = editorBox?.localToGlobal(Offset.zero).dx ?? anchorRect.left;

    setState(() => _isSettingsCardVisible = true);
    await OutlineEditorSettingsCard.show(
      context: context,
      anchorRect: anchorRect,
      editorLeft: editorLeft,
    );
    if (!mounted) return;
    setState(() => _isSettingsCardVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    // 编辑器内容不随应用界面字号缩放，保留编辑器自身的字体大小设置
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: _buildEditorBody(context),
    );
  }

  /// 取上下边距换算所依据的编辑区高度
  ///
  /// 键盘收起时以当前可用高度更新基准，键盘弹出期间沿用上一次记录的基准，
  /// 使上下边距不随键盘动画变化，节点内容在键盘升降过程中保持原位。
  double _resolveMarginBasisHeight(double availableHeight) {
    // 高度取自窗口视图的原始内边距：需要区分键盘升降，与应用内边距无关
    if (View.of(context).viewInsets.bottom <= 0) {
      _marginBasisHeight = availableHeight;
    }
    return _marginBasisHeight > 0 ? _marginBasisHeight : availableHeight;
  }

  /// 构建编辑器主体内容
  Widget _buildEditorBody(BuildContext context) {
    final colorScheme = widget.colorScheme;

    // 检测窗口从最小化恢复的情况，开启滚动保护防止 TextField 自动滚动到光标位置
    // 仅监听最小化状态，窗口其他状态变化时不重建大纲编辑器
    final bool isMinimized = context.select<WindowProvider, bool>((p) => p.isMinimized);
    if (_wasMinimized && !isMinimized) {
      _scrollGuard.protect(const Duration(milliseconds: 150));
    }
    _wasMinimized = isMinimized;

    // 监听查找匹配状态变化，仅在匹配项或当前索引变化时重建
    // 使用哈希摘要避免在字数更新等无关通知时重建整个大纲
    context.select<WorkspaceProvider, int>((p) {
      final matches = p.findMatches;
      int hash = p.currentMatchIndex ^ matches.length;
      for (final m in matches) {
        hash = Object.hash(hash, m.baseOffset, m.extentOffset);
      }
      return hash;
    });

    // 将查找匹配高亮同步到各节点控制器
    final workspaceProvider = context.read<WorkspaceProvider>();
    _syncFindHighlightsToControllers(
      workspaceProvider.findMatches,
      workspaceProvider.currentMatchIndex,
    );

    // 异步加载文件内容时显示加载状态
    if (_isLoading) {
      return Container(
        color: colorScheme.surface,
        child: Center(child: CircularProgressIndicator(color: colorScheme.primary)),
      );
    }

    final flatList = _flatten();

    // 编辑区底色：默认跟随主题，自定义时使用配置的颜色；纸张模式下纸张外背景由淡化设置决定
    final bool isPaperMode = SettingsService.instance.outlinePageViewMode == 'paper';
    final Color editorBackgroundColor = ColorUtils.getEditorBackgroundColorForTheme(context);
    final Color editorAreaColor = isPaperMode
        ? ColorUtils.getPaperOutsideBackgroundColor(context)
        : editorBackgroundColor;

    // 是否启用编辑器级选区和拖拽手势
    // 桌面端支持从文本内拖拽选择文字、从空白或连接线区域拖拽框选多个节点；
    // 移动端禁用，避免手指滑动屏幕滚动时误触发节点选区，
    // 选区仅交由各节点输入框自身的原生选区逻辑处理
    final bool enableEditorSelection = !PlatformCapabilities.isMobile;

    return Container(
      color: editorAreaColor,
      child: Column(
        children: [
          // 顶部工具栏
          OutlineEditorTopBar(
            colorScheme: colorScheme,
            backgroundColor: editorAreaColor,
            readOnly: widget.readOnly,
            onExpandAll: _expandAll,
            onCollapseAll: _collapseAll,
            onAddRoot: _addRootNode,
            isShortcutPanelVisible: _isShortcutPanelVisible,
            onToggleShortcutPanel: _toggleShortcutPanel,
            isBatchMode: _isBatchSelectionMode,
            isAllNodesSelected: isAllNodesSelected,
            isPartialNodesSelected: isPartialNodesSelected,
            onEnterBatchMode: enterBatchSelectionMode,
            onExitBatchMode: exitBatchSelectionMode,
            onToggleSelectAll: toggleSelectAllNodes,
            settingsButtonKey: _settingsButtonKey,
            isSettingsCardVisible: _isSettingsCardVisible,
            onOpenSettings: _showSettingsCard,
          ),
          // 大纲列表
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 主内容区域：可滚动的大纲列表
                Focus(
                        focusNode: _editorFocusNode,
                        onKeyEvent: _onEditorKeyEvent,
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          // 移动端不安装编辑器级指针处理，避免清除选区、抢占焦点等干扰输入框自身选区
                          onPointerDown: enableEditorSelection ? _onPointerDown : null,
                          onPointerUp: enableEditorSelection
                              ? _onPointerUp
                              // 批量选择模式下抬起指针结束竖条滑选
                              : (_isBatchSelectionMode ? _onBatchPointerUp : null),
                          // 批量选择模式下按住竖条滑动时按指针位置更新选区，
                          // 指针越出视口上下边缘时持续滚动视口
                          onPointerMove: _isBatchSelectionMode ? _onBatchPointerMove : null,
                          onPointerCancel: _isBatchSelectionMode ? _onBatchPointerUp : null,
                          child: RawGestureDetector(
                            behavior: HitTestBehavior.translucent,
                            // 移动端不注册自定义拖拽识别器，让垂直拖动交由滚动容器处理，
                            // 保证手指滑动屏幕可正常滚动而非触发节点选区
                            gestures: enableEditorSelection
                                ? {
                                    _EagerPanGestureRecognizer:
                                        GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
                                          () => _EagerPanGestureRecognizer(),
                                          (instance) {
                                            instance.onStart = _onPanStart;
                                            instance.onUpdate = _onPanUpdate;
                                            instance.onEnd = _onPanEnd;
                                            instance.onCancel = _onPanCancel;
                                            instance.shouldDeferToScrollbar = _isPositionOnScrollbar;
                                          },
                                        ),
                                  }
                                : const <Type, GestureRecognizerFactory>{},
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final settings = SettingsService.instance;

                                final scrollContent = ScrollConfiguration(
                                  behavior: CleanEditorScrollBehavior(),
                                  child: _buildEditorScrollView(
                                    constraints: constraints,
                                    pageViewMode: settings.outlinePageViewMode,
                                    colorScheme: colorScheme,
                                    paperColor: editorBackgroundColor,
                                    flatList: flatList,
                                  ),
                                );

                                // 移动端隐藏滚动条，避免遮挡窄屏下的编辑内容；桌面端保持原有滚动条表现
                                if (PlatformCapabilities.isMobile) {
                                  return scrollContent;
                                }

                                return Scrollbar(
                                  key: _scrollbarKey,
                                  controller: _scrollController,
                                  thumbVisibility: settings.scrollbarAlwaysVisible ? true : null,
                                  thickness: editorScrollbarThickness,
                                  radius: Radius.circular(editorScrollbarThickness / 2),
                                  child: scrollContent,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                // 底部快捷键提示：仅桌面端显示
                // 移动端没有物理键盘，隐藏提示，底部预留高度保持为 0
                if (!PlatformCapabilities.isMobile)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      child: MeasureSize(
                        onSizeChanged: (size) {
                          if (mounted && size.height != _bottomHintHeight) {
                            setState(() => _bottomHintHeight = size.height);
                          }
                        },
                        child: OutlineEditorBottomHint(colorScheme: colorScheme),
                      ),
                    ),
                  ),
                // 快捷键列表面板：浮动在编辑器右侧，覆盖滚动条，不受内容滚动影响
                if (_isShortcutPanelVisible)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: OutlineShortcutPanel(
                      colorScheme: colorScheme,
                      onClose: _toggleShortcutPanel,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建编辑器的懒加载滚动视图
  ///
  /// 三种模式：
  /// - 'adaptive' 自适应：不约束宽度，不居中，节点区域自适应容器宽度
  /// - 'default' 默认：限制 A4 宽度并居中，不显示纸张样式
  /// - 'paper' 纸张：在默认基础上显示 A4 纸张背景与投影效果，内容不足时纸张铺满视口
  ///
  /// 节点列表使用 [SliverList] 懒加载，只构建视口及其预取范围内的节点瓦片，
  /// 避免节点数量较多时一次性构建全部节点带来的移动端卡顿。
  /// 水平边距在纸张模式下相对于 A4 宽度计算（作为纸张内边距），其他模式相对于编辑器宽度计算；
  /// 桌面端作为滚动容器内边距，移动端则由节点行内容承担，使行尾竖条始终贴到编辑区右边缘
  Widget _buildEditorScrollView({
    required BoxConstraints constraints,
    required String pageViewMode,
    required ColorScheme colorScheme,
    required Color paperColor,
    required List<FlatNode> flatList,
  }) {
    final settings = SettingsService.instance;
    final bool isPaperMode = pageViewMode == 'paper';
    final double horizontalBase =
        isPaperMode ? GlobalConstants.a4Width : constraints.maxWidth;
    final double horizontalPadding =
        horizontalBase * (settings.outlineHorizontalMargin / 100);
    // 顶边距和底边距（百分比，相对于编辑器高度）
    // 换算基准在键盘升降期间保持不变，避免节点内容随键盘上下移动
    final double marginBasisHeight = _resolveMarginBasisHeight(constraints.maxHeight);
    final double topPadding = marginBasisHeight * (settings.outlineTopMargin / 100);
    final double bottomPadding = marginBasisHeight * (settings.outlineBottomMargin / 100);
    // 记录底边距，供聚焦、定位节点时作为底部安全间距使用
    _bottomContentPadding = bottomPadding;

    // 内容按 A4 宽度居中的额外内缩量；宽度不足以容纳 A4 时取 0；
    // 纸张模式与移动端在整个视口宽度内居中，桌面端非纸张模式先施加左右边距再居中
    final double viewportCenterRaw = (constraints.maxWidth - GlobalConstants.a4Width) / 2;
    final double viewportCenterInset = viewportCenterRaw > 0 ? viewportCenterRaw : 0.0;
    final double paddedCenterRaw =
        (constraints.maxWidth - 2 * horizontalPadding - GlobalConstants.a4Width) / 2;
    final double paddedCenterInset = paddedCenterRaw > 0 ? paddedCenterRaw : 0.0;

    // 构建节点列表，每个节点都用右键菜单包装；
    // 移动端长按交还系统原生选择行为，不注册长按识别器
    final Widget nodeList = SliverList.builder(
      itemCount: flatList.length,
      itemBuilder: (context, index) => ContextMenu(
        getMenuItems: _buildContextMenuItems,
        onSecondaryTapDown: _handleSecondaryTapDown,
        onDismissed: _handleContextMenuDismissed,
        enableMobileLongPress: !PlatformCapabilities.isMobile,
        child: _buildNodeTile(flatList[index], horizontalMargin: horizontalPadding),
      ),
    );

    final List<Widget> slivers;
    if (isPaperMode) {
      // 纸张模式：纸张按 A4 宽度居中，水平/上下边距作为纸张内边距；
      // 滚动容器只保留查找替换浮窗的顶边距、纸张顶边距（防止顶部阴影被遮挡）与底部快捷键提示高度；
      // 内容不足 A4 高度时在其后补足空白，使纸张始终保持 A4 尺寸
      slivers = [
        SliverPadding(
          padding: EdgeInsets.only(
            top: widget.extraTopPadding + 10.0,
            bottom: _bottomHintHeight,
          ),
          sliver: SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: viewportCenterInset),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: paperColor,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              sliver: SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  topPadding,
                  horizontalPadding,
                  bottomPadding,
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    nodeList,
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    } else {
      // 自适应模式不限制宽度、不居中，不施加居中内缩量
      final bool isMobile = PlatformCapabilities.isMobile;
      final double centerInset = pageViewMode == 'adaptive'
          ? 0.0
          : (isMobile ? viewportCenterInset : paddedCenterInset);
      // 移动端不在滚动容器上施加左右内边距，左右边距改由节点行内容承担，
      // 使行尾竖条始终贴到编辑区右边缘
      final EdgeInsets scrollPadding = isMobile
          ? EdgeInsets.only(
              left: centerInset,
              right: centerInset,
              top: topPadding + widget.extraTopPadding,
              bottom: bottomPadding + _bottomHintHeight,
            )
          : EdgeInsets.only(
              left: horizontalPadding + centerInset,
              right: horizontalPadding + centerInset,
              top: topPadding + widget.extraTopPadding,
              bottom: bottomPadding + _bottomHintHeight,
            );
      slivers = [
        SliverPadding(padding: scrollPadding, sliver: nodeList),
      ];
    }

    return CustomScrollView(
      key: _scrollViewKey,
      controller: _scrollController,
      slivers: slivers,
    );
  }

  /// 构建单个节点行
  ///
  /// [horizontalMargin] 为左右边距（像素），仅移动端使用：
  /// 桌面端由滚动容器内边距统一施加，移动端则由节点行内容承担
  Widget _buildNodeTile(FlatNode flatNode, {required double horizontalMargin}) {
    // 获取或创建节点瓦片的全局键，用于拖拽选区的命中检测
    final key = _nodeTileKeys.putIfAbsent(flatNode.node.id, () => GlobalKey());

    return OutlineNodeTile(
      key: key,
      node: flatNode.node,
      depth: flatNode.depth,
      controller: _controllers[flatNode.node.id]!,
      focusNode: _focusNodes[flatNode.node.id]!,
      colorScheme: widget.colorScheme,
      editorBackgroundColor: ColorUtils.getEditorBackgroundColorForTheme(context),
      indentWidth: _indentWidth,
      dotTextGapReduction: _dotTextGapReduction,
      nodeSpacing: SettingsService.instance.outlineNodeSpacing,
      horizontalMargin: horizontalMargin,
      isSelected: _selectedNodeIds.contains(flatNode.node.id),
      isBatchMode: _isBatchSelectionMode,
      readOnly: widget.readOnly,
      onToggleExpand: () => _toggleExpand(flatNode.node.id),
      onBatchTap: () => toggleNodeSubtreeSelection(flatNode.node.id),
      onTrailingBarLongPress: _onTrailingBarLongPress,
      onTrailingBarLongPressMove: _onTrailingBarLongPressMove,
      onTrailingBarDragStart: () {
        _batchSelectionController.onCheckboxDragStart(flatNode.node.id);
        // 按住竖条拖动滑选时同样支持视口边缘自动滚动
        _autoScrollSelectionUpdater = _batchSelectionController.onPointerMoveTo;
      },
      onTrailingBarDragEnd: _batchSelectionController.onPointerUp,
      onChanged: (newText) {
        final oldText = flatNode.node.text;
        if (oldText != newText) {
          // 文本变化时调整样式区间位置，保持样式与文字对应
          flatNode.node.styleRanges = TextStyleRangeUtils.adjustForTextChange(
            flatNode.node.styleRanges,
            oldText,
            newText,
          );
          // 同步到控制器以触发富文本重建
          final controller = _controllers[flatNode.node.id];
          if (controller is RichTextEditingController) {
            controller.styleRanges = flatNode.node.styleRanges;
          }
        }
        flatNode.node.text = newText;
        _notifyContentChanged();
      },
      shouldPersistSelectionOnFocusLoss: (nodeId) => _isContextMenuOpening && nodeId == _contextMenuNodeId,
    );
  }
}

/// 拖拽选区模式：无、文本选区、节点选区
enum _DragMode { none, text, node }

/// 自定义平移手势识别器，以极小的移动阈值接受手势
///
/// 确保在输入框内部开始拖拽时，能优先于输入框自带的手势识别器赢得竞技场。
/// 当指针落在滚动条区域时则不参与竞技场，把交互让给滚动条。
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  /// 判断指针是否应交由滚动条处理
  ///
  /// 返回 true 时本识别器不进入该指针的竞技场，由滚动条赢得拖拽与点击。
  bool Function(Offset globalPosition)? shouldDeferToScrollbar;

  @override
  bool isPointerAllowed(PointerEvent event) {
    // 指针位于滚动条区域时不参与竞技场
    if (shouldDeferToScrollbar?.call(event.position) ?? false) {
      return false;
    }
    return super.isPointerAllowed(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    // 使用极小阈值，确保在任何拖拽场景下都能优先接受
    return globalDistanceMoved.abs() > 0.1;
  }
}
