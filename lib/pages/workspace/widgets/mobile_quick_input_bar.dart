import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/pages/workspace/editor/novel_editor.dart';
import 'package:quick_write/pages/workspace/widgets/punctuation_key_button.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// 移动端快捷输入栏
///
/// 软键盘弹出时贴在键盘上方，提供常用标点符号的快捷输入；
/// 右端提供前往「其他设置」的入口。
class MobileQuickInputBar extends StatefulWidget {
  const MobileQuickInputBar({super.key});

  @override
  State<MobileQuickInputBar> createState() => _MobileQuickInputBarState();
}

class _MobileQuickInputBarState extends State<MobileQuickInputBar> with WidgetsBindingObserver {
  /// 快捷输入栏高度
  static const double _barHeight = 44;

  /// 标点按键列表左侧留白，避免首个按键紧贴屏幕边缘不便点按
  static const double _keyListLeftPadding = 8;

  /// 软键盘高度，大于 0 表示键盘正在显示
  double _keyboardHeight = 0;

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
    if (mounted) setState(() {});
  }

  /// 设置变化时重新判断显隐
  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// 同步软键盘高度
  ///
  /// 高度取自窗口视图的原始内边距：Scaffold 按键盘高度收缩本子树时，
  /// 会一并剔除子树 MediaQuery 中的底部内边距，从 MediaQuery 读取无法识别键盘升降。
  void _syncKeyboardHeight() {
    if (!mounted) return;
    final double height = View.of(context).viewInsets.bottom;
    if (height == _keyboardHeight) return;
    setState(() => _keyboardHeight = height);
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
  /// 仅在移动端键盘弹出、且输入焦点位于正文编辑器时显示。
  bool get _shouldShow {
    if (_keyboardHeight <= 0) return false;
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

  @override
  Widget build(BuildContext context) {
    // 切换标签页时重新判断显隐
    context.watch<WorkspaceProvider>();

    if (!_shouldShow) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    // 整栏纳入编辑器的点击区域组：编辑区在点击自身区域之外时会主动失焦收起输入法，
    // 快捷栏必须归属同一区域组，否则一碰就会收起键盘
    return CodeEditorTapRegion(
      // 覆盖整栏矩形，落在按键之间的间隙同样算作栏内
      behavior: HitTestBehavior.opaque,
      // 整栏不参与焦点争夺，避免点击时输入法收起
      child: ExcludeFocus(
        child: Container(
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
                  itemCount: PunctuationSymbols.quickInputKeys.length,
                  itemBuilder: (context, index) {
                    final symbol = PunctuationSymbols.quickInputKeys[index];
                    return PunctuationKeyButton(symbol: symbol, onTap: () => _handleSymbolTap(symbol));
                  },
                ),
              ),

              // 与设置入口之间的分隔线，上下留白避免顶满整栏
              Container(
                width: 1,
                height: _barHeight - 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: colorScheme.outlineVariant,
              ),

              // 其他设置入口
              SmallToolbarButton(
                icon: Icons.settings_rounded,
                tooltip: '其他设置',
                width: 44,
                height: _barHeight,
                iconSize: 20,
                onPressed: _handleSettingsTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
