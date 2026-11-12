import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/cache_services/outline_last_edit_cache_service.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';
import 'package:quick_write/core/services/workspace/outline_companion_store.dart';
import 'package:quick_write/core/services/workspace/outline_keyword_service.dart';
import 'package:quick_write/core/services/workspace/outline_link_service.dart';
import 'package:quick_write/core/services/workspace/outline_note_service.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/utils/batch_selection_controller.dart';
import 'package:quick_write/core/utils/clean_scroll.dart';
import 'package:quick_write/core/utils/clipboard_state_cache.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/editor_scroll_helper.dart';
import 'package:quick_write/core/utils/find_replace_target.dart';
import 'package:quick_write/core/utils/outline_html_codec.dart';
import 'package:quick_write/core/utils/outline_markdown_codec.dart';
import 'package:quick_write/core/utils/outline_undo_manager.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/rich_clipboard.dart';
import 'package:quick_write/core/utils/rich_text_controller.dart';
import 'package:quick_write/core/utils/text_style_range.dart';
import 'package:quick_write/core/utils/text_similarity.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/models/outline_link.dart';
import 'package:quick_write/core/models/outline_note.dart';
import 'package:quick_write/core/models/outline_table.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'utils/drag_cursor.dart';
import 'utils/outline_shortcut_keys.dart';
import 'widgets/outline_color_palette.dart';
import 'widgets/outline_connection_painter.dart';
import 'widgets/outline_keyword_card.dart';
import 'widgets/outline_link_dialog.dart';
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

  /// 所属书籍 UUID（与 [settingItemUuid] 一起用于读写上次编辑节点缓存）
  final String? bookUuid;

  /// 设定项 UUID（与 [bookUuid] 一起用于读写上次编辑节点缓存）
  final String? settingItemUuid;

  /// 大纲标题
  ///
  /// 显示在第一个节点上方，不属于节点，不参与节点格式与样式的设置。
  final String title;

  /// 大纲标题修改回调
  ///
  /// 标题内容随标签页标题更新，保存时由外部同步重命名大纲文件。
  final ValueChanged<String>? onTitleChanged;

  /// 内容变化回调（用于触发自动保存和备份）
  final VoidCallback? onContentChanged;

  /// 保存回调（Ctrl/Cmd+S 触发）
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

  /// 内容加载完成后是否自动聚焦第一个节点
  ///
  /// 新建设定文件时为 true，使光标直接落在首个节点上便于立即输入。
  final bool autoFocusFirstNode;

  /// 内容加载完成后是否优先定位到上一次编辑的节点
  ///
  /// 会话恢复的标签页为 true，使其回到关闭前的编辑位置，
  /// 不受「打开文件时」设置影响。
  final bool restoreLastEditPosition;

  /// 是否为当前激活的标签页
  ///
  /// 恢复定位后只在激活的标签页上获取焦点，避免会话恢复时后台标签页抢走当前标签页的键盘焦点。
  final bool isActive;

  /// 大纲关键词服务
  ///
  /// 用于读写当前设定项的关键词伴生文件，并同步书籍级关键词索引；
  /// 为空时不启用关键词功能（如未提供工作台的场景）。
  final OutlineKeywordService? keywordService;

  const OutlineEditor({
    super.key,
    required this.colorScheme,
    this.filePath,
    this.bookUuid,
    this.settingItemUuid,
    this.title = '',
    this.onTitleChanged,
    this.onContentChanged,
    this.onSave,
    this.readOnly = false,
    this.onStatsChanged,
    this.extraTopPadding = 0.0,
    this.onContentLoaded,
    this.autoFocusFirstNode = false,
    this.restoreLastEditPosition = false,
    this.isActive = true,
    this.keywordService,
  });

  @override
  State<OutlineEditor> createState() => OutlineEditorState();
}

class OutlineEditorState extends State<OutlineEditor>
    with WidgetsBindingObserver, TickerProviderStateMixin
    implements FindReplaceTarget {
  // ================= 常量 =================

  /// 每级缩进的像素宽度
  static const double _indentWidth = 24.0;

  /// 最大节点深度（避免节点层级过深导致显示溢出）
  static const int _maxDepth = 20;

  /// 圆点与文本间距缩减量
  static const double _dotTextGapReduction = 5.0;

  /// 从空白区域拖拽唤起节点选区的最小上下移动距离（像素）
  ///
  /// 指针从按下位置上下移动超过该距离后才生成节点选区，
  /// 避免鼠标轻微移动或纯水平移动就意外拉出节点选区
  static const double _nodeSelectionDragThreshold = 20.0;

  /// 加载指示的显示延迟
  ///
  /// 本地文件通常几十毫秒内解析完成，立即显示加载指示会造成闪烁；
  /// 超过该时长仍未完成时才显示，慢速读取时用户仍能得到反馈。
  static const Duration _loadingIndicatorDelay = Duration(milliseconds: 300);

  // ================= 树结构数据 =================

  /// 根节点列表
  final List<OutlineNode> _roots = [];

  /// 当前进入的主题节点 ID
  ///
  /// 为 null 时编辑区显示全部根节点；非空时只显示该节点的子节点，
  /// 该节点本身不在列表中展示，由顶部面包屑标识当前所在层级。
  String? _focusNodeId;

  /// 节点ID计数器（用于生成唯一ID）
  int _idCounter = 0;

  // ================= 控制器与焦点节点 =================

  /// 节点ID到文本控制器的映射
  final Map<String, TextEditingController> _controllers = {};

  /// 节点ID到焦点节点的映射
  final Map<String, FocusNode> _focusNodes = {};

  /// 节点瓦片的全局键映射（节点ID -> GlobalKey），用于命中检测
  final Map<String, GlobalKey> _nodeTileKeys = {};

  /// 大纲标题输入控制器
  late final TextEditingController _titleController;

  /// 大纲标题输入框焦点
  final FocusNode _titleFocusNode = FocusNode();

  /// 大纲标题区域的全局键，用于标题区域的命中检测
  final GlobalKey _titleFieldKey = GlobalKey();

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

  /// 表格编辑的撤销记录定时器
  ///
  /// 单元格输入与表格结构调整会不断重置计时，停止操作后统一提交为一条撤销记录。
  Timer? _tableUndoTimer;

  /// 表格编辑合并为一条撤销记录的时间窗口
  static const Duration _tableUndoWindow = Duration(milliseconds: 800);

  /// 编辑器滚动保护器
  ///
  /// 在窗口恢复、标签页切换等场景下锁定滚动位置，防止 TextField 获取焦点时
  /// 触发 Scrollable.ensureVisible 自动滚动到光标位置导致视口跳动
  late final EditorScrollGuard _scrollGuard;

  /// 缓存窗口最小化状态，用于检测从最小化恢复的情况
  bool _wasMinimized = false;

  /// 待补偿的额外顶边距变化量
  double? _pendingExtraPaddingDelta;

  /// 待在本帧布局阶段补足底部安全间距的节点 ID
  ///
  /// 插入新节点后记录该节点，布局完成时在绘制之前修正滚动偏移，
  /// 避免节点先渲染在视口底部、随后才被滚动上移造成的闪烁。
  String? _pendingRevealNodeId;

  /// 上下边距换算所依据的编辑区高度
  ///
  /// 上下边距按编辑区高度的百分比换算，而软键盘升降会压缩编辑区高度；
  /// 若直接采用实时高度，键盘动画期间节点内容会随之上下移动。
  /// 此处记录键盘收起时的编辑区高度作为基准，键盘弹出期间沿用该基准。
  double _marginBasisHeight = 0;

  /// 上一次记录的软键盘高度
  ///
  /// 用于识别键盘由弹出变为收起的时刻，据此释放输入框焦点
  double _lastKeyboardInset = 0;

  /// 底部内容边距（像素）
  ///
  /// 由用户设置的底边距按编辑区高度百分比换算而来，随布局一并更新。
  /// 节点定位时以该值作为节点底部与视口底部之间应保留的安全间距。
  double _bottomContentPadding = 0;

  /// 底部快捷键提示的预留高度（像素）
  ///
  /// 位于底边距之下，随内容一起参与滚动，定位列表末尾节点时需从可滚动范围中扣除。
  double _bottomHintReserved = 0;

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

  /// Ctrl/Cmd+A 全选状态：0=未全选，1=已全选主题，2=已全选文档
  int _selectAllLevel = 0;

  /// 选区锚点索引（Shift+click 扩展选区时的起始点）
  int? _selectionAnchorIndex;

  /// 最近获得焦点的节点ID（用于取消选区后恢复焦点）
  String? _lastFocusedNodeId;

  /// 上下箭头垂直移动光标时记录的目标横向坐标
  ///
  /// 该坐标相对节点文本内容左边缘，连续垂直移动时沿用同一值，
  /// 避免经过较短的可视行或切换节点后光标列发生漂移；
  /// 用其他按键或用鼠标、手指重新定位光标时清除。
  double? _preferredCaretX;

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

  /// 本次指针序列中编辑器级拖拽手势是否已赢得竞技场
  ///
  /// 用于在拖拽手势抢占了节点输入框的点击时，按点击位置补上光标定位
  bool _panGestureAccepted = false;

  /// 文本选区锚点（拖拽起始处在文本中的位置）
  TextPosition? _dragTextAnchor;

  /// 拖拽起始节点ID
  String? _dragStartNodeId;

  // ================= 圆点拖拽排序 =================

  /// 正在拖拽排序的节点ID（null 表示没有拖拽排序进行中）
  String? _reorderNodeId;

  /// 拖拽排序的落点（null 表示当前没有可放置的落点）
  _OutlineReorderTarget? _reorderTarget;

  /// 拖拽排序时指针的全局坐标（null 表示没有拖拽排序进行中）
  ///
  /// 供跟随鼠标的圆点使用；单独以可监听值维护，避免指针每移动一次就重建整个编辑器
  final ValueNotifier<Offset?> _reorderPointerPosition = ValueNotifier<Offset?>(null);

  /// 编辑区内容层叠区域的全局键，用于把拖拽指示线的全局坐标换算为本地坐标
  final GlobalKey _editorStackKey = GlobalKey();

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

  /// 内容是否已从文件载入完成
  ///
  /// 载入完成前禁用添加节点与标题编辑，避免输入被随后解析的内容覆盖
  bool _isContentReady = true;

  /// 内容读取失败时的错误说明（null 表示未失败）
  String? _loadErrorMessage;

  /// 加载指示是否可见（载入超过 [_loadingIndicatorDelay] 仍未完成时置位）
  bool _showLoadingIndicator = false;

  /// 加载指示的延时定时器
  Timer? _loadingIndicatorTimer;

  /// 内容首次呈现在界面前是否暂缓绘制节点列表
  ///
  /// 打开文件时需按设置定位到上次编辑节点或文末，懒加载列表的定位要跨多帧完成；
  /// 若先绘制列表，会先闪出文档头部再跳到目标位置。置位期间列表照常布局
  /// （定位依赖布局结果）但不绘制，定位完成后一次性呈现最终位置的内容。
  bool _deferContentPaint = false;

  /// 当前内容是否可安全保存（载入完成且读取成功）
  ///
  /// 供保存流程判断：载入中或读取失败时禁止保存，避免空内容覆盖原文件
  bool get canSave => _isContentReady && _loadErrorMessage == null;

  /// 折叠状态写入任务链
  ///
  /// 因内容与结构变化都会刷新折叠状态，多次保存按此链顺序执行，避免并发写同一文件
  Future<void> _foldStateWriteChain = Future.value();

  /// 上一次编辑节点的路径（自根节点起的层级索引路径）
  ///
  /// 节点 ID 每次解析文件都会重新生成，跨次加载无法对应到同一节点，
  /// 因此与折叠状态一样改用「自根节点起的层级索引路径」标识节点。
  String? _lastEditedPath;

  /// 上一次编辑节点路径的写入防抖定时器
  ///
  /// 连续点击节点会频繁切换焦点，合并短时间内的多次记录，避免反复写文件
  Timer? _lastEditedPathSaveTimer;

  /// 大纲关联服务（读写关联伴生文件）
  final OutlineLinkService _linkService = OutlineLinkService();

  /// 关联标识到关联目标的映射
  ///
  /// 关联标识同时记录在文本样式区间中，此处保存标识对应的跳转目标信息。
  final Map<String, OutlineLinkTarget> _links = {};

  /// 大纲备注服务（读写备注伴生文件与附加图片）
  final OutlineNoteService _noteService = OutlineNoteService();

  /// 待清理的图片文件名
  ///
  /// 替换或删除节点图片时先行记录，待伴生数据随设定文件落盘后再删除文件，
  /// 避免用户未保存就离开时图片已被删除、伴生文件仍指向它。
  final Set<String> _discardedImageFileNames = {};

  /// 本次编辑中新插入的图片文件名
  ///
  /// 保存时若已不再被任何节点引用，则一并删除，避免取消编辑后残留文件。
  final Set<String> _importedImageFileNames = {};

  /// 正在编辑备注的节点 ID（null 表示没有节点处于备注编辑状态）
  String? _noteEditingNodeId;

  /// 节点附加备注区的全局键（节点 ID → 键）
  ///
  /// 备注区内部包含输入框与图片，编辑器据此判断指针是否落在该区域，
  /// 从而把手势交给备注输入框自身处理。
  final Map<String, GlobalKey> _attachmentKeys = {};

  /// 节点附加表格的全局键（节点 ID → 键）
  ///
  /// 编辑器据此判断指针是否落在表格内，把单元格右键菜单交给表格自身处理。
  final Map<String, GlobalKey> _tableKeys = {};

  /// 节点折叠动画控制器（节点ID -> 控制器）
  ///
  /// 值从 1 收敛到 0 表示子节点收进圆点，从 0 增长到 1 表示子节点从圆点展开；
  /// 动画结束后移除对应控制器，节点重新按展开状态直接渲染
  final Map<String, AnimationController> _foldAnimations = {};

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
    _scrollController = SyncScrollController(
      onApplyContentDimensions: _onApplyContentDimensions,
      onCorrectScrollOffset: _onCorrectScrollOffset,
    );
    _scrollGuard = EditorScrollGuard(_scrollController);
    // 标题初始内容取自外部传入的大纲标题
    _titleController = TextEditingController(text: widget.title);

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
    _loadingIndicatorTimer?.cancel();
    _lastEditedPathSaveTimer?.cancel();
    _tableUndoTimer?.cancel();
    // 关闭时未保存的新插入图片不再有落盘机会，直接清理避免残留文件
    _cleanupUnsavedImages();
    _scrollGuard.dispose();
    SettingsService.instance.removeListener(_onSettingsChanged);
    _undoManager.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    for (final controller in _foldAnimations.values) {
      controller.dispose();
    }
    _foldAnimations.clear();
    _editorFocusNode.dispose();
    _titleController.dispose();
    _titleFocusNode.dispose();
    _scrollController.dispose();
    _batchRevision.dispose();
    _reorderPointerPosition.dispose();
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
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 仅移动端需要处理软键盘收起
    if (!PlatformCapabilities.isMobile) return;
    // 度量变化当帧布局尚未完成，键盘高度需等布局结束后读取
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final double keyboardInset = View.of(context).viewInsets.bottom;
      final double previousInset = _lastKeyboardInset;
      _lastKeyboardInset = keyboardInset;
      // 键盘由弹出变为收起：释放输入框焦点。
      // 键盘收起后若输入框仍持有焦点，打开再关闭抽屉或卡片时焦点会被恢复，
      // 键盘随之重新弹出；释放焦点后只有用户点击输入框才会再次唤起键盘
      if (previousInset > 0 && keyboardInset <= 0) {
        _releaseTextInputFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant OutlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部重命名后同步标题输入框内容，避免输入框与文件标题不一致；
    // 标题输入框正在输入时不覆盖，防止光标位置被打断
    if (widget.title != oldWidget.title &&
        _titleController.text != widget.title &&
        !_titleFocusNode.hasFocus) {
      _titleController.text = widget.title;
    }
    // 大纲文件改名或移动后迁移伴生数据与图片
    if (widget.filePath != oldWidget.filePath && !widget.readOnly) {
      // 折叠状态为本地专用文件，随大纲文件迁移
      _renameFoldStateFile(oldWidget.filePath, widget.filePath);
      // 关键词、关联与备注统一存放，一并迁移到新路径
      OutlineCompanionStore.instance.move(oldWidget.filePath, widget.filePath);
      // 节点附加图片随设定项所在目录一并迁移
      _noteService.moveImages(
        oldSettingItemFilePath: oldWidget.filePath,
        newSettingItemFilePath: widget.filePath,
        imageFileNames: _flattenAll().map((node) => node.imageFileName).toList(),
      );
    }
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

  /// 在 Layout 阶段为插入到列表末尾的新节点补足底部安全间距
  ///
  /// 内容尺寸变化时由 [SyncScrollPosition.correctForNewDimensions] 调用，
  /// 此时可滚动范围已包含新节点，可在绘制之前把滚动偏移修正到位；
  /// 返回 true 时 Viewport 会在本帧内重新布局，节点不会先渲染再被移上去。
  bool _onCorrectScrollOffset(ScrollPosition position) {
    final nodeId = _pendingRevealNodeId;
    if (nodeId == null) return false;
    _pendingRevealNodeId = null;

    // 仅处理列表末尾的节点：其底边到滚动内容底边只隔着底部预留，
    // 因此可由可滚动范围直接推出节点底边的位置，无需在布局阶段读取节点尺寸
    final flatList = _flatten();
    if (flatList.isEmpty || flatList.last.node.id != nodeId) return false;

    // 节点底边对齐视口底部安全线所需的最小滚动偏移
    final targetOffset = (position.maxScrollExtent - _bottomHintReserved).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (position.pixels >= targetOffset - 0.5) return false;

    position.correctPixels(targetOffset);
    // 同步更新滚动保护的目标偏移量，避免保护器把滚动位置拉回修正前的值
    _scrollGuard.retarget();
    return true;
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
  ///
  /// [styleRanges] 用于携带文本片段原有的样式区间，例如分割节点时
  /// 把前半段的样式一并交给新节点。
  OutlineNode _createNode(String text, {List<TextStyleRange>? styleRanges}) {
    return OutlineNode(id: _generateId(), text: text, styleRanges: styleRanges);
  }

  /// 当前进入的主题节点（未进入主题时为 null）
  OutlineNode? get _focusNode {
    final nodeId = _focusNodeId;
    return nodeId == null ? null : _findNode(nodeId);
  }

  /// 编辑区当前展示的顶级节点列表
  ///
  /// 主题模式下为当前主题的子节点，否则为大纲的全部根节点。
  List<OutlineNode> get _visibleRoots => _focusNode?.children ?? _roots;

  /// 当前主题从根到自身的节点路径（未进入主题时为空）
  List<OutlineNode> get _focusPath {
    final node = _focusNode;
    if (node == null) return const [];
    return [..._findAncestors(node.id), node];
  }

  /// 节点是否为当前主题视图的顶层节点
  ///
  /// 主题模式下当前主题的子节点构成视图的根级节点，
  /// 反缩进会把它们移出当前主题，因此需要限制该操作。
  bool _isTopicTopLevelNode(String nodeId) {
    final focus = _focusNode;
    if (focus == null) return false;
    return _findLocation(nodeId)?.parent?.id == focus.id;
  }

  /// 顶部面包屑展示的主题名称列表（不含固定在最前面的“全部”）
  List<String> get _breadcrumbTitles => _focusPath.map(_nodeDisplayText).toList();

  /// 节点的展示文本，优先取输入框中的实时内容
  String _nodeDisplayText(OutlineNode node) => _controllers[node.id]?.text ?? node.text;

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

    for (final root in _visibleRoots) {
      walk(root, 0, null);
    }
    return result;
  }

  /// 构建节点列表的展示数据
  ///
  /// 与 [_flatten] 的可见节点一致，另外保留正处于折叠动画中的子节点行，
  /// 使这些行在动画期间仍参与布局并绘制收进圆点的过渡效果；
  /// 动画结束后移除对应控制器，子节点行随即从列表中消失。
  List<_OutlineDisplayRow> _buildDisplayRows() {
    final List<_OutlineDisplayRow> rows = [];

    // rowFoldProgress 为该节点行所属祖先的收拢动画进度，
    // foldDotDepth 为收拢目标圆点所在节点的深度
    void walk(
      OutlineNode node,
      int depth,
      OutlineNode? parent,
      Animation<double>? rowFoldProgress,
      int foldDotDepth,
    ) {
      final Animation<double>? ownFold = _foldAnimations[node.id];
      rows.add(
        _OutlineDisplayRow(
          flatNode: FlatNode(node: node, depth: depth, parent: parent),
          foldProgress: rowFoldProgress,
          foldDotDepth: rowFoldProgress == null ? null : foldDotDepth,
          dotFoldProgress: ownFold,
        ),
      );

      // 展开的节点正常展示子节点；处于折叠动画中的节点在动画期间也需要展示子节点行
      if (!node.isExpanded && ownFold == null) return;

      // 当前节点自身有动画时，子节点统一收进当前节点的圆点；否则沿用祖先动画的目标圆点
      final Animation<double>? childFoldProgress = ownFold ?? rowFoldProgress;
      final int childFoldDotDepth = ownFold != null ? depth : foldDotDepth;
      for (final child in node.children) {
        walk(child, depth + 1, node, childFoldProgress, childFoldDotDepth);
      }
    }

    for (final root in _visibleRoots) {
      walk(root, 0, null, null, 0);
    }
    return rows;
  }

  /// 计算当前编辑节点下方连接线的高亮范围
  ///
  /// 当前节点的圆点位于列（深度 + 1），该列上的连接线由其后代节点行绘制，
  /// 从圆点下方一直延伸到下一个同级节点所在行；同级节点是最后一个时，
  /// 连接线一直延伸到子树结束处，只要有子节点就存在可点亮的线条。
  /// 返回高亮列、起始行索引（当前节点的下一行）与结束行索引（不含）；
  /// 当前节点没有子孙节点时该列上不存在连接线，返回 null。
  ({int column, int startIndex, int endIndex})? _resolveActiveSiblingLine(
    List<FlatNode> flatList,
    String? activeNodeId,
  ) {
    if (activeNodeId == null) return null;
    final int activeIndex = flatList.indexWhere((flat) => flat.node.id == activeNodeId);
    if (activeIndex < 0) return null;
    final int activeDepth = flatList[activeIndex].depth;

    // 向后跨过当前节点的全部子孙行，直到子树结束
    int endIndex = activeIndex + 1;
    while (endIndex < flatList.length && flatList[endIndex].depth > activeDepth) {
      endIndex++;
    }

    // 当前节点没有子孙节点时，圆点所在列上没有连接线
    if (endIndex == activeIndex + 1) return null;
    return (column: activeDepth + 1, startIndex: activeIndex + 1, endIndex: endIndex);
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

  // ================= 主题导航 =================

  /// 进入指定节点的主题视图
  ///
  /// 进入后只展示该节点的子节点；节点暂无子节点时展示空主题提示，
  /// 可继续通过顶部“添加节点”创建子主题。
  void _enterNodeTopic(String nodeId) {
    final node = _findNode(nodeId);
    if (node == null) return;
    _switchFocusTheme(nodeId);
  }

  /// 点击顶部面包屑切换主题层级
  ///
  /// [depth] 为 0 时回到显示全部节点，否则进入路径中对应层的节点。
  void _onBreadcrumbTap(int depth) {
    if (depth <= 0) {
      _switchFocusTheme(null);
      return;
    }
    final path = _focusPath;
    if (depth > path.length) return;
    _switchFocusTheme(path[depth - 1].id);
  }

  /// 切换主题视图的聚焦节点
  ///
  /// [nodeId] 为 null 时退出主题视图；切换后释放文本输入焦点并回到视口顶部。
  void _switchFocusTheme(String? nodeId) {
    if (nodeId == _focusNodeId) return;

    // 切换视图前退出批量选择模式，避免选区状态残留在不可见的节点上
    if (_isBatchSelectionMode) exitBatchSelectionMode();
    _releaseTextInputFocus();

    setState(() {
      _focusNodeId = nodeId;
      // 清除旧的节点选区与焦点记录，避免工具栏或选区继续作用于已不可见的节点
      _selectedNodeIds.clear();
      _selectAllLevel = 0;
      _selectionAnchorIndex = null;
      _lastFocusedNodeId = null;
    });
    // 主题切换改变了可见节点行，丢弃进行中的折叠动画，避免残留过渡
    _clearFoldAnimations();

    // 等待新列表完成布局后再回到顶部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  // ================= 资源管理 =================

  /// 为单个节点创建控制器和焦点节点
  void _ensureResources(OutlineNode node) {
    if (!_controllers.containsKey(node.id)) {
      final controller = RichTextEditingController(
        text: node.text,
        // 关联文本使用主题强调色渲染，字号与字重由样式解析器统一处理
        styleResolver: (baseStyle, flags) => defaultStyleResolver(
          baseStyle,
          flags,
          linkColor: widget.colorScheme.primary,
        ),
      );
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
          // 记录最近编辑的节点，供下次打开时按「上一次编辑」定位
          _scheduleLastEditedPathSave();
          // 输入框获得焦点时清除节点选区（Shift+click、右键菜单唤起、撤销/重做时除外）
          if (!_isShiftClicking &&
              !_isContextMenuOpening &&
              !_isUndoRedoing &&
              (_selectedNodeIds.isNotEmpty || _selectAllLevel != 0)) {
            _selectedNodeIds.clear();
            _selectAllLevel = 0;
          }
          // 重置选区锚点：点击输入框获得焦点后，Shift+click 应以当前焦点节点为起始
          if (!_isShiftClicking && !_isContextMenuOpening && !_isUndoRedoing) {
            _selectionAnchorIndex = null;
          }
          // 当前编辑节点变为本节点，刷新节点列表以更新圆点与连接线高亮；
          // 失焦时高亮仍保留在最近编辑的节点上，无需重建
          if (mounted) setState(() {});
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
      _attachmentKeys.remove(id);
      _tableKeys.remove(id);
    }
  }

  // ================= 文件读写 =================

  /// 启动加载指示的延时显示
  ///
  /// 本地文件通常几十毫秒内解析完成，立即显示加载指示会造成闪烁；
  /// 超过 [_loadingIndicatorDelay] 仍未完成时才显示
  void _startLoadingIndicator() {
    _showLoadingIndicator = false;
    _loadingIndicatorTimer?.cancel();
    _loadingIndicatorTimer = Timer(_loadingIndicatorDelay, () {
      if (!mounted) return;
      setState(() => _showLoadingIndicator = true);
    });
  }

  /// 停止加载指示
  void _stopLoadingIndicator() {
    _loadingIndicatorTimer?.cancel();
    _loadingIndicatorTimer = null;
    _showLoadingIndicator = false;
  }

  /// 从关联的文件加载大纲内容
  ///
  /// 载入失败时记录错误原因，由编辑器展示错误占位与重试入口
  Future<void> _loadFromFile() async {
    _isContentReady = false;
    _loadErrorMessage = null;
    // 读取上一次编辑节点，供「打开文件时」的「上一次编辑」模式定位；
    // 需在解析前读取，解析会触发重建，据此提前决定内容呈现时是否需要先完成定位
    _loadLastEditedPath();
    _deferContentPaint = _shouldDeferContentPaint();
    _startLoadingIndicator();
    try {
      final file = File(widget.filePath!);
      if (!await file.exists()) {
        _loadErrorMessage = '设定文件不存在，可能已被移动或删除';
        return;
      }
      final text = await file.readAsString();
      parseFromText(text);
      // 回填节点备注与附加图片（伴生文件不存在时保持为空）
      await _loadNotes();
      // 回填节点关键词（伴生文件不存在时保持为空）
      await _loadKeywords();
      // 回填节点关联文本（伴生文件不存在时保持为空）
      await _loadLinks();
      // 恢复上次退出时的节点折叠状态
      await _loadFoldState();
    } catch (e) {
      debugPrint('加载大纲文件失败: $e');
      _loadErrorMessage = '设定内容读取失败';
    } finally {
      _isContentReady = true;
      _stopLoadingIndicator();
      // 读取失败时不会定位，直接恢复绘制以显示错误占位
      if (_loadErrorMessage != null) _deferContentPaint = false;
      if (mounted) {
        // 解析完成后重建节点列表（解析本身不触发刷新）
        setState(() {});
        // 仅在读取成功时执行聚焦与内容就绪通知
        if (_loadErrorMessage == null) {
          // 新建设定文件时把焦点落到第一个节点，便于内容加载完成后立即输入；
          // 其余情况按「打开文件时」设置定位视口，只读的备份预览固定从顶部开始
          if (widget.autoFocusFirstNode) {
            _focusFirstNode();
          } else if (!widget.readOnly) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _applyOpenBehavior();
            });
          }
          // 通知外部内容已加载完成，用于刷新查找替换等依赖内容的状态
          widget.onContentLoaded?.call();
        }
      }
    }
  }

  /// 重新载入文件内容
  ///
  /// 读取失败后由错误占位的重试按钮触发
  void _retryLoad() {
    setState(() {
      _loadErrorMessage = null;
      _isContentReady = false;
    });
    _loadFromFile();
  }

  /// 聚焦第一个节点并把光标置于节点开头
  ///
  /// 内容加载完成后节点可能尚未完成构建，因此延后到下一帧再请求焦点，
  /// 确保对应的输入框已挂载；滚动定位由 [_focusNodeWithSelection] 负责。
  void _focusFirstNode() {
    final flatList = _flatten();
    if (flatList.isEmpty) return;
    final String nodeId = flatList.first.node.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNodeWithSelection(nodeId, moveCursorToEnd: false);
    });
  }

  /// 按「打开文件时」设置定位视口
  ///
  /// 「默认」保持视口在顶部；「上一次编辑」定位到上次编辑过的节点；
  /// 「定位至文末」定位到最后一个节点。记录的上次编辑节点已不存在时回退到顶部。
  /// 会话恢复的标签页优先回到关闭前编辑的节点，不受设置影响。
  /// 定位结束后恢复节点列表的绘制，使内容呈现时已处于定位后的位置。
  void _applyOpenBehavior() {
    // 内容加载后已被外部定位（如全文搜索跳转）时，以外部定位为准
    if (_lastFocusedNodeId != null) {
      _endContentDeferral();
      return;
    }

    final String? targetId = _resolveOpenTargetNodeId();
    if (targetId == null) {
      _endContentDeferral();
      return;
    }

    _scrollToNode(targetId, onDone: () => _finishOpenPositioning(targetId));
  }

  /// 解析「打开文件时」应定位到的节点
  ///
  /// 未配置定位或记录的位置已失效时返回 null，此时视口保持在顶部。
  String? _resolveOpenTargetNodeId() {
    final String mode = widget.restoreLastEditPosition
        ? 'lastEdit'
        : SettingsService.instance.openChapterCursorMode;

    if (mode == 'lastEdit') {
      final String? path = _lastEditedPath;
      return path == null ? null : _nodeAtPath(path)?.id;
    }
    if (mode == 'end') {
      return _lastNodeInTree()?.id;
    }
    return null;
  }

  /// 是否需要在内容首次呈现前暂缓绘制节点列表
  ///
  /// 在解析内容前调用，此时节点树尚未建立，只能按定位模式判断：
  /// 「上一次编辑」模式存在记录路径、「定位至文末」模式下均可能需要滚动定位。
  /// 记录的位置实际失效时会由 [_applyOpenBehavior] 直接恢复绘制。
  bool _shouldDeferContentPaint() {
    // 只读预览固定从顶部开始，新建文件聚焦首个节点，两者都不需要定位
    if (widget.readOnly || widget.autoFocusFirstNode) return false;

    final String mode = widget.restoreLastEditPosition
        ? 'lastEdit'
        : SettingsService.instance.openChapterCursorMode;
    if (mode == 'lastEdit') return _lastEditedPath != null;
    return mode == 'end';
  }

  /// 打开定位结束后的收尾
  ///
  /// 桌面端把焦点与光标交给定位到的节点、光标落在文末，便于打开后直接继续输入；
  /// 目标节点未能构建（定位放弃）或标签页未激活时不获取焦点，
  /// 避免后台标签页抢占键盘焦点。
  void _finishOpenPositioning(String nodeId) {
    final bool focused = !PlatformCapabilities.isMobile &&
        widget.isActive &&
        _nodeTileGlobalRect(nodeId) != null;
    if (!focused) {
      _endContentDeferral();
      return;
    }

    _focusNodeWithSelection(nodeId, moveCursorToEnd: true, ensureVisible: false);
    // 延后一帧恢复绘制：输入框获取焦点后可能因光标超出视口而调整滚动位置，
    // 让该调整在隐藏状态下完成，内容呈现时便不再发生移动
    WidgetsBinding.instance.addPostFrameCallback((_) => _endContentDeferral());
  }

  /// 结束内容绘制延迟，让节点列表一次性呈现在定位后的位置
  void _endContentDeferral() {
    if (!mounted || !_deferContentPaint) return;
    setState(() => _deferContentPaint = false);
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
    // 重新解析内容后旧的主题节点可能已不存在，回到显示全部节点的视图
    _focusNodeId = null;
    // 节点 ID 全部重新生成，正在编辑备注的节点已不存在
    _noteEditingNodeId = null;
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

  /// 保存伴生数据到文件
  ///
  /// 关键词、关联、备注与图片随设定文件一同保存，
  /// 由外部保存流程在设定项内容写入文件后调用。
  Future<void> saveCompanionData() async {
    if (widget.readOnly) return;
    // 关键词与节点树同在保存流程中落盘，保证正文编辑器索引同步更新
    await _saveKeywords();
    // 关联文本位置随内容变化，与节点树一同落盘
    await _saveLinks();
    // 节点备注与附加图片随内容变化，与节点树一同落盘
    await _saveNotes();
    // 伴生数据落盘后清理不再被引用的图片文件
    await _cleanupImages();
  }

  /// 折叠状态文件路径
  ///
  /// 与大纲文件同目录同名、扩展名替换为 `.fold.json`，
  /// 独立存放且只在本机使用，不参与云同步。
  String? get _foldStateFilePath => BookFolderService.foldStateFilePath(widget.filePath);

  /// 从文件读取折叠状态并应用到当前大纲树
  Future<void> _loadFoldState() async {
    final String? path = _foldStateFilePath;
    if (path == null) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final dynamic data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      final Set<String> collapsed = (data['collapsed'] as List?)?.whereType<String>().toSet() ?? {};
      if (!mounted) return;
      if (collapsed.isEmpty) return;
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

  /// 从缓存读取上一次编辑节点的路径
  void _loadLastEditedPath() {
    final String? bookUuid = widget.bookUuid;
    final String? itemUuid = widget.settingItemUuid;
    if (bookUuid == null || itemUuid == null) return;
    _lastEditedPath = OutlineLastEditCacheService.instance.getLastEditedPath(
      bookUuid: bookUuid,
      settingItemUuid: itemUuid,
    );
  }

  /// 安排记录上一次编辑节点的路径
  ///
  /// 节点焦点切换可能连续发生，等待一小段时间并合并为一次写入，
  /// 避免频繁点击节点时产生多次缓存写入
  void _scheduleLastEditedPathSave() {
    if (widget.readOnly) return;
    _lastEditedPathSaveTimer?.cancel();
    _lastEditedPathSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _lastEditedPathSaveTimer = null;
      _saveLastEditedPath();
    });
  }

  /// 将最近聚焦节点的路径同步到 [_lastEditedPath] 并写入缓存
  ///
  /// 最近聚焦节点已被删除时清空记录，使「上一次编辑」回退到默认行为。
  void _saveLastEditedPath() {
    if (widget.readOnly) return;
    final String? bookUuid = widget.bookUuid;
    final String? itemUuid = widget.settingItemUuid;
    if (bookUuid == null || itemUuid == null) return;

    final String? nodeId = _lastFocusedNodeId;
    if (nodeId == null) return;
    // 结构变化会移动节点，写入前按最新树结构刷新路径
    final String? path = _pathOfNode(nodeId);
    _lastEditedPath = path;
    // 节点已被删除时移除记录，下次打开回退到默认行为
    if (path == null) {
      unawaited(OutlineLastEditCacheService.instance.removeSettingItem(
        bookUuid: bookUuid,
        settingItemUuid: itemUuid,
      ));
      return;
    }

    unawaited(OutlineLastEditCacheService.instance.saveLastEditedPath(
      bookUuid: bookUuid,
      settingItemUuid: itemUuid,
      path: path,
    ));
  }

  /// 将折叠状态写入指定文件
  Future<void> _writeFoldStateFile(String path) async {
    try {
      final file = File(path);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString(jsonEncode({
        'collapsed': _collectCollapsedPaths(),
      }));
    } catch (e) {
      debugPrint('保存大纲折叠状态失败: $e');
    }
  }

  /// 将折叠状态文件随大纲文件重命名一同迁移
  ///
  /// 折叠状态文件按大纲文件路径派生，大纲文件改名后需要把旧文件移动到新路径，
  /// 否则折叠状态会残留在旧文件名下，与新文件名脱节。
  void _renameFoldStateFile(String? oldFilePath, String? newFilePath) {
    if (widget.readOnly) return;
    final String? oldFoldPath = BookFolderService.foldStateFilePath(oldFilePath);
    final String? newFoldPath = BookFolderService.foldStateFilePath(newFilePath);
    if (oldFoldPath == null || newFoldPath == null || oldFoldPath == newFoldPath) return;
    // 并入写入任务链，保证先完成排队中的旧路径写入，再迁移折叠状态文件
    _foldStateWriteChain = _foldStateWriteChain.then((_) => _moveFoldStateFile(oldFoldPath, newFoldPath));
  }

  /// 将折叠状态文件从旧路径移动到新路径
  Future<void> _moveFoldStateFile(String oldPath, String newPath) async {
    try {
      final File oldFile = File(oldPath);
      if (!await oldFile.exists()) return;
      final File newFile = File(newPath);
      if (!await newFile.parent.exists()) {
        await newFile.parent.create(recursive: true);
      }
      // 目标文件已存在时先移除，避免重命名因目标存在而失败
      if (await newFile.exists()) {
        await newFile.delete();
      }
      await oldFile.rename(newPath);
    } catch (e) {
      debugPrint('重命名大纲折叠状态文件失败: $e');
    }
  }

  // ================= 大纲关键词 =================

  /// 从伴生文件读取关键词并回填到当前节点树
  ///
  /// 关键词按「层级索引路径」与节点对应，与折叠状态使用同一套路径规则；
  /// 文件中已不存在的节点路径会被忽略。
  Future<void> _loadKeywords() async {
    final OutlineKeywordService? service = widget.keywordService;
    if (service == null) return;
    final Map<String, OutlineKeywordFileNode> nodes = await service.readSettingKeywords(widget.filePath);
    if (nodes.isEmpty) return;
    for (final entry in nodes.entries) {
      final OutlineNode? node = _nodeAtPath(entry.key);
      if (node == null) continue;
      node.keywords = List<OutlineKeyword>.of(entry.value.keywords);
    }
    // 让书籍级索引与本次加载结果保持一致（如伴生文件被外部修改过）
    _syncKeywordsToService();
  }

  /// 将当前树中带关键词的节点写入伴生文件
  Future<void> _saveKeywords() async {
    final OutlineKeywordService? service = widget.keywordService;
    final String? filePath = widget.filePath;
    final String? itemUuid = widget.settingItemUuid;
    if (service == null || filePath == null || itemUuid == null || itemUuid.isEmpty) return;
    await service.saveSettingKeywords(
      settingItemFilePath: filePath,
      settingItemUuid: itemUuid,
      settingItemTitle: widget.title,
      nodes: _collectKeywordNodes(),
    );
  }

  /// 将当前树的关键词同步到书籍级索引（不写盘）
  ///
  /// 关键词修改、撤销恢复后立即调用，保证正文编辑器与冲突校验使用的索引是最新状态。
  void _syncKeywordsToService() {
    final OutlineKeywordService? service = widget.keywordService;
    final String? itemUuid = widget.settingItemUuid;
    if (service == null || itemUuid == null || itemUuid.isEmpty) return;
    service.applySettingKeywords(
      settingItemUuid: itemUuid,
      settingItemTitle: widget.title,
      settingItemFilePath: widget.filePath,
      nodes: _collectKeywordNodes(),
    );
  }

  /// 收集整棵树中带关键词的节点
  ///
  /// 每个条目同时记录节点文本、图片与其全部子孙节点快照，供正文悬浮卡片直接展示；
  /// 快照包含子孙节点的标题级别、文字样式、备注、图片与表格，卡片内容区据此还原节点样式。
  Map<String, OutlineKeywordFileNode> _collectKeywordNodes() {
    final result = <String, OutlineKeywordFileNode>{};

    // 收集节点的全部子孙节点，depth 以绑定节点为基准（子节点为 1）
    List<OutlineKeywordSubNode> collectChildren(OutlineNode node) {
      final children = <OutlineKeywordSubNode>[];
      void walk(OutlineNode parent, int depth) {
        for (final child in parent.children) {
          children.add(OutlineKeywordSubNode(
            depth: depth,
            text: child.text,
            note: child.note,
            imageFileName: child.imageFileName,
            headingLevel: child.headingLevel,
            styleRanges: List<TextStyleRange>.of(child.styleRanges),
            table: child.table?.clone(),
          ));
          walk(child, depth + 1);
        }
      }

      walk(node, 1);
      return children;
    }

    void walk(OutlineNode node, String path) {
      if (node.keywords.isNotEmpty) {
        result[path] = OutlineKeywordFileNode(
          text: node.text,
          imageFileName: node.imageFileName,
          children: collectChildren(node),
          keywords: List<OutlineKeyword>.of(node.keywords),
        );
      }
      for (int i = 0; i < node.children.length; i++) {
        walk(node.children[i], '$path.$i');
      }
    }

    for (int i = 0; i < _roots.length; i++) {
      walk(_roots[i], '$i');
    }
    return result;
  }

  /// 设置节点的关键词列表
  ///
  /// 关键词在整本书内唯一：已被其他节点绑定的关键词会被拒绝，
  /// 返回值即被拒绝的关键词集合，供关键词卡片提示冲突。
  Set<String> _setNodeKeywords(String nodeId, List<OutlineKeyword> keywords) {
    final OutlineNode? node = _findNode(nodeId);
    if (node == null) return {};

    final OutlineKeywordService? service = widget.keywordService;
    final String? nodePath = _pathOfNode(nodeId);
    final String currentItemUuid = widget.settingItemUuid ?? '';
    final Set<String> rejected = {};
    final Set<String> seen = {};
    final List<OutlineKeyword> accepted = [];

    for (final keyword in keywords) {
      final String text = keyword.keyword.trim();
      if (text.isEmpty || !seen.add(text)) continue;
      final OutlineKeywordEntry? owner = service?.findKeywordOwner(text);
      // 已被其他设定项或其他节点绑定时拒绝
      final bool conflict = owner != null &&
          (owner.settingItemUuid != currentItemUuid || owner.nodePath != nodePath);
      if (conflict) {
        rejected.add(text);
        continue;
      }
      accepted.add(keyword.copyWith(keyword: text));
    }

    // 关键词未发生变化时只返回校验结果，避免产生无意义的撤销记录与保存
    if (_isSameKeywords(node.keywords, accepted)) return rejected;

    final TextSelection? selection = _controllers[nodeId]?.selection;
    _undoManager.beginBatch();
    setState(() {
      node.keywords = accepted;
    });
    _endBatchAndNotify(description: '设置关键词', focusNodeId: nodeId, focusSelection: selection);
    return rejected;
  }

  /// 判断两组关键词是否完全一致
  bool _isSameKeywords(List<OutlineKeyword> a, List<OutlineKeyword> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 打开节点关键词编辑卡片
  ///
  /// 卡片以居中弹窗展示（弹窗外区域变暗），每次增删改都通过 [_setNodeKeywords] 立即落库。
  Future<void> _showKeywordCard(String nodeId) async {
    if (widget.readOnly || widget.keywordService == null) return;
    final OutlineNode? node = _findNode(nodeId);
    if (node == null) return;
    await OutlineKeywordCard.show(
      context: context,
      keywords: List<OutlineKeyword>.of(node.keywords),
      onChanged: (keywords) => _setNodeKeywords(nodeId, keywords),
    );
  }

  /// 为当前活动节点打开关键词绑定卡片
  ///
  /// 供移动端工具栏等外部入口调用；无活动节点或只读时不响应。
  void showKeywordCardForActiveNode() {
    final String? nodeId = _activeNodeId;
    if (nodeId != null) _showKeywordCard(nodeId);
  }

  // ================= 大纲关联 =================

  /// 生成关联标识
  String _generateLinkId() => 'link_${DateTime.now().microsecondsSinceEpoch}';

  /// 从伴生文件读取关联目标与关联文本范围并回填到当前节点树
  ///
  /// 关联文本范围按「层级索引路径」与节点对应，与关键词、折叠状态使用同一套路径规则；
  /// 文件中已不存在的节点路径会被忽略。
  Future<void> _loadLinks() async {
    final OutlineLinkFile file = await _linkService.read(widget.filePath);
    _links
      ..clear()
      ..addAll(file.links);
    if (file.nodes.isEmpty) return;

    for (final entry in file.nodes.entries) {
      final OutlineNode? node = _nodeAtPath(entry.key);
      if (node == null) continue;

      List<TextStyleRange> ranges = node.styleRanges;
      for (final OutlineLinkRange linkRange in entry.value) {
        if (linkRange.linkId.isEmpty) continue;

        // 位置与记录文字一致时直接使用，否则按文字重新定位，
        // 避免上次未及时落盘的编辑导致关联范围产生偏移
        int start = linkRange.start;
        int end = linkRange.end;
        final String linkText = linkRange.text;
        final bool sameText = linkText.isNotEmpty &&
            start >= 0 &&
            end <= node.text.length &&
            end - start == linkText.length &&
            node.text.substring(start, end) == linkText;
        if (linkText.isNotEmpty && !sameText) {
          // 同一段文字可能出现多次，取与记录位置最近的一处
          int? bestIndex;
          int bestDistance = 1 << 30;
          int searchStart = 0;
          while (searchStart < node.text.length) {
            final int index = node.text.indexOf(linkText, searchStart);
            if (index < 0) break;
            final int distance = (index - start).abs();
            if (distance < bestDistance) {
              bestDistance = distance;
              bestIndex = index;
            }
            searchStart = index + linkText.length;
          }
          if (bestIndex == null) continue;
          start = bestIndex;
          end = bestIndex + linkText.length;
        }
        if (start >= end || end > node.text.length) continue;

        ranges = TextStyleRangeUtils.applyToggle(
          ranges,
          start,
          end,
          (current) => current.copyWith(linkId: linkRange.linkId),
          node.text.length,
        );
      }
      node.styleRanges = ranges;
      final controller = _controllers[node.id];
      if (controller is RichTextEditingController) {
        controller.styleRanges = ranges;
      }
    }

    if (mounted) setState(() {});
  }

  /// 将当前树中的关联目标与关联文本范围写入伴生文件
  ///
  /// 仅保存仍被文本引用的关联目标，文本删除后残留的目标不再写盘。
  Future<bool> _saveLinks() async {
    if (widget.readOnly) return false;
    final Map<String, List<OutlineLinkRange>> nodes = _collectLinkRanges();
    final Set<String> usedIds = {
      for (final ranges in nodes.values)
        for (final range in ranges) range.linkId,
    };
    final Map<String, OutlineLinkTarget> links = {
      for (final entry in _links.entries)
        if (usedIds.contains(entry.key)) entry.key: entry.value,
    };
    return _linkService.save(
      settingItemFilePath: widget.filePath,
      links: links,
      nodes: nodes,
    );
  }

  /// 收集整棵树中的关联文本范围
  ///
  /// 返回「节点路径 → 关联文本范围列表」，仅包含存在关联文本的节点。
  Map<String, List<OutlineLinkRange>> _collectLinkRanges() {
    final result = <String, List<OutlineLinkRange>>{};

    void walk(OutlineNode node, String path) {
      final ranges = <OutlineLinkRange>[];
      for (final range in node.styleRanges) {
        final String? linkId = range.flags.linkId;
        if (linkId == null) continue;
        final int start = range.start.clamp(0, node.text.length);
        final int end = range.end.clamp(0, node.text.length);
        if (start < end) {
          ranges.add(OutlineLinkRange(
            start: start,
            end: end,
            linkId: linkId,
            text: node.text.substring(start, end),
          ));
        }
      }
      if (ranges.isNotEmpty) result[path] = ranges;
      for (int i = 0; i < node.children.length; i++) {
        walk(node.children[i], '$path.$i');
      }
    }

    for (int i = 0; i < _roots.length; i++) {
      walk(_roots[i], '$i');
    }
    return result;
  }

  /// 查找与指定范围重叠的关联样式区间
  List<TextStyleRange> _linkRangesInSelection(OutlineNode node, TextSelection selection) {
    if (!selection.isValid) return const [];
    return [
      for (final range in node.styleRanges)
        if (range.flags.linkId != null && range.start < selection.end && range.end > selection.start) range,
    ];
  }

  /// 从右键菜单打开关联目标选择弹窗
  ///
  /// 仅在单节点存在文字选区时可用，选择完成后把选区文字标记为关联文本。
  Future<void> _showLinkDialog(String? nodeId) async {
    if (widget.readOnly || nodeId == null) return;
    final OutlineNode? node = _findNode(nodeId);
    final controller = _controllers[nodeId];
    if (node == null || controller == null) return;

    final TextSelection selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final int start = selection.start.clamp(0, node.text.length);
    final int end = selection.end.clamp(0, node.text.length);
    if (start >= end) return;

    final WorkspaceProvider provider = context.read<WorkspaceProvider>();
    final OutlineLinkTarget? target = await OutlineLinkDialog.show(
      context: context,
      chapters: provider.chapters,
      settingItems: provider.settingItems,
      currentSettingItemUuid: widget.settingItemUuid ?? '',
      readChapterContent: provider.readChapterContent,
      readSettingItemContent: provider.readSettingItemContent,
      volumeNameOf: provider.getVolumeName,
      groupNameOf: provider.getSettingGroupName,
    );
    if (target == null || !mounted) return;

    _applyLink(nodeId, start, end, target.copyWith(id: _generateLinkId()));
  }

  /// 将节点文本的指定范围标记为关联文本
  void _applyLink(String nodeId, int start, int end, OutlineLinkTarget target) {
    final OutlineNode? node = _findNode(nodeId);
    final controller = _controllers[nodeId];
    if (node == null || controller == null) return;

    final TextSelection selection = controller.selection;
    _undoManager.beginBatch();
    setState(() {
      _links[target.id] = target;

      // 先清除选区范围内已有的关联标记，保证同一段文字只关联到一个目标
      List<TextStyleRange> ranges = node.styleRanges;
      final TextSelection targetRange = TextSelection(baseOffset: start, extentOffset: end);
      for (final existing in _linkRangesInSelection(node, targetRange)) {
        ranges = TextStyleRangeUtils.applyToggle(
          ranges,
          existing.start,
          existing.end,
          (current) => current.copyWith(clearLink: true),
          node.text.length,
        );
      }
      // 再为选区写入新的关联标识
      ranges = TextStyleRangeUtils.applyToggle(
        ranges,
        start,
        end,
        (current) => current.copyWith(linkId: target.id),
        node.text.length,
      );
      node.styleRanges = ranges;
      // 同步到控制器以触发富文本重建
      (controller as RichTextEditingController).styleRanges = ranges;
    });
    _endBatchAndNotify(description: '添加关联', focusNodeId: nodeId, focusSelection: selection);
  }

  /// 移除与指定范围重叠的关联文本标记
  void _removeLink(String nodeId, int start, int end) {
    final OutlineNode? node = _findNode(nodeId);
    final controller = _controllers[nodeId];
    if (node == null || controller == null) return;

    final TextSelection selection = TextSelection(baseOffset: start, extentOffset: end);
    final List<TextStyleRange> targets = _linkRangesInSelection(node, selection);
    if (targets.isEmpty) return;

    _undoManager.beginBatch();
    setState(() {
      List<TextStyleRange> ranges = node.styleRanges;
      // 按整段关联文本清除标记，避免只移除选区覆盖的部分
      for (final range in targets) {
        ranges = TextStyleRangeUtils.applyToggle(
          ranges,
          range.start,
          range.end,
          (current) => current.copyWith(clearLink: true),
          node.text.length,
        );
      }
      node.styleRanges = ranges;
      (controller as RichTextEditingController).styleRanges = ranges;
    });
    _endBatchAndNotify(description: '移除关联', focusNodeId: nodeId, focusSelection: controller.selection);
  }

  /// 光标处的关联文本范围
  ///
  /// 用于把落在关联文本内部的程序化光标位置移到关联文本末尾，避免光标停在关联文本中间。
  int _snapOffsetOutOfLink(String nodeId, int offset) {
    final OutlineNode? node = _findNode(nodeId);
    if (node == null) return offset;
    final span = node.linkSpanAt(offset);
    // 只处理严格位于关联文本内部的位置，边界上的光标保持不变
    if (span == null || offset == span.start) return offset;
    return span.end;
  }

  /// 删除光标旁的关联标记
  ///
  /// [forward] 为 true 时对应删除键（光标左侧的字符），false 时对应退格键（光标右侧的字符）。
  /// 命中关联文本时仅移除关联标记并保留文字，返回 true 表示本次按键已被处理。
  bool _removeLinkAtCaret(String nodeId, {required bool forward}) {
    final OutlineNode? node = _findNode(nodeId);
    final controller = _controllers[nodeId];
    if (node == null || controller == null) return false;

    final TextSelection selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;

    final int caret = selection.start.clamp(0, node.text.length);
    final int offset = forward ? caret : caret - 1;
    final span = node.linkSpanAt(offset);
    if (span == null) return false;

    _removeLink(nodeId, span.start, span.end);
    return true;
  }

  /// 左右方向键跨越关联文本
  ///
  /// 关联文本视为一个整体：向右移动时整段跳过，向左移动时同样整段跳过。
  /// 返回 true 表示已移动光标，false 表示光标不在关联文本边界，交由输入框默认处理。
  bool _moveCaretAcrossLink(String nodeId, {required bool forward}) {
    final OutlineNode? node = _findNode(nodeId);
    final controller = _controllers[nodeId];
    if (node == null || controller == null) return false;

    final TextSelection selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;

    final int caret = selection.start.clamp(0, node.text.length);
    if (forward) {
      // 光标位于关联文本左边界或内部时，跳到整段关联文本末尾
      final span = node.linkSpanAt(caret);
      if (span == null) return false;
      controller.selection = TextSelection.collapsed(offset: span.end);
    } else {
      // 光标位于关联文本右边界或内部时，跳到整段关联文本开头
      final span = node.linkSpanAt(caret - 1);
      if (span == null) return false;
      controller.selection = TextSelection.collapsed(offset: span.start);
    }
    _ensureCaretVisibleInViewport(nodeId);
    return true;
  }

  /// 点击关联文本时跳转到关联目标
  ///
  /// 跳转失败（目标被删除、无法定位到段落或节点）时给出浮动提示。
  Future<void> _handleLinkTap(String linkId) async {
    final OutlineLinkTarget? target = _links[linkId];
    if (target == null) {
      SnackBarService.showError(context, '关联目标不存在，无法跳转');
      return;
    }

    final bool located = await context.read<WorkspaceProvider>().navigateToOutlineLink(target);
    if (!located && mounted) {
      SnackBarService.showError(context, '无法定位关联目标，目标可能已被修改或删除');
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

  /// 计算节点自根节点起的层级索引路径
  ///
  /// 路径形如 `0.2.1`，与折叠状态的记录方式一致；节点不存在时返回 null。
  String? _pathOfNode(String nodeId) {
    String? search(List<OutlineNode> nodes, String prefix) {
      for (int i = 0; i < nodes.length; i++) {
        final path = prefix.isEmpty ? '$i' : '$prefix.$i';
        if (nodes[i].id == nodeId) return path;
        final result = search(nodes[i].children, path);
        if (result != null) return result;
      }
      return null;
    }

    return search(_roots, '');
  }

  /// 按层级索引路径查找节点
  ///
  /// 路径中的任一级索引越界或格式非法时返回 null。
  OutlineNode? _nodeAtPath(String path) {
    List<OutlineNode> nodes = _roots;
    OutlineNode? node;
    for (final segment in path.split('.')) {
      final int index = int.tryParse(segment) ?? -1;
      if (index < 0 || index >= nodes.length) return null;
      node = nodes[index];
      nodes = node.children;
    }
    return node;
  }

  /// 获取大纲树中的最后一个节点
  ///
  /// 沿每级子节点的末尾向下查找，得到整棵树中排在最末的节点；
  /// 大纲为空时返回 null。
  OutlineNode? _lastNodeInTree() {
    if (_roots.isEmpty) return null;
    OutlineNode node = _roots.last;
    while (node.children.isNotEmpty) {
      node = node.children.last;
    }
    return node;
  }

  // ================= 节点备注、图片与表格 =================

  /// 从伴生文件读取备注、图片与表格并回填到当前节点树
  ///
  /// 按「层级索引路径」与节点对应，与关键词、关联使用同一套路径规则；
  /// 文件中已不存在的节点路径会被忽略。
  Future<void> _loadNotes() async {
    final OutlineNoteFile file = await _noteService.read(widget.filePath);
    if (file.nodes.isEmpty) return;

    for (final entry in file.nodes.entries) {
      final OutlineNode? node = _nodeAtPath(entry.key);
      if (node == null) continue;
      node.note = entry.value.note;
      node.imageFileName = entry.value.imageFileName;
      node.table = entry.value.table;
    }

    if (mounted) setState(() {});
  }

  /// 将当前树中的备注、图片与表格写入伴生文件
  Future<void> _saveNotes() async {
    if (widget.readOnly) return;
    await _noteService.save(
      settingItemFilePath: widget.filePath,
      nodes: _collectNoteNodes(),
    );
  }

  /// 收集整棵树中存在备注、图片或表格的节点
  ///
  /// 返回「节点路径 → 备注、图片与表格数据」，仅包含有内容的节点。
  Map<String, OutlineNoteData> _collectNoteNodes() {
    final result = <String, OutlineNoteData>{};

    void walk(OutlineNode node, String path) {
      if (node.note.isNotEmpty || node.imageFileName.isNotEmpty || node.table != null) {
        result[path] = OutlineNoteData(
          note: node.note,
          imageFileName: node.imageFileName,
          table: node.table,
        );
      }
      for (int i = 0; i < node.children.length; i++) {
        walk(node.children[i], '$path.$i');
      }
    }

    for (int i = 0; i < _roots.length; i++) {
      walk(_roots[i], '$i');
    }
    return result;
  }

  /// 开始编辑指定节点的备注
  ///
  /// 右键菜单选择「添加备注」或点击已有备注时进入编辑，
  /// 备注区展开为多行输入框并自动获取焦点。
  void _startNoteEditing(String nodeId) {
    if (widget.readOnly) return;
    if (_findNode(nodeId) == null) return;
    if (_noteEditingNodeId == nodeId) return;

    // 备注输入框拥有焦点时删除键用于编辑备注文字，
    // 先清除节点选区，避免按键冒泡到编辑器时误删选中的节点
    _selectedNodeIds.clear();
    _selectAllLevel = 0;
    _selectionAnchorIndex = null;

    setState(() => _noteEditingNodeId = nodeId);
  }

  /// 结束指定节点的备注编辑
  ///
  /// 备注为空或只含空白字符时视为未填写，清空后隐藏备注区。
  void _stopNoteEditing(String nodeId) {
    if (_noteEditingNodeId != nodeId) return;

    final OutlineNode? node = _findNode(nodeId);
    if (node != null && node.note.isNotEmpty && node.note.trim().isEmpty) {
      node.note = '';
      _notifyContentChanged();
    }

    if (mounted) setState(() => _noteEditingNodeId = null);
  }

  /// 节点备注内容变化
  ///
  /// 备注输入过程中不刷新节点列表，由备注输入框自身维护显示内容。
  void _onNodeNoteChanged(String nodeId, String note) {
    if (widget.readOnly) return;
    final OutlineNode? node = _findNode(nodeId);
    if (node == null || node.note == note) return;
    node.note = note;
    _notifyContentChanged();
  }

  /// 选择图片并插入到指定节点
  ///
  /// 选中的图片会被复制到设定项文件所在目录的 image 文件夹，
  /// 节点只记录文件名；替换已有图片时暂存原文件名，待伴生数据保存时再清理。
  Future<void> _pickImageForNode(String nodeId) async {
    if (widget.readOnly) return;
    if (widget.filePath == null || widget.filePath!.isEmpty) return;
    if (_findNode(nodeId) == null) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
    } catch (e) {
      debugPrint('选择备注图片失败: $e');
      return;
    }

    final String? sourcePath = result?.files.single.path;
    if (sourcePath == null || !mounted) return;

    final String? imageFileName = await _noteService.importImage(
      settingItemFilePath: widget.filePath,
      sourcePath: sourcePath,
    );
    if (imageFileName == null || !mounted) return;

    final OutlineNode? node = _findNode(nodeId);
    if (node == null) return;

    final String oldImageFileName = node.imageFileName;
    setState(() => node.imageFileName = imageFileName);
    _importedImageFileNames.add(imageFileName);
    // 旧图片暂不删除，待伴生数据保存后统一清理
    if (oldImageFileName.isNotEmpty) {
      _discardedImageFileNames.add(oldImageFileName);
    }
    _notifyContentChanged();
  }

  /// 删除指定节点的图片
  ///
  /// 图片文件在伴生数据保存后统一清理，避免用户未保存就离开时文件已被删除。
  Future<void> _deleteNodeImage(String nodeId) async {
    if (widget.readOnly) return;
    final OutlineNode? node = _findNode(nodeId);
    if (node == null || node.imageFileName.isEmpty) return;

    _discardedImageFileNames.add(node.imageFileName);
    setState(() => node.imageFileName = '');
    _notifyContentChanged();
  }

  /// 清理不再被引用的图片文件
  ///
  /// 在伴生数据落盘后调用：删除编辑过程中被替换或移除的图片，
  /// 以及导入后又被撤销、已不被任何节点引用的图片；
  /// 仍被其它节点引用的文件保持不动。
  Future<void> _cleanupImages() async {
    if (_discardedImageFileNames.isEmpty && _importedImageFileNames.isEmpty) return;

    final Set<String> referenced = {};
    void walk(OutlineNode node) {
      if (node.imageFileName.isNotEmpty) referenced.add(node.imageFileName);
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }

    final Set<String> candidates = {
      ..._discardedImageFileNames,
      ..._importedImageFileNames,
    }..removeWhere(referenced.contains);
    _discardedImageFileNames.clear();
    _importedImageFileNames.clear();

    for (final fileName in candidates) {
      await _noteService.deleteImage(
        settingItemFilePath: widget.filePath,
        imageFileName: fileName,
      );
    }
  }

  /// 清理未随设定文件保存的新插入图片
  ///
  /// 关闭编辑器时这些图片尚未写入伴生文件，删除可避免残留；
  /// 曾参与过保存的图片已从集合中移除，不受影响。
  void _cleanupUnsavedImages() {
    if (_importedImageFileNames.isEmpty) return;
    for (final fileName in _importedImageFileNames) {
      unawaited(_noteService.deleteImage(
        settingItemFilePath: widget.filePath,
        imageFileName: fileName,
      ));
    }
    _importedImageFileNames.clear();
    _discardedImageFileNames.clear();
  }

  /// 为指定节点插入表格
  ///
  /// 表格显示在备注下方，初始为三列两行，首行作为表头。
  /// 同一节点最多保留一个表格，已有表格时不再重复插入。
  void _insertTableForNode(String nodeId) {
    if (widget.readOnly) return;
    final OutlineNode? node = _findNode(nodeId);
    if (node == null || node.table != null) return;

    // 表格输入框需要接收键盘事件，先清除节点选区避免按键误触发节点操作
    _selectedNodeIds.clear();
    _selectAllLevel = 0;
    _selectionAnchorIndex = null;

    _undoManager.beginBatch();
    setState(() => node.table = OutlineTableData.create());
    _undoManager.endBatch(description: '插入表格');
    _notifyContentChanged();
    // 焦点随菜单操作丢失时交还编辑器，保证插入后快捷键仍可用
    _restoreEditorFocusIfIdle();
  }

  /// 表格数据即将变化
  ///
  /// 表格组件在修改数据之前调用，开启撤销记录并把提交推迟到操作停止之后，
  /// 使连续输入与连续调整合并为一条撤销记录。
  void _onNodeTableWillChange() {
    if (widget.readOnly) return;
    _undoManager.beginBatch();
    _tableUndoTimer?.cancel();
    _tableUndoTimer = Timer(_tableUndoWindow, _commitTableUndo);
  }

  /// 提交表格编辑的撤销记录
  void _commitTableUndo() {
    _tableUndoTimer?.cancel();
    _tableUndoTimer = null;
    if (!_undoManager.isBatching) return;
    _undoManager.endBatch(description: '编辑表格');
  }

  /// 节点表格内容或结构变化
  ///
  /// 表格数据由表格组件直接修改，此处只负责通知外部保存与统计刷新。
  void _onNodeTableChanged(String nodeId) {
    if (widget.readOnly) return;
    final OutlineNode? node = _findNode(nodeId);
    if (node == null || node.table == null) return;
    _notifyContentChanged();
  }

  /// 删除指定节点的表格
  void _deleteNodeTable(String nodeId) {
    if (widget.readOnly) return;
    final OutlineNode? node = _findNode(nodeId);
    if (node == null || node.table == null) return;

    _undoManager.beginBatch();
    setState(() => node.table = null);
    _undoManager.endBatch(description: '删除表格');
    _notifyContentChanged();
    // 表格随单元格焦点一同移除，焦点丢失时交还编辑器，保证可以立即撤销
    _restoreEditorFocusIfIdle();
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
    // 结构变化会改变节点路径，同步刷新折叠状态与关键词索引，避免对应到错误的节点
    _saveFoldState();
    _syncKeywordsToService();
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
  /// 控制器变化监听器触发时，节点的 text 字段尚未通过 onChanged 同步，
  /// 传入 {nodeId: text} 可在深拷贝后覆盖对应节点的文本，确保快照记录正确文本。
  /// 传 null 时（结构操作场景），会从控制器同步所有节点的文本，避免遗漏。
  ///
  /// 可选参数 [nodeCaretOffsets] 与 [nodeTextOverrides] 配合：
  /// 传入 {nodeId: caretOffset} 表示文本覆盖后光标所在偏移，供样式区间调整使用。
  OutlineTreeSnapshot captureUndoSnapshot({
    String? focusNodeId,
    TextSelection? focusSelection,
    Map<String, String>? nodeTextOverrides,
    Map<String, int>? nodeCaretOffsets,
  }) {
    // 深拷贝整棵树，避免后续修改影响快照
    final rootsClone = _roots.map((r) => r.clone()).toList();

    // 在克隆的树上修正节点文本，确保快照捕获的是正确的文本状态
    if (nodeTextOverrides != null) {
      // 文本编辑场景：用指定的文本覆盖对应节点
      void applyOverride(OutlineNode node) {
        final text = nodeTextOverrides[node.id];
        if (text != null) {
          // 克隆节点的样式区间仍对应覆盖前的文本，按文本差异同步调整位置，
          // 保证快照中样式区间与文本长度一致
          if (text != node.text) {
            node.styleRanges = TextStyleRangeUtils.adjustForTextChange(
              node.styleRanges,
              node.text,
              text,
              caretOffset: nodeCaretOffsets?[node.id],
            );
          }
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

    // 撤销后当前主题节点可能已不存在，回退到显示全部节点的视图
    if (_focusNodeId != null && _findNode(_focusNodeId!) == null) {
      _focusNodeId = null;
    }
    // 撤销后正在编辑备注的节点可能已不存在，退出备注编辑
    if (_noteEditingNodeId != null && _findNode(_noteEditingNodeId!) == null) {
      _noteEditingNodeId = null;
    }

    setState(() {});

    // 撤销/重做可能恢复关键词，同步刷新书籍级索引
    _syncKeywordsToService();

    // 同步恢复焦点和选区，不依赖 post-frame，避免多次撤销/重做时回调交叉
    _restoreFocusFromSnapshot(snapshot);
    // 撤销可能移除正在编辑的表格等控件，焦点丢失时交还编辑器保证快捷键可用
    _restoreEditorFocusIfIdle();

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

  /// 没有输入控件持有焦点时把焦点交还编辑器
  ///
  /// 单元格、备注等输入框在桌面端点击自身之外的位置会失焦，撤销也可能移除正在
  /// 编辑的表格控件而使焦点消失；此时若不接管焦点，保存、撤销等快捷键会全部失效，
  /// 因此在帧末检查并交还编辑器焦点。
  void _restoreEditorFocusIfIdle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 焦点仍由输入控件持有时保持不动，避免打断正在进行的输入
      final FocusNode? primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return;
      if (_editorFocusNode.hasFocus) return;
      _editorFocusNode.requestFocus();
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
    // 先提交尚未结束的表格编辑，确保撤销能回退到本次表格修改之前
    _commitTableUndo();
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
    // 先提交尚未结束的表格编辑，避免之后提交时覆盖已恢复的状态
    _commitTableUndo();
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

  /// 上下箭头垂直移动光标
  ///
  /// 优先在当前节点内的可视行之间移动，位于首行（向上）或末行（向下）时切换到相邻节点；
  /// [forward] 为 true 向下移动，false 向上移动。
  /// 连续的垂直移动沿用同一横向坐标，避免经过较短的可视行或切换节点后光标列发生漂移。
  void _moveCaretVertically(String nodeId, {required bool forward}) {
    final controller = _controllers[nodeId];
    if (controller == null) return;

    final selection = controller.selection;
    // 存在文字选区时按方向折叠到选区一端，不产生跨行移动
    if (!selection.isCollapsed) {
      controller.selection = TextSelection.collapsed(offset: forward ? selection.end : selection.start);
      _preferredCaretX = null;
      return;
    }

    // 保留光标原有的亲和性，使自动换行处的光标落在正确的可视行上
    final TextPosition caretPosition = TextPosition(
      offset: selection.isValid ? selection.extentOffset.clamp(0, controller.text.length) : controller.text.length,
      affinity: selection.affinity,
    );
    final renderEditable = _findRenderEditable(nodeId);
    if (renderEditable == null || !renderEditable.attached) {
      // 节点尚未完成排版，无法换算可视行：退化为按节点整体跳转
      final double goalX = _preferredCaretX ?? 0.0;
      _preferredCaretX = _moveFocusToNeighbor(nodeId, forward: forward, caretX: goalX) ? goalX : null;
      return;
    }

    final Rect caretRect = renderEditable.getLocalRectForCaret(caretPosition);
    // 光标高度即当前行的行高，用于把探测点落到相邻行的垂直中心
    final double lineHeight = caretRect.height;
    // 首次垂直移动时记录当前横向坐标，连续移动沿用该值
    final double goalX = _preferredCaretX ?? caretRect.left;

    // 从当前行向上/下偏移一行得到探测点，再换算成该点处的文字位置
    final TextPosition probePosition = renderEditable.getPositionForPoint(
      renderEditable.localToGlobal(Offset(goalX, caretRect.center.dy + (forward ? lineHeight : -lineHeight))),
    );
    final Rect probeCaretRect = renderEditable.getLocalRectForCaret(probePosition);

    // 探测点仍落在当前行，说明已是首行/末行，切换到相邻节点
    if ((probeCaretRect.center.dy - caretRect.center.dy).abs() < lineHeight / 2) {
      _preferredCaretX = _moveFocusToNeighbor(nodeId, forward: forward, caretX: goalX) ? goalX : null;
      return;
    }

    // 探测点落在相邻行：把光标移到该行的对应横向位置
    _preferredCaretX = goalX;
    controller.selection = TextSelection.fromPosition(probePosition);
    _ensureCaretVisibleInViewport(nodeId);
  }

  /// 左右箭头在节点边界处切换相邻节点
  ///
  /// 光标位于节点文本开头时按左键切到上一节点并置于文本末尾，
  /// 位于文本末尾时按右键切到下一节点并置于文本开头。
  /// 返回 true 表示已切换节点；光标不在边界或已到达文档首/尾时返回 false。
  bool _moveCaretAcrossNodeBoundary(String nodeId, {required bool forward}) {
    final controller = _controllers[nodeId];
    if (controller == null) return false;

    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;

    // 光标未处于文本首/末位置时属于节点内部的横向移动，不切换节点
    final int textLength = controller.text.length;
    if (forward ? selection.extentOffset < textLength : selection.extentOffset > 0) return false;

    final flatList = _flatten();
    final currentIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    if (currentIndex == -1) return false;

    final targetIndex = forward ? currentIndex + 1 : currentIndex - 1;
    if (targetIndex < 0 || targetIndex >= flatList.length) return false;

    // 向右切换置于下一节点开头，向左切换置于上一节点末尾
    _focusNodeWithSelection(flatList[targetIndex].node.id, moveCursorToEnd: !forward);
    return true;
  }

  /// 把光标焦点切换到相邻节点，并把光标定位到指定横向坐标处
  ///
  /// 返回 true 表示成功切换；已到达文档首/尾时返回 false。
  bool _moveFocusToNeighbor(String nodeId, {required bool forward, required double caretX}) {
    final flatList = _flatten();
    final currentIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    if (currentIndex == -1) return false;

    final targetIndex = forward ? currentIndex + 1 : currentIndex - 1;
    if (targetIndex < 0 || targetIndex >= flatList.length) return false;

    // 向下切换定位到目标节点首行，向上切换定位到末行，保持光标在视觉上的连续
    _focusNodeAtCaretX(flatList[targetIndex].node.id, caretX, lastLine: !forward);
    return true;
  }

  /// 聚焦指定节点，并把光标定位到首行或末行的指定横向坐标处
  ///
  /// 节点尚未构建或排版未完成时，先聚焦并滚动，待下一帧排版完成后再定位。
  void _focusNodeAtCaretX(String nodeId, double caretX, {required bool lastLine}) {
    final focusNode = _focusNodes[nodeId];
    final controller = _controllers[nodeId];
    if (focusNode == null || controller == null) return;

    focusNode.requestFocus();
    _scrollToNode(nodeId);
    if (_applyCaretX(nodeId, caretX, lastLine: lastLine)) return;

    // 节点排版完成后重新定位，避免切换时目标节点尚未构建而丢失横向坐标
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyCaretX(nodeId, caretX, lastLine: lastLine);
    });
  }

  /// 按横向坐标定位节点光标（横向坐标相对文本内容左边缘）
  ///
  /// 返回 false 表示节点尚未排版（如节点还未构建进视口）。
  bool _applyCaretX(String nodeId, double caretX, {required bool lastLine}) {
    final controller = _controllers[nodeId];
    final renderEditable = _findRenderEditable(nodeId);
    if (controller == null || renderEditable == null || !renderEditable.attached) return false;

    // 向下切换定位到首行，向上切换定位到末行
    final TextPosition anchor = lastLine ? TextPosition(offset: controller.text.length) : const TextPosition(offset: 0);
    final Rect lineRect = renderEditable.getLocalRectForCaret(anchor);
    final TextPosition position = renderEditable.getPositionForPoint(
      renderEditable.localToGlobal(Offset(caretX, lineRect.center.dy)),
    );
    controller.selection = TextSelection.fromPosition(position);
    return true;
  }

  /// 聚焦指定节点并设置光标位置
  ///
  /// [ensureVisible] 为 true 时立即把节点滚动进视口：
  /// 节点可能位于视口之外而尚未构建，仅请求焦点不会带动视口，
  /// 因此交由 [_scrollToNode] 滚动并按需重试定位。
  void _focusNodeWithSelection(String nodeId, {required bool moveCursorToEnd, bool ensureVisible = true}) {
    final focusNode = _focusNodes[nodeId];
    final controller = _controllers[nodeId];
    if (focusNode == null || controller == null) return;

    focusNode.requestFocus();
    final offset = moveCursorToEnd ? controller.text.length : 0;
    controller.selection = TextSelection.fromPosition(TextPosition(offset: offset));

    if (ensureVisible) {
      _scrollToNode(nodeId);
    }
    _confirmNodeFocus(nodeId, moveCursorToEnd: moveCursorToEnd);
  }

  /// 在帧末确认焦点已落到指定节点
  ///
  /// 节点所在标签页尚未切换为当前页时处于不可聚焦的隐藏状态，
  /// 此时发起的焦点请求会被丢弃，需在切换完成后再补发请求并恢复光标位置。
  /// 同时可纠正同一指针操作中后续控件抢走焦点的情况。
  /// [retryCount] 为已补发次数，用尽后放弃，避免与其他焦点操作长期相互争抢。
  void _confirmNodeFocus(String nodeId, {required bool moveCursorToEnd, int retryCount = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusNode = _focusNodes[nodeId];
      final controller = _controllers[nodeId];
      if (focusNode == null || controller == null) return;
      if (focusNode.hasFocus || retryCount >= 2) return;

      focusNode.requestFocus();
      final offset = moveCursorToEnd ? controller.text.length : 0;
      controller.selection = TextSelection.fromPosition(TextPosition(offset: offset));
      _confirmNodeFocus(nodeId, moveCursorToEnd: moveCursorToEnd, retryCount: retryCount + 1);
    });
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

    // 首次进入滚动定位时，布局阶段的预修正机会已过，清除待修正标记
    if (retryCount == 0 && _pendingRevealNodeId == nodeId) {
      _pendingRevealNodeId = null;
    }

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
  ///
  /// 空白且无子节点的节点位于同级末尾时，换行改为提升该节点的层级。
  void _createSibling(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null) return;

    final siblings = location.parent?.children ?? _roots;
    final currentNode = siblings[location.index];
    final controller = _controllers[nodeId]!;
    final selection = controller.selection;
    final text = controller.text;
    final hasChildren = currentNode.children.isNotEmpty;

    // 空白节点位于同级末尾时，换行视为提升该空行的层级，而不是继续新增同级空节点
    if (text.isEmpty && !hasChildren && location.index == siblings.length - 1) {
      final canOutdent = location.parent != null && !_isTopicTopLevelNode(nodeId);
      if (canOutdent) {
        _outdentNode(nodeId);
        return;
      }
    }

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    // 光标在文本开头（且非空）：在当前节点上方插入空节点，将当前行下推
    if (selection.isCollapsed && selection.baseOffset == 0 && text.isNotEmpty) {
      final newNode = _createNode('');
      _ensureResources(newNode);
      siblings.insert(location.index, newNode);

      _scheduleRevealBeforePaint(newNode.id);
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
      // 样式区间随文本一起分割：前半段归前面的节点，后半段归后面的节点
      final rangesBefore = TextStyleRangeUtils.slice(currentNode.styleRanges, 0, selection.baseOffset);
      final rangesAfter = TextStyleRangeUtils.slice(currentNode.styleRanges, selection.baseOffset, text.length);

      if (hasChildren) {
        // 有子节点：在当前节点上方插入新节点承载前半部分，当前节点保留后半部分和子节点
        final newNode = _createNode(textBefore, styleRanges: rangesBefore);
        _ensureResources(newNode);
        siblings.insert(location.index, newNode);

        // 当前节点只保留后半段文本，样式区间同步裁剪到后半段
        currentNode.styleRanges = rangesAfter;
        controller.text = textAfter;
        currentNode.text = textAfter;
        if (controller is RichTextEditingController) {
          controller.styleRanges = rangesAfter;
        }

        // 新节点插入在当前节点上方，需保证当前节点插入后仍满足底部安全间距
        _scheduleRevealBeforePaint(currentNode.id);
        setState(() {});

        // 聚焦当前节点开头（光标后内容）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodeWithSelection(currentNode.id, moveCursorToEnd: false);
          _endBatchAndNotify(description: '创建同级节点', focusNodeId: currentNode.id, focusSelection: _selectionAtStart());
        });
        return;
      }

      // 无子节点：前半部分留当前节点，新节点在下方承载后半部分
      // 当前节点只保留前半段文本，样式区间同步裁剪到前半段
      currentNode.styleRanges = rangesBefore;
      controller.text = textBefore;
      currentNode.text = textBefore;
      if (controller is RichTextEditingController) {
        controller.styleRanges = rangesBefore;
      }

      final newNode = _createNode(textAfter, styleRanges: rangesAfter);
      _ensureResources(newNode);
      siblings.insert(location.index + 1, newNode);

      _scheduleRevealBeforePaint(newNode.id);
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

        _scheduleRevealBeforePaint(newNode.id);
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

      _scheduleRevealBeforePaint(newNode.id);
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

    _scheduleRevealBeforePaint(newNode.id);
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
  bool _canBatchIndentNode(String nodeId) => _canIndentNode(nodeId) && _indentTargetParent(nodeId) != null;

  /// 反缩进节点（提升一级，变成父节点的兄弟节点）
  void _outdentNode(String nodeId) {
    final location = _findLocation(nodeId);
    if (location == null || location.parent == null) return;
    // 主题视图的顶层节点不能移出当前主题
    if (_isTopicTopLevelNode(nodeId)) return;

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
    if (_isTopicTopLevelNode(nodeId)) return;

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
    if (location.parent == null && nodeToDelete.children.isEmpty && _roots.length == 1) {
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
  /// 将当前节点的文本追加到同级上一节点末尾，并删除当前节点，
  /// 两段文字的样式区间一并拼接保留，光标定位到合并处。
  /// 只有当前节点和同级上一节点都没有子节点时才允许合并。
  void _mergeWithPreviousNode(String nodeId) {
    final currentLocation = _findLocation(nodeId);
    // 没有同级上一节点时无法合并
    if (currentLocation == null || currentLocation.index <= 0) return;

    // 按树结构直接取同级上一节点，不依赖扁平列表中的相邻行
    final siblings = currentLocation.parent?.children ?? _roots;
    final previousNode = siblings[currentLocation.index - 1];
    final currentNode = siblings[currentLocation.index];

    // 只允许两个没有子节点的节点合并，避免把节点合并进有子节点的节点
    if (previousNode.children.isNotEmpty || currentNode.children.isNotEmpty) return;

    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    // 将当前节点的文本追加到上一节点末尾，记录合并位置（即上一节点原文本长度）
    final mergeOffset = previousNode.text.length;
    final mergedText = previousNode.text + currentNode.text;

    // 合并样式区间：上一节点的区间保持原位，当前节点的区间按合并位置整体后移
    final mergedStyleRanges = TextStyleRangeUtils.mergeAdjacent(<TextStyleRange>[
      ...previousNode.styleRanges,
      ...TextStyleRangeUtils.shift(currentNode.styleRanges, mergeOffset),
    ]);

    final previousController = _controllers[previousNode.id];
    if (previousController != null) {
      // 先同步样式区间再写入文本，避免合并后的文字丢失样式
      if (previousController is RichTextEditingController) {
        previousController.styleRanges = mergedStyleRanges;
      }
      previousController.text = mergedText;
    }
    previousNode.styleRanges = mergedStyleRanges;
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

  /// 获取节点的折叠动画控制器，不存在时按起始进度创建
  ///
  /// [startCollapsed] 为 true 表示从完全收起的状态（进度 0）开始播放展开动画，
  /// 否则从进度 1 开始播放收起动画
  AnimationController _ensureFoldController(String nodeId, {required bool startCollapsed}) {
    final existing = _foldAnimations[nodeId];
    if (existing != null) return existing;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: startCollapsed ? 0.0 : 1.0,
    );
    controller.addStatusListener((status) {
      // 动画到达两端后回归静态渲染，子节点行重新由展开状态决定是否展示
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        _finishFoldAnimation(nodeId, controller);
      }
    });
    _foldAnimations[nodeId] = controller;
    return controller;
  }

  /// 结束节点的折叠动画
  ///
  /// 先移除动画记录并重建列表，再在下一帧释放控制器，
  /// 避免节点行仍在监听已被销毁的控制器
  void _finishFoldAnimation(String nodeId, AnimationController controller) {
    if (_foldAnimations[nodeId] != controller) return;
    _foldAnimations.remove(nodeId);
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  /// 停止并释放全部折叠动画
  ///
  /// 整体展开/折叠时不逐个播放过渡，直接丢弃正在进行的折叠动画，
  /// 避免动画中的子节点行残留在列表里
  void _clearFoldAnimations() {
    final controllers = _foldAnimations.values.toList();
    _foldAnimations.clear();
    // 等本帧重建移除监听后再释放控制器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }

  /// 切换节点展开/折叠状态
  void _toggleExpand(String nodeId) {
    final node = _findNode(nodeId);
    if (node == null) return;
    final bool willExpand = !node.isExpanded;
    setState(() {
      node.isExpanded = willExpand;
    });

    // 有子节点时以动画呈现子节点收进圆点或从圆点展开；
    // 动画期间子节点行仍参与布局，结束后再按展开状态直接渲染
    if (node.children.isNotEmpty) {
      final controller = _ensureFoldController(nodeId, startCollapsed: willExpand);
      if (willExpand) {
        controller.forward();
      } else {
        controller.reverse();
      }
    }
    _saveFoldState();
  }

  /// 添加根节点
  ///
  /// 主题模式下新节点添加到当前主题的子节点末尾，否则添加到大纲根节点末尾。
  void _addRootNode() {
    // 开启批量操作，在操作完成后记录撤销项
    _undoManager.beginBatch();

    final OutlineNode? focusNode = _focusNode;
    final newNode = _createNode('');
    _ensureResources(newNode);
    if (focusNode != null) {
      // 主题视图中的“添加节点”即添加子主题，并展开父节点以便立即看到新节点
      focusNode.children.add(newNode);
      focusNode.isExpanded = true;
    } else {
      _roots.add(newNode);
    }
    _scheduleRevealBeforePaint(newNode.id);
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 滚动使新节点可见
      _focusAndScrollToNode(newNode.id, moveCursorToEnd: false);
      _endBatchAndNotify(
        description: focusNode == null ? '添加根节点' : '添加子主题',
        focusNodeId: newNode.id,
        focusSelection: _selectionAtStart(),
      );
    });
  }

  /// 展开当前视图中的所有节点
  void _expandAll() {
    void walk(OutlineNode node) {
      node.isExpanded = true;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _visibleRoots) {
      walk(root);
    }
    setState(() {});
    // 整体展开时丢弃进行中的折叠动画，子节点直接按展开状态渲染
    _clearFoldAnimations();
    _saveFoldState();
  }

  /// 折叠当前视图中的所有节点（仅保留根级节点可见）
  void _collapseAll() {
    void walk(OutlineNode node) {
      node.isExpanded = false;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _visibleRoots) {
      walk(root);
    }
    setState(() {});
    // 整体折叠时丢弃进行中的折叠动画，避免折叠中的子节点行残留
    _clearFoldAnimations();
    _saveFoldState();
  }

  // ================= 圆点拖拽排序 =================

  /// 圆点长按：开始拖拽排序
  ///
  /// 记录被拖拽的节点与指针位置，后续移动由 [_onDotDragMove] 刷新落点；
  /// 移动端给出震动反馈，提示已进入拖拽状态
  void _onDotDragStart(String nodeId, Offset globalPosition) {
    if (widget.readOnly || _isBatchSelectionMode) return;

    // 预加载抓取光标，加载完成后拖拽期间的鼠标样式自动切换
    unawaited(DragCursor.load());

    _reorderPointerPosition.value = globalPosition;
    setState(() {
      _reorderNodeId = nodeId;
      _reorderTarget = null;
    });
    if (PlatformCapabilities.isMobile) HapticFeedback.mediumImpact();
  }

  /// 圆点拖拽移动：刷新落点，并在指针进入视口上下边缘时自动滚动
  void _onDotDragMove(Offset globalPosition) {
    _reorderPointerPosition.value = globalPosition;
    _refreshReorderTarget(globalPosition);
    _updateEdgeAutoScroll(globalPosition, selectionUpdater: _refreshReorderTarget);
  }

  /// 按指针位置刷新拖拽落点
  ///
  /// 指针停住不动、仅视口自动滚动时同样按最新位置重新计算落点
  void _refreshReorderTarget(Offset globalPosition) {
    final draggedNodeId = _reorderNodeId;
    if (draggedNodeId == null) return;

    final target = _resolveReorderTarget(draggedNodeId, globalPosition);
    final previous = _reorderTarget;
    // 落点未变化时不重建，避免拖拽过程中无意义的刷新
    if (target == null && previous == null) return;
    if (target != null &&
        previous != null &&
        target.targetNodeId == previous.targetNodeId &&
        target.placement == previous.placement &&
        target.depth == previous.depth &&
        target.indicatorNodeId == previous.indicatorNodeId &&
        target.indicatorAbove == previous.indicatorAbove) {
      return;
    }
    setState(() => _reorderTarget = target);
  }

  /// 计算拖拽落点
  ///
  /// 纵向优先：指针位于目标行上半区时只有一种落点，即插到该行之前且层级不变；
  /// 指针位于下半区时，该行下方的间隙允许的层级从“下一可见行层级”到“该行的子级”，
  /// 再按指针的水平位置在这些层级中选择：落在该行圆点所在列时为该行层级，
  /// 每右移一列深一层，每左移一列浅一层，最终夹在允许范围内。
  /// 落点为被拖拽节点自身或其后代、放置后超出最大层级时返回 null
  _OutlineReorderTarget? _resolveReorderTarget(String draggedNodeId, Offset globalPosition) {
    final flatList = _flatten();
    if (flatList.isEmpty) return null;

    final index = _findNodeIndexAtPosition(globalPosition);
    if (index == null || index >= flatList.length) return null;

    final FlatNode hovered = flatList[index];
    final Rect? hoveredRect = _nodeTileGlobalRect(hovered.node.id);

    // 上半区：只有插到该行之前、层级不变这一种可能，横向位置不参与判定
    if (hoveredRect != null && globalPosition.dy < hoveredRect.center.dy) {
      if (!_isValidReorderTarget(draggedNodeId, hovered.node.id, hovered.depth)) return null;
      return _OutlineReorderTarget(
        targetNodeId: hovered.node.id,
        placement: _OutlineReorderPlacement.before,
        depth: hovered.depth,
        indicatorNodeId: hovered.node.id,
        indicatorAbove: true,
      );
    }

    // 下半区：间隙可选的层级范围从下一可见行层级（最浅）到该行的子级（最深）
    final int nextIndex = index + 1;
    final int shallowestDepth = nextIndex < flatList.length ? flatList[nextIndex].depth : 0;
    final int deepestDepth = hovered.depth + 1;
    final int desiredDepth = hovered.depth + _depthOffsetFromPointer(hovered, globalPosition);
    final int depth = desiredDepth < shallowestDepth
        ? shallowestDepth
        : (desiredDepth > deepestDepth ? deepestDepth : desiredDepth);

    // 最深一档：作为该行的第一个子节点
    if (depth == deepestDepth) {
      if (!_isValidReorderTarget(draggedNodeId, hovered.node.id, depth)) return null;
      return _OutlineReorderTarget(
        targetNodeId: hovered.node.id,
        placement: _OutlineReorderPlacement.firstChild,
        depth: depth,
        indicatorNodeId: hovered.node.id,
        indicatorAbove: false,
      );
    }

    // 其余档位：插到该层级的祖先行之后
    final FlatNode? ancestor = _ancestorAtDepth(flatList, index, depth);
    if (ancestor == null) return null;
    if (!_isValidReorderTarget(draggedNodeId, ancestor.node.id, depth)) return null;
    return _OutlineReorderTarget(
      targetNodeId: ancestor.node.id,
      placement: _OutlineReorderPlacement.after,
      depth: depth,
      indicatorNodeId: hovered.node.id,
      indicatorAbove: false,
    );
  }

  /// 按指针水平位置计算相对目标行的层级偏移
  ///
  /// 以该行圆点所在列的左边缘为基准，指针落在该列内偏移为 0（层级不变），
  /// 每右移一列深一层，每左移一列浅一层
  int _depthOffsetFromPointer(FlatNode row, Offset globalPosition) {
    final double? dotCenterX = _dotCenterGlobalX(row.node.id, row.depth, row.depth);
    if (dotCenterX == null) return 0;
    final double dotColumnLeft = dotCenterX - _indentWidth / 2;
    return ((globalPosition.dx - dotColumnLeft) / _indentWidth).floor();
  }

  /// 查找指定行在给定层级上的祖先行
  ///
  /// 行自身层级等于目标层级时返回该行，否则沿扁平列表向上找到最近的同层级行
  FlatNode? _ancestorAtDepth(List<FlatNode> flatList, int index, int depth) {
    for (int i = index; i >= 0; i--) {
      if (flatList[i].depth == depth) return flatList[i];
    }
    return null;
  }

  /// 判断落点是否有效
  ///
  /// 目标行不能是被拖拽节点自身或其后代，且放置后不能超出最大层级
  bool _isValidReorderTarget(String draggedNodeId, String targetNodeId, int depth) {
    if (targetNodeId == draggedNodeId) return false;
    if (_isDescendantNode(targetNodeId, draggedNodeId)) return false;
    return _canPlaceAtDepth(draggedNodeId, depth);
  }

  /// 判断被拖拽节点的子树放到指定深度后是否超出最大层级
  bool _canPlaceAtDepth(String nodeId, int depth) {
    final node = _findNode(nodeId);
    if (node == null) return false;
    return depth + _subtreeHeight(node) <= _maxDepth;
  }

  /// 判断节点是否为指定祖先节点的后代（不含自身）
  bool _isDescendantNode(String nodeId, String ancestorId) {
    final ancestor = _findNode(ancestorId);
    if (ancestor == null) return false;

    bool contains(OutlineNode parent) {
      for (final child in parent.children) {
        if (child.id == nodeId || contains(child)) return true;
      }
      return false;
    }

    return contains(ancestor);
  }

  /// 将节点移动到拖拽落点（不处理撤销记录与通知）
  void _applyReorder(String nodeId, _OutlineReorderTarget target) {
    final location = _findLocation(nodeId);
    if (location == null) return;

    final siblings = location.parent?.children ?? _roots;
    final node = siblings.removeAt(location.index);

    // 摘除节点后同级列表可能发生位移，按目标节点 ID 重新查找落点
    final targetLocation = _findLocation(target.targetNodeId);
    if (targetLocation == null) {
      // 目标节点已不存在，把节点放回原位置
      siblings.insert(location.index, node);
      return;
    }

    switch (target.placement) {
      case _OutlineReorderPlacement.before:
        final targetSiblings = targetLocation.parent?.children ?? _roots;
        targetSiblings.insert(targetLocation.index, node);
      case _OutlineReorderPlacement.after:
        final targetSiblings = targetLocation.parent?.children ?? _roots;
        targetSiblings.insert(targetLocation.index + 1, node);
      case _OutlineReorderPlacement.firstChild:
        final targetNode = (targetLocation.parent?.children ?? _roots)[targetLocation.index];
        targetNode.children.insert(0, node);
        // 放入子节点后展开目标节点，使新子节点可见
        targetNode.isExpanded = true;
    }
  }

  /// 圆点拖拽结束：存在有效落点时把节点移动到落点位置
  void _onDotDragEnd() {
    _stopEdgeAutoScroll();
    final draggedNodeId = _reorderNodeId;
    final target = _reorderTarget;
    _reorderPointerPosition.value = null;
    if (draggedNodeId == null) return;

    if (target == null) {
      setState(() {
        _reorderNodeId = null;
        _reorderTarget = null;
      });
      return;
    }

    // 拖拽排序属于结构变更，记录为一步可撤销操作
    _undoManager.beginBatch();
    _applyReorder(draggedNodeId, target);
    setState(() {
      _reorderNodeId = null;
      _reorderTarget = null;
    });
    _endBatchAndNotify(description: '拖拽排序节点');
  }

  /// 圆点拖拽取消：清理拖拽状态，不改变节点结构
  void _onDotDragCancel() {
    _stopEdgeAutoScroll();
    _reorderPointerPosition.value = null;
    if (_reorderNodeId == null && _reorderTarget == null) return;
    setState(() {
      _reorderNodeId = null;
      _reorderTarget = null;
    });
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
  ///
  /// 选区以子树为单位：范围内节点的全部子孙节点一并选中，
  /// 折叠状态下不可见的子节点同样包含在内。
  void _selectNodeRange(int startIndex, int endIndex) {
    final flatList = _flatten();
    if (flatList.isEmpty) return;

    final start = startIndex < endIndex ? startIndex : endIndex;
    final end = startIndex < endIndex ? endIndex : startIndex;

    final rangeIds = <String>{};
    for (int i = start; i <= end && i < flatList.length; i++) {
      rangeIds.add(flatList[i].node.id);
    }

    _selectedNodeIds
      ..clear()
      ..addAll(_expandWithDescendants(rangeIds));
    _selectAllLevel = 0;
    setState(() {});
    _notifyBatchChanged();
  }

  /// 收集节点及其全部子节点（含各级子孙）的 ID
  ///
  /// 遍历树结构收集子树，折叠状态下不可见的子孙节点同样包含在内。
  List<String> _collectSubtreeIds(String nodeId) => _expandWithDescendants([nodeId]).toList();

  /// 将节点集合扩展为包含其全部子孙节点的集合
  ///
  /// 深度优先遍历整棵树：集合中的节点连同各级子孙节点一并加入结果，
  /// 存在已包含祖先的节点同样加入，用于让节点选区始终覆盖完整子树。
  Set<String> _expandWithDescendants(Iterable<String> ids) {
    final seeds = ids.toSet();
    final result = <String>{};

    void walk(OutlineNode node, bool ancestorSelected) {
      final included = ancestorSelected || seeds.contains(node.id);
      if (included) {
        result.add(node.id);
      }
      for (final child in node.children) {
        walk(child, included);
      }
    }

    for (final root in _roots) {
      walk(root, false);
    }
    return result;
  }

  /// 清除指定节点的文本选区，光标停在选区尾部
  void _collapseNodeTextSelection(String nodeId) {
    final controller = _controllers[nodeId];
    if (controller == null || controller.selection.isCollapsed) return;
    controller.selection = TextSelection.collapsed(offset: controller.selection.extentOffset);
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

  /// 释放大纲内所有输入框的焦点
  ///
  /// 输入框失焦后不再参与焦点恢复，打开再关闭抽屉或卡片时不会重新唤起键盘
  void _releaseTextInputFocus() {
    if (_titleFocusNode.hasFocus) {
      _titleFocusNode.unfocus();
    }
    for (final focusNode in _focusNodes.values) {
      if (focusNode.hasFocus) {
        focusNode.unfocus();
      }
    }
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
    _updateEdgeAutoScroll(globalPosition, selectionUpdater: _onTrailingBarLongPressMove);
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

  /// 获取按文档顺序排列的选中节点（包含折叠状态下不可见的子孙节点）
  ///
  /// 深度优先遍历整棵树：选中的节点连同其全部子孙节点一并收集，
  /// 存在选中祖先的节点同样收集，用于复制时保留完整的子树结构。
  List<FlatNode> _getSelectedFlatNodesWithDescendants() {
    final result = <FlatNode>[];

    void walk(OutlineNode node, int depth, OutlineNode? parent, bool ancestorSelected) {
      final selected = ancestorSelected || _selectedNodeIds.contains(node.id);
      if (selected) {
        result.add(FlatNode(node: node, depth: depth, parent: parent));
      }
      for (final child in node.children) {
        walk(child, depth + 1, node, selected);
      }
    }

    for (final root in _roots) {
      walk(root, 0, null, false);
    }
    return result;
  }

  /// 处理 Ctrl/Cmd+A 全选操作
  ///
  /// 状态循环：未选区 → 全选当前主题 → 全选整个文档 → 取消全选
  /// 进入主题/文档选区时转移焦点到编辑器，取消时恢复到最近编辑的节点
  void _handleSelectAll(String focusedNodeId) {
    final flatList = _flatten();
    if (flatList.isEmpty) return;

    if (_selectAllLevel == 0) {
      // 全选当前节点及其全部子孙节点
      final focusIndex = flatList.indexWhere((f) => f.node.id == focusedNodeId);
      if (focusIndex == -1) return;

      _selectedNodeIds
        ..clear()
        ..addAll(_collectSubtreeIds(focusedNodeId));
      _selectAllLevel = 1;
      // 记录选区的起始锚点
      _selectionAnchorIndex = focusIndex;
      _activateNodeSelectionFocus();
    } else if (_selectAllLevel == 1) {
      // 全选整个文档
      _selectedNodeIds
        ..clear()
        ..addAll(_expandWithDescendants(flatList.map((f) => f.node.id)));
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
      _selectedNodeIds
        ..clear()
        ..addAll(_expandWithDescendants(flatList.map((f) => f.node.id)));
      _selectAllLevel = 2;
      _selectionAnchorIndex = 0;
      _activateNodeSelectionFocus();
      setState(() {});
      return;
    }

    // 无目标节点 → 全选所有节点
    if (nodeId == null) {
      _selectedNodeIds.addAll(_expandWithDescendants(flatList.map((f) => f.node.id)));
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
      // 文字已全选 → 选择当前节点及其全部子孙节点
      final focusIndex = flatList.indexWhere((f) => f.node.id == nodeId);
      if (focusIndex == -1) return;

      _selectedNodeIds
        ..clear()
        ..addAll(_collectSubtreeIds(nodeId));
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
    return flatList.isNotEmpty && flatList.every((f) => _selectedNodeIds.contains(f.node.id));
  }

  /// 是否仅选中了部分可见节点（有选中项但未全选）
  bool get isPartialNodesSelected {
    final flatList = _flatten();
    final selectedVisibleCount = flatList.where((f) => _selectedNodeIds.contains(f.node.id)).length;
    return selectedVisibleCount > 0 && selectedVisibleCount < flatList.length;
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
        _selectedNodeIds.addAll(_expandWithDescendants(_flatten().map((f) => f.node.id)));
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
    return _flatten().where((flat) => topLevelIds.contains(flat.node.id)).map((flat) => flat.node.id).toList();
  }

  /// 批量选中的节点是否可以缩进为子节点
  bool get canIndentSelectedNodes => _selectedTopLevelNodeIds().any(_canBatchIndentNode);

  /// 批量选中的节点是否可以提升层级
  bool get canOutdentSelectedNodes =>
      _selectedTopLevelNodeIds().any((id) => _findLocation(id)?.parent != null && !_isTopicTopLevelNode(id));

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
    // 主题视图的顶层节点保持在当前主题内，不参与批量提升；
    // 按文档逆序处理，使同级节点依次插入到父节点之后时仍保持原有先后顺序
    final targets = _selectedTopLevelNodeIdsInOrder()
        .where((id) => !_isTopicTopLevelNode(id))
        .toList()
        .reversed
        .toList();
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
  ///
  /// 只返回节点文字本身所在的渲染对象：附加备注区处于编辑状态时同样包含
  /// 可编辑文本，遍历时整体跳过，避免取到备注输入框的渲染对象。
  RenderEditable? _findRenderEditable(String nodeId) {
    final key = _nodeTileKeys[nodeId];
    final context = key?.currentContext;
    if (context == null) return null;
    final root = context.findRenderObject();
    if (root == null) return null;

    // 备注区根节点，遍历到它时不再向下查找
    final attachmentRoot = _attachmentKeys[nodeId]?.currentContext?.findRenderObject();
    RenderEditable? result;
    void visit(RenderObject child) {
      if (result != null || child == attachmentRoot) return;
      if (child is RenderEditable) {
        result = child;
        return;
      }
      child.visitChildren(visit);
    }

    visit(root);
    return result;
  }

  /// 获取节点瓦片的全局矩形
  ///
  /// 节点尚未构建或不在渲染树中时返回 null
  Rect? _nodeTileGlobalRect(String nodeId) {
    final renderBox = _nodeTileKeys[nodeId]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return null;
    return MatrixUtils.transformRect(renderBox.getTransformTo(null), Offset.zero & renderBox.size);
  }

  /// 判断全局坐标是否落在某节点行的圆点上
  ///
  /// 圆点处仅响应长按拖拽排序，编辑器级的拖拽选区不参与该指针，
  /// 避免指针的轻微移动先于长按识别被判定为拖拽而中断长按
  bool _isPositionOnNodeDot(Offset globalPosition) {
    final index = _findNodeIndexAtPosition(globalPosition);
    if (index == null) return false;

    final flatList = _flatten();
    if (index >= flatList.length) return false;

    final FlatNode flat = flatList[index];
    final Rect? tileRect = _nodeTileGlobalRect(flat.node.id);
    if (tileRect == null) return false;

    // 圆点位于列 (深度 + 1) 的中心，横向按半列宽判定热区
    final double dotCenterX = tileRect.left + 8 + (flat.depth + 1.5) * _indentWidth;
    return (globalPosition.dx - dotCenterX).abs() <= _indentWidth / 2;
  }

  /// 判断全局坐标是否落在某节点行的折叠箭头上
  ///
  /// 折叠箭头仅存在于有子节点的行，是切换展开/折叠的入口；
  /// 编辑器级的拖拽选区不参与该区域，避免指针的轻微移动抢走箭头的点击
  bool _isPositionOnNodeArrow(Offset globalPosition) {
    final index = _findNodeIndexAtPosition(globalPosition);
    if (index == null) return false;

    final flatList = _flatten();
    if (index >= flatList.length) return false;

    final FlatNode flat = flatList[index];
    if (flat.node.children.isEmpty) return false;

    final Rect? tileRect = _nodeTileGlobalRect(flat.node.id);
    if (tileRect == null) return false;

    // 箭头矩形按节点行内布局计算，左内边距 8 由节点行内容区施加
    final renderEditable = _findRenderEditable(flat.node.id);
    if (renderEditable == null || !renderEditable.attached) return false;
    final Rect arrowRect = OutlineNodeTile.foldArrowLocalRect(
      depth: flat.depth,
      indentWidth: _indentWidth,
      textLineHeight: renderEditable.preferredLineHeight,
    ).shift(Offset(tileRect.left + 8, tileRect.top));
    return arrowRect.contains(globalPosition);
  }

  /// 判断全局坐标是否落在大纲标题区域
  ///
  /// 标题不属于节点，位于其上的指针交互交由标题输入框自身处理，
  /// 编辑器级的选区、拖拽与焦点处理需要跳过该区域。
  bool _isPositionOnTitle(Offset globalPosition) {
    final renderBox = _titleFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return false;
    final rect = MatrixUtils.transformRect(renderBox.getTransformTo(null), Offset.zero & renderBox.size);
    return rect.contains(globalPosition);
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

  /// 判断全局坐标是否落在节点行的圆点与连接线指示区
  ///
  /// 指示区从一级节点竖线所在列的左边缘开始，到文本区起点为止；
  /// 该区域内的按下不参与节点选区，避免点击圆点或竖线时误选节点。
  bool _isPositionOnNodeIndicator(Offset globalPosition) {
    final index = _findNodeIndexAtPosition(globalPosition);
    if (index == null) return false;
    final flatList = _flatten();
    if (index < 0 || index >= flatList.length) return false;

    final flat = flatList[index];
    final renderBox = _nodeTileKeys[flat.node.id]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return false;

    final rect = MatrixUtils.transformRect(renderBox.getTransformTo(null), Offset.zero & renderBox.size);
    // 节点行内容左内边距为 8，一级节点竖线所在的列 1 自缩进一列处开始
    final indicatorLeft = rect.left + 8 + _indentWidth;
    final textAreaStartX = rect.left + 8 + (flat.depth + 2) * _indentWidth - _dotTextGapReduction;
    return globalPosition.dx >= indicatorLeft && globalPosition.dx < textAreaStartX;
  }

  /// 判断全局坐标是否在指定节点行的文本区域内
  ///
  /// 横向起点取圆点右边缘、终点取节点行右边缘，行首与文字之间的空白同样算作文本区；
  /// 纵向覆盖整个节点行，行下方的节点间距也归属于当前节点行的文本区，
  /// 从该处起拖同样拉出文本选区，不唤起节点选区。
  bool _isPositionWithinNodeText(String nodeId, Offset globalPosition) {
    final renderBox = _nodeTileKeys[nodeId]?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return false;

    final flatList = _flatten();
    final int index = flatList.indexWhere((flat) => flat.node.id == nodeId);
    if (index == -1) return false;

    final tileRect = MatrixUtils.transformRect(renderBox.getTransformTo(null), Offset.zero & renderBox.size);
    // 文本区起点 = 节点行内容左内边距 8 + 圆点左边缘 + 圆点直径
    final double textAreaStartX =
        tileRect.left +
        8 +
        OutlineNodeTile.dotLeftInsetForDepth(flatList[index].depth, indentWidth: _indentWidth) +
        OutlineConnectionMetrics.dotRadius * 2;

    return tileRect.contains(globalPosition) && globalPosition.dx >= textAreaStartX;
  }

  /// 判断全局坐标是否完全落在指定节点的文字行内
  ///
  /// 仅用于拖拽文本选区时判断指针是否已进入其他节点：节点行下方的间距不算进入文字行，
  /// 指针停留在间距时仍继续扩展文本选区，避免文字选区被节点选区抢占。
  bool _isPositionWithinNodeTextLine(String nodeId, Offset globalPosition) {
    final renderEditable = _findRenderEditable(nodeId);
    if (renderEditable == null || !renderEditable.attached) return false;
    final rect = MatrixUtils.transformRect(renderEditable.getTransformTo(null), Offset.zero & renderEditable.size);
    return globalPosition.dy >= rect.top && globalPosition.dy <= rect.bottom;
  }

  /// 判断全局坐标是否落在指定节点的附加备注区内
  bool _isPositionOnAttachmentOf(String nodeId, Offset globalPosition) {
    final RenderObject? renderObject = _attachmentKeys[nodeId]?.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final Rect rect = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & renderObject.size,
    );
    return rect.contains(globalPosition);
  }

  /// 判断全局坐标是否落在任意节点的附加备注区内
  ///
  /// 备注区包含图片缩略图与备注输入框，指针落在其中时编辑器的拖拽选区手势
  /// 需要让出，保证备注文字选中、图片点击等交互不被节点选区抢走。
  bool _isPositionOnNodeAttachment(Offset globalPosition) {
    for (final String nodeId in _attachmentKeys.keys) {
      if (_isPositionOnAttachmentOf(nodeId, globalPosition)) return true;
    }
    return false;
  }

  /// 判断全局坐标是否落在某个节点的表格区域内
  ///
  /// 表格拥有自己的单元格右键格式栏，需要让节点右键菜单在该区域让出。
  bool _isPositionOnNodeTable(Offset globalPosition) {
    for (final GlobalKey key in _tableKeys.values) {
      final RenderObject? renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final Rect rect = MatrixUtils.transformRect(
        renderObject.getTransformTo(null),
        Offset.zero & renderObject.size,
      );
      if (rect.contains(globalPosition)) return true;
    }
    return false;
  }

  /// 判断全局坐标是否落在滚动条所在的右侧条带上
  ///
  /// 滚动条 thumb 位于可滚动区域的右边缘，宽度等于 [editorScrollbarThickness]。
  /// 指针落在该条带时，编辑器的拖拽选区手势应让位于滚动条自身的拖拽与点击交互。
  bool _isPositionOnScrollbar(Offset globalPosition) {
    final renderObject = _scrollbarKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final rect = MatrixUtils.transformRect(renderObject.getTransformTo(null), Offset.zero & renderObject.size);
    return globalPosition.dx >= rect.right - editorScrollbarThickness &&
        globalPosition.dx <= rect.right &&
        globalPosition.dy >= rect.top &&
        globalPosition.dy <= rect.bottom;
  }

  // ================= 指针事件与拖拽选区 =================

  /// 指针按下：记录起始位置用于后续判断是否为点击
  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;

    // 指针按下会重新定位光标，之前按方向键记录的横向坐标不再适用
    _preferredCaretX = null;

    // 新的指针序列开始，重置上一次手势的竞技场结果
    _panGestureAccepted = false;

    // 标题区域不参与节点选区与编辑器级焦点处理，交互交由标题输入框自身处理
    if (_isPositionOnTitle(event.position)) {
      _dragStartPosition = null;
      _dragMode = _DragMode.none;
      return;
    }

    // 指针落在滚动条区域时跳过编辑器自身的指针处理，让滚动条正常响应点击与拖拽
    if (_isPositionOnScrollbar(event.position)) {
      _dragStartPosition = null;
      return;
    }

    // 指针落在节点附加备注区时跳过编辑器级处理，交互交由备注输入框、图片与表格控件
    if (_isPositionOnNodeAttachment(event.position)) {
      _dragStartPosition = null;
      _dragMode = _DragMode.none;
      _restoreEditorFocusIfIdle();
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
      final startPosition = _dragStartPosition!;
      // 备注区内的点击由备注控件处理，不在此清除节点选区或抢占焦点
      if (_isPositionOnNodeAttachment(startPosition)) {
        _dragStartPosition = null;
        return;
      }
      // 批量选择模式下节点选中由节点行自身处理，不在此处清除节点选区
      if (!_isBatchSelectionMode) {
        if (_isPositionOnTextField(startPosition)) {
          // 拖拽手势赢得竞技场时输入框收不到点击，按按下位置补上光标定位
          if (_panGestureAccepted) {
            _placeCaretAtPosition(startPosition);
          }
        } else {
          _clearSelection();
          // 点击空白区域时，若无输入框持有焦点，则请求编辑器级焦点
          // 确保撤销/恢复等快捷键在空白区域也能正常响应
          if (!_focusNodes.values.any((fn) => fn.hasFocus)) {
            _editorFocusNode.requestFocus();
          }
        }
      }
    }
    _dragStartPosition = null;
  }

  /// 将光标定位到指定全局坐标并聚焦对应节点
  ///
  /// 按坐标命中目标节点后，将其文本偏移换算为折叠选区，
  /// 节点未持有焦点时一并请求焦点
  void _placeCaretAtPosition(Offset globalPosition) {
    final index = _findNodeIndexAtPosition(globalPosition);
    if (index == null) return;
    final flatList = _flatten();
    if (index >= flatList.length) return;

    final nodeId = flatList[index].node.id;
    final controller = _controllers[nodeId];
    final focusNode = _focusNodes[nodeId];
    final renderEditable = _findRenderEditable(nodeId);
    if (controller == null ||
        focusNode == null ||
        renderEditable == null ||
        !renderEditable.attached) {
      return;
    }

    controller.selection = TextSelection.collapsed(
      offset: renderEditable.getPositionForPoint(globalPosition).offset,
    );
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }
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

    // 标题区域不参与节点拖拽选区
    if (_isPositionOnTitle(details.globalPosition)) return;

    // 拖拽手势已赢得竞技场，输入框本次收不到点击
    _panGestureAccepted = true;

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
    _updateEdgeAutoScroll(globalPosition, selectionUpdater: _updateDragSelection);
    _updateDragSelection(globalPosition);
  }

  /// 按指针位置更新拖拽选区
  ///
  /// 统一选区逻辑：
  /// - 起始位置在节点行的文本区内时先做文本选区，指针完全进入其他节点的文字行后才切换为节点选区
  /// - 起始位置在圆点、竖线之外的空白区域时，上下拖拽超过阈值后做节点选区
  /// - 起始位置在圆点与竖线指示区内时不唤起节点选区
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
      final startPosition = _dragStartPosition;
      final startInText = startPosition != null && _isPositionWithinNodeText(_dragStartNodeId!, startPosition);
      if (startInText) {
        // 起始位置在文本内：进入文本选区模式
        _dragMode = _DragMode.text;
        final renderEditable = _findRenderEditable(_dragStartNodeId!);
        if (renderEditable != null && renderEditable.attached) {
          _dragTextAnchor = renderEditable.getPositionForPoint(startPosition);
        }
        // 让起始节点获得焦点，确保文本选区可见
        _focusNodes[_dragStartNodeId!]?.requestFocus();
      } else if (startPosition != null && !_isPositionOnNodeIndicator(startPosition)) {
        // 起始位置在圆点与竖线之外的空白区域：上下拖拽距离达到阈值后才进入节点选区模式
        if (!_hasReachedNodeSelectionDragThreshold(globalPosition)) return;
        _dragMode = _DragMode.node;
        _selectAllLevel = 0;
        _activateNodeSelectionFocus();
      } else {
        // 起始位置在圆点与竖线指示区内：不唤起节点选区
        return;
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
        // 仅当指针完全进入其他节点的文字行时才从文本选区切换为节点选区，
        // 停留在起始节点行内（含行下方的节点间距）时始终扩展文本选区
        final currentIndex = _findNodeIndexAtPosition(globalPosition);
        final int? otherNodeIndex = currentIndex != _dragStartIndex ? currentIndex : null;
        final bool enteredOtherNode =
            otherNodeIndex != null &&
            _isPositionWithinNodeTextLine(_flatten()[otherNodeIndex].node.id, globalPosition);
        if (!enteredOtherNode) {
          _extendTextSelection(_dragStartNodeId!, _dragTextAnchor!, globalPosition);
        } else {
          // 完全进入其他节点的文字行：切换到节点选区
          _dragMode = _DragMode.node;
          _selectAllLevel = 0;
          _activateNodeSelectionFocus();
          _selectNodeRange(_dragStartIndex!, otherNodeIndex);
        }
      }
    } else if (_dragMode == _DragMode.node) {
      // 回到起始节点行时，从节点选区恢复到文本选区
      final currentIndex = _findNodeIndexAtPosition(globalPosition);
      final backToStartText = _dragTextAnchor != null && currentIndex == _dragStartIndex;
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

  /// 判断指针相对拖拽起点在垂直方向上的移动距离是否已达到唤起节点选区的阈值
  ///
  /// 仅统计上下移动，纯水平移动不会唤起节点选区
  bool _hasReachedNodeSelectionDragThreshold(Offset globalPosition) {
    final startPosition = _dragStartPosition;
    if (startPosition == null) return false;
    return (globalPosition.dy - startPosition.dy).abs() >= _nodeSelectionDragThreshold;
  }

  /// 拖拽结束：清理拖拽状态
  void _onPanEnd(DragEndDetails details) {
    _stopEdgeAutoScroll();
    _panGestureAccepted = false;
    _dragStartPosition = null;
    _dragMode = _DragMode.none;
    _dragTextAnchor = null;
    _dragStartNodeId = null;
    _dragStartIndex = null;
  }

  /// 拖拽取消：清理拖拽状态
  void _onPanCancel() {
    _stopEdgeAutoScroll();
    _panGestureAccepted = false;
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

  /// 获取光标所在字符的样式标记
  ///
  /// 光标落在两个字符之间时取右侧字符，落在文本末尾时取最后一个字符；
  /// 文本为空时返回空样式。
  TextStyleFlags _getCaretStyleFlags(OutlineNode node, TextSelection selection) {
    if (node.text.isEmpty) return TextStyleFlags.none;
    final int index = selection.start >= node.text.length ? node.text.length - 1 : selection.start;
    var flags = TextStyleFlags.none;
    for (final r in node.styleRanges) {
      if (index >= r.start && index < r.end) {
        flags = flags.merge(r.flags);
      }
    }
    return flags;
  }

  /// 获取右键菜单展示用的文字样式标记
  ///
  /// 单节点且无选中文字时只取光标所在字符的样式，
  /// 避免整段文本中其他区间的样式把菜单图标错误点亮；
  /// 其余情况沿用 [_getSelectionFlags] 的合并逻辑。
  TextStyleFlags _getContextMenuStyleFlags(List<OutlineNode> nodes, TextSelection? selection) {
    if (nodes.length != 1 || selection == null || !selection.isValid || !selection.isCollapsed) {
      return _getSelectionFlags(nodes, selection);
    }
    return _getCaretStyleFlags(nodes.first, selection);
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

  /// 获取右键菜单展示用的颜色
  ///
  /// 单节点且无选中文字时只取光标所在字符的颜色，
  /// 避免整段文本中其他区间的颜色被错误标记为当前颜色；
  /// 其余情况沿用 [_getCurrentColor] 的合并逻辑。
  /// [isForeground] 为 true 时查询字体颜色，false 时查询字底颜色。
  ({bool isUniform, Color? color}) _getContextMenuColor(
    List<OutlineNode> nodes,
    TextSelection? selection,
    bool isForeground,
  ) {
    if (nodes.length != 1 || selection == null || !selection.isValid || !selection.isCollapsed) {
      return _getCurrentColor(nodes, selection, isForeground);
    }
    final flags = _getCaretStyleFlags(nodes.first, selection);
    return (isUniform: true, color: isForeground ? flags.foregroundColor : flags.backgroundColor);
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

    final TextSelection? selection = nodes.length == 1 ? _controllers[nodeIds.first]?.selection : null;

    _undoManager.beginBatch();
    setState(() {
      for (final node in nodes) {
        node.headingLevel = level;
      }
    });
    _endBatchAndNotify(description: '设置标题级别', focusNodeId: nodeIds.first, focusSelection: selection);
  }

  /// 将当前节点的样式应用到全部同级节点
  ///
  /// 样式包括标题级别，以及当前节点整个文本合并后的文字样式
  /// （加粗/斜体/下划线/删除线、字体颜色、字底颜色）。
  /// 同级节点以统一样式覆盖全部文本，当前节点本身保持不变。
  void _applyStyleToSiblings(String nodeId) {
    final sourceNode = _findNode(nodeId);
    if (sourceNode == null) return;

    final siblingIds = _getSiblingNodeIds(nodeId);
    if (siblingIds.length <= 1) return;

    // 合并当前节点整个文本的样式，作为同级节点的统一样式
    final sourceFlags = _getSelectionFlags([sourceNode], null);
    final TextSelection? selection = _controllers[nodeId]?.selection;

    _undoManager.beginBatch();
    setState(() {
      for (final siblingId in siblingIds) {
        if (siblingId == nodeId) continue;
        final sibling = _findNode(siblingId);
        if (sibling == null) continue;

        sibling.headingLevel = sourceNode.headingLevel;
        // 统一样式覆盖同级节点全部文本；空样式表示清除所有文字样式
        sibling.styleRanges = sourceFlags.isEmpty
            ? []
            : [TextStyleRange(start: 0, end: sibling.text.length, flags: sourceFlags)];

        final controller = _controllers[siblingId];
        if (controller is RichTextEditingController) {
          controller.styleRanges = sibling.styleRanges;
        }
      }
    });
    _endBatchAndNotify(description: '应用样式到同级节点', focusNodeId: nodeId, focusSelection: selection);
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
  TextStyleFlags get currentTextStyleFlags => _getSelectionFlags(_toolbarTargetNodes, _toolbarTargetSelection);

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
    return nodeId != null && _findLocation(nodeId)?.parent != null && !_isTopicTopLevelNode(nodeId);
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
  }) => _applyColor(
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

    final bool autoComplete = symbol.isPairStart && SettingsService.instance.punctuationAutoCompleteEnabled;

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
    _endBatchAndNotify(description: '插入标点符号', focusNodeId: nodeId, focusSelection: controller.selection);
  }

  /// 活动节点是否可以添加关联
  ///
  /// 关联文本仅作用于节点内的文字选区，没有选区时不可用。
  bool get canAddLinkForActiveNode {
    final nodeId = _activeNodeId;
    final selection = nodeId == null ? null : _controllers[nodeId]?.selection;
    return selection != null && selection.isValid && !selection.isCollapsed;
  }

  /// 活动节点是否已插入表格
  ///
  /// 每个节点最多保留一个表格，已有表格时不可再次插入。
  bool get activeNodeHasTable {
    final nodeId = _activeNodeId;
    return nodeId != null && _findNode(nodeId)?.table != null;
  }

  /// 为活动节点选中的文字打开关联目标选择弹窗
  void showLinkDialogForActiveNode() {
    final nodeId = _activeNodeId;
    if (nodeId != null) _showLinkDialog(nodeId);
  }

  /// 开始编辑活动节点的备注
  void startNoteEditingForActiveNode() {
    final nodeId = _activeNodeId;
    if (nodeId != null) _startNoteEditing(nodeId);
  }

  /// 为活动节点选择并插入图片
  void pickImageForActiveNode() {
    final nodeId = _activeNodeId;
    if (nodeId != null) _pickImageForNode(nodeId);
  }

  /// 为活动节点插入表格
  void insertTableForActiveNode() {
    final nodeId = _activeNodeId;
    if (nodeId != null) _insertTableForNode(nodeId);
  }

  // ================= 剪贴板操作 =================

  /// 剪切指定节点内选中的文本（含文字样式）
  ///
  /// 返回是否存在可剪切的文本选区。
  bool _cutNodeTextSelection(String nodeId) {
    final controller = _controllers[nodeId];
    final node = _findNode(nodeId);
    if (controller == null || node == null) return false;

    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return false;
    final start = selection.start.clamp(0, controller.text.length);
    final end = selection.end.clamp(0, controller.text.length);
    if (start >= end) return false;

    final selectedText = controller.text.substring(start, end);
    final selectedRanges = TextStyleRangeUtils.slice(node.styleRanges, start, end);
    unawaited(RichClipboard.write(
      plainText: selectedText,
      htmlFragment: OutlineHtmlCodec.serializeInline(
        selectedText,
        selectedRanges,
        headingLevel: node.headingLevel,
      ),
    ));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();

    // 删除选中文本并同步调整样式区间，使剩余文字的样式保持不变
    final newText = controller.text.substring(0, start) + controller.text.substring(end);
    node.styleRanges = TextStyleRangeUtils.adjustForDeletion(node.styleRanges, start, end);
    (controller as RichTextEditingController).styleRanges = node.styleRanges;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start),
    );
    node.text = newText;
    _notifyContentChanged();
    return true;
  }

  /// 复制指定节点内选中的文本（含文字样式）
  ///
  /// 返回是否存在可复制的文本选区。
  bool _copyNodeTextSelection(String nodeId) {
    final controller = _controllers[nodeId];
    final node = _findNode(nodeId);
    if (controller == null || node == null) return false;

    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return false;
    final start = selection.start.clamp(0, controller.text.length);
    final end = selection.end.clamp(0, controller.text.length);
    if (start >= end) return false;

    final selectedText = controller.text.substring(start, end);
    final selectedRanges = TextStyleRangeUtils.slice(node.styleRanges, start, end);
    unawaited(RichClipboard.write(
      plainText: selectedText,
      htmlFragment: OutlineHtmlCodec.serializeInline(
        selectedText,
        selectedRanges,
        headingLevel: node.headingLevel,
      ),
    ));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();
    return true;
  }

  /// 剪切右键菜单目标节点的选中文本
  void _handleCutText() {
    final nodeId = _contextMenuNodeId;
    if (nodeId != null) _cutNodeTextSelection(nodeId);
  }

  /// 复制右键菜单目标节点的选中文本
  void _handleCopyText() {
    final nodeId = _contextMenuNodeId;
    if (nodeId != null) _copyNodeTextSelection(nodeId);
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
    final start = selection.start.clamp(0, controller.text.length);
    final end = selection.end.clamp(0, controller.text.length);
    if (start >= end) return;

    // 删除选中文本并同步调整样式区间，使剩余文字的样式保持不变
    final newText = controller.text.substring(0, start) + controller.text.substring(end);
    node.styleRanges = TextStyleRangeUtils.adjustForDeletion(node.styleRanges, start, end);
    (controller as RichTextEditingController).styleRanges = node.styleRanges;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start),
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

  /// 复制选中节点到剪贴板（纯文本保留缩进，HTML 保留结构与文字样式）
  ///
  /// 复制内容包含选中节点的全部子孙节点，折叠状态下不可见的子节点同样会被复制。
  void _copySelectedNodes() {
    final selectedNodes = _getSelectedFlatNodesWithDescendants();
    if (selectedNodes.isEmpty) return;

    final text = _serializeNodes(selectedNodes);
    unawaited(RichClipboard.write(
      plainText: text,
      htmlFragment: OutlineHtmlCodec.serializeNodes(selectedNodes),
    ));
    // 同步标记剪贴板已有内容，避免下次右键菜单的"粘贴"项被错误禁用
    ClipboardStateCache.markHasContent();
  }

  /// 剪切选中节点：复制后删除
  ///
  /// 复制内容包含选中节点的全部子孙节点，折叠状态下不可见的子节点同样会被复制。
  void _cutSelectedNodes() {
    final selectedNodes = _getSelectedFlatNodesWithDescendants();
    if (selectedNodes.isEmpty) return;

    final text = _serializeNodes(selectedNodes);
    unawaited(RichClipboard.write(
      plainText: text,
      htmlFragment: OutlineHtmlCodec.serializeNodes(selectedNodes),
    ));
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
        _endBatchAndNotify(description: '删除选中节点', focusNodeId: targetId, focusSelection: _selectionAtEnd(targetId!));
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
  /// 优先读取剪贴板中的富文本 HTML，保留文字样式、标题级别与列表层级；
  /// 无 HTML 时按带缩进的纯文本解析。先删除所有选中节点，
  /// 在第一个选中节点的位置插入解析出的新节点。
  Future<void> _pasteNodes() async {
    if (_selectedNodeIds.isEmpty) return;

    final pastedNodes = await _readClipboardNodes();
    if (pastedNodes.isEmpty || !mounted) return;
    if (_selectedNodeIds.isEmpty) return;

    final selectedNodes = _getSelectedFlatNodes();
    if (selectedNodes.isEmpty) return;

    final firstSelected = selectedNodes.first;
    final firstLocation = _findLocation(firstSelected.node.id);
    if (firstLocation == null) return;

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

    for (final newNode in pastedNodes) {
      _ensureResourcesForNode(newNode);
      siblings.insert(insertIndex, newNode);
      insertIndex++;
    }

    setState(() {});

    // 聚焦到第一个新节点
    final firstNodeId = pastedNodes.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodeWithSelection(firstNodeId, moveCursorToEnd: false);
      _endBatchAndNotify(description: '粘贴节点', focusNodeId: firstNodeId, focusSelection: _selectionAtStart());
    });
  }

  /// 粘贴内容到指定节点的光标位置
  ///
  /// 单个节点直接插入到光标位置（替换选区），文字样式随插入内容保留；
  /// 多个节点按行创建新节点，层级随 HTML 列表结构或文本缩进还原。
  Future<void> _pasteIntoNode(String nodeId) async {
    final pastedNodes = await _readClipboardNodes();
    if (pastedNodes.isEmpty || !mounted) return;

    final location = _findLocation(nodeId);
    if (location == null) return;
    final siblings = location.parent?.children ?? _roots;
    if (location.index >= siblings.length) return;
    final currentNode = siblings[location.index];
    final controller = _controllers[nodeId];
    if (controller is! RichTextEditingController) return;

    // 单节点粘贴：文本插入光标位置，样式区间一并拼接
    if (pastedNodes.length == 1 && pastedNodes.first.children.isEmpty) {
      _insertNodeAtCursor(controller, currentNode, pastedNodes.first);
      return;
    }

    // 多节点粘贴涉及节点结构变化，开启批量操作
    _undoManager.beginBatch();

    final selection = controller.selection;
    final selStart = selection.start >= 0 ? selection.start : 0;
    final selEnd = selection.end >= 0 ? selection.end : controller.text.length;
    final textBefore = controller.text.substring(0, selStart);
    final textAfter = controller.text.substring(selEnd);

    // 光标前后的文本需要分别切分样式，避免样式随文字移动后错位
    final prefixRanges = TextStyleRangeUtils.slice(currentNode.styleRanges, 0, selStart);
    final tailRanges = TextStyleRangeUtils.slice(currentNode.styleRanges, selEnd, controller.text.length);

    final firstNode = pastedNodes.first;

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
    for (int i = 1; i < pastedNodes.length; i++) {
      pastedSiblings.add(pastedNodes[i]);
    }

    // 光标后的剩余文本作为新节点追加到末尾（不属于粘贴内容）
    final nodesToInsert = <OutlineNode>[];
    nodesToInsert.addAll(pastedSiblings);
    if (textAfter.isNotEmpty) {
      final tailNode = _createNode(textAfter);
      tailNode.styleRanges = tailRanges;
      nodesToInsert.add(tailNode);
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

    // 第一个节点的文本合并到当前节点光标位置，样式按插入位置拼接
    // 空节点接收带标题级别的内容时沿用其标题级别
    if (controller.text.isEmpty && firstNode.headingLevel > 0) {
      currentNode.headingLevel = firstNode.headingLevel;
    }
    final currentNewText = textBefore + firstNode.text;
    currentNode.styleRanges = TextStyleRangeUtils.mergeAdjacent(<TextStyleRange>[
      ...prefixRanges,
      ...TextStyleRangeUtils.shift(firstNode.styleRanges, selStart),
    ]);
    controller.text = currentNewText;
    controller.styleRanges = currentNode.styleRanges;
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
  }

  /// 在控制器光标位置插入粘贴节点的文本（替换当前选区），保留文字样式
  void _insertNodeAtCursor(
    RichTextEditingController controller,
    OutlineNode node,
    OutlineNode pasted,
  ) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start >= 0 ? selection.start : 0;
    final end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.substring(0, start) + pasted.text + text.substring(end);
    // 原文本前缀/后缀样式与粘贴内容样式按插入位置拼接
    final ranges = TextStyleRangeUtils.mergeAdjacent(<TextStyleRange>[
      ...TextStyleRangeUtils.slice(node.styleRanges, 0, start),
      ...TextStyleRangeUtils.shift(pasted.styleRanges, start),
      ...TextStyleRangeUtils.shift(
        TextStyleRangeUtils.slice(node.styleRanges, end, text.length),
        start + pasted.text.length,
      ),
    ]);

    // 空节点接收带标题级别的内容时沿用其标题级别
    final bool headingChanged = text.isEmpty && pasted.headingLevel > 0;
    if (headingChanged) {
      node.headingLevel = pasted.headingLevel;
    }

    node.styleRanges = ranges;
    node.text = newText;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + pasted.text.length),
    );
    controller.styleRanges = ranges;
    // 标题级别影响节点整行的字号，需要重建节点行
    if (headingChanged) setState(() {});
    _notifyContentChanged();
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

  /// 读取剪贴板并转换为节点列表
  ///
  /// 优先使用剪贴板中的富文本 HTML，保留文字样式、标题级别和列表层级；
  /// 剪贴板不含 HTML 时回退为按缩进解析的纯文本。
  Future<List<OutlineNode>> _readClipboardNodes() async {
    final content = await RichClipboard.read();

    final html = content.html;
    if (html != null && html.isNotEmpty) {
      final parsed = OutlineHtmlCodec.parseHtml(html, maxDepth: _maxDepth);
      if (parsed.isNotEmpty) return _buildNodesFromParsed(parsed);
    }

    final text = content.text;
    if (text == null || text.isEmpty) return const [];
    // 统一换行符后按行分割，过滤空白行
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const [];
    return _parseNodesFromText(lines);
  }

  /// 将解析结果批量转换为编辑器节点
  List<OutlineNode> _buildNodesFromParsed(List<ParsedOutlineNode> parsed) =>
      parsed.map(_buildNodeFromParsed).toList();

  /// 将单个解析结果递归转换为编辑器节点
  OutlineNode _buildNodeFromParsed(ParsedOutlineNode parsed) {
    final node = _createNode(parsed.text);
    node.headingLevel = parsed.headingLevel;
    node.styleRanges = List.of(parsed.styleRanges);
    for (final child in parsed.children) {
      node.children.add(_buildNodeFromParsed(child));
    }
    return node;
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
        // 落在关联文本内部时把光标移到关联文本末尾，避免光标停在关联文本中间
        final offset = _snapOffsetOutOfLink(
          nodeId,
          renderEditable.getPositionForPoint(position).offset,
        );
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
  /// 避免菜单关闭后焦点先回到菜单所在节点造成光标闪烁。
  /// 点击节点用于关闭菜单表示回到单点编辑，同时取消多节点选区与菜单目标节点残留的文本选区
  /// （批量选择模式下节点选中由节点行自身切换，不在此清除）
  void _syncCursorAndFocusAfterMenuDismiss(PointerDownEvent event) {
    final nodeIndex = _findNodeIndexAtPosition(event.position);
    if (nodeIndex == null) return;

    if (!_isBatchSelectionMode) {
      _clearSelection();
    }

    final flatList = _flatten();
    final nodeId = flatList[nodeIndex].node.id;

    // 菜单显示期间菜单自身持有焦点，菜单目标节点失焦后仍保留文本选区以维持高亮；
    // 点击其他节点关闭菜单时该节点不会再重新获得焦点，需在此清除其选区，避免高亮残留
    final menuNodeId = _contextMenuNodeId;
    if (menuNodeId != null && menuNodeId != nodeId) {
      _collapseNodeTextSelection(menuNodeId);
    }

    final controller = _controllers[nodeId];
    final focusNode = _focusNodes[nodeId];
    final renderEditable = _findRenderEditable(nodeId);
    if (controller == null || focusNode == null || renderEditable == null || !renderEditable.attached) {
      return;
    }

    // 立即将光标定位到点击位置
    final offset = _snapOffsetOutOfLink(
      nodeId,
      renderEditable.getPositionForPoint(event.position).offset,
    );
    controller.selection = TextSelection.collapsed(offset: offset);

    // 请求目标节点焦点，覆盖 _handleContextMenuDismissed 对旧节点的焦点请求
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }
  }

  /// 构建文字样式相关的菜单项
  ///
  /// 包含标题级别行、文字样式行、字体颜色与字底颜色；
  /// 节点右键菜单与主题标题右键菜单共用这部分内容。
  List<ContextMenuItem> _buildStyleContextMenuItems(String? nodeId) {
    final controller = nodeId != null ? _controllers[nodeId] : null;
    final bool hasNodeSelection = _selectedNodeIds.isNotEmpty;
    final bool isReadOnly = widget.readOnly;
    final bool hasTarget = nodeId != null && controller != null;

    // 计算当前选区/节点的颜色，用于子菜单高亮
    final targetIds = _getStyleTargetNodeIds(nodeId);
    final targetNodes = targetIds.map((id) => _findNode(id)).whereType<OutlineNode>().toList();
    final TextSelection? styleSelection = targetIds.length == 1 ? _controllers[targetIds.first]?.selection : null;
    final currentFg = _getContextMenuColor(targetNodes, styleSelection, true);
    final currentBg = _getContextMenuColor(targetNodes, styleSelection, false);

    return [
      // 标题/正文格式行
      ContextMenuItem(label: _buildHeadingRow(nodeId), enabled: false),
      // 文字样式行
      ContextMenuItem(label: _buildFormatRow(nodeId), enabled: false),

      ContextMenuItem.divider(),

      // 字体颜色
      ContextMenuItem(
        labelText: '字体颜色',
        iconBuilder: (color) => OutlineColorPalette.buildColorBarIcon(Icons.format_color_text, color, Colors.red),
        children: [
          for (final c in OutlineColorPalette.colors)
            ContextMenuItem(
              // 当前颜色与该色板一致时，文字前加 '·' 标记
              labelText: currentFg.isUniform && currentFg.color == c.foreground ? '· ${c.name}' : c.name,
              iconBuilder: (_) => OutlineColorPalette.buildColorSwatchIcon(c.foreground),
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
            iconBuilder: (_) => OutlineColorPalette.buildColorSwatchIcon(widget.colorScheme.onSurface),
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
        iconBuilder: (color) => OutlineColorPalette.buildColorBarIcon(Icons.format_color_fill, color, Colors.amber),
        children: [
          for (final c in OutlineColorPalette.colors)
            ContextMenuItem(
              // 当前字底色与该色板一致时，文字前加 '·' 标记
              labelText: currentBg.isUniform && currentBg.color == c.background ? '· ${c.name}' : c.name,
              iconBuilder: (_) => OutlineColorPalette.buildColorSwatchIcon(c.background),
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
            iconBuilder: (_) => OutlineColorPalette.buildColorSwatchIcon(widget.colorScheme.surface),
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
    ];
  }

  /// 构建「插入」子菜单
  ///
  /// 集中节点内容绑定与附加内容的入口：关键词、关联、备注、图片、表格。
  /// 关键词与关联作用于单个节点及其文字选区，备注、图片与表格属于节点附加内容，
  /// 节点选区与批量选择下均不提供。
  ContextMenuItem _buildInsertContextMenu(String? nodeId) {
    final controller = nodeId != null ? _controllers[nodeId] : null;
    final bool hasTarget = nodeId != null && controller != null;
    final bool hasNodeSelection = _selectedNodeIds.isNotEmpty;
    final bool isReadOnly = widget.readOnly;

    // 关联文本仅作用于节点内的文字选区
    final TextSelection? selection = controller?.selection;
    final bool hasTextSelection =
        selection != null && selection.isValid && !selection.isCollapsed;
    final bool canAddNote = !isReadOnly && !hasNodeSelection && !_isBatchSelectionMode && hasTarget;
    // 每个节点只保留一个表格
    final bool hasTable = nodeId != null && _findNode(nodeId)?.table != null;

    return ContextMenuItem(
      labelText: '插入',
      icon: Icons.library_add_outlined,
      children: [
        ContextMenuItem(
          labelText: '关键词',
          icon: Icons.sell_outlined,
          enabled: !isReadOnly && !hasNodeSelection && hasTarget,
          onTap: () => _showKeywordCardForContextMenu(nodeId),
        ),
        ContextMenuItem(
          labelText: '关联',
          icon: Icons.link,
          enabled: !isReadOnly && !hasNodeSelection && hasTarget && hasTextSelection,
          onTap: () => _showLinkDialog(nodeId),
        ),
        ContextMenuItem(
          labelText: '备注',
          icon: Icons.post_add_rounded,
          enabled: canAddNote,
          onTap: () {
            if (nodeId != null) _startNoteEditing(nodeId);
          },
        ),
        ContextMenuItem(
          labelText: '图片',
          icon: Icons.image_outlined,
          enabled: canAddNote && widget.filePath != null,
          onTap: () {
            if (nodeId != null) _pickImageForNode(nodeId);
          },
        ),
        ContextMenuItem(
          labelText: '表格',
          icon: Icons.table_chart_outlined,
          enabled: canAddNote && !hasTable,
          onTap: () {
            if (nodeId != null) _insertTableForNode(nodeId);
          },
        ),
      ],
    );
  }

  /// 从右键菜单打开目标节点的关键词卡片
  void _showKeywordCardForContextMenu(String? nodeId) {
    if (nodeId == null) return;
    _showKeywordCard(nodeId);
  }

  /// 构建右键菜单项列表
  ///
  /// 菜单结构：
  /// - 文字样式相关菜单项（标题级别、文字样式、字体颜色、字底颜色）
  /// - 插入子菜单：关键词、关联、备注、图片
  /// - 常规菜单项：剪切、复制、粘贴、删除、全选
  List<ContextMenuItem> _buildContextMenuItems() {
    final nodeId = _contextMenuNodeId;
    final controller = nodeId != null ? _controllers[nodeId] : null;
    final selection = controller?.selection ?? const TextSelection.collapsed(offset: 0);
    final bool hasTextSelection = selection.isValid && !selection.isCollapsed;
    final bool hasNodeSelection = _selectedNodeIds.isNotEmpty;
    final bool isReadOnly = widget.readOnly;
    final bool hasTarget = nodeId != null && controller != null;

    return [
      // 文字样式相关菜单项
      ..._buildStyleContextMenuItems(nodeId),

      ContextMenuItem.divider(),

      // 节点内容绑定与附加内容入口
      _buildInsertContextMenu(nodeId),

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
    // 目标级别一致时点亮对应按钮，不一致时不点亮任何级别
    final firstLevel = nodes.first.headingLevel;
    final commonLevel = nodes.every((node) => node.headingLevel == firstLevel) ? firstLevel : -1;
    return HeadingLevelSelector(
      initialLevel: commonLevel,
      onLevelChanged: (level) => _setHeadingLevel(targetIds, level),
    );
  }

  /// 构建文字样式按钮行（加粗/斜体/下划线/删除线）
  ///
  /// 按钮的初始状态由选区决定：
  /// - 节点选区状态下：合并所有选中节点的样式状态
  /// - 有选中文字时：根据选中文字的样式状态点亮
  /// - 无选中文字时：根据光标所在字符的样式状态点亮
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
    // 计算目标节点在选区或光标位置的样式状态，作为按钮初始点亮状态
    final selectionFlags = _getContextMenuStyleFlags(targetNodes, selection);
    return TextStyleToggleRow(
      initialFlags: selectionFlags,
      onToggle: (toggle) => _toggleTextStyle(targetIds, toggle),
    );
  }

  // ================= 键盘事件 =================

  /// 判断按键是否为方向键
  static bool _isArrowKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;

  /// 节点级键盘事件处理
  ///
  /// 拦截特定按键并执行对应的节点操作，返回 handled 阻止 TextField 默认行为
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event, String nodeId) {
    // 拦截 Enter 键的重复事件，防止 TextField 插入换行符
    if (event is KeyRepeatEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      return KeyEventResult.handled;
    }

    // 拦截撤销/恢复的重复事件（长按 Ctrl/Cmd+Z、Ctrl+Y），避免触发 TextField 内置撤销机制
    if (event is KeyRepeatEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
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

    // 方向键：上下键在节点内的可视行之间移动、位于首行/末行时切换相邻节点；
    // 左右键在节点文本首/末位置时切换相邻节点，其余情况交由输入框默认处理。
    // 长按方向键产生的重复事件按同样规则处理，保证连续步进一致
    if (_isArrowKey(event.logicalKey)) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        // 带修饰键的方向键交由输入框默认行为处理（扩展选区、按词/段跳转等）
        final bool plain =
            !HardwareKeyboard.instance.isShiftPressed &&
            !(HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed) &&
            !HardwareKeyboard.instance.isAltPressed;
        if (plain) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _moveCaretVertically(nodeId, forward: false);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _moveCaretVertically(nodeId, forward: true);
            return KeyEventResult.handled;
          }
          // 左右移动属于横向移动，放弃垂直移动记录的目标列
          _preferredCaretX = null;
          final bool forward = event.logicalKey == LogicalKeyboardKey.arrowRight;
          // 关联文本视为一个整体，左右移动时整段跳过
          if (_moveCaretAcrossLink(nodeId, forward: forward)) {
            return KeyEventResult.handled;
          }
          final bool moved = _moveCaretAcrossNodeBoundary(nodeId, forward: forward);
          if (moved) return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    // 除方向键外的按键都会重新定位光标，之前记录的横向坐标不再适用
    _preferredCaretX = null;

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    // 主修饰键：Windows 使用 Ctrl，macOS 使用 Command，两者均视为快捷键前缀
    final isCommand =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Ctrl/Cmd+S：保存
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return KeyEventResult.handled;
    }

    // Ctrl+F / Cmd+F：打开查找
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyF) {
      context.read<WorkspaceProvider>().openFindReplace();
      return KeyEventResult.handled;
    }
    // Cmd+Option+F：打开查找替换（macOS 习惯）
    if (isCommand && isAlt && event.logicalKey == LogicalKeyboardKey.keyF) {
      context.read<WorkspaceProvider>().openFindReplace(showReplace: true);
      return KeyEventResult.handled;
    }
    // Ctrl+H：打开查找替换（Windows 习惯）
    if (HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyH) {
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

    // Ctrl/Cmd+C：复制节点内选中的文本（含文字样式）
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_copyNodeTextSelection(nodeId)) return KeyEventResult.handled;
    }

    // 只读模式下仅允许导航，禁用所有修改操作
    if (widget.readOnly) return KeyEventResult.ignored;

    // Ctrl/Cmd+X：剪切节点内选中的文本（含文字样式）
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyX) {
      if (_cutNodeTextSelection(nodeId)) return KeyEventResult.handled;
    }

    // Ctrl/Cmd+Z：撤销；Ctrl/Cmd+Shift+Z：重做（macOS 习惯）；Ctrl+Y：重做（Windows 习惯）
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        redo();
      } else {
        undo();
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyY) {
      redo();
      return KeyEventResult.handled;
    }

    // ================= 文字样式快捷键 =================

    // Ctrl/Cmd+B：加粗
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyB) {
      _toggleTextStyle([nodeId], TextStyleFlags.toggleBold);
      return KeyEventResult.handled;
    }
    // Ctrl/Cmd+I：斜体
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyI) {
      _toggleTextStyle([nodeId], TextStyleFlags.toggleItalic);
      return KeyEventResult.handled;
    }
    // Ctrl/Cmd+U：下划线
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyU) {
      _toggleTextStyle([nodeId], TextStyleFlags.toggleUnderline);
      return KeyEventResult.handled;
    }
    // Ctrl/Cmd+=：将当前节点的样式应用到全部同级节点
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.equal) {
      _applyStyleToSiblings(nodeId);
      return KeyEventResult.handled;
    }

    // Alt+数字：设置标题级别
    // Shift 时作用于当前节点的所有同级节点，否则仅作用于当前节点
    if (isAlt && !isCommand) {
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
          _applyColor([nodeId], foregroundColor: OutlineShortcutKeys.foregroundColor(event.logicalKey));
        }
        return KeyEventResult.handled;
      }
    }

    // Ctrl/Cmd+K：打开当前节点的关键词绑定卡片
    if (isCommand && !isAlt && OutlineShortcutKeys.isKeywordKey(event.logicalKey)) {
      _showKeywordCard(nodeId);
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd+L：为当前节点选中的文字添加关联
    if (isCommand && !isAlt && OutlineShortcutKeys.isLinkKey(event.logicalKey)) {
      _showLinkDialog(nodeId);
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd+Alt+T：为当前节点插入表格
    if (isCommand && isAlt && OutlineShortcutKeys.isTableKey(event.logicalKey)) {
      _insertTableForNode(nodeId);
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd+Alt+字母：设置字底颜色（D 为清除）
    if (isCommand && isAlt && OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
      if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
        _applyColor([nodeId], clearBackground: true);
      } else {
        _applyColor([nodeId], backgroundColor: OutlineShortcutKeys.backgroundColor(event.logicalKey));
      }
      return KeyEventResult.handled;
    }

    // Enter：创建同级新节点
    // Shift+Enter：添加/编辑备注；Alt+Enter：插入图片；Ctrl/Cmd+Enter：切换删除线
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (isShift && !isCommand && !isAlt) {
        _startNoteEditing(nodeId);
      } else if (isAlt && !isCommand && !isShift) {
        _pickImageForNode(nodeId);
      } else if (isCommand || isAlt) {
        _toggleTextStyle([nodeId], TextStyleFlags.toggleStrikethrough);
      } else {
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

    // 关联文本视为一个整体：在关联文本右侧按退格、左侧按删除时先移除关联，
    // 文字保持不变，再次按下同样的按键才按普通文本处理
    if (!isCommand &&
        !isAlt &&
        !isShift &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete)) {
      final bool forward = event.logicalKey == LogicalKeyboardKey.delete;
      if (_removeLinkAtCaret(nodeId, forward: forward)) {
        return KeyEventResult.handled;
      }
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

    // Ctrl/Cmd+A：全选当前主题，再次按下全选整个文档
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyA) {
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

    // Ctrl/Cmd+V：粘贴文本（多行转换为节点，缩进转换为子节点）
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyV) {
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
    // 拦截撤销/恢复的重复事件（长按 Ctrl/Cmd+Z、Ctrl+Y），与 _onKeyEvent 保持一致
    if (event is KeyRepeatEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
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
    // 主修饰键：Windows 使用 Ctrl，macOS 使用 Command，两者均视为快捷键前缀
    final isCommand =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Ctrl+S / Cmd+S：保存
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return KeyEventResult.handled;
    }

    // Ctrl+F / Cmd+F：打开查找
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyF) {
      context.read<WorkspaceProvider>().openFindReplace();
      return KeyEventResult.handled;
    }
    // Cmd+Option+F：打开查找替换（macOS 习惯）
    if (isCommand && isAlt && event.logicalKey == LogicalKeyboardKey.keyF) {
      context.read<WorkspaceProvider>().openFindReplace(showReplace: true);
      return KeyEventResult.handled;
    }
    // Ctrl+H：打开查找替换（Windows 习惯）
    if (HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyH) {
      context.read<WorkspaceProvider>().openFindReplace(showReplace: true);
      return KeyEventResult.handled;
    }

    // 标题输入框聚焦时，其余按键交还给输入框默认处理，避免误作用到节点
    if (_titleFocusNode.hasFocus) return KeyEventResult.ignored;

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
      // Ctrl/Cmd+C：复制选中节点（只读模式下仍允许复制）
      if (isCommand && event.logicalKey == LogicalKeyboardKey.keyC) {
        if (_selectedNodeIds.isNotEmpty) {
          _copySelectedNodes();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    // Ctrl/Cmd+K：为活动节点打开关键词绑定卡片（存在节点选区时不响应）
    if (isCommand && !isAlt && _selectedNodeIds.isEmpty &&
        OutlineShortcutKeys.isKeywordKey(event.logicalKey)) {
      final String? activeNodeId = _activeNodeId;
      if (activeNodeId != null) {
        _showKeywordCard(activeNodeId);
        return KeyEventResult.handled;
      }
    }

    // Ctrl/Cmd+L：为活动节点选中的文字添加关联（存在节点选区时不响应）
    if (isCommand && !isAlt && _selectedNodeIds.isEmpty &&
        OutlineShortcutKeys.isLinkKey(event.logicalKey)) {
      final String? activeNodeId = _activeNodeId;
      if (activeNodeId != null) {
        _showLinkDialog(activeNodeId);
        return KeyEventResult.handled;
      }
    }

    // Ctrl/Cmd+Alt+T：为活动节点插入表格（存在节点选区时不响应）
    if (isCommand && isAlt && _selectedNodeIds.isEmpty &&
        OutlineShortcutKeys.isTableKey(event.logicalKey)) {
      final String? activeNodeId = _activeNodeId;
      if (activeNodeId != null) {
        _insertTableForNode(activeNodeId);
        return KeyEventResult.handled;
      }
    }

    // Ctrl/Cmd+Z：撤销；Ctrl/Cmd+Shift+Z：重做（macOS 习惯）；Ctrl+Y：重做（Windows 习惯）
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        redo();
      } else {
        undo();
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyY) {
      redo();
      return KeyEventResult.handled;
    }

    // ================= 文字样式快捷键（作用于节点选区）=================

    if (_selectedNodeIds.isNotEmpty) {
      final targetIds = _selectedNodeIds.toList();

      // Ctrl/Cmd+B：加粗；Ctrl/Cmd+I：斜体；Ctrl/Cmd+U：下划线；Ctrl/Cmd+Enter：删除线
      if (isCommand && !isAlt) {
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
      if (isAlt && !isCommand) {
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
            _applyColor(targetIds, foregroundColor: OutlineShortcutKeys.foregroundColor(event.logicalKey));
          }
          return KeyEventResult.handled;
        }
      }

      // Ctrl/Cmd+Alt+字母：设置字底颜色（D 为清除）
      if (isCommand && isAlt && OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
        if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
          _applyColor(targetIds, clearBackground: true);
        } else {
          _applyColor(targetIds, backgroundColor: OutlineShortcutKeys.backgroundColor(event.logicalKey));
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

    // Ctrl/Cmd+A：在主题选区与文档选区间切换
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyA) {
      if (_selectAllLevel == 1) {
        // 主题已选 → 全选文档
        final flatList = _flatten();
        _selectedNodeIds
          ..clear()
          ..addAll(_expandWithDescendants(flatList.map((f) => f.node.id)));
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

    // Ctrl/Cmd+C：复制选中节点
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_selectedNodeIds.isNotEmpty) {
        _copySelectedNodes();
        return KeyEventResult.handled;
      }
    }

    // Ctrl/Cmd+X：剪切选中节点
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyX) {
      if (_selectedNodeIds.isNotEmpty) {
        _cutSelectedNodes();
        return KeyEventResult.handled;
      }
    }

    // Ctrl/Cmd+V：粘贴节点
    if (isCommand && event.logicalKey == LogicalKeyboardKey.keyV) {
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
        return (nodeId: entry.node.id, nodeStart: entry.startOffset, localOffset: globalOffset - entry.startOffset);
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
  /// 默认为用户设置的底边距。[onDone] 在定位结束（成功或放弃）时调用。
  void _scrollToNode(String nodeId, {double? margin, VoidCallback? onDone}) {
    if (!mounted) {
      onDone?.call();
      return;
    }
    // 已进入滚动定位阶段，布局阶段的预修正机会已过，清除待修正标记
    if (_pendingRevealNodeId == nodeId) _pendingRevealNodeId = null;
    _ensureAncestorsExpanded(nodeId);
    _scrollToNodeWithRetry(nodeId, 0, null, margin: margin ?? _bottomContentPadding, onDone: onDone);
  }

  /// 安排节点在下一次布局阶段完成底部安全间距修正
  ///
  /// 需在插入节点并触发重建之前调用：下一帧内容尺寸变化时，
  /// 若该节点位于列表末尾，会在绘制之前补足底部安全间距，
  /// 节点不会先出现在视口底部再被移上去。
  void _scheduleRevealBeforePaint(String nodeId) {
    _pendingRevealNodeId = nodeId;
  }

  /// 滚动到节点的重试实现
  ///
  /// 节点未构建时通过估算偏移量跳转，下一帧重试直到节点构建成功或超过最大重试次数；
  /// 定位结束（成功或放弃）时调用 [onDone]。
  void _scrollToNodeWithRetry(
    String nodeId,
    int retryCount,
    double? lastJumpOffset, {
    double margin = 0,
    VoidCallback? onDone,
  }) {
    if (!mounted || !_scrollController.hasClients || retryCount >= 30) {
      onDone?.call();
      return;
    }

    final key = _nodeTileKeys[nodeId];
    final context = key?.currentContext;

    // 节点已构建：确保目标在视口内可见
    if (context != null && context.findRenderObject()?.attached == true) {
      _ensureNodeVisible(context, margin: margin);
      onDone?.call();
      return;
    }

    final flatList = _flatten();
    final targetIndex = flatList.indexWhere((f) => f.node.id == nodeId);
    if (targetIndex == -1) {
      onDone?.call();
      return;
    }

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
      if (jumpTarget <= currentOffset + 1.0) {
        onDone?.call();
        return;
      }
    } else {
      jumpTarget = clampedEstimate;
    }

    _scrollController.position.jumpTo(jumpTarget);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNodeWithRetry(nodeId, retryCount + 1, jumpTarget, margin: margin, onDone: onDone);
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

  /// 保证节点光标所在行在编辑区视口内可见
  ///
  /// 节点内文字换行较多时，光标会随可视行移动而移出视口，
  /// 需要同步滚动外层列表，使光标行始终可见。
  void _ensureCaretVisibleInViewport(String nodeId) {
    if (!_scrollController.hasClients) return;

    final controller = _controllers[nodeId];
    final renderEditable = _findRenderEditable(nodeId);
    final viewportRect = _viewportGlobalRect();
    if (controller == null || renderEditable == null || !renderEditable.attached || viewportRect == null) {
      return;
    }

    final Rect caretRect = renderEditable.getLocalRectForCaret(controller.selection.extent);
    final Rect caretGlobalRect = MatrixUtils.transformRect(renderEditable.getTransformTo(null), caretRect);
    // 光标与视口边缘保留一行高度的间距，避免光标贴边而难以看清
    final double margin = caretRect.height > 8.0 ? caretRect.height : 8.0;

    final double currentOffset = _scrollController.offset;
    double? target;
    if (caretGlobalRect.bottom > viewportRect.bottom - margin) {
      // 光标行位于视口下方：向下滚动使光标行回到视口内
      target = currentOffset + caretGlobalRect.bottom - viewportRect.bottom + margin;
    } else if (caretGlobalRect.top < viewportRect.top + margin) {
      // 光标行位于视口上方：向上滚动使光标行回到视口内
      target = currentOffset + caretGlobalRect.top - viewportRect.top - margin;
    }
    if (target == null) return;

    final position = _scrollController.position;
    _scrollController.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  // ================= 边缘自动滚动 =================

  /// 更新边缘自动滚动状态
  ///
  /// 指针进入视口上下边缘的触发区时启动定时滚动，离开触发区后停止；
  /// [selectionUpdater] 用于在指针不动、仅视口滚动的过程中继续刷新选区。
  void _updateEdgeAutoScroll(Offset globalPosition, {required void Function(Offset globalPosition) selectionUpdater}) {
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

    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _onEdgeAutoScrollTick());
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
    final double target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
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
    return MatrixUtils.transformRect(renderObject.getTransformTo(null), Offset.zero & renderObject.size);
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
    if (previousNodeId != null && previousNodeId != baseResolved.nodeId && _controllers.containsKey(previousNodeId)) {
      final prevController = _controllers[previousNodeId]!;
      if (!prevController.selection.isCollapsed) {
        final offset = prevController.selection.baseOffset.clamp(0, prevController.text.length);
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
    node.styleRanges = TextStyleRangeUtils.adjustForTextChange(node.styleRanges, oldText, newText);
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

      final sortedMatches = entry.value.toList()..sort((a, b) => b.start.compareTo(a.start));

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
      node.styleRanges = TextStyleRangeUtils.adjustForTextChange(node.styleRanges, oldText, newText);
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

  /// 按节点层级路径定位并聚焦节点
  ///
  /// 供正文关键词跳转使用：先展开全部祖先使节点可见，再滚动到视口中央，
  /// 最后把焦点与光标（位于节点末尾）交给该节点。返回 false 表示节点尚未解析出来（如内容仍在加载）。
  bool revealNodeByPath(String path) {
    final OutlineNode? node = _nodeAtPath(path);
    if (node == null) return false;
    _revealNode(node);
    return true;
  }

  /// 按关联目标定位节点
  ///
  /// 优先使用节点路径，并对路径节点的文本做校验：
  /// - 路径节点文本与目标一致或高度相似时直接定位
  /// - 节点被移动到其他位置时按文本查找
  /// - 文本也被大幅修改时回退到原路径节点（结构未变的情况）
  /// 返回 false 表示节点尚未解析出来或无法定位。
  bool revealLinkedNode({required String nodePath, required String text}) {
    final OutlineNode? pathNode = _nodeAtPath(nodePath);
    final String target = text.trim();

    if (pathNode != null) {
      if (target.isEmpty) {
        _revealNode(pathNode);
        return true;
      }
      final String pathText = pathNode.text.trim();
      final bool sameNode = pathText == target ||
          pathText.contains(target) ||
          TextSimilarity.similarity(target, pathText) >= TextSimilarity.matchThreshold;
      if (sameNode) {
        _revealNode(pathNode);
        return true;
      }
    }

    // 路径节点已不是原目标，按文本查找被移动的节点
    if (target.isNotEmpty && revealNodeByText(target)) return true;

    // 文本也被修改且无法匹配时，结构未变的情况下回退到原路径节点
    if (pathNode != null) {
      _revealNode(pathNode);
      return true;
    }
    return false;
  }

  /// 展开祖先并滚动聚焦到指定节点
  ///
  /// 光标置于节点文本末尾，便于定位后直接在原有内容之后继续编辑。
  void _revealNode(OutlineNode node) {
    _ensureAncestorsExpanded(node.id);
    _focusAndScrollToNode(node.id, moveCursorToEnd: true);
  }

  /// 按节点文本定位并聚焦节点
  ///
  /// 供关联跳转兜底使用：节点路径因结构变化失效时，按记录的目标文本查找节点，
  /// 依次尝试完全相同、包含目标文本、文本相似度匹配。
  /// 返回 false 表示未找到可信的对应节点。
  bool revealNodeByText(String text) {
    final String target = text.trim();
    if (target.isEmpty) return false;

    OutlineNode? exactNode;
    OutlineNode? partialNode;
    OutlineNode? fuzzyNode;
    double bestScore = 0;

    void walk(OutlineNode node) {
      final String nodeText = node.text.trim();
      if (nodeText == target) {
        exactNode ??= node;
        return;
      }
      if (partialNode == null && nodeText.isNotEmpty && nodeText.contains(target)) {
        partialNode = node;
      }
      // 记录相似度最高的节点，供文本被局部修改后兜底定位；
      // 过短的文本相似度不可靠，不做模糊匹配
      if (target.length >= 4) {
        final double score = TextSimilarity.similarity(target, nodeText);
        if (score > bestScore) {
          bestScore = score;
          fuzzyNode = node;
        }
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }

    final OutlineNode? node = exactNode ??
        partialNode ??
        (bestScore >= TextSimilarity.matchThreshold ? fuzzyNode : null);
    if (node == null) return false;
    _revealNode(node);
    return true;
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
    await OutlineEditorSettingsCard.show(context: context, anchorRect: anchorRect, editorLeft: editorLeft);
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
    _syncFindHighlightsToControllers(workspaceProvider.findMatches, workspaceProvider.currentMatchIndex);

    // 展示数据包含折叠动画中的子节点行，用于呈现子节点收进圆点的过渡
    final displayRows = _buildDisplayRows();

    // 编辑区底色：默认跟随主题，自定义时使用配置的颜色；纸张模式下纸张外背景由淡化设置决定
    final bool isPaperMode = SettingsService.instance.outlinePageViewMode == 'paper';
    final Color editorBackgroundColor = ColorUtils.getEditorBackgroundColorForTheme(context);
    final Color editorAreaColor = isPaperMode
        ? ColorUtils.getPaperOutsideBackgroundColor(context)
        : editorBackgroundColor;

    // 文件读取失败：显示错误占位与重试入口，避免空内容被继续编辑或保存
    if (_loadErrorMessage != null) {
      return Container(
        color: editorAreaColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _loadErrorMessage!,
                style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _retryLoad,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

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
            // 内容载入完成前禁用添加节点，避免输入被随后解析的内容覆盖
            readOnly: widget.readOnly || !_isContentReady,
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
            topicPath: _breadcrumbTitles,
            onTopicPathTap: _onBreadcrumbTap,
          ),
          // 大纲列表
          Expanded(
            child: Stack(
              key: _editorStackKey,
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
                                      instance.shouldYieldPointer = (position) =>
                                          _isPositionOnScrollbar(position) ||
                                          _isPositionOnTitle(position) ||
                                          _isPositionOnNodeDot(position) ||
                                          _isPositionOnNodeArrow(position) ||
                                          _isPositionOnNodeAttachment(position);
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
                              displayRows: displayRows,
                            ),
                          );

                          // 移动端隐藏滚动条，避免遮挡窄屏下的编辑内容；桌面端保持原有滚动条表现
                          final Widget contentView = PlatformCapabilities.isMobile
                              ? scrollContent
                              : Scrollbar(
                                  key: _scrollbarKey,
                                  controller: _scrollController,
                                  thumbVisibility: settings.scrollbarAlwaysVisible ? true : null,
                                  thickness: editorScrollbarThickness,
                                  radius: Radius.circular(editorScrollbarThickness / 2),
                                  child: scrollContent,
                                );

                          // 定位完成前不绘制节点列表：列表仍参与布局以便完成定位，
                          // 定位结束后再一次性呈现，避免先闪出文档头部再跳转
                          if (!_deferContentPaint) return contentView;
                          return Opacity(opacity: 0, child: contentView);
                        },
                      ),
                    ),
                  ),
                ),
                // 加载指示：仅在解析超过一定时长仍未完成时显示；
                // 正常几十毫秒的解析不显示，避免编辑器背景闪动
                if (_showLoadingIndicator)
                  Positioned.fill(
                    child: AbsorbPointer(
                      child: ColoredBox(
                        color: editorAreaColor,
                        child: Center(
                          child: CircularProgressIndicator(color: colorScheme.primary),
                        ),
                      ),
                    ),
                  ),
                // 拖拽排序的落点指示：浮在节点列表之上，不参与指针交互
                ?_buildReorderIndicator(colorScheme),
                // 拖拽排序时跟随指针的圆点，模拟被鼠标抓起的圆点
                _buildReorderPointerDot(colorScheme, editorBackgroundColor),
                // 拖拽期间覆盖整个编辑区，让鼠标全程保持抓取光标；
                // 节点拖拽排序与表格行列拖拽共用该覆盖层，指针移出被拖动控件也不变样式
                if (!PlatformCapabilities.isMobile)
                  ValueListenableBuilder<bool>(
                    valueListenable: DragCursor.isDragging,
                    builder: (context, dragging, _) {
                      if (!dragging && _reorderNodeId == null) {
                        return const SizedBox.shrink();
                      }
                      return Positioned.fill(
                        child: ValueListenableBuilder<MouseCursor>(
                          valueListenable: DragCursor.notifier,
                          builder: (context, cursor, _) => MouseRegion(cursor: cursor),
                        ),
                      );
                    },
                  ),
                // 底部快捷键提示：仅桌面端且设置中开启时显示
                // 移动端没有物理键盘，隐藏提示，底部预留高度保持为 0
                if (!PlatformCapabilities.isMobile && SettingsService.instance.outlineBottomHintEnabled)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: MeasureSize(
                      onSizeChanged: (size) {
                        if (mounted && size.height != _bottomHintHeight) {
                          setState(() => _bottomHintHeight = size.height);
                        }
                      },
                      child: OutlineEditorBottomHint(
                        colorScheme: colorScheme,
                        // 点击关闭按钮时关闭快捷键提示，与设置面板中的开关保持同步
                        onClose: () => SettingsService.instance.updateOutlineBottomHintEnabled(false),
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
                      // 传入编辑器画布底色，面板据此叠加出层次化的浮层底色
                      canvasColor: editorAreaColor,
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

  /// 构建拖拽排序的落点指示
  ///
  /// 插入线贴在指针所在行的上边界（插到其之前）或下边界（落点在其后的间隙），
  /// 横向缩进按落点层级绘制，提示松手后节点将出现的层级与位置；
  /// 未处于拖拽排序或没有有效落点时返回 null
  Widget? _buildReorderIndicator(ColorScheme colorScheme) {
    final target = _reorderTarget;
    if (target == null || _reorderNodeId == null) return null;

    final flatList = _flatten();
    final int anchorIndex = flatList.indexWhere((flat) => flat.node.id == target.indicatorNodeId);
    if (anchorIndex < 0) return null;

    final FlatNode anchor = flatList[anchorIndex];
    final Rect? anchorRect = _nodeTileGlobalRect(anchor.node.id);
    final RenderBox? stackBox = _editorStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorRect == null || stackBox == null || !stackBox.attached) return null;

    // 按落点层级计算插入线横向起点，使用指针所在行作为换算基准
    final double? dotCenterGlobalX = _dotCenterGlobalX(anchor.node.id, anchor.depth, target.depth);
    if (dotCenterGlobalX == null) return null;

    // 插入线纵向位置：贴指针所在行的上边界或下边界
    final double lineGlobalY = target.indicatorAbove ? anchorRect.top : anchorRect.bottom;

    // 换算到编辑区内容层叠区域内的本地坐标
    final double lineY = stackBox.globalToLocal(Offset(0, lineGlobalY)).dy;
    final double lineStartX = stackBox.globalToLocal(Offset(dotCenterGlobalX, 0)).dx - _indentWidth / 2;
    final double lineEndX = stackBox.globalToLocal(anchorRect.topRight).dx;
    final double trailingWidth = lineStartX + 4 < lineEndX ? lineEndX - lineStartX - 4 : 0.0;
    final Color indicatorColor = colorScheme.primary;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // 插入位置指示：左端圆点 + 横向指示线
            Positioned(
              left: lineStartX,
              top: lineY - 2,
              width: 4,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle),
              ),
            ),
            Positioned(
              left: lineStartX + 4,
              top: lineY - 1,
              width: trailingWidth,
              height: 2,
              child: ColoredBox(color: indicatorColor),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建拖拽排序时跟随指针的圆点
  ///
  /// 外观与节点圆点保持一致（外轮廓 + 中心圆点），位于指针右下方，
  /// 模拟被鼠标抓起来的效果；未处于拖拽排序时不显示
  Widget _buildReorderPointerDot(ColorScheme colorScheme, Color backgroundColor) {
    // 与节点圆点相同的配色，先与编辑区底色合成再绘制：
    // 避免半透明圆点叠在文字上显得发糊，同时保持与节点圆点一致的观感
    final Color outlineColor =
        Color.alphaBlend(colorScheme.onSurfaceVariant.withValues(alpha: 0.1), backgroundColor);
    final Color dotColor = Color.alphaBlend(colorScheme.onSurfaceVariant.withValues(alpha: 0.4), backgroundColor);

    final double outlineRadius = OutlineConnectionMetrics.hoverDotBackgroundRadius;
    final double ghostSize = outlineRadius * 2;
    // 圆点中心相对指针热点的偏移，使圆点落在指针右下方
    const double centerOffset = 20.0;

    return ValueListenableBuilder<Offset?>(
      valueListenable: _reorderPointerPosition,
      builder: (context, position, _) {
        if (position == null) return const SizedBox.shrink();

        final RenderBox? stackBox = _editorStackKey.currentContext?.findRenderObject() as RenderBox?;
        if (stackBox == null || !stackBox.attached) return const SizedBox.shrink();

        // 换算到编辑区内容层叠区域内的本地坐标
        final Offset local = stackBox.globalToLocal(position);
        return Positioned(
          left: local.dx + centerOffset - outlineRadius,
          top: local.dy + centerOffset - outlineRadius,
          child: IgnorePointer(
            child: Container(
              width: ghostSize,
              height: ghostSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: outlineColor,
                shape: BoxShape.circle,
              ),
              // 中心圆点，与节点圆点同色同大小
              child: Container(
                width: OutlineConnectionMetrics.dotRadius * 2,
                height: OutlineConnectionMetrics.dotRadius * 2,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 计算指定节点行上某一层级圆点中心的全局横坐标
  ///
  /// 以该行文本区左边缘为基准换算：同层圆点中心比文字起点左移
  /// (半列宽 - 圆点与文本的间距缩减量)，每深一层再右移一列，
  /// 从而与连接线绘制器中的圆点位置保持一致
  double? _dotCenterGlobalX(String nodeId, int anchorDepth, int depth) {
    final renderEditable = _findRenderEditable(nodeId);
    if (renderEditable != null && renderEditable.attached) {
      final rect = MatrixUtils.transformRect(renderEditable.getTransformTo(null), Offset.zero & renderEditable.size);
      return rect.left - (_indentWidth / 2 - _dotTextGapReduction) + (depth - anchorDepth) * _indentWidth;
    }

    // 文本区尚未构建时退回按节点行左边缘估算
    final Rect? tileRect = _nodeTileGlobalRect(nodeId);
    if (tileRect == null) return null;
    final int columnOffset = PlatformCapabilities.isMobile ? -1 : 0;
    return tileRect.left + 8 + (depth + 1 + columnOffset) * _indentWidth + _indentWidth / 2;
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
    required List<_OutlineDisplayRow> displayRows,
  }) {
    final settings = SettingsService.instance;
    final bool isPaperMode = pageViewMode == 'paper';
    final double horizontalBase = isPaperMode ? GlobalConstants.a4Width : constraints.maxWidth;
    final double horizontalPadding = horizontalBase * (settings.outlineHorizontalMargin / 100);
    // 顶边距和底边距（百分比，相对于编辑器高度）
    // 换算基准在键盘升降期间保持不变，避免节点内容随键盘上下移动
    final double marginBasisHeight = _resolveMarginBasisHeight(constraints.maxHeight);
    final double topPadding = marginBasisHeight * (settings.outlineTopMargin / 100);
    final double bottomPadding = marginBasisHeight * (settings.outlineBottomMargin / 100);
    // 记录底边距，供聚焦、定位节点时作为底部安全间距使用
    _bottomContentPadding = bottomPadding;
    // 底部快捷键提示的预留高度：提示关闭或移动端不显示时不预留
    final double bottomHintHeight = (!PlatformCapabilities.isMobile && settings.outlineBottomHintEnabled)
        ? _bottomHintHeight
        : 0.0;
    // 记录进入滚动内容的底部预留高度，供列表末尾节点的定位使用
    _bottomHintReserved = bottomHintHeight;

    // 内容按 A4 宽度居中的额外内缩量；宽度不足以容纳 A4 时取 0；
    // 纸张模式与移动端在整个视口宽度内居中，桌面端非纸张模式先施加左右边距再居中
    final double viewportCenterRaw = (constraints.maxWidth - GlobalConstants.a4Width) / 2;
    final double viewportCenterInset = viewportCenterRaw > 0 ? viewportCenterRaw : 0.0;
    final double paddedCenterRaw = (constraints.maxWidth - 2 * horizontalPadding - GlobalConstants.a4Width) / 2;
    final double paddedCenterInset = paddedCenterRaw > 0 ? paddedCenterRaw : 0.0;

    // 当前编辑节点，及其到下一个同级节点之间连接线的高亮范围
    final String? activeNodeId = _activeNodeId;
    final List<FlatNode> flatList = displayRows.map((row) => row.flatNode).toList(growable: false);
    final ({int column, int startIndex, int endIndex})? siblingLineRange = _resolveActiveSiblingLine(
      flatList,
      activeNodeId,
    );

    // 构建节点列表，每个节点都用右键菜单包装；
    // 移动端长按交还系统原生选择行为，不注册长按识别器
    final Widget nodeList = SliverList.builder(
      itemCount: displayRows.length,
      itemBuilder: (context, index) => ContextMenu(
        getMenuItems: _buildContextMenuItems,
        onSecondaryTapDown: _handleSecondaryTapDown,
        // 备注输入框编辑时右键交还输入框自身，使用默认的文字编辑菜单；
        // 表格拥有单元格格式栏，同样不让节点菜单接管
        shouldHandleSecondaryTap: (position) {
          final String? editingNoteNodeId = _noteEditingNodeId;
          final bool onEditingNote = editingNoteNodeId != null &&
              _isPositionOnAttachmentOf(editingNoteNodeId, position);
          return !onEditingNote && !_isPositionOnNodeTable(position);
        },
        onDismissed: _handleContextMenuDismissed,
        enableMobileLongPress: !PlatformCapabilities.isMobile,
        child: _buildNodeTile(
          displayRows[index],
          index: index,
          activeNodeId: activeNodeId,
          siblingLineRange: siblingLineRange,
          horizontalMargin: horizontalPadding,
        ),
      ),
    );

    // 大纲标题距内容区左侧的内缩量：与一级节点的圆点左对齐；
    // 桌面端由滚动容器统一施加左右边距，移动端边距由节点行自身承担，故需额外计入
    final double titleLeftPadding = 2.0 +
        (PlatformCapabilities.isMobile ? horizontalPadding : 0.0) +
        OutlineNodeTile.dotLeftInsetForDepth(0, indentWidth: _indentWidth);

    // 标题显示在第一个节点上方，随内容一同滚动，不属于节点：
    // 未进入主题时显示大纲文件标题，进入主题后显示当前主题节点自身的文本
    final OutlineNode? topicNode = _focusNode;
    final Widget? titleSliver;
    if (!settings.outlineShowTitle) {
      titleSliver = null;
    } else if (topicNode != null) {
      // 主题标题以纯文本标签展示当前主题文本，不可编辑、不可选中；
      // 需要修改时返回上一级，在对应节点中输入
      titleSliver = SliverToBoxAdapter(
        child: OutlineTopicTitleLabel(
          key: _titleFieldKey,
          node: topicNode,
          colorScheme: colorScheme,
          leftPadding: titleLeftPadding,
        ),
      );
    } else {
      titleSliver = SliverToBoxAdapter(
        child: OutlineTitleField(
          key: _titleFieldKey,
          controller: _titleController,
          focusNode: _titleFocusNode,
          colorScheme: colorScheme,
          // 内容载入完成前不允许编辑标题，避免输入被随后同步的内容覆盖
          readOnly: widget.readOnly || !_isContentReady,
          leftPadding: titleLeftPadding,
          onChanged: (value) => widget.onTitleChanged?.call(value),
        ),
      );
    }

    // 主题模式下当前主题暂无子节点时展示提示，避免出现无内容的空白视图
    final Widget? emptyTopicHint = _focusNode != null && displayRows.isEmpty
        ? SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(left: titleLeftPadding, right: 8, top: 8, bottom: 8),
              child: Text(
                '该主题暂无子主题，可通过顶部“添加节点”创建',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
          )
        : null;

    final List<Widget> slivers;
    if (isPaperMode) {
      // 纸张模式：纸张按 A4 宽度居中，水平/上下边距作为纸张内边距；
      // 滚动容器只保留查找替换浮窗的顶边距、纸张顶边距（防止顶部阴影被遮挡）与底部快捷键提示高度；
      // 内容不足 A4 高度时在其后补足空白，使纸张始终保持 A4 尺寸
      slivers = [
        SliverPadding(
          padding: EdgeInsets.only(top: widget.extraTopPadding + 10.0, bottom: bottomHintHeight),
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
                padding: EdgeInsets.fromLTRB(horizontalPadding, topPadding, horizontalPadding, bottomPadding),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    ?titleSliver,
                    ?emptyTopicHint,
                    nodeList,
                    SliverFillRemaining(hasScrollBody: false, child: const SizedBox.shrink()),
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
              bottom: bottomPadding + bottomHintHeight,
            )
          : EdgeInsets.only(
              left: horizontalPadding + centerInset,
              right: horizontalPadding + centerInset,
              top: topPadding + widget.extraTopPadding,
              bottom: bottomPadding + bottomHintHeight,
            );
      slivers = [
        SliverPadding(
          padding: scrollPadding,
          sliver: SliverMainAxisGroup(
            slivers: [
              ?titleSliver,
              ?emptyTopicHint,
              nodeList,
            ],
          ),
        ),
      ];
    }

    return CustomScrollView(key: _scrollViewKey, controller: _scrollController, slivers: slivers);
  }

  /// 构建单个节点行
  ///
  /// [horizontalMargin] 为左右边距（像素），仅移动端使用：
  /// 桌面端由滚动容器内边距统一施加，移动端则由节点行内容承担。
  /// [index] 为该节点在扁平列表中的行索引，
  /// [activeNodeId] 为当前编辑节点 ID，[siblingLineRange] 为连接线高亮范围，
  /// 二者共同决定该行圆点与同级连接线是否点亮。
  /// [displayRow] 额外携带折叠动画进度，用于让子节点行收进父节点圆点
  Widget _buildNodeTile(
    _OutlineDisplayRow displayRow, {
    required int index,
    required String? activeNodeId,
    required ({int column, int startIndex, int endIndex})? siblingLineRange,
    required double horizontalMargin,
  }) {
    final FlatNode flatNode = displayRow.flatNode;

    // 获取或创建节点瓦片的全局键，用于拖拽选区的命中检测
    final key = _nodeTileKeys.putIfAbsent(flatNode.node.id, () => GlobalKey());

    // 当前编辑节点的圆点高亮
    final bool isActiveNode = flatNode.node.id == activeNodeId;

    // 是否允许通过长按圆点拖拽排序：只读模式与批量选择模式下不修改节点结构
    final bool canReorderByDot = !widget.readOnly && !_isBatchSelectionMode;

    // 当前编辑节点到下一个同级节点之间的连接线高亮列：
    // 该连接线位于当前节点圆点所在的列，由两者之间的子孙节点行整行点亮
    final int? highlightedLineColumn =
        siblingLineRange != null && index >= siblingLineRange.startIndex && index < siblingLineRange.endIndex
        ? siblingLineRange.column
        : null;

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
      isActiveNode: isActiveNode,
      highlightedLineColumn: highlightedLineColumn,
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
      // 圆点拖拽排序：只读模式与批量选择模式下不启用
      onDotDragStart: canReorderByDot ? (position) => _onDotDragStart(flatNode.node.id, position) : null,
      onDotDragMove: canReorderByDot ? _onDotDragMove : null,
      onDotDragEnd: canReorderByDot ? _onDotDragEnd : null,
      onDotDragCancel: canReorderByDot ? _onDotDragCancel : null,
      // 点击圆点进入该节点的主题视图，批量选择模式下不切换
      onDotTap: !_isBatchSelectionMode ? () => _enterNodeTopic(flatNode.node.id) : null,
      // 点击关联文本跳转到关联目标
      onLinkTap: widget.readOnly || _isBatchSelectionMode ? null : _handleLinkTap,
      // 节点附加备注区：图片路径按设定文件所在目录解析
      imagePath: BookFolderService.settingImageFilePath(
            widget.filePath,
            flatNode.node.imageFileName,
          ) ??
          '',
      isEditingNote: _noteEditingNodeId == flatNode.node.id,
      onNoteChanged: (note) => _onNodeNoteChanged(flatNode.node.id, note),
      onStartNoteEdit: () => _startNoteEditing(flatNode.node.id),
      onStopNoteEdit: () => _stopNoteEditing(flatNode.node.id),
      onDeleteNodeImage: () => _deleteNodeImage(flatNode.node.id),
      // 节点附加表格：位于备注下方，单元格交互由表格组件自行处理
      table: flatNode.node.table,
      onTableChanged: () => _onNodeTableChanged(flatNode.node.id),
      onTableWillChange: _onNodeTableWillChange,
      onDeleteNodeTable: () => _deleteNodeTable(flatNode.node.id),
      tableKey: _tableKeys.putIfAbsent(flatNode.node.id, () => GlobalKey()),
      attachmentKey: _attachmentKeys.putIfAbsent(flatNode.node.id, () => GlobalKey()),
      isDragging: _reorderNodeId == flatNode.node.id,
      // 折叠动画进度：子节点行据此收进父节点圆点，节点自身据此同步圆点轮廓
      subtreeFoldProgress: displayRow.foldProgress,
      foldTargetDotDepth: displayRow.foldDotDepth,
      dotFoldProgress: displayRow.dotFoldProgress,
      onChanged: (newText) {
        final oldText = flatNode.node.text;
        if (oldText != newText) {
          final controller = _controllers[flatNode.node.id];
          // 编辑后的光标位置，用于纯删除时精确定位被删除的区间
          final selection = controller?.selection;
          final caretOffset = selection != null && selection.isValid && selection.isCollapsed
              ? selection.start
              : null;
          // 文本变化时调整样式区间位置，保持样式与文字对应
          flatNode.node.styleRanges = TextStyleRangeUtils.adjustForTextChange(
            flatNode.node.styleRanges,
            oldText,
            newText,
            caretOffset: caretOffset,
          );
          // 同步到控制器以触发富文本重建
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

/// 展示用的节点行
///
/// 在可见节点基础上携带折叠动画信息：收起/展开过程中，
/// 子节点行按动画进度向目标圆点缩放淡出，动画结束后不再出现在列表中
class _OutlineDisplayRow {
  /// 节点行数据
  final FlatNode flatNode;

  /// 本行的收拢动画进度（1 为完全展开，0 为完全收进圆点），无动画时为 null
  final Animation<double>? foldProgress;

  /// 收拢目标圆点所在节点的深度，无动画时为 null
  final int? foldDotDepth;

  /// 本节点圆点自身的折叠动画进度，非空表示该节点正在收起或展开子节点
  final Animation<double>? dotFoldProgress;

  _OutlineDisplayRow({
    required this.flatNode,
    this.foldProgress,
    this.foldDotDepth,
    this.dotFoldProgress,
  });
}

/// 拖拽选区模式：无、文本选区、节点选区
enum _DragMode { none, text, node }

/// 拖拽排序的放置方式
enum _OutlineReorderPlacement {
  /// 插入到目标行之前，层级与目标行相同
  before,

  /// 插入到目标行之后，层级与目标行相同
  after,

  /// 作为目标行的第一个子节点插入
  firstChild,
}

/// 拖拽排序的落点
class _OutlineReorderTarget {
  /// 实际插入的目标节点ID
  final String targetNodeId;

  /// 放置方式
  final _OutlineReorderPlacement placement;

  /// 插入后的层级
  final int depth;

  /// 插入指示线所依附的节点ID（指针所在行）
  final String indicatorNodeId;

  /// 指示线是否贴在依附节点的上边界
  ///
  /// 为 true 表示贴上行顶（插到其之前），为 false 表示贴行底（插到其后的间隙）
  final bool indicatorAbove;

  const _OutlineReorderTarget({
    required this.targetNodeId,
    required this.placement,
    required this.depth,
    required this.indicatorNodeId,
    required this.indicatorAbove,
  });
}

/// 自定义平移手势识别器，以极小的移动阈值接受手势
///
/// 确保在输入框内部开始拖拽时，能优先于输入框自带的手势识别器赢得竞技场。
/// 当指针落在滚动条、大纲标题或节点交互控件（圆点、折叠箭头）上时则不参与竞技场，
/// 把交互让给目标控件。
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  /// 判断指针是否应交由其他控件处理
  ///
  /// 返回 true 时本识别器不进入该指针的竞技场，由目标控件赢得拖拽与点击。
  bool Function(Offset globalPosition)? shouldYieldPointer;

  @override
  bool isPointerAllowed(PointerEvent event) {
    // 指针位于滚动条或大纲标题区域时不参与竞技场
    if (shouldYieldPointer?.call(event.position) ?? false) {
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
