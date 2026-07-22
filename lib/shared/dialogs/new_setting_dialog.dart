import 'package:flutter/material.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示新建设定/分组对话框
///
/// [workspaceProvider] 工作台 Provider，从调用方传入以避免 Provider 找不到的问题
/// [groups] 当前书籍的设定分组列表，从调用方传入以避免 Provider 找不到的问题
/// [initialGroupUuid] 初始选中的分组 UUID，空字符串表示未分组
/// [onCreated] 设定创建成功后的回调，参数为新建的设定项模型
Future<void> showNewSettingDialog({
  required BuildContext context,
  required WorkspaceProvider workspaceProvider,
  required List<SettingGroupModel> groups,
  String initialGroupUuid = '',
  void Function(SettingItemModel)? onCreated,
}) {
  return showDialogBase(
    context: context,
    title: '',
    showCloseButton: false,
    width: 400,
    height: 380,
    adaptiveHeight: true,
    anchorTop: true,
    content: _NewSettingDialogContent(
      workspaceProvider: workspaceProvider,
      groups: groups,
      initialGroupUuid: initialGroupUuid,
      onCreated: onCreated,
    ),
  );
}

/// 新建设定/分组对话框内容
class _NewSettingDialogContent extends StatefulWidget {
  /// 工作台 Provider
  final WorkspaceProvider workspaceProvider;
  /// 当前书籍的设定分组列表
  final List<SettingGroupModel> groups;
  /// 初始选中的分组 UUID
  final String initialGroupUuid;
  /// 设定创建成功后的回调
  final void Function(SettingItemModel)? onCreated;

  const _NewSettingDialogContent({
    required this.workspaceProvider,
    required this.groups,
    this.initialGroupUuid = '',
    this.onCreated,
  });

  @override
  State<_NewSettingDialogContent> createState() => _NewSettingDialogContentState();
}

class _NewSettingDialogContentState extends State<_NewSettingDialogContent>
    with SingleTickerProviderStateMixin {
  // 当前页面索引：0=新建设定，1=新建分组
  int _pageIndex = 0;

  // 设定标题控制器
  final TextEditingController _settingTitleController = TextEditingController();
  // 设定标题焦点节点
  final FocusNode _settingTitleFocusNode = FocusNode();
  // 当前选中的分组 UUID，空字符串表示未分组
  String _selectedGroupUuid = '';

  // 分组名称控制器
  final TextEditingController _groupNameController = TextEditingController();
  // 分组名称焦点节点
  final FocusNode _groupNameFocusNode = FocusNode();

  // 错误信息
  String? _errorMessage;
  // 是否正在加载
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedGroupUuid = widget.initialGroupUuid;
    // autofocus 会触发全选，需要在下一帧将光标定位到末尾
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _settingTitleController.selection = TextSelection.collapsed(
          offset: _settingTitleController.text.length,
        );
      });
    });
  }

  @override
  void dispose() {
    _settingTitleController.dispose();
    _settingTitleFocusNode.dispose();
    _groupNameController.dispose();
    _groupNameFocusNode.dispose();
    super.dispose();
  }

  /// 处理创建设定
  Future<void> _handleCreateSetting() async {
    final title = _settingTitleController.text.trim();

    // 标题必填校验
    if (title.isEmpty) {
      setState(() => _errorMessage = '请输入设定名称');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 在 async gap 之前获取 Provider 引用
    final workspaceProvider = widget.workspaceProvider;

    final settingItem = await workspaceProvider.addSettingItem(
      title: title,
      groupUuid: _selectedGroupUuid,
    );

    if (!mounted) return;

    if (settingItem != null) {
      // 创建成功，保存分组选择记忆
      final bookUuid = workspaceProvider.currentBook?.uuid;
      if (bookUuid != null) {
        MiscCacheService.instance.saveLastSelectedSettingGroup(bookUuid, _selectedGroupUuid);
      }
      widget.onCreated?.call(settingItem);
      Navigator.of(context).pop();
      SnackBarService.show(context, '设定创建成功');
    } else {
      // 创建失败（同名设定已存在）
      setState(() {
        _errorMessage = '已存在同名设定';
        _isLoading = false;
      });
    }
  }

  /// 处理创建分组
  Future<void> _handleCreateGroup() async {
    final groupName = _groupNameController.text.trim();

    // 分组名称必填校验
    if (groupName.isEmpty) {
      setState(() => _errorMessage = '请输入分组名称');
      return;
    }

    // 检查是否已存在同名分组
    if (widget.groups.any((g) => g.name == groupName)) {
      setState(() => _errorMessage = '已存在同名分组');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 在 async gap 之前获取 Provider 引用
    final workspaceProvider = widget.workspaceProvider;

    final newGroup = await workspaceProvider.addSettingGroup(name: groupName);

    if (!mounted) return;

    if (newGroup != null) {
      // 创建成功，保存分组选择记忆
      final bookUuid = workspaceProvider.currentBook?.uuid;
      if (bookUuid != null) {
        MiscCacheService.instance.saveLastSelectedSettingGroup(bookUuid, newGroup.uuid);
      }
      Navigator.of(context).pop();
      SnackBarService.show(context, '分组创建成功');
    } else {
      setState(() {
        _errorMessage = '分组创建失败';
        _isLoading = false;
      });
    }
  }

  /// 执行创建操作
  void _handleCreate() {
    if (_pageIndex == 0) {
      _handleCreateSetting();
    } else {
      _handleCreateGroup();
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
              labels: const ['新建设定', '新建分组'],
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
                    _settingTitleFocusNode.requestFocus();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _settingTitleController.selection = TextSelection.collapsed(
                        offset: _settingTitleController.text.length,
                      );
                    });
                  } else {
                    _groupNameFocusNode.requestFocus();
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            // 页面内容
            _pageIndex == 0 ? _buildSettingPage() : _buildGroupPage(),
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
    final title = _pageIndex == 0 ? '新建设定' : '新建分组';
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

  /// 构建新建设定页面
  Widget _buildSettingPage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 设定名称输入框
        ImeCursorFixerWrapper(
          controller: _settingTitleController,
          focusNode: _settingTitleFocusNode,
          child: TextField(
            controller: _settingTitleController,
            focusNode: _settingTitleFocusNode,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '设定名称',
              hintText: '请输入设定名称',
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
        // 分组选择下拉框
        _buildGroupDropdown(),
      ],
    );
  }

  /// 构建分组选择下拉框
  Widget _buildGroupDropdown() {
    final colorScheme = Theme.of(context).colorScheme;

    // 构建下拉选项列表：未分组 + 已有分组
    final dropdownItems = <DropdownItem>[
      const DropdownItem(displayText: '未分组', value: ''),
      for (final group in widget.groups) DropdownItem(displayText: group.name, value: group.uuid),
    ];

    // 确定下拉框当前值
    String dropdownValue;
    if (_selectedGroupUuid.isEmpty || widget.groups.any((g) => g.uuid == _selectedGroupUuid)) {
      dropdownValue = _selectedGroupUuid;
    } else {
      // 之前选中的分组已不存在，重置为未分组
      _selectedGroupUuid = '';
      dropdownValue = '';
    }

    return Row(
      children: [
        Text(
          '选择分组',
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
                _selectedGroupUuid = value;
              });
            },
          ),
        ),
      ],
    );
  }

  /// 构建新建分组页面
  Widget _buildGroupPage() {
    return ImeCursorFixerWrapper(
      controller: _groupNameController,
      focusNode: _groupNameFocusNode,
      child: TextField(
        controller: _groupNameController,
        focusNode: _groupNameFocusNode,
        autofocus: false,
        decoration: InputDecoration(
          labelText: '分组名称',
          hintText: '请输入分组名称',
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
