import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/theme/custom_theme.dart';

/// 应用全局设置模型类
/// 
/// 该类定义了应用的所有设置项，使用 JSON 序列化/反序列化来支持配置文件的读写
class AppSettings {
  // ================= 主题设置 =================
  /// 主题模式：light（亮色）、dark（暗色）、system（跟随系统）
  final String themeMode;

  /// 暗色模式下是否让封面变暗
  /// true: 暗色模式下封面会添加遮罩变暗
  /// false: 封面保持原样
  final bool dimCoverInDarkMode;

  /// 当前激活的自定义主题 ID
  /// null 表示使用内置主题（跟随系统/亮色/暗色）
  final String? activeCustomThemeId;

  /// 已保存的自定义主题列表
  final List<CustomTheme> customThemes;

  // ================= 多窗口设置 =================
  /// 是否在新窗口中打开工作台
  /// true: 工作台在新窗口中打开
  /// false: 工作台在当前窗口中打开
  final bool openWorkspaceInNewWindow;

  // ================= 编辑器字体设置 =================
  
  /// 字体名称
  final String fontFamily;
  
  /// 字体大小（单位：像素）
  final double fontSize;
  
  /// 是否加粗
  final bool isBold;
  
  /// 是否斜体
  final bool isItalic;
  
  /// 是否下划线
  final bool isUnderline;
  
  /// 正文字体颜色（亮色主题，十六进制字符串）
  final String? fontColorLight;

  /// 正文字体颜色（暗色主题，十六进制字符串）
  final String? fontColorDark;

  // ================= 大纲编辑器字体设置 =================

  /// 大纲编辑器字体名称
  final String outlineFontFamily;

  /// 大纲编辑器字体大小（单位：像素）
  final double outlineFontSize;

  // ================= 布局设置（右侧边栏 - 布局设置面板）=================
  
  /// 是否显示章节标题
  final bool showChapterTitle;
  
  /// 章节标题顶边距（单位：像素）
  final double chapterTitleTopMargin;
  
  /// 章节标题字体大小（单位：像素）
  final double chapterTitleFontSize;
  
  /// 章节标题颜色（亮色主题，十六进制字符串）
  final String? chapterTitleColorLight;

  /// 章节标题颜色（暗色主题，十六进制字符串）
  final String? chapterTitleColorDark;
  
  /// 页面顶边距（单位：百分比）
  final double topMargin;
  
  /// 页面左右边距（单位：百分比）
  final double horizontalMargin;
  
  /// 页面底边距（单位：百分比）
  final double bottomMargin;
  
  /// 是否开启纸张模式
  /// 开启后正文编辑器内容以 A4 纸宽度显示，并具备纸张背景色与投影效果
  final bool isPageViewEnabled;

  /// 滚动条是否常驻显示
  /// true: 滚动条始终可见，不会自动隐藏
  /// false: 滚动条在空闲时自动隐藏
  final bool scrollbarAlwaysVisible;

  // ================= 大纲编辑器布局设置 =================

  /// 大纲编辑器顶边距（单位：百分比）
  final double outlineTopMargin;

  /// 大纲编辑器左右边距（单位：百分比）
  final double outlineHorizontalMargin;

  /// 大纲编辑器底边距（单位：百分比）
  final double outlineBottomMargin;

  /// 大纲编辑器节点间距（单位：像素）
  final double outlineNodeSpacing;

  /// 大纲编辑器页面视图模式
  /// 'adaptive' - 自适应：取消宽度限制，不居中，节点区域自适应容器宽度
  /// 'default' - 默认：限制 A4 宽度并居中，不显示纸张样式
  /// 'paper' - 纸张：在默认基础上显示 A4 纸张背景与投影效果
  final String outlinePageViewMode;

  // ================= 排版设置（右侧边栏 - 排版设置面板）=================
  
  /// 字间距（单位：像素，负值表示紧凑）
  final double letterSpacing;
  
  /// 行间距倍数（1.0 = 单倍行距）
  final double lineHeight;
  
  /// 是否开启首行缩进
  final bool isFirstLineIndentEnabled;

  /// 是否开启自动空行（段间距）
  final bool autoLineBreak;
  
  /// 是否显示行间线条
  final bool showLineSeparator;

  /// 行间线样式：'solid'（实线）或 'dashed'（虚线）
  final String lineSeparatorStyle;

  /// 行间线不透明度（0.0 ~ 1.0，1.0 为完全不透明）
  final double lineSeparatorOpacity;

  /// 是否开启对话高亮
  final bool dialogueHighlightEnabled;

  /// 对话高亮颜色（亮色主题，十六进制字符串，为 null 时使用默认颜色）
  final String? dialogueHighlightColorLight;

  /// 对话高亮颜色（暗色主题，十六进制字符串，为 null 时使用默认颜色）
  final String? dialogueHighlightColorDark;

  // ================= 其他设置（右侧边栏 - 其他设置面板）=================
  
  /// 是否开启自动保存
  final bool autoSaveEnabled;
  
  /// 是否开启自动备份
  final bool autoBackupEnabled;
  
  /// 备份间隔（单位：分钟）
  final int backupInterval;

  /// 历史记录保存天数
  /// 1~365 表示保留对应天数内的备份，0 表示永久保留
  final int historyRetentionDays;

  /// 打开章节时光标定位模式
  /// 'default' - 默认（光标位于章节开头）
  /// 'end' - 定位至章末（光标位于章节末尾）
  /// 'lastEdit' - 上一次编辑位置（暂未实现）
  final String openChapterCursorMode;

  /// 是否启用预览模式
  /// 开启后，单击章节/设定/备份预览以预览模式打开，再次单击其他项时替换当前预览标签页
  /// 关闭后，所有标签页均以固定模式打开
  final bool previewModeEnabled;

  // ================= 默认配置常量 =================
  
  /// 应用默认设置常量
  static const AppSettings defaults = AppSettings();


  // ================= 构造函数 =================
  const AppSettings({
    this.themeMode = 'system',
    // 暗色模式下封面变暗
    this.dimCoverInDarkMode = false,
    // 自定义主题
    this.activeCustomThemeId,
    this.customThemes = const [],
    // 多窗口设置
    this.openWorkspaceInNewWindow = false,
    // 工作台布局设置
    this.showChapterTitle = true, // 是否显示章节标题
    this.chapterTitleTopMargin = 16.0, // 章节标题顶边距（单位：像素）
    this.chapterTitleFontSize = 24.0, // 章节标题字体大小（单位：像素）
    this.chapterTitleColorLight, // 章节标题颜色（亮色主题，十六进制字符串）
    this.chapterTitleColorDark, // 章节标题颜色（暗色主题，十六进制字符串）
    this.topMargin = 4.0, // 页面顶边距（单位：百分比）
    this.horizontalMargin = 4.0, // 页面左右边距（单位：百分比）
    this.bottomMargin = 40.0, // 页面底边距（单位：百分比）
    this.isPageViewEnabled = false, // 纸张模式
    this.scrollbarAlwaysVisible = false, // 滚动条是否常驻显示
    // 大纲编辑器布局设置
    this.outlineTopMargin = 4.0, // 大纲编辑器顶边距（单位：百分比）
    this.outlineHorizontalMargin = 4.0, // 大纲编辑器左右边距（单位：百分比）
    this.outlineBottomMargin = 20.0, // 大纲编辑器底边距（单位：百分比）
    this.outlineNodeSpacing = 0.0, // 大纲编辑器节点间距（单位：像素）
    this.outlinePageViewMode = 'default', // 大纲编辑器页面视图模式
    // 工作台排版设置
    this.letterSpacing = 0.5, // 字间距（单位：像素，负值表示紧凑）
    this.lineHeight = 1.8, // 行间距倍数（1.0 = 单倍行距）
    this.isFirstLineIndentEnabled = true, // 是否开启首行缩进
    this.autoLineBreak = true, // 是否开启自动空行
    this.showLineSeparator = false, // 是否显示行间线条
    this.lineSeparatorStyle = 'dashed', // 行间线样式（dashed/solid）
    this.lineSeparatorOpacity = 0.3, // 行间线不透明度
    this.dialogueHighlightEnabled = false, // 是否开启对话高亮
    this.dialogueHighlightColorLight, // 对话高亮颜色（亮色主题）
    this.dialogueHighlightColorDark, // 对话高亮颜色（暗色主题）
    // 字体设置
    this.fontFamily = 'Microsoft YaHei', // 字体名称
    this.fontSize = 16.0, // 字体大小（单位：像素）
    this.isBold = false, // 是否加粗
    this.isItalic = false, // 是否斜体
    this.isUnderline = false, // 是否下划线
    this.fontColorLight, // 正文字体颜色（亮色主题，十六进制字符串）
    this.fontColorDark, // 正文字体颜色（暗色主题，十六进制字符串）
    // 大纲编辑器字体设置
    this.outlineFontFamily = 'Microsoft YaHei', // 大纲编辑器字体名称
    this.outlineFontSize = 16.0, // 大纲编辑器字体大小（单位：像素）
    // 其他设置
    this.autoSaveEnabled = false, // 是否开启自动保存
    this.autoBackupEnabled = true, // 是否开启自动备份
    this.backupInterval = 10, // 备份间隔（单位：分钟）
    this.historyRetentionDays = 30, // 历史记录保存天数
    this.openChapterCursorMode = 'default', // 打开章节时光标定位模式
    this.previewModeEnabled = true, // 是否启用预览模式
  });

  // ================= JSON 序列化 =================
  
  /// 从 JSON Map 创建 AppSettings 实例
  /// 所有默认值均从 defaults 常量获取，确保与构造函数一致
  /// 支持新的嵌套 JSON 结构：global、editor 两大类
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // 全局设置
    final globalJson = json['global'] as Map<String, dynamic>? ?? {};
    final themeJson = globalJson['theme'] as Map<String, dynamic>? ?? {};

    // 编辑器设置
    final editorJson = json['editor'] as Map<String, dynamic>? ?? {};
    final fontJson = editorJson['font'] as Map<String, dynamic>? ?? {};
    final fontColorJson = fontJson['color'] as Map<String, dynamic>? ?? {};
    final layoutJson = editorJson['layout'] as Map<String, dynamic>? ?? {};
    final chapterTitleJson = layoutJson['chapterTitle'] as Map<String, dynamic>? ?? {};
    final chapterTitleColorJson = chapterTitleJson['color'] as Map<String, dynamic>? ?? {};
    final pageJson = layoutJson['page'] as Map<String, dynamic>? ?? {};
    final outlineLayoutJson = layoutJson['outline'] as Map<String, dynamic>? ?? {};
    final typographyJson = editorJson['typography'] as Map<String, dynamic>? ?? {};
    final autoSaveJson = editorJson['autoSave'] as Map<String, dynamic>? ?? {};
    final autoBackupJson = editorJson['autoBackup'] as Map<String, dynamic>? ?? {};

    return AppSettings(
      // 主题设置（全局）
      themeMode: themeJson['mode'] as String? ?? defaults.themeMode,
      dimCoverInDarkMode: themeJson['dimCoverInDarkMode'] as bool? ?? defaults.dimCoverInDarkMode,
      activeCustomThemeId: themeJson['activeCustomThemeId'] as String?,
      customThemes: (themeJson['customThemes'] as List<dynamic>? ?? [])
          .map((e) => CustomTheme.fromJson(e as Map<String, dynamic>))
          .toList(),
      
      // 多窗口设置（全局）
      openWorkspaceInNewWindow: globalJson['openWorkspaceInNewWindow'] as bool? ?? defaults.openWorkspaceInNewWindow,
      
      // 布局设置（编辑器）
      showChapterTitle: chapterTitleJson['show'] as bool? ?? defaults.showChapterTitle,
      chapterTitleTopMargin: (chapterTitleJson['topMargin'] as num?)?.toDouble() ?? defaults.chapterTitleTopMargin,
      chapterTitleFontSize: (chapterTitleJson['fontSize'] as num?)?.toDouble() ?? defaults.chapterTitleFontSize,
      chapterTitleColorLight: chapterTitleColorJson['light'] as String? ?? defaults.chapterTitleColorLight,
      chapterTitleColorDark: chapterTitleColorJson['dark'] as String? ?? defaults.chapterTitleColorDark,
      topMargin: (pageJson['topMargin'] as num?)?.toDouble() ?? defaults.topMargin,
      horizontalMargin: (pageJson['horizontalMargin'] as num?)?.toDouble() ?? defaults.horizontalMargin,
      bottomMargin: (pageJson['bottomMargin'] as num?)?.toDouble() ?? defaults.bottomMargin,
      isPageViewEnabled: pageJson['viewEnabled'] as bool? ?? defaults.isPageViewEnabled,
      scrollbarAlwaysVisible: pageJson['scrollbarAlwaysVisible'] as bool? ?? defaults.scrollbarAlwaysVisible,

      // 大纲编辑器布局设置（编辑器）
      outlineTopMargin: (outlineLayoutJson['topMargin'] as num?)?.toDouble() ?? defaults.outlineTopMargin,
      outlineHorizontalMargin: (outlineLayoutJson['horizontalMargin'] as num?)?.toDouble() ?? defaults.outlineHorizontalMargin,
      outlineBottomMargin: (outlineLayoutJson['bottomMargin'] as num?)?.toDouble() ?? defaults.outlineBottomMargin,
      outlineNodeSpacing: (outlineLayoutJson['nodeSpacing'] as num?)?.toDouble() ?? defaults.outlineNodeSpacing,
      outlinePageViewMode: outlineLayoutJson['pageViewMode'] as String? ?? defaults.outlinePageViewMode,

      // 排版设置（编辑器）
      letterSpacing: (typographyJson['letterSpacing'] as num?)?.toDouble() ?? defaults.letterSpacing,
      lineHeight: (typographyJson['lineHeight'] as num?)?.toDouble() ?? defaults.lineHeight,
      isFirstLineIndentEnabled: typographyJson['firstLineIndent'] as bool? ?? defaults.isFirstLineIndentEnabled,
      autoLineBreak: typographyJson['autoLineBreak'] as bool? ?? defaults.autoLineBreak,
      showLineSeparator: typographyJson['lineSeparator'] as bool? ?? defaults.showLineSeparator,
      lineSeparatorStyle: typographyJson['lineSeparatorStyle'] as String? ?? defaults.lineSeparatorStyle,
      lineSeparatorOpacity: (typographyJson['lineSeparatorOpacity'] as num?)?.toDouble() ?? defaults.lineSeparatorOpacity,
      dialogueHighlightEnabled: typographyJson['dialogueHighlight'] as bool? ?? defaults.dialogueHighlightEnabled,
      dialogueHighlightColorLight: typographyJson['dialogueHighlightColorLight'] as String? ?? defaults.dialogueHighlightColorLight,
      dialogueHighlightColorDark: typographyJson['dialogueHighlightColorDark'] as String? ?? defaults.dialogueHighlightColorDark,
      
      // 字体设置（编辑器）
      fontFamily: fontJson['family'] as String? ?? defaults.fontFamily,
      fontSize: (fontJson['size'] as num?)?.toDouble() ?? defaults.fontSize,
      isBold: fontJson['bold'] as bool? ?? defaults.isBold,
      isItalic: fontJson['italic'] as bool? ?? defaults.isItalic,
      isUnderline: fontJson['underline'] as bool? ?? defaults.isUnderline,
      fontColorLight: fontColorJson['light'] as String? ?? defaults.fontColorLight,
      fontColorDark: fontColorJson['dark'] as String? ?? defaults.fontColorDark,

      // 大纲编辑器字体设置（编辑器）
      outlineFontFamily: fontJson['outlineFamily'] as String? ?? defaults.outlineFontFamily,
      outlineFontSize: (fontJson['outlineSize'] as num?)?.toDouble() ?? defaults.outlineFontSize,

      // 其他设置（编辑器）
      autoSaveEnabled: autoSaveJson['enabled'] as bool? ?? defaults.autoSaveEnabled,
      autoBackupEnabled: autoBackupJson['enabled'] as bool? ?? defaults.autoBackupEnabled,
      backupInterval: autoBackupJson['interval'] as int? ?? defaults.backupInterval,
      historyRetentionDays: autoBackupJson['historyRetentionDays'] as int? ?? defaults.historyRetentionDays,
      openChapterCursorMode: autoBackupJson['openCursorMode'] as String? ?? defaults.openChapterCursorMode,
      previewModeEnabled: autoBackupJson['previewModeEnabled'] as bool? ?? defaults.previewModeEnabled,
    );
  }

  /// 将 AppSettings 实例转换为 JSON Map
  /// 设置项分为两大类：全局设置、编辑器设置
  Map<String, dynamic> toJson() {
    return {
      // 全局设置
      'global': {
        // 主题设置
        'theme': {
          'mode': themeMode,
          'dimCoverInDarkMode': dimCoverInDarkMode,
          'activeCustomThemeId': activeCustomThemeId,
          'customThemes': customThemes.map((e) => e.toJson()).toList(),
        },
        // 多窗口设置
        'openWorkspaceInNewWindow': openWorkspaceInNewWindow,
      },
      // 编辑器设置
      'editor': {
        // 字体设置
        'font': {
          'family': fontFamily,
          'size': fontSize,
          'bold': isBold,
          'italic': isItalic,
          'underline': isUnderline,
          'color': {
            'light': fontColorLight,
            'dark': fontColorDark,
          },
          'outlineFamily': outlineFontFamily,
          'outlineSize': outlineFontSize,
        },
        // 布局设置
        'layout': {
          'chapterTitle': {
            'show': showChapterTitle,
            'topMargin': chapterTitleTopMargin,
            'fontSize': chapterTitleFontSize,
            'color': {
              'light': chapterTitleColorLight,
              'dark': chapterTitleColorDark,
            },
          },
          'page': {
            'topMargin': topMargin,
            'horizontalMargin': horizontalMargin,
            'bottomMargin': bottomMargin,
            'viewEnabled': isPageViewEnabled,
            'scrollbarAlwaysVisible': scrollbarAlwaysVisible,
          },
          'outline': {
            'topMargin': outlineTopMargin,
            'horizontalMargin': outlineHorizontalMargin,
            'bottomMargin': outlineBottomMargin,
            'nodeSpacing': outlineNodeSpacing,
            'pageViewMode': outlinePageViewMode,
          },
        },
        // 排版设置
        'typography': {
          'letterSpacing': letterSpacing,
          'lineHeight': lineHeight,
          'firstLineIndent': isFirstLineIndentEnabled,
          'autoLineBreak': autoLineBreak,
          'lineSeparator': showLineSeparator,
          'lineSeparatorStyle': lineSeparatorStyle,
          'lineSeparatorOpacity': lineSeparatorOpacity,
          'dialogueHighlight': dialogueHighlightEnabled,
          'dialogueHighlightColorLight': dialogueHighlightColorLight,
          'dialogueHighlightColorDark': dialogueHighlightColorDark,
        },
        // 其他设置
        'autoSave': {
          'enabled': autoSaveEnabled,
        },
        'autoBackup': {
          'enabled': autoBackupEnabled,
          'interval': backupInterval,
          'historyRetentionDays': historyRetentionDays,
          'openCursorMode': openChapterCursorMode,
          'previewModeEnabled': previewModeEnabled,
        },
      },
    };
  }

  // ================= 辅助方法 =================
  
  /// copyWith 中用于区分"未传入参数"和"传入 null"的哨兵值
  static const Object _unset = Object();

  /// 创建设置副本，用于更新部分设置项
  ///
  /// 对于 nullable 颜色字段（如 chapterTitleColorLight），使用 Object? 类型参数 + 哨兵值，
  /// 以支持将字段重置为 null（默认值）。传入 null 表示重置，不传入表示保持原值。
  AppSettings copyWith({
    String? themeMode,
    // 暗色模式下封面变暗
    bool? dimCoverInDarkMode,
    // 自定义主题
    Object? activeCustomThemeId = _unset,
    List<CustomTheme>? customThemes,
    // 多窗口设置
    bool? openWorkspaceInNewWindow,
    // 布局设置（右侧边栏 - 布局设置面板）
    bool? showChapterTitle,
    double? chapterTitleTopMargin,
    double? chapterTitleFontSize,
    Object? chapterTitleColorLight = _unset,
    Object? chapterTitleColorDark = _unset,
    double? topMargin,
    double? horizontalMargin,
    double? bottomMargin,
    bool? isPageViewEnabled,
    bool? scrollbarAlwaysVisible,
    // 大纲编辑器布局设置
    double? outlineTopMargin,
    double? outlineHorizontalMargin,
    double? outlineBottomMargin,
    double? outlineNodeSpacing,
    String? outlinePageViewMode,
    // 排版设置（右侧边栏 - 排版设置面板）
    double? letterSpacing,
    double? lineHeight,
    bool? isFirstLineIndentEnabled,
    bool? autoLineBreak,
    bool? showLineSeparator,
    String? lineSeparatorStyle,
    double? lineSeparatorOpacity,
    bool? dialogueHighlightEnabled,
    Object? dialogueHighlightColorLight = _unset,
    Object? dialogueHighlightColorDark = _unset,
    // 字体设置
    String? fontFamily,
    double? fontSize,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    Object? fontColorLight = _unset,
    Object? fontColorDark = _unset,
    // 大纲编辑器字体设置
    String? outlineFontFamily,
    double? outlineFontSize,
    // 其他设置（右侧边栏 - 其他设置面板）
    bool? autoSaveEnabled,
    bool? autoBackupEnabled,
    int? backupInterval,
    int? historyRetentionDays,
    String? openChapterCursorMode,
    bool? previewModeEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      // 暗色模式下封面变暗
      dimCoverInDarkMode: dimCoverInDarkMode ?? this.dimCoverInDarkMode,
      // 自定义主题
      activeCustomThemeId: activeCustomThemeId == _unset ? this.activeCustomThemeId : activeCustomThemeId as String?,
      customThemes: customThemes ?? this.customThemes,
      // 多窗口设置
      openWorkspaceInNewWindow: openWorkspaceInNewWindow ?? this.openWorkspaceInNewWindow,
      // 布局设置（右侧边栏 - 布局设置面板）
      showChapterTitle: showChapterTitle ?? this.showChapterTitle,
      chapterTitleTopMargin: chapterTitleTopMargin ?? this.chapterTitleTopMargin,
      chapterTitleFontSize: chapterTitleFontSize ?? this.chapterTitleFontSize,
      chapterTitleColorLight: chapterTitleColorLight == _unset ? this.chapterTitleColorLight : chapterTitleColorLight as String?,
      chapterTitleColorDark: chapterTitleColorDark == _unset ? this.chapterTitleColorDark : chapterTitleColorDark as String?,
      topMargin: topMargin ?? this.topMargin,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
      bottomMargin: bottomMargin ?? this.bottomMargin,
      isPageViewEnabled: isPageViewEnabled ?? this.isPageViewEnabled,
      scrollbarAlwaysVisible: scrollbarAlwaysVisible ?? this.scrollbarAlwaysVisible,
      // 大纲编辑器布局设置
      outlineTopMargin: outlineTopMargin ?? this.outlineTopMargin,
      outlineHorizontalMargin: outlineHorizontalMargin ?? this.outlineHorizontalMargin,
      outlineBottomMargin: outlineBottomMargin ?? this.outlineBottomMargin,
      outlineNodeSpacing: outlineNodeSpacing ?? this.outlineNodeSpacing,
      outlinePageViewMode: outlinePageViewMode ?? this.outlinePageViewMode,
      // 排版设置（右侧边栏 - 排版设置面板）
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      isFirstLineIndentEnabled: isFirstLineIndentEnabled ?? this.isFirstLineIndentEnabled,
      autoLineBreak: autoLineBreak ?? this.autoLineBreak,
      showLineSeparator: showLineSeparator ?? this.showLineSeparator,
      lineSeparatorStyle: lineSeparatorStyle ?? this.lineSeparatorStyle,
      lineSeparatorOpacity: lineSeparatorOpacity ?? this.lineSeparatorOpacity,
      dialogueHighlightEnabled: dialogueHighlightEnabled ?? this.dialogueHighlightEnabled,
      dialogueHighlightColorLight: dialogueHighlightColorLight == _unset ? this.dialogueHighlightColorLight : dialogueHighlightColorLight as String?,
      dialogueHighlightColorDark: dialogueHighlightColorDark == _unset ? this.dialogueHighlightColorDark : dialogueHighlightColorDark as String?,
      // 字体设置
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      fontColorLight: fontColorLight == _unset ? this.fontColorLight : fontColorLight as String?,
      fontColorDark: fontColorDark == _unset ? this.fontColorDark : fontColorDark as String?,
      // 大纲编辑器字体设置
      outlineFontFamily: outlineFontFamily ?? this.outlineFontFamily,
      outlineFontSize: outlineFontSize ?? this.outlineFontSize,
      // 其他设置（右侧边栏 - 其他设置面板）
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      backupInterval: backupInterval ?? this.backupInterval,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
      openChapterCursorMode: openChapterCursorMode ?? this.openChapterCursorMode,
      previewModeEnabled: previewModeEnabled ?? this.previewModeEnabled,
    );
  }

  /// 将 ThemeMode 转换为字符串
  static String themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// 将字符串转换为 ThemeMode
  static ThemeMode stringToThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// 获取当前的 ThemeMode 对象
  ThemeMode get themeModeValue => stringToThemeMode(themeMode);

  @override
  String toString() {
    return 'AppSettings(themeMode: $themeMode, openWorkspaceInNewWindow: $openWorkspaceInNewWindow, fontFamily: $fontFamily, fontSize: $fontSize, outlineFontFamily: $outlineFontFamily, outlineFontSize: $outlineFontSize)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings && 
           other.themeMode == themeMode &&
           other.dimCoverInDarkMode == dimCoverInDarkMode &&
           other.activeCustomThemeId == activeCustomThemeId &&
           listEquals(other.customThemes, customThemes) &&
           other.openWorkspaceInNewWindow == openWorkspaceInNewWindow &&
           // 布局设置（右侧边栏 - 布局设置面板）
           other.showChapterTitle == showChapterTitle &&
           other.chapterTitleTopMargin == chapterTitleTopMargin &&
           other.chapterTitleFontSize == chapterTitleFontSize &&
           other.chapterTitleColorLight == chapterTitleColorLight &&
           other.chapterTitleColorDark == chapterTitleColorDark &&
           other.topMargin == topMargin &&
           other.horizontalMargin == horizontalMargin &&
           other.bottomMargin == bottomMargin &&
           other.isPageViewEnabled == isPageViewEnabled &&
           other.scrollbarAlwaysVisible == scrollbarAlwaysVisible &&
           // 大纲编辑器布局设置
           other.outlineTopMargin == outlineTopMargin &&
           other.outlineHorizontalMargin == outlineHorizontalMargin &&
           other.outlineBottomMargin == outlineBottomMargin &&
           other.outlineNodeSpacing == outlineNodeSpacing &&
           other.outlinePageViewMode == outlinePageViewMode &&
           // 排版设置（右侧边栏 - 排版设置面板）
           other.letterSpacing == letterSpacing &&
           other.lineHeight == lineHeight &&
           other.isFirstLineIndentEnabled == isFirstLineIndentEnabled &&
           other.autoLineBreak == autoLineBreak &&
           other.showLineSeparator == showLineSeparator &&
           other.lineSeparatorStyle == lineSeparatorStyle &&
           other.lineSeparatorOpacity == lineSeparatorOpacity &&
           other.dialogueHighlightEnabled == dialogueHighlightEnabled &&
           other.dialogueHighlightColorLight == dialogueHighlightColorLight &&
           other.dialogueHighlightColorDark == dialogueHighlightColorDark &&
           // 字体设置
           other.fontFamily == fontFamily &&
           other.fontSize == fontSize &&
           other.isBold == isBold &&
           other.isItalic == isItalic &&
           other.isUnderline == isUnderline &&
           other.fontColorLight == fontColorLight &&
           other.fontColorDark == fontColorDark &&
           // 大纲编辑器字体设置
           other.outlineFontFamily == outlineFontFamily &&
           other.outlineFontSize == outlineFontSize &&
           // 其他设置（右侧边栏 - 其他设置面板）
           other.autoSaveEnabled == autoSaveEnabled &&
           other.autoBackupEnabled == autoBackupEnabled &&
           other.backupInterval == backupInterval &&
           other.historyRetentionDays == historyRetentionDays &&
           other.openChapterCursorMode == openChapterCursorMode &&
           other.previewModeEnabled == previewModeEnabled;
  }

  @override
  int get hashCode {
    // Object.hash 最多支持 20 个参数，这里分多次计算后合并
    return Object.hash(
      // 基础设置（主题、多窗口）
      Object.hash(
        themeMode, 
        dimCoverInDarkMode,
        openWorkspaceInNewWindow,
        activeCustomThemeId,
        Object.hashAll(customThemes),
      ),
      // 布局设置（右侧边栏 - 布局设置面板）
      Object.hash(
        showChapterTitle,
        chapterTitleTopMargin,
        chapterTitleFontSize,
        chapterTitleColorLight,
        chapterTitleColorDark,
        topMargin,
        horizontalMargin,
        bottomMargin,
        isPageViewEnabled,
        scrollbarAlwaysVisible,
        // 大纲编辑器布局设置
        outlineTopMargin,
        outlineHorizontalMargin,
        outlineBottomMargin,
        outlineNodeSpacing,
        outlinePageViewMode,
      ),
      // 排版设置（右侧边栏 - 排版设置面板）
      Object.hash(
        letterSpacing,
        lineHeight,
        isFirstLineIndentEnabled,
        autoLineBreak,
        showLineSeparator,
        lineSeparatorStyle,
        lineSeparatorOpacity,
      ),
      // 对话高亮设置
      Object.hash(
        dialogueHighlightEnabled,
        dialogueHighlightColorLight,
        dialogueHighlightColorDark,
      ),
      // 字体设置和其他设置
      Object.hash(
        fontFamily,
        fontSize,
        isBold,
        isItalic,
        isUnderline,
        fontColorLight,
        fontColorDark,
        // 大纲编辑器字体设置
        outlineFontFamily,
        outlineFontSize,
        // 其他设置（右侧边栏 - 其他设置面板）
        autoSaveEnabled,
        autoBackupEnabled,
        backupInterval,
        historyRetentionDays,
        openChapterCursorMode,
        previewModeEnabled,
      ),
    );
  }
}
