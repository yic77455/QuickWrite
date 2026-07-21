import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/shared/widgets/toolbar_button.dart';

/// 大纲编辑器顶部工具栏
///
/// 提供展开全部、折叠全部、添加节点等操作入口
class OutlineEditorTopBar extends StatelessWidget {
  /// 工具栏高度（垂直 padding 8*2 + 图标按钮 32）
  ///
  /// 供外部组件（如查找替换浮窗）计算避让偏移量使用
  static const double height = 48.0;

  /// 颜色方案
  final ColorScheme colorScheme;

  /// 是否只读（只读时禁用添加节点按钮）
  final bool readOnly;

  /// 展开全部节点回调
  final VoidCallback onExpandAll;

  /// 折叠全部节点回调
  final VoidCallback onCollapseAll;

  /// 添加根节点回调
  final VoidCallback onAddRoot;

  const OutlineEditorTopBar({
    super.key,
    required this.colorScheme,
    required this.readOnly,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onAddRoot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        // border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          // 标题
          Icon(Icons.account_tree_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('大纲编辑器', style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          // 展开全部
          _buildIconButton(icon: Icons.unfold_more_rounded, tooltip: '展开全部', onTap: onExpandAll),
          // 折叠全部
          _buildIconButton(icon: Icons.unfold_less_rounded, tooltip: '折叠全部', onTap: onCollapseAll),
          const SizedBox(width: 4),
          // 添加根节点
          _buildIconButton(icon: Icons.add_rounded, tooltip: '添加节点', onTap: onAddRoot, enabled: !readOnly),
        ],
      ),
    );
  }

  /// 构建工具栏图标按钮
  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final color = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3);

    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// 大纲编辑器空状态
///
/// 无任何节点时显示的占位提示
class OutlineEditorEmptyState extends StatelessWidget {
  /// 颜色方案
  final ColorScheme colorScheme;

  const OutlineEditorEmptyState({super.key, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('暂无大纲内容', style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '点击右上角 + 添加节点',
            style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 大纲编辑器底部快捷键提示
///
/// 展示常用快捷键及其功能说明
class OutlineEditorBottomHint extends StatelessWidget {
  /// 颜色方案
  final ColorScheme colorScheme;

  const OutlineEditorBottomHint({super.key, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        // 将半透明背景色与编辑器背景预混合为不透明颜色，保持视觉颜色不变的同时避免透出下方滚动内容
        color: Color.alphaBlend(
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          colorScheme.surfaceContainerLowest,
        ),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _buildShortcutHint('Enter', '新建同级', colorScheme),
          _buildShortcutHint('Tab', '缩进', colorScheme),
          _buildShortcutHint('Shift+Tab', '反缩进', colorScheme),
          _buildShortcutHint('Ctrl+Enter', '完成', colorScheme),
          _buildShortcutHint('↑↓', '切换节点', colorScheme),
          _buildShortcutHint('Ctrl+A', '全选', colorScheme),
        ],
      ),
    );
  }

  /// 构建单个快捷键提示
  Widget _buildShortcutHint(String key, String desc, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Text(
            key,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(width: 4),
        Text(desc, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
      ],
    );
  }
}

/// 测量子节点尺寸并通过回调上报的组件
///
/// 在子节点完成布局后，将其实际尺寸通过 [onSizeChanged] 回调上报，
/// 适用于需要根据子节点动态尺寸调整其他布局（如内边距）的场景。
class MeasureSize extends SingleChildRenderObjectWidget {
  /// 尺寸变化回调
  final void Function(Size size) onSizeChanged;

  const MeasureSize({super.key, super.child, required this.onSizeChanged});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onSizeChanged: onSizeChanged);
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderMeasureSize).onSizeChanged = onSizeChanged;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize({required this.onSizeChanged});

  /// 当前绑定的尺寸变化回调
  void Function(Size size) onSizeChanged;

  /// 上一次记录的尺寸，用于判断是否发生变化
  Size _lastSize = Size.zero;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _lastSize) {
      _lastSize = size;
      // 延迟到下一帧回调，避免在布局阶段触发重建
      SchedulerBinding.instance.addPostFrameCallback((_) {
        onSizeChanged(size);
      });
    }
  }
}

/// 标题级别单选组件
///
/// 在右键菜单中以单选方式切换标题级别（H1/H2/H3/T），
/// 选中后立即将对应级别写入所有目标节点并触发编辑器重建。
class HeadingLevelSelector extends StatefulWidget {
  /// 目标节点列表（支持节点选区批量操作）
  final List<OutlineNode> nodes;

  /// 级别变化回调
  final ValueChanged<int> onLevelChanged;

  const HeadingLevelSelector({
    super.key,
    required this.nodes,
    required this.onLevelChanged,
  });

  @override
  State<HeadingLevelSelector> createState() => _HeadingLevelSelectorState();
}

class _HeadingLevelSelectorState extends State<HeadingLevelSelector> {
  /// 当前选中的标题级别（0=正文, 1=H1, 2=H2, 3=H3）
  ///
  /// 多节点时取所有节点的公共级别，不一致则为 -1（无选中）。
  late int _selectedLevel;

  @override
  void initState() {
    super.initState();
    _selectedLevel = _computeCommonLevel();
  }

  @override
  void didUpdateWidget(covariant HeadingLevelSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 目标节点列表变化时重新计算公共级别
    if (oldWidget.nodes != widget.nodes) {
      _selectedLevel = _computeCommonLevel();
    }
  }

  /// 计算所有目标节点的公共标题级别
  ///
  /// 所有节点级别一致时返回该级别，否则返回 -1 表示不一致。
  int _computeCommonLevel() {
    if (widget.nodes.isEmpty) return -1;
    final first = widget.nodes.first.headingLevel;
    final allSame = widget.nodes.every((n) => n.headingLevel == first);
    return allSame ? first : -1;
  }

  /// 选择指定级别
  void _select(int level) {
    if (level == _selectedLevel) return;
    setState(() {
      _selectedLevel = level;
    });
    widget.onLevelChanged(level);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ToggleToolButton(
          icon: MaterialIcons.format_h1,
          tooltip: '一级标题',
          iconSize: 22,
          isSelected: _selectedLevel == 1,
          onChanged: (selected) { if (selected) _select(1); },
        ),
        ToggleToolButton(
          icon: MaterialIcons.format_h2,
          tooltip: '二级标题',
          iconSize: 22,
          isSelected: _selectedLevel == 2,
          onChanged: (selected) { if (selected) _select(2); },
        ),
        ToggleToolButton(
          icon: MaterialIcons.format_h3,
          tooltip: '三级标题',
          iconSize: 22,
          isSelected: _selectedLevel == 3,
          onChanged: (selected) { if (selected) _select(3); },
        ),
        ToggleToolButton(
          icon: MaterialIcons.format_title,
          tooltip: '正文',
          isSelected: _selectedLevel == 0,
          onChanged: (selected) { if (selected) _select(0); },
        ),
      ],
    );
  }
}
