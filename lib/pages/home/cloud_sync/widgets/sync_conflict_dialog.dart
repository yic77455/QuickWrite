import 'dart:io';

import 'package:flutter/material.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/cloud_sync/sync_conflict_resolver.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:quick_write/core/utils/file_explorer.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 可以按图片方式预览的扩展名
const Set<String> _imageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
};

/// 可以按文本方式预览的扩展名
const Set<String> _textExtensions = {
  '.txt',
  '.json',
  '.md',
  '.markdown',
  '.csv',
  '.xml',
  '.yaml',
  '.yml',
  '.html',
  '.htm',
  '.css',
  '.js',
};

/// 展示同步冲突副本处理弹窗
///
/// 同步为本机版本另存出冲突副本时弹出，逐个列出发生冲突的文件，
/// 用户可以查看当前文件与冲突副本的内容，并决定是否用副本替换当前文件。
/// [navigatorKey] 应用根导航器的键；界面尚未就绪时无法弹窗，直接跳过提示
/// [conflicts] 本次另存出的冲突副本
Future<void> showSyncConflictDialog(
  GlobalKey<NavigatorState> navigatorKey,
  List<SyncConflictCopy> conflicts,
) async {
  final context = navigatorKey.currentContext;
  if (context == null || conflicts.isEmpty) return;

  await showDialogBase<void>(
    context: context,
    title: '同步保留了冲突副本',
    width: 460,
    height: 540,
    barrierDismissible: false,
    content: _SyncConflictDialogContent(conflicts: conflicts),
  );
}

/// 冲突副本列表内容
class _SyncConflictDialogContent extends StatefulWidget {
  /// 本次待处理的冲突副本
  final List<SyncConflictCopy> conflicts;

  const _SyncConflictDialogContent({required this.conflicts});

  @override
  State<_SyncConflictDialogContent> createState() =>
      _SyncConflictDialogContentState();
}

class _SyncConflictDialogContentState
    extends State<_SyncConflictDialogContent> {
  /// 尚未处理的冲突副本
  late final List<SyncConflictCopy> _conflicts = List.of(widget.conflicts);

  /// 打开对比弹窗；用户完成替换后从列表中移除该冲突副本
  Future<void> _openCompare(SyncConflictCopy conflict) async {
    final replaced = await showDialogBase<bool>(
      context: context,
      title: '冲突文件对比',
      width: 560,
      height: 560,
      content: _ConflictCompareContent(conflict: conflict),
    );
    if (!mounted || replaced != true) return;

    setState(() => _conflicts.remove(conflict));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 冲突说明：说明冲突来源与可执行的处理方式
          Text(
            _conflicts.isEmpty
                ? '所有冲突副本都已处理完毕。'
                : '本次同步有 ${_conflicts.length} 处内容两端都做过修改，'
                      '已把本机版本另存为冲突副本。点按文件可查看两版内容，'
                      '并决定是否用副本替换当前文件。',
            style: context.bodyMedium?.copyWith(
              height: 1.5,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          // 冲突文件列表
          Expanded(
            child: _conflicts.isEmpty
                ? Center(
                    child: Text(
                      '暂无待处理的冲突副本',
                      style: context.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _conflicts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conflict = _conflicts[index];
                      return _ConflictItem(
                        conflict: conflict,
                        onTap: () => _openCompare(conflict),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 冲突文件列表项
class _ConflictItem extends StatelessWidget {
  /// 冲突副本
  final SyncConflictCopy conflict;

  /// 点击查看对比
  final VoidCallback onTap;

  const _ConflictItem({required this.conflict, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 文件所属的书籍或配置分类，帮助用户快速识别冲突所在的上下文
    final contextLabel = _contextOf(conflict.originalPath);

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              // 文件图标
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              // 文件名与操作说明
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fileNameOf(conflict.originalPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contextLabel == null
                          ? '点按查看当前文件与冲突副本的内容'
                          : '$contextLabel · 点按查看两版内容',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 冲突文件对比内容
class _ConflictCompareContent extends StatefulWidget {
  /// 待对比的冲突副本
  final SyncConflictCopy conflict;

  const _ConflictCompareContent({required this.conflict});

  @override
  State<_ConflictCompareContent> createState() =>
      _ConflictCompareContentState();
}

class _ConflictCompareContentState extends State<_ConflictCompareContent> {
  /// 当前文件的内容预览
  _ConflictPreview? _currentPreview;

  /// 冲突副本的内容预览
  _ConflictPreview? _copyPreview;

  /// 当前查看的版本：0 为当前文件，1 为冲突副本
  int _selectedIndex = 0;

  /// 是否正在执行替换
  bool _replacing = false;

  @override
  void initState() {
    super.initState();
    _loadPreviews();
  }

  /// 同时读取当前文件与冲突副本的内容，供切换查看
  Future<void> _loadPreviews() async {
    final previews = await Future.wait([
      _loadPreview(widget.conflict.originalPath),
      _loadPreview(widget.conflict.copyPath),
    ]);
    if (!mounted) return;

    setState(() {
      _currentPreview = previews[0];
      _copyPreview = previews[1];
    });
  }

  /// 读取文件内容并判断预览方式
  Future<_ConflictPreview> _loadPreview(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return const _ConflictPreview(kind: _PreviewKind.missing);
      }

      final size = await file.length();
      final extension = _extensionOf(path);
      if (_imageExtensions.contains(extension)) {
        return _ConflictPreview(kind: _PreviewKind.image, size: size);
      }
      if (!_textExtensions.contains(extension)) {
        return _ConflictPreview(kind: _PreviewKind.unsupported, size: size);
      }

      return _ConflictPreview(
        kind: _PreviewKind.text,
        text: await file.readAsString(),
        size: size,
      );
    } catch (e) {
      debugPrint('读取冲突文件内容失败: $path，$e');
      return const _ConflictPreview(kind: _PreviewKind.unsupported);
    }
  }

  /// 确认后把冲突副本的内容写回正式文件
  Future<void> _replaceWithCopy() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '用冲突副本替换当前文件？',
      description:
          '「${_fileNameOf(widget.conflict.originalPath)}」的当前内容将被冲突副本覆盖，'
          '替换后冲突副本会被删除。若该文件正在编辑，请重新打开以查看替换后的内容。',
      type: ConfirmType.warning,
      confirmText: '替换',
      cancelText: '取消',
    );
    if (!confirmed || !mounted) return;

    setState(() => _replacing = true);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await SyncConflictResolver.replaceWithCopy(widget.conflict);
      // 替换后的内容需要尽快推送到云端，交由同步调度器按设置安排
      CloudSyncService.instance.notifyLocalChange();
      if (!mounted) return;

      Navigator.of(context).pop(true);
      SnackBarService.showOnOverlay(overlay, '已用冲突副本替换当前文件');
    } catch (e) {
      debugPrint('用冲突副本替换文件失败: $e');
      if (!mounted) return;

      setState(() => _replacing = false);
      SnackBarService.showError(context, '替换失败，请稍后重试');
    }
  }

  /// 在系统文件管理器中定位冲突副本（仅桌面端可用）
  Future<void> _revealCopy() async {
    final revealed = await FileExplorer.revealAll([widget.conflict.copyPath]);
    if (!revealed && mounted) {
      SnackBarService.showError(context, '无法定位冲突副本');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 冲突副本缺失时已没有可替换的内容，禁用替换入口
    final copyMissing = _copyPreview?.kind == _PreviewKind.missing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 文件名
          Text(
            _fileNameOf(widget.conflict.originalPath),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '「当前文件」为本次同步写入的版本，「冲突副本」为本机修改过的版本',
            style: context.bodySmall?.copyWith(
              height: 1.4,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // 版本切换
          SegmentedControl(
            labels: const ['当前文件', '冲突副本'],
            selectedIndex: _selectedIndex,
            onChanged: (index) => setState(() => _selectedIndex = index),
          ),
          const SizedBox(height: 12),
          // 内容预览
          Expanded(
            child: _ConflictPreviewView(
              preview: _selectedIndex == 0 ? _currentPreview : _copyPreview,
              path: _selectedIndex == 0
                  ? widget.conflict.originalPath
                  : widget.conflict.copyPath,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // 桌面端保留在文件管理器中定位副本的入口
              if (PlatformCapabilities.supportsFileManagerReveal)
                TextButton.icon(
                  onPressed: _replacing ? null : _revealCopy,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('定位副本文件'),
                ),
              const Spacer(),
              TextButton(
                onPressed: _replacing
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('关闭'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _replacing || copyMissing ? null : _replaceWithCopy,
                child: _replacing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('用副本替换'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 文件内容预览
class _ConflictPreviewView extends StatelessWidget {
  /// 已读取的预览内容；为 null 表示仍在读取
  final _ConflictPreview? preview;

  /// 文件路径，用于展示图片
  final String path;

  const _ConflictPreviewView({required this.preview, required this.path});

  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    if (preview == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    switch (preview.kind) {
      case _PreviewKind.missing:
        return _buildMessage(context, '文件不存在，可能已被移动或删除');
      case _PreviewKind.unsupported:
        return _buildMessage(
          context,
          '该文件无法直接预览（${_formatSize(preview.size)}）',
        );
      case _PreviewKind.text:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              preview.text!.isEmpty ? '（文件为空）' : preview.text!,
              style: context.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        );
      case _PreviewKind.image:
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _buildMessage(context, '图片无法显示'),
            ),
          ),
        );
    }
  }

  /// 构建居中提示文字
  Widget _buildMessage(BuildContext context, String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 预览方式
enum _PreviewKind {
  /// 文件不存在
  missing,

  /// 文本内容
  text,

  /// 图片内容
  image,

  /// 无法预览的其它内容
  unsupported,
}

/// 冲突文件的预览数据
class _ConflictPreview {
  /// 预览方式
  final _PreviewKind kind;

  /// 文本内容（非文本预览时为 null）
  final String? text;

  /// 文件字节数
  final int size;

  const _ConflictPreview({required this.kind, this.text, this.size = 0});
}

/// 获取路径中的文件名
String _fileNameOf(String path) {
  final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
  return separatorIndex == -1 ? path : path.substring(separatorIndex + 1);
}

/// 获取冲突文件所属的上下文名称
///
/// 书籍内的文件返回书名，词典、主题与应用设置返回对应的分类名；
/// 无法判断时返回 null，由界面退化为通用说明
String? _contextOf(String path) {
  final separator = Platform.pathSeparator;
  final booksPath = AppPaths.instance.isInitialized
      ? AppPaths.instance.booksPath
      : '';

  // 书籍根目录下的文件取书名作为上下文
  final booksPrefix = '$booksPath$separator';
  if (booksPath.isNotEmpty && path.startsWith(booksPrefix)) {
    final segments = path.substring(booksPrefix.length).split(separator);
    if (segments.isNotEmpty && segments.first.isNotEmpty) {
      return segments.first;
    }
  }

  final segments = path.split(separator);
  if (segments.length < 2) return null;

  // 书籍目录之外的配置文件按所在目录分类
  switch (segments[segments.length - 2]) {
    case 'dict':
      return '自定义词典';
    case 'theme':
      return '自定义主题';
    case 'app':
      return '应用设置';
    default:
      return null;
  }
}

/// 获取路径中的扩展名（含点号，统一为小写），无扩展名时返回空字符串
String _extensionOf(String path) {
  final dotIndex = path.lastIndexOf('.');
  final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
  if (dotIndex <= separatorIndex) return '';
  return path.substring(dotIndex).toLowerCase();
}

/// 将字节数格式化为便于阅读的大小
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
