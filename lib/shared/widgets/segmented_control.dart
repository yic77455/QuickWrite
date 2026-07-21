import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 分段选择器组件
///
/// 类似 iOS 的 UISegmentedControl，用于在多个选项之间切换
/// 支持滑动指示器动画效果
class SegmentedControl extends StatefulWidget {
  /// 选项标签列表
  final List<String> labels;

  /// 当前选中的索引
  final int selectedIndex;

  /// 选中项改变回调
  final ValueChanged<int>? onChanged;

  /// 是否禁用
  final bool disabled;

  /// 高度
  final double height;

  /// 圆角半径
  final double borderRadius;

  const SegmentedControl({
    required this.labels,
    required this.selectedIndex,
    this.onChanged,
    this.disabled = false,
    this.height = 32,
    this.borderRadius = 8,
    super.key,
  });

  @override
  State<SegmentedControl> createState() => _SegmentedControlState();
}

class _SegmentedControlState extends State<SegmentedControl> {
  /// 当前悬浮的按钮索引
  int? _hoveredIndex;
  
  /// 是否应该使用动画（只在选中项变化时使用）
  bool _shouldAnimate = false;
  
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(SegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有当选中索引变化时才启用动画
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      setState(() {
        _shouldAnimate = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = widget.labels.length;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final segmentWidth = totalWidth / count;

          // 计算动画的目标位置
          final targetLeft = widget.selectedIndex * segmentWidth;

          return Stack(
            children: [
              // 底层：所有分段按钮的背景
              Row(
                children: List.generate(count, (index) {
                  return Expanded(
                    child: Container(
                      color: Colors.transparent,
                    ),
                  );
                }),
              ),
              // 中层：滑动指示器（选中项的白色背景）
              // 使用 AnimatedPositioned 或 Positioned 根据是否需要动画
              AnimatedPositioned(
                duration: _shouldAnimate ? const Duration(milliseconds: 300) : Duration.zero,
                curve: Curves.easeInOut,
                left: targetLeft,
                top: 2,
                width: segmentWidth,
                height: widget.height - 4,
                onEnd: () {
                  // 动画结束后禁用动画，避免宽度变化时触发动画
                  // 使用 addPostFrameCallback 确保在当前帧构建完成后更新状态
                  // 避免在 build 阶段调用 setState 导致错误
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _shouldAnimate = false;
                      });
                    }
                  });
                },
                child: _buildIndicator(colorScheme),
              ),
              // 顶层：所有分段按钮的文字
              ...List.generate(count, (index) {
                final isSelected = widget.selectedIndex == index;
                final isHovered = _hoveredIndex == index;

                return Positioned(
                  left: index * segmentWidth,
                  width: segmentWidth,
                  top: 0,
                  height: widget.height,
                  child: _buildSegmentButton(
                    label: widget.labels[index],
                    isSelected: isSelected,
                    isHovered: isHovered && !isSelected,
                    colorScheme: colorScheme,
                    onEnter: () {
                      if (!widget.disabled && !isSelected) {
                        setState(() => _hoveredIndex = index);
                      }
                    },
                    onExit: () {
                      if (_hoveredIndex == index) {
                        setState(() => _hoveredIndex = null);
                      }
                    },
                    onTap: () {
                      if (!widget.disabled && !isSelected) {
                        widget.onChanged?.call(index);
                      }
                    },
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  /// 构建滑动指示器
  Widget _buildIndicator(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(widget.borderRadius - 2),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

  /// 构建单个分段按钮
  Widget _buildSegmentButton({
    required String label,
    required bool isSelected,
    required bool isHovered,
    required ColorScheme colorScheme,
    required VoidCallback onEnter,
    required VoidCallback onExit,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius - 2),
          child: Container(
            alignment: Alignment.center,
            color: isHovered
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
                : Colors.transparent,
            child: Text(
              label,
              style: context.titleSmall?.copyWith(
                color: widget.disabled
                    ? colorScheme.onSurface.withValues(alpha: 0.3)
                    : isSelected
                        ? colorScheme.onSurface
                        : isHovered
                            ? colorScheme.onSurface.withValues(alpha: 0.8)
                            : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
