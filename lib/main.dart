import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/app.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/cache_services/chapter_cursor_cache_service.dart';
import 'package:quick_write/core/services/font_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/window_service.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';

void main(List<String> args) async {
  // 必须确保 Flutter 绑定初始化完成，在 main() 函数中，如果需要在 runApp() 之前调用任何异步方法或原生插件，就必须先调用ensureInitialized()这个方法
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化设置服务（必须在其他服务初始化之前）
  // 这会创建配置目录并加载用户设置
  await SettingsService.instance.initialize();
  
  // 初始化窗体缓存服务（用于独立管理窗体的临时性数据）
  // 包括：窗口大小、位置、最大化状态、侧边栏状态等
  await WindowCacheService.instance.initialize();
  
  // 初始化章节光标缓存服务（用于存储章节编辑时的光标位置）
  await ChapterCursorCacheService.instance.initialize();
  
  // 初始化杂项缓存服务（用于存储分组展开状态、书架分组选择等零散数据）
  await MiscCacheService.instance.initialize();
  
  // 初始化字体服务，加载系统字体列表
  await FontService().initialize();

  // 获取当前窗口控制器
  final windowController = await WindowController.fromCurrentEngine();
  
  // 解析窗口参数
  final arguments = _parseArguments(windowController.arguments);
  final type = arguments['type'] as String?;
  final bookId = arguments['bookId'] as String?;
  
  // 根据窗口类型运行不同的应用
  if (type == MultiWindowService.workspaceWindowType && bookId != null) {
    // 初始化工作台窗口
    await WindowService.instance.initializeWorkspaceWindow();
    runApp(WorkspaceApp(bookId: bookId, mainWindowId: arguments['mainWindowId'] as String?));
    return;
  }

  // 初始化主窗口
  await WindowService.instance.initializeMainWindow();
  // 初始化多窗口通信通道（主窗口负责监听子窗口的消息）
  await MultiWindowService.instance.initMethodChannel(windowController);
  // 后台异步清理过期备份
  BackupService.instance.cleanupExpiredBackups();
  runApp(const MyWriterApp());
}

/// 解析窗口参数
Map<String, dynamic> _parseArguments(dynamic arguments) {
  if (arguments == null) return {};
  try {
    if (arguments is String) {
      // 空字符串直接返回空 Map，避免 jsonDecode 报错
      if (arguments.isEmpty) return {};
      return jsonDecode(arguments) as Map<String, dynamic>;
    }
    return arguments as Map<String, dynamic>;
  } catch (e) {
    debugPrint('解析窗口参数失败: $e');
    return {};
  }
}
