import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/models/outline_table.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/clean_scroll.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/rich_text_controller.dart';
import 'package:quick_write/core/utils/text_style_range.dart';
import 'package:quick_write/pages/workspace/editor/utils/drag_cursor.dart';
import 'package:quick_write/pages/workspace/editor/utils/outline_shortcut_keys.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_color_palette.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_editor_widgets.dart';
import 'package:quick_write/pages/workspace/widgets/mobile_table_toolbar_binding.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 单元格坐标（行、列）
typedef _CellPosition = ({int row, int col});

/// 移动端单元格的选中阶段
///
/// 移动端把「选中单元格」与「聚焦输入框」拆成两次点击：
/// 第一次只选中并显示高亮边框与快捷栏，第二次才把光标交给输入框。
enum _MobileCellStage {
  /// 未选中
  none,

  /// 已选中，未聚焦输入框
  selected,

  /// 已聚焦输入框，正在编辑
  editing,
}

/// 节点附加表格
///
/// 表格位于备注下方，首行作为表头并带浅色底色：
/// - 鼠标悬停或正在编辑时，表格右侧与下方出现「+」按钮，分别追加列与行；
/// - 单击单元格进入编辑，Tab / Shift+Tab 在单元格之间移动，末尾单元格继续向后
///   移动时自动补一行；
/// - Shift+单击或从单元格边距拖动可选中连续的一批单元格，Ctrl+A 全选单元格，
///   Delete 清空选区内容；样式快捷键与右键菜单均作用于整个选区；
/// - 拖动第一行单元格的右边缘调整该列宽度，后续列宽保持不变并整体向右平移；
/// - 拖动第一行单元格上边缘的手柄调整列顺序，拖动第一列单元格左边缘的手柄
///   调整行顺序；
/// - 右键单元格弹出浮动格式栏，可设置标题级别、文字样式、字体颜色，
///   并通过「⋯」删除当前行、当前列或整个表格；
/// - 未手动调整过列宽时按内容自动调整；内容显示不全时表格下方出现横向滚动条，
///   可拖动滚动条或按住 Shift 滚动滚轮左右移动视口，移动端直接左右滑动。
///
/// 移动端不安装桌面端的悬停、长按与拖拽选区检测，改由显式手势驱动：
/// 第一次点击选中单元格并显示高亮边框与底部快捷栏，第二次点击才聚焦输入框；
/// 选中首行单元格显示列拖拽手柄、选中第一列非表头单元格显示行拖拽手柄，
/// 两者与桌面端共用外观与拖动逻辑，只是移动端改为长按触发；
/// 选中首行单元格还显示列宽指示器；快捷栏提供与桌面右键菜单一致的样式操作；
/// 编辑态长按选中单元格内文字时，选区上方弹出剪切、复制、粘贴、全选工具栏。
class OutlineTableBlock extends StatefulWidget {
  /// 表格数据
  ///
  /// 组件直接修改该对象，修改后通过 [onChanged] 通知外部保存。
  final OutlineTableData table;

  /// 颜色方案
  final ColorScheme colorScheme;

  /// 单元格基础字号
  final double fontSize;

  /// 是否只读
  final bool readOnly;

  /// 表格内容或结构变化回调
  final VoidCallback onChanged;

  /// 表格数据即将变化回调
  ///
  /// 在修改表格数据之前调用，供外部记录撤销所需的前置状态。
  final VoidCallback? onBeforeChange;

  /// 删除整个表格回调
  final VoidCallback? onDeleteTable;

  /// 表格左侧与上方为拖拽手柄预留的空白宽度
  ///
  /// 手柄压在边框线上时会向表格外溢出一段，预留该空白保证手柄完整可见，
  /// 同时让表格外的这一段区域也能响应悬停与拖动。
  /// 外部布局可据此把表格整体左移，使表格边框与上方文字对齐。
  static const double handleGutter = 8.0;

  const OutlineTableBlock({
    super.key,
    required this.table,
    required this.colorScheme,
    required this.fontSize,
    required this.readOnly,
    required this.onChanged,
    this.onBeforeChange,
    this.onDeleteTable,
  });

  @override
  State<OutlineTableBlock> createState() => _OutlineTableBlockState();
}

class _OutlineTableBlockState extends State<OutlineTableBlock>
    implements MobileTableToolbarSource {
  /// 列宽下限
  static const double _minColumnWidth = 96.0;

  /// 自动测量时的列宽上限
  static const double _maxColumnWidth = 280.0;

  /// 手动拖动调整列宽时的上限
  static const double _maxDragColumnWidth = 640.0;

  /// 单元格水平内边距
  static const double _cellHorizontalPadding = 12.0;

  /// 单元格垂直内边距
  static const double _cellVerticalPadding = 8.0;

  /// 表格右侧与下方为「+」按钮预留的宽度
  static const double _addControlGutter = 28.0;

  /// 「+」按钮的直径
  static const double _addControlSize = 22.0;

  /// 横向滚动条与表格底部之间的空隙
  static const double _scrollbarGap = 2.0;

  /// 单元格文本行高倍数
  static const double _lineHeightFactor = 1.35;

  /// 行拖拽手柄的命中宽度
  static const double _rowHandleHitWidth = 10.0;

  /// 列拖拽手柄的命中高度
  static const double _columnHandleHitHeight = 8.0;

  /// 列宽拖拽条的命中宽度
  static const double _columnResizeHitWidth = 10.0;

  /// 表格外框线宽（单边）
  static const double _gridBorderWidth = 1.0;

  /// 表格外框圆角半径
  static const double _tableRadius = 4.0;

  /// 行拖拽手柄的可见宽度
  static const double _rowHandleBarWidth = 12.0;

  /// 行拖拽手柄的可见高度
  static const double _rowHandleBarHeight = 20.0;

  /// 列拖拽手柄的可见宽度
  static const double _columnHandleBarWidth = 24.0;

  /// 列拖拽手柄的可见高度
  static const double _columnHandleBarHeight = 12.0;

  /// 手柄描边宽度
  static const double _handleBorderWidth = 1.0;

  /// 行拖拽手柄压在边框线上时水平外溢的宽度
  ///
  /// 等于手柄宽度的一半加上半个外框线宽，保证手柄中心正好落在边框线上。
  static const double _rowHandleOverflowX = _rowHandleBarWidth / 2 + _gridBorderWidth / 2;

  /// 列拖拽手柄压在边框线上时垂直外溢的高度
  ///
  /// 等于手柄高度的一半加上半个外框线宽，保证手柄中心正好落在边框线上。
  static const double _columnHandleOverflowY =
      _columnHandleBarHeight / 2 + _gridBorderWidth / 2;

  /// 移动端列宽指示器的命中区域宽度
  static const double _mobileResizeHitWidth = 24.0;

  /// 移动端列宽指示器的命中区域高度
  static const double _mobileResizeHitHeight = 30.0;

  /// 移动端列宽指示器的可见尺寸
  static const double _mobileResizeBarWidth = 8.0;
  static const double _mobileResizeBarHeight = 28.0;

  /// 移动端选中单元格的高亮边框宽度
  static const double _mobileSelectionBorderWidth = 2.0;

  /// 单元格输入控制器（键为「行:列」）
  final Map<String, TextEditingController> _controllers = {};

  /// 单元格焦点节点（键为「行:列」）
  final Map<String, FocusNode> _focusNodes = {};

  /// 单元格根节点键（键为「行:列」）
  ///
  /// 用于按全局坐标定位指针所在的单元格，支撑拖拽选择与边距判定。
  final Map<String, GlobalKey> _cellKeys = {};

  /// 表格级焦点节点
  ///
  /// 多单元格选区存在时由表格持有焦点，使快捷键作用于整个选区。
  final FocusNode _tableFocusNode = FocusNode(debugLabel: 'outline-table', skipTraversal: true);

  /// 表格横向滚动控制器
  ///
  /// 供表格视口与横向滚动条共用，拖动滚动条即可左右移动表格。
  final ScrollController _horizontalScrollController = ScrollController();

  /// 各列当前宽度
  List<double> _columnWidths = const [];

  /// 鼠标是否悬停在表格上
  bool _isHovered = false;

  /// 是否有单元格持有焦点
  bool _hasFocusedCell = false;

  /// 当前单元格选区（null 表示没有选区）
  _CellRange? _selection;

  /// 选区基线单元格
  ///
  /// Shift+单击时从该单元格扩展到目标单元格。
  _CellPosition? _selectionAnchor;

  /// 当前活动单元格（最近一次点击、聚焦或右键的单元格）
  _CellPosition? _activeCell;

  /// 是否正在从单元格边距拖动选择单元格
  bool _isSelectingCells = false;

  /// 拖拽调宽时的起始列宽
  double _resizeStartWidth = 0.0;

  /// 拖拽调宽过程中的累计水平位移
  double _resizeDelta = 0.0;

  /// 当前悬停的行拖拽手柄所在行
  int? _hoveredRowHandle;

  /// 当前悬停的列拖拽手柄所在列
  int? _hoveredColumnHandle;

  /// 正在拖动的行（null 表示没有拖动行）
  int? _draggingRow;

  /// 正在拖动的列（null 表示没有拖动列）
  int? _draggingColumn;

  /// 行拖拽的落点间隙索引（null 表示暂无落点）
  ///
  /// 间隙索引表示插入到第几行之前，取值 0 到行数。
  int? _rowDropGap;

  /// 列拖拽的落点间隙索引（null 表示暂无落点）
  int? _columnDropGap;

  /// 行手柄层最近一次记录到的指针位置
  Offset? _rowHandlePointer;

  /// 列手柄层最近一次记录到的指针位置
  Offset? _columnHandlePointer;

  /// 行手柄层的渲染对象键，用于判断指针是否仍停在手柄层内
  final GlobalKey _rowHandleLayerKey = GlobalKey();

  /// 列手柄层的渲染对象键，用于判断指针是否仍停在手柄层内
  final GlobalKey _columnHandleLayerKey = GlobalKey();

  /// 拖动行或列时使用的抓取光标
  ///
  /// 系统 grab 光标在 Windows 端会回退成普通箭头，因此使用全局共享的自定义光标，
  /// 创建完成前与创建失败时退回系统光标。
  MouseCursor _dragCursor = DragCursor.current;

  /// 是否使用移动端交互
  bool get _isMobile => PlatformCapabilities.isMobile;

  /// 移动端单元格选中阶段
  _MobileCellStage _mobileStage = _MobileCellStage.none;

  /// 移动端是否处于单元格批量选择模式
  bool _mobileBatchMode = false;

  /// 批量选择模式下勾选的单元格（允许不连续）
  final Set<_CellPosition> _mobileBatchSelection = <_CellPosition>{};

  /// 批量选择模式下最近一次操作的单元格，退出模式时沿用为单选对象
  _CellPosition? _mobileBatchAnchor;

  /// 移动端正在拖动调整宽度的列（用于绘制贯穿表格的参考线）
  int? _mobileResizingColumn;

  /// 移动端单元格最近一次按下的全局坐标
  ///
  /// 第二次点击时据此把输入光标放到手指点击的位置。
  Offset _mobileLastTapPosition = Offset.zero;

  /// 移动端表格工具栏控制器
  MobileTableToolbarController? _mobileToolbarController;

  /// 是否已排定表格工具栏状态同步
  bool _mobileToolbarSyncScheduled = false;

  /// 表格网格层键，用于把单元格的全局矩形换算成网格局部坐标
  final GlobalKey _gridLayerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _columnWidths = _resolveColumnWidths();
    // 移动端不使用鼠标光标，避免加载桌面的自定义 grab 光标
    if (!_isMobile) _loadDragCursor();
  }

  /// 加载拖动行或列时使用的抓取光标
  void _loadDragCursor() async {
    final MouseCursor cursor = await DragCursor.load();
    if (!mounted || _dragCursor == cursor) return;
    setState(() => _dragCursor = cursor);
  }

  @override
  void didUpdateWidget(covariant OutlineTableBlock oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 外部替换表格数据（如撤销恢复）时同步单元格文本与列宽
    if (!identical(oldWidget.table, widget.table)) {
      _pruneCellResources();
      _syncCellTexts();
      _selection = null;
      _selectionAnchor = null;
      _activeCell = null;
      _resetMobileInteraction();
      _columnWidths = _resolveColumnWidths();
    } else if (oldWidget.fontSize != widget.fontSize) {
      _columnWidths = _resolveColumnWidths();
    }
  }

  @override
  void dispose() {
    for (final FocusNode node in _focusNodes.values) {
      node.removeListener(_handleCellFocusChanged);
      node.dispose();
    }
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    _tableFocusNode.dispose();
    _horizontalScrollController.dispose();
    // 表格销毁时解绑移动端快捷栏，避免工具栏停留在已消失的表格上
    MobileTableToolbarBinding.detach(_mobileToolbarController);
    _mobileToolbarController?.dispose();
    // 表格在拖拽中被移除时清除拖拽状态，避免编辑区的抓取光标覆盖层残留
    DragCursor.isDragging.value = false;
    super.dispose();
  }

  // ================= 移动端工具栏绑定 =================

  /// 排定一次表格工具栏状态同步
  ///
  /// 表格状态变化都会触发重建，重建后在帧末统一刷新工具栏，
  /// 避免在各个手势回调里逐个补通知，也避免在构建过程中触发监听器。
  void _scheduleMobileToolbarSync() {
    if (!_isMobile || !mounted || _mobileToolbarSyncScheduled) return;
    _mobileToolbarSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mobileToolbarSyncScheduled = false;
      if (mounted) _syncMobileToolbar();
    });
  }

  /// 同步移动端表格工具栏的绑定与状态
  void _syncMobileToolbar() {
    if (!_isMobile || !mounted) return;

    final bool active = !widget.readOnly &&
        (_mobileBatchMode || _mobileStage != _MobileCellStage.none);
    if (!active) {
      MobileTableToolbarBinding.detach(_mobileToolbarController);
      return;
    }

    final MobileTableToolbarController controller =
        _mobileToolbarController ??= MobileTableToolbarController(source: this);
    controller.tabId = context.read<WorkspaceProvider>().currentTab?.id;
    MobileTableToolbarBinding.attach(controller);
    controller.refresh();
  }

  /// 重置移动端交互状态（不改变已有选区等桌面端状态）
  void _resetMobileInteraction() {
    _mobileStage = _MobileCellStage.none;
    _mobileBatchMode = false;
    _mobileBatchSelection.clear();
    _mobileBatchAnchor = null;
    _mobileResizingColumn = null;
  }

  /// 移动端是否有一个非批量模式下的选中单元格
  bool get _hasMobileSelection =>
      _isMobile && !_mobileBatchMode && _mobileStage != _MobileCellStage.none;

  /// 移动端选中单元格所在行是否符合行排序条件（第一列且非表头）
  int? get _mobileRowDragRow {
    final _CellPosition? cell = _hasMobileSelection ? _activeCell : null;
    if (cell == null || cell.col != 0 || cell.row == 0) return null;
    return cell.row;
  }

  /// 移动端选中单元格所在列是否符合列排序条件（首行）
  int? get _mobileColumnDragCol {
    final _CellPosition? cell = _hasMobileSelection ? _activeCell : null;
    if (cell == null || cell.row != 0) return null;
    return cell.col;
  }

  // ================= 移动端工具栏数据源 =================

  @override
  bool get isBatchMode => _mobileBatchMode;

  @override
  int get selectedCellCount => _mobileBatchMode
      ? _mobileBatchSelection.length
      : (_mobileStage == _MobileCellStage.none ? 0 : 1);

  @override
  OutlineTableAlignment get alignment => widget.table.alignment;

  @override
  bool get canDeleteRow => widget.table.rowCount > 1;

  @override
  bool get canDeleteColumn => widget.table.columnCount > 1;

  @override
  int get currentHeadingLevel => _commonHeadingLevel;

  @override
  TextStyleFlags get currentTextStyleFlags => _mergedTextStyleFlags;

  @override
  ({bool isUniform, Color? color}) currentColor({required bool isForeground}) =>
      _targetColor(foreground: isForeground);

  @override
  void setHeadingLevel(int level) => _applyCellStyles((cell) => cell.headingLevel = level);

  @override
  void toggleTextStyle(TextStyleFlags Function(TextStyleFlags) toggleFn) =>
      _toggleCellTextStyle(toggleFn);

  @override
  void applyColor({
    Color? foregroundColor,
    Color? backgroundColor,
    bool clearForeground = false,
    bool clearBackground = false,
  }) {
    if (clearForeground) _applyCellForegroundColor(null);
    if (clearBackground) _applyCellBackgroundColor(null);
    if (foregroundColor != null) _applyCellForegroundColor(foregroundColor);
    if (backgroundColor != null) _applyCellBackgroundColor(backgroundColor);
  }

  @override
  void setAlignment(OutlineTableAlignment value) => _setTableAlignment(value);

  @override
  void clearContents() => _clearSelectedCellContents();

  @override
  void enterBatchMode() => _enterMobileBatchMode();

  @override
  void exitBatchMode() => _exitMobileBatchMode();

  @override
  void dismiss() => _dismissMobileSelection();

  @override
  void deleteRow() {
    final _CellPosition? cell = _activeCell;
    if (cell != null) _deleteRow(cell.row);
  }

  @override
  void deleteColumn() {
    final _CellPosition? cell = _activeCell;
    if (cell != null) _deleteColumn(cell.col);
  }

  @override
  void deleteTable() => widget.onDeleteTable?.call();

  // ================= 单元格资源 =================

  /// 生成单元格的映射键
  String _cellKeyOf(int row, int col) => '$row:$col';

  /// 为当前表格补齐单元格控制器与焦点节点
  void _ensureCellResources() {
    for (int row = 0; row < widget.table.rowCount; row++) {
      for (int col = 0; col < widget.table.columnCount; col++) {
        final String key = _cellKeyOf(row, col);
        final OutlineTableCell cell = widget.table.rows[row][col];
        _controllers.putIfAbsent(key, () => TextEditingController(text: cell.text));
        _focusNodes.putIfAbsent(key, () {
          final FocusNode node = FocusNode();
          node.addListener(_handleCellFocusChanged);
          return node;
        });
        _cellKeys.putIfAbsent(key, () => GlobalKey());
      }
    }
  }

  /// 释放已不存在的单元格资源
  void _pruneCellResources() {
    final Set<String> alive = {
      for (int row = 0; row < widget.table.rowCount; row++)
        for (int col = 0; col < widget.table.columnCount; col++) _cellKeyOf(row, col),
    };

    for (final String key in _controllers.keys.where((key) => !alive.contains(key)).toList()) {
      _controllers.remove(key)?.dispose();
      final FocusNode? node = _focusNodes.remove(key);
      if (node != null) {
        node.removeListener(_handleCellFocusChanged);
        node.dispose();
      }
      _cellKeys.remove(key);
    }
  }

  /// 把表格中的文本同步到单元格输入框
  ///
  /// 外部替换表格数据（撤销恢复）或删除、移动行列导致位置变化时同步文本，
  /// 聚焦中的单元格保留光标位置并收敛到文本范围内。
  void _syncCellTexts() {
    for (int row = 0; row < widget.table.rowCount; row++) {
      for (int col = 0; col < widget.table.columnCount; col++) {
        final String key = _cellKeyOf(row, col);
        final TextEditingController? controller = _controllers[key];
        if (controller == null) continue;
        final String text = widget.table.rows[row][col].text;
        if (controller.text == text) continue;

        final TextSelection selection = controller.selection;
        controller.text = text;
        if (selection.isValid) {
          controller.selection = TextSelection.collapsed(
            offset: selection.baseOffset.clamp(0, text.length).toInt(),
          );
        }
      }
    }
  }

  // ================= 列宽 =================

  /// 计算单元格文字样式
  ///
  /// 标题级别与节点一致，级别越高字号越大。
  TextStyle _cellTextStyle(OutlineTableCell cell) {
    final int level = cell.headingLevel;
    final double fontSize = widget.fontSize + (level == 0 ? 0 : (4 - level) * 2);
    final TextStyle base = TextStyle(
      fontFamily: SettingsService.instance.outlineFontFamily,
      fontSize: fontSize,
      height: _lineHeightFactor,
      color: widget.colorScheme.onSurface,
    );
    return defaultStyleResolver(base, cell.flags);
  }

  /// 测量单列的自然宽度
  double _naturalColumnWidth(OutlineTableCell cell) {
    final String text = cell.text;
    if (text.isEmpty) return _minColumnWidth;

    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: _cellTextStyle(cell)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final double width = painter.width + _cellHorizontalPadding * 2 + 2;
    painter.dispose();
    return width.clamp(_minColumnWidth, _maxColumnWidth).toDouble();
  }

  /// 按内容测量所有列的宽度
  List<double> _measureColumnWidths() {
    final int columnCount = widget.table.columnCount;
    if (columnCount == 0) return const [];

    final List<double> widths = [];
    for (int col = 0; col < columnCount; col++) {
      double width = _minColumnWidth;
      for (int row = 0; row < widget.table.rowCount; row++) {
        final double natural = _naturalColumnWidth(widget.table.rows[row][col]);
        if (natural > width) width = natural;
      }
      widths.add(width);
    }
    return widths;
  }

  /// 解析当前应使用的列宽
  ///
  /// 表格记录过固定列宽时以记录为准（用户拖动分隔线后不再随内容变化），
  /// 否则按内容自动测量。
  List<double> _resolveColumnWidths() {
    final List<double> fixed = widget.table.columnWidths;
    if (fixed.length == widget.table.columnCount) {
      return [
        for (final double width in fixed) width.clamp(_minColumnWidth, _maxDragColumnWidth).toDouble(),
      ];
    }
    return _measureColumnWidths();
  }

  /// 输入过程中只扩展列宽，避免文字在窄列中频繁换行
  void _growColumnWidths() {
    // 用户手动设定过列宽时保持固定宽度，超出内容靠换行容纳
    if (widget.table.columnWidths.isNotEmpty) return;

    final List<double> measured = _measureColumnWidths();
    if (measured.length != _columnWidths.length) {
      setState(() => _columnWidths = measured);
      return;
    }

    bool changed = false;
    for (int i = 0; i < measured.length; i++) {
      if (measured[i] > _columnWidths[i] + 0.5) {
        _columnWidths[i] = measured[i];
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  /// 重新计算列宽（允许按内容收缩）
  void _refreshColumnWidths() {
    if (!mounted) return;
    // 固定列宽不随内容收缩
    if (widget.table.columnWidths.isNotEmpty) return;
    final List<double> measured = _measureColumnWidths();
    if (_isSameWidths(measured, _columnWidths)) return;
    setState(() => _columnWidths = measured);
  }

  /// 判断两组列宽是否一致
  ///
  /// 浮点比较留出少量容差，避免亚像素差异触发无意义的重建。
  bool _isSameWidths(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  /// 开始拖动列分隔线
  void _startColumnResize(int col) {
    if (widget.readOnly || col >= _columnWidths.length) return;
    widget.onBeforeChange?.call();
    _resizeStartWidth = _columnWidths[col];
    _resizeDelta = 0.0;
  }

  /// 拖动列分隔线：仅改变当前列宽度，后续列保持原宽并整体右移
  void _updateColumnResize(int col, double delta) {
    if (widget.readOnly || col >= _columnWidths.length) return;
    _resizeDelta += delta;
    final double width = (_resizeStartWidth + _resizeDelta).clamp(_minColumnWidth, _maxDragColumnWidth);
    if ((_columnWidths[col] - width).abs() < 0.5) return;
    setState(() => _columnWidths[col] = width);
  }

  /// 结束拖动列分隔线：记录固定列宽并通知外部保存
  void _endColumnResize() {
    if (widget.readOnly) return;
    _resizeDelta = 0.0;
    widget.table.setColumnWidths(_columnWidths);
    widget.onChanged();
  }

  /// 设置整表水平对齐方式
  void _setTableAlignment(OutlineTableAlignment value) {
    if (widget.readOnly || widget.table.alignment == value) return;
    widget.onBeforeChange?.call();
    setState(() => widget.table.alignment = value);
    widget.onChanged();
  }

  // ================= 单元格选区 =================

  /// 样式操作的目标单元格
  ///
  /// 桌面端存在多单元格选区时取整个选区，否则取当前活动单元格；
  /// 移动端批量模式取所有勾选的单元格，否则取当前选中的单个单元格。
  List<OutlineTableCell> get _styleTargetCells {
    if (_isMobile) {
      return [
        for (final _CellPosition cell in _mobileTargetCells)
          if (cell.row < widget.table.rowCount && cell.col < widget.table.columnCount)
            widget.table.rows[cell.row][cell.col],
      ];
    }

    final _CellRange? selection = _selection;
    if (selection != null && !selection.isSingleCell) {
      return [
        for (int row = selection.startRow; row <= selection.endRow; row++)
          for (int col = selection.startColumn; col <= selection.endColumn; col++)
            if (row < widget.table.rowCount && col < widget.table.columnCount)
              widget.table.rows[row][col],
      ];
    }

    final _CellPosition? cell = _activeCell ?? _focusedCellPosition;
    if (cell == null) return const [];
    if (cell.row >= widget.table.rowCount || cell.col >= widget.table.columnCount) return const [];
    return [widget.table.rows[cell.row][cell.col]];
  }

  /// 移动端样式与清空操作覆盖的单元格坐标
  List<_CellPosition> get _mobileTargetCells {
    if (_mobileBatchMode) return _mobileBatchSelection.toList();
    final _CellPosition? cell = _activeCell;
    if (cell == null || _mobileStage == _MobileCellStage.none) return const <_CellPosition>[];
    return <_CellPosition>[cell];
  }

  /// 当前持有焦点的单元格
  _CellPosition? get _focusedCellPosition {
    for (int row = 0; row < widget.table.rowCount; row++) {
      for (int col = 0; col < widget.table.columnCount; col++) {
        if (_focusNodes[_cellKeyOf(row, col)]?.hasFocus ?? false) return (row: row, col: col);
      }
    }
    return null;
  }

  /// 合并目标单元格的文字样式标记
  ///
  /// 任一单元格开启某标记位即视为开启，用于决定切换后的统一状态。
  TextStyleFlags get _mergedTextStyleFlags {
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strikethrough = false;
    for (final OutlineTableCell cell in _styleTargetCells) {
      bold = bold || cell.flags.bold;
      italic = italic || cell.flags.italic;
      underline = underline || cell.flags.underline;
      strikethrough = strikethrough || cell.flags.strikethrough;
    }
    return TextStyleFlags(
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strikethrough,
    );
  }

  /// 目标单元格统一使用的标题级别
  ///
  /// 级别不一致时返回 -1，用于让标题级别按钮不点亮任何选项。
  int get _commonHeadingLevel {
    final List<OutlineTableCell> cells = _styleTargetCells;
    if (cells.isEmpty) return 0;
    final int first = cells.first.headingLevel;
    return cells.every((cell) => cell.headingLevel == first) ? first : -1;
  }

  /// 目标单元格统一使用的颜色
  ///
  /// [foreground] 为 true 时取字体颜色，否则取字底颜色；
  /// 颜色不一致时 isUniform 为 false。
  ({bool isUniform, Color? color}) _targetColor({required bool foreground}) {
    final List<OutlineTableCell> cells = _styleTargetCells;
    if (cells.isEmpty) return (isUniform: true, color: null);
    final Color? first = foreground ? cells.first.flags.foregroundColor : cells.first.flags.backgroundColor;
    final bool uniform = cells.every(
      (cell) => (foreground ? cell.flags.foregroundColor : cell.flags.backgroundColor) == first,
    );
    return (isUniform: uniform, color: uniform ? first : null);
  }

  /// 对目标单元格批量应用样式
  void _applyCellStyles(void Function(OutlineTableCell cell) apply) {
    final List<OutlineTableCell> cells = _styleTargetCells;
    if (cells.isEmpty) return;
    widget.onBeforeChange?.call();
    for (final OutlineTableCell cell in cells) {
      apply(cell);
    }
    _handleCellStyleChanged();
  }

  /// 按主导样式切换目标单元格的文字样式
  ///
  /// 只切换状态发生变化的标记位，其余标记位保持各单元格原值。
  void _toggleCellTextStyle(TextStyleFlags Function(TextStyleFlags) toggle) {
    final TextStyleFlags dominant = _mergedTextStyleFlags;
    final TextStyleFlags target = toggle(dominant);
    if (target.bold == dominant.bold &&
        target.italic == dominant.italic &&
        target.underline == dominant.underline &&
        target.strikethrough == dominant.strikethrough) {
      return;
    }

    _applyCellStyles((cell) {
      cell.flags = cell.flags.copyWith(
        bold: target.bold == dominant.bold ? null : target.bold,
        italic: target.italic == dominant.italic ? null : target.italic,
        underline: target.underline == dominant.underline ? null : target.underline,
        strikethrough: target.strikethrough == dominant.strikethrough ? null : target.strikethrough,
      );
    });
  }

  /// 设置目标单元格的字体颜色（null 表示恢复默认）
  void _applyCellForegroundColor(Color? color) {
    _applyCellStyles((cell) {
      cell.flags = color == null
          ? cell.flags.copyWith(clearForegroundColor: true)
          : cell.flags.copyWith(foregroundColor: color);
    });
  }

  /// 设置目标单元格的字底颜色（null 表示恢复默认）
  void _applyCellBackgroundColor(Color? color) {
    _applyCellStyles((cell) {
      cell.flags = color == null
          ? cell.flags.copyWith(clearBackgroundColor: true)
          : cell.flags.copyWith(backgroundColor: color);
    });
  }

  /// 清空选区内所有单元格的文本
  void _clearSelectedCellContents() {
    if (widget.readOnly) return;

    final List<_CellPosition> targets = <_CellPosition>[];
    if (_isMobile) {
      targets.addAll(_mobileTargetCells);
    } else {
      final _CellRange? selection = _selection;
      if (selection == null) return;
      for (int row = selection.startRow; row <= selection.endRow; row++) {
        for (int col = selection.startColumn; col <= selection.endColumn; col++) {
          targets.add((row: row, col: col));
        }
      }
    }
    if (targets.isEmpty) return;

    // 选区内容全为空时不做修改，避免产生空的撤销记录
    bool hasContent = false;
    for (final _CellPosition cell in targets) {
      if (cell.row >= widget.table.rowCount || cell.col >= widget.table.columnCount) continue;
      if (widget.table.rows[cell.row][cell.col].text.isNotEmpty) {
        hasContent = true;
        break;
      }
    }
    if (!hasContent) return;

    widget.onBeforeChange?.call();
    for (final _CellPosition cell in targets) {
      if (cell.row >= widget.table.rowCount || cell.col >= widget.table.columnCount) continue;
      widget.table.rows[cell.row][cell.col].text = '';
      _controllers[_cellKeyOf(cell.row, cell.col)]?.text = '';
    }

    _refreshColumnWidths();
    widget.onChanged();
  }

  /// 更新单元格选区
  void _setSelection(_CellRange? selection) {
    if (_selection == selection) return;
    setState(() => _selection = selection);
  }

  /// 清除单元格选区
  void _clearSelection() {
    if (_selection == null) return;
    setState(() => _selection = null);
  }

  /// 选中整个表格的单元格
  void _selectAllCells() {
    final int rowCount = widget.table.rowCount;
    final int columnCount = widget.table.columnCount;
    if (rowCount == 0 || columnCount == 0) return;

    _activeCell = (row: 0, col: 0);
    _selectionAnchor = _activeCell;
    _setSelection(_CellRange.between(0, 0, rowCount - 1, columnCount - 1));
    _tableFocusNode.requestFocus();
  }

  /// 获取单元格在屏幕坐标系中的矩形
  Rect? _cellRect(_CellPosition cell) {
    final BuildContext? cellContext = _cellKeys[_cellKeyOf(cell.row, cell.col)]?.currentContext;
    final RenderBox? box = cellContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 定位全局坐标所在的单元格
  ///
  /// [clampToTable] 为 true 时，落在表格外部的坐标取距离最近的单元格，
  /// 用于拖拽选择时把选区延伸到表格边缘。
  _CellPosition? _cellAtGlobalPosition(Offset globalPosition, {bool clampToTable = false}) {
    _CellPosition? nearest;
    double nearestDistance = double.infinity;

    for (int row = 0; row < widget.table.rowCount; row++) {
      for (int col = 0; col < widget.table.columnCount; col++) {
        final _CellPosition cell = (row: row, col: col);
        final Rect? rect = _cellRect(cell);
        if (rect == null) continue;
        if (rect.contains(globalPosition)) return cell;
        if (!clampToTable) continue;

        final double dx = globalPosition.dx < rect.left
            ? rect.left - globalPosition.dx
            : (globalPosition.dx > rect.right ? globalPosition.dx - rect.right : 0);
        final double dy = globalPosition.dy < rect.top
            ? rect.top - globalPosition.dy
            : (globalPosition.dy > rect.bottom ? globalPosition.dy - rect.bottom : 0);
        final double distance = dx * dx + dy * dy;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = cell;
        }
      }
    }
    return nearest;
  }

  /// 判断指针是否落在单元格的内边距上（文字区域之外）
  bool _isPointerInCellPadding(Offset globalPosition, _CellPosition cell) {
    final Rect? rect = _cellRect(cell);
    if (rect == null) return false;
    return globalPosition.dx < rect.left + _cellHorizontalPadding ||
        globalPosition.dx > rect.right - _cellHorizontalPadding ||
        globalPosition.dy < rect.top + _cellVerticalPadding ||
        globalPosition.dy > rect.bottom - _cellVerticalPadding;
  }

  /// 判断指针是否落在单元格的行列拖拽手柄或列宽拖拽条上
  bool _isPointerOnCellHandle(Offset globalPosition, _CellPosition cell) {
    if (widget.readOnly) return false;
    final Rect? rect = _cellRect(cell);
    if (rect == null) return false;

    final Offset local = globalPosition - rect.topLeft;
    // 第一行单元格顶部为列拖拽手柄、右边缘为列宽拖拽条
    if (cell.row == 0 && local.dy <= _columnHandleHitHeight) return true;
    if (cell.row == 0 && local.dx >= rect.width - _columnResizeHitWidth) return true;
    // 第一列非首行单元格左侧为行拖拽手柄
    if (cell.col == 0 && cell.row > 0 && local.dx <= _rowHandleHitWidth) return true;
    return false;
  }

  /// 处理表格内的指针按下：定位活动单元格、扩展或清除选区
  void _handleTablePointerDown(PointerDownEvent event) {
    if (widget.readOnly || event.buttons != kPrimaryButton) return;

    final _CellPosition? cell = _cellAtGlobalPosition(event.position);
    if (cell == null) {
      // 点击表格空白处时清除选区
      _clearSelection();
      return;
    }

    // 行列拖拽手柄与列宽拖拽条自行处理手势，不参与选区
    if (_isPointerOnCellHandle(event.position, cell)) return;

    _activeCell = cell;

    // Shift+单击：从选区基线扩展到目标单元格
    if (HardwareKeyboard.instance.isShiftPressed) {
      final _CellPosition anchor = _selectionAnchor ?? cell;
      _selectionAnchor = anchor;
      _setSelection(_CellRange.between(anchor.row, anchor.col, cell.row, cell.col));
      return;
    }

    // 普通按下清除已有选区，并从单元格边距开始拖动选择
    _clearSelection();
    _selectionAnchor = cell;
    _isSelectingCells = _isPointerInCellPadding(event.position, cell);
  }

  /// 处理表格内的指针移动：拖拽选择时把选区延伸到指针所在单元格
  void _handleTablePointerMove(PointerMoveEvent event) {
    if (!_isSelectingCells) return;
    final _CellPosition? anchor = _selectionAnchor;
    if (anchor == null) return;

    final _CellPosition? cell = _cellAtGlobalPosition(event.position, clampToTable: true);
    if (cell == null) return;
    _setSelection(_CellRange.between(anchor.row, anchor.col, cell.row, cell.col));
  }

  /// 处理表格内的指针抬起：结束拖拽选择并把焦点交给表格
  void _handleTablePointerUp(PointerUpEvent event) {
    if (!_isSelectingCells) return;
    _isSelectingCells = false;

    // 未拖动到其他单元格时不保留选区
    final _CellRange? selection = _selection;
    if (selection != null && selection.isSingleCell) {
      _clearSelection();
    } else if (selection != null) {
      _tableFocusNode.requestFocus();
    }
  }

  // ================= 移动端单元格交互 =================

  /// 处理移动端单元格点击
  ///
  /// 批量模式下只切换勾选状态；普通模式下第一次点击选中单元格（显示高亮边框、
  /// 拖拽手柄与底部快捷栏），第二次点击同一单元格才聚焦输入框。
  void _handleMobileCellTap(int row, int col, Offset globalPosition) {
    if (!_isMobile || widget.readOnly) return;
    final _CellPosition cell = (row: row, col: col);

    if (_mobileBatchMode) {
      setState(() {
        if (!_mobileBatchSelection.add(cell)) _mobileBatchSelection.remove(cell);
        _mobileBatchAnchor = cell;
      });
      return;
    }

    final bool sameSelectedCell =
        _activeCell == cell && _mobileStage != _MobileCellStage.none;
    if (sameSelectedCell && _mobileStage == _MobileCellStage.selected) {
      _focusMobileCell(cell, globalPosition);
      return;
    }
    if (sameSelectedCell) return;

    // 首次点击：收起可能已弹出的软键盘，只保留单元格选中态
    _releaseInputFocus();
    setState(() {
      _activeCell = cell;
      _selectionAnchor = cell;
      _selection = null;
      _isSelectingCells = false;
      _mobileStage = _MobileCellStage.selected;
    });
  }

  /// 第二次点击后把输入光标交给单元格输入框
  ///
  /// 借助 [RenderEditable] 把点击位置换算为文本偏移，光标落在手指点击处；
  /// 无法定位时退回到文本末尾。
  void _focusMobileCell(_CellPosition cell, Offset globalPosition) {
    final String key = _cellKeyOf(cell.row, cell.col);
    final TextEditingController? controller = _controllers[key];
    final FocusNode? node = _focusNodes[key];
    if (controller == null || node == null) return;

    int offset = controller.text.length;
    final RenderEditable? editable = _renderEditableOf(cell);
    if (editable != null && editable.attached) {
      final int candidate = editable.getPositionForPoint(globalPosition).offset;
      offset = candidate.clamp(0, controller.text.length).toInt();
    }
    controller.selection = TextSelection.collapsed(offset: offset);

    if (!mounted) return;
    setState(() => _mobileStage = _MobileCellStage.editing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.canRequestFocus) node.requestFocus();
    });
  }

  /// 查找单元格输入框对应的 [RenderEditable]
  RenderEditable? _renderEditableOf(_CellPosition cell) {
    final RenderObject? root =
        _cellKeys[_cellKeyOf(cell.row, cell.col)]?.currentContext?.findRenderObject();
    if (root == null) return null;
    return _findRenderEditable(root);
  }

  /// 在渲染树中递归查找 [RenderEditable]
  RenderEditable? _findRenderEditable(RenderObject object) {
    if (object is RenderEditable) return object;
    RenderEditable? found;
    object.visitChildren((RenderObject child) {
      found ??= _findRenderEditable(child);
    });
    return found;
  }

  /// 释放当前输入焦点，隐藏软键盘
  void _releaseInputFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_tableFocusNode.hasFocus) _tableFocusNode.unfocus();
  }

  /// 只释放表格自身持有的焦点
  ///
  /// 取消选中时焦点可能已交给节点输入框，此时不应把节点的键盘一并收起。
  void _unfocusTableCells() {
    for (final FocusNode node in _focusNodes.values) {
      if (node.hasFocus) node.unfocus();
    }
    if (_tableFocusNode.hasFocus) _tableFocusNode.unfocus();
  }

  /// 进入单元格批量选择模式
  ///
  /// 进入后所有单元格都不再响应聚焦，只切换勾选状态；
  /// 当前选中的单元格作为初始勾选项，方便直接对它套用样式。
  void _enterMobileBatchMode() {
    if (!_isMobile || widget.readOnly) return;
    final _CellPosition? seed = _activeCell;
    _releaseInputFocus();
    setState(() {
      _mobileBatchMode = true;
      _mobileBatchSelection.clear();
      if (seed != null) _mobileBatchSelection.add(seed);
      _mobileBatchAnchor = seed;
      _mobileStage = _MobileCellStage.none;
      _selection = null;
      _selectionAnchor = null;
      _mobileResizingColumn = null;
    });
  }

  /// 退出单元格批量选择模式
  ///
  /// 回到单选态，沿用最近一次操作的已勾选单元格，底部快捷栏恢复常规样式操作。
  void _exitMobileBatchMode() {
    if (!_isMobile || !_mobileBatchMode) return;
    final _CellPosition? anchor = _mobileBatchAnchor;
    final _CellPosition? last = anchor != null && _mobileBatchSelection.contains(anchor)
        ? anchor
        : (_mobileBatchSelection.isEmpty ? null : _mobileBatchSelection.last);
    _resetMobileInteraction();
    setState(() {
      _activeCell = last;
      _mobileStage = last == null ? _MobileCellStage.none : _MobileCellStage.selected;
    });
  }

  /// 取消移动端选中态并收起快捷栏
  void _dismissMobileSelection() {
    if (!_isMobile || !mounted) return;
    final bool hadState = _mobileBatchMode || _mobileStage != _MobileCellStage.none;
    _resetMobileInteraction();
    _activeCell = null;
    _selection = null;
    _selectionAnchor = null;
    _unfocusTableCells();
    MobileTableToolbarBinding.detach(_mobileToolbarController);
    if (hadState) setState(() {});
  }

  /// 构建移动端单元格文字选择工具栏
  ///
  /// 编辑态长按选中单元格内文字后，在选区上方弹出剪切、复制、粘贴、全选；
  /// 未选中文字时只保留粘贴与全选，只读表格只保留复制与全选。
  Widget _buildMobileCellSelectionToolbar(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
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

  // ================= 行列拖拽（桌面与移动端共用） =================

  /// 开始拖动某一行
  void _startRowDrag(int? row) {
    if (row == null || !mounted) return;
    // 移动端由 LongPressDraggable 触发，其自带的 hapticFeedbackOnStart 已给出触觉反馈
    DragCursor.isDragging.value = true;
    setState(() {
      _draggingRow = row;
      _hoveredRowHandle = null;
      _hoveredColumnHandle = null;
      _rowDropGap = null;
      _columnDropGap = null;
    });
  }

  /// 拖动过程中按指针位置更新行落点
  void _updateRowDrag(Offset globalPosition) {
    _rowHandlePointer = globalPosition;
    _updateRowDropGap(globalPosition);
  }

  /// 结束拖动行并按落点移动
  void _endRowDrag() {
    final int? from = _draggingRow;
    final int? gap = _rowDropGap;
    DragCursor.isDragging.value = false;
    if (!mounted) return;
    setState(() {
      _draggingRow = null;
      _rowDropGap = null;
    });
    if (from != null && gap != null) {
      _moveRow(from, gap > from ? gap - 1 : gap);
    }
    if (!_isMobile) _restoreRowHandleHover();
  }

  /// 开始拖动某一列
  void _startColumnDrag(int? col) {
    if (col == null || !mounted) return;
    DragCursor.isDragging.value = true;
    setState(() {
      _draggingColumn = col;
      _hoveredRowHandle = null;
      _hoveredColumnHandle = null;
      _rowDropGap = null;
      _columnDropGap = null;
    });
  }

  /// 拖动过程中按指针位置更新列落点
  void _updateColumnDrag(Offset globalPosition) {
    _columnHandlePointer = globalPosition;
    _updateColumnDropGap(globalPosition);
  }

  /// 结束拖动列并按落点移动
  void _endColumnDrag() {
    final int? from = _draggingColumn;
    final int? gap = _columnDropGap;
    DragCursor.isDragging.value = false;
    if (!mounted) return;
    setState(() {
      _draggingColumn = null;
      _columnDropGap = null;
    });
    if (from != null && gap != null) {
      _moveColumn(from, gap > from ? gap - 1 : gap);
    }
    if (!_isMobile) _restoreColumnHandleHover();
  }

  // ================= 单元格交互 =================

  /// 单元格焦点变化时刷新「+」入口与列宽
  void _handleCellFocusChanged() {
    if (!mounted) return;

    final _CellPosition? focused = _focusedCellPosition;
    if (focused != null) {
      // 输入框获得焦点后同步活动单元格，供样式快捷键使用
      _activeCell = focused;
    }

    final bool hasFocus = _focusNodes.values.any((node) => node.hasFocus);
    // 输入框失焦（如收起软键盘）后退回单选态，重新显示选中边框与拖拽手柄
    if (_isMobile && !hasFocus && _mobileStage == _MobileCellStage.editing) {
      _mobileStage = _MobileCellStage.selected;
    }
    if (hasFocus == _hasFocusedCell) {
      if (!hasFocus) _scheduleColumnShrink();
      return;
    }

    // 布局阶段释放单元格焦点时延后重建，避免在构建过程中修改状态
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _hasFocusedCell = hasFocus);
      });
    } else {
      setState(() => _hasFocusedCell = hasFocus);
    }

    if (!hasFocus) _scheduleColumnShrink();
  }

  /// 单元格全部失焦后按最终内容收缩列宽
  void _scheduleColumnShrink() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 右键菜单显示期间输入框会暂时失焦，此时不收缩列宽，避免表格尺寸跳动
      if (ContextMenu.isMenuShowing()) return;
      if (_focusNodes.values.any((node) => node.hasFocus)) return;
      _refreshColumnWidths();
    });
  }

  /// 把焦点交给指定单元格
  void _focusCell(int row, int col) {
    // 新增行列时输入框尚未构建，先补齐对应的控制器与焦点节点
    _ensureCellResources();
    final FocusNode? node = _focusNodes[_cellKeyOf(row, col)];
    if (node == null) return;
    _activeCell = (row: row, col: col);
    _selectionAnchor = _activeCell;
    // 表格可能刚刚新增行列，需要等待对应输入框构建完成后再聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.canRequestFocus) node.requestFocus();
    });
  }

  /// 处理单元格键盘事件
  ///
  /// Tab / Shift+Tab 移动到相邻单元格，末尾继续向后移动时自动补一行；
  /// Esc 清除多单元格选区后保持在单元格内，避免编辑器把焦点移回节点文字。
  KeyEventResult _handleCellKey(int row, int col, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    _activeCell = (row: row, col: col);

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Esc 保持在单元格内，避免编辑器把焦点移回节点文字
      if (_selection != null) _clearSelection();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _moveCellFocus(row, col, forward: !HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    return _handleStyleShortcuts(event);
  }

  /// 处理表格级键盘事件
  ///
  /// 多单元格选区存在且由表格持有焦点时接收按键：
  /// Delete / Backspace 清空选区内容，其余样式快捷键交给统一样式处理。
  KeyEventResult _handleTableKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selection != null) {
        _clearSelection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if ((event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) &&
        _selection != null) {
      _clearSelectedCellContents();
      return KeyEventResult.handled;
    }

    return _handleStyleShortcuts(event);
  }

  /// 处理表格内的样式与全选快捷键
  ///
  /// 与节点编辑器保持一致的按键组合，作用于当前单元格或整个单元格选区。
  KeyEventResult _handleStyleShortcuts(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.ignored;

    final bool isCommand =
        HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final bool isAlt = HardwareKeyboard.instance.isAltPressed;

    // Ctrl/Cmd+A：在多选与全选单元格之间切换
    if (isCommand && !isAlt && event.logicalKey == LogicalKeyboardKey.keyA) {
      if (_selection != null) {
        _clearSelection();
        return KeyEventResult.handled;
      }

      // 单元格文本尚未全选时，交给输入框执行全选文本
      final _CellPosition? focused = _focusedCellPosition;
      if (focused != null) {
        final TextEditingController? controller = _controllers[_cellKeyOf(focused.row, focused.col)];
        final TextSelection? textSelection = controller?.selection;
        final bool fullySelected =
            controller == null ||
            controller.text.isEmpty ||
            (textSelection != null &&
                textSelection.isValid &&
                !textSelection.isCollapsed &&
                textSelection.start == 0 &&
                textSelection.end == controller.text.length);
        if (!fullySelected) return KeyEventResult.ignored;
      }

      _selectAllCells();
      return KeyEventResult.handled;
    }

    if (widget.table.rowCount == 0) return KeyEventResult.ignored;

    // Ctrl/Cmd+B/I/U：加粗、斜体、下划线；Ctrl/Cmd+Enter：删除线
    if (isCommand && !isAlt) {
      if (event.logicalKey == LogicalKeyboardKey.keyB) {
        _toggleCellTextStyle(TextStyleFlags.toggleBold);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyI) {
        _toggleCellTextStyle(TextStyleFlags.toggleItalic);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyU) {
        _toggleCellTextStyle(TextStyleFlags.toggleUnderline);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        _toggleCellTextStyle(TextStyleFlags.toggleStrikethrough);
        return KeyEventResult.handled;
      }
    }

    // Alt+数字：设置标题级别
    if (isAlt && !isCommand) {
      final int? level = OutlineShortcutKeys.headingLevelFromKey(event.logicalKey);
      if (level != null) {
        _applyCellStyles((cell) => cell.headingLevel = level);
        return KeyEventResult.handled;
      }

      // Alt+字母：设置字体颜色（D 为清除）
      if (OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
        if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
          _applyCellForegroundColor(null);
        } else {
          _applyCellForegroundColor(OutlineShortcutKeys.foregroundColor(event.logicalKey));
        }
        return KeyEventResult.handled;
      }
    }

    // Ctrl/Cmd+Alt+字母：设置字底颜色（D 为清除）
    if (isCommand && isAlt && OutlineShortcutKeys.isColorLetterKey(event.logicalKey)) {
      if (OutlineShortcutKeys.isClearColorKey(event.logicalKey)) {
        _applyCellBackgroundColor(null);
      } else {
        _applyCellBackgroundColor(OutlineShortcutKeys.backgroundColor(event.logicalKey));
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 按 Tab 方向移动单元格焦点
  void _moveCellFocus(int row, int col, {required bool forward}) {
    final int columnCount = widget.table.columnCount;
    final int total = widget.table.rowCount * columnCount;
    int index = row * columnCount + col + (forward ? 1 : -1);

    // 从最后一格继续向后移动时追加一行，落点为新行首格
    if (index >= total) {
      _appendRow();
      index = total;
    }
    if (index < 0) index = 0;

    _focusCell(index ~/ columnCount, index % columnCount);
  }

  /// 处理单元格右键：保留已有选区，在指针位置弹出样式菜单
  void _handleCellSecondaryTap(int row, int col, Offset globalPosition) {
    if (widget.readOnly) return;

    final _CellPosition cell = (row: row, col: col);
    _activeCell = cell;

    // 右键落在选区外时选区改为该单元格，落在选区内时保持原选区
    if (_selection != null && !_selection!.contains(row, col)) {
      _clearSelection();
    }
    _selectionAnchor = cell;

    // 单选时聚焦单元格，右键菜单关闭后可继续编辑
    if (_selection == null) {
      _focusNodes[_cellKeyOf(row, col)]?.requestFocus();
    }

    ContextMenu.showMenuAt(
      context: context,
      position: globalPosition,
      menuItems: _buildCellContextMenu(row, col),
      onDismissed: _handleCellContextMenuDismissed,
    );
  }

  /// 单元格右键菜单关闭后恢复焦点
  ///
  /// 菜单显示期间会抢走单元格焦点，关闭后恢复，
  /// 使选区与光标状态得以保留，可直接继续编辑或使用快捷键。
  void _handleCellContextMenuDismissed() {
    if (!mounted) return;

    if (_selection != null) {
      _tableFocusNode.requestFocus();
      return;
    }

    final _CellPosition? cell = _activeCell;
    if (cell == null) return;
    final FocusNode? node = _focusNodes[_cellKeyOf(cell.row, cell.col)];
    if (node != null && !node.hasFocus) node.requestFocus();
  }

  /// 追加一行
  void _appendRow() {
    widget.onBeforeChange?.call();
    setState(() {
      widget.table.addRow();
    });
    widget.onChanged();
  }

  /// 追加一列
  void _appendColumn() {
    widget.onBeforeChange?.call();
    setState(() {
      widget.table.addColumn(width: _minColumnWidth);
      _columnWidths = [..._columnWidths, _minColumnWidth];
    });
    widget.onChanged();
  }

  /// 删除指定行
  void _deleteRow(int row) {
    if (_isMobile) _resetMobileInteraction();
    _selection = null;
    _selectionAnchor = null;
    _activeCell = null;
    _hoveredRowHandle = null;
    widget.onBeforeChange?.call();
    setState(() {
      if (widget.table.removeRow(row)) {
        _columnWidths = _resolveColumnWidths();
      }
    });
    _pruneCellResources();
    // 行索引整体前移，同步非聚焦单元格的文本
    _syncCellTexts();
    widget.onChanged();
  }

  /// 删除指定列
  void _deleteColumn(int col) {
    if (_isMobile) _resetMobileInteraction();
    _selection = null;
    _selectionAnchor = null;
    _activeCell = null;
    _hoveredColumnHandle = null;
    widget.onBeforeChange?.call();
    setState(() {
      if (widget.table.removeColumn(col)) {
        _columnWidths = _resolveColumnWidths();
      }
    });
    _pruneCellResources();
    // 列索引整体前移，同步非聚焦单元格的文本
    _syncCellTexts();
    widget.onChanged();
  }

  /// 按指针位置更新行拖拽的落点
  ///
  /// 指针可以落在表格之外，此时按最近的单元格反推所在行，因此拖动过程中
  /// 不必把指针移回表格内也能看到插入位置；指针位于该行上半部分时插入到
  /// 该行之前，位于下半部分时插入到下一行之前。
  void _updateRowDropGap(Offset globalPosition) {
    final _CellPosition? cell = _cellAtGlobalPosition(globalPosition, clampToTable: true);
    final Rect? rect = cell == null ? null : _rowRect(cell.row);
    if (cell == null || rect == null) return;
    final int gap = globalPosition.dy > rect.center.dy ? cell.row + 1 : cell.row;
    if (_rowDropGap == gap) return;
    setState(() => _rowDropGap = gap);
  }

  /// 按指针位置更新列拖拽的落点
  ///
  /// 指针可以落在表格之外，此时按最近的单元格反推所在列；指针位于该列
  /// 左半部分时插入到该列之前，位于右半部分时插入到下一列之前。
  void _updateColumnDropGap(Offset globalPosition) {
    final _CellPosition? cell = _cellAtGlobalPosition(globalPosition, clampToTable: true);
    final Rect? rect = cell == null ? null : _cellRect(cell);
    if (cell == null || rect == null) return;
    final int gap = globalPosition.dx > rect.center.dx ? cell.col + 1 : cell.col;
    if (_columnDropGap == gap) return;
    setState(() => _columnDropGap = gap);
  }

  /// 按指针位置更新悬停的行手柄
  ///
  /// 指针可以位于表格边框之外，因此按最近的单元格反推所在行；表头不提供行手柄。
  void _updateHoveredRowHandle(Offset globalPosition) {
    _rowHandlePointer = globalPosition;
    final _CellPosition? cell = _cellAtGlobalPosition(globalPosition, clampToTable: true);
    _setHoveredRowHandle(cell == null || cell.row == 0 ? null : cell.row);
  }

  /// 记录悬停的行手柄
  void _setHoveredRowHandle(int? row) {
    if (_hoveredRowHandle == row) return;
    // 拖动期间仅记录悬停行，不重建界面，避免其他行手柄闪烁
    if (_isDraggingStructure) {
      _hoveredRowHandle = row;
      return;
    }
    setState(() => _hoveredRowHandle = row);
  }

  /// 按指针位置更新悬停的列手柄
  void _updateHoveredColumnHandle(Offset globalPosition) {
    _columnHandlePointer = globalPosition;
    final _CellPosition? cell = _cellAtGlobalPosition(globalPosition, clampToTable: true);
    _setHoveredColumnHandle(cell?.col);
  }

  /// 记录悬停的列手柄
  void _setHoveredColumnHandle(int? col) {
    if (_hoveredColumnHandle == col) return;
    // 拖动期间仅记录悬停列，不重建界面，避免其他列手柄闪烁
    if (_isDraggingStructure) {
      _hoveredColumnHandle = col;
      return;
    }
    setState(() => _hoveredColumnHandle = col);
  }

  /// 松开行拖拽后按最后的指针位置恢复手柄悬停
  ///
  /// 指针已离开手柄层时不恢复，避免表格外出现手柄。
  void _restoreRowHandleHover() {
    final Offset? pointer = _rowHandlePointer;
    final RenderBox? layer =
        _rowHandleLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (pointer == null || layer == null || !layer.attached) return;
    if (!(Offset.zero & layer.size).contains(layer.globalToLocal(pointer))) return;
    _updateHoveredRowHandle(pointer);
  }

  /// 松开列拖拽后按最后的指针位置恢复手柄悬停
  ///
  /// 指针已离开手柄层时不恢复，避免表格外出现手柄。
  void _restoreColumnHandleHover() {
    final Offset? pointer = _columnHandlePointer;
    final RenderBox? layer =
        _columnHandleLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (pointer == null || layer == null || !layer.attached) return;
    if (!(Offset.zero & layer.size).contains(layer.globalToLocal(pointer))) return;
    _updateHoveredColumnHandle(pointer);
  }

  /// 是否正在拖动行或列
  ///
  /// 拖动期间其他手柄与单元格不响应悬停，避免落点区域出现多余的悬停反馈。
  bool get _isDraggingStructure => _draggingRow != null || _draggingColumn != null;

  /// 行拖拽需要展示的插入间隙
  ///
  /// 落点与拖动源相邻时调整后位置不变，不展示插入线。
  int? get _activeRowDropGap {
    final int? gap = _rowDropGap;
    final int? from = _draggingRow;
    if (gap == null || from == null) return null;
    if (gap == from || gap == from + 1) return null;
    return gap;
  }

  /// 列拖拽需要展示的插入间隙
  int? get _activeColumnDropGap {
    final int? gap = _columnDropGap;
    final int? from = _draggingColumn;
    if (gap == null || from == null) return null;
    if (gap == from || gap == from + 1) return null;
    return gap;
  }

  /// 计算整行的矩形范围
  ///
  /// 同行单元格高度可能不同，取各单元格的并集作为行范围。
  Rect? _rowRect(int row) {
    Rect? rect;
    for (int col = 0; col < widget.table.columnCount; col++) {
      final Rect? cell = _cellRect((row: row, col: col));
      if (cell == null) continue;
      rect = rect == null
          ? cell
          : Rect.fromLTRB(
              rect.left < cell.left ? rect.left : cell.left,
              rect.top < cell.top ? rect.top : cell.top,
              rect.right > cell.right ? rect.right : cell.right,
              rect.bottom > cell.bottom ? rect.bottom : cell.bottom,
            );
    }
    return rect;
  }

  /// 移动行到指定位置
  void _moveRow(int from, int to) {
    if (from == to) return;
    if (_isMobile) _resetMobileInteraction();

    _selection = null;
    _selectionAnchor = null;
    _activeCell = null;
    _hoveredRowHandle = null;
    _rowDropGap = null;
    widget.onBeforeChange?.call();
    setState(() {
      if (!widget.table.moveRow(from, to)) return;
      // 行移动不改变列宽，自动列宽模式下按新内容重新测量
      if (widget.table.columnWidths.isEmpty) {
        _columnWidths = _measureColumnWidths();
      }
    });
    _syncCellTexts();
    widget.onChanged();
  }

  /// 移动列到指定位置
  void _moveColumn(int from, int to) {
    if (from == to) return;
    if (_isMobile) _resetMobileInteraction();

    _selection = null;
    _selectionAnchor = null;
    _activeCell = null;
    _hoveredColumnHandle = null;
    _columnDropGap = null;
    widget.onBeforeChange?.call();
    setState(() {
      if (!widget.table.moveColumn(from, to)) return;
      // 固定列宽随列一起移动，自动列宽模式按新内容重新测量
      _columnWidths = _resolveColumnWidths();
    });
    _syncCellTexts();
    widget.onChanged();
  }

  // ================= 单元格右键菜单 =================

  /// 构建单元格右键菜单
  ///
  /// 与节点右键菜单保持同一套结构与视觉：标题级别行、文字样式行、
  /// 字体颜色、字底颜色与对齐方式子菜单，其后提供删除行、删除列与删除表格。
  /// 样式项作用于当前单元格选区。
  List<ContextMenuItem> _buildCellContextMenu(int row, int col) {
    final TextStyleFlags mergedFlags = _mergedTextStyleFlags;
    final ({bool isUniform, Color? color}) foreground = _targetColor(foreground: true);
    final ({bool isUniform, Color? color}) background = _targetColor(foreground: false);

    return [
      // 标题级别行
      ContextMenuItem(
        label: HeadingLevelSelector(
          initialLevel: _commonHeadingLevel,
          onLevelChanged: (level) => _applyCellStyles((cell) => cell.headingLevel = level),
        ),
        enabled: false,
      ),
      // 文字样式行
      ContextMenuItem(
        label: TextStyleToggleRow(
          initialFlags: mergedFlags,
          onToggle: _toggleCellTextStyle,
        ),
        enabled: false,
      ),

      ContextMenuItem.divider(),

      // 字体颜色
      ContextMenuItem(
        labelText: '字体颜色',
        iconBuilder: (color) =>
            OutlineColorPalette.buildColorBarIcon(Icons.format_color_text, color, Colors.red),
        children: [
          for (final paletteColor in OutlineColorPalette.colors)
            ContextMenuItem(
              // 当前颜色与该色板一致时，文字前加 '·' 标记并高亮
              labelText: foreground.isUniform && foreground.color == paletteColor.foreground
                  ? '· ${paletteColor.name}'
                  : paletteColor.name,
              iconBuilder: (_) => OutlineColorPalette.buildColorSwatchIcon(paletteColor.foreground),
              labelColor: foreground.isUniform && foreground.color == paletteColor.foreground
                  ? paletteColor.foreground
                  : null,
              labelBold: foreground.isUniform && foreground.color == paletteColor.foreground,
              onTap: () => _applyCellForegroundColor(paletteColor.foreground),
            ),
          // 默认：清除字体颜色
          ContextMenuItem.divider(),
          ContextMenuItem(
            labelText: '默认',
            iconBuilder: (_) =>
                OutlineColorPalette.buildColorSwatchIcon(widget.colorScheme.onSurface),
            onTap: () => _applyCellForegroundColor(null),
          ),
        ],
      ),

      // 字底颜色
      ContextMenuItem(
        labelText: '字底颜色',
        iconBuilder: (color) =>
            OutlineColorPalette.buildColorBarIcon(Icons.format_color_fill, color, Colors.amber),
        children: [
          for (final paletteColor in OutlineColorPalette.colors)
            ContextMenuItem(
              // 当前字底色与该色板一致时，文字前加 '·' 标记并高亮
              labelText: background.isUniform && background.color == paletteColor.background
                  ? '· ${paletteColor.name}'
                  : paletteColor.name,
              iconBuilder: (_) => OutlineColorPalette.buildColorSwatchIcon(paletteColor.background),
              labelColor: background.isUniform && background.color == paletteColor.background
                  ? paletteColor.background
                  : null,
              labelBold: background.isUniform && background.color == paletteColor.background,
              onTap: () => _applyCellBackgroundColor(paletteColor.background),
            ),
          // 默认：清除字底颜色
          ContextMenuItem.divider(),
          ContextMenuItem(
            labelText: '默认',
            iconBuilder: (_) =>
                OutlineColorPalette.buildColorSwatchIcon(widget.colorScheme.surface),
            onTap: () => _applyCellBackgroundColor(null),
          ),
        ],
      ),

      // 对齐方式：作用于整个表格，当前选项加 '·' 标记并加粗
      ContextMenuItem(
        labelText: '对齐方式',
        icon: Icons.format_align_left,
        children: [
          for (final (alignment, label, icon) in const [
            (OutlineTableAlignment.left, '左对齐', Icons.format_align_left),
            (OutlineTableAlignment.center, '居中', Icons.format_align_center),
            (OutlineTableAlignment.right, '右对齐', Icons.format_align_right),
          ])
            ContextMenuItem(
              labelText: widget.table.alignment == alignment ? '· $label' : label,
              icon: icon,
              labelBold: widget.table.alignment == alignment,
              onTap: () => _setTableAlignment(alignment),
            ),
        ],
      ),

      ContextMenuItem.divider(),

      // 清空选区内容：仅在多单元格选区存在时可用
      ContextMenuItem(
        labelText: '清空单元格',
        icon: Icons.backspace_outlined,
        enabled: _selection != null,
        onTap: () => _clearSelectedCellContents(),
      ),

      ContextMenuItem(
        labelText: '删除行',
        icon: Icons.table_rows_outlined,
        enabled: widget.table.rowCount > 1,
        onTap: () => _deleteRow(row),
      ),
      ContextMenuItem(
        labelText: '删除列',
        icon: MaterialIcons.view_column,
        enabled: widget.table.columnCount > 1,
        onTap: () => _deleteColumn(col),
      ),

      ContextMenuItem.divider(),

      ContextMenuItem(
        labelText: '删除表格',
        icon: Icons.delete_sweep_outlined,
        labelColor: Colors.redAccent,
        onTap: () => widget.onDeleteTable?.call(),
      ),
    ];
  }

  /// 单元格样式变化后按新字号重算列宽并通知外部保存
  void _handleCellStyleChanged() {
    if (!mounted) return;
    setState(() => _columnWidths = _resolveColumnWidths());
    widget.onChanged();
  }

  // ================= 构建 =================

  @override
  Widget build(BuildContext context) {
    _ensureCellResources();
    // 移动端底部快捷栏是表格的兄弟子树，状态放到帧末统一同步
    if (_isMobile) _scheduleMobileToolbarSync();

    final List<double> widths = _columnWidths.length == widget.table.columnCount
        ? _columnWidths
        : _resolveColumnWidths();
    _columnWidths = widths;
    final double tableWidth = widths.fold(0.0, (sum, width) => sum + width);
    // 外框线占用左右各一条，手柄向表格外溢出也需要额外预留空白
    final double tableOuterWidth =
        tableWidth + _gridBorderWidth * 2 + OutlineTableBlock.handleGutter;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : tableOuterWidth + _addControlGutter;
        // 表格较窄时区域收缩到表格宽度，使「+」按钮紧贴表格；
        // 超出可用宽度时占据全部空间，由表格内部横向滚动
        final double tableAreaWidth =
            (availableWidth - _addControlGutter).clamp(0.0, tableOuterWidth).toDouble();

        final Widget grid = _buildGrid(widths);
        // 表格内容超出可用宽度时需要横向滚动并显示滚动条
        final bool hasOverflow = tableOuterWidth > tableAreaWidth + 0.5;

        // 移动端没有鼠标悬停，不安装 MouseRegion，避免悬停状态干扰触摸检测
        Widget stack = Stack(
          children: [
            // 右侧与下方各留出「+」按钮的位置
            Padding(
              padding: const EdgeInsets.only(
                right: _addControlGutter,
                bottom: _addControlGutter,
              ),
              child: _buildScrollArea(
                grid: grid,
                viewportWidth: tableAreaWidth,
                contentWidth: tableOuterWidth,
                hasOverflow: hasOverflow,
              ),
            ),
            if (!widget.readOnly) _buildAddControls(),
          ],
        );

        if (!_isMobile) {
          stack = MouseRegion(
            // 拖动行或列期间整表统一使用抓取光标
            cursor: _isDraggingStructure ? _dragCursor : MouseCursor.defer,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: stack,
          );
        }

        return Focus(
          focusNode: _tableFocusNode,
          onKeyEvent: _handleTableKey,
          child: stack,
        );
      },
    );
  }

  /// 构建可横向滚动的表格视口
  ///
  /// 始终使用横向滚动容器，拖动列宽时组件结构保持稳定，拖拽不会中断；
  /// 表格未超出可用宽度时禁用滚动，避免干扰单元格内的文字选择。
  /// 桌面端在内容显示不全时提供滚动条，滚动表格或悬停到滚动条上时显形，
  /// 停止滚动并移开后自动淡出；可拖动滚动条左右移动，
  /// 也可按住 Shift 滚动滚轮（横向滚动容器会把滚轮的纵向位移映射到横向）；
  /// 移动端不绘制滚动条，直接左右滑动表格。
  Widget _buildScrollArea({
    required Widget grid,
    required double viewportWidth,
    required double contentWidth,
    required bool hasOverflow,
  }) {
    // 桌面端在内容下方预留滚动条的位置，避免手柄压住最后一行文字
    final bool reserveScrollbar = hasOverflow && !PlatformCapabilities.isMobile;
    final double scrollbarGutter =
        reserveScrollbar ? editorScrollbarThickness + _scrollbarGap : 0.0;

    final Widget scrollView = SingleChildScrollView(
      controller: _horizontalScrollController,
      scrollDirection: Axis.horizontal,
      physics: hasOverflow ? null : const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.only(bottom: scrollbarGutter),
        child: SizedBox(width: contentWidth, child: grid),
      ),
    );

    if (PlatformCapabilities.isMobile) {
      return SizedBox(width: viewportWidth, child: scrollView);
    }

    return SizedBox(
      width: viewportWidth,
      child: _TableScrollbar(
        controller: _horizontalScrollController,
        colorScheme: widget.colorScheme,
        thickness: editorScrollbarThickness,
        radius: Radius.circular(editorScrollbarThickness / 2),
        // 左侧让出拖拽手柄的预留空白，使滚动条与表格边框对齐
        padding: const EdgeInsets.only(left: OutlineTableBlock.handleGutter),
        child: scrollView,
      ),
    );
  }

  /// 构建表格网格
  ///
  /// 行、列手柄层桌面端覆盖整条边框并按悬停定位，移动端只在选中首行或
  /// 第一列单元格时覆盖对应的一段并改为长按拖动，外观与拖动逻辑共用。
  Widget _buildGrid(List<double> widths) {
    final Color gridColor = widget.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Stack(
      key: _gridLayerKey,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: OutlineTableBlock.handleGutter,
            top: OutlineTableBlock.handleGutter,
          ),
          child: Listener(
            // 桌面端指针事件在表格层级统一处理，支撑单元格拖拽选择；
            // 移动端全部关闭，避免与单元格点击、长按排序手势互相干扰
            onPointerDown: _isMobile ? null : _handleTablePointerDown,
            onPointerMove: _isMobile ? null : _handleTablePointerMove,
            onPointerUp: _isMobile ? null : _handleTablePointerUp,
            onPointerCancel: _isMobile ? null : (_) => _isSelectingCells = false,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_tableRadius),
                border: Border.all(color: gridColor, width: _gridBorderWidth),
              ),
              // 手柄需要压在边框线上并向表格外溢出，因此不裁剪子组件
              clipBehavior: Clip.none,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int row = 0; row < widget.table.rowCount; row++)
                    _buildRow(row, widths, gridColor: gridColor),
                ],
              ),
            ),
          ),
        ),
        if (!widget.readOnly) ...[
          _buildRowHandleLayer(),
          _buildColumnHandleLayer(),
        ],
        if (_isMobile && !widget.readOnly) ..._buildMobileSelectionOverlay(widths),
      ],
    );
  }

  /// 构建单行
  ///
  /// 首行作为表头绘制浅色底，网格线绘制在文字下方，
  /// 行高由内容最高的单元格决定，内容较少的单元格也不会出现网格线断裂。
  /// 非只读时整行同时作为行拖拽的落点，拖动行手柄到任意行即可调整顺序。
  Widget _buildRow(
    int row,
    List<double> widths, {
    required Color gridColor,
  }) {
    final int? columnDropGap = _activeColumnDropGap;

    final Widget rowContent = Stack(
      // 插入线与手柄需要越出行边界绘制
      clipBehavior: Clip.none,
      children: [
        // 表头使用浅色底色，与正文行区分；
        // 表格不再裁剪内容，表头底色自行绘制出与边框一致的顶部圆角
        if (row == 0)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_tableRadius),
                ),
              ),
            ),
          ),
        // 正在拖动的行整行着色，明确当前操作对象
        if (_draggingRow == row)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: widget.colorScheme.primary.withValues(alpha: 0.08)),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OutlineTableGridPainter(
                columnWidths: widths,
                isLastRow: row == widget.table.rowCount - 1,
                gridColor: gridColor,
              ),
            ),
          ),
        ),
        Row(
          key: ValueKey('outline-table-row-$row'),
          // 行宽由单元格宽度之和决定，避免撑满整个编辑区宽度
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int col = 0; col < widths.length; col++) _buildCell(row, col, widths[col]),
          ],
        ),
        // 列拖拽的插入线跨越整张表格，每一行各画一段
        if (columnDropGap != null) _buildColumnInsertLine(columnDropGap, widths),
        // 移动端拖动列宽时绘制贯穿表格的参考线
        if (_isMobile && _mobileResizingColumn != null)
          _buildMobileColumnResizeGuide(_mobileResizingColumn!, widths),
        // 行拖拽的插入线绘制在目标行的上边界或下边界
        if (_activeRowDropGap == row) _buildRowInsertLine(top: true),
        if (_activeRowDropGap == row + 1) _buildRowInsertLine(top: false),
      ],
    );

    return rowContent;
  }

  /// 构建行拖拽的插入线
  Widget _buildRowInsertLine({required bool top}) {
    return Positioned(
      left: 0,
      right: 0,
      top: top ? -1 : null,
      bottom: top ? null : -1,
      height: 2,
      child: IgnorePointer(
        child: ColoredBox(color: widget.colorScheme.primary),
      ),
    );
  }

  /// 构建列拖拽的插入线
  ///
  /// 绘制在指定间隙处，跨越当前行的高度，多行叠加后形成贯穿表格的竖线。
  Widget _buildColumnInsertLine(int gap, List<double> widths) {
    double x = 0;
    for (int i = 0; i < gap && i < widths.length; i++) {
      x += widths[i];
    }
    final double tableWidth = widths.fold(0.0, (sum, width) => sum + width);
    final double left = (x - 1).clamp(-_gridBorderWidth, tableWidth - 1);

    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: 2,
      child: IgnorePointer(
        child: ColoredBox(color: widget.colorScheme.primary),
      ),
    );
  }

  /// 构建移动端调宽时的竖向参考线
  ///
  /// 位于正在调整列的右边缘，逐行绘制后形成贯穿整表的细线，
  /// 与表格类应用常见的列边界拖拽反馈一致。
  Widget _buildMobileColumnResizeGuide(int col, List<double> widths) {
    double x = 0;
    for (int i = 0; i <= col && i < widths.length; i++) {
      x += widths[i];
    }
    final double tableWidth = widths.fold(0.0, (sum, width) => sum + width);
    final double left = (x - 1).clamp(0.0, tableWidth - 1);

    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: 2,
      child: IgnorePointer(
        child: ColoredBox(color: widget.colorScheme.primary),
      ),
    );
  }

  /// 单元格文字水平对齐方式（与整表设置一致）
  TextAlign get _cellTextAlign {
    switch (widget.table.alignment) {
      case OutlineTableAlignment.left:
        return TextAlign.left;
      case OutlineTableAlignment.center:
        return TextAlign.center;
      case OutlineTableAlignment.right:
        return TextAlign.right;
    }
  }

  /// 构建单元格
  ///
  /// 移动端在未聚焦阶段用 [AbsorbPointer] 挡住输入框，改由覆盖层接收点击：
  /// 这样第一次点击不会弹出软键盘，也不会触发输入框自带的长按选词。
  Widget _buildCell(int row, int col, double width) {
    final String key = _cellKeyOf(row, col);
    final OutlineTableCell cell = widget.table.rows[row][col];
    final TextEditingController controller = _controllers[key]!;
    final FocusNode focusNode = _focusNodes[key]!;
    final bool selected = _selection?.contains(row, col) ?? false;
    final _CellPosition position = (row: row, col: col);

    final bool mobileActive = _hasMobileSelection && _activeCell == position;
    final bool batchSelected =
        _isMobile && _mobileBatchMode && _mobileBatchSelection.contains(position);
    final bool allowCellFocus = !_isMobile ||
        widget.readOnly ||
        (!_mobileBatchMode &&
            _mobileStage == _MobileCellStage.editing &&
            _activeCell == position);

    Widget input = Listener(
      // 单元格内边距同样响应右键，整个单元格都能唤起格式栏
      behavior: HitTestBehavior.opaque,
      // 移动端没有右键，长按由选中态控件显式处理，不安装任何长按检测
      onPointerDown: _isMobile
          ? null
          : (event) {
              if (event.buttons == kSecondaryButton) {
                _handleCellSecondaryTap(row, col, event.position);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _cellHorizontalPadding,
          vertical: _cellVerticalPadding,
        ),
        child: Focus(
          onKeyEvent: (node, event) => _handleCellKey(row, col, event),
          // 包裹输入法修复，使中文候选框跟随光标所在单元格
          child: ImeCursorFixerWrapper(
            controller: controller,
            focusNode: focusNode,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              readOnly: widget.readOnly,
              maxLines: null,
              minLines: 1,
              keyboardType: TextInputType.multiline,
              textAlign: _cellTextAlign,
              style: _cellTextStyle(cell),
              cursorColor: widget.colorScheme.primary,
              // 拖动行或列时整表使用抓取光标，避免经过其他单元格时出现文字光标
              mouseCursor: _isDraggingStructure ? _dragCursor : null,
              decoration: InputDecoration(
                isCollapsed: true,
                isDense: true,
                filled: false,
                // 关闭主题继承的圆角描边与底色，单元格边框由表格网格统一绘制
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              // 桌面端屏蔽输入框默认右键菜单，改用表格自身的右键菜单；
              // 移动端长按选中文字后弹出文字选择工具栏
              contextMenuBuilder: _isMobile
                  ? _buildMobileCellSelectionToolbar
                  : (context, editableTextState) => const SizedBox.shrink(),
              onChanged: (value) {
                if (cell.text == value) return;
                widget.onBeforeChange?.call();
                cell.text = value;
                // 输入时只扩展列宽，收缩留给失焦时处理
                _growColumnWidths();
                widget.onChanged();
              },
            ),
          ),
        ),
      ),
    );

    if (!allowCellFocus) {
      input = AbsorbPointer(absorbing: true, child: input);
    }

    final Widget cellContent = Stack(
      clipBehavior: Clip.none,
      children: [
        // 正在拖动的列整列着色，明确当前操作对象
        if (_draggingColumn == col)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: widget.colorScheme.primary.withValues(alpha: 0.08)),
            ),
          ),
        // 选中单元格的底色，绘制在文字下方
        if (selected || mobileActive || batchSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: widget.colorScheme.primary.withValues(
                  alpha: batchSelected ? 0.12 : (mobileActive ? 0.08 : 0.1),
                ),
              ),
            ),
          ),
        input,
        // 移动端单选单元格的四边高亮边框
        if (mobileActive)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.colorScheme.primary,
                    width: _mobileSelectionBorderWidth,
                  ),
                ),
              ),
            ),
          ),
        // 批量勾选：相邻已勾选单元格之间共享的边只画一次，避免边缘重叠变粗
        if (batchSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(border: _batchSelectionBorder(row, col)),
              ),
            ),
          ),
        // 未聚焦阶段统一由覆盖层处理点击：第一次选中、第二次聚焦
        if (_isMobile && !widget.readOnly && !allowCellFocus)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _mobileLastTapPosition = details.globalPosition,
              onTap: () => _handleMobileCellTap(row, col, _mobileLastTapPosition),
              child: const SizedBox.expand(),
            ),
          ),
        // 行列拖拽手柄外观：桌面端悬停显示，移动端选中首行/首列时显示
        if (!widget.readOnly && row == 0) _buildColumnHandleIndicator(col),
        if (!widget.readOnly && col == 0 && row > 0) _buildRowHandleIndicator(row),
        // 桌面端的列宽拖拽条（移动端改用选中态指示器）
        if (!_isMobile && !widget.readOnly && row == 0) _buildColumnResizeHandle(col),
      ],
    );

    return SizedBox(key: _cellKeys[key]!, width: width, child: cellContent);
  }

  /// 批量勾选单元格的边框
  ///
  /// 上方或左侧已勾选时省略本格的 top / left 边，共享边统一由靠上、靠左
  /// 那个单元格的 bottom / right 边绘制一次，避免相邻两个 2px 边框
  /// 叠成一条 4px 的粗线；不相邻的单元格仍是完整的四边框。
  Border _batchSelectionBorder(int row, int col) {
    final BorderSide side = BorderSide(
      color: widget.colorScheme.primary,
      width: _mobileSelectionBorderWidth,
    );
    // 用等宽透明边而不是 width=0，保证四角拼接形状与其它边一致
    final BorderSide hidden = BorderSide(
      color: Colors.transparent,
      width: _mobileSelectionBorderWidth,
    );
    return Border(
      top: _mobileBatchSelection.contains((row: row - 1, col: col)) ? hidden : side,
      bottom: side,
      left: _mobileBatchSelection.contains((row: row, col: col - 1)) ? hidden : side,
      right: side,
    );
  }

  // ================= 移动端选中态控件 =================

  /// 构建移动端选中态的附加控件
  ///
  /// 行列拖拽手柄的可见样式与拖动区域已完全复用桌面端实现；
  /// 批量勾选模式的边框由各单元格自己绘制，这里只负责首行列宽指示器。
  List<Widget> _buildMobileSelectionOverlay(List<double> widths) {
    if (!_hasMobileSelection) return const <Widget>[];
    final _CellPosition? cell = _activeCell;
    if (cell == null || cell.row != 0) return const <Widget>[];
    final Rect? rect = _localCellRect(cell);
    if (rect == null) return const <Widget>[];

    final double gridWidth = widths.fold(0.0, (sum, width) => sum + width) +
        _gridBorderWidth * 2 +
        OutlineTableBlock.handleGutter;
    return <Widget>[_buildMobileColumnResizeControl(cell.col, rect, gridWidth)];
  }

  /// 把单元格的全局矩形换算成网格层局部坐标
  Rect? _localCellRect(_CellPosition cell) {
    final Rect? global = _cellRect(cell);
    final RenderBox? box =
        _gridLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.attached) return null;
    return Rect.fromPoints(
      box.globalToLocal(global.topLeft),
      box.globalToLocal(global.bottomRight),
    );
  }

  /// 把左侧坐标收敛到网格层可命中的范围内
  double _clampControlLeft(double value, double width, double gridWidth) {
    final double maxLeft = gridWidth > width ? gridWidth - width : 0.0;
    return value < 0 ? 0.0 : (value > maxLeft ? maxLeft : value);
  }

  /// 移动端行拖拽手柄层的命中矩形（选中第一列非表头单元格时）
  Rect? _mobileRowDragRect() {
    if (_mobileRowDragRow == null) return null;
    final _CellPosition? cell = _activeCell;
    return cell == null ? null : _localCellRect(cell);
  }

  /// 移动端列拖拽手柄层的命中矩形（选中首行单元格时）
  Rect? _mobileColumnDragRect() {
    if (_mobileColumnDragCol == null) return null;
    final _CellPosition? cell = _activeCell;
    return cell == null ? null : _localCellRect(cell);
  }

  /// 构建首行选中时的列宽指示器
  ///
  /// 采用表格类应用常见的窄竖条：主色圆角竖条内嵌一条浅色握线，
  /// 拖动时沿列右边缘绘制贯穿整表的参考线。
  Widget _buildMobileColumnResizeControl(int col, Rect rect, double gridWidth) {
    final double height =
        rect.height < _mobileResizeHitHeight ? _mobileResizeHitHeight : rect.height;
    final double centeredTop = rect.center.dy - height / 2;
    final double top = centeredTop < 0 ? 0.0 : centeredTop;

    return Positioned(
      left: _clampControlLeft(
        rect.right - _mobileResizeHitWidth / 2,
        _mobileResizeHitWidth,
        gridWidth,
      ),
      top: top,
      width: _mobileResizeHitWidth,
      height: height,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            setState(() => _mobileResizingColumn = col);
            _startColumnResize(col);
          },
          onHorizontalDragUpdate: (details) =>
              _updateColumnResize(col, details.delta.dx),
          onHorizontalDragEnd: (_) => _finishMobileColumnResize(),
          onHorizontalDragCancel: _finishMobileColumnResize,
          child: SizedBox(
            width: _mobileResizeHitWidth,
            height: _mobileResizeHitHeight,
            child: Center(child: _buildMobileResizeBar()),
          ),
        ),
      ),
    );
  }

  /// 结束移动端列宽拖拽
  void _finishMobileColumnResize() {
    _endColumnResize();
    if (mounted) setState(() => _mobileResizingColumn = null);
  }

  /// 构建列宽拖拽指示器的外观
  Widget _buildMobileResizeBar() {
    return Container(
      width: _mobileResizeBarWidth,
      height: _mobileResizeBarHeight,
      decoration: BoxDecoration(
        color: widget.colorScheme.primary,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 2,
          height: 12,
          decoration: BoxDecoration(
            color: widget.colorScheme.onPrimary,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  /// 构建行手柄的拖动区域
  ///
  /// 桌面端覆盖整条左边框并按悬停位置反推行、立即拖动；移动端只在选中
  /// 第一列非表头单元格时覆盖该行对应的一段，改由长按拖动。
  /// 可见手柄、落点计算、插入线与移动逻辑两端完全共用。
  Widget _buildRowHandleLayer() {
    final Rect? mobileRect = _isMobile ? _mobileRowDragRect() : null;
    if (_isMobile && mobileRect == null) return const SizedBox.shrink();

    return Positioned(
      key: _rowHandleLayerKey,
      left: 0,
      top: _isMobile ? mobileRect!.top : OutlineTableBlock.handleGutter,
      bottom: _isMobile ? null : 0,
      height: _isMobile ? mobileRect!.height : null,
      width: OutlineTableBlock.handleGutter + _rowHandleHitWidth,
      // 拖动过程中让出指针，避免表格内的悬停反馈干扰拖拽
      child: IgnorePointer(
        ignoring: _isDraggingStructure,
        child: _isMobile
            ? LongPressDraggable<Object>(
                feedback: const SizedBox(width: 1, height: 1),
                dragAnchorStrategy: (draggable, context, position) => Offset.zero,
                onDragStarted: () => _startRowDrag(_mobileRowDragRow),
                onDragUpdate: (details) => _updateRowDrag(details.globalPosition),
                onDragEnd: (_) => _endRowDrag(),
                child: Container(color: Colors.transparent),
              )
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (event) => _updateHoveredRowHandle(event.position),
                onHover: (event) => _updateHoveredRowHandle(event.position),
                onExit: (_) => _setHoveredRowHandle(null),
                child: Draggable<Object>(
                  feedback: const SizedBox(width: 1, height: 1),
                  dragAnchorStrategy: (draggable, context, position) => Offset.zero,
                  onDragStarted: () => _startRowDrag(_hoveredRowHandle),
                  onDragUpdate: (details) => _updateRowDrag(details.globalPosition),
                  onDragEnd: (_) => _endRowDrag(),
                  child: Container(color: Colors.transparent),
                ),
              ),
      ),
    );
  }

  /// 构建列手柄的拖动区域
  ///
  /// 桌面端覆盖整条上边框并按悬停位置反推列、立即拖动；移动端只在选中
  /// 首行单元格时覆盖该列对应的一段，改由长按拖动。
  Widget _buildColumnHandleLayer() {
    final Rect? mobileRect = _isMobile ? _mobileColumnDragRect() : null;
    if (_isMobile && mobileRect == null) return const SizedBox.shrink();

    return Positioned(
      key: _columnHandleLayerKey,
      left: _isMobile ? mobileRect!.left : OutlineTableBlock.handleGutter,
      right: _isMobile ? null : 0,
      width: _isMobile ? mobileRect!.width : null,
      top: 0,
      height: OutlineTableBlock.handleGutter + _columnHandleHitHeight,
      // 拖动过程中让出指针，避免表格内的悬停反馈干扰拖拽
      child: IgnorePointer(
        ignoring: _isDraggingStructure,
        child: _isMobile
            ? LongPressDraggable<Object>(
                feedback: const SizedBox(width: 1, height: 1),
                dragAnchorStrategy: (draggable, context, position) => Offset.zero,
                onDragStarted: () => _startColumnDrag(_mobileColumnDragCol),
                onDragUpdate: (details) => _updateColumnDrag(details.globalPosition),
                onDragEnd: (_) => _endColumnDrag(),
                child: Container(color: Colors.transparent),
              )
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (event) => _updateHoveredColumnHandle(event.position),
                onHover: (event) => _updateHoveredColumnHandle(event.position),
                onExit: (_) => _setHoveredColumnHandle(null),
                child: Draggable<Object>(
                  feedback: const SizedBox(width: 1, height: 1),
                  dragAnchorStrategy: (draggable, context, position) => Offset.zero,
                  onDragStarted: () => _startColumnDrag(_hoveredColumnHandle),
                  onDragUpdate: (details) => _updateColumnDrag(details.globalPosition),
                  onDragEnd: (_) => _endColumnDrag(),
                  child: Container(color: Colors.transparent),
                ),
              ),
      ),
    );
  }

  /// 构建行拖拽手柄的外观
  ///
  /// 居中压在表格左边框线上，一半位于表格外侧；
  /// 桌面端悬停时出现，移动端选中第一列非表头单元格时出现。
  Widget _buildRowHandleIndicator(int row) {
    final bool visible = _isMobile
        ? _mobileRowDragRow == row
        : _hoveredRowHandle == row;

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: _rowHandleBarWidth,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            // 向左平移半个手柄宽度与半个边框线宽，使手柄居中压在表格左边框线上
            child: Transform.translate(
              offset: const Offset(-_rowHandleOverflowX, 0),
              child: _buildGripHandle(horizontal: false),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建列拖拽手柄的外观
  ///
  /// 居中压在表格上边框线上，一半位于表格外侧；
  /// 桌面端悬停时出现，移动端选中首行单元格时出现。
  Widget _buildColumnHandleIndicator(int col) {
    final bool visible = _isMobile
        ? _mobileColumnDragCol == col
        : _hoveredColumnHandle == col;

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: _columnHandleBarHeight,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            // 向上平移半个手柄高度与半个边框线宽，使手柄居中压在表格上边框线上
            child: Transform.translate(
              offset: const Offset(0, -_columnHandleOverflowY),
              child: _buildGripHandle(horizontal: true),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建抓取手柄的外观
  ///
  /// 浅色圆角底配描边与六个圆点，明确提示该处可以抓取拖动。
  Widget _buildGripHandle({required bool horizontal}) {
    final double width = horizontal ? _columnHandleBarWidth : _rowHandleBarWidth;
    final double height = horizontal ? _columnHandleBarHeight : _rowHandleBarHeight;
    // 圆点按短边缩放并留出描边宽度，使图标在描边内居中且不压线
    final double iconSize = (width < height ? width : height) - _handleBorderWidth * 2;
    final Widget grip = Icon(
      Icons.drag_indicator_rounded,
      size: iconSize,
      color: widget.colorScheme.onSurfaceVariant,
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: widget.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          width: _handleBorderWidth,
          color: widget.colorScheme.outlineVariant,
        ),
      ),
      child: Center(
        // 列手柄使用横向排列的圆点，与行手柄区分方向
        child: horizontal ? RotatedBox(quarterTurns: 1, child: grip) : grip,
      ),
    );
  }

  /// 构建列宽拖拽条
  ///
  /// 覆盖表头单元格的右边缘，拖动时只改变该列宽度，
  /// 其右侧的列保持原宽并整体平移。
  Widget _buildColumnResizeHandle(int col) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: _columnResizeHitWidth,
      child: MouseRegion(
        // 拖动行或列期间不再提示可调整列宽，统一使用抓取光标
        cursor: _isDraggingStructure ? _dragCursor : SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _startColumnResize(col),
          onHorizontalDragUpdate: (details) => _updateColumnResize(col, details.delta.dx),
          onHorizontalDragEnd: (_) => _endColumnResize(),
          onHorizontalDragCancel: _endColumnResize,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  /// 构建表格右侧与下方的「+」入口
  ///
  /// 桌面端随悬停、编辑或选区出现；移动端没有悬停状态，
  /// 改为选中单元格时显示，批量选择模式下隐藏。
  Widget _buildAddControls() {
    final bool visible = _isMobile
        ? (!_mobileBatchMode && _mobileStage != _MobileCellStage.none)
        : (_isHovered || _hasFocusedCell || _selection != null);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: Stack(
          children: [
            Positioned(
              right: 3,
              top: 3,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 140),
                child: _buildAddButton(
                  icon: Icons.add_rounded,
                  tooltip: '添加列',
                  onTap: _appendColumn,
                ),
              ),
            ),
            Positioned(
              left: 3,
              bottom: 3,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 140),
                child: _buildAddButton(
                  icon: Icons.add_rounded,
                  tooltip: '添加行',
                  onTap: _appendRow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建「+」按钮
  Widget _buildAddButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return CursorTooltipTarget(
      // 移动端的长按提示会与选中态的长按排序手势争抢指针，此处关闭
      showTooltip: !_isMobile,
      tooltipContent: Text(tooltip),
      child: Material(
        color: widget.colorScheme.surface,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: widget.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: _addControlSize,
            height: _addControlSize,
            child: Icon(
              icon,
              size: 15,
              color: widget.colorScheme.primary.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表格横向滚动条
///
/// 在 [RawScrollbar] 的基础上补充悬停与拖动时的颜色反馈，
/// 并支持只收缩左侧轨道，使滚动条起点与表格左边框对齐。
class _TableScrollbar extends RawScrollbar {
  const _TableScrollbar({
    required super.child,
    super.controller,
    super.thickness,
    super.radius,
    super.padding,
    required this.colorScheme,
  });

  /// 手柄配色使用的颜色方案
  final ColorScheme colorScheme;

  @override
  RawScrollbarState<_TableScrollbar> createState() => _TableScrollbarState();
}

class _TableScrollbarState extends RawScrollbarState<_TableScrollbar> {
  /// 指针是否悬停在滚动条上
  bool _isHovered = false;

  /// 是否正在拖动滚动条手柄
  bool _isDragging = false;

  /// 手柄颜色：拖动时最明显，悬停次之，静止时最淡
  Color get _thumbColor {
    final Color onSurface = widget.colorScheme.onSurface;
    final bool isDark = widget.colorScheme.brightness == Brightness.dark;
    if (_isDragging) return onSurface.withValues(alpha: isDark ? 0.75 : 0.6);
    if (_isHovered) return onSurface.withValues(alpha: isDark ? 0.65 : 0.5);
    return onSurface.withValues(alpha: isDark ? 0.3 : 0.1);
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    scrollbarPainter.color = _thumbColor;
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final bool hovered = isPointerOverScrollbar(event.position, event.kind, forHover: true);
    if (hovered == _isHovered) return;
    setState(() => _isHovered = hovered);
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    if (!_isHovered) return;
    setState(() => _isHovered = false);
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    if (_isDragging) return;
    setState(() => _isDragging = true);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    if (!_isDragging) return;
    setState(() => _isDragging = false);
  }
}

/// 单元格矩形选区
///
/// 记录选区的起止行列，构造时已归一化为左上角到右下角。
class _CellRange {
  /// 起始行
  final int startRow;

  /// 起始列
  final int startColumn;

  /// 结束行
  final int endRow;

  /// 结束列
  final int endColumn;

  const _CellRange({
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
  });

  /// 以两个单元格为对角构造选区
  factory _CellRange.between(int rowA, int columnA, int rowB, int columnB) {
    return _CellRange(
      startRow: rowA < rowB ? rowA : rowB,
      startColumn: columnA < columnB ? columnA : columnB,
      endRow: rowA > rowB ? rowA : rowB,
      endColumn: columnA > columnB ? columnA : columnB,
    );
  }

  /// 是否只包含一个单元格
  bool get isSingleCell => startRow == endRow && startColumn == endColumn;

  /// 是否包含指定单元格
  bool contains(int row, int column) =>
      row >= startRow && row <= endRow && column >= startColumn && column <= endColumn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CellRange &&
          startRow == other.startRow &&
          startColumn == other.startColumn &&
          endRow == other.endRow &&
          endColumn == other.endColumn;

  @override
  int get hashCode => Object.hash(startRow, startColumn, endRow, endColumn);
}

/// 表格网格线绘制器
///
/// 绘制列分隔线与行分隔线，行高由同行的单元格共同决定。
class _OutlineTableGridPainter extends CustomPainter {
  /// 各列宽度
  final List<double> columnWidths;

  /// 是否为最后一行（最后一行不留底部分隔线）
  final bool isLastRow;

  /// 网格线颜色
  final Color gridColor;

  const _OutlineTableGridPainter({
    required this.columnWidths,
    required this.isLastRow,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    double x = 0;
    for (int i = 0; i < columnWidths.length - 1; i++) {
      x += columnWidths[i];
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    if (!isLastRow) {
      final double y = size.height - 0.5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OutlineTableGridPainter oldDelegate) {
    return oldDelegate.isLastRow != isLastRow ||
        oldDelegate.gridColor != gridColor ||
        !_sameWidths(oldDelegate.columnWidths, columnWidths);
  }

  /// 比较两组列宽是否一致
  bool _sameWidths(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
