import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 应用路径管理服务
/// 
/// 单例模式，负责统一管理应用的所有文件系统路径：
/// - 配置目录路径
/// - 数据库文件路径
/// - 配置文件路径
/// - 书籍存储路径等
/// 
/// 使用方式：
/// ```dart
/// // 在 main.dart 中初始化（必须在 runApp 之前调用）
/// await AppPaths.instance.initialize();
/// 
/// // 获取各种路径
/// final dbPath = AppPaths.instance.databasePath;
/// final configPath = AppPaths.instance.configFilePath;
/// ```
class AppPaths {
  // ================= 单例模式 =================
  static final AppPaths instance = AppPaths._internal();
  AppPaths._internal();

  // ================= 私有常量 =================
  
  /// 应用名称（用于配置目录名）
  static const String _appName = 'QuickWrite';
  
  /// 配置文件名
  static const String _configFileName = 'settings.json';
  
  /// 数据库文件名
  static const String _databaseName = 'quick_write_db';

  /// 书籍存储目录名
  static const String _worksDirName = 'works';

  /// 缓存目录名
  static const String _cacheDirName = 'cache';

  /// 回收站目录名
  static const String _recycleBinDirName = 'recycle_bin';

  /// 备份目录名
  static const String _backupsDirName = 'backups';

  /// 云同步目录名
  static const String _syncDirName = 'sync';

  // ================= 状态属性 =================
  
  /// 应用根目录（文档目录下的 QuickWrite 文件夹）
  String? _appRootPath;
  
  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ================= 初始化方法 =================
  
  /// 初始化路径服务
  /// 
  /// 该方法应该在应用启动时调用（main.dart 中）
  /// 主要工作：
  /// 1. 获取文档目录路径
  /// 2. 创建应用根目录（如果不存在）
  /// 3. 缓存各种路径供后续使用
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('AppPaths 已经初始化，跳过重复初始化');
      return;
    }

    try {
      // 获取操作系统的文档目录（如 Windows 的 "我的文档"）
      final documentsDir = await getApplicationDocumentsDirectory();
      debugPrint('文档目录: ${documentsDir.path}');

      // 构建应用根目录路径
      _appRootPath = '${documentsDir.path}${Platform.pathSeparator}$_appName';

      // 创建应用根目录（如果不存在）
      final appRootDir = Directory(_appRootPath!);
      if (!await appRootDir.exists()) {
        await appRootDir.create(recursive: true);
        debugPrint('已创建应用根目录: $_appRootPath');
      } else {
        debugPrint('应用根目录已存在: $_appRootPath');
      }

      _isInitialized = true;
      debugPrint('AppPaths 初始化完成');
    } catch (e, stackTrace) {
      debugPrint('AppPaths 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      rethrow;
    }
  }

  // ================= 路径 Getter =================
  
  /// 应用根目录路径
  /// 
  /// 例如：C:\Users\用户名\Documents\QuickWrite
  String get appRootPath {
    _assertInitialized();
    return _appRootPath!;
  }

  /// 数据库目录路径（Isar 数据库存放位置）
  /// 
  /// 与应用根目录相同，Isar 会在此目录下创建数据库文件
  String get databaseDirectory {
    _assertInitialized();
    return _appRootPath!;
  }

  /// 数据库文件名
  String get databaseName => _databaseName;

  /// 配置文件完整路径
  /// 
  /// 例如：C:\Users\用户名\Documents\QuickWrite\settings.json
  String get configFilePath {
    _assertInitialized();
    return '$_appRootPath${Platform.pathSeparator}$_configFileName';
  }

  /// 配置文件名
  String get configFileName => _configFileName;

  /// 应用名称
  String get appName => _appName;

  // ================= 工具方法 =================
  
  /// 确保已初始化
  void _assertInitialized() {
    if (!_isInitialized || _appRootPath == null) {
      throw StateError(
        'AppPaths 尚未初始化，请先调用 AppPaths.instance.initialize()',
      );
    }
  }

  /// 获取书籍存储目录路径
  /// 
  /// 用于存储书籍相关的文件（封面、内容等）
  /// 如果目录不存在会自动创建
  Future<String> getBooksPath() async {
    _assertInitialized();
    
    final booksPath = '$_appRootPath${Platform.pathSeparator}$_worksDirName';
    final booksDir = Directory(booksPath);
    
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
      debugPrint('已创建书籍目录: $booksPath');
    }
    
    return booksPath;
  }

  /// 获取缓存目录路径
  /// 
  /// 使用系统标准的应用支持目录：
  /// - Windows: C:\Users\用户名\AppData\Roaming\QuickWrite\quick_write\cache
  /// - macOS: ~/Library/Application Support/com.quickwrite.app/cache
  /// - Linux: ~/.local/share/com.quickwrite.app/cache
  /// 
  /// 用于存储窗体状态、编辑位置等临时性缓存数据
  /// 如果目录不存在会自动创建
  Future<String> getCachePath() async {
    final cachePath = '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}$_cacheDirName';
    final cacheDir = Directory(cachePath);
    
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
      debugPrint('已创建缓存目录: $cachePath');
    }
    
    return cachePath;
  }

  /// 获取回收站目录路径
  /// 
  /// 用于存储被删除的书籍文件夹
  /// 如果目录不存在会自动创建
  Future<String> getRecycleBinPath() async {
    _assertInitialized();
    
    final recycleBinPath = '$_appRootPath${Platform.pathSeparator}$_recycleBinDirName';
    final recycleBinDir = Directory(recycleBinPath);
    
    if (!await recycleBinDir.exists()) {
      await recycleBinDir.create(recursive: true);
      debugPrint('已创建回收站目录: $recycleBinPath');
    }
    
    return recycleBinPath;
  }

  /// 获取备份目录路径
  /// 
  /// 与 works、recycle_bin 同级，用于存储章节历史备份
  /// 内部按书籍名称建立子文件夹
  /// 如果目录不存在会自动创建
  Future<String> getBackupPath() async {
    _assertInitialized();
    
    final backupPath = '$_appRootPath${Platform.pathSeparator}$_backupsDirName';
    final backupDir = Directory(backupPath);
    
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
      debugPrint('已创建备份目录: $backupPath');
    }
    
    return backupPath;
  }

  /// 获取云同步目录路径
  /// 
  /// 用于存储本机云同步的配置与同步状态
  /// 该目录属于设备私有数据，不参与云端同步
  /// 如果目录不存在会自动创建
  Future<String> getSyncPath() async {
    _assertInitialized();
    
    final syncPath = '$_appRootPath${Platform.pathSeparator}$_syncDirName';
    final syncDir = Directory(syncPath);
    
    if (!await syncDir.exists()) {
      await syncDir.create(recursive: true);
      debugPrint('已创建云同步目录: $syncPath');
    }
    
    return syncPath;
  }
}
