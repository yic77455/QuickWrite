import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/constants.dart';

/// 纸张容器
///
/// 在纸张模式下将子组件约束为 A4 纸宽度，并叠加纸张背景色与投影效果，
/// 让内容呈现出独立的纸页视觉。
/// 未开启纸张模式时仍施加纸张背景色，但不约束宽度、不加投影。
class PaperContainer extends StatelessWidget {

  /// 是否开启纸张模式
  final bool enabled;

  /// 顶边距保护高度
  ///
  /// 用于查找替换浮窗出现时在内容顶部留出空白，防止浮窗遮挡文字。
  /// 纸张模式下此高度位于纸张之外，不会撑高纸张；非纸张模式下位于背景色之内。
  final double topPadding;

  /// 子组件
  final Widget child;

  const PaperContainer({
    super.key,
    required this.enabled,
    required this.child,
    this.topPadding = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // 顶边距保护组件，仅在 topPadding > 0 时生成
    final Widget topPaddingWidget =
        topPadding > 0 ? SizedBox(height: topPadding) : const SizedBox.shrink();

    // 纸张模式未开启：施加纸张背景色，顶边距在背景色之内
    if (!enabled) {
      return ColoredBox(
        color: colorScheme.surfaceContainerLowest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [topPaddingWidget, child],
        ),
      );
    }

    // 纸张模式开启：顶边距位于纸张之外，不撑高纸张；纸张水平居中并叠加投影
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        topPaddingWidget,
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: GlobalConstants.paperTopMargin),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: GlobalConstants.a4Width,
                minHeight: GlobalConstants.a4Height,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
