import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 分组标题组件
///
/// 用于章节分卷、设定分类等可展开/折叠的分组标题
/// 支持悬停时将子项数量替换为菜单按钮
class GroupHeader extends StatefulWidget {
  /// 分组名称
  final String title;

  /// 分组图标
  final IconData? icon;

  /// 子项数量
  final int itemCount;

  /// 是否展开
  final bool isExpanded;

  /// 点击回调
  final VoidCallback? onTap;

  /// 子项数量显示文本（如"章"、"项"等），为空则不显示数量
  final String? itemCountSuffix;

  /// 右侧操作按钮
  final Widget? trailing;

  /// 悬停时显示的菜单按钮回调，提供此回调后悬停时子项数量会替换为菜单按钮
  /// 回调参数为菜单按钮的 BuildContext，用于定位弹出菜单
  final void Function(BuildContext)? onMenuPressed;

  /// 菜单按钮是否处于打开状态（用于保持分组标题按下效果）
  final bool isMenuOpen;

  /// 菜单按钮是否处于按下状态（仅通过按钮打开菜单时为 true，右键菜单时为 false）
  final bool isButtonPressed;

  /// 悬停时显示的新建按钮回调，提供此回调后悬停时在菜单按钮左侧显示新建按钮
  final VoidCallback? onAddPressed;

  /// 新建按钮的提示文本
  final String? addTooltip;

  /// 菜单按钮的提示文本
  final String? menuTooltip;

  /// 右键点击回调
  final void Function(TapDownDetails)? onSecondaryTapDown;

  const GroupHeader({
    required this.title,
    this.icon,
    required this.itemCount,
    required this.isExpanded,
    this.onTap,
    this.itemCountSuffix,
    this.trailing,
    this.onMenuPressed,
    this.isMenuOpen = false,
    this.isButtonPressed = false,
    this.onAddPressed,
    this.addTooltip,
    this.menuTooltip,
    this.onSecondaryTapDown,
    super.key,
  });

  @override
  State<GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<GroupHeader> {
  /// 鼠标是否悬停在分组标题上
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 判断是否应该显示菜单按钮（悬停时或菜单打开时）
    final showMenuButton =
        widget.onMenuPressed != null && (_isHovered || widget.isMenuOpen);
    // 判断是否应该显示新建按钮（悬停时或菜单打开时）
    final showAddButton = widget.onAddPressed != null && (_isHovered || widget.isMenuOpen);
    // 是否显示悬停操作按钮区域
    final showHoverActions = showMenuButton || showAddButton;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Material(
          color: widget.isExpanded
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: widget.onTap,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: widget.isMenuOpen
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  // 展开/折叠图标
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 分组图标
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 分组名称
                  Expanded(
                    child: Text(
                      widget.title,
                      style: context.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 子项数量或悬停操作按钮
                  if (showHoverActions) ...[
                    // 新建按钮
                    if (showAddButton)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CursorTooltipTarget(
                            tooltipContent: Text(widget.addTooltip ?? ''),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(28),
                              child: InkWell(
                                onTap: widget.onAddPressed,
                                hoverColor: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.08),
                                highlightColor: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.12),
                                splashColor: Colors.transparent,
                                borderRadius: BorderRadius.circular(28),
                                child: Center(
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 菜单按钮
                    if (showMenuButton)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Builder(
                            builder: (buttonContext) {
                              return CursorTooltipTarget(
                                tooltipContent: Text(widget.menuTooltip ?? ''),
                                child: Material(
                                  color: widget.isButtonPressed
                                      ? colorScheme.onSurfaceVariant.withValues(
                                          alpha: 0.12,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(28),
                                  animationDuration: Duration.zero,
                                  child: InkWell(
                                    onTap: () => widget.onMenuPressed?.call(
                                      buttonContext,
                                    ),
                                    hoverColor: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.08),
                                    highlightColor: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.12),
                                    splashColor: Colors.transparent,
                                    borderRadius: BorderRadius.circular(28),
                                    child: Center(
                                      child: Icon(
                                        Icons.more_vert_rounded,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ] else if (widget.itemCountSuffix != null &&
                      widget.itemCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${widget.itemCount}${widget.itemCountSuffix}',
                        style: context.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ),
                  // 右侧操作按钮
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 吸顶分组标题的 SliverPersistentHeaderDelegate
///
/// 用于在滚动时将分组标题固定在视口顶部，使当前分组始终可见
class StickyGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  /// 子组件
  final Widget child;

  /// 标题高度
  final double height;

  StickyGroupHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final colorScheme = Theme.of(context).colorScheme;
    // 使用不透明背景色，避免滚动内容从吸顶标题下方透出
    return ColoredBox(
      color: colorScheme.surface,
      child: child,
    );
  }

  @override
  bool shouldRebuild(StickyGroupHeaderDelegate oldDelegate) => true;
}

/// 序号标签组件
///
/// 用于显示章节序号等，框大小固定，数字自适应缩放
class IndexBadge extends StatelessWidget {
  /// 序号文本
  final String text;

  /// 是否选中
  final bool isSelected;

  const IndexBadge({required this.text, this.isSelected = false, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 固定框的大小
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.15)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      // 使用 FittedBox 让数字自适应缩放
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            text,
            style: context.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表项组件
///
/// 通用的列表项，支持序号、标题、副标题、操作按钮等
class ListItem extends StatelessWidget {
  /// 序号文本
  final String? indexText;

  /// 标题
  final String title;

  /// 副标题
  final String? subtitle;

  /// 是否选中
  final bool isSelected;

  /// 是否按下（菜单打开时锁定按下状态）
  final bool isPressed;

  /// 左侧缩进
  final double leftIndent;

  /// 点击回调
  final VoidCallback? onTap;

  /// 右键点击回调
  final void Function(TapDownDetails)? onSecondaryTapDown;

  /// 右侧操作按钮
  final Widget? trailing;

  /// 左侧图标（替代序号）
  final Widget? leading;

  const ListItem({
    this.indexText,
    required this.title,
    this.subtitle,
    this.isSelected = false,
    this.isPressed = false,
    this.leftIndent = 8,
    this.onTap,
    this.onSecondaryTapDown,
    this.trailing,
    this.leading,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 1, bottom: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: EdgeInsets.only(left: leftIndent, right: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : isPressed
                  ? colorScheme.onSurfaceVariant.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // 左侧：序号或图标
                if (leading != null)
                  leading!
                else if (indexText != null)
                  IndexBadge(text: indexText!, isSelected: isSelected),
                const SizedBox(width: 8),
                // 中间：标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: context.titleSmall?.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: context.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // 右侧：操作按钮
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
