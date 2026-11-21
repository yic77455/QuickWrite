import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 工具面板可配置显示项的分组
///
/// 不同分组的显示项各自维护显示顺序，互不影响：
/// - [function]：功能区（随机取名、敏感词检测）
/// - [section]：信息区块（书籍信息、码字统计）
enum ToolsSectionGroup {
  /// 功能区
  function,

  /// 信息区块
  section,
}

/// 工具面板可配置显示的区块标识
enum ToolsSection {
  /// 随机取名
  nameGen('nameGen', '随机取名', Icons.casino_rounded, ToolsSectionGroup.function),

  /// 敏感词检测
  sensitiveWord('sensitiveWord', '敏感词检测', Icons.gpp_bad_outlined, ToolsSectionGroup.function),

  /// 书籍信息
  bookInfo('bookInfo', '书籍信息', Icons.menu_book_rounded, ToolsSectionGroup.section),

  /// 码字统计
  stats('stats', '码字统计', Icons.insights_rounded, ToolsSectionGroup.section);

  /// 区块唯一标识（用于持久化）
  final String id;

  /// 区块显示名称
  final String label;

  /// 区块图标
  final IconData icon;

  /// 所属分组
  final ToolsSectionGroup group;

  const ToolsSection(this.id, this.label, this.icon, this.group);

  /// 获取指定分组下的全部显示项（按枚举声明顺序）
  static List<ToolsSection> ofGroup(ToolsSectionGroup group) =>
      values.where((s) => s.group == group).toList();

  /// 根据 ID 解析对应区块，未知 ID 回退为书籍信息
  static ToolsSection fromId(String id) =>
      values.firstWhere((s) => s.id == id, orElse: () => ToolsSection.bookInfo);
}

/// 工具面板显示设置面板
///
/// 作为工具面板标题栏"显示设置"按钮的下拉菜单内容，
/// 用于配置功能区（随机取名、敏感词检测）与信息区块（书籍信息、码字统计）的
/// 显示开关与显示顺序。两个区域相互独立，可见项只能在各自区域内拖拽排序，
/// 隐藏项排在可见项下方且不参与拖拽。
/// [functionOrder]、[sectionOrder] 分别为两个区域当前可见项的 ID 顺序列表，
/// 变化时通过对应回调通知父级，由父级负责持久化与重新渲染。
class ToolsDisplaySettings extends StatelessWidget {
  /// 功能区当前可见项的 ID 顺序列表
  final List<String> functionOrder;

  /// 信息区块当前可见项的 ID 顺序列表
  final List<String> sectionOrder;

  /// 功能区顺序/可见性变化回调
  final ValueChanged<List<String>> onFunctionOrderChanged;

  /// 信息区块顺序/可见性变化回调
  final ValueChanged<List<String>> onSectionOrderChanged;

  /// 是否展示功能区配置项
  ///
  /// 码字统计面板不展示功能区，其显示设置中也不提供功能区的配置
  final bool showFunctionGroup;

  /// 菜单内容固定宽度
  static const double _panelWidth = 235.0;

  /// 拖拽手柄宽度（图标 16 + 与区块图标之间的间距 4）
  static const double _dragHandleWidth = 20.0;

  /// 单个配置行的固定高度
  ///
  /// 拖拽列表需要有界高度，行高固定后即可按可见项数量算出列表高度，
  /// 避免在弹出菜单中触发列表视口的内联尺寸测量
  static const double _rowHeight = 36.0;

  const ToolsDisplaySettings({
    super.key,
    required this.functionOrder,
    required this.sectionOrder,
    required this.onFunctionOrderChanged,
    required this.onSectionOrderChanged,
    this.showFunctionGroup = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: _panelWidth,
      // 左侧留白收窄，使拖拽手柄更贴近卡片左边缘
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
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
          // 功能区配置项
          if (showFunctionGroup) ...[
            _buildGroupList(
              context,
              ToolsSectionGroup.function,
              functionOrder,
              onFunctionOrderChanged,
            ),
            // 两个区域之间的淡入淡出分隔线
            _buildGroupDivider(colorScheme),
          ],
          // 信息区块配置项
          _buildGroupList(
            context,
            ToolsSectionGroup.section,
            sectionOrder,
            onSectionOrderChanged,
          ),
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

  /// 构建两个区域之间的分隔线
  ///
  /// 不占满面板宽度，两端渐隐，用于区分功能区与信息区块
  Widget _buildGroupDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.9,
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              gradient: LinearGradient(
                colors: [
                  colorScheme.outlineVariant.withValues(alpha: 0),
                  colorScheme.outlineVariant.withValues(alpha: 0.55),
                  colorScheme.outlineVariant.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建单个分组的配置列表
  ///
  /// 可见项按 [order] 顺序渲染并支持拖拽排序；
  /// 隐藏项排列在可见项下方，不参与拖拽
  Widget _buildGroupList(
    BuildContext context,
    ToolsSectionGroup group,
    List<String> order,
    ValueChanged<List<String>> onChanged,
  ) {
    // 按顺序列表解析出本分组的可见项
    final visibleSections =
        order.map(ToolsSection.fromId).where((s) => s.group == group).toList();
    // 本分组中未开启显示的项
    final hiddenSections =
        ToolsSection.ofGroup(group).where((s) => !order.contains(s.id)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 可见项组成的有界高度拖拽列表（高度按固定行高计算）
        if (visibleSections.isNotEmpty)
          SizedBox(
            height: visibleSections.length * _rowHeight,
            child: ReorderableListView.builder(
              // 不接管父级 PrimaryScrollController，避免与外层菜单的滚动视图冲突
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: visibleSections.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderVisible(oldIndex, newIndex, order, onChanged),
              proxyDecorator: (child, index, animation) {
                // 拖拽中的项目抬升并添加圆角底色
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final elevation =
                        1 + Curves.easeInOut.transform(animation.value) * 6;
                    return Material(
                      elevation: elevation,
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, index) => _buildSectionRow(
                context,
                visibleSections[index],
                order,
                onChanged,
                dragIndex: index,
              ),
            ),
          ),
        for (final section in hiddenSections)
          _buildSectionRow(context, section, order, onChanged),
      ],
    );
  }

  /// 构建单个显示项配置行
  ///
  /// 左侧为拖拽手柄（仅可见项可拖拽），中间为图标与名称，右侧为显示开关。
  /// 隐藏项置灰且不参与拖拽，开关控制其是否在对应区域的显示列表中。
  Widget _buildSectionRow(
    BuildContext context,
    ToolsSection section,
    List<String> order,
    ValueChanged<List<String>> onChanged, {
    int? dragIndex,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isVisible = order.contains(section.id);

    return SizedBox(
      key: ValueKey(section.id),
      height: _rowHeight,
      child: Row(
        children: [
          // 拖拽手柄；隐藏项留出等宽占位以保持对齐
          if (dragIndex != null)
            ReorderableDragStartListener(
              index: dragIndex,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: SizedBox(
                  width: _dragHandleWidth,
                  // 图标靠左对齐，贴向卡片左边缘
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: _dragHandleWidth),
          // 开启显示时图标以主色高亮，关闭时保持常规色
          Icon(
            section.icon,
            size: 16,
            color: isVisible ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
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
          const SizedBox(width: 2),
          // 显示开关
          QwSwitch(
            value: isVisible,
            onChanged: (v) => _toggle(section, v, order, onChanged),
          ),
        ],
      ),
    );
  }

  /// 处理分组内的拖拽排序
  ///
  /// 只在 [order]（当前分组的可见项顺序）内部调整位置，
  /// 拖拽项不会进入其他分组，隐藏项也不参与排序
  void _reorderVisible(
    int oldIndex,
    int newIndex,
    List<String> order,
    ValueChanged<List<String>> onChanged,
  ) {
    // onReorder 的 newIndex 表示"插入到该位置之前"，向下拖动时需先补偿一位
    if (oldIndex < newIndex) newIndex -= 1;
    final newOrder = List<String>.from(order);
    final id = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex, id);
    onChanged(newOrder);
  }

  /// 切换显示项可见性
  ///
  /// 开启时将该 ID 加入对应区域顺序列表末尾，关闭时从列表移除
  void _toggle(
    ToolsSection section,
    bool visible,
    List<String> order,
    ValueChanged<List<String>> onChanged,
  ) {
    final newOrder = List<String>.from(order);
    if (visible) {
      if (!newOrder.contains(section.id)) newOrder.add(section.id);
    } else {
      newOrder.remove(section.id);
    }
    onChanged(newOrder);
  }
}
