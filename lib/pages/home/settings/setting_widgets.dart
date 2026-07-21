import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 设置分组的卡片容器
///
/// 提供统一的现代化外观：扁平化、圆角、细边框、带圆点的标题
/// 卡片内的设置项之间自动渲染不贯穿到图标位置的细分隔线
class SettingSectionCard extends StatelessWidget {
  /// 分组标题
  final String title;

  /// 分组内的设置项
  final List<Widget> children;

  const SettingSectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分组标题：左侧带主色圆点
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: context.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          // 设置项之间渲染细分割线（左缩进与图标后的文字对齐）
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 70),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 现代化风格的设置项
///
/// 提供统一的图标容器、文字层级和点击交互
class SettingTile extends StatelessWidget {
  /// 图标
  final IconData icon;

  /// 标题
  final String title;

  /// 副标题
  final String? subtitle;

  /// 右侧控件（Switch、箭头等）
  final Widget? trailing;

  /// 点击回调
  final VoidCallback? onTap;

  /// 图标强调色，为 null 时使用主题主色
  final Color? accentColor;

  /// 是否启用
  final bool enabled;

  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.accentColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveAccent = accentColor ?? colorScheme.primary;
    final effectiveOpacity = enabled ? 1.0 : 0.4;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // 图标容器：使用强调色的低透明度背景
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: effectiveAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: effectiveAccent,
            ),
          ),
          const SizedBox(width: 14),
          // 标题与副标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.titleLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 右侧控件
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );

    // 禁用或无点击回调时只渲染内容
    if (!enabled || onTap == null) {
      return Opacity(opacity: effectiveOpacity, child: content);
    }

    // 包裹 Material 以便 InkWell 的悬停高亮和水波纹生效
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: content,
      ),
    );
  }
}
