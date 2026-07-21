import 'package:flutter/material.dart';
import 'package:quick_write/core/models/cache_models/chapter_cursor_cache.dart';
import 'package:quick_write/core/services/cache_services/cache_service.dart';

/// 章节光标位置缓存服务
///
/// 专门管理章节编辑时的光标位置数据，使用独立的缓存文件（chapter_cursor.cache）
/// 
/// 缓存内容包括：
/// - 每本书每个章节的光标偏移量
/// - 每个章节的滚动位置
/// - 最后更新时间
///
/// 使用方式：
/// ```dart
/// // 初始化（在 main.dart 中）
/// await ChapterCursorCacheService.instance.initialize();
///
/// // 保存光标位置
/// await ChapterCursorCacheService.instance.saveCursorPosition(
///   bookUuid: 'book-uuid',
///   chapterUuid: 'chapter-uuid',
///   offset: 100,
///   scrollOffset: 50.0,
/// );
///
/// // 获取光标位置
/// final position = ChapterCursorCacheService.instance.getCursorPosition(
///   bookUuid: 'book-uuid',
///   chapterUuid: 'chapter-uuid',
/// );
/// ```
class ChapterCursorCacheService extends CacheService<ChapterCursorCacheData> {
  // ================= 单例模式 =================

  static final ChapterCursorCacheService instance = ChapterCursorCacheService._internal();

  /// 私有构造函数
  ChapterCursorCacheService._internal() : super('chapter_cursor');

  // ================= 状态属性 =================

  /// 当前缓存的光标位置数据（内存中的副本）
  ChapterCursorCacheData _data = const ChapterCursorCacheData();

  /// 获取当前光标位置数据（只读访问）
  ///
  /// 注意：此方法返回的是内存中的数据，不会触发文件读取
  /// 如果需要从文件重新加载，请调用 load() 方法
  ChapterCursorCacheData get data => _data;

  // ================= 初始化方法 =================

  /// 初始化章节光标缓存服务
  ///
  /// 该方法会：
  /// 1. 调用基类的 initialize() 创建缓存目录和文件路径
  /// 2. 尝试从 chapter_cursor.cache 文件加载已有的缓存数据
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
        debugPrint('ChapterCursorCacheService: 已从缓存文件加载数据');
      } else {
        debugPrint('ChapterCursorCacheService: 使用空数据（缓存文件不存在或为空）');
      }
    } catch (e, stackTrace) {
      debugPrint('ChapterCursorCacheService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      // 初始化失败时使用空数据，确保应用能正常运行
      _data = const ChapterCursorCacheData();
    }
  }

  // ================= 反序列化实现 =================

  @override
  ChapterCursorCacheData fromJson(Map<String, dynamic> json) {
    return ChapterCursorCacheData.fromJson(json);
  }

  // ================= 光标位置管理方法 =================

  /// 获取指定章节的光标位置
  ///
  /// [bookUuid] 书籍 UUID
  /// [chapterUuid] 章节 UUID
  /// 返回光标位置，如果不存在则返回 null
  ChapterCursorPosition? getCursorPosition({
    required String bookUuid,
    required String chapterUuid,
  }) {
    return _data.getCursorPosition(bookUuid, chapterUuid);
  }

  /// 保存章节光标位置
  ///
  /// [bookUuid] 书籍 UUID
  /// [chapterUuid] 章节 UUID
  /// [offset] 光标偏移量（字符位置）
  Future<bool> saveCursorPosition({
    required String bookUuid,
    required String chapterUuid,
    required int offset,
  }) async {
    final position = ChapterCursorPosition(
      offset: offset,
      updatedAt: DateTime.now(),
    );

    _data = _data.withCursorPosition(bookUuid, chapterUuid, position);
    return await save(_data);
  }

  /// 移除指定书籍的所有光标位置缓存
  ///
  /// [bookUuid] 书籍 UUID
  Future<bool> removeBook(String bookUuid) async {
    _data = _data.withoutBook(bookUuid);
    return await save(_data);
  }

  /// 移除指定章节的光标位置缓存
  ///
  /// [bookUuid] 书籍 UUID
  /// [chapterUuid] 章节 UUID
  Future<bool> removeChapter({
    required String bookUuid,
    required String chapterUuid,
  }) async {
    _data = _data.withoutChapter(bookUuid, chapterUuid);
    return await save(_data);
  }

  /// 清空所有光标位置缓存
  Future<bool> clearAll() async {
    _data = _data.clear();
    return await save(_data);
  }
}
