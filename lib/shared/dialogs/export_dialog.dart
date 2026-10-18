import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/services/book_export_service.dart';
import 'package:quick_write/core/services/export_saver_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 导出模式
enum ExportMode {
  /// 导出书籍
  book,

  /// 导出分卷
  volume,

  /// 导出章节
  chapter,

  /// 导出设定分组
  settingGroup,

  /// 导出设定项
  setting,
}

/// 显示导出对话框
///
/// [context] 上下文
/// [books] 要导出的书籍列表（单本或批量）
/// [mode] 导出模式（书籍/分卷/章节/设定分组/设定项）
/// [volumeName] 分卷名称（分卷导出时使用）
/// [volumeUuid] 分卷 UUID（分卷导出时使用）
/// [chapters] 章节列表（章节/分卷导出时使用）
/// [bookTitle] 书籍标题（分卷/章节/设定导出时使用，用于定位数据文件夹）
/// [groupName] 分组名称（设定分组导出时使用）
/// [settingItems] 设定项列表（设定分组/设定项导出时使用）
Future<void> showExportDialog({
  required BuildContext context,
  List<BookModel>? books,
  ExportMode mode = ExportMode.book,
  String? volumeName,
  String? volumeUuid,
  List<ChapterModel>? chapters,
  String? bookTitle,
  String? groupName,
  List<SettingItemModel>? settingItems,
}) {
  // 创建对话框交互状态控制器（导出时禁用拖拽和关闭）
  final interactiveNotifier = ValueNotifier<bool>(true);

  return showDialogBase(
    context: context,
    title: '', // 不使用默认标题栏
    width: 440,
    height: 680,
    adaptiveHeight: true,
    anchorTop: false,
    showCloseButton: false,
    dialogInteractiveNotifier: interactiveNotifier,
    content: _ExportDialogContent(
      books: books,
      mode: mode,
      volumeName: volumeName,
      volumeUuid: volumeUuid,
      chapters: chapters,
      bookTitle: bookTitle,
      groupName: groupName,
      settingItems: settingItems,
      interactiveNotifier: interactiveNotifier,
    ),
  );
}

/// 导出对话框内容
class _ExportDialogContent extends StatefulWidget {
  /// 要导出的书籍列表（书籍导出模式）
  final List<BookModel>? books;

  /// 导出模式
  final ExportMode mode;

  /// 分卷名称（分卷导出模式）
  final String? volumeName;

  /// 分卷 UUID（分卷导出模式）
  final String? volumeUuid;

  /// 章节列表（分卷/章节导出模式）
  final List<ChapterModel>? chapters;

  /// 书籍标题（分卷/章节/设定导出模式，用于定位数据文件夹）
  final String? bookTitle;

  /// 分组名称（设定分组导出模式）
  final String? groupName;

  /// 设定项列表（设定分组/设定项导出模式）
  final List<SettingItemModel>? settingItems;

  /// 对话框交互状态控制器
  final ValueNotifier<bool> interactiveNotifier;

  const _ExportDialogContent({
    this.books,
    required this.mode,
    this.volumeName,
    this.volumeUuid,
    this.chapters,
    this.bookTitle,
    this.groupName,
    this.settingItems,
    required this.interactiveNotifier,
  });

  @override
  State<_ExportDialogContent> createState() => _ExportDialogContentState();
}

class _ExportDialogContentState extends State<_ExportDialogContent> {
  // 是否合并为一个文件导出
  bool _mergeIntoOneFile = false;
  // 导出格式：0 = txt, 1 = docx
  int _formatIndex = 0;
  // 导出目录
  String? _exportDir;
  // 移动端导出中转目录（导出内容先落盘于此，最终经系统保存框写入公共存储）
  Directory? _stagingDirectory;
  // 是否正在导出
  bool _isExporting = false;
  // 导出进度
  double _progress = 0;
  // 当前状态文字
  String _statusText = '';
  // 错误信息
  String? _errorMessage;

  /// 当前选中的导出格式
  ExportFormat get _exportFormat => _formatIndex == 0 ? ExportFormat.txt : ExportFormat.docx;

  /// 是否为单章导出（不显示导出方式选项）
  bool get _isSingleChapter => widget.mode == ExportMode.chapter && (widget.chapters?.length ?? 0) == 1;

  /// 是否为单个设定项导出（不显示导出方式选项）
  bool get _isSingleSetting => widget.mode == ExportMode.setting && (widget.settingItems?.length ?? 0) == 1;

  /// 是否为单条导出（不显示导出方式选项）
  bool get _isSingleItem => _isSingleChapter || _isSingleSetting;

  /// 是否为移动端
  bool get _isMobile => PlatformCapabilities.isMobile;

  /// 移动端保存时使用的默认文件名（不含扩展名）
  ///
  /// 仅在导出内容被打包为 zip 时用于命名
  String get _mobileSaveBaseName {
    switch (widget.mode) {
      case ExportMode.book:
        final books = widget.books!;
        return books.length == 1 ? books.first.title : '书籍导出';
      case ExportMode.volume:
        return widget.volumeName ?? '分卷导出';
      case ExportMode.chapter:
        final chapters = widget.chapters!;
        return chapters.length == 1 ? chapters.first.title : (widget.bookTitle ?? '章节导出');
      case ExportMode.settingGroup:
        return widget.groupName ?? '设定导出';
      case ExportMode.setting:
        final items = widget.settingItems!;
        return items.length == 1 ? items.first.title : (widget.bookTitle ?? '设定导出');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 选择导出目录
  Future<void> _pickExportDir() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择导出目录');
      if (result != null && mounted) {
        setState(() {
          _exportDir = result;
          _errorMessage = null;
        });
      }
    } catch (e) {
      // 选择目录失败，忽略
    }
  }

  /// 开始导出
  Future<void> _startExport() async {
    if (_isMobile) {
      // 移动端：导出内容先落到应用私有的中转目录，稍后由系统保存框选定公共位置
      try {
        _stagingDirectory = await ExportSaverService.instance.createStagingDirectory();
      } catch (e) {
        setState(() => _errorMessage = '导出失败: $e');
        return;
      }
      _exportDir = _stagingDirectory!.path;
    } else if (_exportDir == null) {
      setState(() => _errorMessage = '请选择导出目录');
      return;
    }

    // 禁用对话框交互
    widget.interactiveNotifier.value = false;

    setState(() {
      _isExporting = true;
      _progress = 0;
      _statusText = '正在准备导出...';
      _errorMessage = null;
    });

    final exportService = BookExportService.instance;

    try {
      final _ExportSummary summary;
      if (widget.mode == ExportMode.book) {
        // 书籍导出
        summary = await _exportBooks(exportService);
      } else if (widget.mode == ExportMode.settingGroup || widget.mode == ExportMode.setting) {
        // 设定分组/设定项导出
        summary = await _exportSettings(exportService);
      } else {
        // 分卷/章节导出
        summary = await _exportChapters(exportService);
      }

      if (!mounted) return;

      // 移动端：有成功导出的内容时，通过系统保存框写入公共存储
      if (_isMobile && summary.successCount > 0) {
        setState(() => _statusText = '正在保存...');
        final savedPath = await ExportSaverService.instance.saveToPublicStorage(
          stagingDirectory: _stagingDirectory!,
          preferredName: _mobileSaveBaseName,
        );

        if (!mounted) return;

        if (savedPath == null) {
          // 用户在系统保存框取消，保持对话框打开并提示
          setState(() {
            _isExporting = false;
            _errorMessage = '已取消保存';
          });
          widget.interactiveNotifier.value = true;
          return;
        }
      }

      _finishExport(summary);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _errorMessage = '导出失败: $e';
      });
      widget.interactiveNotifier.value = true;
    } finally {
      // 清理移动端中转目录
      if (_isMobile && _stagingDirectory != null) {
        try {
          await ExportSaverService.instance.disposeStagingDirectory(_stagingDirectory!);
        } catch (_) {
          // 中转目录清理失败不影响导出结果
        }
        _stagingDirectory = null;
      }
    }
  }

  /// 导出书籍
  Future<_ExportSummary> _exportBooks(BookExportService exportService) async {
    final isar = context.read<BookshelfProvider>().isar;
    int successCount = 0;
    int failCount = 0;
    String? lastError;

    for (int i = 0; i < widget.books!.length; i++) {
      final book = widget.books![i];

      setState(() {
        _statusText = '正在导出: ${book.title}';
        _progress = i / widget.books!.length;
      });

      final result = await exportService.exportBook(
        book: book,
        exportDir: _exportDir!,
        format: _exportFormat,
        mergeIntoOneFile: _mergeIntoOneFile,
        isar: isar,
        onProgress: (current, total, status) {
          if (mounted) {
            setState(() {
              _progress = (i + current / total) / widget.books!.length;
              _statusText = status;
            });
          }
        },
      );

      if (result.success) {
        successCount++;
      } else {
        failCount++;
        lastError = result.errorMessage;
      }
    }

    return _ExportSummary(
      successCount: successCount,
      failCount: failCount,
      lastError: lastError,
      unit: '${widget.books!.length} 本书籍',
    );
  }

  /// 导出分卷/章节
  Future<_ExportSummary> _exportChapters(BookExportService exportService) async {
    final chapters = widget.chapters!;
    final bookTitle = widget.bookTitle!;

    setState(() {
      _statusText = '正在准备导出...';
      _progress = 0;
    });

    final result = await exportService.exportChapters(
      chapters: chapters,
      bookTitle: bookTitle,
      volumeName: widget.volumeName,
      exportDir: _exportDir!,
      format: _exportFormat,
      mergeIntoOneFile: _isSingleChapter ? true : _mergeIntoOneFile,
      isar: context.read<BookshelfProvider>().isar,
      onProgress: (current, total, status) {
        if (mounted) {
          setState(() {
            _progress = current / total;
            _statusText = status;
          });
        }
      },
    );

    return _ExportSummary(
      successCount: result.success ? 1 : 0,
      failCount: result.success ? 0 : 1,
      lastError: result.errorMessage,
      unit: _isSingleChapter ? '章节' : '分卷',
    );
  }

  /// 导出设定分组/设定项
  Future<_ExportSummary> _exportSettings(BookExportService exportService) async {
    final settingItems = widget.settingItems!;
    final bookTitle = widget.bookTitle!;

    setState(() {
      _statusText = '正在准备导出...';
      _progress = 0;
    });

    final result = await exportService.exportSettings(
      settingItems: settingItems,
      bookTitle: bookTitle,
      groupName: widget.groupName,
      exportDir: _exportDir!,
      format: _exportFormat,
      mergeIntoOneFile: _isSingleSetting ? true : _mergeIntoOneFile,
      isar: context.read<BookshelfProvider>().isar,
      onProgress: (current, total, status) {
        if (mounted) {
          setState(() {
            _progress = current / total;
            _statusText = status;
          });
        }
      },
    );

    return _ExportSummary(
      successCount: result.success ? 1 : 0,
      failCount: result.success ? 0 : 1,
      lastError: result.errorMessage,
      unit: _isSingleSetting ? '设定项' : '分组',
    );
  }

  /// 完成导出，更新 UI 状态
  void _finishExport(_ExportSummary summary) {
    setState(() {
      _isExporting = false;
      _progress = 1.0;
    });

    // 恢复对话框交互
    widget.interactiveNotifier.value = true;

    if (summary.failCount == 0) {
      Navigator.of(context).pop();
      SnackBarService.show(context, '导出完成');
    } else if (summary.successCount == 0) {
      setState(() {
        _errorMessage = summary.lastError ?? '导出失败';
      });
    } else {
      Navigator.of(context).pop();
      SnackBarService.show(
        context,
        '导出完成：成功 ${summary.successCount} ${summary.unit}，失败 ${summary.failCount} ${summary.unit}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isExporting,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 自定义标题栏
            _buildTitleBar(colorScheme),
            // 内容区域
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 导出信息
                  _buildInfoSection(colorScheme),
                  const SizedBox(height: 20),
                  // 导出格式选择
                  _buildFormatSelector(colorScheme),
                  // 导出方式选项（单条导出时不显示）
                  if (!_isSingleItem) ...[const SizedBox(height: 20), _buildMergeOption(colorScheme)],
                  // 导出目录选择（移动端经系统保存框选定位置，无需预先选择）
                  if (!_isMobile) ...[const SizedBox(height: 20), _buildDirSelector(colorScheme)],
                  // 进度条
                  if (_isExporting || _progress > 0) ...[
                    const SizedBox(height: 20),
                    _buildProgressSection(colorScheme),
                  ],
                  // 错误信息
                  if (_errorMessage != null) ...[const SizedBox(height: 12), _buildErrorBox(colorScheme)],
                  const SizedBox(height: 20),
                  // 底部按钮
                  _buildButtonRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建标题栏
  Widget _buildTitleBar(ColorScheme colorScheme) {
    final title = switch (widget.mode) {
      ExportMode.book => '导出书籍',
      ExportMode.volume => '导出分卷',
      ExportMode.chapter => '导出章节',
      ExportMode.settingGroup => '导出分组',
      ExportMode.setting => _isSingleSetting ? '导出设定项' : '导出设定项',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 20,
              color: _isExporting ? colorScheme.onSurface.withValues(alpha: 0.3) : null,
            ),
            onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: colorScheme.onSurfaceVariant,
            hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
            highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
          ),
        ],
      ),
    );
  }

  /// 构建导出信息区域
  Widget _buildInfoSection(ColorScheme colorScheme) {
    final icon = switch (widget.mode) {
      ExportMode.book => Icons.menu_book_outlined,
      ExportMode.volume => Icons.folder_outlined,
      ExportMode.chapter => Icons.description_outlined,
      ExportMode.settingGroup => Icons.folder_outlined,
      ExportMode.setting => Icons.description_outlined,
    };

    String label;
    if (widget.mode == ExportMode.book) {
      final bookCount = widget.books!.length;
      label = bookCount == 1 ? '「${widget.books!.first.title}」' : '已选择 $bookCount 本书籍';
    } else if (widget.mode == ExportMode.volume) {
      label = '「${widget.volumeName}」';
    } else if (widget.mode == ExportMode.settingGroup) {
      label = '「${widget.groupName}」';
    } else if (widget.mode == ExportMode.setting) {
      final settingCount = widget.settingItems!.length;
      label = settingCount == 1 ? '「${widget.settingItems!.first.title}」' : '已选择 $settingCount 个设定项';
    } else {
      final chapterCount = widget.chapters!.length;
      label = chapterCount == 1 ? '「${widget.chapters!.first.title}」' : '已选择 $chapterCount 个章节';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: context.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建导出格式选择
  Widget _buildFormatSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('导出格式', style: context.titleSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        Row(
          children: [
            // TXT 选项
            Expanded(
              child: _buildFormatOption(
                colorScheme: colorScheme,
                icon: Icons.description_outlined,
                label: 'TXT',
                description: '纯文本格式',
                isSelected: _formatIndex == 0,
                onTap: () => setState(() => _formatIndex = 0),
              ),
            ),
            const SizedBox(width: 12),
            // DOCX 选项
            Expanded(
              child: _buildFormatOption(
                colorScheme: colorScheme,
                icon: Icons.article_outlined,
                label: 'DOCX',
                description: '文档格式',
                isSelected: _formatIndex == 1,
                onTap: () => setState(() => _formatIndex = 1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建单个格式选项
  Widget _buildFormatOption({
    required ColorScheme colorScheme,
    required IconData icon,
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback? onTap,
    bool disabled = false,
  }) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorScheme.primary.withValues(alpha: 0.5) : colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: disabled
                  ? colorScheme.onSurface.withValues(alpha: 0.3)
                  : isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: disabled
                        ? colorScheme.onSurface.withValues(alpha: 0.3)
                        : isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
                Text(
                  description,
                  style: context.bodySmall?.copyWith(
                    color: disabled
                        ? colorScheme.onSurface.withValues(alpha: 0.2)
                        : colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建导出方式选项
  Widget _buildMergeOption(ColorScheme colorScheme) {
    // 根据导出模式调整描述文字
    final String structureDesc;
    final String mergeDesc;
    if (widget.mode == ExportMode.settingGroup) {
      structureDesc = '按分组名建文件夹，每个设定项一个文件';
      mergeDesc = '将所有设定项合并为一个文件';
    } else if (widget.mode == ExportMode.setting) {
      structureDesc = '按分组名建文件夹，每个设定项一个文件';
      mergeDesc = '将所有设定项合并为一个文件';
    } else if (widget.mode == ExportMode.volume) {
      structureDesc = '按分卷名建文件夹，每章一个文件';
      mergeDesc = '将所有章节合并为一个文件';
    } else {
      structureDesc = '按书名建文件夹，分卷建子文件夹，每章一个文件';
      mergeDesc = '将所有章节合并为一个文件';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('导出方式', style: context.titleSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        InkWell(
          onTap: _isExporting ? null : () => setState(() => _mergeIntoOneFile = false),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: !_mergeIntoOneFile
                  ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: !_mergeIntoOneFile
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: !_mergeIntoOneFile,
                  onChanged: _isExporting ? null : (v) => setState(() => _mergeIntoOneFile = !(v ?? false)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('按目录结构导出', style: context.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        structureDesc,
                        style: context.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _isExporting ? null : () => setState(() => _mergeIntoOneFile = true),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _mergeIntoOneFile
                  ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _mergeIntoOneFile
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _mergeIntoOneFile,
                  onChanged: _isExporting ? null : (v) => setState(() => _mergeIntoOneFile = v ?? true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('合并为一个文件导出', style: context.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        mergeDesc,
                        style: context.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建导出目录选择
  Widget _buildDirSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('导出目录', style: context.titleSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        InkWell(
          onTap: _isExporting ? null : _pickExportDir,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _exportDir != null
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _exportDir != null ? Icons.folder : Icons.folder_outlined,
                  size: 22,
                  color: _exportDir != null ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _exportDir ?? '点击选择导出目录',
                    style: context.bodyLarge?.copyWith(
                      color: _exportDir != null ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建进度条
  Widget _buildProgressSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: _progress < 1.0
                    ? CircularProgressIndicator(strokeWidth: 2, value: _progress, color: colorScheme.primary)
                    : Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_statusText, style: context.bodyMedium?.copyWith(color: colorScheme.onSurface)),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: context.titleSmall?.copyWith(fontWeight: FontWeight.w500, color: colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 5,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建错误提示框
  Widget _buildErrorBox(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!, style: context.titleSmall?.copyWith(color: colorScheme.error)),
          ),
        ],
      ),
    );
  }

  /// 构建底部按钮
  Widget _buildButtonRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          width: 80,
          height: 36,
          child: TextButton(
            onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          height: 36,
          child: FilledButton(
            onPressed: _isExporting || (!_isMobile && _exportDir == null) ? null : _startExport,
            child: _isExporting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('导出'),
          ),
        ),
      ],
    );
  }
}

/// 单次导出结果汇总
///
/// 汇总各导出分支的成功/失败数量与单位，供统一收尾处理
class _ExportSummary {
  /// 成功数量
  final int successCount;

  /// 失败数量
  final int failCount;

  /// 最后一次失败的错误信息
  final String? lastError;

  /// 数量单位（书籍/分卷/章节/分组/设定项）
  final String unit;

  const _ExportSummary({required this.successCount, required this.failCount, required this.unit, this.lastError});
}
