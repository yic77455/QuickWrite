import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/models/outline_table.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/text_style_range.dart';
import 'package:quick_write/pages/workspace/editor/outline_editor.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_color_palette.dart';
import 'package:quick_write/pages/workspace/widgets/mobile_table_toolbar_binding.dart';
import 'package:quick_write/pages/workspace/widgets/punctuation_key_button.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 键盘工具栏与二级面板的高度
const double _barHeight = 44;

/// 工具栏按钮的点击区域尺寸
const double _buttonSize = 44;

/// 工具栏按钮图标尺寸
const double _iconSize = 20;

/// 工具栏图标组左侧留白，避免首个图标紧贴屏幕边缘不便点按
const double _iconListLeftPadding = 8;

/// 分部面板与主工具栏之间的分隔线高度留白
const double _dividerVerticalInset = 16;

/// 大纲编辑器键盘工具栏二级面板类型
enum OutlineToolbarPanel {
  /// 快捷输入：常用标点符号
  quickInput,

  /// 文字格式：标题级别与字形样式
  format,

  /// 字体颜色
  fontColor,

  /// 字底颜色
  backgroundColor,

  /// 插入：关键词、关联、备注、图片、表格
  insert,

  /// 表格单元格：整表对齐方式
  tableAlignment,

  /// 表格单元格：批量选择、清空、删除行列与删除表格
  tableActions,
}

/// 移动端大纲编辑器键盘工具栏
///
/// 软键盘弹出时贴在键盘上方：主工具栏左侧为二级面板入口（快捷输入、文字格式、
/// 字体颜色、字底颜色、插入），数量较多时横向滚动；右侧为节点层级调整按钮；
/// 点击面板入口时在其上方展开对应的二级面板，唤起键盘时默认展开快捷输入面板。
/// 选中表格单元格时切换为表格模式，复用同一套栏体、面板容器与格式按钮。
class MobileOutlineToolbar extends StatefulWidget {
  const MobileOutlineToolbar({super.key});

  @override
  State<MobileOutlineToolbar> createState() => _MobileOutlineToolbarState();
}

class _MobileOutlineToolbarState extends State<MobileOutlineToolbar> with WidgetsBindingObserver {
  /// 软键盘高度，大于 0 表示键盘正在显示
  double _keyboardHeight = 0;

  /// 软键盘是否正在收起
  ///
  /// 键盘收起时高度逐帧减小，若继续按「高度大于 0」显示，工具栏会跟随键盘
  /// 一路下滑到屏幕底部才消失；检测到高度减小时据此立即隐藏。
  /// 该状态一旦置位便保持到键盘完全消失，收起动画期间重复的度量通知不会解除它。
  bool _keyboardRetracting = false;

  /// 软键盘是否处于弹出状态（收起动画一开始即视为已收起）
  bool get _keyboardShown => _keyboardHeight > 0 && !_keyboardRetracting;

  /// 上一次已知的横竖屏状态，用于识别屏幕旋转；为 null 表示尚未记录
  bool? _isLandscape;

  /// 当前展开的二级面板，null 表示未展开
  OutlineToolbarPanel? _panel = OutlineToolbarPanel.quickInput;

  @override
  void initState() {
    super.initState();
    // 视口指标变化不会触发本子树重建，需自行监听以跟踪键盘升降
    WidgetsBinding.instance.addObserver(this);
    // 编辑器焦点变化决定工具栏的显隐
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 挂载时键盘已弹出也能正确判断显隐
    _keyboardHeight = View.of(context).viewInsets.bottom;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 度量变化当帧布局尚未完成，键盘高度需等布局结束后读取
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncKeyboardHeight());
  }

  /// 焦点变化时重新判断显隐
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// 同步软键盘高度与屏幕方向
  ///
  /// 高度取自窗口视图的原始内边距：Scaffold 按键盘高度收缩本子树时，
  /// 会一并剔除子树 MediaQuery 中的底部内边距，从 MediaQuery 读取无法识别键盘升降。
  void _syncKeyboardHeight() {
    if (!mounted) return;
    final double height = View.of(context).viewInsets.bottom;
    final bool isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    // 屏幕方向变化同样需要重新确定默认面板
    final bool orientationChanged = _isLandscape != null && _isLandscape != isLandscape;
    final bool wasShown = _keyboardShown;
    // 从无到有表示键盘重新唤起，此时回到默认面板
    final bool keyboardOpening = _keyboardHeight <= 0 && height > 0;
    // 键盘完全消失时结束收起过程；高度减小时进入收起过程，立即隐藏工具栏，
    // 不等收起动画结束。收起期间可能连续收到高度相同或短暂回升的度量通知，
    // 因此只在高度归零时解除，避免工具栏在屏幕底部反复闪现
    if (height <= 0) {
      _keyboardRetracting = false;
    } else if (height < _keyboardHeight) {
      _keyboardRetracting = true;
    }
    _keyboardHeight = height;
    _isLandscape = isLandscape;

    // 仅在显隐状态或屏幕方向变化时重建，键盘动画期间的连续高度变化被合并掉
    if (_keyboardShown == wasShown && !orientationChanged) return;
    setState(() {
      // 键盘重新唤起或屏幕旋转时回到默认面板：竖屏展开快捷输入，横屏收起以保留编辑区高度
      if (keyboardOpening || orientationChanged) {
        _panel = isLandscape ? null : OutlineToolbarPanel.quickInput;
      }
    });
  }

  /// 当前标签页的大纲编辑器状态，无大纲编辑器时返回 null
  OutlineEditorState? _currentEditorState() {
    final tab = context.read<WorkspaceProvider>().currentTab;
    if (tab == null || !tab.usesOutlineEditor) return null;
    final state = tab.editorKey.currentState;
    if (state is! OutlineEditorState) return null;
    // 批量选择模式下工具栏需要常显，只读限制由各操作自行判断
    if (tab.isReadOnly && !state.isBatchSelectionMode) return null;
    return state;
  }

  /// 切换二级面板
  ///
  /// 点击已展开面板的入口时收起该面板，主工具栏保持显示。
  void _togglePanel(OutlineToolbarPanel panel) {
    setState(() => _panel = _panel == panel ? null : panel);
  }

  /// 当前应当展开的二级面板
  ///
  /// 批量选择模式下不提供快捷输入与插入面板。
  OutlineToolbarPanel? _effectivePanel(OutlineEditorState state) {
    final bool nodeScopedPanel =
        _panel == OutlineToolbarPanel.quickInput || _panel == OutlineToolbarPanel.insert;
    if (state.isBatchSelectionMode && nodeScopedPanel) return null;
    return _panel;
  }

  /// 表格模式下应当展开的二级面板
  ///
  /// 节点模式遗留的快捷输入、插入面板在表格模式下改为文字格式面板；
  /// 批量选择模式下不再提供单元格操作面板（删除行列、进入批量等）。
  OutlineToolbarPanel? _effectiveTablePanel({required bool batchMode}) {
    final OutlineToolbarPanel? panel = _panel;
    if (panel == null) return null;
    const Set<OutlineToolbarPanel> tablePanels = <OutlineToolbarPanel>{
      OutlineToolbarPanel.format,
      OutlineToolbarPanel.fontColor,
      OutlineToolbarPanel.backgroundColor,
      OutlineToolbarPanel.tableAlignment,
      OutlineToolbarPanel.tableActions,
    };
    if (!tablePanels.contains(panel)) return OutlineToolbarPanel.format;
    if (batchMode && panel == OutlineToolbarPanel.tableActions) return null;
    return panel;
  }

  /// 执行工具栏操作并刷新按钮的点亮状态
  void _runAction(VoidCallback action) {
    action();
    if (mounted) setState(() {});
  }

  /// 执行节点层级调整操作并给出震动反馈
  void _runLevelAction(VoidCallback action) {
    HapticFeedback.lightImpact();
    _runAction(action);
  }

  @override
  Widget build(BuildContext context) {
    // 切换标签页时重新判断显隐
    context.watch<WorkspaceProvider>();
    final String? currentTabId = context.read<WorkspaceProvider>().currentTab?.id;
    final OutlineEditorState? state = _currentEditorState();

    return ValueListenableBuilder<MobileTableToolbarController?>(
      valueListenable: MobileTableToolbarBinding.active,
      builder: (context, table, _) {
        return ListenableBuilder(
          listenable: Listenable.merge(<Listenable?>[table, state?.batchRevision]),
          builder: (context, _) {
            // 表格所在标签页已切走、节点正在输入或节点处于批量选择模式时，
            // 表格快捷栏让位给节点工具栏，并顺带清除表格的选中态
            final bool nodeEditing = state?.hasEditorFocus ?? false;
            final bool nodeBatchMode = state?.isBatchSelectionMode ?? false;
            final bool tabMatches = table == null ||
                table.tabId == null ||
                currentTabId == null ||
                currentTabId == table.tabId;
            final bool showTable =
                table != null && state != null && tabMatches && !nodeEditing && !nodeBatchMode;

            if (table != null && !showTable) {
              WidgetsBinding.instance.addPostFrameCallback((_) => table.dismiss());
            }
            if (showTable) return _buildTableToolbar(context, table);
            return _buildNodeToolbar(context);
          },
        );
      },
    );
  }

  /// 构建节点编辑工具栏
  Widget _buildNodeToolbar(BuildContext context) {
    final state = _currentEditorState();
    if (state == null) return const SizedBox.shrink();

    // 监听批量选择状态与节点选区变化，同步工具栏的显隐、形态与按钮可用状态
    return ListenableBuilder(
      listenable: state.batchRevision,
      builder: (context, _) {
        final bool batchMode = state.isBatchSelectionMode;

        // 批量选择模式下工具栏常显；其余情况仅在软键盘弹出且输入焦点位于编辑器时显示，
        // 键盘一开始收起即隐藏，避免跟随键盘下滑到屏幕底部
        if (!batchMode && (!_keyboardShown || !state.hasEditorFocus)) {
          return const SizedBox.shrink();
        }

        final controller = state.activeController;
        // 非批量模式下没有活动输入框时无需显示
        if (!batchMode && controller == null) return const SizedBox.shrink();

        final panel = _effectivePanel(state);

        // 整栏纳入输入框的点击区域组：点击输入框之外会主动失焦收起输入法，
        // 工具栏必须归属同一区域组，否则一碰就会收起键盘
        return TextFieldTapRegion(
          // 整栏不参与焦点争夺，避免点击时输入法收起
          child: ExcludeFocus(
            // 监听活动节点的控制器，同步文字选区与样式变化引起的按钮点亮状态
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, state.batchRevision]),
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 两行工具栏均按可用高度自适应：空间充足时保持设计高度，
                  // 空间不足时等比压缩，保证整条工具栏不溢出且始终可用
                  if (panel != null)
                    Flexible(
                      fit: FlexFit.loose,
                      child: _buildPanel(context, state: state, table: null, panel: panel),
                    ),
                  Flexible(fit: FlexFit.loose, child: _buildMainBar(context, state, batchMode)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建表格单元格快捷操作栏
  ///
  /// 与节点工具栏共用栏体、面板容器和样式按钮，保证移动端两处交互视觉一致。
  Widget _buildTableToolbar(BuildContext context, MobileTableToolbarController table) {
    final OutlineToolbarPanel? panel =
        _effectiveTablePanel(batchMode: table.isBatchMode);

    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (panel != null)
              Flexible(
                fit: FlexFit.loose,
                child: _buildPanel(context, state: null, table: table, panel: panel),
              ),
            Flexible(
              fit: FlexFit.loose,
              child: _buildTableMainBar(context, table, panel),
            ),
          ],
        ),
      ),
    );
  }

  /// 切换表格模式的二级面板
  ///
  /// 以实际展开的面板为准，避免节点模式遗留的面板值导致按钮点亮状态错位。
  void _toggleTablePanel(OutlineToolbarPanel entry, OutlineToolbarPanel? effective) {
    setState(() => _panel = effective == entry ? null : entry);
  }

  /// 构建表格模式的二级面板入口
  Widget _buildTablePanelEntry(
    OutlineToolbarPanel entry,
    IconData icon,
    String tooltip,
    OutlineToolbarPanel? effective,
  ) {
    return ToggleToolButton(
      icon: icon,
      tooltip: tooltip,
      isSelected: effective == entry,
      size: _buttonSize,
      iconSize: _iconSize,
      onChanged: (_) => _toggleTablePanel(entry, effective),
    );
  }

  /// 构建主工具栏
  ///
  /// 左侧为二级面板入口（可横向滚动），右侧为节点层级调整按钮；
  /// 批量选择模式下隐藏快捷输入入口、追加复制与删除按钮，操作对象为选中的节点。
  Widget _buildMainBar(BuildContext context, OutlineEditorState state, bool batchMode) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: _barHeight,
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // 二级面板入口
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
              children: [
                // 快捷输入仅作用于当前节点，批量选择模式下不提供
                if (!batchMode)
                  _buildPanelEntry(OutlineToolbarPanel.quickInput, Icons.keyboard_alt_outlined, '快捷输入'),
                _buildPanelEntry(OutlineToolbarPanel.format, Icons.text_fields_rounded, '文字格式'),
                _buildPanelEntry(OutlineToolbarPanel.fontColor, Icons.format_color_text_rounded, '字体颜色'),
                _buildPanelEntry(
                  OutlineToolbarPanel.backgroundColor,
                  Icons.format_color_fill_rounded,
                  '字底颜色',
                ),
                // 插入仅作用于当前节点，批量选择模式下不提供
                if (!batchMode)
                  _buildPanelEntry(OutlineToolbarPanel.insert, Icons.library_add_outlined, '插入'),
                // 批量选择模式下的复制与删除
                if (batchMode) ...[
                  _buildActionButton(
                    icon: Icons.copy_rounded,
                    tooltip: '复制选中节点',
                    onPressed: state.copySelectedNodes,
                  ),
                  _buildActionButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: '删除选中节点',
                    onPressed: state.deleteSelectedNodes,
                  ),
                ],
              ],
            ),
          ),

          // 与层级调整按钮之间的分隔线，上下留白避免顶满整栏
          _buildDivider(colorScheme),

          // 向左提升层级
          _buildLevelButton(
            icon: Icons.first_page_rounded,
            tooltip: '提升层级',
            enabled: batchMode ? state.canOutdentSelectedNodes : state.canOutdentActiveNode,
            onPressed: () => _runLevelAction(batchMode ? state.outdentSelectedNodes : state.outdentActiveNode),
          ),

          // 向右缩进为子节点
          _buildLevelButton(
            icon: Icons.last_page_rounded,
            tooltip: '缩进为子节点',
            enabled: batchMode ? state.canIndentSelectedNodes : state.canIndentActiveNode,
            onPressed: () => _runLevelAction(batchMode ? state.indentSelectedNodes : state.indentActiveNode),
          ),
        ],
      ),
    );
  }

  /// 构建表格单元格模式的主工具栏
  ///
  /// 左侧为样式面板入口，对应桌面端表格右键菜单；批量选择模式下只保留清空内容，
  /// 右侧按钮用于取消选中或退出批量模式。
  Widget _buildTableMainBar(
    BuildContext context,
    MobileTableToolbarController table,
    OutlineToolbarPanel? effectivePanel,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool batchMode = table.isBatchMode;

    return Container(
      height: _barHeight,
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
              children: [
                _buildTablePanelEntry(
                  OutlineToolbarPanel.format,
                  Icons.text_fields_rounded,
                  '文字格式',
                  effectivePanel,
                ),
                _buildTablePanelEntry(
                  OutlineToolbarPanel.fontColor,
                  Icons.format_color_text_rounded,
                  '字体颜色',
                  effectivePanel,
                ),
                _buildTablePanelEntry(
                  OutlineToolbarPanel.backgroundColor,
                  Icons.format_color_fill_rounded,
                  '字底颜色',
                  effectivePanel,
                ),
                _buildTablePanelEntry(
                  OutlineToolbarPanel.tableAlignment,
                  Icons.format_align_left,
                  '对齐方式',
                  effectivePanel,
                ),
                if (!batchMode)
                  _buildTablePanelEntry(
                    OutlineToolbarPanel.tableActions,
                    MaterialIcons.table_edit,
                    '单元格操作',
                    effectivePanel,
                  ),
                if (batchMode)
                  _buildActionButton(
                    icon: Icons.backspace_outlined,
                    tooltip: '清空选中单元格',
                    onPressed: table.clearContents,
                  ),
              ],
            ),
          ),

          if (batchMode)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '已选 ${table.selectedCellCount} 格',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ),

          _buildDivider(colorScheme),

          _buildActionButton(
            icon: Icons.close_rounded,
            tooltip: batchMode ? '退出批量选择' : '取消选中',
            onPressed: batchMode ? table.exitBatchMode : table.dismiss,
          ),
        ],
      ),
    );
  }

  /// 构建主工具栏中的单次操作按钮
  ///
  /// 不可执行时按钮置灰且不响应点击。
  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool enabled = true,
    Color? iconColor,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: SmallToolbarButton(
        icon: icon,
        tooltip: tooltip,
        width: _buttonSize,
        height: _barHeight,
        iconSize: _iconSize,
        iconColor: iconColor,
        onPressed: enabled ? () => _runAction(onPressed) : null,
      ),
    );
  }

  /// 构建二级面板入口按钮
  ///
  /// 对应面板展开时按钮图标点亮。
  Widget _buildPanelEntry(OutlineToolbarPanel panel, IconData icon, String tooltip) {
    return ToggleToolButton(
      icon: icon,
      tooltip: tooltip,
      isSelected: _panel == panel,
      size: _buttonSize,
      iconSize: _iconSize,
      onChanged: (_) => _togglePanel(panel),
    );
  }

  /// 构建节点层级调整按钮
  ///
  /// 不可执行时按钮置灰且不响应点击。
  Widget _buildLevelButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return _buildActionButton(
      icon: icon,
      tooltip: tooltip,
      enabled: enabled,
      onPressed: onPressed,
    );
  }

  /// 构建工具组之间的分隔线
  ///
  /// 通过上下内边距留出空隙，使分隔线不占满整栏高度
  Widget _buildDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _dividerVerticalInset / 2 + 2),
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: colorScheme.outlineVariant,
      ),
    );
  }

  /// 构建二级面板
  ///
  /// 节点与表格共用文字格式、字体颜色、字底颜色三个面板，
  /// 通过 [MobileToolbarStyleTarget] 适配不同的操作对象。
  Widget _buildPanel(
    BuildContext context, {
    required OutlineEditorState? state,
    required MobileTableToolbarController? table,
    required OutlineToolbarPanel panel,
  }) {
    switch (panel) {
      case OutlineToolbarPanel.quickInput:
        return _buildQuickInputPanel(context, state!);
      case OutlineToolbarPanel.insert:
        return _buildInsertPanel(context, state!);
      case OutlineToolbarPanel.tableAlignment:
        return _buildTableAlignmentPanel(context, table!);
      case OutlineToolbarPanel.tableActions:
        return _buildTableActionsPanel(context, table!);
      case OutlineToolbarPanel.format:
        return _buildFormatPanel(context, table ?? _EditorStyleTarget(state!));
      case OutlineToolbarPanel.fontColor:
        return _buildColorPanel(
          context,
          table ?? _EditorStyleTarget(state!),
          isForeground: true,
        );
      case OutlineToolbarPanel.backgroundColor:
        return _buildColorPanel(
          context,
          table ?? _EditorStyleTarget(state!),
          isForeground: false,
        );
    }
  }

  /// 构建二级面板容器
  Widget _buildPanelContainer(BuildContext context, Widget child) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: _barHeight,
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }

  /// 构建快捷输入面板
  ///
  /// 提供常用标点符号，成对符号按设置自动补全。
  Widget _buildQuickInputPanel(BuildContext context, OutlineEditorState state) {
    return _buildPanelContainer(
      context,
      ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
        itemCount: PunctuationSymbols.quickInputKeys.length,
        itemBuilder: (context, index) {
          final symbol = PunctuationSymbols.quickInputKeys[index];
          return PunctuationKeyButton(
            symbol: symbol,
            onTap: () => _runAction(() => state.insertQuickSymbol(symbol)),
          );
        },
      ),
    );
  }

  /// 构建文字格式面板
  ///
  /// 提供标题级别（一级、二级、三级标题、正文）与字形样式（加粗、斜体、下划线、删除线）。
  Widget _buildFormatPanel(BuildContext context, MobileToolbarStyleTarget target) {
    final int headingLevel = target.currentHeadingLevel;
    final TextStyleFlags flags = target.currentTextStyleFlags;

    return _buildPanelContainer(
      context,
      ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
        children: [
          _buildHeadingButton(
            target,
            level: 1,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_h1,
            tooltip: '一级标题',
          ),
          _buildHeadingButton(
            target,
            level: 2,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_h2,
            tooltip: '二级标题',
          ),
          _buildHeadingButton(
            target,
            level: 3,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_h3,
            tooltip: '三级标题',
          ),
          _buildHeadingButton(
            target,
            level: 0,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_title,
            tooltip: '正文',
          ),

          // 标题级别与字形样式之间分隔线
          _buildDivider(Theme.of(context).colorScheme),

          _buildStyleButton(
            target,
            icon: MaterialIcons.format_bold,
            tooltip: '加粗',
            isSelected: flags.bold,
            toggleFn: TextStyleFlags.toggleBold,
          ),
          _buildStyleButton(
            target,
            icon: MaterialIcons.format_italic,
            tooltip: '斜体',
            isSelected: flags.italic,
            toggleFn: TextStyleFlags.toggleItalic,
          ),
          _buildStyleButton(
            target,
            icon: MaterialIcons.format_underlined,
            tooltip: '下划线',
            isSelected: flags.underline,
            toggleFn: TextStyleFlags.toggleUnderline,
          ),
          _buildStyleButton(
            target,
            icon: MaterialIcons.strikethrough_s,
            tooltip: '删除线',
            isSelected: flags.strikethrough,
            toggleFn: TextStyleFlags.toggleStrikethrough,
          ),
        ],
      ),
    );
  }

  /// 构建标题级别按钮
  ///
  /// 当前级别已选中时按钮点亮，点击其他级别则切换为该级别。
  Widget _buildHeadingButton(
    MobileToolbarStyleTarget target, {
    required int level,
    required int currentLevel,
    required IconData icon,
    required String tooltip,
  }) {
    return ToggleToolButton(
      icon: icon,
      tooltip: tooltip,
      isSelected: currentLevel == level,
      size: _buttonSize,
      iconSize: _iconSize,
      onChanged: (selected) {
        if (selected) _runAction(() => target.setHeadingLevel(level));
      },
    );
  }

  /// 构建字形样式切换按钮
  ///
  /// 样式已开启时按钮点亮，点击后作用于选中文字或整个节点。
  Widget _buildStyleButton(
    MobileToolbarStyleTarget target, {
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required TextStyleFlags Function(TextStyleFlags) toggleFn,
  }) {
    return ToggleToolButton(
      icon: icon,
      tooltip: tooltip,
      isSelected: isSelected,
      size: _buttonSize,
      iconSize: _iconSize,
      onChanged: (_) => _runAction(() => target.toggleTextStyle(toggleFn)),
    );
  }

  /// 构建插入面板
  ///
  /// 集中节点内容绑定与附加内容的入口：关键词、关联、备注、图片、表格；
  /// 关联需要节点内存在文字选区，表格每个节点只保留一个，均不可用时按钮置灰。
  Widget _buildInsertPanel(BuildContext context, OutlineEditorState state) {
    return _buildPanelContainer(
      context,
      ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
        children: [
          _buildActionButton(
            icon: Icons.sell_outlined,
            tooltip: '添加关键词',
            onPressed: state.showKeywordCardForActiveNode,
          ),
          _buildActionButton(
            icon: Icons.link,
            tooltip: '关联',
            enabled: state.canAddLinkForActiveNode,
            onPressed: state.showLinkDialogForActiveNode,
          ),
          _buildActionButton(
            icon: Icons.post_add_rounded,
            tooltip: '备注',
            onPressed: state.startNoteEditingForActiveNode,
          ),
          _buildActionButton(
            icon: Icons.image_outlined,
            tooltip: '图片',
            onPressed: state.pickImageForActiveNode,
          ),
          _buildActionButton(
            icon: MaterialIcons.table,
            tooltip: '表格',
            enabled: !state.activeNodeHasTable,
            onPressed: state.insertTableForActiveNode,
          ),
        ],
      ),
    );
  }

  /// 构建表格对齐方式面板
  ///
  /// 对应桌面端右键菜单的「对齐方式」，作用于整张表格。
  Widget _buildTableAlignmentPanel(
    BuildContext context,
    MobileTableToolbarController table,
  ) {
    return _buildPanelContainer(
      context,
      ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
        children: [
          for (final (alignment, label, icon) in const [
            (OutlineTableAlignment.left, '左对齐', Icons.format_align_left),
            (OutlineTableAlignment.center, '居中', Icons.format_align_center),
            (OutlineTableAlignment.right, '右对齐', Icons.format_align_right),
          ])
            ToggleToolButton(
              icon: icon,
              tooltip: label,
              isSelected: table.alignment == alignment,
              size: _buttonSize,
              iconSize: _iconSize,
              onChanged: (_) => _runAction(() => table.setAlignment(alignment)),
            ),
        ],
      ),
    );
  }

  /// 删除类操作的二次确认
  ///
  /// 图标本身不足以表达破坏性，删除行、列、表格前统一弹确认框。
  Future<void> _confirmDestructiveAction(
    BuildContext context, {
    required String title,
    required String description,
    required VoidCallback onConfirmed,
  }) async {
    final bool confirmed = await showConfirmDialog(
      context: context,
      title: title,
      description: description,
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
    );
    if (!confirmed || !mounted) return;
    _runAction(onConfirmed);
  }

  /// 构建表格单元格操作面板
  ///
  /// 除清空、删除行列与删除表格等桌面右键菜单操作外，
  /// 额外提供进入批量选择模式的入口；破坏性操作图标标红。
  Widget _buildTableActionsPanel(
    BuildContext context,
    MobileTableToolbarController table,
  ) {
    return _buildPanelContainer(
      context,
      ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
        children: [
          _buildActionButton(
            icon: MaterialIcons.select_check_box,
            tooltip: '批量选择单元格',
            onPressed: table.enterBatchMode,
          ),
          _buildDivider(Theme.of(context).colorScheme),
          _buildActionButton(
            icon: Icons.backspace_outlined,
            tooltip: '清空单元格',
            iconColor: Colors.redAccent,
            onPressed: table.clearContents,
          ),
          _buildActionButton(
            icon: Icons.table_rows_outlined,
            tooltip: '删除行',
            iconColor: Colors.redAccent,
            enabled: table.canDeleteRow,
            onPressed: () => _confirmDestructiveAction(
              context,
              title: '删除行',
              description: '当前单元格所在的整行将被删除。',
              onConfirmed: table.deleteRow,
            ),
          ),
          _buildActionButton(
            icon: MaterialIcons.view_column,
            tooltip: '删除列',
            iconColor: Colors.redAccent,
            enabled: table.canDeleteColumn,
            onPressed: () => _confirmDestructiveAction(
              context,
              title: '删除列',
              description: '当前单元格所在的整列将被删除。',
              onConfirmed: table.deleteColumn,
            ),
          ),
          _buildActionButton(
            icon: Icons.delete_sweep_outlined,
            tooltip: '删除表格',
            iconColor: Colors.redAccent,
            onPressed: () => _confirmDestructiveAction(
              context,
              title: '删除表格',
              description: '整张表格及所有单元格内容将被删除。',
              onConfirmed: table.deleteTable,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建颜色面板
  ///
  /// [isForeground] 为 true 时设置字体颜色，false 时设置字底颜色。
  Widget _buildColorPanel(
    BuildContext context,
    MobileToolbarStyleTarget target, {
    required bool isForeground,
  }) {
    final ({bool isUniform, Color? color}) current = target.currentColor(isForeground: isForeground);

    return _buildPanelContainer(
      context,
      ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
        children: [
          // 默认色：清除当前颜色
          ToggleToolButton(
            icon: MaterialIcons.ink_eraser,
            tooltip: '默认',
            isSelected: current.isUniform && current.color == null,
            size: _buttonSize,
            iconSize: _iconSize,
            onChanged: (_) => _runAction(
              () => isForeground
                  ? target.applyColor(clearForeground: true)
                  : target.applyColor(clearBackground: true),
            ),
          ),

          // 默认色与调色板之间分隔线
          _buildDivider(Theme.of(context).colorScheme),

          for (final item in OutlineColorPalette.colors)
            _ColorSwatchButton(
              color: isForeground ? item.foreground : item.background,
              isSelected:
                  current.isUniform && current.color == (isForeground ? item.foreground : item.background),
              onTap: () => _runAction(
                () => target.applyColor(
                  foregroundColor: isForeground ? item.foreground : null,
                  backgroundColor: isForeground ? null : item.background,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 节点编辑器的样式操作适配器
///
/// 让大纲编辑器状态与表格单元格控制器共用同一套格式、颜色面板。
class _EditorStyleTarget implements MobileToolbarStyleTarget {
  const _EditorStyleTarget(this.state);

  final OutlineEditorState state;

  @override
  int get currentHeadingLevel => state.currentHeadingLevel;

  @override
  TextStyleFlags get currentTextStyleFlags => state.currentTextStyleFlags;

  @override
  ({bool isUniform, Color? color}) currentColor({required bool isForeground}) =>
      state.currentColor(isForeground: isForeground);

  @override
  void setHeadingLevel(int level) => state.setHeadingLevel(level);

  @override
  void toggleTextStyle(TextStyleFlags Function(TextStyleFlags) toggleFn) =>
      state.toggleTextStyle(toggleFn);

  @override
  void applyColor({
    Color? foregroundColor,
    Color? backgroundColor,
    bool clearForeground = false,
    bool clearBackground = false,
  }) =>
      state.applyColor(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        clearForeground: clearForeground,
        clearBackground: clearBackground,
      );
}

/// 颜色色块按钮
///
/// 点击后把该颜色应用到字体颜色或字底颜色；当前颜色与色块一致时以色环标记。
class _ColorSwatchButton extends StatelessWidget {
  /// 色块显示的颜色
  final Color color;

  /// 是否为当前颜色
  final bool isSelected;

  /// 点击回调
  final VoidCallback onTap;

  const _ColorSwatchButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 选中标记的颜色按色块明度取黑白，保证在深浅底色上均清晰可见
    final Color checkColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // 按钮不参与焦点争夺，避免点击时输入法收起
        canRequestFocus: false,
        onTap: onTap,
        highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
        splashColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: Center(
            // 选中时描主色外环，未选中时外环透明，保证色块位置不随状态变化
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
                  ),
                  child: isSelected ? Icon(Icons.check, size: 14, color: checkColor) : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
