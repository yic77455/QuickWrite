import 'package:flutter/material.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 带悬浮效果的图标按钮
///
/// 悬浮时显示背景色，用于回收站列表项的恢复/彻底删除等操作
class HoverIconButton extends StatelessWidget {
  /// 图标
  final IconData icon;

  /// 提示文本
  final String tooltip;

  /// 图标颜色
  final Color color;

  /// 悬浮时的背景色
  final Color hoverBackgroundColor;

  /// 点击回调
  final VoidCallback onPressed;

  /// 是否禁用
  final bool isDisabled;

  const HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.hoverBackgroundColor,
    required this.onPressed,
    this.isDisabled = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // 禁用时降低透明度
    final effectiveColor = isDisabled
        ? color.withValues(alpha: 0.3)
        : color;

    return CursorTooltipTarget(
      tooltipContent: Text(tooltip),
      child: InkWell(
        onTap: isDisabled ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        hoverColor: isDisabled ? Colors.transparent : hoverBackgroundColor,
        splashColor: isDisabled ? Colors.transparent : hoverBackgroundColor.withValues(alpha: 0.3),
        highlightColor: isDisabled ? Colors.transparent : hoverBackgroundColor.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: effectiveColor,
          ),
        ),
      ),
    );
  }
}
