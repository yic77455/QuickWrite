import 'package:flutter/material.dart';

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