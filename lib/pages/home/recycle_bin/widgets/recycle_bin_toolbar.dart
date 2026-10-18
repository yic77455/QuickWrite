import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 回收站工具栏组件
///
/// 显示全选复选框、选中数量、批量操作按钮和清空按钮
/// 书籍回收站和章节回收站共用此组件
class RecycleBinToolbar extends StatelessWidget {
  /// 已选中的数量
  final int selectedCount;

  /// 当前视图的项总数（用于计算全选复选框的三态）
  final int totalCount;

  /// 是否有选中项
  final bool hasSelection;

  /// 全选回调
  final VoidCallback onSelectAll;

  /// 取消全选回调
  final VoidCallback onDeselectAll;

  /// 恢复回调
  final VoidCallback onRestore;

  /// 彻底删除回调
  final VoidCallback onDelete;

  /// 清空回收站回调
  final VoidCallback onEmpty;

  /// 清空按钮文字
  final String emptyLabel;

  const RecycleBinToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.hasSelection,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onRestore,
    required this.onDelete,
    required this.onEmpty,
    this.emptyLabel = '清空回收站',
    super.key,
  });

  /// 全选复选框的三态值
  /// - true: 全部选中
  /// - false: 未选中任何项
  /// - null: 部分选中
  bool? get _selectAllState {
    if (selectedCount == 0) return false;
    if (selectedCount >= totalCount) return true;
    return null;
  }

  /// 处理全选复选框点击
  /// 已全选时取消全选，其他情况执行全选
  void _handleToggleSelectAll() {
    if (_selectAllState == true) {
      onDeselectAll();
    } else {
      onSelectAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 移动端：仅保留全选、选中数量与清空按钮，批量操作按钮交由列表下方的操作栏承载
    if (PlatformCapabilities.isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: [
            _buildSelectAllCheckbox(),
            const SizedBox(width: 8),
            _buildSelectedCount(context),
            const Spacer(),
            _buildEmptyButton(),
          ],
        ),
      );
    }

    return Padding(
      // 顶部增加间距，与 Tab 切换栏保持视觉间距
      padding: const EdgeInsets.only(left: 32, right: 32, top: 8, bottom: 8),
      child: Row(
        children: [
          // 全选复选框（左侧加 16px 内边距，与下方列表卡片内的复选框对齐）
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildSelectAllCheckbox(),
          ),
          const SizedBox(width: 8),
          // 选中数量提示
          _buildSelectedCount(context),
          const Spacer(),
          // 批量恢复按钮
          _buildRecycleRestoreButton(enabled: hasSelection, onPressed: onRestore),
          const SizedBox(width: 8),
          // 批量彻底删除按钮
          _buildRecycleDeleteButton(enabled: hasSelection, onPressed: onDelete),
          const SizedBox(width: 8),
          // 清空回收站按钮
          _buildEmptyButton(),
        ],
      ),
    );
  }

  /// 构建全选复选框
  Widget _buildSelectAllCheckbox() {
    return Checkbox(
      value: _selectAllState,
      tristate: true,
      onChanged: (_) => _handleToggleSelectAll(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  /// 构建选中数量提示
  Widget _buildSelectedCount(BuildContext context) {
    return Text(
      '已选中 $selectedCount 项',
      style: context.bodyLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  /// 构建清空回收站按钮
  Widget _buildEmptyButton() {
    return FilledButton.tonal(
      onPressed: onEmpty,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      ),
      child: Text(emptyLabel),
    );
  }
}

/// 回收站批量操作栏
///
/// 移动端位于列表下方，承载批量恢复与彻底删除操作
class RecycleBinActionBar extends StatelessWidget {
  /// 恢复回调
  final VoidCallback onRestore;

  /// 彻底删除回调
  final VoidCallback onDelete;

  const RecycleBinActionBar({
    required this.onRestore,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          const Spacer(),
          // 批量恢复
          _buildRecycleRestoreButton(enabled: true, onPressed: onRestore),
          const SizedBox(width: 8),
          // 批量彻底删除
          _buildRecycleDeleteButton(enabled: true, onPressed: onDelete),
        ],
      ),
    );
  }
}

/// 构建批量恢复按钮
Widget _buildRecycleRestoreButton({
  required bool enabled,
  required VoidCallback onPressed,
}) {
  return TextButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: const Icon(Icons.restore, size: 18),
    style: TextButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
    ),
    label: const Text('恢复'),
  );
}

/// 构建批量彻底删除按钮
Widget _buildRecycleDeleteButton({
  required bool enabled,
  required VoidCallback onPressed,
}) {
  return TextButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: Icon(
      Icons.delete_forever_outlined,
      size: 18,
      color: enabled ? const Color.fromARGB(255, 224, 52, 40) : null,
    ),
    style: TextButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
    ),
    label: Text(
      '彻底删除',
      style: TextStyle(
        color: enabled ? const Color.fromARGB(255, 224, 52, 40) : null,
      ),
    ),
  );
}
