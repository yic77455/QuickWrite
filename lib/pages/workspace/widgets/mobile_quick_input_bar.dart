import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/constants/quick_input_action.dart';
import 'package:quick_write/core/models/quick_phrase.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/pages/workspace/editor/novel_editor.dart';
import 'package:quick_write/pages/workspace/name_gen/name_generator_dialog_mobile.dart';
import 'package:quick_write/pages/workspace/widgets/punctuation_key_button.dart';
import 'package:quick_write/pages/workspace/widgets/quick_phrase_manager_dialog.dart';
import 'package:quick_write/pages/workspace/widgets/quick_phrase_popup.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// 快捷操作按钮尺寸
const double _buttonSize = 42;

/// 快捷操作图标尺寸
const double _iconSize = 18;

/// 移动端快捷输入栏
///
/// 软键盘弹出时贴在键盘上方，提供常用标点符号的快捷输入；
/// 右端提供两个可自定义的快捷操作按钮（可设为「无」隐藏），
/// 默认分别为关键词高亮开关与其他设置入口。
/// 选择「快捷短语」动作后，点击图标即在其上方弹出短语浮层，
/// 点击短语将完整内容键入编辑器，浮层底部提供短语编辑入口。
class MobileQuickInputBar extends StatefulWidget {
  const MobileQuickInputBar({super.key});

  @override
  State<MobileQuickInputBar> createState() => _MobileQuickInputBarState();
}

class _MobileQuickInputBarState extends State<MobileQuickInputBar> with WidgetsBindingObserver {
  /// 快捷输入栏高度
  static const double _barHeight = 42;

  /// 标点按键列表左侧留白，避免首个按键紧贴屏幕边缘不便点按
  static const double _keyListLeftPadding = 8;

  /// 快捷短语图标的定位键，用于计算浮层锚点位置
  final GlobalKey _phraseButtonKey = GlobalKey();

  /// 快捷短语浮层的 Overlay 条目，null 表示浮层未显示
  OverlayEntry? _phrasePopupEntry;

  /// 软键盘高度，大于 0 表示键盘正在显示
  double _keyboardHeight = 0;

  /// 软键盘是否正在收起
  ///
  /// 键盘收起时高度逐帧减小，若继续按「高度大于 0」显示，快捷栏会跟随键盘
  /// 一路下滑到屏幕底部才消失；检测到高度减小时据此立即隐藏。
  /// 该状态一旦置位便保持到键盘完全消失，收起动画期间重复的度量通知不会解除它。
  bool _keyboardRetracting = false;

  /// 软键盘是否处于弹出状态（收起动画一开始即视为已收起）
  bool get _keyboardShown => _keyboardHeight > 0 && !_keyboardRetracting;

  @override
  void initState() {
    super.initState();
    // 视口指标变化不会触发本子树重建，需自行监听以跟踪键盘升降
    WidgetsBinding.instance.addObserver(this);
    // 编辑器焦点变化决定快捷栏的显隐
    FocusManager.instance.addListener(_onFocusChanged);
    // 快捷栏开关变化需要重新判断显隐
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 挂载时键盘已弹出也能正确判断显隐
    _keyboardHeight = View.of(context).viewInsets.bottom;
  }

  @override
  void dispose() {
    _removePhrasePopup();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusChanged);
    SettingsService.instance.removeListener(_onSettingsChanged);
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
    if (!mounted) return;
    // 输入焦点离开编辑器时浮层失去锚点意义，一并关闭
    if (!(_currentEditorState()?.hasEditorFocus ?? false)) {
      _closePhrasePopup();
    }
    setState(() {});
  }

  /// 设置变化时重新判断显隐
  void _onSettingsChanged() {
    if (!mounted) return;
    // 快捷短语入口被移除后，浮层不再有对应图标，直接关闭
    if (_phrasePopupEntry != null &&
        !_visibleActions().contains(QuickInputAction.quickPhrase)) {
      _closePhrasePopup();
    }
    setState(() {});
  }

  /// 同步软键盘高度
  ///
  /// 高度取自窗口视图的原始内边距：Scaffold 按键盘高度收缩本子树时，
  /// 会一并剔除子树 MediaQuery 中的底部内边距，从 MediaQuery 读取无法识别键盘升降。
  void _syncKeyboardHeight() {
    if (!mounted) return;
    final double height = View.of(context).viewInsets.bottom;
    final bool wasShown = _keyboardShown;
    // 键盘完全消失时结束收起过程；高度减小时进入收起过程，立即隐藏快捷栏，
    // 不等收起动画结束。收起期间可能连续收到高度相同或短暂回升的度量通知，
    // 因此只在高度归零时解除，避免快捷栏在屏幕底部反复闪现
    if (height <= 0) {
      _keyboardRetracting = false;
      // 键盘完全收起后快捷栏随之隐藏，短语浮层一并关闭
      _closePhrasePopup();
    } else if (height < _keyboardHeight) {
      _keyboardRetracting = true;
      // 键盘开始收起时立即关闭浮层，避免浮层悬留在空处
      _closePhrasePopup();
    }
    _keyboardHeight = height;
    // 仅在显隐状态真正变化时重建，键盘动画期间的连续高度变化被合并掉
    if (_keyboardShown != wasShown) setState(() {});
  }

  /// 当前标签页的正文编辑器状态，无正文编辑器时返回 null
  NovelEditorState? _currentEditorState() {
    final tab = context.read<WorkspaceProvider>().currentTab;
    if (tab == null || tab.textController == null || tab.isReadOnly || tab.usesOutlineEditor) {
      return null;
    }
    final state = tab.editorKey.currentState;
    return state is NovelEditorState ? state : null;
  }

  /// 快捷输入栏是否应当显示
  ///
  /// 仅在移动端键盘弹出、且输入焦点位于正文编辑器时显示；
  /// 键盘一开始收起即隐藏，避免跟随键盘下滑到屏幕底部。
  bool get _shouldShow {
    if (!_keyboardShown) return false;
    if (!SettingsService.instance.quickInputBarEnabled) return false;
    final state = _currentEditorState();
    return state != null && state.hasEditorFocus;
  }

  /// 在当前光标处插入标点符号
  ///
  /// 开启标点自动补全时，成对符号的起始符号连同结束符号一起插入，
  /// 光标落在两条符号之间。
  void _handleSymbolTap(PunctuationSymbol symbol) {
    final state = _currentEditorState();
    if (state == null) return;

    if (symbol.isPairStart && SettingsService.instance.punctuationAutoCompleteEnabled) {
      state.insertText(symbol.symbol + symbol.closing!, caretOffsetInText: symbol.symbol.length);
    } else {
      state.insertText(symbol.symbol);
    }
  }

  /// 打开其他设置面板
  void _handleSettingsTap() {
    // 先收起输入法，避免键盘遮挡展开的设置面板
    FocusManager.instance.primaryFocus?.unfocus();
    context.read<WorkspaceProvider>().openRightSidebar(RightSidebarType.other);
  }

  /// 打开或关闭当前编辑器的查找替换栏
  void _handleFindReplaceTap() {
    context.read<WorkspaceProvider>().toggleFindReplace();
  }

  /// 打开全文搜索面板
  void _handleFullTextSearchTap() {
    // 先收起输入法，避免键盘遮挡展开的搜索面板
    FocusManager.instance.primaryFocus?.unfocus();
    context.read<WorkspaceProvider>().openRightSidebar(RightSidebarType.search);
  }

  /// 打开随机取名弹窗
  void _handleRandomNameTap() {
    // 先收起输入法，避免键盘遮挡弹窗
    FocusManager.instance.primaryFocus?.unfocus();
    showMobileNameGeneratorDialog(context: context);
  }

  /// 切换快捷短语浮层的显隐
  void _togglePhrasePopup() {
    if (_phrasePopupEntry != null) {
      _closePhrasePopup();
    } else {
      _openPhrasePopup();
    }
  }

  /// 在图标上方打开快捷短语浮层
  void _openPhrasePopup() {
    // 以图标自身的屏幕矩形作为浮层锚点，使浮层从图标位置向上弹出
    final RenderBox? buttonBox =
        _phraseButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) return;

    final Rect anchorRect = buttonBox.localToGlobal(Offset.zero) & buttonBox.size;
    final OverlayEntry entry = OverlayEntry(
      builder: (overlayContext) => QuickPhrasePopup(
        anchorRect: anchorRect,
        phrases: SettingsService.instance.quickPhrases,
        onSelect: _handlePhraseTap,
        onEdit: _handleManagePhrases,
        onDismiss: _closePhrasePopup,
      ),
    );

    _phrasePopupEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  /// 关闭快捷短语浮层并刷新图标选中态
  void _closePhrasePopup() {
    if (_phrasePopupEntry == null) return;
    _removePhrasePopup();
    if (mounted) setState(() {});
  }

  /// 移除快捷短语浮层，不触发重建
  void _removePhrasePopup() {
    _phrasePopupEntry?.remove();
    _phrasePopupEntry = null;
  }

  /// 在当前光标处键入快捷短语
  void _handlePhraseTap(QuickPhrase phrase) {
    final state = _currentEditorState();
    if (state != null) state.insertText(phrase.content);
    _closePhrasePopup();
  }

  /// 打开快捷短语管理弹窗
  void _handleManagePhrases() {
    _closePhrasePopup();
    // 先收起输入法，避免键盘遮挡弹窗
    FocusManager.instance.primaryFocus?.unfocus();
    showQuickPhraseManagerDialog(context: context);
  }

  /// 右侧操作区实际需要渲染的动作
  ///
  /// 「无」不占位、不渲染。标点按键列表是 Expanded，剩余按钮始终贴着整栏右端，
  /// 因此图标一有值而图标二为「无」时，图标一会自然落到原本图标二的位置，
  /// 不需要改动配置值，也不需要在设置面板中禁止这种组合。
  List<QuickInputAction> _visibleActions() {
    final settings = SettingsService.instance;
    return [
      settings.quickInputBarLeftAction,
      settings.quickInputBarRightAction,
    ].where((action) => !action.isNone).toList(growable: false);
  }

  /// 按设置的左右顺序构建右侧操作区图标按钮
  List<Widget> _buildRightActions(NovelEditorState editorState, List<QuickInputAction> actions) {
    return actions
        .map((action) => _buildActionButton(editorState, action))
        .toList(growable: false);
  }

  /// 构建单个操作图标按钮
  ///
  /// 关键词高亮开关需要跟随编辑器状态显示选中态，故单独处理；
  /// 当前正文未绑定关键词时不显示该按钮，避免出现无效入口。
  Widget _buildActionButton(NovelEditorState editorState, QuickInputAction action) {
    // 「无」没有图标，直接返回空占位；正常渲染流程已在 _visibleActions 中过滤
    final IconData? icon = action.icon;
    if (icon == null) return const SizedBox.shrink();
    switch (action) {
      case QuickInputAction.none:
        // 仅用于穷举枚举：none 的 icon 为 null，上方已返回
        return const SizedBox.shrink();
      case QuickInputAction.keywordToggle:
        if (!editorState.hasOutlineKeywords) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: editorState.keywordHighlightNotifier,
          builder: (context, enabled, _) => PressScaleIconButton(
            icon: icon,
            tooltip: action.label,
            isSelected: enabled,
            size: _buttonSize,
            iconSize: _iconSize,
            onPressed: editorState.toggleKeywordHighlight,
          ),
        );
      case QuickInputAction.settings:
        return _buildSmallActionButton(action, icon, _handleSettingsTap);
      case QuickInputAction.findReplace:
        return _buildSmallActionButton(action, icon, _handleFindReplaceTap);
      case QuickInputAction.fullTextSearch:
        return _buildSmallActionButton(action, icon, _handleFullTextSearchTap);
      case QuickInputAction.randomName:
        return _buildSmallActionButton(action, icon, _handleRandomNameTap);
      case QuickInputAction.quickPhrase:
        return PressScaleIconButton(
          key: _phraseButtonKey,
          icon: icon,
          tooltip: action.label,
          isSelected: _phrasePopupEntry != null,
          size: _buttonSize,
          iconSize: _iconSize,
          onPressed: _togglePhrasePopup,
        );
    }
  }

  /// 构建普通样式的操作按钮
  Widget _buildSmallActionButton(QuickInputAction action, IconData icon, VoidCallback onPressed) {
    return PressScaleIconButton(
      icon: icon,
      tooltip: action.label,
      size: _buttonSize,
      iconSize: _iconSize,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 切换标签页时重新判断显隐
    context.watch<WorkspaceProvider>();

    if (!_shouldShow) return const SizedBox.shrink();

    final NovelEditorState? editorState = _currentEditorState();
    if (editorState == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final visibleActions = _visibleActions();
    // 按键列表支持用户自定义，每次构建时读取当前生效的符号表
    final symbols = SettingsService.instance.quickInputSymbols;

    // 整栏纳入编辑器的点击区域组：编辑区在点击自身区域之外时会主动失焦收起输入法，
    // 快捷栏必须归属同一区域组，否则一碰就会收起键盘
    return CodeEditorTapRegion(
      // 覆盖整栏矩形，落在按键之间的间隙同样算作栏内
      behavior: HitTestBehavior.opaque,
      // 整栏不参与焦点争夺，避免点击时输入法收起
      child: ExcludeFocus(
        child: _buildMainBar(context, colorScheme, symbols, editorState, visibleActions),
      ),
    );
  }

  /// 构建快捷输入主栏（标点按键与右侧操作区）
  Widget _buildMainBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<PunctuationSymbol> symbols,
    NovelEditorState editorState,
    List<QuickInputAction> visibleActions,
  ) {
    return Container(
      height: _barHeight,
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // 标点符号按键（数量较多，横向滚动显示）
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: _keyListLeftPadding, right: 4),
              itemCount: symbols.length,
              itemBuilder: (context, index) {
                final symbol = symbols[index];
                return PunctuationKeyButton(symbol: symbol, onTap: () => _handleSymbolTap(symbol));
              },
            ),
          ),

          // 与右侧操作区之间的分隔线，上下留白避免顶满整栏；
          // 两个图标都设为「无」时一并隐藏，标点按键占满整栏
          if (visibleActions.isNotEmpty)
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: colorScheme.outlineVariant,
            ),

          // 右侧操作区：最多两个快捷操作图标，种类与顺序由设置决定
          ..._buildRightActions(editorState, visibleActions),
        ],
      ),
    );
  }
}
