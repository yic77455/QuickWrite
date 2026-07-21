import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/multi_window_service.dart';

/// 主题状态管理 Provider
/// 
/// 负责管理应用的主题模式（亮色/暗色/跟随系统）
/// 通过 SettingsService 实现主题设置的持久化存储
class ThemeProvider extends ChangeNotifier {
  // ================= 内部状态 =================
  
  /// 当前主题模式
  ThemeMode _themeMode = ThemeMode.system;
  
  /// 获取当前主题模式
  ThemeMode get themeMode => _themeMode;
  
  // ================= 构造函数 =================
  
  ThemeProvider() {
    // 构造时从设置服务加载主题
    _loadThemeFromSettings();
  }

  // ================= 私有方法 =================
  
  /// 从设置服务加载主题设置
  void _loadThemeFromSettings() {
    final settingsService = SettingsService.instance;
    
    // 如果设置服务已初始化，直接读取主题设置
    if (settingsService.isInitialized) {
      _themeMode = settingsService.themeMode;
      debugPrint('从设置服务加载主题: $_themeMode');
    }
    
    // 监听设置服务的变化（例如：设置被其他地方修改）
    settingsService.addListener(_onSettingsChanged);
  }
  
  /// 当设置服务中的设置发生变化时的回调
  void _onSettingsChanged() {
    final newThemeMode = SettingsService.instance.themeMode;
    
    // 只有当主题确实发生变化时才更新
    if (newThemeMode != _themeMode) {
      _themeMode = newThemeMode;
      debugPrint('主题设置已更新: $_themeMode');
      notifyListeners();
    }
  }

  // ================= 公共方法 =================
  
  /// 设置主题模式
  /// 
  /// [mode] 新的主题模式（ThemeMode.light / ThemeMode.dark / ThemeMode.system）
  /// 会自动保存到配置文件
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      debugPrint('主题模式未变化，跳过设置');
      return;
    }
    
    _themeMode = mode;
    
    // 保存到设置服务（会自动持久化到配置文件）
    await SettingsService.instance.updateThemeMode(mode);
    
    // 广播主题变化到所有子窗口
    MultiWindowService.instance.broadcastThemeChange(mode.name);
    
    debugPrint('主题模式已设置为: $mode');
    notifyListeners();
  }
  
  /// 从主窗口接收主题变化（子窗口调用）
  /// 
  /// [themeModeName] 主题模式名称（light / dark / system）
  void updateThemeFromMain(String themeModeName) {
    ThemeMode newMode;
    switch (themeModeName) {
      case 'light':
        newMode = ThemeMode.light;
        break;
      case 'dark':
        newMode = ThemeMode.dark;
        break;
      default:
        newMode = ThemeMode.system;
    }
    
    if (_themeMode != newMode) {
      _themeMode = newMode;
      debugPrint('从主窗口更新主题: $_themeMode');
      notifyListeners();
    }
  }
  
  /// 切换主题模式（亮色 <-> 暗色）
  /// 
  /// 如果当前是跟随系统，则切换到亮色模式
  Future<void> toggleTheme() async {
    ThemeMode newMode;
    
    switch (_themeMode) {
      case ThemeMode.light:
        newMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        newMode = ThemeMode.light;
        break;
      case ThemeMode.system:
        // 如果当前是跟随系统，默认切换到亮色模式
        newMode = ThemeMode.light;
        break;
    }
    
    await setThemeMode(newMode);
  }

  // ================= 生命周期 =================
  
  @override
  void dispose() {
    // 移除设置服务的监听
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
