import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 通用缓存服务基类
///
/// 提供统一的缓存文件管理能力，所有具体的缓存服务都应继承或使用此类
/// 
/// 特性：
/// - 统一管理缓存目录（{应用根目录}/cache/）
/// - 使用 .cache 作为文件后缀名（内部格式为 JSON）
/// - 支持多种缓存数据类型，每种数据使用独立的 .cache 文件
/// - 提供通用的读写、序列化、反序列化方法
///
/// 缓存文件规划示例：
/// ```
/// cache/
/// ├── window.cache              # 窗体设置缓存
/// ├── chapter_position.cache    # 章节编辑位置缓存
/// └── ...                       # 其他缓存文件
/// ```
///
/// 使用方式（作为基类）：
/// ```dart
/// class WindowCacheService extends CacheService<WindowSettingsData> {
///   WindowCacheService() : super('window');
///   
///   // 实现具体的序列化方法
///   @override
///   WindowSettingsData fromJson(Map<String, dynamic> json) {
///     return WindowSettingsData.fromJson(json);
///   }
/// }
/// ```
abstract class CacheService<T> {
  // ================= 常量定义 =================

  /// 缓存文件后缀名
  static const String _fileExtension = '.cache';

  // ================= 状态属性 =================

  /// 缓存文件名（不含后缀）
  final String _fileName;

  /// 缓存目录路径
  String? _cacheDirPath;

  /// 缓存文件完整路径
  String? _cacheFilePath;

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ================= 构造函数 =================

  /// 创建缓存服务实例
  ///
  /// [fileName] 缓存文件名（不含后缀），例如：'window' 会生成 window.cache
  CacheService(this._fileName);

  // ================= 初始化方法 =================

  /// 初始化缓存服务
  ///
  /// 该方法应该在应用启动时调用（main.dart 中）
  /// 主要工作：
  /// 1. 确保 AppPaths 已初始化
  /// 2. 创建缓存目录（如果不存在）
  /// 3. 构建缓存文件路径
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('CacheService [$_fileName] 已经初始化，跳过重复初始化');
      return;
    }

    try {
      // 确保 AppPaths 已初始化
      if (!AppPaths.instance.isInitialized) {
        await AppPaths.instance.initialize();
      }

      // 获取并创建缓存目录
      _cacheDirPath = await AppPaths.instance.getCachePath();

      // 构建缓存文件完整路径
      _cacheFilePath = '$_cacheDirPath${Platform.pathSeparator}$_fileName$_fileExtension';

      _isInitialized = true;
      debugPrint('CacheService [$_fileName] 初始化完成，缓存文件路径: $_cacheFilePath');
    } catch (e, stackTrace) {
      debugPrint('CacheService [$_fileName] 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      rethrow;
    }
  }

  // ================= 抽象方法（子类必须实现） =================

  /// 从 JSON Map 反序列化为具体的数据对象
  ///
  /// 子类必须实现此方法，用于将 JSON 数据转换为对应的模型对象
  T fromJson(Map<String, dynamic> json);

  // ================= 缓存文件读写方法 =================

  /// 检查缓存文件是否存在
  Future<bool> exists() async {
    _assertInitialized();
    
    if (_cacheFilePath == null) return false;
    
    final file = File(_cacheFilePath!);
    return await file.exists();
  }

  /// 从缓存文件加载数据
  ///
  /// 如果缓存文件不存在或读取失败，返回 null
  Future<T?> load() async {
    _assertInitialized();

    if (_cacheFilePath == null) {
      debugPrint('CacheService [$_fileName]: 缓存文件路径为空');
      return null;
    }

    final cacheFile = File(_cacheFilePath!);

    if (!await cacheFile.exists()) {
      debugPrint('CacheService [$_fileName]: 缓存文件不存在');
      return null;
    }

    try {
      final content = await cacheFile.readAsString();
      final jsonMap = json.decode(content) as Map<String, dynamic>;
      final data = fromJson(jsonMap);
      debugPrint('CacheService [$_fileName]: 已加载缓存文件');
      return data;
    } catch (e) {
      debugPrint('CacheService [$_fileName]: 解析缓存文件失败: $e');
      return null;
    }
  }

  /// 保存数据到缓存文件
  ///
  /// [data] 要保存的数据对象
  /// 返回是否保存成功
  Future<bool> save(T data) async {
    _assertInitialized();

    if (_cacheFilePath == null) {
      debugPrint('CacheService [$_fileName]: 缓存文件路径为空，无法保存');
      return false;
    }

    try {
      // 调用数据的 toJson 方法获取 JSON Map
      final jsonData = (data as dynamic).toJson() as Map<String, dynamic>;
      
      final cacheFile = File(_cacheFilePath!);
      final jsonContent = const JsonEncoder.withIndent('  ').convert(jsonData);
      await cacheFile.writeAsString(jsonContent);
      // debugPrint('CacheService [$_fileName]: 缓存已保存');
      return true;
    } catch (e) {
      debugPrint('CacheService [$_fileName]: 保存缓存文件失败: $e');
      return false;
    }
  }

  /// 删除缓存文件
  ///
  /// 返回是否删除成功（如果文件不存在也返回 true）
  Future<bool> delete() async {
    _assertInitialized();

    if (_cacheFilePath == null) {
      debugPrint('CacheService [$_fileName]: 缓存文件路径为空');
      return false;
    }

    try {
      final cacheFile = File(_cacheFilePath!);

      if (!await cacheFile.exists()) {
        debugPrint('CacheService [$_fileName]: 缓存文件不存在，无需删除');
        return true;
      }

      await cacheFile.delete();
      debugPrint('CacheService [$_fileName]: 缓存文件已删除');
      return true;
    } catch (e) {
      debugPrint('CacheService [$_fileName]: 删除缓存文件失败: $e');
      return false;
    }
  }

  /// 清空缓存文件内容（删除后重新创建空文件）
  ///
  /// 返回是否清空成功
  Future<bool> clear() async {
    return await delete();
  }

  // ================= 工具方法 =================

  /// 获取缓存文件路径
  String? get cacheFilePath => _cacheFilePath;

  /// 获取缓存目录路径
  String? get cacheDirPath => _cacheDirPath;

  /// 获取缓存文件名（含后缀）
  String get cacheFileName => '$_fileName$_fileExtension';

  /// 确保已初始化
  void _assertInitialized() {
    if (!_isInitialized || _cacheFilePath == null) {
      throw StateError(
        'CacheService [$_fileName] 尚未初始化，请先调用 initialize()',
      );
    }
  }
}
