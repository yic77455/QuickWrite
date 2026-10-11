import 'package:flutter/material.dart';
import 'package:quick_write/core/models/cache_models/workspace_session_cache.dart';
import 'package:quick_write/core/services/cache_services/cache_service.dart';

/// 工作台会话缓存服务
///
/// 专门管理工作台的标签页会话数据，使用独立的缓存文件（workspace_session.cache）
///
/// 缓存内容包括：
/// - 每本书最后一次退出工作台时打开的标签页列表
/// - 退出时选中的标签页索引
///
/// 使用方式：
/// ```dart
/// // 初始化（在 main.dart 中）
/// await WorkspaceSessionCacheService.instance.initialize();
///
/// // 保存会话
/// await WorkspaceSessionCacheService.instance.saveSession(
///   bookUuid: 'book-uuid',
///   tabs: entries,
///   currentIndex: 2,
/// );
///
/// // 获取会话
/// final session = WorkspaceSessionCacheService.instance.getSession('book-uuid');
/// ```
class WorkspaceSessionCacheService extends CacheService<WorkspaceSessionCacheData> {
  // ================= 单例模式 =================

  static final WorkspaceSessionCacheService instance = WorkspaceSessionCacheService._internal();

  /// 私有构造函数
  WorkspaceSessionCacheService._internal() : super('workspace_session');

  // ================= 状态属性 =================

  /// 当前缓存的会话数据（内存中的副本）
  WorkspaceSessionCacheData _data = const WorkspaceSessionCacheData();

  /// 获取当前会话数据（只读访问）
  ///
  /// 注意：此方法返回的是内存中的数据，不会触发文件读取
  WorkspaceSessionCacheData get data => _data;

  // ================= 初始化方法 =================

  /// 初始化工作台会话缓存服务
  ///
  /// 该方法会：
  /// 1. 调用基类的 initialize() 创建缓存目录和文件路径
  /// 2. 尝试从 workspace_session.cache 文件加载已有的缓存数据
  /// 3. 如果文件不存在或读取失败，则使用空数据
  @override
  Future<void> initialize() async {
    try {
      // 先初始化基类（创建缓存目录等）
      await super.initialize();

      // 尝试从文件加载数据
      final loadedData = await load();

      if (loadedData != null) {
        _data = loadedData;
        debugPrint('WorkspaceSessionCacheService: 已从缓存文件加载数据');
      } else {
        debugPrint('WorkspaceSessionCacheService: 使用空数据（缓存文件不存在或为空）');
      }
    } catch (e, stackTrace) {
      debugPrint('WorkspaceSessionCacheService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      // 初始化失败时使用空数据，确保应用能正常运行
      _data = const WorkspaceSessionCacheData();
    }
  }

  // ================= 反序列化实现 =================

  @override
  WorkspaceSessionCacheData fromJson(Map<String, dynamic> json) {
    return WorkspaceSessionCacheData.fromJson(json);
  }

  // ================= 会话管理方法 =================

  /// 获取指定书籍的标签页会话
  ///
  /// [bookUuid] 书籍 UUID
  /// 返回会话，如果不存在则返回 null
  BookTabSession? getSession(String bookUuid) {
    return _data.getSession(bookUuid);
  }

  /// 保存指定书籍的标签页会话
  ///
  /// [bookUuid] 书籍 UUID
  /// [tabs] 打开的标签页列表
  /// [currentIndex] 当前选中的标签页索引
  Future<bool> saveSession({
    required String bookUuid,
    required List<TabSessionEntry> tabs,
    required int currentIndex,
  }) async {
    _data = _data.withSession(
      bookUuid,
      BookTabSession(tabs: tabs, currentIndex: currentIndex),
    );
    return await save(_data);
  }

  /// 移除指定书籍的会话缓存
  ///
  /// [bookUuid] 书籍 UUID
  Future<bool> removeBook(String bookUuid) async {
    _data = _data.withoutBook(bookUuid);
    return await save(_data);
  }

  /// 清空所有会话缓存
  Future<bool> clearAll() async {
    _data = _data.clear();
    return await save(_data);
  }
}