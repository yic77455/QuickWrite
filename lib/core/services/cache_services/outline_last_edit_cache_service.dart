import 'package:flutter/material.dart';
import 'package:quick_write/core/models/cache_models/outline_last_edit_cache.dart';
import 'package:quick_write/core/services/cache_services/cache_service.dart';

/// 大纲上次编辑节点缓存服务
///
/// 专门管理各设定项最后一次编辑的节点位置，使用独立的缓存文件（outline_last_edit.cache）
///
/// 缓存内容包括：
/// - 每本书每个设定项上次编辑节点的层级索引路径
/// - 最后更新时间
///
/// 使用方式：
/// ```dart
/// // 初始化（在 main.dart 中）
/// await OutlineLastEditCacheService.instance.initialize();
///
/// // 保存上次编辑节点
/// await OutlineLastEditCacheService.instance.saveLastEditedPath(
///   bookUuid: 'book-uuid',
///   settingItemUuid: 'setting-item-uuid',
///   path: '0.2.1',
/// );
///
/// // 获取上次编辑节点
/// final path = OutlineLastEditCacheService.instance.getLastEditedPath(
///   bookUuid: 'book-uuid',
///   settingItemUuid: 'setting-item-uuid',
/// );
/// ```
class OutlineLastEditCacheService extends CacheService<OutlineLastEditCacheData> {
  // ================= 单例模式 =================

  static final OutlineLastEditCacheService instance = OutlineLastEditCacheService._internal();

  /// 私有构造函数
  OutlineLastEditCacheService._internal() : super('outline_last_edit');

  // ================= 状态属性 =================

  /// 当前缓存的上次编辑节点数据（内存中的副本）
  OutlineLastEditCacheData _data = const OutlineLastEditCacheData();

  /// 获取当前缓存数据（只读访问）
  ///
  /// 注意：此方法返回的是内存中的数据，不会触发文件读取
  OutlineLastEditCacheData get data => _data;

  // ================= 初始化方法 =================

  /// 初始化缓存服务
  ///
  /// 该方法会：
  /// 1. 调用基类的 initialize() 创建缓存目录和文件路径
  /// 2. 尝试从 outline_last_edit.cache 文件加载已有的缓存数据
  /// 3. 如果文件不存在或读取失败，则使用空数据
  @override
  Future<void> initialize() async {
    try {
      await super.initialize();

      final loadedData = await load();

      if (loadedData != null) {
        _data = loadedData;
        debugPrint('OutlineLastEditCacheService: 已从缓存文件加载数据');
      } else {
        debugPrint('OutlineLastEditCacheService: 使用空数据（缓存文件不存在或为空）');
      }
    } catch (e, stackTrace) {
      debugPrint('OutlineLastEditCacheService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      // 初始化失败时使用空数据，确保应用能正常运行
      _data = const OutlineLastEditCacheData();
    }
  }

  // ================= 反序列化实现 =================

  @override
  OutlineLastEditCacheData fromJson(Map<String, dynamic> json) {
    return OutlineLastEditCacheData.fromJson(json);
  }

  // ================= 上次编辑节点管理方法 =================

  /// 获取指定设定项上次编辑节点的路径
  ///
  /// [bookUuid] 书籍 UUID
  /// [settingItemUuid] 设定项 UUID
  /// 返回节点路径，未记录时返回 null
  String? getLastEditedPath({
    required String bookUuid,
    required String settingItemUuid,
  }) {
    return _data.getLastEditedPath(bookUuid, settingItemUuid);
  }

  /// 保存指定设定项上次编辑节点的路径
  ///
  /// [bookUuid] 书籍 UUID
  /// [settingItemUuid] 设定项 UUID
  /// [path] 节点自根节点起的层级索引路径
  Future<bool> saveLastEditedPath({
    required String bookUuid,
    required String settingItemUuid,
    required String path,
  }) async {
    final position = OutlineLastEditPosition(
      path: path,
      updatedAt: DateTime.now(),
    );

    _data = _data.withLastEditedPath(bookUuid, settingItemUuid, position);
    return await save(_data);
  }

  /// 移除指定设定项的上次编辑记录
  Future<bool> removeSettingItem({
    required String bookUuid,
    required String settingItemUuid,
  }) async {
    _data = _data.withoutSettingItem(bookUuid, settingItemUuid);
    return await save(_data);
  }

  /// 移除指定书籍的所有上次编辑记录
  Future<bool> removeBook(String bookUuid) async {
    _data = _data.withoutBook(bookUuid);
    return await save(_data);
  }

  /// 清空所有上次编辑记录
  Future<bool> clearAll() async {
    _data = _data.clear();
    return await save(_data);
  }
}
