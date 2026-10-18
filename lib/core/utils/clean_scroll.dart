import 'package:flutter/material.dart';
import 'platform_capabilities.dart';

/// 编辑器滚动条手柄的宽度
///
/// 桌面端沿用较宽的手柄，便于鼠标拖拽时看清与命中；移动端由手指直接滑动滚动，
/// 不需要同样宽的视觉宽度，收窄至与移动平台系统滚动条相近的尺寸。
final double editorScrollbarThickness = PlatformCapabilities.isMobile ? 4.0 : 8.0;

/// 专用于文本编辑器的纯净滚动行为
/// 强制剥离系统自带的滚动条和边界发光效果
class CleanEditorScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // 直接返回 child，彻底拦截内置滚动条的构建
    return child; 
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // 顺手屏蔽掉 Android 平台滚动到边缘时的半月形发光效果（水波纹）
    // 让编辑器在所有平台上都保持桌面端的纯净感
    return child; 
  }
}