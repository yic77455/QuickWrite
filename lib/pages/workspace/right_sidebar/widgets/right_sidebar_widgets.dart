import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_switch.dart';

/// 右侧边栏设置分组容器
/// 
/// 用于将相关的设置项组织在一起，显示标题和图标
class SettingsSection extends StatelessWidget {
  /// 分组标题
  final String title;
  
  /// 分组图标
  final IconData icon;
  
  /// 分组内的子组件列表
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题行：图标 + 文字标题
        Row(
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: context.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 设置项容器：圆角背景 + 子组件列表
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// 开关类型的设置项
/// 
/// 显示图标、标签和 Switch 控件
class SwitchSettingItem extends StatelessWidget {
  /// 设置项图标
  final IconData icon;
  
  /// 设置项标签文字
  final String label;
  
  /// 当前开关状态
  final bool value;
  
  /// 是否可用（默认为 true）
  final bool enabled;
  
  /// 状态改变回调
  final ValueChanged<bool> onChanged;

  const SwitchSettingItem({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // 左侧图标（根据 enabled 状态调整透明度）
          Icon(
            icon,
            size: 18,
            color: enabled 
                ? colorScheme.onSurfaceVariant 
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
          ),
          const SizedBox(width: 10),
          // 中间标签文字（自动填充剩余空间）
          Expanded(
            child: Text(
              label,
              style: context.titleSmall?.copyWith(
                color: enabled 
                    ? colorScheme.onSurface 
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // 右侧开关控件
          QwSwitch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

/// 滑块类型的设置项
/// 
/// 显示图标、标签、当前数值和 Slider 控件
class SliderSettingItem extends StatelessWidget {
  /// 设置项图标
  final IconData icon;
  
  /// 设置项标签文字
  final String label;
  
  /// 当前滑块值
  final double value;
  
  /// 最小值
  final double min;
  
  /// 最大值
  final double max;
  
  /// 刻度间隔数
  final int divisions;
  
  /// 数值单位（如 'px'、'倍'、'字符'）
  final String unit;
  
  /// 小数位数（默认为 1）
  final int decimalPlaces;
  
  /// 值改变回调
  final ValueChanged<double> onChanged;

  const SliderSettingItem({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    this.decimalPlaces = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：图标 + 标签 + 当前数值显示
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                label,
                style: context.titleSmall?.copyWith(color: colorScheme.onSurface),
              ),
              const Spacer(),
              // 当前数值标签（带背景色）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${value.toStringAsFixed(decimalPlaces)}$unit',
                  style: context.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 第二行：滑块控件（自定义主题样式）
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置项之间的分隔线
/// 
/// 用于在同一个 SettingsGroup 内部区分不同的设置项
class SettingDivider extends StatelessWidget {
  const SettingDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
    );
  }
}

/// 颜色指示器组件
///
/// 显示一个圆形颜色预览，悬停时有缩放动画效果
class ColorIndicator extends StatefulWidget {
  /// 显示的颜色
  final Color color;

  const ColorIndicator({super.key, required this.color});

  @override
  State<ColorIndicator> createState() => _ColorIndicatorState();
}

class _ColorIndicatorState extends State<ColorIndicator> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}


/// 通用设置项（暂时只用于显示颜色指示器）
/// 
/// 显示图标、标签和右侧内容，可点击
class SettingItem extends StatelessWidget {
  /// 设置项图标
  final IconData icon;
  
  /// 设置项标签文字
  final String label;
  
  /// 右侧显示的内容
  final Widget trailing;
  
  /// 点击回调
  final VoidCallback onTap;

  const SettingItem({
    super.key,
    required this.icon,
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 左侧图标
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            // 中间标签文字
            Expanded(
              child: Text(
                label,
                style: context.titleSmall?.copyWith(color: colorScheme.onSurface),
              ),
            ),
            // 右侧内容
            trailing,
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// 带悬停效果的备份记录项
///
/// 鼠标悬停时显示高亮背景，点击时打开预览窗口
/// 当鼠标悬停在按钮区域时，取消记录项的悬停效果
class HoverableBackupItem extends StatefulWidget {
  /// 点击时打开预览
  final VoidCallback onPreview;

  /// 是否被选中
  final bool isSelected;

  /// 子组件
  final Widget child;

  const HoverableBackupItem({required this.onPreview, this.isSelected = false, required this.child, super.key});

  @override
  State<HoverableBackupItem> createState() => _HoverableBackupItemState();
}

class _HoverableBackupItemState extends State<HoverableBackupItem> {
  /// 是否处于悬停状态
  bool _isHovered = false;

  /// 鼠标是否在按钮区域
  bool _isOnButtonArea = false;

  /// 记录项是否应该显示悬停效果
  bool get _shouldShowHover => _isHovered && !_isOnButtonArea;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 确定背景色：选中 > 悬停 > 默认
    Color bgColor;
    if (widget.isSelected) {
      bgColor = colorScheme.primary.withValues(alpha: 0.12);
    } else if (_shouldShowHover) {
      bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    } else {
      bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onPreview,
        behavior: HitTestBehavior.translucent,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: NotificationListener<ButtonHoverNotification>(
            onNotification: (notification) {
              setState(() => _isOnButtonArea = notification.isHovered);
              return true;
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 按钮悬停状态通知
///
/// 当鼠标进入/离开按钮区域时发送，通知父级取消记录项的悬停效果
class ButtonHoverNotification extends Notification {
  /// 是否处于悬停状态
  final bool isHovered;

  ButtonHoverNotification(this.isHovered);
}

/// 带悬停效果的操作按钮
///
/// 悬停时显示背景高亮，同时通过通知机制告知父级取消记录项的悬停效果
class HoverableActionButton extends StatefulWidget {
  /// 按钮颜色
  final Color color;

  /// 点击回调
  final VoidCallback onTap;

  /// 子组件
  final Widget child;

  const HoverableActionButton({required this.color, required this.onTap, required this.child, super.key});

  @override
  State<HoverableActionButton> createState() => _HoverableActionButtonState();
}

class _HoverableActionButtonState extends State<HoverableActionButton> {
  /// 是否处于悬停状态
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        ButtonHoverNotification(true).dispatch(context);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        ButtonHoverNotification(false).dispatch(context);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _isHovered ? widget.color.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
