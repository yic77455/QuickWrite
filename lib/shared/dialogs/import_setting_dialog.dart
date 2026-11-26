import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/setting_import_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_text_field.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示导入设定对话框
///
/// [provider] 由调用方传入，避免弹窗路由上下文中找不到工作台 Provider
Future<void> showImportSettingDialog(BuildContext context, WorkspaceProvider provider) {
  final interactiveNotifier = ValueNotifier<bool>(true);
  return showDialogBase(
    context: context,
    title: '导入设定',
    width: 460,
    height: 560,
    adaptiveHeight: true,
    anchorTop: true,
    dialogInteractiveNotifier: interactiveNotifier,
    content: _ImportSettingDialogContent(
      interactiveNotifier: interactiveNotifier,
      provider: provider,
    ),
  );
}

class _ImportSettingDialogContent extends StatefulWidget {
  final ValueNotifier<bool> interactiveNotifier;
  final WorkspaceProvider provider;

  const _ImportSettingDialogContent({
    required this.interactiveNotifier,
    required this.provider,
  });

  @override
  State<_ImportSettingDialogContent> createState() => _ImportSettingDialogContentState();
}

class _ImportSettingDialogContentState extends State<_ImportSettingDialogContent> {
  String? _sourcePath;
  SettingImportPreview? _preview;
  late final TextEditingController _titleController;
  final FocusNode _titleFocusNode = FocusNode();
  String _groupUuid = '';
  bool _isImporting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  /// 选择原格式导出的设定文件
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md'],
        allowMultiple: false,
      );
      final picked = result?.files;
      if (picked == null || picked.isEmpty) return;
      final path = picked.single.path;
      if (path == null || !mounted) return;

      final preview = await SettingImportService.instance.inspect(path);
      if (!mounted) return;
      setState(() {
        _sourcePath = path;
        _preview = preview;
        _titleController.text = preview.title;
        _errorMessage = null;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '读取文件失败: $e');
    }
  }

  /// 执行导入
  Future<void> _startImport() async {
    final sourcePath = _sourcePath;
    if (sourcePath == null) {
      setState(() => _errorMessage = '请先选择设定文件');
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = '请输入设定名称');
      return;
    }

    widget.interactiveNotifier.value = false;
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    final result = await widget.provider.importSettingItem(
      sourceFilePath: sourcePath,
      title: title,
      groupUuid: _groupUuid,
    );
    if (!mounted) return;

    widget.interactiveNotifier.value = true;
    if (!result.success) {
      setState(() {
        _isImporting = false;
        _errorMessage = result.errorMessage ?? '导入失败';
      });
      return;
    }

    Navigator.of(context).pop();
    final details = <String>[];
    if (result.imageCount > 0) details.add('${result.imageCount} 张图片');
    SnackBarService.show(
      context,
      details.isEmpty ? '设定「$title」导入成功' : '设定「$title」导入成功：${details.join('、')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final groups = widget.provider.settingGroups;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFileSelector(colorScheme),
            const SizedBox(height: 20),
            _buildTitleInput(colorScheme),
            const SizedBox(height: 20),
            _buildGroupSelector(colorScheme, groups),
            if (_preview != null) ...[const SizedBox(height: 16), _buildPreview(colorScheme, _preview!)],
            if (_errorMessage != null) ...[const SizedBox(height: 12), _buildErrorBox(colorScheme)],
            const SizedBox(height: 20),
            _buildButtonRow(),
          ],
        ),
      ),
    );
  }

  /// 构建文件选择区域
  Widget _buildFileSelector(ColorScheme colorScheme) {
    final fileName = _sourcePath == null ? null : File(_sourcePath!).path.split(Platform.pathSeparator).last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设定文件', style: context.titleSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        InkWell(
          onTap: _isImporting ? null : _pickFile,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: fileName != null
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  fileName != null ? Icons.insert_drive_file : Icons.upload_file_outlined,
                  size: 22,
                  color: fileName != null ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fileName ?? '点击选择按原格式导出的 .md 文件',
                    style: context.bodyLarge?.copyWith(
                      color: fileName != null ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '将一并恢复同名伴生文件与使用到的图片',
          style: context.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  /// 构建设定名称输入
  Widget _buildTitleInput(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设定名称', style: context.titleSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        ImeCursorFixerWrapper(
          controller: _titleController,
          focusNode: _titleFocusNode,
          child: QwTextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            enabled: !_isImporting,
            style: context.bodyLarge,
            decoration: const InputDecoration(hintText: '请输入设定名称'),
            onChanged: (_) {
              if (_errorMessage != null) setState(() => _errorMessage = null);
            },
          ),
        ),
      ],
    );
  }

  /// 构建分组选择
  Widget _buildGroupSelector(ColorScheme colorScheme, List<SettingGroupModel> groups) {
    final items = <DropdownItem>[
      const DropdownItem(displayText: '未分组', value: ''),
      for (final group in groups) DropdownItem(displayText: group.name, value: group.uuid),
    ];
    final groupUuid = items.any((item) => item.value == _groupUuid) ? _groupUuid : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('导入到分组', style: context.titleSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        IgnorePointer(
          ignoring: _isImporting,
          child: CustomDropdown(
            width: double.infinity,
            value: groupUuid,
            items: items,
            onChanged: (value) => setState(() => _groupUuid = value),
          ),
        ),
      ],
    );
  }

  /// 构建检查结果预览
  Widget _buildPreview(ColorScheme colorScheme, SettingImportPreview preview) {
    final parts = <String>[
      preview.hasCompanion ? '找到伴生文件' : '未找到伴生文件',
      '${preview.imageCount} 张图片',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(parts.join(' · '), style: context.bodyMedium),
          for (final warning in preview.warnings.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '提示：$warning',
                style: context.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建错误提示
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
            child: Text(
              _errorMessage!,
              style: context.titleSmall?.copyWith(color: colorScheme.error),
            ),
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
            onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          height: 36,
          child: FilledButton(
            onPressed: _isImporting || _sourcePath == null ? null : _startImport,
            child: _isImporting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('导入'),
          ),
        ),
      ],
    );
  }
}
