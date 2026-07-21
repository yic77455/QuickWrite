import 'dart:io';
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/models/recycle_item.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/writing_stat.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/cache_services/chapter_cursor_cache_service.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/services/recycle_item_service.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

/// 回收站状态管理 Provider
///
/// 管理回收站中的书籍和章节/设定项数据
/// - 移入回收站（从书架删除时调用）
/// - 恢复书籍到书架
/// - 彻底删除书籍
/// - 批量操作（恢复、删除）
/// - 清空回收站
class RecycleBinProvider extends ChangeNotifier {
  Isar? _isar; // 可空类型，避免 late 初始化错误
  List<RecycleBinModel> _allRecycledBooks = []; // 回收站中的书籍列表
  List<RecycleItemModel> _allRecycledItems = []; // 回收站中的章节/设定项列表
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 获取 Isar 实例，如果未初始化则抛出异常
  Isar get _db {
    final db = _isar;
    if (db == null) {
      throw StateError('RecycleBinProvider 未初始化，请先调用 refresh()');
    }
    return db;
  }

  /// 获取回收站中的所有书籍（按删除时间降序排列）
  List<RecycleBinModel> get recycledBooks {
    return _allRecycledBooks.toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  }

  /// 获取回收站中的书籍数量
  int get recycledBooksCount => _allRecycledBooks.length;

  /// 书籍回收站是否为空
  bool get isBooksEmpty => _allRecycledBooks.isEmpty;

  /// 获取回收站中的所有章节/设定项（按删除时间降序排列）
  List<RecycleItemModel> get recycledItems {
    return _allRecycledItems.toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  }

  /// 获取回收站中的章节/设定项数量
  int get recycledItemsCount => _allRecycledItems.length;

  /// 章节回收站是否为空
  bool get isItemsEmpty => _allRecycledItems.isEmpty;

  /// 回收站是否整体为空（书籍和章节都为空）
  bool get isEmpty => isBooksEmpty && isItemsEmpty;

  // 构造函数中异步初始化数据库
  RecycleBinProvider() {
    _initDatabase();
  }

  /// 初始化 Isar 并加载数据
  Future<void> _initDatabase() async {
    // 确保 AppPaths 已初始化
    if (!AppPaths.instance.isInitialized) {
      await AppPaths.instance.initialize();
    }

    // 尝试获取已存在的 Isar 实例，避免重复打开数据库
    _isar = Isar.getInstance(AppPaths.instance.databaseName) ?? await Isar.open(
      [BookModelSchema, RecycleBinModelSchema, RecycleItemModelSchema, ChapterModelSchema, VolumeModelSchema, SettingGroupModelSchema, SettingItemModelSchema, WritingStatModelSchema],
      directory: AppPaths.instance.databaseDirectory,
      name: AppPaths.instance.databaseName,
    );

    // 初始化章节回收站服务
    RecycleItemService.instance.initialize(_isar!);

    // 从数据库中拉取所有回收站数据
    await _loadRecycledBooks();
    await _loadRecycledItems();

    _isInitialized = true;
    notifyListeners();
  }

  /// 从 Isar 查出所有回收站书籍
  Future<void> _loadRecycledBooks() async {
    _allRecycledBooks = await _db.recycleBinModels.where().findAll();
  }

  /// 从 Isar 查出所有回收项（章节/设定项）
  Future<void> _loadRecycledItems() async {
    _allRecycledItems = await _db.recycleItemModels.where().findAll();
  }

  /// 刷新回收站数据（同时刷新书籍和章节回收站）
  Future<void> refresh() async {
    // 如果数据库还没初始化完成，等待初始化
    if (!_isInitialized) {
      await _initDatabase();
      return;
    }
    await _loadRecycledBooks();
    await _loadRecycledItems();
    notifyListeners();
  }

  /// 仅刷新章节回收站数据
  Future<void> refreshItems() async {
    if (!_isInitialized) {
      await _initDatabase();
      return;
    }
    await _loadRecycledItems();
    notifyListeners();
  }

  /// 将书籍移入回收站
  /// 
  /// [book] 要移入回收站的书籍
  /// [bookFolderPath] 书籍文件夹路径
  /// 返回是否成功
  Future<bool> moveToRecycleBin(BookModel book, String bookFolderPath) async {
    try {
      // 生成回收站文件夹名称（使用 UUID）
      final recycleFolderName = const Uuid().v4();
      
      // 获取回收站路径
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}$recycleFolderName';
      
      // 移动文件夹到回收站
      final bookDirectory = Directory(bookFolderPath);
      if (bookDirectory.existsSync()) {
        await bookDirectory.rename(recycleFolderPath);
      }
      
      // 创建回收站记录
      final recycleBinItem = RecycleBinModel.fromBookModel(book, recycleFolderName);
      
      // 存入数据库
      await _db.writeTxn(() async {
        await _db.recycleBinModels.put(recycleBinItem);
      });
      
      // 更新内存数据
      _allRecycledBooks.add(recycleBinItem);
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('移入回收站失败: $e');
      return false;
    }
  }

  /// 恢复书籍到书架
  /// 
  /// [recycledBook] 要恢复的回收站记录
  /// [newTitle] 新书名（如果有重名冲突）
  /// 返回恢复后的 BookModel，失败返回 null
  Future<BookModel?> restoreBook(RecycleBinModel recycledBook, {String? newTitle}) async {
    try {
      // 获取路径
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final worksPath = await AppPaths.instance.getBooksPath();
      
      // 回收站中的文件夹路径
      final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}${recycledBook.recycleFolderName}';
      
      // 恢复后的文件夹名称（使用新标题或原标题）
      final restoredFolderName = newTitle ?? recycledBook.title;
      final restoredFolderPath = '$worksPath${Platform.pathSeparator}$restoredFolderName';
      
      // 检查目标路径是否已存在
      if (Directory(restoredFolderPath).existsSync()) {
        // 如果存在，添加后缀
        int suffix = 1;
        String finalPath = restoredFolderPath;
        while (Directory(finalPath).existsSync()) {
          finalPath = '$restoredFolderPath ($suffix)';
          suffix++;
        }
        // 移动文件夹
        final recycleDir = Directory(recycleFolderPath);
        if (recycleDir.existsSync()) {
          await recycleDir.rename(finalPath);
        }
        // 更新书名
        newTitle = '$restoredFolderName (${suffix - 1})';
      } else {
        // 直接移动
        final recycleDir = Directory(recycleFolderPath);
        if (recycleDir.existsSync()) {
          await recycleDir.rename(restoredFolderPath);
        }
      }
      
      // 创建恢复后的 BookModel
      final restoredBook = recycledBook.toBookModel(
        newTitle: newTitle,
        newOrderIndex: 0, // 恢复到最前面
      );
      
      // 从回收站数据库中删除记录
      await _db.writeTxn(() async {
        await _db.recycleBinModels.delete(recycledBook.id);
      });
      
      // 更新内存数据
      _allRecycledBooks.removeWhere((b) => b.uuid == recycledBook.uuid);
      notifyListeners();
      
      return restoredBook;
    } catch (e) {
      debugPrint('恢复书籍失败: $e');
      return null;
    }
  }

  /// 彻底删除回收站中的书籍
  /// 
  /// [recycledBook] 要彻底删除的回收站记录
  Future<void> deletePermanently(RecycleBinModel recycledBook) async {
    try {
      // 获取回收站路径
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}${recycledBook.recycleFolderName}';
      
      // 删除文件夹
      final recycleDir = Directory(recycleFolderPath);
      if (recycleDir.existsSync()) {
        await recycleDir.delete(recursive: true);
      }
      
      // 从数据库中删除记录和章节
      await _db.writeTxn(() async {
        // 删除该书籍的所有章节
        await _db.chapterModels.where().bookUuidEqualTo(recycledBook.bookUuid).deleteAll();
        // 删除该书籍的所有分卷
        await _db.volumeModels.where().bookUuidEqualTo(recycledBook.bookUuid).deleteAll();
        // 删除回收站记录
        await _db.recycleBinModels.delete(recycledBook.id);
      });

      // 清理缓存数据
      await _clearBookCache(recycledBook.bookUuid);

      // 删除该书籍的全部备份记录
      await BackupService.instance.deleteBookBackups(recycledBook.bookUuid);
      
      // 更新内存数据
      _allRecycledBooks.removeWhere((b) => b.uuid == recycledBook.uuid);
      notifyListeners();
    } catch (e) {
      debugPrint('彻底删除失败: $e');
    }
  }

  /// 批量彻底删除
  /// 
  /// [recycledBooks] 要删除的回收站记录列表
  Future<void> deletePermanentlyBatch(List<RecycleBinModel> recycledBooks) async {
    if (recycledBooks.isEmpty) return;

    try {
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final idsToDelete = recycledBooks.map((b) => b.id).toList();
      // 使用 bookUuid 删除章节，不是 uuid！
      final bookUuidsToDelete = recycledBooks.map((b) => b.bookUuid).toSet();

      // 删除所有文件夹
      for (final book in recycledBooks) {
        final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}${book.recycleFolderName}';
        final recycleDir = Directory(recycleFolderPath);
        if (recycleDir.existsSync()) {
          await recycleDir.delete(recursive: true);
        }
      }

      // 批量删除数据库记录
      await _db.writeTxn(() async {
        // 删除所有书籍的章节
        for (final bookUuid in bookUuidsToDelete) {
          await _db.chapterModels.where().bookUuidEqualTo(bookUuid).deleteAll();
          // 删除所有书籍的分卷
          await _db.volumeModels.where().bookUuidEqualTo(bookUuid).deleteAll();
        }
        // 删除回收站记录
        await _db.recycleBinModels.deleteAll(idsToDelete);
      });

      // 清理缓存数据
      for (final bookUuid in bookUuidsToDelete) {
        await _clearBookCache(bookUuid);
      }

      // 删除所有书籍的备份记录
      for (final book in recycledBooks) {
        await BackupService.instance.deleteBookBackups(book.bookUuid);
      }

      // 更新内存数据
      _allRecycledBooks.removeWhere((b) => bookUuidsToDelete.contains(b.bookUuid));
      notifyListeners();
    } catch (e) {
      debugPrint('批量删除失败: $e');
    }
  }

  /// 批量恢复
  /// 
  /// [recycledBooks] 要恢复的回收站记录列表
  /// 返回恢复成功的 BookModel 列表
  Future<List<BookModel>> restoreBatch(List<RecycleBinModel> recycledBooks) async {
    final restoredBooks = <BookModel>[];
    
    for (final book in recycledBooks) {
      final restored = await restoreBook(book);
      if (restored != null) {
        restoredBooks.add(restored);
      }
    }
    
    return restoredBooks;
  }

  /// 清空回收站
  Future<void> emptyRecycleBin() async {
    if (_allRecycledBooks.isEmpty) return;

    try {
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      
      // 收集所有 bookUuid（用于删除章节）
      final bookUuidsToDelete = _allRecycledBooks.map((b) => b.bookUuid).toList();
      
      // 删除所有文件夹
      for (final book in _allRecycledBooks) {
        final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}${book.recycleFolderName}';
        final recycleDir = Directory(recycleFolderPath);
        if (recycleDir.existsSync()) {
          await recycleDir.delete(recursive: true);
        }
      }

      // 清空数据库
      await _db.writeTxn(() async {
        // 删除所有书籍的章节
        for (final bookUuid in bookUuidsToDelete) {
          await _db.chapterModels.where().bookUuidEqualTo(bookUuid).deleteAll();
          // 删除所有书籍的分卷
          await _db.volumeModels.where().bookUuidEqualTo(bookUuid).deleteAll();
        }
        // 清空回收站记录
        await _db.recycleBinModels.clear();
      });

      // 清理缓存数据
      for (final bookUuid in bookUuidsToDelete) {
        await _clearBookCache(bookUuid);
      }

      // 删除所有书籍的备份记录
      for (final book in _allRecycledBooks) {
        await BackupService.instance.deleteBookBackups(book.bookUuid);
      }

      // 清空内存数据
      _allRecycledBooks.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('清空回收站失败: $e');
    }
  }

  /// 检查书架中是否存在同名书籍
  /// 
  /// [title] 书名
  /// [bookshelfBooks] 书架中的书籍列表（由调用方传入）
  bool hasDuplicateTitle(String title, List<BookModel> bookshelfBooks) {
    return bookshelfBooks.any((book) => book.title == title);
  }

  /// 根据 UUID 获取回收站记录
  RecycleBinModel? getRecycledBookByUuid(String uuid) {
    try {
      return _allRecycledBooks.firstWhere((book) => book.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  /// 根据 bookUuid 获取回收站记录
  RecycleBinModel? getRecycledBookByBookUuid(String bookUuid) {
    try {
      return _allRecycledBooks.firstWhere((book) => book.bookUuid == bookUuid);
    } catch (_) {
      return null;
    }
  }

  /// 清理指定书籍的所有缓存数据
  Future<void> _clearBookCache(String bookUuid) async {
    await MiscCacheService.instance.removeBook(bookUuid);
    await ChapterCursorCacheService.instance.removeBook(bookUuid);
  }

  // ================= 章节回收站操作 =================

  /// 根据 UUID 获取回收项
  RecycleItemModel? getRecycledItemByUuid(String uuid) {
    try {
      return _allRecycledItems.firstWhere((item) => item.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  /// 检查指定书籍是否还在书架上（用于判断章节是否可恢复）
  ///
  /// [bookUuid] 书籍 UUID
  /// [existingBooks] 当前书架上的书籍列表（由调用方传入）
  bool isBookOnShelf(String bookUuid, List<BookModel> existingBooks) {
    return existingBooks.any((book) => book.uuid == bookUuid);
  }

  /// 查询指定书籍的所有章节（用于恢复时计算排序索引和检测重名）
  Future<List<ChapterModel>> getBookChapters(String bookUuid) async {
    return await _db.chapterModels.where().bookUuidEqualTo(bookUuid).findAll();
  }

  /// 查询指定书籍的所有分卷（用于恢复时查找分卷名称）
  Future<List<VolumeModel>> getBookVolumes(String bookUuid) async {
    final volumes = await _db.volumeModels.where().bookUuidEqualTo(bookUuid).findAll();
    volumes.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return volumes;
  }

  /// 查询指定书籍的所有设定项（用于恢复时计算排序索引和检测重名）
  Future<List<SettingItemModel>> getBookSettingItems(String bookUuid) async {
    return await _db.settingItemModels.where().bookUuidEqualTo(bookUuid).findAll();
  }

  /// 查询指定书籍的所有设定分组（用于恢复时查找分组名称）
  Future<List<SettingGroupModel>> getBookSettingGroups(String bookUuid) async {
    final groups = await _db.settingGroupModels.where().bookUuidEqualTo(bookUuid).findAll();
    groups.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return groups;
  }

  /// 恢复章节到原书籍
  ///
  /// [item] 回收项记录
  /// [book] 目标书籍
  /// [existingChapters] 书籍现有章节列表
  /// [volumes] 书籍现有分卷列表（用于检测原分卷是否存在）
  /// 返回恢复后的 ChapterModel，失败返回 null
  Future<ChapterModel?> restoreChapterFromRecycle({
    required RecycleItemModel item,
    required BookModel book,
    required List<ChapterModel> existingChapters,
    required List<VolumeModel> volumes,
  }) async {
    // 计算书籍文件夹路径
    final worksPath = await AppPaths.instance.getBooksPath();
    final bookFolderPath = '$worksPath${Platform.pathSeparator}${book.title}';

    final restoredChapter = await RecycleItemService.instance.restoreChapter(
      item: item,
      bookFolderPath: bookFolderPath,
      existingChapters: existingChapters,
      existingVolumes: volumes,
    );

    if (restoredChapter != null) {
      // 更新内存数据
      _allRecycledItems.removeWhere((i) => i.uuid == item.uuid);
      notifyListeners();
    }

    return restoredChapter;
  }

  /// 恢复设定项到原书籍
  ///
  /// [item] 回收项记录
  /// [book] 目标书籍
  /// [existingItems] 书籍现有设定项列表
  /// [groups] 书籍现有分组列表（用于检测原分组是否存在）
  /// 返回恢复后的 SettingItemModel，失败返回 null
  Future<SettingItemModel?> restoreSettingItemFromRecycle({
    required RecycleItemModel item,
    required BookModel book,
    required List<SettingItemModel> existingItems,
    required List<SettingGroupModel> groups,
  }) async {
    // 计算书籍文件夹路径
    final worksPath = await AppPaths.instance.getBooksPath();
    final bookFolderPath = '$worksPath${Platform.pathSeparator}${book.title}';

    final restoredItem = await RecycleItemService.instance.restoreSettingItem(
      item: item,
      bookFolderPath: bookFolderPath,
      existingItems: existingItems,
      existingGroups: groups,
    );

    if (restoredItem != null) {
      // 更新内存数据
      _allRecycledItems.removeWhere((i) => i.uuid == item.uuid);
      notifyListeners();
    }

    return restoredItem;
  }

  /// 彻底删除单个回收项
  ///
  /// [item] 要彻底删除的回收项
  Future<void> deleteItemPermanently(RecycleItemModel item) async {
    await RecycleItemService.instance.deleteItemPermanently(item);
    _allRecycledItems.removeWhere((i) => i.uuid == item.uuid);
    notifyListeners();
  }

  /// 批量彻底删除回收项
  ///
  /// [items] 要彻底删除的回收项列表
  Future<void> deleteItemsPermanentlyBatch(List<RecycleItemModel> items) async {
    await RecycleItemService.instance.deleteItemsPermanentlyBatch(items);
    final uuidsToDelete = items.map((i) => i.uuid).toSet();
    _allRecycledItems.removeWhere((i) => uuidsToDelete.contains(i.uuid));
    notifyListeners();
  }

  /// 清空章节回收站
  Future<void> emptyItemsRecycleBin() async {
    if (_allRecycledItems.isEmpty) return;
    await RecycleItemService.instance.emptyItems();
    _allRecycledItems.clear();
    notifyListeners();
  }
}
