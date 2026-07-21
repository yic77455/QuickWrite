import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';

/// 显示新建作品弹窗
Future<void> showNewBookDialog(BuildContext context) {
  return showDialogBase(
    context: context,
    title: '新建作品',
    width: 560,
    height: 360,
    content: const _NewBookDialogContent(),
  );
}

/// 显示修改作品信息弹窗
Future<void> showEditBookDialog(BuildContext context, BookModel book) {
  return showDialogBase(
    context: context,
    title: '修改信息',
    width: 560,
    height: 360,
    content: _NewBookDialogContent(book: book),
  );
}

/// 新建/编辑作品对话框内容
class _NewBookDialogContent extends StatefulWidget {
  /// 编辑模式时传入的作品数据
  final BookModel? book;

  const _NewBookDialogContent({this.book});

  @override
  State<_NewBookDialogContent> createState() => _NewBookDialogContentState();
}

class _NewBookDialogContentState extends State<_NewBookDialogContent> {
  // 书名控制器
  late final TextEditingController _titleController;
  // 简介控制器
  late final TextEditingController _synopsisController;
  // 书名焦点节点
  final _titleFocusNode = FocusNode();
  // 简介焦点节点
  final _synopsisFocusNode = FocusNode();
  // 选中的封面路径
  String? _coverPath;
  // 错误信息
  String? _errorMessage;
  // 是否正在加载
  bool _isLoading = false;
  // 是否为编辑模式
  bool get _isEditMode => widget.book != null;
  // 原始封面路径（编辑模式下用于判断是否更换了封面）
  String _originalCoverPath = '';

  @override
  void initState() {
    super.initState();
    // 编辑模式：预填充数据
    if (_isEditMode) {
      _titleController = TextEditingController(text: widget.book!.title);
      _synopsisController = TextEditingController(text: widget.book!.synopsis);
      _coverPath = widget.book!.coverPath.isNotEmpty ? widget.book!.coverPath : null;
      _originalCoverPath = widget.book!.coverPath;
    } else {
      _titleController = TextEditingController();
      _synopsisController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _synopsisController.dispose();
    _titleFocusNode.dispose();
    _synopsisFocusNode.dispose();
    super.dispose();
  }

  /// 选择封面图片
  Future<void> _pickCoverImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null && mounted) {
        setState(() {
          _coverPath = result.files.single.path;
        });
      }
    } catch (e) {
      // 选择图片失败，忽略错误
    }
  }

  /// 创建作品目录结构
  Future<String> _createBookDirectory(String bookTitle) async {
    final worksPath = await AppPaths.instance.getBooksPath();
    final bookFolderPath = '$worksPath${Platform.pathSeparator}$bookTitle';

    final bookDirectory = Directory(bookFolderPath);
    if (!bookDirectory.existsSync()) {
      bookDirectory.createSync(recursive: true);
      // 创建 chapters 文件夹用于存放章节文件
      Directory('$bookFolderPath${Platform.pathSeparator}chapters').createSync();
    }

    return bookFolderPath;
  }

  /// 复制封面到作品目录
  /// 
  /// 将选中的封面图片复制到作品目录下，命名为 cover.扩展名（保留原格式）
  Future<String?> _copyCoverToBookDirectory(String bookFolderPath) async {
    if (_coverPath == null || _coverPath!.isEmpty) {
      return null;
    }

    // 如果封面路径已经是作品目录下的文件，直接返回
    if (_coverPath!.startsWith(bookFolderPath)) {
      return _coverPath;
    }

    try {
      final sourceFile = File(_coverPath!);
      if (!sourceFile.existsSync()) {
        return null;
      }

      // 获取原文件扩展名，保留原格式
      final extension = _coverPath!.split('.').last.toLowerCase();
      final coverExtension = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains('.$extension') 
          ? '.$extension' 
          : '.png';
      
      // 封面命名为 cover.扩展名
      final coverPath = '$bookFolderPath${Platform.pathSeparator}cover$coverExtension';
      await sourceFile.copy(coverPath);
      return coverPath;
    } catch (e) {
      // 复制失败，返回 null
      return null;
    }
  }

  /// 处理创建作品
  Future<void> _handleCreate() async {
    final title = _titleController.text.trim();

    // 书名必填校验
    if (title.isEmpty) {
      setState(() => _errorMessage = '请输入书名');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 在 async gap 之前获取 Provider 引用
    final bookshelfProvider = context.read<BookshelfProvider>();
    final synopsis = _synopsisController.text.trim();

    try {
      // 1. 创建作品目录结构
      final bookFolderPath = await _createBookDirectory(title);

      // 2. 复制封面到作品目录（如果有选择封面）
      final coverPath = await _copyCoverToBookDirectory(bookFolderPath);

      // 3. 调用 Provider 创建作品（只操作数据库）
      final result = await bookshelfProvider.addBook(
        bookTitle: title,
        coverPath: coverPath ?? '',
        synopsis: synopsis,
      );

      if (mounted) {
        if (result == 1) {
          // 书名已存在，删除刚创建的目录
          Directory(bookFolderPath).deleteSync(recursive: true);
          setState(() {
            _errorMessage = '书名已存在';
            _isLoading = false;
          });
        } else {
          // 创建成功，关闭弹窗并显示提示
          Navigator.of(context).pop();
          SnackBarService.show(context, '作品创建成功');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '创建失败，请重试';
          _isLoading = false;
        });
      }
    }
  }

  /// 处理更新作品信息
  Future<void> _handleUpdate() async {
    final title = _titleController.text.trim();

    // 书名必填校验
    if (title.isEmpty) {
      setState(() => _errorMessage = '请输入书名');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 在 async gap 之前获取 Provider 引用
    final bookshelfProvider = context.read<BookshelfProvider>();
    final synopsis = _synopsisController.text.trim();
    final oldTitle = widget.book!.title;
    final worksPath = await AppPaths.instance.getBooksPath();

    try {
      String finalCoverPath = _originalCoverPath;
      bool coverChanged = _coverPath != null && _coverPath != _originalCoverPath;
      bool coverCleared = _coverPath == null && _originalCoverPath.isNotEmpty;
      bool titleChanged = title != oldTitle;

      // 1. 如果书名变化，先重命名文件夹
      if (titleChanged) {
        final oldPath = '$worksPath${Platform.pathSeparator}$oldTitle';
        final newPath = '$worksPath${Platform.pathSeparator}$title';
        
        final oldDir = Directory(oldPath);
        if (oldDir.existsSync()) {
          // 检查新路径是否已存在
          final newDir = Directory(newPath);
          if (newDir.existsSync()) {
            if (mounted) {
              setState(() {
                _errorMessage = '书名已存在';
                _isLoading = false;
              });
            }
            return;
          }
          // 重命名文件夹
          await oldDir.rename(newPath);
          // 更新封面路径（如果封面没变，需要更新路径中的书名部分）
          if (!coverChanged && !coverCleared && _originalCoverPath.isNotEmpty) {
            final coverFileName = _originalCoverPath.split(Platform.pathSeparator).last;
            finalCoverPath = '$newPath${Platform.pathSeparator}$coverFileName';
          }
        }
      }

      // 2. 处理封面变化
      if (coverChanged) {
        // 封面有变化，需要删除旧封面并复制新封面
        final bookFolderPath = '$worksPath${Platform.pathSeparator}$title';
        
        // 删除旧封面文件
        if (_originalCoverPath.isNotEmpty) {
          final oldCoverFile = File(_originalCoverPath);
          if (oldCoverFile.existsSync()) {
            oldCoverFile.deleteSync();
          }
        }
        
        // 复制新封面
        finalCoverPath = await _copyCoverToBookDirectory(bookFolderPath) ?? '';
      } else if (coverCleared) {
        // 封面被清空，删除旧封面文件
        if (_originalCoverPath.isNotEmpty) {
          final oldCoverFile = File(_originalCoverPath);
          if (oldCoverFile.existsSync()) {
            oldCoverFile.deleteSync();
          }
        }
        finalCoverPath = '';
      }

      // 3. 更新数据库
      await bookshelfProvider.updateBookInfo(
        bookUuid: widget.book!.uuid,
        title: title,
        synopsis: synopsis,
        coverPath: finalCoverPath,
      );

      if (mounted) {
        Navigator.of(context).pop();
        SnackBarService.show(context, '修改成功');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '修改失败，请重试';
          _isLoading = false;
        });
      }
    }
  }

  /// 处理提交（根据模式调用不同方法）
  void _handleSubmit() {
    if (_isEditMode) {
      _handleUpdate();
    } else {
      _handleCreate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 主内容区域：左侧封面 + 右侧输入框
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧：封面选择区域
                _buildCoverSection(colorScheme),
                const SizedBox(width: 20),
                // 右侧：书名和简介输入区域
                Expanded(
                  child: _buildInputSection(colorScheme),
                ),
              ],
            ),
          ),
          // 底部按钮区域
          const SizedBox(height: 16),
          _buildButtonRow(),
        ],
      ),
    );
  }

  /// 构建封面选择区域
  Widget _buildCoverSection(ColorScheme colorScheme) {
    return Column(
      children: [
        // 封面预览框 - 使用 Expanded 让高度自适应
        Expanded(
          child: Container(
            width: 140,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            // 根据是否选择了封面显示不同内容
            child: _buildCoverImage(colorScheme),
          ),
        ),
        const SizedBox(height: 12),
        // 选择封面按钮
        SizedBox(
          width: 140,
          height: 36,
          child: OutlinedButton.icon(
            onPressed: _pickCoverImage,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('选择封面'),
          ),
        ),
      ],
    );
  }

  /// 构建封面图片
  Widget _buildCoverImage(ColorScheme colorScheme) {
    if (_coverPath == null || _coverPath!.isEmpty) {
      return Center(
        child: Icon(
          Icons.image_outlined,
          size: 48,
          color: colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      );
    }

    // 判断是本地文件还是网络图片
    final file = File(_coverPath!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: file.existsSync()
          ? Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // 图片加载失败时显示占位图标
                return Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: colorScheme.onSurface.withValues(alpha: 0.3),
                );
              },
            )
          : Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
    );
  }

  /// 构建输入区域（书名 + 简介）
  Widget _buildInputSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 书名输入框（必填）
        // 用 ImeCursorFixerWrapper 包裹 TextField，修复中文输入法光标跟随问题
        ImeCursorFixerWrapper(
          controller: _titleController,
          focusNode: _titleFocusNode,
          child: TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '书名',
              hintText: '请输入书名',
              errorText: _errorMessage,
              suffix: Text(
                '*',
                style: context.titleLarge?.copyWith(color: colorScheme.error),
              ),
            ),
            onChanged: (_) {
              // 输入时清除错误信息
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
            onSubmitted: (_) => _handleSubmit(),
          ),
        ),
        const SizedBox(height: 16),
        // 简介输入框（非必填，多行）
        // 用 ImeCursorFixerWrapper 包裹 TextField，修复中文输入法光标跟随问题
        Expanded(
          child: ImeCursorFixerWrapper(
            controller: _synopsisController,
            focusNode: _synopsisFocusNode,
            child: TextField(
              controller: _synopsisController,
              focusNode: _synopsisFocusNode,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: '简介',
                hintText: '请输入作品简介（选填）',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建底部按钮行
  Widget _buildButtonRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 取消按钮
        SizedBox(
          width: 80,
          height: 36,
          child: TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        // 创建/保存按钮
        SizedBox(
          width: 80,
          height: 36,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleSubmit,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditMode ? '保存' : '创建'),
          ),
        ),
      ],
    );
  }
}
