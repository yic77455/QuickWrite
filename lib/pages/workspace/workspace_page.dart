import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/tab_close_guard.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/pages/workspace/left_sidebar/widgets/left_sidebar_expand_btn.dart';
import 'package:quick_write/shared/dialogs/word_count_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'left_sidebar/left_sidebar.dart';
import 'right_sidebar/right_sidebar.dart';
import 'toolbar/workspace_toolbar.dart';
import 'editor/editor_container.dart';
import 'widgets/mobile_workspace_app_bar.dart';
import 'widgets/mobile_quick_input_bar.dart';
import 'widgets/mobile_outline_toolbar.dart';

/// 工作台页面
class WorkspacePage extends StatelessWidget {
  // 书籍ID，从书架传过来
  final String bookId;

  // 主窗口ID（用于向主窗口发送消息）
  final String? mainWindowId;

  // 同窗口模式下的书籍保存回调（保存章节后通知书架刷新）
  final VoidCallback? onBookSaved;

  const WorkspacePage({super.key, required this.bookId, this.mainWindowId, this.onBookSaved});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WorkspaceProvider(),
      child: _WorkspaceContent(bookId: bookId, mainWindowId: mainWindowId, onBookSaved: onBookSaved),
    );
  }
}

// 工作台内容组件
class _WorkspaceContent extends StatefulWidget {
  // 书籍ID
  final String bookId;

  // 主窗口ID（用于向主窗口发送消息）
  final String? mainWindowId;

  // 同窗口模式下的书籍保存回调（保存章节后通知书架刷新）
  final VoidCallback? onBookSaved;

  const _WorkspaceContent({required this.bookId, this.mainWindowId, this.onBookSaved});

  @override
  State<_WorkspaceContent> createState() => _WorkspaceContentState();
}

class _WorkspaceContentState extends State<_WorkspaceContent> {
  // 上一次已知的可用宽度，避免重复更新
  double _lastKnownWidth = 0;

  // 保存 WindowProvider 引用，便于在 dispose 中安全清空回调
  // dispose 阶段 widget 已从树中移除，不能再通过 context.read 获取 Provider
  WindowProvider? _windowProvider;

  // 关闭是否已确认并完成收尾
  // 主窗口退出流程会先请求本窗口确认关闭，随后窗口自身关闭时不应再弹窗、再收尾
  bool _closeConfirmed = false;

  // 移动端右抽屉的 Scaffold 控制器，用于将右侧面板状态同步到抽屉开合
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();

  // 上一次已知的右侧面板展开状态；为 null 表示尚未完成首次同步
  bool? _prevRightSidebarExpanded;

  // 移动端左侧目录抽屉是否打开，用于同步顶部目录入口的选中高亮
  bool _isMobileContentsDrawerOpen = false;

  // 移动端左侧目录抽屉占屏幕宽度的比例
  static const double _mobileDrawerWidthFactor = 0.75;

  // 移动端右侧面板抽屉占屏幕宽度的比例
  static const double _mobileRightDrawerWidthFactor = 0.75;

  @override
  void initState() {
    super.initState();
    // 初始化工作台数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final workspaceProvider = context.read<WorkspaceProvider>();
      _windowProvider = context.read<WindowProvider>();

      workspaceProvider.initialize(
        widget.bookId,
        mainWindowId: widget.mainWindowId,
        onBookSaved: widget.onBookSaved,
      );

      // 关闭前的确认与收尾：检查未保存内容，保存光标位置与标签页会话后清空标签页
      // 已确认过时直接放行，避免主窗口退出流程与窗口自身关闭流程重复弹窗、重复收尾
      Future<bool> confirmCloseAndCleanup() async {
        if (_closeConfirmed) return true;

        // 关闭窗口前检查未保存内容，让用户选择保存/不保存/取消
        // 选择"保存"会保存所有未保存的标签页；选择"取消"则中止关闭流程
        final shouldClose = await TabCloseGuard.confirmCloseWindow(
          context: context,
          provider: workspaceProvider,
        );
        if (!shouldClose) return false;

        // 保存所有的光标位置
        await workspaceProvider.saveAllCursorPositions();
        // 保存标签页会话，供下次打开作品时恢复
        await workspaceProvider.saveTabSession();
        // 清空所有标签页
        workspaceProvider.closeAllTabs();
        _closeConfirmed = true;
        return true; // 允许关闭
      }

      // 设置窗口关闭前的清理回调
      _windowProvider!.onBeforeClose = confirmCloseAndCleanup;

      // 设置主窗口请求关闭时的回调：主窗口退出时先请求本窗口确认，再关闭本窗口
      MultiWindowService.instance.onRequestClose = confirmCloseAndCleanup;

      // 设置从最大化恢复时的回调
      // 在窗口恢复前将边栏宽度调整到恢复后窗口的安全范围内，避免溢出
      _windowProvider!.onBeforeUnmaximize = () async {
        final cache = WindowCacheService.instance;
        final restoredWidth = _windowProvider!.windowType == WindowType.workspace
            ? cache.workspaceWindowSize.width
            : cache.mainWindowSize.width;
        workspaceProvider.clampSidebarsToWidth(restoredWidth);
      };

      // 设置最大化完成后的回调
      // 窗口最大化会使编辑区失去输入焦点，此处将焦点归还给当前标签页的正文编辑器
      _windowProvider!.onAfterMaximize = () async {
        workspaceProvider.requestEditorFocus();
      };

      // 设置从最大化恢复完成后的回调
      // 恢复过程中编辑区同样会失去输入焦点，此处将焦点归还给当前标签页的正文编辑器
      _windowProvider!.onAfterUnmaximize = () async {
        workspaceProvider.requestEditorFocus();
      };
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听窗口宽度变化，更新可用宽度并自动调整边栏
    final availableWidth = MediaQuery.of(context).size.width;
    if (_lastKnownWidth != availableWidth) {
      _lastKnownWidth = availableWidth;
      // 延迟到当前 build 帧结束后再更新，避免在 build 阶段调用 notifyListeners 导致报错
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<WorkspaceProvider>().updateAvailableWidth(availableWidth);
        }
      });
    }
  }

  @override
  void dispose() {
    // 使用 initState 中保存的引用清空回调，避免在 dispose 中使用已失效的 context
    // 同窗口模式下从工作台返回书架时，WorkspacePage 会被卸载，
    // 若不清空 onBeforeClose，下次关闭主窗口时会因使用失效的 context 而报错
    _windowProvider?.onBeforeClose = null;
    _windowProvider?.onBeforeUnmaximize = null;
    _windowProvider?.onAfterMaximize = null;
    _windowProvider?.onAfterUnmaximize = null;
    MultiWindowService.instance.onRequestClose = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 移动端采用编辑区全屏 + 左右抽屉的布局
    if (PlatformCapabilities.isMobile) {
      return _buildMobileLayout(context);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      appBar: _workspaceTitleBar(context),
      body: Column(
        children: [
          // 顶部工具栏（与标题栏视觉一体）
          const WorkspaceToolbar(),

          // 主要内容区域
          Expanded(
            child: Stack(
              children: [
                // 底层布局
                Row(
                  children: [
                    // 左侧边栏（章节目录 + 设定）
                    const LeftSidebar(),

                    // 中间编辑区（多标签页）
                    Expanded(child: _buildEditorCard(context)),

                    // 右侧边栏（属性面板）
                    const RightSidebar(),
                  ],
                ),

                // 左侧边栏拖拽分隔条（浮层，不占用布局空间）
                // 仅在左侧边栏展开时显示
                // 定位：控制器中心对齐侧边栏边缘
                if (context.watch<WorkspaceProvider>().isLeftSidebarExpanded)
                  Positioned(
                    left: context.watch<WorkspaceProvider>().leftSidebarWidth,
                    top: 0,
                    bottom: 0,
                    child: ResizableDivider(
                      direction: ResizeDirection.left,
                      getCurrentWidth: () => context.read<WorkspaceProvider>().leftSidebarWidth,
                      onWidthChanged: (width) {
                        context.read<WorkspaceProvider>().setLeftSidebarWidth(width);
                      },
                    ),
                  ),

                // 右侧边栏拖拽分隔条（浮层，不占用布局空间）
                // 定位：控制器中心对齐侧边栏边缘
                if (context.watch<WorkspaceProvider>().isRightSidebarExpanded)
                  Positioned(
                    right: context.watch<WorkspaceProvider>().rightSidebarWidth,
                    top: 0,
                    bottom: 0,
                    child: ResizableDivider(
                      direction: ResizeDirection.right,
                      getCurrentWidth: () => context.read<WorkspaceProvider>().rightSidebarWidth,
                      onWidthChanged: (width) {
                        context.read<WorkspaceProvider>().setRightSidebarWidth(width);
                      },
                    ),
                  ),

                // 左侧边栏收起时的展开按钮（贴边长按钮）
                if (!context.watch<WorkspaceProvider>().isLeftSidebarExpanded) _buildLeftSidebarExpandButton(context),
              ],
            ),
          ),

          // 底部状态栏（紧凑卡片样式）
          _buildBottomStatusBar(context),
        ],
      ),
    );
  }

  /// 构建移动端布局：编辑区全屏，章节目录与属性面板分别收纳为左右抽屉
  Widget _buildMobileLayout(BuildContext context) {
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    // 右侧面板的开合与右抽屉保持同步
    _scheduleMobileRightDrawerSync(workspaceProvider.isRightSidebarExpanded);

    // 横屏且输入法弹出时进入沉浸编辑：顶部操作栏与标签页栏一并收起，
    // 避免两层固定栏与键盘上方的工具栏互相挤压，同时让正文可见区域最大化；
    // 键盘收起后两层固定栏自动恢复
    final bool immersiveEditing = MediaQuery.orientationOf(context) == Orientation.landscape &&
        MediaQuery.viewInsetsOf(context).bottom > 0;

    // 顶部系统状态栏高度：沉浸编辑时顶部操作栏已收起，改由正文区自行避让
    final double topInset = MediaQuery.paddingOf(context).top;

    return PopScope(
      // 拦截系统返回键，交由 _handleMobileBack 处理，避免直接退出应用
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleMobileBack();
      },
      child: Scaffold(
        key: _mobileScaffoldKey,
        backgroundColor: colorScheme.secondaryContainer,
        // 左侧抽屉：章节目录与设定，宽度占屏幕的 75%
        // 抽屉底色与面板一致，避免系统状态栏区域与目录面板出现色差
        drawer: Drawer(
          width: MediaQuery.sizeOf(context).width * _mobileDrawerWidthFactor,
          backgroundColor: colorScheme.surface,
          // 抽屉内容加绘制隔离：滑出与收回只改变图层位置，可直接复用已缓存的图层
          child: const SafeArea(child: RepaintBoundary(child: LeftSidebar(forceExpanded: true))),
        ),
        // 右侧抽屉：属性与工具面板，宽度占屏幕的 75%
        endDrawer: Drawer(
          width: MediaQuery.sizeOf(context).width * _mobileRightDrawerWidthFactor,
          backgroundColor: colorScheme.surface,
          // 与左侧抽屉同理，隔离绘制避免抽屉滑动时逐帧重绘下方正文
          child: const SafeArea(child: RepaintBoundary(child: RightSidebar(forceExpanded: true))),
        ),
        // 左抽屉开合时同步顶部目录入口的选中高亮
        onDrawerChanged: (isOpen) {
          if (_isMobileContentsDrawerOpen == isOpen) return;
          setState(() => _isMobileContentsDrawerOpen = isOpen);
        },
        // 用户滑动或点击遮罩关闭右抽屉时，同步收起右侧面板状态
        onEndDrawerChanged: (isOpen) {
          if (!isOpen) context.read<WorkspaceProvider>().closeRightSidebar();
        },
        // 常规状态下应用界面延伸到系统状态栏后方，由顶部操作栏自行避让系统状态栏；
        // 沉浸编辑时顶部操作栏已收起，改由下方 AnimatedPadding 避让，避免正文被系统状态栏压住。
        // 底部间距交由下方状态栏自行避让系统导航栏，此处不再重复避让
        body: SafeArea(
          top: false,
          bottom: false,
          // 正文区域加绘制隔离：抽屉滑出与收回期间正文保持静止，可直接复用已缓存的图层
          child: RepaintBoundary(
            child: AnimatedPadding(
              // 沉浸编辑时补上系统状态栏高度，与顶部操作栏的收起动画同步，全程无跳动
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(top: immersiveEditing ? topInset : 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 键盘上方工具栏可占用的最大高度：扣除顶部操作栏（含其状态栏安全区）后的剩余高度。
                  // 沉浸编辑时顶部操作栏已收起，无需扣减；横屏等纵向空间紧张的场景下
                  // 工具栏会被压缩到该上限内，保证整列布局不溢出
                  final double chromeHeight =
                      immersiveEditing ? 0.0 : MobileWorkspaceAppBar.contentHeight + topInset;
                  final double barsMaxHeight = math.max(0.0, constraints.maxHeight - chromeHeight);

                  return Column(
                    children: [
                      // 顶部操作栏（自定义，不占用 Scaffold 的 appBar 槽位）
                      // 移动端横屏输入法弹出时收起，把纵向空间全部让给编辑区；
                      // 占满整宽由外层 SizedBox 保证，使收起/恢复动画只发生在纵向
                      SizedBox(
                        width: double.infinity,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: immersiveEditing
                              ? const SizedBox.shrink()
                              // 监听专用的历史状态通知器，仅刷新撤销/恢复按钮的禁用态
                              : ListenableBuilder(
                                  listenable: workspaceProvider.editHistoryNotifier,
                                  builder: (context, _) => MobileWorkspaceAppBar(
                                    onBack: _handleBackToShelf,
                                    onUndo: workspaceProvider.undo,
                                    onRedo: workspaceProvider.redo,
                                    canUndo: workspaceProvider.canUndo,
                                    canRedo: workspaceProvider.canRedo,
                                    onContents: () => _mobileScaffoldKey.currentState?.openDrawer(),
                                    isContentsSelected: _isMobileContentsDrawerOpen,
                                  ),
                                ),
                        ),
                      ),

                      // 编辑区占满剩余空间（沉浸编辑时一并收起编辑区内的标签页栏）
                      Expanded(child: _buildEditorCard(context, hideTabBar: immersiveEditing)),

                      // 键盘上方的快捷输入栏（键盘弹出时显示）
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: barsMaxHeight),
                        child: const MobileQuickInputBar(),
                      ),

                      // 键盘上方的大纲编辑器工具栏（键盘弹出或节点批量选择模式下显示）
                      // 与快捷输入栏分属不同类型的标签页，同一时刻只会显示其中一个
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: barsMaxHeight),
                        child: const MobileOutlineToolbar(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),

        // 底部状态栏（精简信息，仅保留保存状态与字数）
        // 固定在屏幕底部，键盘弹出时由输入法直接覆盖，不随输入法上移
        bottomNavigationBar: SafeArea(
          top: false,
          child: _buildMobileBottomStatusBar(context),
        ),
      ),
    );
  }

  /// 将右侧面板的展开状态同步到右抽屉的开合
  ///
  /// 工具栏按钮与右侧面板的关闭按钮都会改变展开状态，此处统一映射为抽屉的打开与关闭
  void _scheduleMobileRightDrawerSync(bool expanded) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 首次同步只记录状态，避免进入工作台时自动弹出右抽屉
      if (_prevRightSidebarExpanded == null) {
        _prevRightSidebarExpanded = expanded;
        return;
      }
      if (_prevRightSidebarExpanded == expanded) return;
      _prevRightSidebarExpanded = expanded;

      final scaffoldState = _mobileScaffoldKey.currentState;
      if (scaffoldState == null) return;
      if (expanded) {
        scaffoldState.openEndDrawer();
      } else {
        scaffoldState.closeEndDrawer();
      }
    });
  }

  /// 构建编辑器卡片
  ///
  /// [hideTabBar] 为 true 时收起编辑区内部的标签页栏（移动端横屏沉浸编辑）
  Widget _buildEditorCard(BuildContext context, {bool hideTabBar = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(left: 2, right: 4, top: 2, bottom: 2),
      decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(6)),
      // 裁剪子组件，确保圆角生效
      clipBehavior: Clip.antiAlias,
      child: EditorContainer(hideTabBar: hideTabBar),
    );
  }

  /// 构建左侧边栏展开按钮（贴边按钮）
  /// 当左侧边栏收起时显示在左侧边缘，点击后展开左侧边栏并隐藏此按钮
  Widget _buildLeftSidebarExpandButton(BuildContext context) {
    return const Positioned(left: 0, top: 0, bottom: 0, child: Center(child: LeftSidebarExpandButton()));
  }

  /// 构建底部状态栏（桌面端）
  Widget _buildBottomStatusBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final currentTab = workspaceProvider.currentTab;

    return Container(
      height: 28,
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          // 左侧：当前文件信息
          Icon(Icons.article_outlined, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(currentTab?.title ?? '未打开文件', style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),

          const Spacer(),

          // 大纲标签页额外显示主题数，正文标签页仅显示字数
          if (currentTab?.usesOutlineEditor ?? false) ...[
            // 监听专用的字数通知器，主题数变化时仅重建此区域
            ListenableBuilder(
              listenable: workspaceProvider.wordCountNotifier,
              builder: (context, _) {
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_tree_outlined, size: 14),
                      const SizedBox(width: 4),
                      Text('主题：${currentTab?.topicCount ?? 0}', style: context.bodySmall),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
          ],

          // 字数统计
          _buildWordCountIndicator(context, workspaceProvider, currentTab),

          const SizedBox(width: 16),

          // 右侧：保存状态信息
          _buildSaveStatusIndicator(context, colorScheme, currentTab),
        ],
      ),
    );
  }

  /// 构建底部状态栏（移动端）
  ///
  /// 精简信息以防窄屏溢出：左侧显示作品名，右侧保留主题数与字数统计
  Widget _buildMobileBottomStatusBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final currentTab = workspaceProvider.currentTab;

    return Container(
      height: 28,
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          // 左侧：作品名（过长时省略号截断）
          Expanded(
            child: Text(
              '《${workspaceProvider.bookTitle}》',
              style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 12),

          // 大纲标签页额外显示主题数，正文标签页仅显示字数
          if (currentTab?.usesOutlineEditor ?? false) ...[
            // 监听专用的字数通知器，主题数变化时仅重建此区域
            ListenableBuilder(
              listenable: workspaceProvider.wordCountNotifier,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_tree_outlined, size: 14),
                  const SizedBox(width: 4),
                  Text('主题：${currentTab?.topicCount ?? 0}', style: context.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],

          // 右侧：字数统计
          _buildWordCountIndicator(context, workspaceProvider, currentTab),
        ],
      ),
    );
  }

  /// 构建保存状态指示（图标 + 文案，存在未保存修改时用错误色提示）
  Widget _buildSaveStatusIndicator(BuildContext context, ColorScheme colorScheme, EditorTab? currentTab) {
    final isModified = currentTab?.isModified == true;
    final color = isModified ? colorScheme.error : colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.save_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(isModified ? '未保存' : '已保存', style: context.bodySmall?.copyWith(color: color)),
      ],
    );
  }

  /// 构建字数统计指示（点击可打开详细字数统计弹窗）
  ///
  /// 通过 ListenableBuilder 监听专用的字数通知器，编辑器内容变化时仅重建此区域；
  /// 内部再以 ValueListenableBuilder 监听选中字数变化，避免整个状态栏与编辑器重建
  Widget _buildWordCountIndicator(BuildContext context, WorkspaceProvider provider, EditorTab? currentTab) {
    return ListenableBuilder(
      listenable: provider.wordCountNotifier,
      builder: (context, _) {
        // 获取当前章节字数
        final currentWordCount = currentTab?.wordCount ?? 0;
        // 获取选中字数通知器（为空时直接显示总字数，无需监听）
        final selectedWordCountNotifier = currentTab?.selectedWordCountNotifier;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _showWordCountDialog(context, provider),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.text_fields, size: 14),
                const SizedBox(width: 4),
                if (selectedWordCountNotifier == null)
                  Text('字数：$currentWordCount 字', style: context.bodySmall)
                else
                  ValueListenableBuilder<int>(
                    valueListenable: selectedWordCountNotifier,
                    builder: (context, selectedWordCount, _) {
                      final wordCountText = selectedWordCount > 0
                          ? '字数：$selectedWordCount/$currentWordCount 字'
                          : '字数：$currentWordCount 字';
                      return Text(wordCountText, style: context.bodySmall);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示字数统计弹窗
  void _showWordCountDialog(BuildContext context, WorkspaceProvider provider) {
    final currentTab = provider.currentTab;

    // 如果没有打开的标签页，不显示弹窗
    if (currentTab == null || currentTab.textController == null) {
      return;
    }

    // 获取详细字数统计
    final result = WordCountUtils.countWordsDetail(currentTab.textController!.text);

    showWordCountDialog(context: context, result: result, chapterTitle: currentTab.title);
  }

  /// 返回书架
  /// 返回前若存在未保存内容，弹窗让用户选择保存/不保存/取消
  Future<void> _handleBackToShelf() async {
    // 在 async gap 之前捕获 provider 引用，避免跨 async gap 使用 BuildContext
    final provider = context.read<WorkspaceProvider>();
    // 返回书架前检查未保存内容，让用户选择保存/不保存/取消
    final shouldReturn = await TabCloseGuard.confirmCloseWindow(
      context: context,
      provider: provider,
      title: '返回书架',
      descriptionTemplate: '有 {n} 个标签页的修改尚未保存，是否在返回前保存？',
      saveText: '保存',
    );
    if (!shouldReturn) return;
    // 保存所有打开标签页的光标位置到缓存
    await provider.saveAllCursorPositions();
    // 保存标签页会话，供下次打开作品时恢复
    await provider.saveTabSession();
    // 返回书架主界面
    if (!mounted) return;
    // 移动端工作台以 push 方式打开，返回时弹出当前页面以播放反向切换动效；
    // 工作台为唯一页面时无页面可弹出，直接跳转到书架
    if (PlatformCapabilities.isMobile && context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  /// 处理移动端系统返回键
  ///
  /// 抽屉打开时优先收起抽屉，与系统返回键的常规行为一致；
  /// 否则走与顶部返回按钮相同的流程返回书架（含未保存内容的确认）
  void _handleMobileBack() {
    final scaffoldState = _mobileScaffoldKey.currentState;
    if (scaffoldState != null) {
      if (scaffoldState.isDrawerOpen) {
        scaffoldState.closeDrawer();
        return;
      }
      if (scaffoldState.isEndDrawerOpen) {
        scaffoldState.closeEndDrawer();
        return;
      }
    }
    _handleBackToShelf();
  }

  /// 构建标题栏
  PreferredSizeWidget _workspaceTitleBar(BuildContext context) {
    // 判断是否在新窗口中打开（通过 WindowProvider 的窗口类型判断）
    final windowProvider = context.watch<WindowProvider>();
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final isOpenInNewWindow = windowProvider.windowType == WindowType.workspace;

    // 获取书籍标题
    final bookTitle = workspaceProvider.bookTitle;

    return AppTitleBar(
      // centerTitle: true,
      title: Text('《$bookTitle》 - 正在创作', style: Theme.of(context).textTheme.bodyMedium),
      // 新窗口打开时显示静态 LOGO；否则显示可返回书架的 LOGO 按钮
      // 统一用 Center 包裹：Center 提供松约束，避免 LOGO 被标题栏的紧约束拉伸放大
      leading: isOpenInNewWindow
          ? const Center(child: _AppLogo())
          : Center(child: _LogoBackButton(onPressed: _handleBackToShelf)),
      // 收窄左侧区域宽度与标题间距，让标题贴近 LOGO
      leadingWidth: 40,
      titleSpacing: 4,
      height: 40,
    );
  }
}

/// 应用 LOGO 图标
///
/// 根据主题亮度自动切换图片：浅色使用 icon1，深色使用 icon2
class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      Theme.of(context).brightness == Brightness.dark
          ? 'assets/icon/icon2.png'
          : 'assets/icon/icon1.png',
      // LOGO 显示尺寸
      width: 24,
      height: 24,
      fit: BoxFit.contain, // 保持比例，避免拉伸变形
    );
  }
}

/// 返回按钮
///
/// - 默认显示应用 LOGO
/// - 悬停时切换为返回箭头，并显示主色高亮背景
class _LogoBackButton extends StatefulWidget {
  // 点击返回时执行的回调
  final VoidCallback onPressed;

  const _LogoBackButton({required this.onPressed});

  @override
  State<_LogoBackButton> createState() => _LogoBackButtonState();
}

class _LogoBackButtonState extends State<_LogoBackButton> {
  // 记录鼠标是否悬停，用于在 LOGO 与返回箭头之间切换
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          onTap: widget.onPressed,
          // 高亮框尺寸，略小于标题栏高度，使上下边缘留出间距
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              // 悬停显示返回箭头，默认显示应用 LOGO
              child: _isHovered ? const Icon(Icons.arrow_back, size: 18) : const _AppLogo(),
            ),
          ),
        ),
      ),
    );
  }
}
