import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/services/data_integrity_service.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示数据完整性校验结果对话框
///
/// [context] 构建上下文
/// [isar] 数据库实例
/// [result] 校验结果
Future<void> showIntegrityCheckDialog(
  BuildContext context,
  Isar isar,
  IntegrityCheckResult result,
) async {
  // 如果没有问题，不显示对话框
  if (result.missingFolderBooks.isEmpty &&
      result.missingFileChapters.isEmpty &&
      result.orphanChapters.isEmpty) {
    return;
  }

  await showDialogBase(
    context: context,
    title: '数据完整性校验',
    width: 480,
    height: 500,
    barrierDismissible: false,
    content: _IntegrityCheckDialogContent(
      isar: isar,
      result: result,
    ),
  );
}

/// 校验结果对话框内容
class _IntegrityCheckDialogContent extends StatefulWidget {
  final Isar isar;
  final IntegrityCheckResult result;

  const _IntegrityCheckDialogContent({
    required this.isar,
    required this.result,
  });

  @override
  State<_IntegrityCheckDialogContent> createState() =>
      _IntegrityCheckDialogContentState();
}

class _IntegrityCheckDialogContentState
    extends State<_IntegrityCheckDialogContent> {
  bool _isProcessing = false;
  String? _statusMessage;

  // 用户选择要移除的书籍
  final Set<String> _selectedBookUuids = {};

  @override
  void initState() {
    super.initState();
    // 默认全选丢失文件夹的书籍
    _selectedBookUuids
        .addAll(widget.result.missingFolderBooks.map((b) => b.uuid));
  }

  /// 执行清理操作
  Future<void> _performCleanup() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = '正在清理...';
    });

    try {
      // 1. 清理用户选择的丢失文件夹的书籍
      final booksToRemove = widget.result.missingFolderBooks
          .where((b) => _selectedBookUuids.contains(b.uuid))
          .toList();
      final chaptersRemovedWithBooks = await DataIntegrityService.instance
          .removeMissingFolderBooks(widget.isar, booksToRemove);

      // 2. 清理所有丢失文件的章节（自动处理）
      final allMissingChapters = <ChapterModel>[];
      for (final entry in widget.result.missingFileChapters.entries) {
        // 如果这本书的文件夹也被删除了，章节会随书籍一起删除，跳过
        if (!_selectedBookUuids.contains(entry.key)) {
          allMissingChapters.addAll(entry.value.map((e) => e.chapter));
        }
      }
      await DataIntegrityService.instance
          .removeMissingFileChapters(widget.isar, allMissingChapters);

      // 3. 清理孤儿章节（自动处理）
      await DataIntegrityService.instance
          .removeOrphanChapters(widget.isar, widget.result.orphanChapters);

      // 4. 刷新书架数据
      if (mounted) {
        final bookshelfProvider = context.read<BookshelfProvider>();
        await bookshelfProvider.refresh();
      }

      if (mounted) {
        setState(() {
          _statusMessage = '清理完成';
        });

        // 延迟关闭对话框
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop();

          // 构建分项提示信息
          final messages = <String>[];
          if (booksToRemove.isNotEmpty) {
            messages.add('已移除 ${booksToRemove.length} 本书籍');
            if (chaptersRemovedWithBooks > 0) {
              messages.add('  （同时清理 $chaptersRemovedWithBooks 个关联章节记录）');
            }
          }
          if (allMissingChapters.isNotEmpty) {
            messages.add('已移除 ${allMissingChapters.length} 个丢失文件的章节');
          }
          if (widget.result.orphanChapters.isNotEmpty) {
            messages.add('已移除 ${widget.result.orphanChapters.length} 个无主章节');
          }

          SnackBarService.show(context, '数据清理完成\n${messages.join('\n')}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '清理失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 说明文字
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '检测到数据库与本地文件存在不一致，可能是文件被手动删除或移动导致的。请确认处理方案：',
                    style: context.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 问题列表
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 丢失文件夹的书籍
                  if (widget.result.missingFolderBooks.isNotEmpty) ...[
                    _buildSectionHeader(
                      colorScheme,
                      Icons.folder_off_outlined,
                      '书籍文件夹丢失',
                      '${widget.result.missingFolderBooks.length} 本（清理数据库记录）',
                      Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    ...widget.result.missingFolderBooks.map((book) =>
                        _buildBookCheckbox(colorScheme, book)),
                    const SizedBox(height: 16),
                  ],

                  // 丢失文件的章节
                  if (widget.result.missingFileChapters.isNotEmpty) ...[
                    _buildSectionHeader(
                      colorScheme,
                      Icons.description_outlined,
                      '章节文件丢失',
                      '${widget.result.missingFileChapters.values.fold(0, (sum, list) => sum + list.length)} 个（清理数据库记录）',
                      colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    ...widget.result.missingFileChapters.entries.expand(
                        (entry) => entry.value.map((info) =>
                            _buildChapterItem(colorScheme, info))),
                    const SizedBox(height: 16),
                  ],

                  // 孤儿章节
                  if (widget.result.orphanChapters.isNotEmpty) ...[
                    _buildSectionHeader(
                      colorScheme,
                      Icons.link_off,
                      '无主章节（所属书籍已不存在）',
                      '${widget.result.orphanChapters.length} 个（清理数据库记录）',
                      Colors.purple,
                    ),
                    const SizedBox(height: 8),
                    ...widget.result.orphanChapters.map((chapter) =>
                        _buildOrphanChapterItem(colorScheme, chapter)),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 状态信息
          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_isProcessing)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  else
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: context.bodyMedium?.copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 底部按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                child: const Text('跳过'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _isProcessing ||
                        (_selectedBookUuids.isEmpty &&
                            widget.result.missingFileChapters.isEmpty &&
                            widget.result.orphanChapters.isEmpty)
                    ? null
                    : _performCleanup,
                child: const Text('确认清理'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建分区标题
  Widget _buildSectionHeader(
    ColorScheme colorScheme,
    IconData icon,
    String title,
    String count,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: context.titleSmall?.copyWith(fontWeight: FontWeight.w500, color: color),
            ),
          ),
          Text(
            count,
            style: context.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  /// 构建书籍复选框
  Widget _buildBookCheckbox(ColorScheme colorScheme, BookModel book) {
    return CheckboxListTile(
      value: _selectedBookUuids.contains(book.uuid),
      onChanged: _isProcessing
          ? null
          : (checked) {
              setState(() {
                if (checked == true) {
                  _selectedBookUuids.add(book.uuid);
                } else {
                  _selectedBookUuids.remove(book.uuid);
                }
              });
            },
      title: Text(
        book.title,
        style: context.titleSmall,
      ),
      subtitle: Text(
        'UUID: ${book.uuid.substring(0, 8)}...',
        style: context.labelSmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 12, right: 12),
    );
  }

  /// 构建章节项
  Widget _buildChapterItem(ColorScheme colorScheme, MissingChapterInfo info) {
    return ListTile(
      leading: Icon(
        Icons.article_outlined,
        size: 20,
        color: colorScheme.error,
      ),
      title: Text(
        info.chapter.title,
        style: context.titleSmall,
      ),
      subtitle: Text(
        '路径: ${() {
          final parts = info.expectedPath.split(Platform.pathSeparator);
          final lastParts = parts.length > 3 ? parts.skip(parts.length - 3).toList() : parts;
          return lastParts.join(Platform.pathSeparator);
        }()}',
        style: context.labelSmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 28, right: 12),
    );
  }

  /// 构建无主章节项
  Widget _buildOrphanChapterItem(ColorScheme colorScheme, ChapterModel chapter) {
    return ListTile(
      leading: Icon(
        Icons.link_off,
        size: 20,
        color: Colors.purple,
      ),
      title: Text(
        chapter.title,
        style: context.titleSmall,
      ),
      subtitle: Text(
        '所属书籍已不存在',
        style: context.labelSmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 28, right: 12),
    );
  }
}
