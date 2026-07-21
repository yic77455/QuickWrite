import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/group.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/models/recycle_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/writing_stat.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/book_import_service.dart';
import 'package:quick_write/core/services/data_integrity_service.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

/// 书架状态管理 Provider
/// 
/// 管理书架中的书籍数据，负责以下处理：
/// - 加载数据库中的书籍和分组
/// - 提供书籍和分组的读取、修改、删除操作
/// - 批量操作（恢复、删除）
/// - 书籍的拖拽排序
class BookshelfProvider extends ChangeNotifier {
  late Isar _isar;
  List<BookModel> _allBooks = []; // 私有数据：书籍列表
  List<GroupModel> _allGroups = []; // 私有数据：分组列表
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  /// 暴露 Isar 实例（用于全文索引服务）
  Isar get isar => _isar;
  
  /// 数据完整性校验结果（启动时检测）
  IntegrityCheckResult? _integrityCheckResult;
  IntegrityCheckResult? get integrityCheckResult => _integrityCheckResult;

  /// 安全移动文件夹
  /// 
  /// 在 Windows 上，rename 可能因为权限问题失败，所以使用复制+删除的方式
  Future<void> _moveDirectorySafely(String sourcePath, String targetPath) async {
    final sourceDir = Directory(sourcePath);
    final targetDir = Directory(targetPath);
    
    if (!sourceDir.existsSync()) return;
    
    // 先尝试直接重命名（更快）
    try {
      await sourceDir.rename(targetPath);
      return;
    } catch (e) {
      // 如果失败，使用复制+删除的方式
    }
    
    // 创建目标目录
    await targetDir.create(recursive: true);
    
    // 递归复制所有文件和子目录
    await for (final entity in sourceDir.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: sourcePath);
      final newEntityPath = p.join(targetPath, relativePath);
      
      if (entity is File) {
        await File(entity.path).copy(newEntityPath);
      } else if (entity is Directory) {
        await Directory(newEntityPath).create(recursive: true);
      }
    }
    
    // 删除源目录
    await sourceDir.delete(recursive: true);
  }

  /// 供右侧网格使用的 Getter：按用户的拖拽顺序 (orderIndex) 排列
  List<BookModel> get books {
    // 每次获取时，确保返回的是按 orderIndex 升序排列的列表
    // (toList() 是为了防止外部直接修改原数组)
    return _allBooks.toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  /// 获取所有分组（按 orderIndex 排序）
  List<GroupModel> get groups {
    return _allGroups.toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  /// 供左侧大封面使用的 Getter：按修改时间 (updatedAt) 找出最新的一本
  BookModel? get recentBook {
    if (_allBooks.isEmpty) return null;

    // 使用 reduce 找出 updatedAt 最大的那本书 (距离现在最近的时间)
    return _allBooks.reduce((currentBook, nextBook) {
      return currentBook.updatedAt.isAfter(nextBook.updatedAt)
          ? currentBook
          : nextBook;
    });
  }

  // 构造函数中异步初始化数据库
  BookshelfProvider() {
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
      [BookModelSchema, GroupModelSchema, RecycleBinModelSchema, RecycleItemModelSchema, ChapterModelSchema, VolumeModelSchema, SettingGroupModelSchema, SettingItemModelSchema, WritingStatModelSchema],
      directory: AppPaths.instance.databaseDirectory,
      name: AppPaths.instance.databaseName,
      // 启动时自动压缩数据库（只要有空闲空间就压缩）
      compactOnLaunch: const CompactCondition(
        minBytes: 1, // 只要超过 1 字节就压缩
      ),
    );

    // 执行数据完整性校验
    _integrityCheckResult = await DataIntegrityService.instance.checkIntegrity(_isar);

    // 从数据库中拉取所有数据
    await _loadBooks();
    await _loadGroups();

    _isInitialized = true;
    notifyListeners();
  }

  /// 从 Isar 查出所有书籍
  Future<void> _loadBooks() async {
    // .where().findAll() 瞬间查出所有数据
    _allBooks = await _isar.bookModels.where().findAll();
  }

  /// 从 Isar 查出所有分组
  Future<void> _loadGroups() async {
    _allGroups = await _isar.groupModels.where().findAll();
  }

  /// 刷新书架数据
  /// 
  /// 重新从数据库加载所有书籍和分组数据
  Future<void> refresh() async {
    // 清除所有书籍封面缓存
    for (final book in _allBooks) {
      if (book.coverPath.isNotEmpty) {
        final coverFile = File(book.coverPath);
        if (coverFile.existsSync()) {
          FileImage(coverFile).evict();
        }
      }
    }
    
    await _loadBooks();
    await _loadGroups();
    notifyListeners();
  }

  /// 根据分组 ID 获取书籍列表
  /// 
  /// [groupId] 分组 UUID，空字符串表示"全部作品"
  List<BookModel> getBooksByGroup(String groupId) {
    if (groupId.isEmpty) {
      return books;
    }
    return _allBooks
        .where((book) => book.groupId == groupId)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  /// 根据分组 UUID 获取分组
  GroupModel? getGroupByUuid(String uuid) {
    try {
      return _allGroups.firstWhere((group) => group.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  /// 处理 UI 拖拽并持久化到数据库
  /// 
  /// [reorderedListFunction] 拖拽排序函数
  /// [groupId] 当前分组 ID，用于分组内排序。空字符串表示书架（未分组），null 表示全部作品
  Future<void> reorderBooks(
    ReorderedListFunction reorderedListFunction, {
    String? groupId,
  }) async {
    // 根据分组获取当前书籍列表
    List<BookModel> currentOrderedBooks;
    if (groupId == null) {
      // 全部作品
      currentOrderedBooks = books;
    } else if (groupId.isEmpty) {
      // 书架（未分组）
      currentOrderedBooks = _allBooks
          .where((book) => book.groupId.isEmpty)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    } else {
      // 指定分组
      currentOrderedBooks = _allBooks
          .where((book) => book.groupId == groupId)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }

    // 得到用户拖拽改变后的新数组
    List<BookModel> newOrderedBooks =
        reorderedListFunction(currentOrderedBooks) as List<BookModel>;

    // Isar 事务 (Transaction)：极速批量更新数据库
    // writeTxn 保证了这段代码要么全部成功，要么全部回滚，绝对安全
    await _isar.writeTxn(() async {
      for (int i = 0; i < newOrderedBooks.length; i++) {
        final book = newOrderedBooks[i];

        // 只有当新的序号和原来的序号不同时，才去改数据库，节省性能
        if (book.orderIndex != i) {
          book.orderIndex = i; // 直接修改对象的属性
          await _isar.bookModels.put(book); // put() 会根据 id 自动更新这一行数据
        }
      }
    });

    // 通知 UI 重绘
    notifyListeners();
  }

  /// 新建一本书
  /// 
  /// 返回值：
  /// - 0: 创建成功
  /// - 1: 书名已存在，创建失败
  Future<int> addBook({
    required String bookTitle,
    String coverPath = '',
    String synopsis = '',
  }) async {
    // 重名检测：书名不能重复
    final isDuplicate = _allBooks.any((book) => book.title == bookTitle);
    if (isDuplicate) {
      return 1;
    }

    final now = DateTime.now();
    final newUuid = const Uuid().v4(); // 生成 UUID

    // 先把所有现有书的 orderIndex +1，腾出第一个位置
    for (var book in _allBooks) {
      book.orderIndex++;
    }

    // 创建 BookModel 实例
    final newBook = BookModel()
      ..uuid = newUuid
      ..title = bookTitle
      ..coverPath = coverPath
      ..synopsis = synopsis
      ..wordCount = 0
      ..latestChapter = '暂无章节'
      ..createdAt = now
      ..updatedAt = now
      ..orderIndex = 0; // 新书放在网格的最前面

    // 存入 Isar 数据库（新书 + 更新后的旧书序号）
    await _isar.writeTxn(() async {
      await _isar.bookModels.put(newBook);
      if (_allBooks.isNotEmpty) {
        await _isar.bookModels.putAll(_allBooks);
      }
    });

    // 更新内存数据并通知 UI 重绘
    _allBooks.insert(0, newBook);
    notifyListeners();
    
    return 0;
  }

  /// 导入书籍
  /// 
  /// [importResult] 导入服务返回的结果
  /// 返回导入成功的书籍模型
  Future<BookModel?> importBook(ImportResult importResult) async {
    if (!importResult.success || importResult.chapters.isEmpty) {
      return null;
    }
    
    debugPrint('开始导入书籍: ${importResult.bookTitle}, 章节数: ${importResult.chapters.length}');
    
    final now = DateTime.now();
    final bookUuid = const Uuid().v4();
    
    // 先把所有现有书的 orderIndex +1，腾出第一个位置
    for (var book in _allBooks) {
      book.orderIndex++;
    }
    
    // 创建 BookModel 实例
    final newBook = BookModel()
      ..uuid = bookUuid
      ..title = importResult.bookTitle
      ..coverPath = ''
      ..synopsis = ''
      ..wordCount = importResult.totalWordCount
      ..latestChapter = importResult.chapters.last.title
      ..createdAt = now
      ..updatedAt = now
      ..orderIndex = 0;
    
    // 为所有章节设置 bookUuid
    for (final chapter in importResult.chapters) {
      chapter.bookUuid = bookUuid;
    }
    
    // 为所有分卷设置 bookUuid
    for (final volume in importResult.volumes) {
      volume.bookUuid = bookUuid;
    }
    
    debugPrint('开始写入数据库...');
    final stopwatch = Stopwatch()..start();
    
    // 存入数据库（只存元数据，不存内容）
    await _isar.writeTxn(() async {
      // 存入书籍
      await _isar.bookModels.put(newBook);
      debugPrint('书籍信息已存入，耗时: ${stopwatch.elapsedMilliseconds}ms');
      
      // 存入所有分卷
      if (importResult.volumes.isNotEmpty) {
        await _isar.volumeModels.putAll(importResult.volumes);
      }
      
      // 存入所有章节元数据
      await _isar.chapterModels.putAll(importResult.chapters);
      debugPrint('章节元数据已存入，耗时: ${stopwatch.elapsedMilliseconds}ms');
      
      // 更新其他书籍的序号
      if (_allBooks.isNotEmpty) {
        await _isar.bookModels.putAll(_allBooks);
      }
    });
    
    debugPrint('数据库写入完成，总耗时: ${stopwatch.elapsedMilliseconds}ms');
    
    // 更新内存数据
    _allBooks.insert(0, newBook);
    notifyListeners();
    
    return newBook;
  }

  /// 删除一本书（移入回收站）
  /// 
  /// 不再直接删除，而是将书籍移动到回收站
  Future<void> deleteBook(BookModel book) async {
    // 获取书籍文件夹路径
    final worksPath = await AppPaths.instance.getBooksPath();
    final bookFolderPath = '$worksPath${Platform.pathSeparator}${book.title}';
    
    // 生成回收站文件夹名称（使用 UUID）
    final recycleFolderName = const Uuid().v4();
    
    // 获取回收站路径
    final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
    final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}$recycleFolderName';
    
    // 移动文件夹到回收站（使用安全移动方法）
    final bookDirectory = Directory(bookFolderPath);
    if (bookDirectory.existsSync()) {
      await _moveDirectorySafely(bookFolderPath, recycleFolderPath);
    }
    
    // 创建回收站记录
    final recycleBinItem = RecycleBinModel.fromBookModel(book, recycleFolderName);
    
    // 从 Isar 数据库中删除书籍记录（保留章节，恢复时需要）
    await _isar.writeTxn(() async {
      // 删除书籍记录（章节保留，恢复时需要）
      await _isar.bookModels.delete(book.id);
      // 存入回收站记录
      await _isar.recycleBinModels.put(recycleBinItem);
    });

    // 更新内存数据并通知 UI 重绘
    _allBooks.removeWhere((b) => b.uuid == book.uuid);
    
    // 先按 orderIndex 排序，确保顺序正确后再重新整理序号
    _allBooks.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    
    // 因为删了一本书，后面书的 orderIndex 断层了，重新整理一下序号
    for (int i = 0; i < _allBooks.length; i++) {
      _allBooks[i].orderIndex = i;
    }
    // 把整理好的新序号存进数据库
    await _isar.writeTxn(() async {
      await _isar.bookModels.putAll(_allBooks);
    });

    notifyListeners();
  }

  /// 批量删除书籍（移入回收站）
  /// 
  /// [books] 要删除的书籍列表
  /// 相比循环调用 deleteBook，这个方法只执行一次数据库事务，避免唯一索引冲突
  Future<void> deleteBooks(List<BookModel> books) async {
    if (books.isEmpty) return;

    // 收集所有要删除的书籍 ID 和 UUID
    final idsToDelete = books.map((b) => b.id).toList();
    final uuidsToDelete = books.map((b) => b.uuid).toSet();

    // 获取路径
    final worksPath = await AppPaths.instance.getBooksPath();
    final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
    
    // 创建回收站记录列表
    final recycleBinItems = <RecycleBinModel>[];
    
    // 移动所有文件夹到回收站
    for (final book in books) {
      final bookFolderPath = '$worksPath${Platform.pathSeparator}${book.title}';
      final bookDirectory = Directory(bookFolderPath);
      
      if (bookDirectory.existsSync()) {
        // 生成回收站文件夹名称（使用 UUID）
        final recycleFolderName = const Uuid().v4();
        final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}$recycleFolderName';
        
        // 移动文件夹（使用安全移动方法）
        await _moveDirectorySafely(bookFolderPath, recycleFolderPath);
        
        // 创建回收站记录
        final recycleBinItem = RecycleBinModel.fromBookModel(book, recycleFolderName);
        recycleBinItems.add(recycleBinItem);
      }
    }

    // 在一个事务中删除所有书籍记录（保留章节，恢复时需要），并存入回收站
    await _isar.writeTxn(() async {
      // 删除书籍记录（章节保留，恢复时需要）
      await _isar.bookModels.deleteAll(idsToDelete);
      // 存入回收站记录
      await _isar.recycleBinModels.putAll(recycleBinItems);
    });

    // 更新内存数据
    _allBooks.removeWhere((b) => uuidsToDelete.contains(b.uuid));

    // 先按 orderIndex 排序，确保顺序正确后再重新整理序号
    _allBooks.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    // 重新整理序号
    for (int i = 0; i < _allBooks.length; i++) {
      _allBooks[i].orderIndex = i;
    }

    // 一次性更新所有剩余书籍的序号
    await _isar.writeTxn(() async {
      await _isar.bookModels.putAll(_allBooks);
    });

    notifyListeners();
  }

  /// 从回收站恢复书籍
  /// 
  /// [recycledBook] 回收站记录
  /// [newTitle] 新书名（如果有重名冲突）
  /// 返回恢复是否成功
  Future<bool> restoreFromRecycleBin(RecycleBinModel recycledBook, {String? newTitle}) async {
    try {
      // 获取路径
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final worksPath = await AppPaths.instance.getBooksPath();
      
      // 回收站中的文件夹路径
      final recycleFolderPath = '$recycleBinPath${Platform.pathSeparator}${recycledBook.recycleFolderName}';
      
      // 恢复后的文件夹名称（使用新标题或原标题）
      final restoredFolderName = newTitle ?? recycledBook.title;
      String finalFolderName = restoredFolderName;
      String finalFolderPath = '$worksPath${Platform.pathSeparator}$finalFolderName';
      
      // 检查目标路径是否已存在，如果存在则添加后缀
      int suffix = 1;
      while (Directory(finalFolderPath).existsSync()) {
        finalFolderName = '$restoredFolderName ($suffix)';
        finalFolderPath = '$worksPath${Platform.pathSeparator}$finalFolderName';
        suffix++;
      }
      
      // 移动文件夹（使用安全移动方法）
      final recycleDir = Directory(recycleFolderPath);
      if (recycleDir.existsSync()) {
        await _moveDirectorySafely(recycleFolderPath, finalFolderPath);
      }
      
      // 创建恢复后的 BookModel
      final restoredBook = recycledBook.toBookModel(
        newTitle: finalFolderName,
        newOrderIndex: 0, // 恢复到最前面
      );
      
      // 把现有所有书的 orderIndex +1，腾出第一个位置
      for (var book in _allBooks) {
        book.orderIndex++;
      }
      
      // 在一个事务中：删除回收站记录、存入书籍记录、更新其他书籍序号
      await _isar.writeTxn(() async {
        await _isar.recycleBinModels.delete(recycledBook.id);
        await _isar.bookModels.put(restoredBook);
        if (_allBooks.isNotEmpty) {
          await _isar.bookModels.putAll(_allBooks);
        }
      });
      
      // 更新内存数据
      _allBooks.insert(0, restoredBook);
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('恢复书籍失败: $e');
      return false;
    }
  }

  // ================= 分组管理方法 =================

  /// 新建分组
  /// 
  /// 返回值：
  /// - 0: 创建成功
  /// - 1: 分组名已存在
  Future<int> addGroup({required String name}) async {
    // 重名检测
    final isDuplicate = _allGroups.any((group) => group.name == name);
    if (isDuplicate) {
      return 1;
    }

    final newUuid = const Uuid().v4();
    final newGroup = GroupModel()
      ..uuid = newUuid
      ..name = name
      ..orderIndex = _allGroups.length
      ..createdAt = DateTime.now();

    await _isar.writeTxn(() async {
      await _isar.groupModels.put(newGroup);
    });

    _allGroups.add(newGroup);
    notifyListeners();
    return 0;
  }

  /// 重命名分组
  /// 
  /// 返回值：
  /// - 0: 成功
  /// - 1: 分组名已存在
  /// - 2: 分组不存在
  Future<int> renameGroup({required String groupUuid, required String newName}) async {
    // 重名检测（排除自己）
    final isDuplicate = _allGroups.any(
      (group) => group.name == newName && group.uuid != groupUuid,
    );
    if (isDuplicate) {
      return 1;
    }

    final group = getGroupByUuid(groupUuid);
    if (group == null) {
      return 2;
    }

    group.name = newName;
    await _isar.writeTxn(() async {
      await _isar.groupModels.put(group);
    });

    notifyListeners();
    return 0;
  }

  /// 删除分组
  /// 
  /// [groupUuid] 要删除的分组 UUID
  /// [moveBooksToUngrouped] 是否将分组内的书籍移到"未分组"
  Future<void> deleteGroup(String groupUuid, {bool moveBooksToUngrouped = true}) async {
    final group = getGroupByUuid(groupUuid);
    if (group == null) return;

    // 删除分组
    await _isar.writeTxn(() async {
      await _isar.groupModels.delete(group.id);
    });

    _allGroups.removeWhere((g) => g.uuid == groupUuid);

    // 处理分组内的书籍
    if (moveBooksToUngrouped) {
      // 将书籍移到"未分组"
      for (final book in _allBooks.where((b) => b.groupId == groupUuid)) {
        book.groupId = '';
      }
      await _isar.writeTxn(() async {
        for (final book in _allBooks.where((b) => b.groupId == '')) {
          await _isar.bookModels.put(book);
        }
      });
    }

    // 重新整理分组序号
    for (int i = 0; i < _allGroups.length; i++) {
      _allGroups[i].orderIndex = i;
    }
    await _isar.writeTxn(() async {
      await _isar.groupModels.putAll(_allGroups);
    });

    notifyListeners();
  }

  /// 将书籍移动到指定分组
  /// 
  /// [bookUuids] 要移动的书籍 UUID 列表
  /// [groupUuid] 目标分组 UUID，空字符串表示"未分组"
  Future<void> moveBooksToGroup(List<String> bookUuids, String groupUuid) async {
    for (final uuid in bookUuids) {
      final book = _allBooks.firstWhere((b) => b.uuid == uuid);
      book.groupId = groupUuid;
    }

    await _isar.writeTxn(() async {
      for (final uuid in bookUuids) {
        final book = _allBooks.firstWhere((b) => b.uuid == uuid);
        await _isar.bookModels.put(book);
      }
    });

    notifyListeners();
  }

  /// 更新书籍信息
  /// 
  /// [bookUuid] 书籍 UUID
  /// [title] 新书名
  /// [synopsis] 新简介
  /// [coverPath] 新封面路径
  Future<void> updateBookInfo({
    required String bookUuid,
    required String title,
    required String synopsis,
    required String coverPath,
  }) async {
    final book = _allBooks.firstWhere((b) => b.uuid == bookUuid);
    
    // 清除旧封面缓存
    if (book.coverPath.isNotEmpty) {
      final oldCoverFile = File(book.coverPath);
      if (oldCoverFile.existsSync()) {
        FileImage(oldCoverFile).evict();
      }
    }
    
    // 清除新封面缓存（如果路径不同）
    if (coverPath.isNotEmpty && coverPath != book.coverPath) {
      final newCoverFile = File(coverPath);
      if (newCoverFile.existsSync()) {
        FileImage(newCoverFile).evict();
      }
    }
    
    book.title = title;
    book.synopsis = synopsis;
    book.coverPath = coverPath;
    book.updatedAt = DateTime.now();

    await _isar.writeTxn(() async {
      await _isar.bookModels.put(book);
    });

    notifyListeners();
  }

  /// 重排分组顺序
  Future<void> reorderGroups(List<GroupModel> newOrderedGroups) async {
    for (int i = 0; i < newOrderedGroups.length; i++) {
      newOrderedGroups[i].orderIndex = i;
    }

    await _isar.writeTxn(() async {
      await _isar.groupModels.putAll(newOrderedGroups);
    });

    _allGroups = newOrderedGroups;
    notifyListeners();
  }
}
