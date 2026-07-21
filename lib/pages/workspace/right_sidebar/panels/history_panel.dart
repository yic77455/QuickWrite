import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import '../widgets/right_sidebar_widgets.dart';

/// 历史版本面板
///
/// 在右侧边栏中显示当前章节的备份历史记录，
/// 支持预览、删除和恢复操作
class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  /// 当前章节的备份记录列表
  List<BackupRecord> _backups = [];

  /// 是否正在加载
  bool _isLoading = true;

  /// 当前标签页ID（用于检测标签页切换）
  String? _currentTabId;

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 上次点击的时间戳，用于手动检测双击
  int _lastTapTime = 0;

  /// 上次点击的备份文件路径，用于手动检测双击
  String? _lastTappedBackupPath;

  /// 备份记录项的估算高度
  static const double _backupItemExtent = 76.0;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 检测标签页切换，自动刷新备份列表
    final tab = context.watch<WorkspaceProvider>().currentTab;
    if (tab?.id != _currentTabId) {
      _currentTabId = tab?.id;
      _loadBackups();
    }
  }

  

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = context.watch<WorkspaceProvider>();
    final tab = provider.currentTab;

    return Container(
      color: colorScheme.surface.withValues(alpha: 0.3),
      child: Column(
        children: [
          // 章节信息栏
          _buildChapterInfo(context, tab, colorScheme),

          // 分隔线
          Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),

          // 备份列表区域
          Expanded(child: _buildBackupList(context, tab, colorScheme)),
        ],
      ),
    );
  }

  /// 构建章节信息栏
  Widget _buildChapterInfo(BuildContext context, EditorTab? tab, ColorScheme colorScheme) {
    final isChapter = tab != null && tab.type == EditorTabType.chapter;
    final isSetting = tab != null && tab.type == EditorTabType.settings;
    final isBackupPreview = tab != null && tab.type == EditorTabType.backupPreview;
    final hasContent = isChapter || isSetting || isBackupPreview;

    // 备份预览标签页显示原始标题
    String displayTitle;
    if (isBackupPreview) {
      displayTitle = tab.originalChapterTitle ?? tab.title;
    } else if (tab != null) {
      displayTitle = tab.title;
    } else {
      displayTitle = '';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            isBackupPreview ? Icons.history_outlined : Icons.article_outlined,
            size: 16,
            color: hasContent ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasContent ? displayTitle : '未选择内容',
              style: context.titleSmall?.copyWith(
                color: hasContent ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasContent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_backups.length} 份',
                style: context.labelSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建备份列表区域
  Widget _buildBackupList(BuildContext context, EditorTab? tab, ColorScheme colorScheme) {
    // 仅章节、大纲和备份预览标签页显示备份列表
    final isValidTab = tab != null &&
        (tab.type == EditorTabType.chapter ||
         tab.type == EditorTabType.settings ||
         tab.type == EditorTabType.backupPreview);
    if (!isValidTab) {
      return _buildEmptyState(context, icon: Icons.article_outlined, text: '请打开一个章节或大纲以查看历史版本', colorScheme: colorScheme);
    }

    // 加载中
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Text('正在加载...', style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // 无备份记录
    if (_backups.isEmpty) {
      return _buildEmptyState(context, icon: Icons.history_rounded, text: '暂无历史版本', colorScheme: colorScheme);
    }

    // 显示备份列表
    return _buildList(context, colorScheme);
  }

  /// 构建空状态提示
  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String text,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(text, style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  /// 构建备份记录列表
  Widget _buildList(BuildContext context, ColorScheme colorScheme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _backups.length,
      itemBuilder: (context, index) {
        final record = _backups[index];
        return Column(children: [_buildBackupItem(context, record, colorScheme), const SizedBox(height: 4)]);
      },
    );
  }

  /// 构建单条备份记录项
  Widget _buildBackupItem(BuildContext context, BackupRecord record, ColorScheme colorScheme) {
    // 判断当前备份记录是否被选中（正在预览中）
    final provider = context.watch<WorkspaceProvider>();
    final currentTab = provider.currentTab;
    final isSelected = currentTab?.type == EditorTabType.backupPreview &&
        currentTab?.backupFilePath == record.filePath;

    return HoverableBackupItem(
      onPreview: () => _previewBackup(record),
      isSelected: isSelected,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // 主信息行：时间 + 大小
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // 时间图标
                  Icon(Icons.schedule_rounded, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  // 时间文字
                  Expanded(
                    child: Text(
                      record.formattedTime,
                      style: context.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  // 文件大小
                  Text(
                    record.formattedSize,
                    style: context.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            // 操作按钮行
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 恢复按钮
                  _buildActionButton(
                    context: context,
                    icon: Icons.restore_rounded,
                    label: '恢复',
                    colorScheme: colorScheme,
                    onTap: () => _restoreBackup(record),
                  ),
                  const SizedBox(width: 4),
                  // 删除按钮
                  _buildActionButton(
                    context: context,
                    icon: Icons.delete_outline_rounded,
                    label: '删除',
                    colorScheme: colorScheme,
                    isDestructive: true,
                    onTap: () => _deleteBackup(record),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    final color = isDestructive ? colorScheme.error : colorScheme.primary;

    return HoverableActionButton(
      color: color,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
  /// 加载当前章节的备份记录
  Future<void> _loadBackups() async {
    final provider = context.read<WorkspaceProvider>();
    final tab = provider.currentTab;
    final book = provider.currentBook;

    if (tab == null || book == null) {
      if (mounted) {
        setState(() {
          _backups = [];
          _isLoading = false;
        });
      }
      return;
    }

    // 确定要查询的书籍 UUID、标题和分卷名
    String bookUuid;
    String chapterTitle;
    String volumeName;
    bool isSetting = false;

    if (tab.type == EditorTabType.backupPreview) {
      // 备份预览标签页：使用存储的原始信息
      bookUuid = tab.originalBookUuid ?? book.uuid;
      chapterTitle = tab.originalChapterTitle ?? tab.title;
      volumeName = tab.originalVolumeName ?? '';
      isSetting = tab.originalIsSetting;
    } else if (tab.type == EditorTabType.chapter) {
      bookUuid = book.uuid;
      chapterTitle = tab.title;
      // 查找章节的分卷名
      final chapter = provider.chapters.where((c) => c.uuid == tab.id).firstOrNull;
      volumeName = provider.getVolumeName(chapter?.volumeUuid ?? '');
    } else if (tab.type == EditorTabType.settings) {
      bookUuid = book.uuid;
      chapterTitle = tab.title;
      volumeName = '';
      isSetting = true;
    } else {
      // 其他类型标签页不显示备份
      if (mounted) {
        setState(() {
          _backups = [];
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    List<BackupRecord> records;
    if (isSetting) {
      records = await BackupService.instance.getSettingBackups(bookUuid, chapterTitle);
    } else {
      records = await BackupService.instance.getChapterBackups(bookUuid, chapterTitle, volumeName: volumeName);
    }

    if (mounted) {
      setState(() {
        _backups = records;
        _isLoading = false;
      });
      // 备份预览标签页：滚动到对应的备份记录
      if (tab.type == EditorTabType.backupPreview && tab.backupFilePath != null) {
        _scrollToBackupRecord(tab.backupFilePath!);
      }
    }
  }

  /// 滚动到指定备份记录
  void _scrollToBackupRecord(String backupFilePath) {
    final index = _backups.indexWhere((r) => r.filePath == backupFilePath);
    if (index == -1) return;

    // 等待列表构建完成后跳转
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final itemOffset = index * _backupItemExtent;
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentOffset = _scrollController.offset;
      // 目标项已在可视区域内，无需跳转
      if (itemOffset >= currentOffset && itemOffset <= currentOffset + viewportHeight) return;
      final targetOffset = (itemOffset - viewportHeight / 3)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(targetOffset);
    });
  }

  /// 打开备份预览标签页
  /// 单击以预览模式打开，双击以固定模式打开
  void _previewBackup(BackupRecord record) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTap = _lastTappedBackupPath == record.filePath &&
        now - _lastTapTime < GlobalConstants.doubleTapThreshold;

    _lastTapTime = now;
    _lastTappedBackupPath = record.filePath;

    final provider = context.read<WorkspaceProvider>();
    final tab = provider.currentTab;
    final book = provider.currentBook;
    if (tab == null || book == null) return;

    // 确定原始标题、分卷名及是否为设定
    String chapterTitle;
    String volumeName;
    bool isSetting;

    if (tab.type == EditorTabType.backupPreview) {
      chapterTitle = tab.originalChapterTitle ?? tab.title;
      volumeName = tab.originalVolumeName ?? '';
      isSetting = tab.originalIsSetting;
    } else if (tab.type == EditorTabType.settings) {
      chapterTitle = tab.title;
      volumeName = '';
      isSetting = true;
    } else {
      chapterTitle = tab.title;
      final chapter = provider.chapters.where((c) => c.uuid == tab.id).firstOrNull;
      volumeName = provider.getVolumeName(chapter?.volumeUuid ?? '');
      isSetting = false;
    }

    provider.openBackupPreviewTab(
      backupFilePath: record.filePath,
      chapterTitle: chapterTitle,
      formattedTime: record.formattedTime,
      bookUuid: book.uuid,
      volumeName: volumeName,
      isPreview: !isDoubleTap,
      originalIsSetting: isSetting,
    );

    // 双击时固定已打开的预览标签页
    if (isDoubleTap) {
      final currentTab = provider.currentTab;
      if (currentTab != null && currentTab.isPreview) {
        provider.pinTab(currentTab.id);
      }
    }
  }

  /// 删除指定备份记录
  Future<void> _deleteBackup(BackupRecord record) async {
    showConfirmDialog(
      context: context,
      title: '删除备份',
      description: '确定要删除 ${record.formattedTime} 的备份吗？此操作不可撤销。',
      type: ConfirmType.delete,
      confirmText: '删除',
      cancelText: '取消',
      onConfirm: () async {
        final success = await BackupService.instance.deleteBackup(record.filePath);
        if (success && mounted) {
          _loadBackups();
        }
      },
    );
  }

  /// 恢复指定备份记录
  Future<void> _restoreBackup(BackupRecord record) async {
    showConfirmDialog(
      context: context,
      title: '恢复历史版本',
      description: '将使用 ${record.formattedTime} 的备份内容替换当前内容，当前未保存的修改将丢失。确定要恢复吗？',
      type: ConfirmType.warning,
      confirmText: '恢复',
      cancelText: '取消',
      onConfirm: () async {
        final content = await BackupService.instance.readBackupContent(record.filePath);
        if (content != null && mounted) {
          final provider = context.read<WorkspaceProvider>();
          final tab = provider.currentTab;

          if (tab != null && tab.type == EditorTabType.backupPreview) {
            // 备份预览标签页：找到原始标签页并恢复内容
            provider.restoreBackupToChapter(content, tab.originalChapterTitle ?? tab.title);
          } else {
            // 章节或大纲标签页：直接恢复到当前标签页
            provider.restoreFromBackup(content);
          }
        }
      },
    );
  }
}
