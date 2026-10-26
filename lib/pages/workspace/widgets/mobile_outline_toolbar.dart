import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/text_style_range.dart';
import 'package:quick_write/pages/workspace/editor/outline_editor.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_color_palette.dart';
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
}

/// 移动端大纲编辑器键盘工具栏
///
/// 软键盘弹出时贴在键盘上方：主工具栏左侧为二级面板入口（快捷输入、文字格式、
/// 字体颜色、字底颜色，数量较多时横向滚动），右侧为节点层级调整按钮；
/// 点击面板入口时在其上方展开对应的二级面板，唤起键盘时默认展开快捷输入面板。
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
  /// 批量选择模式下不提供快捷输入面板。
  OutlineToolbarPanel? _effectivePanel(OutlineEditorState state) {
    if (state.isBatchSelectionMode && _panel == OutlineToolbarPanel.quickInput) return null;
    return _panel;
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
                    Flexible(fit: FlexFit.loose, child: _buildPanel(context, state, panel)),
                  Flexible(fit: FlexFit.loose, child: _buildMainBar(context, state, batchMode)),
                ],
              ),
            ),
          ),
        );
      },
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
                // 批量选择模式下的复制与删除
                if (batchMode) ...[
                  _buildBatchActionButton(
                    icon: Icons.copy_rounded,
                    tooltip: '复制选中节点',
                    onPressed: state.copySelectedNodes,
                  ),
                  _buildBatchActionButton(
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

  /// 构建批量选择模式下的操作按钮
  Widget _buildBatchActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SmallToolbarButton(
      icon: icon,
      tooltip: tooltip,
      width: _buttonSize,
      height: _barHeight,
      iconSize: _iconSize,
      onPressed: () => _runAction(onPressed),
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
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: SmallToolbarButton(
        icon: icon,
        tooltip: tooltip,
        width: _buttonSize,
        height: _barHeight,
        iconSize: _iconSize,
        onPressed: enabled ? onPressed : null,
      ),
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
  Widget _buildPanel(BuildContext context, OutlineEditorState state, OutlineToolbarPanel panel) {
    switch (panel) {
      case OutlineToolbarPanel.quickInput:
        return _buildQuickInputPanel(context, state);
      case OutlineToolbarPanel.format:
        return _buildFormatPanel(context, state);
      case OutlineToolbarPanel.fontColor:
        return _buildColorPanel(context, state, isForeground: true);
      case OutlineToolbarPanel.backgroundColor:
        return _buildColorPanel(context, state, isForeground: false);
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
  Widget _buildFormatPanel(BuildContext context, OutlineEditorState state) {
    final int headingLevel = state.currentHeadingLevel;
    final TextStyleFlags flags = state.currentTextStyleFlags;

    return _buildPanelContainer(
      context,
      ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: _iconListLeftPadding, right: 4),
        children: [
          _buildHeadingButton(
            state,
            level: 1,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_h1,
            tooltip: '一级标题',
          ),
          _buildHeadingButton(
            state,
            level: 2,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_h2,
            tooltip: '二级标题',
          ),
          _buildHeadingButton(
            state,
            level: 3,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_h3,
            tooltip: '三级标题',
          ),
          _buildHeadingButton(
            state,
            level: 0,
            currentLevel: headingLevel,
            icon: MaterialIcons.format_title,
            tooltip: '正文',
          ),

          // 标题级别与字形样式之间分隔线
          _buildDivider(Theme.of(context).colorScheme),

          _buildStyleButton(
            state,
            icon: MaterialIcons.format_bold,
            tooltip: '加粗',
            isSelected: flags.bold,
            toggleFn: TextStyleFlags.toggleBold,
          ),
          _buildStyleButton(
            state,
            icon: MaterialIcons.format_italic,
            tooltip: '斜体',
            isSelected: flags.italic,
            toggleFn: TextStyleFlags.toggleItalic,
          ),
          _buildStyleButton(
            state,
            icon: MaterialIcons.format_underlined,
            tooltip: '下划线',
            isSelected: flags.underline,
            toggleFn: TextStyleFlags.toggleUnderline,
          ),
          _buildStyleButton(
            state,
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
    OutlineEditorState state, {
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
        if (selected) _runAction(() => state.setHeadingLevel(level));
      },
    );
  }

  /// 构建字形样式切换按钮
  ///
  /// 样式已开启时按钮点亮，点击后作用于选中文字或整个节点。
  Widget _buildStyleButton(
    OutlineEditorState state, {
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
      onChanged: (_) => _runAction(() => state.toggleTextStyle(toggleFn)),
    );
  }

  /// 构建颜色面板
  ///
  /// [isForeground] 为 true 时设置字体颜色，false 时设置字底颜色。
  Widget _buildColorPanel(
    BuildContext context,
    OutlineEditorState state, {
    required bool isForeground,
  }) {
    final ({bool isUniform, Color? color}) current = state.currentColor(isForeground: isForeground);

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
              () => isForeground ? state.applyColor(clearForeground: true) : state.applyColor(clearBackground: true),
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
                () => state.applyColor(
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
