import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';

/// 侧边栏状态管理 Provider
/// 
/// - 使用 Provider 管理侧边栏的展开/收起状态和 LOGO 悬停状态
/// - 替代组件内部的 setState，使状态可以在全局访问
class HomeSidebarProvider extends ChangeNotifier {
  // 侧边栏是否展开，从缓存文件读取
  bool _isExpanded;
  
  // 鼠标是否悬停在 LOGO 区域，默认为 false
  bool _isLogoHovered = false;

  /// 从缓存读取展开状态；macOS 上强制展开避开红绿灯
  HomeSidebarProvider()
    : _isExpanded = PlatformCapabilities.isMacOS || WindowCacheService.instance.homeSidebarExpanded;

  // 获取侧边栏展开状态
  bool get isExpanded => _isExpanded;
  
  // 获取 LOGO 悬停状态
  bool get isLogoHovered => _isLogoHovered;

  // 切换展开状态；macOS 固定展开
  void toggleExpanded() {
    if (PlatformCapabilities.isMacOS) return;
    _isExpanded = !_isExpanded;
    _saveExpandedState();
    notifyListeners();  // 通知监听者状态已改变
  }

  // 设置展开状态；macOS 固定展开
  void setExpanded(bool expanded) {
    if (PlatformCapabilities.isMacOS) return;
    if (_isExpanded != expanded) {
      _isExpanded = expanded;
      _saveExpandedState();
      notifyListeners();  // 通知监听者状态已改变
    }
  }

  // 将展开状态保存到缓存文件
  void _saveExpandedState() {
    WindowCacheService.instance.updateSidebarState(homeExpanded: _isExpanded);
  }

  // 设置 LOGO 悬停状态
  // 当鼠标进入或离开 LOGO 区域时调用
  void setLogoHovered(bool hovered) {
    if (_isLogoHovered != hovered) {
      _isLogoHovered = hovered;
      notifyListeners();  // 通知监听者状态已改变
    }
  }
}
