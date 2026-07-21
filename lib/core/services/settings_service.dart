import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/app_settings.dart';
import 'app_paths.dart';

/// 设置服务类
/// 
/// 负责管理应用的全局设置，包括：
/// - 配置文件的读写（存储在 文档/QuickWrite 目录下）
/// - 应用首次启动时创建配置目录
/// - 提供设置的获取、更新、保存功能
/// 
/// 使用方式：
/// ```dart
/// // 初始化（在 main.dart 中调用）
/// await SettingsService.instance.initialize();
/// 
/// // 获取设置
/// final settings = SettingsService.instance.settings;
/// 
/// // 更新设置
/// await SettingsService.instance.updateThemeMode(ThemeMode.dark);
/// await SettingsService.instance.updateSettings(newSettings);
/// ```
class SettingsService extends ChangeNotifier {
  // ================= 单例模式 =================
  static final SettingsService instance = SettingsService._internal();
  SettingsService._internal();
  
  // ================= 常量定义 =================
    
  /// SharedPreferences 中存储配置文件路径的 key
  static const String _configPathKey = 'config_file_path';
  
  // ================= 状态属性 =================
  
  /// 当前设置
  /// 使用 AppSettings.defaults 作为初始值，保持默认值单一数据源
  AppSettings _settings = AppSettings.defaults;
  
  /// 获取当前设置（只读）
  AppSettings get settings => _settings;
  
  /// 配置文件完整路径
  String? _configFilePath;
  
  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 是否首次启动（配置文件是否是新创建的）
  bool _isFirstLaunch = false;
  bool get isFirstLaunch => _isFirstLaunch;

  /// 防抖保存定时器
  /// 用于在滑块拖动等连续操作时延迟写入文件，避免频繁 IO
  Timer? _saveDebounceTimer;

  /// 防抖延迟时间（毫秒）
  static const int _saveDebounceDelay = 500;

  // ================= 初始化方法 =================
  
  /// 初始化设置服务
  /// 
  /// 该方法应该在应用启动时调用（main.dart 中）
  /// 主要工作：
  /// 1. 确保 AppPaths 已初始化
  /// 2. 加载配置文件（如果存在）或创建默认配置
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('SettingsService 已经初始化，跳过重复初始化');
      return;
    }
    
    try {
      // 确保 AppPaths 已初始化
      if (!AppPaths.instance.isInitialized) {
        await AppPaths.instance.initialize();
      }
      
      // 从 AppPaths 获取配置文件路径
      _configFilePath = AppPaths.instance.configFilePath;
      debugPrint('配置文件路径: $_configFilePath');
      
      // 保存配置目录路径到 SharedPreferences（方便后续使用）
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configPathKey, AppPaths.instance.appRootPath);
      
      // 加载配置文件
      await _loadSettings();
      
      _isInitialized = true;
      debugPrint('SettingsService 初始化完成');
    } catch (e, stackTrace) {
      debugPrint('SettingsService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      // 即使初始化失败，也使用默认设置
      _settings = AppSettings.defaults;
      _isInitialized = true;
    }
  }

  // ================= 配置文件读写 =================
  
  /// 获取当前系统的默认字体
  String _getSystemDefaultFontFamily() {
    if (Platform.isWindows) {
      return 'Microsoft YaHei';
    } else if (Platform.isMacOS) {
      return 'PingFang SC';
    } else if (Platform.isLinux) {
      return 'Noto Sans SC';
    } else {
      return 'Microsoft YaHei';
    }
  }

  /// 获取当前系统的默认字体名称
  /// 用于字体下拉菜单中"默认"选项的重置操作
  String get defaultFontFamily => _getSystemDefaultFontFamily();

  /// 从配置文件加载设置
  Future<void> _loadSettings() async {
    if (_configFilePath == null) {
      debugPrint('配置文件路径为空，使用默认设置');
      _settings = AppSettings.defaults;
      return;
    }
    
    final configFile = File(_configFilePath!);
    
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        _settings = AppSettings.fromJson(jsonMap);
        _isFirstLaunch = false; // 配置文件存在，不是首次启动
        debugPrint('已加载配置文件: $_settings');
      } catch (e) {
        debugPrint('解析配置文件失败: $e，使用默认设置');
        _settings = AppSettings.defaults;
        _isFirstLaunch = false; // 配置文件存在但损坏，不是首次启动
        // 尝试修复损坏的配置文件
        await _saveSettings();
      }
    } else {
      debugPrint('配置文件不存在，创建默认配置');
      // 首次启动时，根据系统设置默认字体
      final defaultFont = _getSystemDefaultFontFamily();
      _settings = AppSettings.defaults.copyWith(fontFamily: defaultFont);
      _isFirstLaunch = true; // 配置文件不存在，是首次启动
      await _saveSettings();
    }
  }
  
  /// 保存设置到配置文件
  Future<bool> _saveSettings() async {
    if (_configFilePath == null) {
      debugPrint('配置文件路径为空，无法保存');
      return false;
    }
    
    try {
      final configFile = File(_configFilePath!);
      final jsonContent = const JsonEncoder.withIndent('  ').convert(_settings.toJson());
      await configFile.writeAsString(jsonContent);
      debugPrint('配置已保存: $_settings');
      return true;
    } catch (e) {
      debugPrint('保存配置文件失败: $e');
      return false;
    }
  }

  // ================= 主题设置相关 =================
  
  /// 获取当前主题模式
  ThemeMode get themeMode => _settings.themeModeValue;
  
  /// 更新主题模式
  /// 
  /// [mode] 新的主题模式
  /// 返回是否保存成功
  Future<bool> updateThemeMode(ThemeMode mode) async {
    final newSettings = _settings.copyWith(
      themeMode: AppSettings.themeModeToString(mode),
    );
    
    if (newSettings == _settings) {
      debugPrint('主题设置未变化，跳过保存');
      return true;
    }
    
    _settings = newSettings;
    final success = await _saveSettings();
    
    if (success) {
      notifyListeners();
    }
    
    return success;
  }

  // ================= 多窗口设置相关 =================
  
  /// 获取是否在新窗口中打开工作台
  bool get openWorkspaceInNewWindow => _settings.openWorkspaceInNewWindow;
  
  /// 更新是否在新窗口中打开工作台
  Future<bool> updateOpenWorkspaceInNewWindow(bool value) async {
    final newSettings = _settings.copyWith(openWorkspaceInNewWindow: value);
    return updateSettings(newSettings);
  }

  // ================= 暗色模式封面变暗设置相关 =================
  
  /// 获取暗色模式下是否让封面变暗
  bool get dimCoverInDarkMode => _settings.dimCoverInDarkMode;
  
  /// 更新暗色模式下是否让封面变暗
  Future<bool> updateDimCoverInDarkMode(bool value) async {
    final newSettings = _settings.copyWith(dimCoverInDarkMode: value);
    return updateSettings(newSettings);
  }

  // ================= 布局设置相关（右侧边栏 - 布局设置面板）=================
  
  /// 获取是否显示章节标题
  bool get showChapterTitle => _settings.showChapterTitle;
  
  /// 获取章节标题顶边距
  double get chapterTitleTopMargin => _settings.chapterTitleTopMargin;
  
  /// 获取章节标题字体大小
  double get chapterTitleFontSize => _settings.chapterTitleFontSize;
  
  /// 获取章节标题颜色（亮色主题，为 null 时使用主题默认颜色）
  String? get chapterTitleColorLight => _settings.chapterTitleColorLight;

  /// 获取章节标题颜色（暗色主题，为 null 时使用主题默认颜色）
  String? get chapterTitleColorDark => _settings.chapterTitleColorDark;
  
  /// 获取页面顶边距
  double get topMargin => _settings.topMargin;
  
  /// 获取页面左右边距
  double get horizontalMargin => _settings.horizontalMargin;
  
  /// 获取页面底边距
  double get bottomMargin => _settings.bottomMargin;
  
  /// 获取是否开启纸张模式
  bool get isPageViewEnabled => _settings.isPageViewEnabled;

  /// 获取滚动条是否常驻显示
  bool get scrollbarAlwaysVisible => _settings.scrollbarAlwaysVisible;

  /// 获取大纲编辑器顶边距
  double get outlineTopMargin => _settings.outlineTopMargin;

  /// 获取大纲编辑器左右边距
  double get outlineHorizontalMargin => _settings.outlineHorizontalMargin;

  /// 获取大纲编辑器底边距
  double get outlineBottomMargin => _settings.outlineBottomMargin;

  /// 获取大纲编辑器节点间距
  double get outlineNodeSpacing => _settings.outlineNodeSpacing;

  /// 获取大纲编辑器页面视图模式
  String get outlinePageViewMode => _settings.outlinePageViewMode;

  /// 更新是否显示章节标题
  Future<bool> updateShowChapterTitle(bool value) async {
    final newSettings = _settings.copyWith(showChapterTitle: value);
    return updateSettings(newSettings);
  }
  
  /// 更新章节标题顶边距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateChapterTitleTopMargin(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(chapterTitleTopMargin: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新章节标题字体大小
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateChapterTitleFontSize(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(chapterTitleFontSize: value);
    return updateSettings(newSettings, debounce: debounce);
  }
  
  /// 更新章节标题颜色（亮色主题）
  Future<bool> updateChapterTitleColorLight(String? value) async {
    final newSettings = _settings.copyWith(chapterTitleColorLight: value);
    return updateSettings(newSettings);
  }

  /// 更新章节标题颜色（暗色主题）
  Future<bool> updateChapterTitleColorDark(String? value) async {
    final newSettings = _settings.copyWith(chapterTitleColorDark: value);
    return updateSettings(newSettings);
  }
  
  /// 更新页面顶边距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateTopMargin(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(topMargin: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新页面左右边距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateHorizontalMargin(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(horizontalMargin: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新页面底边距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateBottomMargin(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(bottomMargin: value);
    return updateSettings(newSettings, debounce: debounce);
  }
  
  /// 更新是否开启纸张模式
  Future<bool> updateIsPageViewEnabled(bool value) async {
    final newSettings = _settings.copyWith(isPageViewEnabled: value);
    return updateSettings(newSettings);
  }

  /// 更新滚动条是否常驻显示
  Future<bool> updateScrollbarAlwaysVisible(bool value) async {
    final newSettings = _settings.copyWith(scrollbarAlwaysVisible: value);
    return updateSettings(newSettings);
  }

  /// 更新大纲编辑器顶边距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateOutlineTopMargin(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(outlineTopMargin: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新大纲编辑器左右边距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateOutlineHorizontalMargin(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(outlineHorizontalMargin: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新大纲编辑器底边距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateOutlineBottomMargin(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(outlineBottomMargin: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新大纲编辑器节点间距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateOutlineNodeSpacing(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(outlineNodeSpacing: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新大纲编辑器页面视图模式
  Future<bool> updateOutlinePageViewMode(String value) async {
    final newSettings = _settings.copyWith(outlinePageViewMode: value);
    return updateSettings(newSettings);
  }

  // ================= 排版设置相关（右侧边栏 - 排版设置面板）=================
  
  /// 获取字间距
  double get letterSpacing => _settings.letterSpacing;
  
  /// 获取行间距倍数
  double get lineHeight => _settings.lineHeight;
  
  /// 获取是否开启首行缩进
  bool get isFirstLineIndentEnabled => _settings.isFirstLineIndentEnabled;

  /// 获取是否开启自动空行
  bool get autoLineBreak => _settings.autoLineBreak;
  
  /// 获取是否显示行间线条
  bool get showLineSeparator => _settings.showLineSeparator;

  /// 获取行间线样式（'solid' 实线 / 'dashed' 虚线）
  String get lineSeparatorStyle => _settings.lineSeparatorStyle;

  /// 获取行间线不透明度（0.0 ~ 1.0）
  double get lineSeparatorOpacity => _settings.lineSeparatorOpacity;
  
  // ================= 字体设置相关 =================
  
  /// 获取字体名称
  String get fontFamily => _settings.fontFamily;
  
  /// 获取字体大小
  double get fontSize => _settings.fontSize;
  
  /// 获取是否加粗
  bool get isBold => _settings.isBold;
  
  /// 获取是否斜体
  bool get isItalic => _settings.isItalic;
  
  /// 获取是否下划线
  bool get isUnderline => _settings.isUnderline;
  
  /// 获取正文字体颜色（亮色主题，为 null 时使用主题默认颜色）
  String? get fontColorLight => _settings.fontColorLight;

  /// 获取正文字体颜色（暗色主题，为 null 时使用主题默认颜色）
  String? get fontColorDark => _settings.fontColorDark;

  /// 获取大纲编辑器字体名称
  String get outlineFontFamily => _settings.outlineFontFamily;

  /// 获取大纲编辑器字体大小
  double get outlineFontSize => _settings.outlineFontSize;

  // ================= 其他设置 =================

  /// 获取是否开启自动保存
  bool get autoSaveEnabled => _settings.autoSaveEnabled;

  /// 获取是否开启自动备份
  bool get autoBackupEnabled => _settings.autoBackupEnabled;

  /// 获取备份间隔（单位：分钟）
  int get backupInterval => _settings.backupInterval;

  /// 获取历史记录保存天数
  /// 1~365 表示保留对应天数，0 表示永久保留
  int get historyRetentionDays => _settings.historyRetentionDays;

  /// 获取打开章节时光标定位模式
  String get openChapterCursorMode => _settings.openChapterCursorMode;

  /// 获取预览模式是否启用
  bool get previewModeEnabled => _settings.previewModeEnabled;

  /// 更新字间距
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateLetterSpacing(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(letterSpacing: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新行间距倍数
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateLineHeight(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(lineHeight: value);
    return updateSettings(newSettings, debounce: debounce);
  }
  
  // ================= 字体设置相关 =================
  
  /// 更新字体名称
  Future<bool> updateFontFamily(String value) async {
    final newSettings = _settings.copyWith(fontFamily: value);
    return updateSettings(newSettings);
  }
  
  /// 更新字体大小
  Future<bool> updateFontSize(double value) async {
    final newSettings = _settings.copyWith(fontSize: value);
    return updateSettings(newSettings);
  }
  
  /// 更新是否加粗
  Future<bool> updateIsBold(bool value) async {
    final newSettings = _settings.copyWith(isBold: value);
    return updateSettings(newSettings);
  }
  
  /// 更新是否斜体
  Future<bool> updateIsItalic(bool value) async {
    final newSettings = _settings.copyWith(isItalic: value);
    return updateSettings(newSettings);
  }
  
  /// 更新是否下划线
  Future<bool> updateIsUnderline(bool value) async {
    final newSettings = _settings.copyWith(isUnderline: value);
    return updateSettings(newSettings);
  }
  
  /// 更新正文字体颜色（亮色主题）
  Future<bool> updateFontColorLight(String? value) async {
    final newSettings = _settings.copyWith(fontColorLight: value);
    return updateSettings(newSettings);
  }

  /// 更新正文字体颜色（暗色主题）
  Future<bool> updateFontColorDark(String? value) async {
    final newSettings = _settings.copyWith(fontColorDark: value);
    return updateSettings(newSettings);
  }

  /// 更新大纲编辑器字体名称
  Future<bool> updateOutlineFontFamily(String value) async {
    final newSettings = _settings.copyWith(outlineFontFamily: value);
    return updateSettings(newSettings);
  }

  /// 更新大纲编辑器字体大小
  Future<bool> updateOutlineFontSize(double value) async {
    final newSettings = _settings.copyWith(outlineFontSize: value);
    return updateSettings(newSettings);
  }

  
  /// 更新是否开启首行缩进
  Future<bool> updateIsFirstLineIndentEnabled(bool value) async {
    final newSettings = _settings.copyWith(isFirstLineIndentEnabled: value);
    return updateSettings(newSettings);
  }

  /// 更新是否开启自动空行
  Future<bool> updateAutoLineBreak(bool value) async {
    final newSettings = _settings.copyWith(autoLineBreak: value);
    return updateSettings(newSettings);
  }
  
  /// 更新是否显示行间线条
  Future<bool> updateShowLineSeparator(bool value) async {
    final newSettings = _settings.copyWith(showLineSeparator: value);
    return updateSettings(newSettings);
  }

  /// 更新行间线样式
  Future<bool> updateLineSeparatorStyle(String value) async {
    final newSettings = _settings.copyWith(lineSeparatorStyle: value);
    return updateSettings(newSettings);
  }

  /// 更新行间线不透明度
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateLineSeparatorOpacity(double value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(lineSeparatorOpacity: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 获取是否开启对话高亮
  bool get dialogueHighlightEnabled => _settings.dialogueHighlightEnabled;

  /// 获取对话高亮颜色（亮色主题）
  String? get dialogueHighlightColorLight => _settings.dialogueHighlightColorLight;

  /// 获取对话高亮颜色（暗色主题）
  String? get dialogueHighlightColorDark => _settings.dialogueHighlightColorDark;

  /// 更新是否开启对话高亮
  Future<bool> updateDialogueHighlightEnabled(bool value) async {
    final newSettings = _settings.copyWith(dialogueHighlightEnabled: value);
    return updateSettings(newSettings);
  }

  /// 更新对话高亮颜色（亮色主题）
  Future<bool> updateDialogueHighlightColorLight(String? value) async {
    final newSettings = _settings.copyWith(dialogueHighlightColorLight: value);
    return updateSettings(newSettings);
  }

  /// 更新对话高亮颜色（暗色主题）
  Future<bool> updateDialogueHighlightColorDark(String? value) async {
    final newSettings = _settings.copyWith(dialogueHighlightColorDark: value);
    return updateSettings(newSettings);
  }

  // ================= 其他设置更新方法 =================

  /// 更新是否开启自动保存
  Future<bool> updateAutoSaveEnabled(bool value) async {
    final newSettings = _settings.copyWith(autoSaveEnabled: value);
    return updateSettings(newSettings);
  }

  /// 更新是否开启自动备份
  Future<bool> updateAutoBackupEnabled(bool value) async {
    final newSettings = _settings.copyWith(autoBackupEnabled: value);
    return updateSettings(newSettings);
  }

  /// 更新备份间隔（单位：分钟）
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateBackupInterval(int value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(backupInterval: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新历史记录保存天数
  /// 1~365 表示保留对应天数，0 表示永久保留
  /// [debounce] 是否使用防抖方式保存
  Future<bool> updateHistoryRetentionDays(int value, {bool debounce = false}) async {
    final newSettings = _settings.copyWith(historyRetentionDays: value);
    return updateSettings(newSettings, debounce: debounce);
  }

  /// 更新打开章节时光标定位模式
  Future<bool> updateOpenChapterCursorMode(String value) async {
    final newSettings = _settings.copyWith(openChapterCursorMode: value);
    return updateSettings(newSettings);
  }

  /// 更新预览模式开关
  Future<bool> updatePreviewModeEnabled(bool value) async {
    final newSettings = _settings.copyWith(previewModeEnabled: value);
    return updateSettings(newSettings);
  }

  // ================= 重置布局和排版设置 =================
  
  /// 重置布局设置为默认值
  /// 从 AppSettings.defaults 获取默认值，保留其他设置不变
  Future<bool> resetLayoutSettings() async {
    final newSettings = _settings.copyWith(
      showChapterTitle: AppSettings.defaults.showChapterTitle,
      chapterTitleTopMargin: AppSettings.defaults.chapterTitleTopMargin,
      topMargin: AppSettings.defaults.topMargin,
      horizontalMargin: AppSettings.defaults.horizontalMargin,
      bottomMargin: AppSettings.defaults.bottomMargin,
      isPageViewEnabled: AppSettings.defaults.isPageViewEnabled,
      scrollbarAlwaysVisible: AppSettings.defaults.scrollbarAlwaysVisible,
      outlineTopMargin: AppSettings.defaults.outlineTopMargin,
      outlineHorizontalMargin: AppSettings.defaults.outlineHorizontalMargin,
      outlineBottomMargin: AppSettings.defaults.outlineBottomMargin,
      outlineNodeSpacing: AppSettings.defaults.outlineNodeSpacing,
      outlinePageViewMode: AppSettings.defaults.outlinePageViewMode,
    );
    return updateSettings(newSettings);
  }

  /// 重置章节标题格式设置为默认值
  Future<bool> resetChapterTitleFormatSettings() async {
    final newSettings = _settings.copyWith(
      chapterTitleFontSize: AppSettings.defaults.chapterTitleFontSize,
      chapterTitleColorLight: AppSettings.defaults.chapterTitleColorLight,
      chapterTitleColorDark: AppSettings.defaults.chapterTitleColorDark,
    );
    return updateSettings(newSettings);
  }
  
  /// 重置排版设置为默认值
  /// 从 AppSettings.defaults 获取默认值，保留其他设置不变
  Future<bool> resetTypesetSettings() async {
    final newSettings = _settings.copyWith(
      letterSpacing: AppSettings.defaults.letterSpacing,
      lineHeight: AppSettings.defaults.lineHeight,
      isFirstLineIndentEnabled: AppSettings.defaults.isFirstLineIndentEnabled,
      autoLineBreak: AppSettings.defaults.autoLineBreak,
      showLineSeparator: AppSettings.defaults.showLineSeparator,
      lineSeparatorStyle: AppSettings.defaults.lineSeparatorStyle,
      lineSeparatorOpacity: AppSettings.defaults.lineSeparatorOpacity,
      dialogueHighlightEnabled: AppSettings.defaults.dialogueHighlightEnabled,
      dialogueHighlightColorLight: AppSettings.defaults.dialogueHighlightColorLight,
      dialogueHighlightColorDark: AppSettings.defaults.dialogueHighlightColorDark,
    );
    return updateSettings(newSettings);
  }

  /// 重置其他设置为默认值
  /// 从 AppSettings.defaults 获取默认值，保留其他设置不变
  Future<bool> resetOtherSettings() async {
    final newSettings = _settings.copyWith(
      autoSaveEnabled: AppSettings.defaults.autoSaveEnabled,
      autoBackupEnabled: AppSettings.defaults.autoBackupEnabled,
      backupInterval: AppSettings.defaults.backupInterval,
      historyRetentionDays: AppSettings.defaults.historyRetentionDays,
      openChapterCursorMode: AppSettings.defaults.openChapterCursorMode,
    );
    return updateSettings(newSettings);
  }

  // ================= 通用设置更新方法 =================

  /// 批量更新设置
  ///
  /// [newSettings] 新的设置对象
  /// [debounce] 是否使用防抖方式保存，适用于滑块拖动等连续操作场景
  /// 返回是否保存成功
  Future<bool> updateSettings(AppSettings newSettings, {bool debounce = false}) async {
    if (newSettings == _settings) {
      debugPrint('设置未变化，跳过保存');
      return true;
    }

    _settings = newSettings;

    if (debounce) {
      // 防抖模式：立即通知监听器以更新 UI，延迟写入文件以避免频繁 IO
      notifyListeners();
      _scheduleDebouncedSave();
      return true;
    }

    // 立即模式：取消可能存在的防抖任务，直接写入文件
    _cancelDebouncedSave();
    final success = await _saveSettings();

    if (success) {
      notifyListeners();
    }

    return success;
  }

  /// 调度防抖保存任务
  /// 在延迟时间到达后执行一次文件写入，期间若再次调用会重新计时
  void _scheduleDebouncedSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(
      const Duration(milliseconds: _saveDebounceDelay),
      () {
        _saveDebounceTimer = null;
        _saveSettings();
      },
    );
  }

  /// 取消待执行的防抖保存任务
  void _cancelDebouncedSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
  }
  
  /// 重置所有设置为默认值
  Future<bool> resetToDefault() async {
    _settings = AppSettings.defaults;
    final success = await _saveSettings();
    
    if (success) {
      notifyListeners();
    }
    
    return success;
  }

  // ================= 工具方法 =================
  
  /// 获取配置目录路径
  Future<String?> getConfigDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_configPathKey);
  }
  
  /// 导出配置到指定路径
  Future<bool> exportConfig(String targetPath) async {
    if (_configFilePath == null) return false;
    
    try {
      final sourceFile = File(_configFilePath!);
      if (!await sourceFile.exists()) return false;
      
      await sourceFile.copy(targetPath);
      debugPrint('配置已导出到: $targetPath');
      return true;
    } catch (e) {
      debugPrint('导出配置失败: $e');
      return false;
    }
  }
  
  /// 从指定路径导入配置
  Future<bool> importConfig(String sourcePath) async {
    if (_configFilePath == null) return false;
    
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return false;
      
      final content = await sourceFile.readAsString();
      final jsonMap = json.decode(content) as Map<String, dynamic>;
      _settings = AppSettings.fromJson(jsonMap);
      
      await _saveSettings();
      notifyListeners();
      
      debugPrint('配置已从 $sourcePath 导入');
      return true;
    } catch (e) {
      debugPrint('导入配置失败: $e');
      return false;
    }
  }
}
