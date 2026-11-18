import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:window_manager/window_manager.dart';

/// 自定义标题栏组件
/// 
/// - 支持标题栏的拖拽移动
/// - 包含最小化、最大化、关闭按钮
/// - 可自定义标题、左侧按钮、右侧操作区、高度、居中、左侧区域宽度与标题间距
class AppTitleBar extends StatefulWidget implements PreferredSizeWidget {
  // 必须实现 PreferredSizeWidget，告诉 Scaffold 这个顶部栏有多高
  // 封装 AppBar 不能简单地继承 StatefulWidget，必须同时实现 PreferredSizeWidget 接口，否则 Scaffold 的 appBar 属性不认识它
  final Widget? title;
  final Widget? leading;
  final bool? centerTitle;
  final double? height;
  final List<Widget>? actions;

  /// 左侧区域宽度（为 null 时使用 AppBar 默认值）
  final double? leadingWidth;

  /// 标题与左侧区域之间的间距（为 null 时使用 AppBar 默认值）
  final double? titleSpacing;
  
  /// 是否显示最小化按钮（默认 true）
  final bool showMinimize;
  
  /// 是否显示最大化按钮（默认 true）
  final bool showMaximize;

  const AppTitleBar({
    super.key,
    this.title,
    this.leading,
    this.centerTitle,
    this.height,
    this.actions,
    this.leadingWidth,
    this.titleSpacing,
    this.showMinimize = true,
    this.showMaximize = true,
  });

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();

  // 返回标题栏的高度 (如果没有设置则返回标准的 Toolbar 高度 通常是56.0)
  @override
  Size get preferredSize => Size.fromHeight(height ?? kToolbarHeight);
}

// 使用 Provider 管理窗口状态，不再需要混入 WindowListener
// 窗口监听逻辑现在由 WindowProvider 统一管理
class _AppTitleBarState extends State<AppTitleBar> {
  /// macOS 红绿灯占用的左侧宽度
  static const double _macTrafficLightWidth = 84;

  /// macOS 上标题栏内容的垂直偏移
  static const double _macTitleVerticalOffset = -4;

  /// macOS 红绿灯与 LOGO 之间分隔线的位置与尺寸
  static const double _macDividerLeft = _macTrafficLightWidth - 4;
  static const double _macDividerHeight = 20;

  @override
  Widget build(BuildContext context) {
    // 使用 context.watch 监听 WindowProvider 的变化
    // 当窗口状态改变时，会自动重新构建此组件
    final windowProvider = context.watch<WindowProvider>();
    final bool isMacOS = PlatformCapabilities.isMacOS;

    // macOS 的窗口控制由系统红绿灯按钮提供，无需自绘窗口按钮
    final bool showCaptionButtons =
        !isMacOS && PlatformCapabilities.supportsNativeWindowControl;

    // macOS 在左侧预留红绿灯按钮的空间，并把标题栏内容上移到与红绿灯对齐
    final Widget baseLeading = Padding(
      padding: const EdgeInsets.only(left: _macTrafficLightWidth),
      child: Transform.translate(
        offset: const Offset(0, _macTitleVerticalOffset),
        child: widget.leading ?? const SizedBox.shrink(),
      ),
    );

    // 分隔线只在标题栏确有内容时显示
    final bool showMacDivider = widget.leading != null || widget.title != null;

    // 分隔线用 Stack 绝对定位叠加，不占布局宽度
    final Widget? effectiveLeading = isMacOS
        ? Stack(
            children: [
              baseLeading,
              if (showMacDivider)
                Positioned(
                  left: _macDividerLeft,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: Transform.translate(
                    offset: const Offset(0, _macTitleVerticalOffset),
                    child: Center(
                      child: Container(
                        width: 1,
                        height: _macDividerHeight,
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
            ],
          )
        : widget.leading;
    final double? effectiveLeadingWidth = isMacOS
        ? _macTrafficLightWidth + (widget.leadingWidth ?? kToolbarHeight)
        : widget.leadingWidth;

    return AppBar(
      // 1. 全局生效的拖拽区域（拖动移动窗口依赖原生窗口，仅在支持原生窗口控制的平台启用）
      flexibleSpace: PlatformCapabilities.supportsNativeWindowControl
          ? const DragToMoveArea(child: SizedBox.expand())
          : null,

      // 2. 接收外部传入的标题和按钮
      leading: effectiveLeading,
      leadingWidth: effectiveLeadingWidth,
      titleSpacing: widget.titleSpacing,
      title: widget.title != null
          ? IgnorePointer(
              // macOS 上标题与红绿灯对齐：同样上移，保持与 leading 一致
              child: isMacOS
                  ? Transform.translate(
                      offset: const Offset(0, _macTitleVerticalOffset),
                      child: widget.title,
                    )
                  : widget.title,
            ) // 忽略并穿透手势
          : null,
      centerTitle: widget.centerTitle ?? false, // 是否居中，桌面端标题通常靠左
      // 3. 右侧操作区：外部传入的 actions + 固定的窗口控制按钮
      actions: [
        if (widget.actions != null)
          ...widget
              .actions!, // 如果外部传了其他按钮，先渲染它们（...是扩展操作符 ：将一个列表中的所有元素展开并插入到另一个列表中）
        // 固定的系统窗口按钮（依赖原生窗口，仅在支持原生窗口控制的平台显示）
        // macOS 由系统红绿灯按钮承担窗口控制，这里不再重复绘制
        // （WindowCaptionButton 是 window_manager 库提供的）
        if (showCaptionButtons)
          Row(
            mainAxisSize: MainAxisSize.min, // 紧凑布局
            children: [
              // 最小化按钮（可选）
              if (widget.showMinimize)
                WindowCaptionButton.minimize(
                  brightness: Theme.of(context).brightness,
                  onPressed: () => windowProvider.minimize(),
                ),

              // 最大化/恢复按钮（可选）
              if (widget.showMaximize) ...[
                if (windowProvider.isMaximized)
                  WindowCaptionButton.unmaximize(
                    // 恢复按钮
                    brightness: Theme.of(context).brightness,
                    onPressed: () => windowProvider.unmaximize(),
                  )
                else
                  WindowCaptionButton.maximize(
                    // 最大化按钮
                    brightness: Theme.of(context).brightness,
                    onPressed: () => windowProvider.maximize(),
                  ),
              ],

              // 关闭按钮（始终显示）
              WindowCaptionButton.close(
                brightness: Theme.of(context).brightness,
                onPressed: () => windowProvider.close(),
              ),
            ],
          ),
      ],
    );
  }
}
