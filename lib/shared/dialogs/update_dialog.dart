import 'package:flutter/material.dart';
import 'package:quick_write/core/services/update_service.dart';
import 'package:quick_write/core/utils/file_explorer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/url_opener.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 检查更新对话框
///
/// 打开后自动向更新源查询最新版本，并按结果切换展示：
/// 检查中、已是最新、发现新版本、下载中、下载完成、检查失败
class UpdateDialog {
  UpdateDialog._();

  /// 打开检查更新对话框
  ///
  /// [currentVersion] 为当前应用版本号
  static Future<void> show(BuildContext context, {required String currentVersion}) {
    return showDialogBase(
      context: context,
      title: '检查更新',
      width: 440,
      height: 440,
      adaptiveHeight: true,
      // 各阶段均有操作按钮，关闭入口统一交由内容的 PopScope 控制
      showCloseButton: false,
      content: _UpdateDialogContent(currentVersion: currentVersion),
    );
  }
}

/// 对话框的当前阶段
enum _UpdateStage { checking, upToDate, available, downloading, downloaded, failed }

/// 检查更新对话框的内容区域
class _UpdateDialogContent extends StatefulWidget {
  const _UpdateDialogContent({required this.currentVersion});

  /// 当前应用版本号
  final String currentVersion;

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  /// 当前所处的阶段
  _UpdateStage _stage = _UpdateStage.checking;

  /// 检查结果
  UpdateCheckResult? _result;

  /// 失败原因
  String? _errorMessage;

  /// 下载进度（0~1，总大小未知时为 null）
  double? _progress;

  /// 下载完成后的本地路径
  String? _savedPath;

  /// 当前下载任务的中止令牌
  UpdateCancelToken? _cancelToken;

  /// 安装程序是否已成功启动
  bool _installerLaunched = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  // ================= 业务流程 =================

  /// 向更新源查询最新版本
  Future<void> _check() async {
    setState(() {
      _stage = _UpdateStage.checking;
      _errorMessage = null;
    });

    try {
      final result = await UpdateService.checkForUpdate(widget.currentVersion);
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = result.hasUpdate ? _UpdateStage.available : _UpdateStage.upToDate;
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateStage.failed;
        _errorMessage = e.message;
      });
    }
  }

  /// 下载当前平台对应的安装包，完成后自动启动安装程序
  Future<void> _download() async {
    final asset = _result?.asset;
    if (asset == null) return;

    final cancelToken = UpdateCancelToken();
    setState(() {
      _stage = _UpdateStage.downloading;
      _progress = 0;
      _cancelToken = cancelToken;
    });

    try {
      final path = await UpdateService.downloadAsset(
        asset,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _stage = _UpdateStage.downloaded;
        _savedPath = path;
        _installerLaunched = false;
      });

      // 下载的是可运行安装包时，直接拉起安装程序，省去用户手动查找
      if (_isInstaller(asset.name)) {
        await _launchInstaller();
      }
    } on UpdateCancelledException {
      if (!mounted) return;
      setState(() => _stage = _UpdateStage.available);
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateStage.failed;
        _errorMessage = e.message;
      });
    }
  }

  /// 中止正在进行的下载
  void _cancelDownload() {
    _cancelToken?.cancel();
  }

  /// 用系统默认程序打开已下载的安装包
  Future<void> _launchInstaller() async {
    final path = _savedPath;
    if (path == null) return;

    final success = await UrlOpener.open(path);
    if (!mounted) return;
    setState(() => _installerLaunched = success);
  }

  /// 判断下载的文件是否为可直接运行的安装程序
  bool _isInstaller(String fileName) {
    const extensions = ['.exe', '.msi', '.dmg', '.pkg', '.appimage', '.deb', '.rpm'];
    final lowerName = fileName.toLowerCase();
    return extensions.any(lowerName.endsWith);
  }

  /// 在浏览器中打开版本发布页
  ///
  /// 优先打开本次检查所用更新源的发布页，未取得结果时回退到默认发布页
  Future<void> _openReleasePage() async {
    await UrlOpener.open(_result?.releaseUrl ?? UpdateService.releasesPageUrl);
  }

  /// 在文件管理器中定位已下载的安装包
  Future<void> _revealDownloadedFile() async {
    final path = _savedPath;
    if (path == null) return;
    final success = await FileExplorer.revealAll([path]);
    if (!mounted) return;
    if (!success) {
      SnackBarService.show(context, '打开所在文件夹失败：$path');
    }
  }

  // ================= 界面构建 =================

  @override
  Widget build(BuildContext context) {
    // 下载过程中拦截关闭操作，避免误触关闭后丢失进度与完成提示
    return PopScope(
      canPop: _stage != _UpdateStage.downloading,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SnackBarService.show(context, '安装包正在下载中，请稍候或点击「取消下载」');
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: switch (_stage) {
          _UpdateStage.checking => _buildChecking(context),
          _UpdateStage.upToDate => _buildUpToDate(context),
          _UpdateStage.available => _buildAvailable(context),
          _UpdateStage.downloading => _buildDownloading(context),
          _UpdateStage.downloaded => _buildDownloaded(context),
          _UpdateStage.failed => _buildFailed(context),
        },
      ),
    );
  }

  /// 检查中
  Widget _buildChecking(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text('正在检查更新…', style: context.bodyMedium),
        ],
      ),
    );
  }

  /// 已是最新版本
  Widget _buildUpToDate(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 40, color: colorScheme.primary),
        const SizedBox(height: 14),
        Text(
          '当前已是最新版本',
          style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'v${widget.currentVersion}',
          style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _openReleasePage, child: const Text('前往发布页')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _check, child: const Text('重新检查')),
          ],
        ),
      ],
    );
  }

  /// 发现新版本
  Widget _buildAvailable(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final result = _result!;
    final asset = result.asset;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.new_releases_outlined, size: 22, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '发现新版本 v${result.latestVersion}',
                style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '当前版本 v${widget.currentVersion}',
          style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),

        // 更新说明
        if (result.releaseNotes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: Text(
                result.releaseNotes,
                style: context.bodySmall?.copyWith(height: 1.6),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),

        // 下载入口：优先下载适配当前平台的安装包
        if (asset != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  asset.size > 0 ? '安装包大小 ${_formatSize(asset.size)}' : asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('下载安装包'),
              ),
            ],
          )
        else ...[
          Text(
            '未找到适配当前平台的安装包，请前往发布页手动下载。',
            style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _openReleasePage,
              child: const Text('前往发布页'),
            ),
          ),
        ],
      ],
    );
  }

  /// 下载中
  Widget _buildDownloading(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = _progress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '正在下载安装包…',
          style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          _result?.asset?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                progress == null ? '下载中…' : '${(progress * 100).toStringAsFixed(0)}%',
                style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(onPressed: _cancelDownload, child: const Text('取消下载')),
          ],
        ),
      ],
    );
  }

  /// 下载完成
  Widget _buildDownloaded(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = _savedPath ?? '';
    final assetName = _result?.asset?.name ?? '';
    final isInstaller = _isInstaller(assetName);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 22, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '下载完成',
              style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _installerLaunched
              ? '已启动安装程序，请按提示完成安装。'
              : isInstaller
                  ? '安装程序启动失败，可手动打开或前往文件夹。'
                  : '免安装包下载完成，解压后即可使用。',
          style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        SelectableText(
          path,
          style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: _revealDownloadedFile,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('打开所在文件夹'),
            ),
            if (isInstaller) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _launchInstaller,
                icon: const Icon(Icons.install_desktop_outlined, size: 18),
                label: const Text('打开安装程序'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 检查或下载失败
  Widget _buildFailed(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 22, color: colorScheme.error),
            const SizedBox(width: 8),
            Text(
              '检查更新失败',
              style: context.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _errorMessage ?? '请稍后重试',
          style: context.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _openReleasePage, child: const Text('前往发布页')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _check, child: const Text('重试')),
          ],
        ),
      ],
    );
  }

  /// 将字节数格式化为可读大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}