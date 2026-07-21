import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/services/book_import_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示导入书籍对话框
Future<void> showImportBookDialog(BuildContext context) {
  // 创建对话框交互状态控制器（导入时禁用拖拽和关闭）
  final interactiveNotifier = ValueNotifier<bool>(true);

  return showDialogBase(
    context: context,
    title: '', // 不使用默认标题栏
    width: 480,
    height: 500, // 最大高度
    adaptiveHeight: true, // 自适应高度
    anchorTop: true, // 高度变化时保持顶部位置
    showCloseButton: false, // 不显示默认关闭按钮
    dialogInteractiveNotifier: interactiveNotifier, // 动态控制对话框交互状态
    content: _ImportBookDialogContent(
      interactiveNotifier: interactiveNotifier,
    ),
  );
}

/// 导入书籍对话框内容
class _ImportBookDialogContent extends StatefulWidget {
  final ValueNotifier<bool> interactiveNotifier;

  const _ImportBookDialogContent({
    required this.interactiveNotifier,
  });

  @override
  State<_ImportBookDialogContent> createState() =>
      _ImportBookDialogContentState();
}

class _ImportBookDialogContentState extends State<_ImportBookDialogContent> {
  // 当前页面索引（0: 文件导入, 1: 文件夹导入）
  int _currentPageIndex = 0;

  // 文件导入相关状态
  String? _selectedFilePath;
  late final TextEditingController _fileTitleController;
  final FocusNode _fileTitleFocusNode = FocusNode();

  // 文件夹导入相关状态
  String? _selectedFolderPath;
  late final TextEditingController _folderTitleController;
  final FocusNode _folderTitleFocusNode = FocusNode();

  // 通用状态
  bool _isImporting = false;
  int _progress = 0;
  String _statusText = '';
  String? _errorMessage;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _fileTitleController = TextEditingController();
    _folderTitleController = TextEditingController();
  }

  @override
  void dispose() {
    _fileTitleController.dispose();
    _folderTitleController.dispose();
    _fileTitleFocusNode.dispose();
    _folderTitleFocusNode.dispose();
    super.dispose();
  }

  /// 切换页面
  void _onTabPressed(int index) {
    if (_currentPageIndex == index || _isImporting) return;
    setState(() {
      _currentPageIndex = index;
    });
  }

  /// 选择文件
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'docx'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null && mounted) {
        final filePath = result.files.single.path!;
        final fileName = filePath.split(Platform.pathSeparator).last;

        setState(() {
          _selectedFilePath = filePath;
          _fileTitleController.text =
              fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
          _errorMessage = null;
          _titleError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '选择文件失败: $e';
        });
      }
    }
  }

  /// 选择文件夹
  Future<void> _pickFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();

      if (result != null && mounted) {
        final folderName = result.split(Platform.pathSeparator).last;

        setState(() {
          _selectedFolderPath = result;
          _folderTitleController.text = folderName;
          _errorMessage = null;
          _titleError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '选择文件夹失败: $e';
        });
      }
    }
  }

  /// 开始导入
  Future<void> _startImport() async {
    // 根据当前页面获取对应的状态
    final (selectedPath, controller) = _currentPageIndex == 0
        ? (_selectedFilePath, _fileTitleController)
        : (_selectedFolderPath, _folderTitleController);

    if (selectedPath == null) {
      setState(() => _errorMessage = _currentPageIndex == 0 ? '请先选择文件' : '请先选择文件夹');
      return;
    }

    final title = controller.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请输入书名');
      return;
    }

    final bookshelfProvider = context.read<BookshelfProvider>();
    if (bookshelfProvider.books.any((book) => book.title == title)) {
      setState(() => _titleError = '书名已存在，请使用其他名称');
      return;
    }

    await _performImport(() async {
      if (_currentPageIndex == 0) {
        return await BookImportService.instance.importBook(
          filePath: selectedPath,
          bookTitle: title,
          onProgress: _updateProgress,
        );
      } else {
        return await BookImportService.instance.importFromFolder(
          folderPath: selectedPath,
          bookTitle: title,
          onProgress: _updateProgress,
        );
      }
    });
  }

  /// 更新进度
  void _updateProgress(int current, int total, String status) {
    // 检查组件是否仍然挂载，防止在组件销毁后调用setState()
    if (mounted) {
      setState(() {
        _progress = (current / total * 90).toInt();
        _statusText = status;
      });
    }
  }

  /// 执行导入
  Future<void> _performImport(
      Future<ImportResult> Function() importFunction) async {
    widget.interactiveNotifier.value = false;

    setState(() {
      _isImporting = true;
      _progress = 0;
      _statusText = '准备导入...';
      _errorMessage = null;
      _titleError = null;
    });

    final result = await importFunction();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _progress = 90;
        _statusText = '正在写入数据库...';
      });

      final bookshelfProvider = context.read<BookshelfProvider>();
      await bookshelfProvider.importBook(result);

      if (!mounted) return;

      setState(() {
        _progress = 100;
        _statusText = '导入完成';
      });

      Navigator.of(context).pop();

      SnackBarService.show(
        context,
        '导入成功：${result.bookTitle}\n'
        '${result.volumeCount} 个分卷，共 ${result.chapterCount} 章，'
        '${WordCountUtils.formatWordCount(result.totalWordCount)}',
      );
    } else {
      widget.interactiveNotifier.value = true;

      setState(() {
        _isImporting = false;
        _progress = 0;
        _errorMessage = result.errorMessage ?? '导入失败';
      });
    }
  }


  /// 清除当前页面的选择状态
  void _clearCurrentSelection() {
    setState(() {
      if (_currentPageIndex == 0) {
        _selectedFilePath = null;
        _fileTitleController.clear();
      } else {
        _selectedFolderPath = null;
        _folderTitleController.clear();
      }
      _progress = 0;
      _statusText = '';
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isImporting,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 自定义标题栏
            _buildTitleBar(colorScheme),

            // 分段选择器
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: SegmentedControl(
                labels: const ['文件导入', '文件夹导入'],
                selectedIndex: _currentPageIndex,
                onChanged: _isImporting ? null : _onTabPressed,
              ),
            ),

            // 内容区域
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: _buildImportPage(
                colorScheme: colorScheme,
                isFileMode: _currentPageIndex == 0,
                selectedPath: _currentPageIndex == 0 ? _selectedFilePath : _selectedFolderPath,
                controller: _currentPageIndex == 0 ? _fileTitleController : _folderTitleController,
                focusNode: _currentPageIndex == 0 ? _fileTitleFocusNode : _folderTitleFocusNode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建标题栏
  Widget _buildTitleBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '导入书籍',
              style: context.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 20,
              color: _isImporting
                  ? colorScheme.onSurface.withValues(alpha: 0.3)
                  : null,
            ),
            onPressed:
                _isImporting ? null : () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// 构建导入页面（统一处理文件和文件夹导入）
  Widget _buildImportPage({
    required ColorScheme colorScheme,
    required bool isFileMode,
    required String? selectedPath,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    final canImport = selectedPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPathSelector(
          colorScheme: colorScheme,
          isFileMode: isFileMode,
          selectedPath: selectedPath,
        ),
        const SizedBox(height: 20),
        _buildTitleInput(
          colorScheme: colorScheme,
          controller: controller,
          focusNode: focusNode,
        ),
        if (_shouldShowProgress(isFileMode)) ...[
          const SizedBox(height: 20),
          _buildProgressSection(colorScheme),
        ],
        if (_shouldShowError(isFileMode)) ...[
          const SizedBox(height: 12),
          _buildErrorBox(colorScheme),
        ],
        const SizedBox(height: 20),
        _buildButtonRow(canImport: canImport),
      ],
    );
  }

  /// 判断是否应该显示进度条
  bool _shouldShowProgress(bool isFileMode) {
    final isCurrentPage = (isFileMode && _currentPageIndex == 0) ||
        (!isFileMode && _currentPageIndex == 1);
    return (isCurrentPage && _isImporting) || _progress > 0;
  }

  /// 判断是否应该显示错误信息
  bool _shouldShowError(bool isFileMode) {
    final isCurrentPage = (isFileMode && _currentPageIndex == 0) ||
        (!isFileMode && _currentPageIndex == 1);
    return _errorMessage != null && isCurrentPage;
  }

  /// 构建路径选择区域（统一处理文件和文件夹）
  Widget _buildPathSelector({
    required ColorScheme colorScheme,
    required bool isFileMode,
    required String? selectedPath,
  }) {
    final label = isFileMode ? '选择文件' : '选择文件夹';
    final hint = isFileMode ? '点击选择 txt 或 docx 文件' : '点击选择书籍文件夹';
    final selectedIcon = isFileMode ? Icons.insert_drive_file : Icons.folder;
    final unselectedIcon = isFileMode ? Icons.upload_file_outlined : Icons.folder_outlined;
    final description = isFileMode
        ? '支持 txt 和 docx 格式，文件大小建议不超过 20MB'
        : '文件夹名称将作为书名，子目录作为分卷，txt/docx 文件作为章节';
    final onTap = isFileMode ? _pickFile : _pickFolder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.titleSmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _isImporting ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selectedPath != null
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selectedPath != null ? selectedIcon : unselectedIcon,
                  size: 24,
                  color: selectedPath != null
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedPath != null
                            ? selectedPath.split(Platform.pathSeparator).last
                            : hint,
                        style: context.bodyLarge?.copyWith(
                          color: selectedPath != null
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      if (selectedPath != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          selectedPath,
                          style: context.labelSmall?.copyWith(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (selectedPath != null && !_isImporting) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _clearCurrentSelection,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: context.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// 构建书名输入区域
  Widget _buildTitleInput({
    required ColorScheme colorScheme,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '书名',
          style: context.titleSmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        ImeCursorFixerWrapper(
          controller: controller,
          focusNode: focusNode,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !_isImporting,
            style: context.bodyLarge,
            decoration: InputDecoration(
              hintText: '请输入书名',
              errorText: _titleError,
            ),
            onChanged: (_) {
              if (_titleError != null) {
                setState(() => _titleError = null);
              }
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
          ),
        ),
      ],
    );
  }

  /// 构建进度显示区域
  Widget _buildProgressSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                child: _progress < 100
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _progress / 100,
                        color: colorScheme.primary,
                      )
                    : Icon(
                        Icons.check_circle,
                        size: 16,
                        color: colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _statusText,
                  style: context.bodyMedium?.copyWith(color: colorScheme.onSurface),
                ),
              ),
              Text(
                '$_progress%',
                style: context.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 6,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: context.titleSmall?.copyWith(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建底部按钮行
  Widget _buildButtonRow({required bool canImport}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          width: 80,
          height: 36,
          child: TextButton(
            onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          height: 36,
          child: FilledButton(
            onPressed: _isImporting || !canImport ? null : _startImport,
            child: _isImporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('导入'),
          ),
        ),
      ],
    );
  }
}
