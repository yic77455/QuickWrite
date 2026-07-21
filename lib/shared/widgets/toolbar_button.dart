import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 工具栏按钮组件
///
/// 提供统一的工具栏按钮样式，支持多种尺寸和配置
/// 主要用于工作台各区域的操作按钮

/// 小型工具栏按钮
///
/// 适用于侧边栏操作栏、标签栏等紧凑区域
/// 尺寸：32x28，只有图标，支持 Tooltip 提示
class SmallToolbarButton extends StatelessWidget {
  /// 按钮图标
  final IconData icon;

  /// Tooltip 提示文本
  final String tooltip;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 图标大小，默认 18
  final double iconSize;

  /// 按钮宽度，默认 32
  final double width;

  /// 按钮高度，默认 28
  final double height;

  /// 菜单是否打开，打开时按钮保持按下状态
  final bool isMenuOpen;

  const SmallToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 18,
    this.width = 32,
    this.height = 28,
    this.isMenuOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: Material(
        color: isMenuOpen ? colorScheme.onSurfaceVariant.withValues(alpha: 0.12) : Colors.transparent,
        animationDuration: Duration.zero,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
          highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
          splashColor: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: iconSize, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 大型工具按钮
///
/// 适用于顶部工具栏等功能区
/// 尺寸：56x56，包含图标和文字标签
class LargeToolbarButton extends StatelessWidget {
  /// 按钮图标
  final IconData icon;

  /// 按钮标签
  final String label;

  /// Tooltip 提示文本
  final String tooltip;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 图标大小，默认 22
  final double iconSize;

  /// 按钮尺寸，默认 56
  final double size;

  const LargeToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 28,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: size,
            height: size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize, color: colorScheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(label, style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 格式按钮
///
/// 适用于工具栏格式区（加粗、斜体、下划线等）
/// 尺寸：32x32，只有图标，带背景色
class FormatButton extends StatelessWidget {
  /// 按钮图标
  final IconData icon;

  /// Tooltip 提示文本
  final String tooltip;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 是否选中状态
  final bool isSelected;

  /// 图标大小，默认 18
  final double iconSize;

  /// 按钮尺寸，默认 32
  final double size;

  const FormatButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isSelected = false,
    this.iconSize = 18,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: iconSize, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 开关式工具按钮
///
/// 适用于需要切换状态的按钮（如加粗、斜体、下划线等）
/// 点击时自动切换选中状态，并通过回调通知父组件
///
/// 支持两种模式：
/// - 非受控模式（默认）：通过 [initialValue] 设置初始状态，内部管理切换
/// - 受控模式：传入 [isSelected]（非 null），由外部控制选中状态
class ToggleToolButton extends StatefulWidget {
  /// 按钮图标
  final IconData icon;

  /// Tooltip 提示文本
  final String tooltip;

  /// 选中状态变化回调
  final ValueChanged<bool>? onChanged;

  /// 初始选中状态
  final bool initialValue;

  /// 图标大小，默认 18
  final double iconSize;

  /// 按钮尺寸，默认 32
  final double size;

  /// 外部控制的选中状态
  ///
  /// 非 null 时进入受控模式，按钮状态完全由外部决定，
  /// 点击时仅通过 [onChanged] 通知外部，不自动切换。
  final bool? isSelected;

  const ToggleToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onChanged,
    this.initialValue = false,
    this.iconSize = 18,
    this.size = 32,
    this.isSelected,
  });

  @override
  State<ToggleToolButton> createState() => _ToggleToolButtonState();
}

class _ToggleToolButtonState extends State<ToggleToolButton> {
  late bool _isSelected;

  @override
  void initState() {
    super.initState();
    _isSelected = widget.isSelected ?? widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant ToggleToolButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 受控模式下同步外部状态
    if (widget.isSelected != null && widget.isSelected != _isSelected) {
      _isSelected = widget.isSelected!;
    }
  }

  /// 当前选中状态：受控模式用外部值，非受控模式用内部值
  bool get _currentSelected => widget.isSelected ?? _isSelected;

  void _handleTap() {
    final newValue = !_currentSelected;
    // 非受控模式才更新内部状态
    if (widget.isSelected == null) {
      setState(() {
        _isSelected = newValue;
      });
    }
    widget.onChanged?.call(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _currentSelected;

    return CursorTooltipTarget(
      tooltipContent: Text(widget.tooltip),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              // color: _isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 开关式大型工具按钮
///
/// 适用于需要切换状态的大型按钮（如布局、排版、其他设置按钮）
/// 支持外部控制选中状态，点击时触发回调
/// 选中时有视觉反馈（背景色和图标颜色变化）
class ToggleLargeToolbarButton extends StatelessWidget {
  /// 按钮图标
  final IconData icon;

  /// 按钮标签
  final String label;

  /// Tooltip 提示文本
  final String tooltip;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 是否选中状态
  final bool isSelected;

  /// 图标大小，默认 28
  final double iconSize;

  /// 按钮尺寸，默认 60
  final double size;

  const ToggleLargeToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onPressed,
    this.isSelected = false,
    this.iconSize = 28,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            width: size,
            height: size,
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              // 选中时显示背景色
              color: isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: iconSize,
                  // 选中时图标颜色变化
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: context.bodySmall?.copyWith(
                    // 选中时文字颜色变化
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
