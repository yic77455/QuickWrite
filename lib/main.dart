import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/app.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/services/app_info_service.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/database_service.dart';
import 'package:quick_write/core/services/cache_services/chapter_cursor_cache_service.dart';
import 'package:quick_write/core/services/cache_services/workspace_session_cache_service.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/font_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/single_instance_service.dart';
import 'package:quick_write/core/services/tray_service.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/cache_services/name_gen_cache_service.dart';
import 'package:quick_write/core/services/window_service.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:quick_write/core/router/router.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/pages/home/cloud_sync/widgets/sync_conflict_dialog.dart';
import 'package:quick_write/pages/home/cloud_sync/widgets/sync_risk_dialog.dart';
import 'package:quick_write/shared/widgets/qw_snackbar.dart';

void main(List<String> args) async {
  // 必须确保 Flutter 绑定初始化完成，在 main() 函数中，如果需要在 runApp() 之前调用任何异步方法或原生插件，就必须先调用ensureInitialized()这个方法
  WidgetsFlutterBinding.ensureInitialized();

  // 移动端开启边到边显示：应用界面延伸到状态栏与系统导航栏后方，
  // 由各页面通过安全区避开系统栏，保证系统栏与界面颜色统一
  if (PlatformCapabilities.isMobile) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // 初始化设置服务（必须在其他服务初始化之前）
  // 这会创建配置目录并加载用户设置
  await SettingsService.instance.initialize();

  // 读取应用包信息，缓存版本号供关于页与更新检查使用
  await AppInfoService.instance.initialize();

  // 获取当前窗口控制器并解析窗口参数
  // 多窗口与窗口参数仅存在于支持多窗口的桌面端，移动端没有窗口概念，视为无参数
  WindowController? windowController;
  Map<String, dynamic> arguments = const {};
  if (PlatformCapabilities.supportsMultiWindow) {
    windowController = await WindowController.fromCurrentEngine();
    arguments = _parseArguments(windowController.arguments);
  }
  final type = arguments['type'] as String?;
  final bookId = arguments['bookId'] as String?;

  // 限制同时只运行一个程序进程：若已有进程在运行，
  // 则唤出对方主窗口并退出当前进程
  // 工作台子窗口与主窗口同属一个进程，必须跳过该检查，避免误杀宿主进程
  if (PlatformCapabilities.supportsSingleInstanceLock &&
      type != MultiWindowService.workspaceWindowType) {
    if (!SingleInstanceService.instance.tryAcquire()) {
      debugPrint('已检测到运行中的实例，唤出其主窗口后退出当前进程');
      SingleInstanceService.instance.activateExistingMainWindow();
      exit(0);
    }
  }

  // 初始化窗体缓存服务（用于独立管理窗体的临时性数据）
  // 包括：窗口大小、位置、最大化状态、侧边栏状态等
  await WindowCacheService.instance.initialize();
  
  // 初始化章节光标缓存服务（用于存储章节编辑时的光标位置）
  await ChapterCursorCacheService.instance.initialize();
  
  // 初始化杂项缓存服务（用于存储分组展开状态、书架分组选择等零散数据）
  await MiscCacheService.instance.initialize();
  
  // 初始化随机取名缓存服务（用于存储取名词典、收藏与生成历史）
  await NameGenCacheService.instance.initialize();

  // 初始化工作台会话缓存服务（用于恢复上次退出时打开的标签页）
  await WorkspaceSessionCacheService.instance.initialize();
  
  // 初始化字体服务，加载系统字体列表
  await FontService().initialize();

  // 校验字体设置引用的字体在本机是否可用，避免云同步带入本机不存在的字体
  await SettingsService.instance.validateFontAvailability();

  // 根据窗口类型运行不同的应用
  if (type == MultiWindowService.workspaceWindowType && bookId != null) {
    // 初始化工作台窗口
    await WindowService.instance.initializeWorkspaceWindow();
    runApp(WorkspaceApp(bookId: bookId, mainWindowId: arguments['mainWindowId'] as String?));
    return;
  }

  // 初始化主窗口（仅支持原生窗口控制的平台需要）
  if (PlatformCapabilities.supportsNativeWindowControl) {
    await WindowService.instance.initializeMainWindow();
  }

  // 初始化云同步服务，读取本机保存的连接配置与同步设置
  // 仅在主窗口初始化，自动同步统一由主窗口负责，避免多个窗口重复执行
  await CloudSyncService.instance.initialize();

  // 注入全局同步风险确认，使自动同步、启动同步等任意时机被风险预检拦截时
  // 都能立刻弹窗告知用户，而不再只依赖云同步页面的角标提示
  CloudSyncService.instance.setRiskConfirmHandler(
    (risk) => showSyncRiskDialog(appNavigatorKey, risk),
  );

  // 注入全局同步提示，使自动同步失败等情况能立即以浮动提示告知用户
  CloudSyncService.instance.setNoticeHandler(_showSyncNotice);

  // 注入全局冲突副本提示，使同步为本机版本另存出的冲突副本能立即弹窗告知用户
  CloudSyncService.instance.setConflictNoticeHandler(
    (conflicts) => showSyncConflictDialog(appNavigatorKey, conflicts),
  );

  // 初始化多窗口通信通道（主窗口负责监听子窗口的消息）
  if (PlatformCapabilities.supportsMultiWindow && windowController != null) {
    await MultiWindowService.instance.initMethodChannel(windowController);
  }

  // 初始化系统托盘图标（仅主窗口常驻，用于最小化至托盘与快捷退出）
  if (PlatformCapabilities.supportsSystemTray) {
    await TrayService.instance.initialize();
  }

  // 后台异步清理过期备份
  BackupService.instance.cleanupExpiredBackups();
  runApp(const MyWriterApp());

  // 启动时按设置自动打开上一次编辑的作品（不阻塞首帧渲染）
  _autoOpenLastEditedWorkOnStartup();
}

/// 启动时按设置自动打开上一次编辑的作品
///
/// 在界面完成首帧渲染后触发：若开启了相关设置，先等待启动同步补齐本地文件，
/// 再查询最近编辑的作品并跳转到其工作台。
/// 多窗口模式下该跳转会被路由重定向拦截，改为在新窗口中打开。
Future<void> _autoOpenLastEditedWorkOnStartup() async {
  if (!SettingsService.instance.autoOpenLastWorkOnStartup) return;

  // 等待首帧渲染完成，确保路由器已挂载
  await WidgetsBinding.instance.endOfFrame;

  // 等待启动同步结束，避免在作品文件尚未补齐时打开
  await CloudSyncService.instance.awaitStartupSync();

  // 查询最近编辑的作品（updatedAt 最大者）
  final isar = await DatabaseService.instance.open();
  final books = await isar.bookModels.where().findAll();
  if (books.isEmpty) return;

  final recentBook = books.reduce(
    (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
  );

  // 跳转到该作品的工作台
  appRouter.go('/workspace/${recentBook.uuid}');
}

/// 在根导航器的浮层上显示同步提示
///
/// 提示由服务层在任意时机发起，没有页面上下文，因此直接使用根导航器的 Overlay
void _showSyncNotice(String message) {
  final overlay = appNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  SnackBarService.showOnOverlay(overlay, message);
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
