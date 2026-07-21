import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';

/// 左侧边栏展开按钮组件
/// 
/// 当左侧边栏收起时显示在左侧边缘，点击后展开左侧边栏
class LeftSidebarExpandButton extends StatefulWidget {
  const LeftSidebarExpandButton({super.key});

  @override
  State<LeftSidebarExpandButton> createState() => LeftSidebarExpandButtonState();
}

class LeftSidebarExpandButtonState extends State<LeftSidebarExpandButton> {
  /// 鼠标是否悬停在按钮上
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      // 鼠标进入时更新悬停状态
      onEnter: (_) => setState(() => _isHovered = true),
      // 鼠标离开时更新悬停状态
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          // 展开左侧边栏
          context.read<WorkspaceProvider>().setLeftSidebarExpanded(true);
        },
        child: AnimatedContainer(
          width: 18,
          height: 100,
          duration: const Duration(milliseconds: 100),
          // 半透明背景，默认较淡，悬停时加深
          decoration: BoxDecoration(
            color: _isHovered
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.95)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
            // 右边框增强视觉提示，悬停时加粗变明显
            border: Border(
              right: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: _isHovered ? 0.3 : 0.1),
                width: _isHovered ? 1.5 : 1,
              ),
            ),
          ),
          child: Center(
            child: AnimatedOpacity(
              opacity: _isHovered ? 0.8 : 0.6,
              duration: const Duration(milliseconds: 100),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}