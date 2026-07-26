import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
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

      // 设置窗口关闭前的清理回调
      _windowProvider!.onBeforeClose = () async {
        // 关闭窗口前检查未保存内容，让用户选择保存/不保存/取消
        // 选择"保存"会保存所有未保存的标签页；选择"取消"则中止关闭流程
        final shouldClose = await TabCloseGuard.confirmCloseWindow(
          context: context,
          provider: workspaceProvider,
        );
        if (!shouldClose) return false;

        // 保存所有的光标位置
        await workspaceProvider.saveAllCursorPositions();
        // 清空所有标签页
        workspaceProvider.closeAllTabs();
        return true; // 允许关闭
      };

      // 设置从最大化恢复时的回调
      // 在窗口恢复前将边栏宽度调整到恢复后窗口的安全范围内，避免溢出
      _windowProvider!.onBeforeUnmaximize = () async {
        final cache = WindowCacheService.instance;
        final restoredWidth = _windowProvider!.windowType == WindowType.workspace
            ? cache.workspaceWindowSize.width
            : cache.mainWindowSize.width;
        workspaceProvider.clampSidebarsToWidth(restoredWidth);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

  /// 构建编辑器卡片
  Widget _buildEditorCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(left: 2, right: 4, top: 2, bottom: 2),
      decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(6)),
      // 裁剪子组件，确保圆角生效
      clipBehavior: Clip.antiAlias,
      child: const EditorContainer(),
    );
  }

  /// 构建左侧边栏展开按钮（贴边按钮）
  /// 当左侧边栏收起时显示在左侧边缘，点击后展开左侧边栏并隐藏此按钮
  Widget _buildLeftSidebarExpandButton(BuildContext context) {
    return const Positioned(left: 0, top: 0, bottom: 0, child: Center(child: LeftSidebarExpandButton()));
  }

  /// 构建底部状态栏
  Widget _buildBottomStatusBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final currentTab = workspaceProvider.currentTab;

    // 获取当前章节字数
    final currentWordCount = currentTab?.wordCount ?? 0;
    // 获取选中字数通知器（为空时直接显示总字数，无需监听）
    final selectedWordCountNotifier = currentTab?.selectedWordCountNotifier;
    // 大纲类型标签页使用独立的统计格式
    final isOutlineTab = currentTab?.usesOutlineEditor ?? false;
    final topicCount = currentTab?.topicCount ?? 0;

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

          // 中间：统计信息
          // 大纲标签页额外显示主题数，正文标签页仅显示字数
          // 字数统计通过 ValueListenableBuilder 只监听选中字数变化，
          // 选区变化时仅重建此处文本，避免整个状态栏与编辑器重建
          if (isOutlineTab) ...[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_tree_outlined, size: 14),
                  const SizedBox(width: 4),
                  Text('主题：$topicCount', style: context.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showWordCountDialog(context, workspaceProvider),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.text_fields, size: 14),
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
          ),

          const SizedBox(width: 16),

          // 右侧：状态信息
          Icon(
            Icons.save_outlined,
            size: 14,
            color: currentTab?.isModified == true ? colorScheme.error : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            currentTab?.isModified == true ? '未保存' : '已保存',
            style: context.bodySmall?.copyWith(
              color: currentTab?.isModified == true ? colorScheme.error : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
      // 如果是在新窗口打开的，显示 LOGO；否则显示返回按钮
      leading: isOpenInNewWindow
          ? Padding(padding: const EdgeInsets.only(left: 8.0), child: Icon(Icons.book))
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              // 返回书架前若存在未保存内容，弹窗让用户选择保存/不保存/取消
              onPressed: () async {
                // 在 async gap 之前捕获 provider 引用，避免跨 async gap 使用 BuildContext
                final provider = context.read<WorkspaceProvider>();
                // 返回书架前检查未保存内容，让用户选择保存/不保存/取消
                final shouldReturn = await TabCloseGuard.confirmCloseWindow(
                  context: context,
                  provider: provider,
                  title: '返回书架',
                  descriptionTemplate: '有 {n} 个标签页的修改尚未保存，是否在返回前保存？',
                  saveText: '保存并返回',
                );
                if (!shouldReturn) return;
                // 保存所有打开标签页的光标位置到缓存
                await provider.saveAllCursorPositions();
                // 返回书架主界面
                if (context.mounted) {
                  context.go('/');
                }
              },
            ),
      height: 40,
    );
  }
}
