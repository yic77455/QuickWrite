import 'dart:io';

import 'package:flutter/foundation.dart';

/// 平台检测
///
/// 集中收拢全项目对运行平台的判断，避免 `Platform.isWindows` 一类的检查散落在各处。
/// 调用方应优先使用表达意图的能力开关（如 [supportsMultiWindow]），而不是直接判断操作系统名称，
/// 这样当某项能力在更多平台开放时，只需修改本文件，无需逐个改动调用点。
///
/// 注意：所有对 [Platform] 的访问都先经过 [kIsWeb] 判断，
/// 因为 Web 平台不存在 dart:io 的 Platform，直接访问会抛异常。
class PlatformCapabilities {
  PlatformCapabilities._();

  // ================= 平台身份 =================

  /// 是否为 Web 平台
  static bool get isWeb => kIsWeb;

  /// 是否为 Windows 桌面平台
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// 是否为 macOS 桌面平台
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// 是否为 Linux 桌面平台
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// 是否为桌面平台（Windows / macOS / Linux）
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  /// 是否为 Android 移动平台
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 是否为移动平台（Android / iOS）
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // ================= 平台能力 =================

  /// 是否支持多窗口工作台
  ///
  /// 依赖 desktop_multi_window，仅桌面端可用
  static bool get supportsMultiWindow => isDesktop;

  /// 是否支持系统托盘图标
  ///
  /// 依赖 tray_manager，仅桌面端可用
  static bool get supportsSystemTray => isDesktop;

  /// 是否支持原生窗口控制（窗口大小、位置、最小化/最大化等）
  ///
  /// 依赖 window_manager，仅桌面端可用
  static bool get supportsNativeWindowControl => isDesktop;

  /// 是否支持在系统文件管理器中打开或定位目录
  ///
  /// 依赖桌面文件管理器（explorer / open / xdg-open），移动端没有对应概念
  static bool get supportsFileManagerReveal => isDesktop;

  /// 是否支持枚举系统字体列表
  ///
  /// 依赖桌面系统的字体目录，移动端无法枚举，字体选择类功能不适用
  static bool get supportsSystemFontEnumeration => isDesktop;

  /// 是否具备鼠标悬停交互
  ///
  /// 桌面端有鼠标指针，可用悬停显示附加操作；移动端没有悬停状态，
  /// 依赖悬停才出现的入口需要改为常显，否则用户无法触达
  static bool get supportsHover => isDesktop;

  /// 是否具备键盘快捷键输入
  ///
  /// 桌面端有物理键盘，快捷键相关的入口（如快捷键列表）才有意义；
  /// 移动端通常只有软键盘，不适用
  static bool get supportsKeyboardShortcuts => isDesktop;

  /// 是否支持单实例约束
  ///
  /// 依赖 Windows 命名互斥体，目前仅 Windows 实现
  static bool get supportsSingleInstanceLock => isWindows;

  /// 是否需要修正输入法候选框位置
  ///
  /// 仅 Flutter Windows 端存在候选框不跟随光标的缺陷，需要原生层介入修正
  static bool get needsImeCursorFix => isWindows;
}