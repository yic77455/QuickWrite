import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 工具面板可配置显示的区块标识
enum ToolsSection {
  /// 书籍信息
  bookInfo('bookInfo', '书籍信息', Icons.menu_book_rounded),

  /// 码字统计
  stats('stats', '码字统计', Icons.insights_rounded);

  /// 区块唯一标识（用于持久化）
  final String id;

  /// 区块显示名称
  final String label;

  /// 区块图标
  final IconData icon;

  const ToolsSection(this.id, this.label, this.icon);

  /// 根据 ID 解析对应区块，未知 ID 回退为书籍信息
  static ToolsSection fromId(String id) =>
      values.firstWhere((s) => s.id == id, orElse: () => ToolsSection.bookInfo);
}

/// 工具面板显示设置面板
///
/// 作为工具面板标题栏"显示设置"按钮的下拉菜单内容，
/// 用于配置书籍信息、码字统计两个区块的显示开关与显示顺序。
/// [sectionOrder] 为当前可见区块的 ID 顺序列表，变化时通过 [onOrderChanged]
/// 回调通知父级，由父级负责持久化与重新渲染。
class ToolsDisplaySettings extends StatelessWidget {
  /// 当前可见区块的 ID 顺序列表
  final List<String> sectionOrder;

  /// 顺序/可见性变化回调
  final ValueChanged<List<String>> onOrderChanged;

  /// 菜单内容固定宽度
  static const double _panelWidth = 220.0;

  const ToolsDisplaySettings({
    super.key,
    required this.sectionOrder,
    required this.onOrderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: _panelWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 面板标题
          Row(
            children: [
              Text(
                '显示设置',
                style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildDivider(colorScheme),
          // 各区块配置行
          for (int i = 0; i < ToolsSection.values.length; i++) ...[
            _buildSectionRow(context, ToolsSection.values[i]),
          ],
        ],
      ),
    );
  }

  /// 构建分隔线
  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
    );
  }

  /// 构建单个区块配置行
  ///
  /// 左侧为区块图标与名称，右侧为上移/下移按钮与显示开关。
  /// 不可见区块的移动按钮禁用，开关控制其是否在显示列表中。
  Widget _buildSectionRow(BuildContext context, ToolsSection section) {
    final colorScheme = Theme.of(context).colorScheme;
    final isVisible = sectionOrder.contains(section.id);
    // 该区块在可见列表中的位置（-1 表示不可见）
    final visibleIndex = sectionOrder.indexOf(section.id);
    final canMoveUp = visibleIndex > 0;
    final canMoveDown = visibleIndex >= 0 && visibleIndex < sectionOrder.length - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(section.icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              section.label,
              style: context.bodySmall?.copyWith(
                color: isVisible ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                fontWeight: isVisible ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          // 上移按钮
          _buildMoveButton(
            context,
            icon: Icons.keyboard_arrow_up_rounded,
            enabled: canMoveUp,
            onTap: () => _move(section, -1),
          ),
          // 下移按钮
          _buildMoveButton(
            context,
            icon: Icons.keyboard_arrow_down_rounded,
            enabled: canMoveDown,
            onTap: () => _move(section, 1),
          ),
          const SizedBox(width: 2),
          // 显示开关
          Switch(
            value: isVisible,
            onChanged: (v) => _toggle(section, v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  /// 构建上下移动按钮
  Widget _buildMoveButton(
    BuildContext context, {
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      color: enabled
          ? colorScheme.onSurfaceVariant
          : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      onPressed: enabled ? onTap : null,
    );
  }

  /// 切换区块可见性
  ///
  /// 开启时将区块 ID 加入顺序列表末尾，关闭时从列表移除
  void _toggle(ToolsSection section, bool visible) {
    final order = List<String>.from(sectionOrder);
    if (visible) {
      if (!order.contains(section.id)) order.add(section.id);
    } else {
      order.remove(section.id);
    }
    onOrderChanged(order);
  }

  /// 移动区块顺序
  ///
  /// [direction] 为 -1 上移，1 下移；通过交换相邻位置实现
  void _move(ToolsSection section, int direction) {
    final order = List<String>.from(sectionOrder);
    final index = order.indexOf(section.id);
    if (index < 0) return;
    final target = index + direction;
    if (target < 0 || target >= order.length) return;
    final tmp = order[index];
    order[index] = order[target];
    order[target] = tmp;
    onOrderChanged(order);
  }
}
