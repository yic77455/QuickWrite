import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/window_provider.dart';
import 'package:window_manager/window_manager.dart';

/// 自定义标题栏组件
/// 
/// - 支持标题栏的拖拽移动
/// - 包含最小化、最大化、关闭按钮
/// - 可自定义标题、左侧按钮、右侧操作区、高度、居中等
class AppTitleBar extends StatefulWidget implements PreferredSizeWidget {
  // 必须实现 PreferredSizeWidget，告诉 Scaffold 这个顶部栏有多高
  // 封装 AppBar 不能简单地继承 StatefulWidget，必须同时实现 PreferredSizeWidget 接口，否则 Scaffold 的 appBar 属性不认识它
  final Widget? title;
  final Widget? leading;
  final bool? centerTitle;
  final double? height;
  final List<Widget>? actions;
  
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
  @override
  Widget build(BuildContext context) {
    // 使用 context.watch 监听 WindowProvider 的变化
    // 当窗口状态改变时，会自动重新构建此组件
    final windowProvider = context.watch<WindowProvider>();

    return AppBar(
      // 1. 全局生效的拖拽区域
      flexibleSpace: const DragToMoveArea(child: SizedBox.expand()),

      // 2. 接收外部传入的标题和按钮
      leading: widget.leading,
      title: widget.title != null
          ? IgnorePointer(child: widget.title) // 忽略并穿透手势
          : null,
      centerTitle: widget.centerTitle ?? false, // 是否居中，桌面端标题通常靠左
      // 3. 右侧操作区：外部传入的 actions + 固定的窗口控制按钮
      actions: [
        if (widget.actions != null)
          ...widget
              .actions!, // 如果外部传了其他按钮，先渲染它们（...是扩展操作符 ：将一个列表中的所有元素展开并插入到另一个列表中）
        // 固定的系统窗口按钮
        // （WindowCaptionButton 是 window_manager 库提供的）
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
