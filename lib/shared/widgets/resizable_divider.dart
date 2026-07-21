import 'package:flutter/material.dart';

/// 可拖拽调整宽度的分隔条组件
/// 
/// 用于侧边栏和主内容区之间的分隔，支持拖拽调整侧边栏宽度
/// 完全透明，只通过光标变化提供视觉反馈
class ResizableDivider extends StatefulWidget {
  /// 拖拽方向：左侧边栏向右拖拽增大，右侧边栏向左拖拽增大
  final ResizeDirection direction;
  
  /// 获取当前宽度的回调
  final double Function() getCurrentWidth;
  
  /// 设置新宽度的回调
  final ValueChanged<double> onWidthChanged;
  
  /// 响应区域的宽度
  final double hitWidth;

  const ResizableDivider({
    super.key,
    required this.direction,
    required this.getCurrentWidth,
    required this.onWidthChanged,
    this.hitWidth = 4.0,
  });

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider> {
  // 拖拽开始时的全局 X 坐标
  double _dragStartGlobalX = 0.0;
  // 拖拽开始时的宽度
  double _dragStartWidth = 0.0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          _dragStartGlobalX = details.globalPosition.dx;
          _dragStartWidth = widget.getCurrentWidth();
        },
        onHorizontalDragUpdate: (details) {
          // 计算鼠标相对于拖拽开始位置的偏移量
          final globalDelta = details.globalPosition.dx - _dragStartGlobalX;
          
          // 根据方向计算新宽度
          double newWidth;
          if (widget.direction == ResizeDirection.left) {
            // 左侧边栏：向右拖拽增大宽度
            newWidth = _dragStartWidth + globalDelta;
          } else {
            // 右侧边栏：向左拖拽增大宽度
            newWidth = _dragStartWidth - globalDelta;
          }
          
          widget.onWidthChanged(newWidth);
        },
        child: Container(
          width: widget.hitWidth,
          // 完全透明，只通过光标变化提供视觉反馈
          color: Colors.transparent,
        ),
      ),
    );
  }
}

/// 拖拽方向枚举
enum ResizeDirection {
  /// 左侧边栏（向右拖拽增大宽度）
  left,
  /// 右侧边栏（向左拖拽增大宽度）
  right,
}
