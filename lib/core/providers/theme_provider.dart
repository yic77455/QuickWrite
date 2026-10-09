import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/multi_window_service.dart';
import '../theme/app_theme.dart';
import '../theme/custom_theme.dart';

/// 主题状态管理 Provider
/// 
/// 负责管理应用的主题模式（亮色/暗色/跟随系统）与自定义主题，
/// 通过 SettingsService 实现主题设置的持久化存储
class ThemeProvider extends ChangeNotifier {
  // ================= 内部状态 =================
  
  /// 当前主题模式
  ThemeMode _themeMode = ThemeMode.system;

  /// 已保存的自定义主题列表
  List<CustomTheme> _customThemes = const [];

  /// 当前激活的自定义主题 ID（null 表示使用内置主题）
  String? _activeCustomThemeId;
  
  /// 获取当前主题模式
  ThemeMode get themeMode => _themeMode;

  /// 获取已保存的自定义主题列表
  List<CustomTheme> get customThemes => _customThemes;

  /// 获取当前激活的自定义主题 ID
  String? get activeCustomThemeId => _activeCustomThemeId;

  /// 获取当前激活的自定义主题对象
  /// 未激活或激活的主题已被删除时返回 null
  CustomTheme? get activeCustomTheme {
    final id = _activeCustomThemeId;
    if (id == null) return null;
    for (final theme in _customThemes) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  /// 获取亮色主题数据
  /// 激活了自定义主题时返回基于自定义关键色构建的主题，否则返回内置亮色主题
  ThemeData get lightTheme {
    final custom = activeCustomTheme;
    if (custom == null) return AppTheme.lightTheme;
    return AppTheme.buildCustom(custom, Brightness.light);
  }

  /// 获取暗色主题数据
  /// 激活了自定义主题时返回基于自定义关键色构建的主题，否则返回内置暗色主题
  ThemeData get darkTheme {
    final custom = activeCustomTheme;
    if (custom == null) return AppTheme.darkTheme;
    return AppTheme.buildCustom(custom, Brightness.dark);
  }

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
      _customThemes = settingsService.customThemes;
      _activeCustomThemeId = settingsService.activeCustomThemeId;
      debugPrint('从设置服务加载主题: $_themeMode');
    }
    
    // 监听设置服务的变化（例如：设置被其他地方修改）
    settingsService.addListener(_onSettingsChanged);
  }
  
  /// 当设置服务中的设置发生变化时的回调
  void _onSettingsChanged() {
    final settingsService = SettingsService.instance;
    var changed = false;

    if (settingsService.themeMode != _themeMode) {
      _themeMode = settingsService.themeMode;
      debugPrint('主题设置已更新: $_themeMode');
      changed = true;
    }
    if (settingsService.activeCustomThemeId != _activeCustomThemeId) {
      _activeCustomThemeId = settingsService.activeCustomThemeId;
      changed = true;
    }
    if (!listEquals(settingsService.customThemes, _customThemes)) {
      _customThemes = settingsService.customThemes;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// 将当前主题配置序列化为 JSON，用于广播到子窗口
  String _themeConfigJson() {
    return jsonEncode({
      'activeCustomThemeId': _activeCustomThemeId,
      'customThemes': _customThemes.map((e) => e.toJson()).toList(),
    });
  }

  /// 广播自定义主题配置变化到所有子窗口
  void _broadcastThemeConfig() {
    MultiWindowService.instance.broadcastThemeConfig(_themeConfigJson());
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

  /// 新增一套自定义主题
  Future<void> addCustomTheme(CustomTheme theme) async {
    _customThemes = [..._customThemes, theme];
    await SettingsService.instance.updateCustomThemes(_customThemes);
    _broadcastThemeConfig();
    notifyListeners();
  }

  /// 更新一套自定义主题（按 id 匹配）
  Future<void> updateCustomTheme(CustomTheme theme) async {
    _customThemes = _customThemes
        .map((item) => item.id == theme.id ? theme : item)
        .toList();
    await SettingsService.instance.updateCustomThemes(_customThemes);
    _broadcastThemeConfig();
    notifyListeners();
  }

  /// 删除一套自定义主题
  /// 
  /// 若删除的是当前激活主题，则回落为内置主题
  Future<void> removeCustomTheme(String id) async {
    _customThemes = _customThemes.where((item) => item.id != id).toList();
    final wasActive = _activeCustomThemeId == id;
    if (wasActive) {
      _activeCustomThemeId = null;
    }
    await SettingsService.instance.updateCustomThemes(_customThemes);
    if (wasActive) {
      await SettingsService.instance.updateActiveCustomThemeId(null);
    }
    _broadcastThemeConfig();
    notifyListeners();
  }

  /// 设置当前激活的自定义主题
  /// 
  /// [id] 传入 null 表示切换回内置主题
  Future<void> setActiveCustomTheme(String? id) async {
    if (_activeCustomThemeId == id) return;
    _activeCustomThemeId = id;
    await SettingsService.instance.updateActiveCustomThemeId(id);
    _broadcastThemeConfig();
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

  /// 从主窗口接收自定义主题配置变化（子窗口调用）
  /// 
  /// [json] 主题配置 JSON（含激活主题 ID 与自定义主题列表）
  void updateThemeConfigFromMain(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final themes = (map['customThemes'] as List<dynamic>? ?? [])
          .map((e) => CustomTheme.fromJson(e as Map<String, dynamic>))
          .toList();
      final activeId = map['activeCustomThemeId'] as String?;

      if (activeId != _activeCustomThemeId || !listEquals(themes, _customThemes)) {
        _activeCustomThemeId = activeId;
        _customThemes = themes;
        debugPrint('从主窗口更新自定义主题配置');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('解析自定义主题配置失败: $e');
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