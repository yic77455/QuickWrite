import 'package:flutter/material.dart';
import 'package:quick_write/core/models/cache_models/misc_cache.dart';
import 'package:quick_write/core/services/cache_services/cache_service.dart';

/// 杂项缓存服务
///
/// 统一管理各类零散的缓存数据，避免创建过多小文件
/// 使用独立的缓存文件（misc.cache）
///
/// 缓存内容包括：
/// - 书架上当前选中的分组 ID
/// - 每本书的未分卷组、未分组设定组折叠状态
/// - 新建章节、设定时分卷或分组选择记忆
/// - 章节、设定列表是否倒序排列
/// - 统计界面是否包含粘贴字数
/// - 工具面板区块显示顺序
class MiscCacheService extends CacheService<MiscCacheData> {
  // ================= 单例模式 =================

  static final MiscCacheService instance = MiscCacheService._internal();

  /// 私有构造函数
  MiscCacheService._internal() : super('misc');

  // ================= 状态属性 =================

  /// 当前缓存数据（内存中的副本）
  MiscCacheData _data = const MiscCacheData();

  /// 获取当前缓存数据（只读访问）
  MiscCacheData get data => _data;

  // ================= 初始化方法 =================

  @override
  Future<void> initialize() async {
    try {
      await super.initialize();

      final loadedData = await load();

      if (loadedData != null) {
        _data = loadedData;
        debugPrint('MiscCacheService: 已从缓存文件加载数据');
      } else {
        debugPrint('MiscCacheService: 使用空数据（缓存文件不存在或为空）');
      }
    } catch (e, stackTrace) {
      debugPrint('MiscCacheService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      _data = const MiscCacheData();
    }
  }

  // ================= 反序列化实现 =================

  @override
  MiscCacheData fromJson(Map<String, dynamic> json) {
    return MiscCacheData.fromJson(json);
  }

  // ================= 书架分组选择状态 =================

  /// 获取书架选中的分组 ID
  String getSelectedGroupId() {
    return _data.selectedGroupId;
  }

  /// 保存书架选中的分组 ID
  Future<bool> saveSelectedGroupId(String groupId) async {
    _data = _data.copyWith(selectedGroupId: groupId);
    return await save(_data);
  }

  // ================= 未分卷组折叠状态 =================

  /// 获取指定书籍的未分卷组是否折叠
  bool isUnassignedCollapsed(String bookUuid) {
    return _data.books[bookUuid]?.isUnassignedCollapsed ?? false;
  }

  /// 保存指定书籍的未分卷组折叠状态
  Future<bool> saveUnassignedCollapsed(String bookUuid, bool collapsed) async {
    final bookCache = _data.books[bookUuid] ?? const BookGroupExpandCache();
    final newBooks = Map<String, BookGroupExpandCache>.from(_data.books);
    newBooks[bookUuid] = bookCache.copyWith(isUnassignedCollapsed: collapsed);
    _data = _data.copyWith(books: newBooks);
    return await save(_data);
  }

  // ================= 未分组设定组折叠状态 =================

  /// 获取指定书籍的未分组设定组是否折叠
  bool isSettingUnassignedCollapsed(String bookUuid) {
    return _data.books[bookUuid]?.isSettingUnassignedCollapsed ?? false;
  }

  /// 保存指定书籍的未分组设定组折叠状态
  Future<bool> saveSettingUnassignedCollapsed(String bookUuid, bool collapsed) async {
    final bookCache = _data.books[bookUuid] ?? const BookGroupExpandCache();
    final newBooks = Map<String, BookGroupExpandCache>.from(_data.books);
    newBooks[bookUuid] = bookCache.copyWith(isSettingUnassignedCollapsed: collapsed);
    _data = _data.copyWith(books: newBooks);
    return await save(_data);
  }

  // ================= 新建章节分卷选择记忆 =================

  /// 获取指定书籍上次新建章节时选择的分卷 UUID
  String getLastSelectedVolume(String bookUuid) {
    return _data.books[bookUuid]?.lastSelectedVolume ?? '';
  }

  /// 保存指定书籍新建章节时选择的分卷 UUID
  Future<bool> saveLastSelectedVolume(String bookUuid, String volumeUuid) async {
    final bookCache = _data.books[bookUuid] ?? const BookGroupExpandCache();
    final newBooks = Map<String, BookGroupExpandCache>.from(_data.books);
    newBooks[bookUuid] = bookCache.copyWith(lastSelectedVolume: volumeUuid);
    _data = _data.copyWith(books: newBooks);
    return await save(_data);
  }

  // ================= 新建设定分组选择记忆 =================

  /// 获取指定书籍上次新建设定时选择的分组 UUID
  String getLastSelectedSettingGroup(String bookUuid) {
    return _data.books[bookUuid]?.lastSelectedSettingGroup ?? '';
  }

  /// 保存指定书籍新建设定时选择的分组 UUID
  Future<bool> saveLastSelectedSettingGroup(String bookUuid, String groupUuid) async {
    final bookCache = _data.books[bookUuid] ?? const BookGroupExpandCache();
    final newBooks = Map<String, BookGroupExpandCache>.from(_data.books);
    newBooks[bookUuid] = bookCache.copyWith(lastSelectedSettingGroup: groupUuid);
    _data = _data.copyWith(books: newBooks);
    return await save(_data);
  }

  // ================= 章节排序状态 =================

  /// 获取章节列表是否倒序排列
  bool isChapterReversed() {
    return _data.isChapterReversed;
  }

  /// 保存章节列表排序方式
  Future<bool> saveChapterReversed(bool reversed) async {
    _data = _data.copyWith(isChapterReversed: reversed);
    return await save(_data);
  }

  // ================= 设定排序状态 =================

  /// 获取设定列表是否倒序排列
  bool isSettingReversed() {
    return _data.isSettingReversed;
  }

  /// 保存设定列表排序方式
  Future<bool> saveSettingReversed(bool reversed) async {
    _data = _data.copyWith(isSettingReversed: reversed);
    return await save(_data);
  }

  // ================= 统计设置状态 =================

  /// 获取统计界面是否包含粘贴字数
  bool isStatsIncludePasteWords() {
    return _data.statsIncludePasteWords;
  }

  /// 保存统计界面是否包含粘贴字数
  Future<bool> saveStatsIncludePasteWords(bool include) async {
    _data = _data.copyWith(statsIncludePasteWords: include);
    return await save(_data);
  }

  // ================= 工具面板显示设置 =================

  /// 获取工具面板区块显示顺序（仅包含可见区块）
  ///
  /// 列表按显示顺序存储开启显示的区块 ID，默认为 ['bookInfo', 'stats']
  List<String> getToolsSectionOrder() {
    return _data.toolsSectionOrder.toList();
  }

  /// 保存工具面板区块显示顺序
  Future<bool> saveToolsSectionOrder(List<String> order) async {
    _data = _data.copyWith(toolsSectionOrder: order);
    return await save(_data);
  }

  // ================= 通用方法 =================

  /// 移除指定书籍的所有缓存
  Future<bool> removeBook(String bookUuid) async {
    final newBooks = Map<String, BookGroupExpandCache>.from(_data.books);
    newBooks.remove(bookUuid);
    _data = _data.copyWith(books: newBooks);
    return await save(_data);
  }

  /// 清空所有缓存
  Future<bool> clearAll() async {
    _data = const MiscCacheData();
    return await save(_data);
  }
}
