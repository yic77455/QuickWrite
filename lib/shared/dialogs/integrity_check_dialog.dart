import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/data_integrity_service.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示数据完整性校验结果对话框
///
/// [context] 构建上下文
/// [isar] 数据库实例
/// [result] 校验结果
/// 返回用户是否已完成处理（清理或从云端恢复）；选择稍后处理时返回 false
Future<bool> showIntegrityCheckDialog(
  BuildContext context,
  Isar isar,
  IntegrityCheckResult result,
) async {
  // 如果没有问题，不显示对话框
  if (result.missingFolderBooks.isEmpty &&
      result.missingFileChapters.isEmpty &&
      result.orphanChapters.isEmpty) {
    return false;
  }

  final resolved = await showDialogBase<bool>(
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

  return resolved ?? false;
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

  /// 是否已连接云服务
  ///
  /// 仅在已连接时展示云端恢复入口与清理风险警告
  bool _isCloudConnected = false;

  @override
  void initState() {
    super.initState();
    // 默认全选丢失文件夹的书籍
    _selectedBookUuids
        .addAll(widget.result.missingFolderBooks.map((b) => b.uuid));
    // 记录云服务连接状态
    _isCloudConnected = CloudSyncService.instance.isConnected;
  }

  /// 是否存在可从云端恢复的缺失内容
  ///
  /// 无主章节的所属书籍已不存在，无法通过同步补齐，因此不计入可恢复范围
  bool get _canRestoreFromCloud =>
      _isCloudConnected &&
      (widget.result.missingFolderBooks.isNotEmpty ||
          widget.result.missingFileChapters.isNotEmpty);

  /// 执行清理操作
  Future<void> _performCleanup() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = '正在清理...';
    });

    try {
      // 1. 清理用户选择的丢失文件夹的书籍（清理前复核，跳过期间已被恢复的书籍）
      final selectedBooks = widget.result.missingFolderBooks
          .where((b) => _selectedBookUuids.contains(b.uuid))
          .toList();
      final booksToRemove = await DataIntegrityService.instance
          .filterStillMissingFolderBooks(selectedBooks);
      final chaptersRemovedWithBooks = await DataIntegrityService.instance
          .removeMissingFolderBooks(widget.isar, booksToRemove);

      // 2. 清理所有丢失文件的章节（自动处理，清理前复核，跳过期间已被恢复的章节）
      final chapterCandidates = <MissingChapterInfo>[];
      for (final entry in widget.result.missingFileChapters.entries) {
        // 如果这本书的文件夹也被删除了，章节会随书籍一起删除，跳过
        if (!_selectedBookUuids.contains(entry.key)) {
          chapterCandidates.addAll(entry.value);
        }
      }
      final allMissingChapters = await DataIntegrityService.instance
          .filterStillMissingFileChapters(chapterCandidates);
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

        // 延迟关闭对话框，回传 true 表示问题已处理
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);

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

  /// 从云端恢复缺失内容
  ///
  /// 关闭对话框后触发一次同步，缺失的文件与记录会在同步过程中自动补齐
  void _restoreFromCloud() {
    Navigator.of(context).pop(true);
    CloudSyncService.instance.syncNow();
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

          // 云端恢复提示（已连接云服务且存在可恢复内容时展示）
          if (_canRestoreFromCloud) ...[
            _buildCloudRestoreNotice(colorScheme),
            const SizedBox(height: 16),
          ],

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

          // 清理风险警告（已连接云服务时展示）
          if (_isCloudConnected) ...[
            _buildCleanupWarning(colorScheme),
            const SizedBox(height: 12),
          ],

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
                // 回传 false 表示稍后处理，重新进入界面时会再次提示
                onPressed: _isProcessing ? null : () => Navigator.of(context).pop(false),
                child: Text(_isCloudConnected ? '稍后处理' : '跳过'),
              ),
              const SizedBox(width: 12),
              // 已连接云服务时清理为破坏性操作，按钮改用警示样式
              if (_isCloudConnected)
                OutlinedButton(
                  onPressed: _isProcessing ||
                          (_selectedBookUuids.isEmpty &&
                              widget.result.missingFileChapters.isEmpty &&
                              widget.result.orphanChapters.isEmpty)
                      ? null
                      : _performCleanup,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
                  ),
                  child: const Text('确认清理'),
                )
              else
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

  /// 构建云端恢复提示
  ///
  /// 引导用户优先从云端补齐缺失的书籍文件夹与章节文件，并提供恢复入口
  Widget _buildCloudRestoreNotice(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 18,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '云端存在备份，缺失的文件可以从云端恢复。建议先执行「从云端恢复」，同步会自动补齐缺失内容。',
                  style: context.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isProcessing ? null : _restoreFromCloud,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('从云端恢复'),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建清理风险警告
  ///
  /// 说明清理会删除数据库记录且删除会被同步到云端，并提示缺失章节与无主章节无法选择性保留
  Widget _buildCleanupWarning(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '「确认清理」会删除数据库记录，操作不可逆；其中仅书籍可勾选保留，'
              '缺失章节与无主章节将被无条件删除。已连接云服务时该删除会同步到云端，'
              '云端副本也会一并删除。',
              style: context.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
