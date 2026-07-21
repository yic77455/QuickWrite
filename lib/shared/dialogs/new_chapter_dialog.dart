import 'package:flutter/material.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/utils/chapter_number_utils.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示新建章节/分卷对话框
///
/// [workspaceProvider] 工作台 Provider，从调用方传入以避免 Provider 找不到的问题
/// [volumes] 当前书籍的分卷列表，从调用方传入以避免 Provider 找不到的问题
/// [initialVolumeUuid] 初始选中的分卷 UUID，空字符串表示未分卷
/// [onCreated] 章节创建成功后的回调，参数为新建的章节模型
Future<void> showNewChapterDialog({
  required BuildContext context,
  required WorkspaceProvider workspaceProvider,
  required List<VolumeModel> volumes,
  String initialVolumeUuid = '',
  void Function(ChapterModel)? onCreated,
}) {
  return showDialogBase(
    context: context,
    title: '',
    showCloseButton: false,
    width: 400,
    height: 380,
    adaptiveHeight: true,
    anchorTop: true,
    content: _NewChapterDialogContent(
      workspaceProvider: workspaceProvider,
      volumes: volumes,
      initialVolumeUuid: initialVolumeUuid,
      onCreated: onCreated,
    ),
  );
}

/// 新建章节/分卷对话框内容
class _NewChapterDialogContent extends StatefulWidget {
  /// 工作台 Provider
  final WorkspaceProvider workspaceProvider;
  /// 当前书籍的分卷列表
  final List<VolumeModel> volumes;
  /// 初始选中的分卷 UUID
  final String initialVolumeUuid;
  /// 章节创建成功后的回调
  final void Function(ChapterModel)? onCreated;

  const _NewChapterDialogContent({
    required this.workspaceProvider,
    required this.volumes,
    this.initialVolumeUuid = '',
    this.onCreated,
  });

  @override
  State<_NewChapterDialogContent> createState() => _NewChapterDialogContentState();
}

class _NewChapterDialogContentState extends State<_NewChapterDialogContent>
    with SingleTickerProviderStateMixin {
  // 当前页面索引：0=新建章节，1=新建分卷
  int _pageIndex = 0;

  // 章节标题控制器
  final TextEditingController _chapterTitleController = TextEditingController();
  // 章节标题焦点节点
  final FocusNode _chapterTitleFocusNode = FocusNode();
  // 当前选中的分卷 UUID，空字符串表示未分卷
  String _selectedVolumeUuid = '';

  // 分卷名称控制器
  final TextEditingController _volumeNameController = TextEditingController();
  // 分卷名称焦点节点
  final FocusNode _volumeNameFocusNode = FocusNode();

  // 错误信息
  String? _errorMessage;
  // 是否正在加载
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedVolumeUuid = widget.initialVolumeUuid;
    // 根据初始分卷自动填充章节序号
    _autoFillChapterNumber();
    // autofocus 会触发全选，需要在下一帧将光标定位到末尾
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _chapterTitleController.selection = TextSelection.collapsed(
          offset: _chapterTitleController.text.length,
        );
      });
    });
  }

  @override
  void dispose() {
    _chapterTitleController.dispose();
    _chapterTitleFocusNode.dispose();
    _volumeNameController.dispose();
    _volumeNameFocusNode.dispose();
    super.dispose();
  }

  /// 根据当前选中的分卷自动填充章节序号
  void _autoFillChapterNumber() {
    final chapters = widget.workspaceProvider.chapters;
    final nextNumber = ChapterNumberUtils.generateNextForVolume(
      chapters,
      _selectedVolumeUuid,
    );
    _chapterTitleController.text = nextNumber;
    // 将光标定位到末尾
    _chapterTitleController.selection = TextSelection.collapsed(
      offset: _chapterTitleController.text.length,
    );
  }

  /// 处理创建章节
  Future<void> _handleCreateChapter() async {
    final title = _chapterTitleController.text.trim();

    // 标题必填校验
    if (title.isEmpty) {
      setState(() => _errorMessage = '请输入章节名称');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 在 async gap 之前获取 Provider 引用
    final workspaceProvider = widget.workspaceProvider;

    final chapter = await workspaceProvider.addChapter(
      title: title,
      volumeUuid: _selectedVolumeUuid,
    );

    if (!mounted) return;

    if (chapter != null) {
      // 创建成功，保存分卷选择记忆
      final bookUuid = workspaceProvider.currentBook?.uuid;
      if (bookUuid != null) {
        MiscCacheService.instance.saveLastSelectedVolume(bookUuid, _selectedVolumeUuid);
      }
      widget.onCreated?.call(chapter);
      Navigator.of(context).pop();
      SnackBarService.show(context, '章节创建成功');
    } else {
      // 创建失败（同名章节已存在）
      setState(() {
        _errorMessage = '已存在同名章节';
        _isLoading = false;
      });
    }
  }

  /// 处理创建分卷
  Future<void> _handleCreateVolume() async {
    final volumeName = _volumeNameController.text.trim();

    // 分卷名称必填校验
    if (volumeName.isEmpty) {
      setState(() => _errorMessage = '请输入分卷名称');
      return;
    }

    // 检查是否已存在同名分卷
    if (widget.volumes.any((v) => v.name == volumeName)) {
      setState(() => _errorMessage = '已存在同名分卷');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 在 async gap 之前获取 Provider 引用
    final workspaceProvider = widget.workspaceProvider;

    final volumeUuid = await workspaceProvider.addVolume(volumeName: volumeName);

    if (!mounted) return;

    if (volumeUuid != null) {
      // 创建成功，保存分卷选择记忆
      final bookUuid = workspaceProvider.currentBook?.uuid;
      if (bookUuid != null) {
        MiscCacheService.instance.saveLastSelectedVolume(bookUuid, volumeUuid);
      }
      Navigator.of(context).pop();
      SnackBarService.show(context, '分卷创建成功');
    } else {
      setState(() {
        _errorMessage = '分卷创建失败';
        _isLoading = false;
      });
    }
  }

  /// 执行创建操作
  void _handleCreate() {
    if (_pageIndex == 0) {
      _handleCreateChapter();
    } else {
      _handleCreateVolume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 动态标题 + 关闭按钮
            _buildTitleRow(),
            const SizedBox(height: 16),
            // 页面切换分段选择器
            SegmentedControl(
              labels: const ['新建章节', '新建分卷'],
              selectedIndex: _pageIndex,
              onChanged: (index) {
                setState(() {
                  _pageIndex = index;
                  _errorMessage = null;
                });
                // 切换后自动聚焦对应输入框，并将光标定位到末尾
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (index == 0) {
                    _chapterTitleFocusNode.requestFocus();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _chapterTitleController.selection = TextSelection.collapsed(
                        offset: _chapterTitleController.text.length,
                      );
                    });
                  } else {
                    _volumeNameFocusNode.requestFocus();
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            // 页面内容
            _pageIndex == 0 ? _buildChapterPage() : _buildVolumePage(),
            const SizedBox(height: 20),
            // 底部按钮
            _buildButtonRow(),
          ],
        ),
      ),
    );
  }

  /// 构建标题行
  Widget _buildTitleRow() {
    final title = _pageIndex == 0 ? '新建章节' : '新建分卷';
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.titleLarge?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  /// 构建新建章节页面
  Widget _buildChapterPage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 章节名称输入框
        ImeCursorFixerWrapper(
          controller: _chapterTitleController,
          focusNode: _chapterTitleFocusNode,
          child: TextField(
            controller: _chapterTitleController,
            focusNode: _chapterTitleFocusNode,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '章节名称',
              hintText: '请输入章节名称',
              errorText: _pageIndex == 0 ? _errorMessage : null,
            ),
            onChanged: (_) {
              // 输入时清除错误信息
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
            onSubmitted: (_) => _handleCreate(),
          ),
        ),
        const SizedBox(height: 16),
        // 分卷选择下拉框
        _buildVolumeDropdown(),
      ],
    );
  }

  /// 构建分卷选择下拉框
  Widget _buildVolumeDropdown() {
    final colorScheme = Theme.of(context).colorScheme;

    // 构建下拉选项列表：未分卷 + 已有分卷
    final dropdownItems = <DropdownItem>[
      const DropdownItem(displayText: '未分卷', value: ''),
      for (final volume in widget.volumes) DropdownItem(displayText: volume.name, value: volume.uuid),
    ];

    // 确定下拉框当前值
    String dropdownValue;
    if (_selectedVolumeUuid.isEmpty || widget.volumes.any((v) => v.uuid == _selectedVolumeUuid)) {
      dropdownValue = _selectedVolumeUuid;
    } else {
      // 之前选中的分卷已不存在，重置为未分卷
      _selectedVolumeUuid = '';
      dropdownValue = '';
    }

    return Row(
      children: [
        Text(
          '选择分卷',
          style: context.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: CustomDropdown(
            width: double.infinity,
            value: dropdownValue,
            items: dropdownItems,
            onChanged: (value) {
              setState(() {
                _selectedVolumeUuid = value;
              });
              // 切换分卷后更新章节序号
              _autoFillChapterNumber();
            },
          ),
        ),
      ],
    );
  }

  /// 构建新建分卷页面
  Widget _buildVolumePage() {
    return ImeCursorFixerWrapper(
      controller: _volumeNameController,
      focusNode: _volumeNameFocusNode,
      child: TextField(
        controller: _volumeNameController,
        focusNode: _volumeNameFocusNode,
        autofocus: false,
        decoration: InputDecoration(
          labelText: '分卷名称',
          hintText: '请输入分卷名称',
          errorText: _pageIndex == 1 ? _errorMessage : null,
        ),
        onChanged: (_) {
          // 输入时清除错误信息
          if (_errorMessage != null) {
            setState(() => _errorMessage = null);
          }
        },
        onSubmitted: (_) => _handleCreate(),
      ),
    );
  }

  /// 构建底部按钮行
  Widget _buildButtonRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          width: 80,
          height: 36,
          child: TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          height: 36,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleCreate,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('创建', textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
