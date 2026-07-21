import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/recycle_item.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 章节回收站服务
///
/// 单例模式，集中管理章节和设定项的回收站业务逻辑：
/// - 将章节/设定项移入回收站（工作台删除时调用）
/// - 从回收站恢复到原书籍
/// - 彻底删除回收项
/// - 批量操作和清空回收站
///
/// 同时被工作台窗口的 WorkspaceProvider 和主窗口的 RecycleBinProvider 使用，
/// 通过 Isar 实例访问同一个数据库
class RecycleItemService {
  // ================= 单例模式 =================
  static final RecycleItemService instance = RecycleItemService._internal();
  RecycleItemService._internal();

  /// Isar 数据库实例（由调用方初始化）
  Isar? _isar;

  /// 初始化服务，传入 Isar 实例
  void initialize(Isar isar) {
    _isar = isar;
  }

  /// 获取 Isar 实例，未初始化则抛出异常
  Isar get _db {
    final db = _isar;
    if (db == null) {
      throw StateError('RecycleItemService 未初始化');
    }
    return db;
  }

  // ================= 移入回收站 =================

  /// 将章节移入回收站
  ///
  /// [chapter] 要移入回收站的章节
  /// [bookTitle] 所属书籍标题
  /// [volumeName] 所属分卷名称（空字符串表示未分卷）
  /// [chapterFilePath] 章节文件的完整路径
  /// 返回是否成功移入回收站
  Future<bool> moveChapterToRecycleBin({
    required ChapterModel chapter,
    required String bookTitle,
    required String volumeName,
    required String chapterFilePath,
  }) async {
    try {
      // 生成回收站中的文件相对路径（items/{uuid}.txt）
      final recycleFileUuid = const Uuid().v4();
      final recycleFilePath = 'items${Platform.pathSeparator}$recycleFileUuid.txt';

      // 将章节文件移动到回收站
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}$recycleFilePath';

      // 确保回收站 items 子目录存在
      final itemsDir = Directory('$recycleBinPath${Platform.pathSeparator}items');
      if (!itemsDir.existsSync()) {
        await itemsDir.create(recursive: true);
      }

      // 移动文件到回收站
      final sourceFile = File(chapterFilePath);
      if (sourceFile.existsSync()) {
        await sourceFile.rename(recycleFileFullPath);
      }

      // 创建回收项记录
      final recycleItem = RecycleItemModel.fromChapter(
        chapter: chapter,
        bookTitle: bookTitle,
        containerName: volumeName,
        recycleFilePath: recycleFilePath,
      );

      // 存入数据库
      await _db.writeTxn(() async {
        await _db.recycleItemModels.put(recycleItem);
      });

      return true;
    } catch (e) {
      debugPrint('章节移入回收站失败: $e');
      return false;
    }
  }

  /// 将设定项移入回收站
  ///
  /// [item] 要移入回收站的设定项
  /// [bookTitle] 所属书籍标题
  /// [groupName] 所属分组名称（空字符串表示未分组）
  /// [itemFilePath] 设定项文件的完整路径
  /// 返回是否成功移入回收站
  Future<bool> moveSettingItemToRecycleBin({
    required SettingItemModel item,
    required String bookTitle,
    required String groupName,
    required String itemFilePath,
  }) async {
    try {
      // 生成回收站中的文件相对路径（items/{uuid}.txt）
      final recycleFileUuid = const Uuid().v4();
      final recycleFilePath = 'items${Platform.pathSeparator}$recycleFileUuid.txt';

      // 将设定项文件移动到回收站
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}$recycleFilePath';

      // 确保回收站 items 子目录存在
      final itemsDir = Directory('$recycleBinPath${Platform.pathSeparator}items');
      if (!itemsDir.existsSync()) {
        await itemsDir.create(recursive: true);
      }

      // 移动文件到回收站
      final sourceFile = File(itemFilePath);
      if (sourceFile.existsSync()) {
        await sourceFile.rename(recycleFileFullPath);
      }

      // 创建回收项记录
      final recycleItem = RecycleItemModel.fromSettingItem(
        item: item,
        bookTitle: bookTitle,
        containerName: groupName,
        recycleFilePath: recycleFilePath,
      );

      // 存入数据库
      await _db.writeTxn(() async {
        await _db.recycleItemModels.put(recycleItem);
      });

      return true;
    } catch (e) {
      debugPrint('设定项移入回收站失败: $e');
      return false;
    }
  }

  /// 批量将章节移入回收站
  ///
  /// [chapters] 要移入回收站的章节列表
  /// [bookTitle] 所属书籍标题
  /// [bookFolderPath] 书籍文件夹根路径（用于定位 chapters 子目录）
  /// [volumeNameOf] 根据 volumeUuid 返回分卷名的函数
  /// 返回成功移入回收站的数量
  Future<int> moveChaptersToRecycleBinBatch({
    required List<ChapterModel> chapters,
    required String bookTitle,
    required String bookFolderPath,
    required String Function(String volumeUuid) volumeNameOf,
  }) async {
    if (chapters.isEmpty) return 0;

    try {
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      // 确保 items 子目录存在（一次性创建）
      final itemsDir = Directory('$recycleBinPath${Platform.pathSeparator}items');
      if (!itemsDir.existsSync()) {
        await itemsDir.create(recursive: true);
      }

      final recycleItems = <RecycleItemModel>[];

      for (final chapter in chapters) {
        // 生成回收站中的文件相对路径（items/{uuid}.txt）
        final recycleFileUuid = const Uuid().v4();
        final recycleFilePath = 'items${Platform.pathSeparator}$recycleFileUuid.txt';
        final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}$recycleFilePath';

        // 移动章节文件到回收站
        final sourceFilePath =
            '$bookFolderPath${Platform.pathSeparator}chapters${Platform.pathSeparator}${chapter.filePath}';
        final sourceFile = File(sourceFilePath);
        if (sourceFile.existsSync()) {
          await sourceFile.rename(recycleFileFullPath);
        }

        // 创建回收项记录
        recycleItems.add(RecycleItemModel.fromChapter(
          chapter: chapter,
          bookTitle: bookTitle,
          containerName: volumeNameOf(chapter.volumeUuid),
          recycleFilePath: recycleFilePath,
        ));
      }

      // 单事务批量写入所有回收项记录
      await _db.writeTxn(() async {
        await _db.recycleItemModels.putAll(recycleItems);
      });

      return recycleItems.length;
    } catch (e) {
      debugPrint('批量章节移入回收站失败: $e');
      return 0;
    }
  }

  /// 批量将设定项移入回收站
  ///
  /// 相比循环调用 [moveSettingItemToRecycleBin]，本方法只开启一次数据库事务，
  /// 一次性写入所有回收项记录，显著减少事务开销
  ///
  /// [items] 要移入回收站的设定项列表
  /// [bookTitle] 所属书籍标题
  /// [bookFolderPath] 书籍文件夹根路径（用于定位 settings 子目录）
  /// [groupNameOf] 根据 groupUuid 返回分组名的函数
  /// 返回成功移入回收站的数量
  Future<int> moveSettingItemsToRecycleBinBatch({
    required List<SettingItemModel> items,
    required String bookTitle,
    required String bookFolderPath,
    required String Function(String groupUuid) groupNameOf,
  }) async {
    if (items.isEmpty) return 0;

    try {
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      // 确保 items 子目录存在（一次性创建）
      final itemsDir = Directory('$recycleBinPath${Platform.pathSeparator}items');
      if (!itemsDir.existsSync()) {
        await itemsDir.create(recursive: true);
      }

      final recycleItems = <RecycleItemModel>[];

      for (final item in items) {
        // 生成回收站中的文件相对路径（items/{uuid}.txt）
        final recycleFileUuid = const Uuid().v4();
        final recycleFilePath = 'items${Platform.pathSeparator}$recycleFileUuid.txt';
        final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}$recycleFilePath';

        // 移动设定项文件到回收站
        final sourceFilePath =
            '$bookFolderPath${Platform.pathSeparator}settings${Platform.pathSeparator}${item.filePath}';
        final sourceFile = File(sourceFilePath);
        if (sourceFile.existsSync()) {
          await sourceFile.rename(recycleFileFullPath);
        }

        // 创建回收项记录
        recycleItems.add(RecycleItemModel.fromSettingItem(
          item: item,
          bookTitle: bookTitle,
          containerName: groupNameOf(item.groupUuid),
          recycleFilePath: recycleFilePath,
        ));
      }

      // 单事务批量写入所有回收项记录
      await _db.writeTxn(() async {
        await _db.recycleItemModels.putAll(recycleItems);
      });

      return recycleItems.length;
    } catch (e) {
      debugPrint('批量设定项移入回收站失败: $e');
      return 0;
    }
  }

  // ================= 读取数据 =================

  /// 加载所有回收项（按删除时间降序）
  Future<List<RecycleItemModel>> loadAllItems() async {
    final items = await _db.recycleItemModels.where().findAll();
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  /// 根据 UUID 获取回收项
  RecycleItemModel? getItemByUuid(String uuid) {
    try {
      return _db.recycleItemModels.where().uuidEqualTo(uuid).findFirstSync();
    } catch (_) {
      return null;
    }
  }

  // ================= 恢复操作 =================

  /// 恢复章节到指定书籍
  ///
  /// [item] 回收项记录
  /// [bookFolderPath] 目标书籍文件夹路径
  /// [existingChapters] 书籍现有的章节列表（用于计算排序索引和检测重名）
  /// [existingVolumes] 书籍现有的分卷列表（用于检测原分卷是否存在并查找分卷名）
  /// 返回恢复后的 ChapterModel，失败返回 null
  ///
  /// 若原分卷已被删除，章节会被恢复到"未分卷"下
  Future<ChapterModel?> restoreChapter({
    required RecycleItemModel item,
    required String bookFolderPath,
    required List<ChapterModel> existingChapters,
    required List<VolumeModel> existingVolumes,
  }) async {
    try {
      // 从回收站读取文件内容
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}${item.recycleFilePath}';
      final recycleFile = File(recycleFileFullPath);
      if (!recycleFile.existsSync()) {
        debugPrint('回收站文件不存在: $recycleFileFullPath');
        return null;
      }

      // 检测重名，必要时添加后缀
      String finalTitle = item.title;
      int suffix = 1;
      while (existingChapters.any((c) => c.title == finalTitle)) {
        finalTitle = '${item.title} ($suffix)';
        suffix++;
      }

      // 检测原分卷是否还存在
      // 若分卷已被删除，恢复到"未分卷"下，避免出现指向不存在分卷的幽灵记录
      String targetVolumeUuid = '';
      String volumeName = '';
      if (item.containerUuid.isNotEmpty) {
        final volume = existingVolumes.where((v) => v.uuid == item.containerUuid).firstOrNull;
        if (volume != null) {
          targetVolumeUuid = volume.uuid;
          volumeName = volume.name;
        }
      }

      // 计算新的排序索引
      // 恢复到目标分卷末尾（或未分卷末尾）
      final sameContainerChapters = existingChapters
          .where((c) => c.volumeUuid == targetVolumeUuid)
          .toList();
      final newVolumeOrderIndex = sameContainerChapters.length;
      final newOrderIndex = existingChapters.length;

      // 生成新的文件相对路径
      final String sanitizedTitle = _sanitizeFileName(finalTitle);
      final String sanitizedVolume = _sanitizeFileName(volumeName);
      final String newRelativePath = volumeName.isNotEmpty
          ? '$sanitizedVolume${Platform.pathSeparator}$sanitizedTitle.txt'
          : '$sanitizedTitle.txt';

      // 确保目标目录存在
      final String targetDirPath = volumeName.isNotEmpty
          ? '$bookFolderPath${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume'
          : '$bookFolderPath${Platform.pathSeparator}chapters';
      final targetDir = Directory(targetDirPath);
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }

      // 移动文件到原位置
      final targetFilePath = '$bookFolderPath${Platform.pathSeparator}chapters${Platform.pathSeparator}$newRelativePath';
      await recycleFile.rename(targetFilePath);

      // 创建恢复后的 ChapterModel
      final restoredChapter = item.toChapterModel(
        filePath: newRelativePath,
        orderIndex: newOrderIndex,
        volumeOrderIndex: newVolumeOrderIndex,
      )
        ..title = finalTitle
        ..volumeUuid = targetVolumeUuid;

      // 写入数据库：删除回收项记录，存入章节记录
      await _db.writeTxn(() async {
        await _db.recycleItemModels.delete(item.id);
        await _db.chapterModels.put(restoredChapter);
      });

      return restoredChapter;
    } catch (e) {
      debugPrint('恢复章节失败: $e');
      return null;
    }
  }

  /// 恢复设定项到指定书籍
  ///
  /// [item] 回收项记录
  /// [bookFolderPath] 目标书籍文件夹路径
  /// [existingItems] 书籍现有的设定项列表（用于计算排序索引和检测重名）
  /// [existingGroups] 书籍现有的分组列表（用于检测原分组是否存在并查找分组名）
  /// 返回恢复后的 SettingItemModel，失败返回 null
  ///
  /// 若原分组已被删除，设定项会被恢复到"未分组"下
  Future<SettingItemModel?> restoreSettingItem({
    required RecycleItemModel item,
    required String bookFolderPath,
    required List<SettingItemModel> existingItems,
    required List<SettingGroupModel> existingGroups,
  }) async {
    try {
      // 从回收站读取文件内容
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}${item.recycleFilePath}';
      final recycleFile = File(recycleFileFullPath);
      if (!recycleFile.existsSync()) {
        debugPrint('回收站文件不存在: $recycleFileFullPath');
        return null;
      }

      // 检测重名，必要时添加后缀
      String finalTitle = item.title;
      int suffix = 1;
      while (existingItems.any((i) => i.title == finalTitle)) {
        finalTitle = '${item.title} ($suffix)';
        suffix++;
      }

      // 检测原分组是否还存在
      // 若分组已被删除，恢复到"未分组"下，避免出现指向不存在分组的幽灵记录
      String targetGroupUuid = '';
      String groupName = '';
      if (item.containerUuid.isNotEmpty) {
        final group = existingGroups.where((g) => g.uuid == item.containerUuid).firstOrNull;
        if (group != null) {
          targetGroupUuid = group.uuid;
          groupName = group.name;
        }
      }

      // 计算新的排序索引
      // 恢复到目标分组末尾（或未分组末尾）
      final sameContainerItems = existingItems
          .where((i) => i.groupUuid == targetGroupUuid)
          .toList();
      final newGroupOrderIndex = sameContainerItems.length;
      final newOrderIndex = existingItems.length;

      // 生成新的文件相对路径
      final String sanitizedTitle = _sanitizeFileName(finalTitle);
      final String sanitizedGroup = _sanitizeFileName(groupName);
      final String newRelativePath = groupName.isNotEmpty
          ? '$sanitizedGroup${Platform.pathSeparator}$sanitizedTitle.txt'
          : '$sanitizedTitle.txt';

      // 确保目标目录存在
      final String targetDirPath = groupName.isNotEmpty
          ? '$bookFolderPath${Platform.pathSeparator}settings${Platform.pathSeparator}$sanitizedGroup'
          : '$bookFolderPath${Platform.pathSeparator}settings';
      final targetDir = Directory(targetDirPath);
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }

      // 移动文件到原位置
      final targetFilePath = '$bookFolderPath${Platform.pathSeparator}settings${Platform.pathSeparator}$newRelativePath';
      await recycleFile.rename(targetFilePath);

      // 创建恢复后的 SettingItemModel
      final restoredItem = item.toSettingItemModel(
        filePath: newRelativePath,
        orderIndex: newOrderIndex,
        groupOrderIndex: newGroupOrderIndex,
      )
        ..title = finalTitle
        ..groupUuid = targetGroupUuid;

      // 写入数据库：删除回收项记录，存入设定项记录
      await _db.writeTxn(() async {
        await _db.recycleItemModels.delete(item.id);
        await _db.settingItemModels.put(restoredItem);
      });

      return restoredItem;
    } catch (e) {
      debugPrint('恢复设定项失败: $e');
      return null;
    }
  }

  // ================= 彻底删除 =================

  /// 彻底删除单个回收项
  ///
  /// [item] 要彻底删除的回收项
  Future<void> deleteItemPermanently(RecycleItemModel item) async {
    try {
      // 删除回收站中的文件
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}${item.recycleFilePath}';
      final file = File(recycleFileFullPath);
      if (file.existsSync()) {
        await file.delete();
      }

      // 删除数据库记录
      await _db.writeTxn(() async {
        await _db.recycleItemModels.delete(item.id);
      });
    } catch (e) {
      debugPrint('彻底删除回收项失败: $e');
    }
  }

  /// 批量彻底删除回收项
  ///
  /// [items] 要彻底删除的回收项列表
  Future<void> deleteItemsPermanentlyBatch(List<RecycleItemModel> items) async {
    if (items.isEmpty) return;

    try {
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final idsToDelete = items.map((i) => i.id).toList();

      // 删除所有文件
      for (final item in items) {
        final recycleFileFullPath = '$recycleBinPath${Platform.pathSeparator}${item.recycleFilePath}';
        final file = File(recycleFileFullPath);
        if (file.existsSync()) {
          await file.delete();
        }
      }

      // 批量删除数据库记录
      await _db.writeTxn(() async {
        await _db.recycleItemModels.deleteAll(idsToDelete);
      });
    } catch (e) {
      debugPrint('批量彻底删除回收项失败: $e');
    }
  }

  // ================= 清空回收站 =================

  /// 清空所有回收项
  Future<void> emptyItems() async {
    try {
      final recycleBinPath = await AppPaths.instance.getRecycleBinPath();
      final itemsDir = Directory('$recycleBinPath${Platform.pathSeparator}items');

      // 删除整个 items 目录
      if (itemsDir.existsSync()) {
        await itemsDir.delete(recursive: true);
      }

      // 清空数据库记录
      await _db.writeTxn(() async {
        await _db.recycleItemModels.clear();
      });
    } catch (e) {
      debugPrint('清空回收项失败: $e');
    }
  }

  // ================= 辅助方法 =================

  /// 文件名安全化处理
  ///
  /// 移除文件名中不允许的字符，避免文件创建失败
  String _sanitizeFileName(String fileName) {
    // 替换 Windows 文件系统不允许的字符
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }
}
