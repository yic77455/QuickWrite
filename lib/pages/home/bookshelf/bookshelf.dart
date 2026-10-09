import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/providers/writing_stats_provider.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/shared/dialogs/integrity_check_dialog.dart';
import 'widgets/widgets.dart';

/// 书架页面
///
/// 展示用户的书籍列表，包括：
/// - 左侧：最近编辑的书籍大封面和详细信息
/// - 右侧：所有书籍的网格列表，支持拖拽排序
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  // 用于控制首帧后才真正渲染拖拽网格，避免在数据加载前就渲染拖拽网格，导致异常行为
  bool _isReady = false;
  // 最近一次已经反映到界面的同步轮次，用于识别同步是否带来了新数据
  int _syncedRevision = CloudSyncService.instance.syncRevision;

  @override
  void initState() {
    super.initState();
    
    // 设置书籍更新回调：当工作台保存章节后，自动刷新书架数据和码字统计数据
    MultiWindowService.instance.onBookUpdated = () {
      // 工作台保存的内容需要在静置后推送到云端
      CloudSyncService.instance.notifyLocalChange();

      // 确保在 Widget 生命周期内才执行刷新
      if (mounted) {
        context.read<BookshelfProvider>().refresh();
        context.read<WritingStatsProvider>().refresh();
      }
    };

    // 自动同步会在后台改写数据库，完成后需要重新加载书架与统计数据
    CloudSyncService.instance.addListener(_onCloudSyncChanged);

    // 上次选择稍后处理时，重新进入界面按最新文件状态再次检测并提示
    context.read<BookshelfProvider>().refreshIntegrityPrompt();
    
    // 首帧渲染完成后的回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isReady = true; // 此时窗口大小已彻底固定，可以安全渲染拖拽网格了
        });
      }
    });
  }

  @override
  void dispose() {
    CloudSyncService.instance.removeListener(_onCloudSyncChanged);
    super.dispose();
  }

  /// 响应云同步状态变化
  ///
  /// 仅在同步结束（轮次增加）时刷新数据，同步进度等信息无需触发刷新
  void _onCloudSyncChanged() {
    final service = CloudSyncService.instance;
    if (service.syncRevision == _syncedRevision) return;

    _syncedRevision = service.syncRevision;
    if (!mounted) return;

    context.read<BookshelfProvider>().refresh();
    context.read<WritingStatsProvider>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    // 从 Provider 中监听数据变化
    // watch 的意思是：只要 Provider 里的 notifyListeners() 被调用，这个 build 方法就会重新执行
    final provider = context.watch<BookshelfProvider>();

    // 如果数据库还没初始化完，显示 Loading 动画
    if (!provider.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 检查是否需要显示数据完整性校验对话框
    // 是否提示由 Provider 记录：用户选择稍后处理时，重新进入界面才会再次提示
    if (provider.shouldShowIntegrityDialog) {
      final result = provider.integrityCheckResult!;
      // 延迟显示对话框，避免在 build 中直接显示
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !provider.shouldShowIntegrityDialog) return;

        provider.beginIntegrityPrompt();
        final resolved = await showIntegrityCheckDialog(
          context,
          provider.isar,
          result,
        );
        provider.completeIntegrityPrompt(resolved: resolved);
      });
    }

    final books = provider.books;
    final recentBook = provider.recentBook;

    // 如果没有数据，显示空状态插画
    if (books.isEmpty || recentBook == null) {
      return const EmptyBookshelf();
    }

    // 数据加载完成，且不是空的，开始渲染书架页面
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        // 左、上、下保持 32，右侧减小到 12，让滚动条更靠近窗体边框
        padding: const EdgeInsets.only(
          left: 32,
          top: 32,
          bottom: 32,
          right: 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start, // 顶部对齐
          children: [
            // 左侧大封面
            Flexible(flex: 0, child: RecentBookPanel(recentBook: recentBook)),
            const SizedBox(width: 36),
            // 右侧网格
            Expanded(
              child: AllBooksGrid(books: books, isReady: _isReady),
            ),
          ],
        ),
      ),
    );
  }
}
